/*
 * Stock Market
 * Fluctuating fake-company share prices players can buy/sell against their
 * personal money_account (economy.dm) via the "stockmarket" modular computer
 * program (code/modules/modular_computers/file_system/programs/generic/
 * stock_market.dm). Companies and holdings are SQL-persistent -- see
 * persistence_stock_market.dm for load/save/seed, modeled on SSttrade
 * (trade.dm) for this subsystem's own tick shape.
 *
 * Deliberately has NO runlevels restriction -- this is a persistent,
 * always-on economy system, not round-specific gameplay, so it follows
 * SSpersistence's own precedent (persistence.dm) of firing unconditionally
 * on `wait` alone rather than gating on RUNLEVELS_PLAYING the way a normal
 * round-scoped gameplay subsystem (e.g. SSttrade) would. An earlier pass
 * copied SSttrade's runlevels gate without checking this distinction, which
 * is the most likely reason prices never moved on a long-running server.
 */
SUBSYSTEM_DEF(stock_market)
	name = "Stock Market"
	// Short enough that a player watching the Market tab actually sees
	// multiple companies visibly move within a few seconds, instead of one
	// slow 30-second-apart tick reading as "random"/not-live.
	wait = 5 SECONDS
	/// "[company_id]" -> /datum/stock_company, populated at boot by
	/// SSpersistence.stockMarketInitialize().
	var/list/companies = list()

/datum/controller/subsystem/stock_market/Recover()
	companies = SSstock_market.companies

/datum/controller/subsystem/stock_market/fire()
	if(!length(companies))
		log_world("SSstock_market: fire() called with zero companies loaded -- skipping tick.")
		return
	// Copy first -- stockMarketRevokeFaction() (called from sync_price_to_treasury()
	// on insolvency) mutates SSstock_market.companies, which would corrupt an
	// in-progress `for(var/cid in companies)` iteration over the live list.
	for(var/cid in companies.Copy())
		var/datum/stock_company/C = companies[cid]
		if(!C)
			continue // already delisted earlier this same tick
		if(C.faction_uid)
			// Faction-backed companies never get the AI random walk -- their
			// price is the faction's own treasury book value per share, so it
			// genuinely reflects that faction's real success (or failure),
			// not a simulation. Checked "even if offline" (this fires
			// regardless of anyone viewing the market) -- see
			// sync_price_to_treasury()'s own insolvency handling.
			C.sync_price_to_treasury()
			continue
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

/// Fixed share count a newly-listed faction company opens with -- deliberately
/// player-scale (thousands, not the AI companies' millions), so real trades
/// move its price meaningfully, matching a small real investor pool instead
/// of a deep simulated float.
#define STOCK_MARKET_FACTION_DEFAULT_SHARES 10000

/// One fake company's live trading state. company_id/ticker/name/base_price/
/// total_shares_outstanding are fixed once seeded; current_price is the only
/// thing tick_price()/apply_trade_impact() mutate on a live basis.
/datum/stock_company
	var/company_id
	/// Set only for a faction-listed company (persistence_factions.dm's
	/// faction_uid) -- null for an ordinary AI-simulated company. Gates out
	/// of tick_price()'s random walk (SSstock_market/fire()) and switches
	/// stock_market.dm's buy/sell handling to move the faction's real
	/// treasury instead of vanishing into the simulated rest-of-market.
	var/faction_uid
	var/ticker
	var/name
	var/current_price = 100
	var/previous_price = 100
	/// Running high/low since this company was seeded -- drives the price-
	/// range bar in the TGUI (current price's position between these two),
	/// updated by both tick_price() and apply_trade_impact() since either
	/// can set a new extreme.
	var/price_high = 100
	var/price_low = 100
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

/// Standard normal (mean 0, stddev 1) sample via the Box-Muller transform --
/// BYOND's rand() is only uniform, so this is the standard way to get a
/// normally-distributed shock for a Geometric Brownian Motion step below.
/proc/_stock_market_gaussian()
	var/u1 = rand(1, 10000) / 10000 // never exactly 0 -- log(0) is undefined
	var/u2 = rand(1, 10000) / 10000
	return sqrt(-2 * log(u1)) * cos(2 * 3.14159265 * u2)

/// Geometric Brownian Motion price step -- the standard model real
/// quantitative finance uses to simulate stock prices (also the process
/// underlying Black-Scholes): S(t+dt) = S(t) * exp((mu - 0.5*sigma^2)*dt +
/// sigma*sqrt(dt)*Z), Z ~ N(0,1). dt is fixed at 1 (one tick = one unit of
/// model time), so sqrt(dt) drops out. `mu` here is a mean-reversion drift
/// (pulls toward base_price, proportional to how far price has strayed) --
/// pure GBM has unbounded variance over time, which is fine for a finite
/// horizon but not for a server that ticks forever, so this layers on the
/// same idea an exponential Ornstein-Uhlenbeck process uses to keep a GBM-
/// style process from wandering to zero or infinity over weeks of uptime.
/// A rare (2%) discrete "news event" jump is layered on top too -- real
/// markets have jump-diffusion on top of continuous GBM, not just smooth
/// wobble. Actual player trades additionally move price via
/// apply_trade_impact(), independent of this background tick.
/datum/stock_company/proc/tick_price()
	previous_price = current_price
	var/sigma = volatility / 100
	// mean_reversion is ~0 once price sits at base_price -- without the
	// +0.5*sigma^2 baseline below, the Ito correction two lines down would
	// subtract from every single tick's log return with nothing to cancel
	// it, producing a guaranteed one-directional downward drift regardless
	// of price level (this was a real bug, not intentional bearishness).
	var/mean_reversion = (base_price - current_price) / max(base_price, 1) * 0.05
	var/mu = mean_reversion + 0.5 * sigma ** 2
	var/z = _stock_market_gaussian()
	var/log_return = (mu - 0.5 * sigma ** 2) + sigma * z
	if(prob(2))
		log_return += rand(-8, 8) / 100
	// BYOND has no exp() proc -- e^x via the power operator instead.
	current_price = max(1, round(current_price * (2.718281828459045 ** log_return)))
	price_high = max(price_high, current_price)
	price_low = min(price_low, current_price)

/// Faction-company counterpart to tick_price() -- price IS the faction's
/// treasury book value per share (balance / total_shares_outstanding),
/// recomputed every SSstock_market tick so it reflects that faction's real
/// financial health, not a simulation: wages paid, ships bought, combat
/// losses, admin adjustments, and stock trades (buy credits the treasury,
/// sell debits it -- see stock_market.dm's ui_act()) all move the balance,
/// and therefore the price, the same way. Runs "even if offline" in the
/// sense that this fires every tick regardless of anyone viewing the
/// market -- if the treasury has run dry, the listing is auto-revoked
/// (force-liquidating remaining holders, who by then are owed next to
/// nothing anyway, since price already fell in step with the balance) the
/// moment it's next ticked, not just when a player happens to trade.
/datum/stock_company/proc/sync_price_to_treasury()
	if(!faction_uid)
		return
	var/balance = get_faction_account_balance(faction_uid)
	if(isnull(balance))
		return // faction gone from the cache entirely -- leave the listing for an admin to sort out
	previous_price = current_price
	current_price = max(0, round(balance / max(total_shares_outstanding, 1)))
	price_high = max(price_high, current_price)
	price_low = min(price_low, current_price)
	if(balance <= 0)
		SSpersistence.stockMarketRevokeFaction(company_id, null)

/// Nudges current_price from an actual player trade -- buying pushes price
/// up, selling pushes it down. Scaled by the SQUARE ROOT of (shares / total
/// float), not linearly -- this is the market-impact law order-execution
/// research actually finds in real markets (impact ~ sigma * sqrt(order
/// size / volume)): a thin-float stock moves noticeably more per share
/// traded than a deep-float one, but doubling an order size doesn't double
/// its price impact the way a linear model would. Called by the
/// stockmarket program immediately after a successful buy/sell (economy.dm's
/// adjust_money() already went through by that point) -- this does NOT
/// touch previous_price, so the "Change" column still reflects tick-to-tick
/// movement, not intra-tick trade noise.
/datum/stock_company/proc/apply_trade_impact(amount, is_buy)
	var/impact_pct = sqrt(amount / max(total_shares_outstanding, 1)) * 100 * STOCK_TRADE_IMPACT_MULTIPLIER
	impact_pct = min(impact_pct, STOCK_TRADE_IMPACT_MAX_PCT)
	if(!is_buy)
		impact_pct = -impact_pct
	current_price = max(1, round(current_price * (1 + impact_pct / 100)))
	price_high = max(price_high, current_price)
	price_low = min(price_low, current_price)
