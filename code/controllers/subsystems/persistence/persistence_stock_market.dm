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

/// Cache of a ckey's stock holdings, loaded in bulk at boot -- ckey -> list of
/// list("company_id"=, "shares_owned"=, "avg_cost_basis"=), mirrors
/// persistence_faction_members_cache's shape (persistence_factions.dm).
GLOBAL_LIST_EMPTY(persistence_stock_holdings_cache)

/// Finds ckey's holding entry for company_id in the cache, or null.
/proc/stock_market_get_holding(ckey, company_id)
	var/list/held = GLOB.persistence_stock_holdings_cache[ckey]
	if(!held)
		return null
	for(var/list/h in held)
		if(h["company_id"] == company_id)
			return h
	return null

/// Sum of shares_owned across every ckey holding company_id -- the "player-
/// held" slice of the float, shown against total_shares_outstanding so the
/// UI can make clear how small a slice any one (or all) player(s) actually
/// hold of the simulated total market.
/proc/stock_market_total_player_shares(company_id)
	var/total = 0
	for(var/ckey in GLOB.persistence_stock_holdings_cache)
		var/list/held = GLOB.persistence_stock_holdings_cache[ckey]
		for(var/list/h in held)
			if(h["company_id"] == company_id)
				total += h["shares_owned"]
	return total

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
					"INSERT INTO ss13_stock_companies (ticker, name, current_price, previous_price, base_price, total_shares_outstanding, volatility) VALUES (:ticker, :name, :price, :price, :price, :shares, :volatility)",
					list("ticker" = seed["ticker"], "name" = seed["name"], "price" = seed["price"], "shares" = seed["shares"], "volatility" = seed["volatility"])
				)
				iq.Execute()
				databaseCheckQueryResult(iq, "stockMarketInitialize seed [seed["ticker"]]")
				qdel(iq)
			log_subsystem_persistence_info("Stock market: seeded [length(GLOB.stock_market_seed_companies)] placeholder companies.")
	qdel(cq)

	var/list/loaded_companies = list()
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT company_id, ticker, name, current_price, previous_price, base_price, total_shares_outstanding, volatility FROM ss13_stock_companies", list())
	q.Execute()
	if(databaseCheckQueryResult(q, "stockMarketInitialize companies"))
		while(q.NextRow())
			var/datum/stock_company/C = new()
			C.company_id = text2num(q.item[1])
			C.ticker = q.item[2]
			C.name = q.item[3]
			C.current_price = text2num(q.item[4])
			C.previous_price = text2num(q.item[5])
			C.base_price = text2num(q.item[6])
			C.total_shares_outstanding = text2num(q.item[7])
			C.volatility = text2num(q.item[8])
			loaded_companies["[C.company_id]"] = C
		SSstock_market.companies = loaded_companies // only replace on confirmed success
	else
		message_admins("Stock market companies load query failed -- stock market may be running on stale/empty data. Check DB schema (db_update?).")
	qdel(q)

	var/list/loaded_holdings = list()
	var/datum/db_query/hq = SSdbcore.NewQuery(
		"SELECT ckey, company_id, shares_owned, avg_cost_basis FROM ss13_stock_holdings WHERE shares_owned > 0", list())
	hq.Execute()
	if(databaseCheckQueryResult(hq, "stockMarketInitialize holdings"))
		while(hq.NextRow())
			var/hckey = hq.item[1]
			LAZYADD(loaded_holdings[hckey], list(list(
				"company_id" = text2num(hq.item[2]),
				"shares_owned" = text2num(hq.item[3]),
				"avg_cost_basis" = text2num(hq.item[4])
			)))
		GLOB.persistence_stock_holdings_cache = loaded_holdings // only replace on confirmed success
	else
		message_admins("Stock market holdings load query failed -- holdings may be running on stale/empty data. Check DB schema (db_update?).")
	qdel(hq)

	log_subsystem_persistence_info("Stock market: loaded [length(SSstock_market.companies)] companies, holdings for [length(GLOB.persistence_stock_holdings_cache)] ckey(s).")

/// Upserts every company's current price -- called from SSstock_market's own
/// fire() (not SSpersistence.fire()) so price ticks stay decoupled from the
/// heavier 30-minute autosave I/O. Also appends + prunes price history.
/datum/controller/subsystem/persistence/proc/stockMarketSaveCompanies()
	if(!databaseCheckConnection("stockMarketSaveCompanies"))
		return
	for(var/cid in SSstock_market.companies)
		var/datum/stock_company/C = SSstock_market.companies[cid]
		var/datum/db_query/q = SSdbcore.NewQuery(
			"UPDATE ss13_stock_companies SET current_price = :price, previous_price = :prev WHERE company_id = :id",
			list("price" = C.current_price, "prev" = C.previous_price, "id" = C.company_id)
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

/// Upserts one player's holding in one company -- called immediately after
/// every buy/sell (stock_market.dm program), same "persist the instant it
/// changes" discipline as money_account/adjust_money() (economy.dm).
/datum/controller/subsystem/persistence/proc/stockMarketSaveHolding(ckey, company_id, shares_owned, avg_cost_basis)
	if(!databaseCheckConnection("stockMarketSaveHolding"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_stock_holdings (ckey, company_id, shares_owned, avg_cost_basis)
		VALUES (:ckey, :cid, :shares, :basis)
		ON DUPLICATE KEY UPDATE shares_owned = VALUES(shares_owned), avg_cost_basis = VALUES(avg_cost_basis)"},
		list("ckey" = ckey, "cid" = company_id, "shares" = shares_owned, "basis" = avg_cost_basis)
	)
	q.Execute()
	databaseCheckQueryResult(q, "stockMarketSaveHolding")
	qdel(q)
