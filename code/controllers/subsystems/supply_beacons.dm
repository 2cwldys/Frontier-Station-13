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
	if(length(beacons))
		for(var/bid in beacons)
			var/obj/effect/overmap/supply_beacon/B = beacons[bid]
			if(QDELETED(B))
				continue
			for(var/commodity_key in GLOB.supply_beacon_commodities)
				B.tick_commodity_price(commodity_key)
		SSpersistence.supplyBeaconsSaveAll()

	// Piracy beacons keep an independent price (piracy_beacon.dm) driven by
	// the exact same tick math and commodity list, but persist through the
	// generic worldstate/persistent_objects hooks already on that type
	// rather than the ss13_supply_beacon_commodities table -- so no
	// SaveAll() call here; their next normal persistence cycle picks up the
	// change on its own. Ticks regardless of powered/tethered state, same
	// as a real supply beacon has no power concept and always ticks.
	for(var/obj/structure/machinery/piracy_beacon/P in GLOB.piracy_beacons)
		if(QDELETED(P))
			continue
		for(var/commodity_key in GLOB.supply_beacon_commodities)
			P.tick_commodity_price(commodity_key)
