/*
 * Idris Market Terminal
 * Self-service stock trading against the player's personal Idris (money_
 * account) balance -- see code/controllers/subsystems/stock_market.dm for
 * the fluctuating-price engine and persistence_stock_market.dm for the
 * SQL-backed companies/holdings. Gated on already having a personal account:
 * accounts are only ever minted at the ID console (card.dm) -- this program
 * must never mint one itself, or the gate is meaningless.
 */
/datum/computer_file/program/stock_market
	filename = "stockmarket"
	filedesc = "Idris Market Terminal"
	program_icon_state = "generic"
	program_key_icon_state = "green_key"
	extended_desc = "Trade shares on the Idris market exchange."
	usage_flags = PROGRAM_ALL_REGULAR
	requires_ntnet = TRUE
	size = 4
	tgui_id = "StockMarket"
	ui_auto_update = TRUE

/datum/computer_file/program/stock_market/ui_data(mob/user)
	var/list/data = initial_data()

	var/datum/money_account/personal_account = SSeconomy.get_account_by_ckey_and_name(user.ckey, user.real_name)
	if(!personal_account)
		data["no_account"] = TRUE
		return data

	data["personal_balance"] = personal_account.money
	data["companies"] = list()
	var/total_market_cap = 0
	var/personal_portfolio_value = 0
	for(var/cid in SSstock_market.companies)
		var/datum/stock_company/C = SSstock_market.companies[cid]
		var/list/holding = stock_market_get_holding(user.ckey, user.real_name, C.company_id)
		var/market_cap = C.current_price * C.total_shares_outstanding
		total_market_cap += market_cap
		var/owned = holding ? holding["shares_owned"] : 0
		personal_portfolio_value += owned * C.current_price
		data["companies"] += list(list(
			"company_id" = C.company_id,
			"ticker" = C.ticker,
			"name" = C.name,
			"faction_uid" = C.faction_uid,
			"faction_name" = C.faction_uid ? get_faction_name(C.faction_uid) : null,
			"current_price" = C.current_price,
			"previous_price" = C.previous_price,
			"price_high" = C.price_high,
			"price_low" = C.price_low,
			"change_pct" = C.previous_price ? round((C.current_price - C.previous_price) / C.previous_price * 100, 0.1) : 0,
			"market_cap" = market_cap,
			"total_shares_outstanding" = C.total_shares_outstanding,
			"player_shares" = stock_market_total_player_shares(C.company_id),
			"shares_owned" = owned,
			"avg_cost_basis" = holding ? holding["avg_cost_basis"] : 0
		))
	data["total_market_cap"] = total_market_cap
	data["personal_portfolio_value"] = personal_portfolio_value
	data["trade_history"] = SSpersistence.stockMarketGetTradeHistory(user.ckey, user.real_name)
	return data

/datum/computer_file/program/stock_market/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/user = usr

	var/datum/money_account/personal_account = SSeconomy.get_account_by_ckey_and_name(user.ckey, user.real_name)
	if(!personal_account)
		to_chat(user, SPAN_WARNING("You need a personal Idris account first -- print a replacement ID at any ID console."))
		return TRUE

	var/company_id = text2num(params["company_id"])
	var/amount = text2num(params["amount"])
	var/datum/stock_company/C = company_id ? SSstock_market.companies["[company_id]"] : null

	switch(action)
		if("buy")
			if(!C || !amount || amount <= 0)
				return TRUE
			var/cost = C.current_price * amount
			if(personal_account.money < cost)
				to_chat(user, SPAN_WARNING("Insufficient funds -- that would cost [cost] credits."))
				return TRUE
			personal_account.adjust_money(-cost)
			var/list/holding = stock_market_get_holding(user.ckey, user.real_name, company_id)
			if(!holding)
				holding = list("company_id" = company_id, "shares_owned" = 0, "avg_cost_basis" = 0)
				LAZYADD(GLOB.persistence_stock_holdings_cache["[user.ckey]|[user.real_name]"], list(holding))
			var/total_shares = holding["shares_owned"] + amount
			holding["avg_cost_basis"] = round((holding["avg_cost_basis"] * holding["shares_owned"] + cost) / total_shares)
			holding["shares_owned"] = total_shares
			SSpersistence.stockMarketSaveHolding(user.ckey, user.real_name, company_id, holding["shares_owned"], holding["avg_cost_basis"])
			SSpersistence.stockMarketLogTrade(user.ckey, user.real_name, company_id, TRUE, amount, C.current_price)
			if(C.faction_uid)
				// Real investment -- the purchase becomes faction treasury
				// income, and price is re-synced immediately (instead of
				// waiting up to 5s for the next tick) so it's felt right away.
				faction_credit(C.faction_uid, cost, "Stock investment by [key_name(user)] ([amount]sh [C.ticker])")
				C.sync_price_to_treasury()
			else
				C.apply_trade_impact(amount, TRUE)
			to_chat(user, SPAN_GOOD("Bought [amount] share(s) of [C.ticker] for [cost] credits."))
			return TRUE

		if("sell")
			if(!C || !amount || amount <= 0)
				return TRUE
			var/list/holding = stock_market_get_holding(user.ckey, user.real_name, company_id)
			if(!holding || holding["shares_owned"] < amount)
				to_chat(user, SPAN_WARNING("You don't own that many shares."))
				return TRUE
			var/proceeds = C.current_price * amount
			if(C.faction_uid && (get_faction_account_balance(C.faction_uid) || 0) < proceeds)
				to_chat(user, SPAN_WARNING("[get_faction_name(C.faction_uid)]'s treasury can't cover a buyout that size right now -- try a smaller amount."))
				return TRUE
			personal_account.adjust_money(proceeds)
			holding["shares_owned"] -= amount
			if(holding["shares_owned"] <= 0)
				holding["avg_cost_basis"] = 0
			SSpersistence.stockMarketSaveHolding(user.ckey, user.real_name, company_id, holding["shares_owned"], holding["avg_cost_basis"])
			SSpersistence.stockMarketLogTrade(user.ckey, user.real_name, company_id, FALSE, amount, C.current_price)
			if(C.faction_uid)
				// A holder can only ever pull out what their own shares are
				// worth (proceeds, guarded above) -- never more than that,
				// so this can't be used to drain the faction beyond a fair
				// buyout of the shares actually being sold.
				faction_debit(C.faction_uid, proceeds, "Stock divestment by [key_name(user)] ([amount]sh [C.ticker])")
				C.sync_price_to_treasury()
			else
				C.apply_trade_impact(amount, FALSE)
			to_chat(user, SPAN_GOOD("Sold [amount] share(s) of [C.ticker] for [proceeds] credits."))
			return TRUE

		if("give")
			if(!C || !amount || amount <= 0)
				return TRUE
			// Server-side prompt sequence, matching Add Crew's own two-
			// tgui_input_text flow (drydock.dm) -- the frontend just triggers
			// the action, no target picker of its own needed.
			var/target_ckey_raw = tgui_input_text(user, "Ckey to give [amount] share(s) of [C.ticker] to:", "Give Shares", "", max_length = 32)
			if(!target_ckey_raw) return TRUE
			var/target_ckey = ckey(target_ckey_raw)
			if(!target_ckey) return TRUE
			var/target_char_name = tgui_input_text(user, "Exact character name for '[target_ckey]':", "Give Shares", "", max_length = 64)
			if(!target_char_name) return TRUE
			if(target_ckey == user.ckey && target_char_name == user.real_name)
				to_chat(user, SPAN_WARNING("You can't give shares to yourself."))
				return TRUE
			var/list/holding = stock_market_get_holding(user.ckey, user.real_name, company_id)
			if(!holding || holding["shares_owned"] < amount)
				to_chat(user, SPAN_WARNING("You don't own that many shares."))
				return TRUE
			if(!SSeconomy.get_account_by_ckey_and_name(target_ckey, target_char_name))
				to_chat(user, SPAN_WARNING("That person doesn't have a personal Idris account."))
				return TRUE

			holding["shares_owned"] -= amount
			if(holding["shares_owned"] <= 0)
				holding["avg_cost_basis"] = 0
			SSpersistence.stockMarketSaveHolding(user.ckey, user.real_name, company_id, holding["shares_owned"], holding["avg_cost_basis"])

			var/list/target_holding = stock_market_get_holding(target_ckey, target_char_name, company_id)
			if(!target_holding)
				target_holding = list("company_id" = company_id, "shares_owned" = 0, "avg_cost_basis" = 0)
				LAZYADD(GLOB.persistence_stock_holdings_cache["[target_ckey]|[target_char_name]"], list(target_holding))
			// Recipient inherits the giver's cost basis for the gifted shares,
			// blended with anything they already hold -- same weighted-average
			// shape "buy" uses, just costed at the giver's basis instead of a
			// fresh purchase price (no money changes hands on a gift).
			var/gift_value = holding["avg_cost_basis"] * amount
			var/target_total = target_holding["shares_owned"] + amount
			target_holding["avg_cost_basis"] = round((target_holding["avg_cost_basis"] * target_holding["shares_owned"] + gift_value) / target_total)
			target_holding["shares_owned"] = target_total
			SSpersistence.stockMarketSaveHolding(target_ckey, target_char_name, company_id, target_holding["shares_owned"], target_holding["avg_cost_basis"])

			SSpersistence.stockMarketLogTrade(user.ckey, user.real_name, company_id, FALSE, amount, 0)
			SSpersistence.stockMarketLogTrade(target_ckey, target_char_name, company_id, TRUE, amount, 0)

			to_chat(user, SPAN_GOOD("Gave [amount] share(s) of [C.ticker] to [target_char_name]."))
			var/client/target_client = GLOB.directory[target_ckey]
			if(target_client)
				to_chat(target_client, SPAN_GOOD("[user.real_name] gave you [amount] share(s) of [C.ticker]."))
			return TRUE
