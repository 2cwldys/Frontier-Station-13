/// Supply Beacon Terminal trade marker -- a fixed point on the overmap chart
/// ships can fly adjacent to and trade commodity crates at, but never a place
/// they can actually enter (no Z-level of its own at all). Deliberately
/// subtypes /obj/effect/overmap directly, NOT /obj/effect/overmap/visitable --
/// see /obj/effect/overmap/event's own doc comment (events/event.dm) for why:
/// subtyping visitable makes something ships can "travel to" and pulls in a
/// huge amount of ship/sector machinery (holopads, telecomms, ship_weapons,
/// waypoints) this has no use for.
///
/// Price state lives directly on the beacon (not a separate stock-market-style
/// datum) since each beacon has exactly one marker for its whole lifetime --
/// see persistence_supply_beacons.dm for the load/save/tick logic and
/// GLOB.supply_beacon_commodities for what commodities exist.
/obj/effect/overmap/supply_beacon
	name = "Supply Beacon"
	desc = "An automated trade beacon. Ships can buy and sell commodity crates here using a Supply Beacon Terminal program once close enough."
	// Icon parity with the Frontier Beacon Depot (centcom_overmap.dm), per
	// request -- players should recognize both as "a fixed depot marker",
	// not confuse a beacon for a flyable sector.
	icon = 'icons/obj/overmap/overmap_stationary.dmi'
	icon_state = "depot"
	opacity = 0
	requires_contact = FALSE
	instant_contact = TRUE
	generic_object = FALSE

	/// Database primary key (ss13_supply_beacons.beacon_id) -- null until
	/// SSpersistence has actually inserted/loaded this beacon's row.
	var/beacon_id
	/// commodity key (GLOB.supply_beacon_commodities) -> current price.
	var/list/commodity_prices = list()
	var/list/commodity_previous_prices = list()
	var/list/commodity_price_high = list()
	var/list/commodity_price_low = list()
	/// Free-text admin label, shown in "Modify Cargo Beacons" and the
	/// terminal program -- e.g. "Coreward relay", purely cosmetic.
	var/notes = ""

/obj/effect/overmap/supply_beacon/examine(mob/user)
	. = ..()
	. += SPAN_NOTICE("A Supply Beacon Terminal program can trade with this beacon once your ship is adjacent.")

/// Seeds every configured commodity's price state to its code-default base
/// price -- called on a brand new beacon (admin-placed, nothing in the DB
/// yet) before its first save. Loading an EXISTING beacon overwrites these
/// from the DB instead (see persistence_supply_beacons.dm).
/obj/effect/overmap/supply_beacon/proc/seed_default_prices()
	for(var/key in GLOB.supply_beacon_commodities)
		var/list/commodity = GLOB.supply_beacon_commodities[key]
		commodity_prices[key] = commodity["base_price"]
		commodity_previous_prices[key] = commodity["base_price"]
		commodity_price_high[key] = commodity["base_price"]
		commodity_price_low[key] = commodity["base_price"]

/// Geometric Brownian Motion price step for one commodity at this beacon --
/// same shape as /datum/stock_company/proc/tick_price() (stock_market.dm),
/// just keyed per-commodity-per-beacon instead of per-company. See that
/// proc's own doc comment for why the mean-reversion/Ito-correction terms
/// are shaped the way they are.
/obj/effect/overmap/supply_beacon/proc/tick_commodity_price(commodity_key)
	var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
	if(!commodity)
		return
	var/current_price = commodity_prices[commodity_key]
	var/base_price = commodity["base_price"]
	var/sigma = commodity["volatility"] / 100
	var/mean_reversion = (base_price - current_price) / max(base_price, 1) * 0.05
	var/mu = mean_reversion + 0.5 * sigma ** 2
	var/z = _stock_market_gaussian()
	var/log_return = (mu - 0.5 * sigma ** 2) + sigma * z
	if(prob(2))
		log_return += rand(-8, 8) / 100
	commodity_previous_prices[commodity_key] = current_price
	current_price = max(SUPPLY_BEACON_PRICE_FLOOR, round(current_price * (2.718281828459045 ** log_return)))
	commodity_prices[commodity_key] = current_price
	commodity_price_high[commodity_key] = max(commodity_price_high[commodity_key], current_price)
	commodity_price_low[commodity_key] = min(commodity_price_low[commodity_key], current_price)

/// Nudges one commodity's price at THIS beacon from an actual buy/sell --
/// mirrors /datum/stock_company/proc/apply_trade_impact() (stock_market.dm):
/// square-root-scaled market impact, clamped, buying pushes up and selling
/// pushes down. Never applies to any other beacon's price for the same
/// commodity -- that asymmetry across beacons is the entire point of the
/// trading loop (arbitrage between depots).
/obj/effect/overmap/supply_beacon/proc/apply_trade_impact(commodity_key, amount, is_buy)
	var/current_price = commodity_prices[commodity_key]
	if(isnull(current_price))
		return
	// Float is modeled as a flat reference quantity (not a real share count
	// like the stock market has) -- big enough that a handful of crates only
	// nudges price a little, small enough that hauling a full ship's worth
	// somewhere is actually felt.
	var/impact_pct = sqrt(amount / SUPPLY_BEACON_IMPACT_REFERENCE_QTY) * 100 * SUPPLY_BEACON_IMPACT_MULTIPLIER
	impact_pct = min(impact_pct, SUPPLY_BEACON_IMPACT_MAX_PCT)
	if(!is_buy)
		impact_pct = -impact_pct
	current_price = max(SUPPLY_BEACON_PRICE_FLOOR, round(current_price * (1 + impact_pct / 100)))
	commodity_prices[commodity_key] = current_price
	commodity_price_high[commodity_key] = max(commodity_price_high[commodity_key], current_price)
	commodity_price_low[commodity_key] = min(commodity_price_low[commodity_key], current_price)
