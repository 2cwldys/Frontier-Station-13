/*
 * Persistence - Stock Market
 * Loads/seeds companies and player holdings at boot, saves company prices
 * periodically (driven by SSstock_market's own tick, not SSpersistence's
 * heavier 30-minute autosave), and saves a holding immediately on every
 * buy/sell so a trade is never lost between saves -- mirrors adjust_money()'s
 * (economy.dm) immediate-persist-on-change pattern.
 */

/// Placeholder company seed data -- name/ticker are flavor text only, easy to
/// rename later. NOTE: editing this list only affects a FRESH database (an
/// empty ss13_stock_companies table); it does not rename companies that
/// already have rows -- do that with a manual UPDATE, or wipe the table to
/// reseed.
GLOBAL_LIST_INIT(stock_market_seed_companies, list(
	list("ticker" = "ZNTH", "name" = "Zenith Dynamics",        "price" = 120, "volatility" = 1.0, "shares" = 2000000),
	list("ticker" = "ORBF", "name" = "Orbital Foundries",      "price" = 80,  "volatility" = 1.8, "shares" = 800000),
	list("ticker" = "VSPR", "name" = "Vesper Biotech",         "price" = 150, "volatility" = 2.3, "shares" = 500000),
	list("ticker" = "HLCY", "name" = "Halcyon Robotics",       "price" = 200, "volatility" = 1.5, "shares" = 3000000),
	list("ticker" = "PRAX", "name" = "Praxis Logistics",       "price" = 60,  "volatility" = 0.7, "shares" = 1500000),
	list("ticker" = "MRDN", "name" = "Meridian Energy",        "price" = 175, "volatility" = 1.2, "shares" = 2500000),
	list("ticker" = "SLCE", "name" = "Solace Pharmaceuticals", "price" = 90,  "volatility" = 2.0, "shares" = 400000),
	list("ticker" = "TNTL", "name" = "Tantalus Mining",        "price" = 55,  "volatility" = 1.8, "shares" = 600000),
	list("ticker" = "AURL", "name" = "Aurelia Shipwrights",    "price" = 130, "volatility" = 0.8, "shares" = 1200000),
	list("ticker" = "NGHT", "name" = "Nightfall Munitions",    "price" = 70,  "volatility" = 2.5, "shares" = 300000),
))

/// Cache of a character's stock holdings, loaded in bulk at boot -- keyed by
/// the composite "[ckey]|[char_name]" string (same convention as
/// GLOB.persistence_economy_cache/card.dm and persistence_faction_members_cache)
/// -> list of list("company_id"=, "shares_owned"=, "avg_cost_basis"=), so a
/// second character on the same ckey gets an isolated portfolio.
GLOBAL_LIST_EMPTY(persistence_stock_holdings_cache)

/// Finds ckey+char_name's holding entry for company_id in the cache, or null.
/proc/stock_market_get_holding(ckey, char_name, company_id)
	var/list/held = GLOB.persistence_stock_holdings_cache["[ckey]|[char_name]"]
	if(!held)
		return null
	for(var/list/h in held)
		if(h["company_id"] == company_id)
			return h
	return null

/// Sum of shares_owned across every character holding company_id -- the
/// "player-held" slice of the float, shown against total_shares_outstanding
/// so the UI can make clear how small a slice any one (or all) player(s)
/// actually hold of the simulated total market.
/proc/stock_market_total_player_shares(company_id)
	var/total = 0
	for(var/key in GLOB.persistence_stock_holdings_cache)
		var/list/held = GLOB.persistence_stock_holdings_cache[key]
		for(var/list/h in held)
			if(h["company_id"] == company_id)
				total += h["shares_owned"]
	return total

/// This faction's own stock listing, or null if it isn't listed -- shared
/// lookup for faction_manage.dm's "List on Stock Exchange" (refuse if
/// already listed) and "Pay Dividends" (refuse if not) actions.
/proc/get_faction_stock_company(faction_uid)
	if(!faction_uid)
		return null
	for(var/cid in SSstock_market.companies)
		var/datum/stock_company/C = SSstock_market.companies[cid]
		if(C.faction_uid == faction_uid)
			return C
	return null

/// Loads all companies into SSstock_market.companies, seeding the table from
/// GLOB.stock_market_seed_companies on a first boot (empty table). Also
/// bulk-loads every player's holdings into GLOB.persistence_stock_holdings_cache.
/// Called from SSpersistence.Initialize().
/datum/controller/subsystem/persistence/proc/stockMarketInitialize()
	if(!databaseCheckConnection("stockMarketInitialize"))
		return

	var/datum/db_query/cq = SSdbcore.NewQuery("SELECT COUNT(*) FROM ss13_stock_companies", list())
	cq.Execute()
	if(databaseCheckQueryResult(cq, "stockMarketInitialize count") && cq.NextRow())
		if(text2num(cq.item[1]) == 0)
			for(var/list/seed in GLOB.stock_market_seed_companies)
				var/datum/db_query/iq = SSdbcore.NewQuery(
					"INSERT INTO ss13_stock_companies (ticker, name, current_price, previous_price, price_high, price_low, base_price, total_shares_outstanding, volatility) VALUES (:ticker, :name, :price, :price, :price, :price, :price, :shares, :volatility)",
					list("ticker" = seed["ticker"], "name" = seed["name"], "price" = seed["price"], "shares" = seed["shares"], "volatility" = seed["volatility"])
				)
				iq.Execute()
				databaseCheckQueryResult(iq, "stockMarketInitialize seed [seed["ticker"]]")
				qdel(iq)
			log_subsystem_persistence_info("Stock market: seeded [length(GLOB.stock_market_seed_companies)] placeholder companies.")
	qdel(cq)

	var/list/loaded_companies = list()
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT company_id, ticker, name, current_price, previous_price, price_high, price_low, base_price, total_shares_outstanding, volatility, faction_uid FROM ss13_stock_companies", list())
	q.Execute()
	if(databaseCheckQueryResult(q, "stockMarketInitialize companies"))
		while(q.NextRow())
			var/datum/stock_company/C = new()
			C.company_id = text2num(q.item[1])
			C.ticker = q.item[2]
			C.name = q.item[3]
			C.current_price = text2num(q.item[4])
			C.previous_price = text2num(q.item[5])
			C.price_high = text2num(q.item[6])
			C.price_low = text2num(q.item[7])
			C.base_price = text2num(q.item[8])
			C.total_shares_outstanding = text2num(q.item[9])
			C.volatility = text2num(q.item[10])
			C.faction_uid = q.item[11] || null
			loaded_companies["[C.company_id]"] = C
		SSstock_market.companies = loaded_companies // only replace on confirmed success
	else
		message_admins("Stock market companies load query failed -- stock market may be running on stale/empty data. Check DB schema (db_update?).")
	qdel(q)

	var/list/loaded_holdings = list()
	var/datum/db_query/hq = SSdbcore.NewQuery(
		"SELECT ckey, char_name, company_id, shares_owned, avg_cost_basis FROM ss13_stock_holdings WHERE shares_owned > 0", list())
	hq.Execute()
	if(databaseCheckQueryResult(hq, "stockMarketInitialize holdings"))
		while(hq.NextRow())
			var/hkey = "[hq.item[1]]|[hq.item[2]]"
			LAZYADD(loaded_holdings[hkey], list(list(
				"company_id" = text2num(hq.item[3]),
				"shares_owned" = text2num(hq.item[4]),
				"avg_cost_basis" = text2num(hq.item[5])
			)))
		GLOB.persistence_stock_holdings_cache = loaded_holdings // only replace on confirmed success
	else
		message_admins("Stock market holdings load query failed -- holdings may be running on stale/empty data. Check DB schema (db_update?).")
	qdel(hq)

	log_subsystem_persistence_info("Stock market: loaded [length(SSstock_market.companies)] companies, holdings for [length(GLOB.persistence_stock_holdings_cache)] character(s).")

/// Lists a faction's own stock on the exchange -- creates its
/// ss13_stock_companies row (faction_uid set, so SSstock_market/fire() never
/// applies the AI random walk to it -- see stock_market.dm) and adds it to
/// the live subsystem list immediately. Refuses if the faction already has a
/// listing (uq_faction_listing backs this up at the DB level too, so a race
/// can't double-list). Starting price is derived from the faction's current
/// treasury so it opens at a sane valuation instead of a flat default.
/// Called from the Faction Management program's officer-gated "List on Stock
/// Exchange" action -- returns null on success, or a user-facing reason.
/datum/controller/subsystem/persistence/proc/stockMarketListFaction(faction_uid, mob/user)
	faction_uid = normalize_faction_uid(faction_uid)
	if(!faction_uid)
		return "No faction context."
	if(!databaseCheckConnection("stockMarketListFaction"))
		return "Database connection failed."
	for(var/cid in SSstock_market.companies)
		var/datum/stock_company/existing = SSstock_market.companies[cid]
		if(existing.faction_uid == faction_uid)
			return "[get_faction_name(faction_uid)] is already listed on the exchange."

	var/balance = get_faction_account_balance(faction_uid) || 0
	var/shares = STOCK_MARKET_FACTION_DEFAULT_SHARES
	var/starting_price = max(1, round(balance / shares))
	var/ticker = uppertext(copytext(faction_uid, 1, 5))
	var/company_name = "[get_faction_name(faction_uid)] Holdings"

	var/datum/db_query/iq = SSdbcore.NewQuery(
		{"INSERT INTO ss13_stock_companies
		(faction_uid, ticker, name, current_price, previous_price, price_high, price_low, base_price, total_shares_outstanding, volatility)
		VALUES (:fid, :ticker, :name, :price, :price, :price, :price, :price, :shares, 0)"},
		list("fid" = faction_uid, "ticker" = ticker, "name" = company_name, "price" = starting_price, "shares" = shares)
	)
	iq.Execute()
	if(!databaseCheckQueryResult(iq, "stockMarketListFaction insert"))
		qdel(iq)
		return "Database insert failed."
	var/new_id = text2num(iq.last_insert_id)
	qdel(iq)

	var/datum/stock_company/C = new()
	C.company_id = new_id
	C.faction_uid = faction_uid
	C.ticker = ticker
	C.name = company_name
	C.current_price = starting_price
	C.previous_price = starting_price
	C.price_high = starting_price
	C.price_low = starting_price
	C.base_price = starting_price
	C.total_shares_outstanding = shares
	C.volatility = 0
	SSstock_market.companies["[C.company_id]"] = C

	log_and_message_admins("[key_name(user)] listed faction '[faction_uid]' on the Idris stock exchange as [ticker] (starting price [starting_price] cr).", user)
	return null

/// Force-liquidates every current holder of a faction-listed company at its
/// current price (personal account credited, faction treasury debited the
/// same total, holding zeroed and logged), then deletes the listing outright
/// -- the only way a faction company ever comes off the exchange once
/// listed (see faction_manage.dm -- there is no faction-side unlist). Called
/// either from the admin verb's "Revoke Faction Business Status" (user set)
/// or automatically by sync_price_to_treasury() when the faction's balance
/// hits zero (user null -- "even if offline," this runs from the ordinary
/// SSstock_market tick regardless of anyone viewing the market). Returns
/// null on success, or a user-facing reason (admin path only -- the
/// automatic path has nowhere to show a refusal, so it never refuses).
/datum/controller/subsystem/persistence/proc/stockMarketRevokeFaction(company_id, mob/user)
	var/datum/stock_company/C = SSstock_market.companies["[company_id]"]
	if(!C || !C.faction_uid)
		return "That isn't a faction-listed company."
	if(!databaseCheckConnection("stockMarketRevokeFaction"))
		return "Database connection failed."

	var/datum/db_query/hq = SSdbcore.NewQuery(
		"SELECT ckey, char_name, shares_owned FROM ss13_stock_holdings WHERE company_id = :id AND shares_owned > 0",
		list("id" = company_id)
	)
	hq.Execute()
	var/list/holders = list()
	if(databaseCheckQueryResult(hq, "stockMarketRevokeFaction holders"))
		while(hq.NextRow())
			holders += list(list("ckey" = hq.item[1], "char_name" = hq.item[2], "shares" = text2num(hq.item[3])))
	qdel(hq)

	var/total_payout = 0
	for(var/list/h in holders)
		var/payout = h["shares"] * C.current_price
		total_payout += payout
		var/datum/money_account/acc = SSeconomy.get_account_by_ckey_and_name(h["ckey"], h["char_name"])
		if(acc)
			acc.adjust_money(payout)
		SSpersistence.stockMarketSaveHolding(h["ckey"], h["char_name"], company_id, 0, 0)
		SSpersistence.stockMarketLogTrade(h["ckey"], h["char_name"], company_id, FALSE, h["shares"], C.current_price)
		var/list/cache_held = GLOB.persistence_stock_holdings_cache["[h["ckey"]]|[h["char_name"]]"]
		if(cache_held)
			for(var/list/ch in cache_held)
				if(ch["company_id"] == company_id)
					ch["shares_owned"] = 0
					ch["avg_cost_basis"] = 0

	if(total_payout > 0)
		// Clamped to whatever's actually left -- current_price is a rounded
		// per-share figure, so summing it across many holders can overshoot
		// the real balance by a few credits at the extreme low end (exactly
		// where this fires most often, the treasury already near zero).
		// faction_debit() itself refuses outright on an over-draw, which
		// would otherwise leave players paid but the treasury never
		// actually debited.
		var/actual_balance = get_faction_account_balance(C.faction_uid) || 0
		faction_debit(C.faction_uid, min(total_payout, actual_balance), "Stock exchange delisting buyout ([C.ticker])")

	var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_stock_holdings WHERE company_id = :id", list("id" = company_id))
	dq.Execute()
	databaseCheckQueryResult(dq, "stockMarketRevokeFaction delete holdings")
	qdel(dq)
	var/datum/db_query/cq = SSdbcore.NewQuery("DELETE FROM ss13_stock_companies WHERE company_id = :id", list("id" = company_id))
	cq.Execute()
	databaseCheckQueryResult(cq, "stockMarketRevokeFaction delete company")
	qdel(cq)

	SSstock_market.companies -= "[company_id]"
	// log_and_message_admins() itself prefixes "EVENT" instead of a key_name
	// when user is null (the automatic insolvency path) -- no need to build
	// that distinction into the message text too.
	log_and_message_admins("revoked faction stock exchange listing '[C.ticker]' ([get_faction_name(C.faction_uid)])[user ? "" : " -- faction treasury ran out of funds"] -- [length(holders)] holder(s) bought out for a total of [total_payout] cr from the faction treasury.", user)

	// Bankruptcy specifically (not an admin's own choice to revoke for some
	// other reason) costs the faction everything -- power down every beacon
	// it holds (releasing the Z claim and un-networking everything that was
	// tagged to it), then dissolve the faction outright. Gated on !user, the
	// same "automatic insolvency path" marker the log line above already
	// relies on -- a manual admin revoke leaves the faction itself intact.
	if(!user)
		var/bankrupt_faction_uid = C.faction_uid
		_power_down_faction_beacons_on_bankruptcy(bankrupt_faction_uid)
		SSpersistence.removeFactionCompletely(bankrupt_faction_uid, null)
	return null

/// Upserts every company's current price -- called from SSstock_market's own
/// fire() (not SSpersistence.fire()) so price ticks stay decoupled from the
/// heavier 30-minute autosave I/O. Also appends + prunes price history.
/datum/controller/subsystem/persistence/proc/stockMarketSaveCompanies()
	if(!databaseCheckConnection("stockMarketSaveCompanies"))
		return
	for(var/cid in SSstock_market.companies)
		var/datum/stock_company/C = SSstock_market.companies[cid]
		var/datum/db_query/q = SSdbcore.NewQuery(
			"UPDATE ss13_stock_companies SET current_price = :price, previous_price = :prev, price_high = :high, price_low = :low WHERE company_id = :id",
			list("price" = C.current_price, "prev" = C.previous_price, "high" = C.price_high, "low" = C.price_low, "id" = C.company_id)
		)
		q.Execute()
		databaseCheckQueryResult(q, "stockMarketSaveCompanies update [C.ticker]")
		qdel(q)

		var/datum/db_query/hq = SSdbcore.NewQuery(
			"INSERT INTO ss13_stock_price_history (company_id, price) VALUES (:id, :price)",
			list("id" = C.company_id, "price" = C.current_price)
		)
		hq.Execute()
		databaseCheckQueryResult(hq, "stockMarketSaveCompanies history [C.ticker]")
		qdel(hq)

		// Keep only the most recent ~200 history rows per company.
		var/datum/db_query/pq = SSdbcore.NewQuery(
			{"DELETE FROM ss13_stock_price_history WHERE company_id = :id AND id NOT IN
			(SELECT id FROM (SELECT id FROM ss13_stock_price_history WHERE company_id = :id ORDER BY recorded_at DESC LIMIT 200) AS keep)"},
			list("id" = C.company_id)
		)
		pq.Execute()
		databaseCheckQueryResult(pq, "stockMarketSaveCompanies prune [C.ticker]")
		qdel(pq)

/// Upserts one character's holding in one company -- called immediately
/// after every buy/sell (stock_market.dm program), same "persist the instant
/// it changes" discipline as money_account/adjust_money() (economy.dm).
/datum/controller/subsystem/persistence/proc/stockMarketSaveHolding(ckey, char_name, company_id, shares_owned, avg_cost_basis)
	if(!databaseCheckConnection("stockMarketSaveHolding"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_stock_holdings (ckey, char_name, company_id, shares_owned, avg_cost_basis)
		VALUES (:ckey, :char_name, :cid, :shares, :basis)
		ON DUPLICATE KEY UPDATE shares_owned = VALUES(shares_owned), avg_cost_basis = VALUES(avg_cost_basis)"},
		list("ckey" = ckey, "char_name" = char_name, "cid" = company_id, "shares" = shares_owned, "basis" = avg_cost_basis)
	)
	q.Execute()
	databaseCheckQueryResult(q, "stockMarketSaveHolding")
	qdel(q)

/// Appends one row to the per-character trade history log -- called
/// immediately after every buy/sell alongside stockMarketSaveHolding(), so
/// "the price you bought at" is a real historical record, not just the
/// running avg_cost_basis.
/datum/controller/subsystem/persistence/proc/stockMarketLogTrade(ckey, char_name, company_id, is_buy, shares, price_per_share)
	if(!databaseCheckConnection("stockMarketLogTrade"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_stock_trade_log (ckey, char_name, company_id, is_buy, shares, price_per_share, total) VALUES (:ckey, :char_name, :cid, :buy, :shares, :price, :total)",
		list("ckey" = ckey, "char_name" = char_name, "cid" = company_id, "buy" = is_buy ? 1 : 0, "shares" = shares, "price" = price_per_share, "total" = shares * price_per_share)
	)
	q.Execute()
	databaseCheckQueryResult(q, "stockMarketLogTrade")
	qdel(q)

/// Returns ckey+char_name's most recent trades (newest first, capped) as a
/// list of list("ticker"=, "name"=, "is_buy"=, "shares"=, "price_per_share"=,
/// "total"=, "traded_at"="") -- queried live rather than bulk-cached at boot
/// (unlike holdings), since this is naturally on-demand, player-specific
/// display data for the Portfolio tab, not something the price-tick engine
/// needs in memory.
/datum/controller/subsystem/persistence/proc/stockMarketGetTradeHistory(ckey, char_name, limit = 50)
	. = list()
	if(!databaseCheckConnection("stockMarketGetTradeHistory"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"SELECT c.ticker, c.name, t.is_buy, t.shares, t.price_per_share, t.total, t.traded_at
		FROM ss13_stock_trade_log t
		LEFT JOIN ss13_stock_companies c ON c.company_id = t.company_id
		WHERE t.ckey = :ckey AND t.char_name = :char_name ORDER BY t.traded_at DESC LIMIT :lim"},
		list("ckey" = ckey, "char_name" = char_name, "lim" = limit)
	)
	q.Execute()
	if(databaseCheckQueryResult(q, "stockMarketGetTradeHistory"))
		while(q.NextRow())
			. += list(list(
				"ticker" = q.item[1] || "???",
				"name" = q.item[2] || "Delisted Company",
				"is_buy" = text2num(q.item[3]),
				"shares" = text2num(q.item[4]),
				"price_per_share" = text2num(q.item[5]),
				"total" = text2num(q.item[6]),
				"traded_at" = q.item[7]
			))
	qdel(q)

/// Admin tool to manually set/nudge a company's price -- e.g. to script a
/// deliberate crash or rally for an event. Automatic ticking (tick_price(),
/// stock_market.dm) is untouched by this: it just keeps random-walking from
/// whatever current_price is, so a manual edit here becomes the new
/// baseline the simulation continues from, same as any other tick.
/datum/admins/proc/manage_stock_market()
	set name = "Manage Stock Market"
	set category = "Persistence"
	if(!check_rights(R_ADMIN))
		return
	if(!length(SSstock_market.companies))
		to_chat(usr, SPAN_WARNING("No companies loaded yet."))
		return

	var/list/options = list()
	for(var/cid in SSstock_market.companies)
		var/datum/stock_company/C = SSstock_market.companies[cid]
		options["[C.ticker] -- [C.name] ([C.current_price] cr)[C.faction_uid ? " (faction: [get_faction_name(C.faction_uid)])" : ""]"] = C

	var/chosen_label = tgui_input_list(usr, "Select a company:", "Manage Stock Market", options)
	if(!chosen_label)
		return
	var/datum/stock_company/C = options[chosen_label]

	var/list/actions = list("Set Price", "Adjust by Amount", "Adjust by Percent")
	if(C.faction_uid)
		actions += "Revoke Faction Business Status"
	var/action = tgui_input_list(usr, "Action:", "Manage Stock Market", actions)
	if(!action)
		return

	if(action == "Revoke Faction Business Status")
		var/confirm = tgui_alert(usr, "Revoke '[C.ticker]'s stock exchange listing? Every current holder is bought out at [C.current_price] cr/share from [get_faction_name(C.faction_uid)]'s treasury, and the listing is permanently removed. This cannot be undone.", "Revoke Faction Business Status", list("Revoke", "Cancel"))
		if(confirm != "Revoke")
			return
		var/reason = SSpersistence.stockMarketRevokeFaction(C.company_id, usr)
		if(reason)
			to_chat(usr, SPAN_WARNING(reason))
		else
			to_chat(usr, SPAN_GOOD("'[C.ticker]' delisted."))
		return

	var/old_price = C.current_price
	switch(action)
		if("Set Price")
			var/new_price = tgui_input_number(usr, "New price (credits):", "Manage Stock Market", C.current_price, 1000000, 1)
			if(isnull(new_price))
				return
			C.current_price = max(1, new_price)
		if("Adjust by Amount")
			var/delta = tgui_input_number(usr, "Adjust by (credits, negative to reduce):", "Manage Stock Market", 0, 1000000, -1000000)
			if(isnull(delta))
				return
			C.current_price = max(1, C.current_price + delta)
		if("Adjust by Percent")
			var/pct = tgui_input_number(usr, "Adjust by percent (negative to reduce):", "Manage Stock Market", 0, 100, -100)
			if(isnull(pct))
				return
			C.current_price = max(1, round(C.current_price * (1 + pct / 100)))

	C.price_high = max(C.price_high, C.current_price)
	C.price_low = min(C.price_low, C.current_price)
	SSpersistence.stockMarketSaveCompanies()
	log_and_message_admins("set [C.ticker] price from [old_price] to [C.current_price] cr via Manage Stock Market.", usr)
	to_chat(usr, SPAN_GOOD("[C.ticker] price: [old_price] -> [C.current_price] cr."))
