/*
 * Supply Beacon Terminal
 * Per-beacon, per-commodity fluctuating crate prices -- see
 * code/modules/overmap/supply_beacon.dm for the marker object itself and
 * persistence_supply_beacons.dm for load/save/seed. Modeled directly on
 * SSstock_market (stock_market.dm) -- same tick shape, same "no runlevels
 * gate, this is a persistent economy not round-scoped gameplay" reasoning.
 */
SUBSYSTEM_DEF(supply_beacons)
	name = "Supply Beacons"
	// Slower than SSstock_market's 5-second tick -- these prices are meant to
	// move on the timescale of "fly to another beacon and back", not be
	// watched live tick-by-tick the way a stock ticker is.
	wait = 30 SECONDS
	/// "[beacon_id]" -> /obj/effect/overmap/supply_beacon, populated at boot
	/// by SSpersistence.supplyBeaconsInitialize().
	var/list/beacons = list()

/datum/controller/subsystem/supply_beacons/Recover()
	beacons = SSsupply_beacons.beacons

/datum/controller/subsystem/supply_beacons/fire()
	if(!length(beacons))
		return
	for(var/bid in beacons)
		var/obj/effect/overmap/supply_beacon/B = beacons[bid]
		if(QDELETED(B))
			continue
		for(var/commodity_key in GLOB.supply_beacon_commodities)
			B.tick_commodity_price(commodity_key)
	SSpersistence.supplyBeaconsSaveAll()
