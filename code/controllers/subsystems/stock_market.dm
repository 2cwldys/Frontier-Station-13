/*
 * Stock Market
 * Fluctuating fake-company share prices players can buy/sell against their
 * personal money_account (economy.dm) via the "stockmarket" modular computer
 * program (code/modules/modular_computers/file_system/programs/generic/
 * stock_market.dm). Companies and holdings are SQL-persistent -- see
 * persistence_stock_market.dm for load/save/seed, modeled on SSttrade
 * (trade.dm) for this subsystem's own tick shape.
 */
SUBSYSTEM_DEF(stock_market)
	name = "Stock Market"
	wait = 5 MINUTES
	runlevels = RUNLEVELS_PLAYING
	/// "[company_id]" -> /datum/stock_company, populated at boot by
	/// SSpersistence.stockMarketInitialize().
	var/list/companies = list()

/datum/controller/subsystem/stock_market/Recover()
	companies = SSstock_market.companies

/datum/controller/subsystem/stock_market/fire()
	if(!length(companies))
		return
	for(var/cid in companies)
		var/datum/stock_company/C = companies[cid]
		C.tick_price()
	SSpersistence.stockMarketSaveCompanies()

/// Amplifies a trade's (shares / total_shares_outstanding) ratio into a
/// visible-but-still-small price move -- e.g. trading 1% of a company's
/// float moves its price roughly 2%. Real markets show exactly this shape
/// (deep-float blue chips barely move on a retail-sized order; a thin float
/// moves a lot more for the same share count) without needing to simulate
/// an actual order book.
#define STOCK_TRADE_IMPACT_MULTIPLIER 2
/// Hard clamp on how much a single trade can move a price, regardless of
/// size -- a safety rail against a player wealthy enough to buy a huge slice
/// of the float in one order swinging a price to an absurd number.
#define STOCK_TRADE_IMPACT_MAX_PCT 20

/// One fake company's live trading state. company_id/ticker/name/base_price/
/// total_shares_outstanding are fixed once seeded; current_price is the only
/// thing tick_price()/apply_trade_impact() mutate on a live basis.
/datum/stock_company
	var/company_id
	var/ticker
	var/name
	var/current_price = 100
	var/previous_price = 100
	/// "Fair value" anchor current_price gently mean-reverts toward -- the
	/// actual long-run stabilizer (see tick_price()). Without this, even a
	/// small per-tick random walk eventually drifts to absurd extremes over
	/// weeks of a server ticking every 5 minutes around the clock.
	var/base_price = 100
	/// Max ordinary percent move per tick -- higher on "meme stock" seed
	/// entries, lower on "blue chip" ones, for a bit of per-company flavor.
	/// Kept small: real single-stock moves over a few minutes are a
	/// fraction of a percent, not a whole day's volatility.
	var/volatility = 1.5
	/// Total float -- market cap (shown to players as this company's "total
	/// net wealth") is current_price * total_shares_outstanding. Players
	/// only ever hold a sliver of this; the rest represents the simulated
	/// rest of the market (every other investor), never individually
	/// modeled. Fixed at seed time.
	var/total_shares_outstanding = 1000000

/// Realistic-ish background price move: a small ordinary +/-volatility%
/// step, pulled gently back toward base_price in proportion to how far it's
/// already strayed (so the price wobbles around a fair value instead of
/// random-walking to zero or the stratosphere), plus a rare (2%) modest
/// "news event" swing layered on top -- never a crash-to-zero or a moonshot.
/// This represents the aggregate churn of the simulated rest of the market;
/// actual player trades additionally move price via apply_trade_impact().
/datum/stock_company/proc/tick_price()
	previous_price = current_price
	var/pct_change = rand(-volatility * 10, volatility * 10) / 10
	var/deviation_pct = (current_price - base_price) / max(base_price, 1) * 100
	pct_change -= deviation_pct * 0.03
	if(prob(2))
		pct_change += rand(-8, 8)
	current_price = max(1, round(current_price * (1 + pct_change / 100)))

/// Nudges current_price from an actual player trade -- buying pushes price
/// up, selling pushes it down, scaled by how big the order is relative to
/// the whole float. Called by the stockmarket program immediately after a
/// successful buy/sell (economy.dm's adjust_money() already went through by
/// that point) -- this does NOT touch previous_price, so the "Change" column
/// still reflects tick-to-tick movement, not intra-tick trade noise.
/datum/stock_company/proc/apply_trade_impact(amount, is_buy)
	var/impact_pct = (amount / max(total_shares_outstanding, 1)) * 100 * STOCK_TRADE_IMPACT_MULTIPLIER
	impact_pct = min(impact_pct, STOCK_TRADE_IMPACT_MAX_PCT)
	if(!is_buy)
		impact_pct = -impact_pct
	current_price = max(1, round(current_price * (1 + impact_pct / 100)))
