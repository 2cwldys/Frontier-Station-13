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

	var/datum/money_account/personal_account = SSeconomy.get_account_by_ckey(user.ckey)
	if(!personal_account)
		data["no_account"] = TRUE
		return data

	data["personal_balance"] = personal_account.money
	data["companies"] = list()
	var/total_market_cap = 0
	for(var/cid in SSstock_market.companies)
		var/datum/stock_company/C = SSstock_market.companies[cid]
		var/list/holding = stock_market_get_holding(user.ckey, C.company_id)
		var/market_cap = C.current_price * C.total_shares_outstanding
		total_market_cap += market_cap
		data["companies"] += list(list(
			"company_id" = C.company_id,
			"ticker" = C.ticker,
			"name" = C.name,
			"current_price" = C.current_price,
			"previous_price" = C.previous_price,
			"change_pct" = C.previous_price ? round((C.current_price - C.previous_price) / C.previous_price * 100, 0.1) : 0,
			"market_cap" = market_cap,
			"total_shares_outstanding" = C.total_shares_outstanding,
			"player_shares" = stock_market_total_player_shares(C.company_id),
			"shares_owned" = holding ? holding["shares_owned"] : 0,
			"avg_cost_basis" = holding ? holding["avg_cost_basis"] : 0
		))
	data["total_market_cap"] = total_market_cap
	return data

/datum/computer_file/program/stock_market/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/user = usr

	var/datum/money_account/personal_account = SSeconomy.get_account_by_ckey(user.ckey)
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
			var/list/holding = stock_market_get_holding(user.ckey, company_id)
			if(!holding)
				holding = list("company_id" = company_id, "shares_owned" = 0, "avg_cost_basis" = 0)
				LAZYADD(GLOB.persistence_stock_holdings_cache[user.ckey], list(holding))
			var/total_shares = holding["shares_owned"] + amount
			holding["avg_cost_basis"] = round((holding["avg_cost_basis"] * holding["shares_owned"] + cost) / total_shares)
			holding["shares_owned"] = total_shares
			SSpersistence.stockMarketSaveHolding(user.ckey, company_id, holding["shares_owned"], holding["avg_cost_basis"])
			C.apply_trade_impact(amount, TRUE)
			to_chat(user, SPAN_GOOD("Bought [amount] share(s) of [C.ticker] for [cost] credits."))
			return TRUE

		if("sell")
			if(!C || !amount || amount <= 0)
				return TRUE
			var/list/holding = stock_market_get_holding(user.ckey, company_id)
			if(!holding || holding["shares_owned"] < amount)
				to_chat(user, SPAN_WARNING("You don't own that many shares."))
				return TRUE
			var/proceeds = C.current_price * amount
			personal_account.adjust_money(proceeds)
			holding["shares_owned"] -= amount
			if(holding["shares_owned"] <= 0)
				holding["avg_cost_basis"] = 0
			SSpersistence.stockMarketSaveHolding(user.ckey, company_id, holding["shares_owned"], holding["avg_cost_basis"])
			C.apply_trade_impact(amount, FALSE)
			to_chat(user, SPAN_GOOD("Sold [amount] share(s) of [C.ticker] for [proceeds] credits."))
			return TRUE
