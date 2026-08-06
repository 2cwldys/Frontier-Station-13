/*
 * Persistence - Supply Beacon Terminal
 * Loads/saves Supply Beacon markers and their per-commodity prices. Unlike
 * the stock market (persistence_stock_market.dm), there is no code-side seed
 * list of beacons themselves -- a fresh server starts with zero beacons, and
 * admins place them one at a time with the "Modify Cargo Beacons" verb
 * (below). GLOB.supply_beacon_commodities IS a code-side seed list, same
 * "placeholder, not final" convention as GLOB.stock_market_seed_companies --
 * it only supplies each commodity's starting/mean-reversion price, never a
 * beacon's actual live price once seeded.
 */

/// Hard floor every beacon commodity price is clamped to -- drift
/// (tick_commodity_price()) and trade impact (apply_trade_impact()) never
/// push a price below this, no matter how much gets dumped on one beacon.
/// No corresponding ceiling -- matches the stock market's own unclamped
/// upside convention.
#define SUPPLY_BEACON_PRICE_FLOOR 1000

/// Trade-impact tuning -- see /obj/effect/overmap/supply_beacon/proc/apply_trade_impact().
/// Reference quantity a trade is compared against (bigger = a given crate
/// count moves price less), multiplier scales the resulting percent, and the
/// max percent hard-clamps a single transaction's swing.
#define SUPPLY_BEACON_IMPACT_REFERENCE_QTY 500
#define SUPPLY_BEACON_IMPACT_MULTIPLIER 2
#define SUPPLY_BEACON_IMPACT_MAX_PCT 20

/// How long, after ANY buy or sell at a given beacon, that same (source,
/// beacon) pair is locked out of trading with it again in either direction.
#define SUPPLY_BEACON_TRADE_COOLDOWN (30 MINUTES)

/// Placeholder commodity seed data -- flavor names only, easy to rename
/// later (see GLOB.stock_market_seed_companies for the same convention).
/// base_price is each commodity's long-run mean-reversion anchor (tick_
/// commodity_price() drifts back toward it over time) AND the starting
/// price any newly-placed beacon seeds that commodity at -- editing this
/// only affects beacons placed AFTER the change; existing beacons keep
/// whatever they've already drifted to.
GLOBAL_LIST_INIT(supply_beacon_commodities, list(
	"zenithium" = list("name" = "Zenithium", "crate_type" = /obj/structure/closet/crate/supply_beacon/zenithium, "base_price" = 3000, "volatility" = 1.5),
	"coraline"  = list("name" = "Coraline",  "crate_type" = /obj/structure/closet/crate/supply_beacon/coraline,  "base_price" = 2000, "volatility" = 2.2),
	"veridium"  = list("name" = "Veridium",  "crate_type" = /obj/structure/closet/crate/supply_beacon/veridium,  "base_price" = 4000, "volatility" = 1.0),
	"pyrolite"  = list("name" = "Pyrolite",  "crate_type" = /obj/structure/closet/crate/supply_beacon/pyrolite,  "base_price" = 1500, "volatility" = 2.5),
))

/// "[x],[y]" -> /obj/effect/overmap/supply_beacon, kept in lockstep with
/// SSsupply_beacons.beacons -- separate lookup because collision checks
/// (persistence_factions.dm's _pick_free_overmap_tile(), away-site
/// generation) care about POSITION, not beacon_id. Populated/cleared
/// alongside every place/remove/load.
GLOBAL_LIST_EMPTY(supply_beacon_positions)

/// "[source_key]|[beacon_id]" -> world.time of that pair's last trade --
/// checked by the terminal program before allowing a new buy/sell. Not
/// database-backed: a 30-minute lockout surviving a server restart isn't
/// worth the persistence weight, and restarts are already rare enough mid-
/// cooldown that players won't reliably exploit it.
GLOBAL_LIST_EMPTY(supply_beacon_trade_cooldowns)

/// Builds the per-(billing mode) identity string a trade cooldown is keyed
/// on -- mirrors the exact 3-way faction/personal/crew branch cargo_order.dm
/// uses to pick a billing mode off a modular computer, so "the same source"
/// always means the same thing a trade's actual payer/payee did.
/proc/get_supply_beacon_source_key(obj/item/modular_computer/computer)
	if(!computer)
		return null
	var/co_net = normalize_faction_uid(computer.persistent_network)
	if(co_net)
		return "faction:[co_net]"
	if(computer.personal_ckey)
		return "personal:[computer.personal_ckey]|[computer.personal_char_name]"
	if(computer.crew_tagged)
		var/datum/drydock_ship/crew_ship = _drydock_ship_at(GET_Z(computer))
		if(crew_ship)
			return "crew:[crew_ship.shuttle_id]"
	return null

/// Seconds remaining before source_key can trade with beacon_id again, or 0
/// if it's currently allowed.
/proc/supply_beacon_cooldown_remaining(source_key, beacon_id)
	if(!source_key)
		return 0
	var/last_trade = GLOB.supply_beacon_trade_cooldowns["[source_key]|[beacon_id]"]
	if(!last_trade)
		return 0
	var/remaining = SUPPLY_BEACON_TRADE_COOLDOWN - (world.time - last_trade)
	return max(0, round(remaining / 10))

/proc/supply_beacon_set_cooldown(source_key, beacon_id)
	if(!source_key)
		return
	GLOB.supply_beacon_trade_cooldowns["[source_key]|[beacon_id]"] = world.time

/// TRUE if a ship on z-level `z` is on or adjacent to (within 1 overmap
/// tile of) beacon B -- mirrors the "must be within 1 tile adjacent" rule
/// from the existing cargo export/delivery system, checked against the
/// ship's OWN overmap marker (GLOB.map_sectors["[z]"]) rather than any
/// physical turf, since B has no Z-level to be physically near.
/proc/supply_beacon_ship_in_range(z, obj/effect/overmap/supply_beacon/B)
	if(!B || !z)
		return FALSE
	var/obj/effect/overmap/visitable/ship_marker = GLOB.map_sectors["[z]"]
	if(!ship_marker)
		return FALSE
	return get_dist(ship_marker, B) <= 1

/// Loads every persisted Supply Beacon (and its commodity prices) into
/// SSsupply_beacons.beacons/GLOB.supply_beacon_positions. Called from
/// SSpersistence.Initialize(). Unlike stock market companies, there is
/// nothing to seed here on an empty table -- zero beacons is the correct
/// starting state until an admin places one.
/datum/controller/subsystem/persistence/proc/supplyBeaconsInitialize()
	if(!databaseCheckConnection("supplyBeaconsInitialize"))
		return
	if(!SSatlas.current_map.use_overmap)
		return
	UNTIL(SSatlas.current_map.overmap_z)

	var/list/loaded_beacons = list()
	var/list/loaded_positions = list()
	var/datum/db_query/q = SSdbcore.NewQuery("SELECT beacon_id, x, y, notes FROM ss13_supply_beacons", list())
	q.Execute()
	if(databaseCheckQueryResult(q, "supplyBeaconsInitialize beacons"))
		while(q.NextRow())
			var/obj/effect/overmap/supply_beacon/B = new()
			B.beacon_id = text2num(q.item[1])
			B.x = text2num(q.item[2])
			B.y = text2num(q.item[3])
			B.notes = q.item[4] || ""
			B.name = B.notes || "Supply Beacon #[B.beacon_id]"
			B.seed_default_prices() // overwritten below for any commodity actually in the DB
			var/turf/home = locate(B.x, B.y, SSatlas.current_map.overmap_z)
			if(home)
				B.forceMove(home)
			loaded_beacons["[B.beacon_id]"] = B
			loaded_positions["[B.x],[B.y]"] = B
	else
		message_admins("Supply beacon load query failed -- beacons may be running on stale/empty data. Check DB schema (db_update?).")
		qdel(q)
		return
	qdel(q)

	var/datum/db_query/pq = SSdbcore.NewQuery("SELECT beacon_id, commodity, current_price, previous_price, price_high, price_low FROM ss13_supply_beacon_commodities", list())
	pq.Execute()
	if(databaseCheckQueryResult(pq, "supplyBeaconsInitialize commodities"))
		while(pq.NextRow())
			var/obj/effect/overmap/supply_beacon/B = loaded_beacons["[text2num(pq.item[1])]"]
			if(!B)
				continue // stale row from a since-removed beacon
			var/commodity_key = pq.item[2]
			B.commodity_prices[commodity_key] = text2num(pq.item[3])
			B.commodity_previous_prices[commodity_key] = text2num(pq.item[4])
			B.commodity_price_high[commodity_key] = text2num(pq.item[5])
			B.commodity_price_low[commodity_key] = text2num(pq.item[6])
	qdel(pq)

	SSsupply_beacons.beacons = loaded_beacons
	GLOB.supply_beacon_positions = loaded_positions
	log_subsystem_persistence_info("Supply beacons: loaded [length(loaded_beacons)] beacon(s).")

	// zone_security_update_overmap_borders() (persistence_zone_security.dm)
	// only repaints on the rare claim/release/security-change events that
	// already call zone_security_update_overmap() -- it is NOT a continuous
	// per-tile check, so a beacon that lands inside an already-active
	// faction beacon's radius does NOT get its tile's tint for free just by
	// existing. Force one repaint here so every loaded beacon's tile
	// reflects current territory the moment the server comes up, instead of
	// waiting for the next unrelated security event to happen to touch it.
	if(length(loaded_beacons))
		zone_security_update_overmap()

/// Upserts every beacon's every commodity price -- called from
/// SSsupply_beacons' own fire() (not SSpersistence.fire()), same "price
/// ticking stays decoupled from the heavy autosave" reasoning as the stock
/// market's stockMarketSaveCompanies().
/datum/controller/subsystem/persistence/proc/supplyBeaconsSaveAll()
	if(!databaseCheckConnection("supplyBeaconsSaveAll"))
		return
	for(var/bid in SSsupply_beacons.beacons)
		var/obj/effect/overmap/supply_beacon/B = SSsupply_beacons.beacons[bid]
		if(QDELETED(B))
			continue
		for(var/commodity_key in GLOB.supply_beacon_commodities)
			var/datum/db_query/q = SSdbcore.NewQuery(
				{"INSERT INTO ss13_supply_beacon_commodities (beacon_id, commodity, current_price, previous_price, price_high, price_low)
				VALUES (:bid, :commodity, :price, :prev, :high, :low)
				ON DUPLICATE KEY UPDATE current_price = VALUES(current_price), previous_price = VALUES(previous_price), price_high = VALUES(price_high), price_low = VALUES(price_low)"},
				list(
					"bid" = B.beacon_id, "commodity" = commodity_key,
					"price" = B.commodity_prices[commodity_key], "prev" = B.commodity_previous_prices[commodity_key],
					"high" = B.commodity_price_high[commodity_key], "low" = B.commodity_price_low[commodity_key],
				)
			)
			q.Execute()
			databaseCheckQueryResult(q, "supplyBeaconsSaveAll [B.beacon_id]/[commodity_key]")
			qdel(q)

/**
 * Places a new Supply Beacon at overmap (x,y) -- inserts its DB row, seeds
 * every commodity to its code-default base price, and adds it to both live
 * lookups immediately. Returns list("beacon" = the new beacon or null,
 * "error" = null or a user-facing reason). Does NOT refuse an occupied tile
 * outright (a beacon has no physical collision with a ship/away-site sitting
 * on the same tile) -- the admin verb itself surfaces an "already occupied"
 * warning and asks for confirmation instead.
 */
/datum/controller/subsystem/persistence/proc/supplyBeaconsPlace(x, y, notes, mob/user)
	if(!databaseCheckConnection("supplyBeaconsPlace"))
		return list("beacon" = null, "error" = "Database connection failed.")
	if(!SSatlas.current_map.use_overmap || !SSatlas.current_map.overmap_z)
		return list("beacon" = null, "error" = "This map has no overmap.")
	var/turf/home = locate(x, y, SSatlas.current_map.overmap_z)
	if(!home)
		return list("beacon" = null, "error" = "No overmap tile at ([x],[y]).")

	var/datum/db_query/iq = SSdbcore.NewQuery(
		"INSERT INTO ss13_supply_beacons (x, y, notes) VALUES (:x, :y, :notes)",
		list("x" = x, "y" = y, "notes" = notes || "")
	)
	iq.Execute()
	if(!databaseCheckQueryResult(iq, "supplyBeaconsPlace insert"))
		qdel(iq)
		return list("beacon" = null, "error" = "Database insert failed.")
	var/new_id = text2num(iq.last_insert_id)
	qdel(iq)

	var/obj/effect/overmap/supply_beacon/B = new()
	B.beacon_id = new_id
	B.x = x
	B.y = y
	B.notes = notes || ""
	B.name = B.notes || "Supply Beacon #[B.beacon_id]"
	B.seed_default_prices()
	B.forceMove(home)

	SSsupply_beacons.beacons["[B.beacon_id]"] = B
	GLOB.supply_beacon_positions["[x],[y]"] = B

	// See the matching comment in supplyBeaconsInitialize() -- the zone
	// security repaint is event-driven, not continuous, so a beacon placed
	// inside an already-active faction beacon's radius won't pick up that
	// tile's tint on its own. Force one now so it shows correctly the
	// instant it's placed, not just whenever the next unrelated security
	// event happens to repaint the map.
	zone_security_update_overmap()

	log_and_message_admins("placed a Supply Beacon (#[B.beacon_id]) at overmap ([x],[y])[notes ? ": \"[notes]\"" : ""].", user)
	return list("beacon" = B, "error" = null)

/// Removes a Supply Beacon completely -- deletes its DB rows, drops it from
/// both live lookups, and qdels the marker. Returns null on success, or a
/// user-facing reason.
/datum/controller/subsystem/persistence/proc/supplyBeaconsRemove(beacon_id, mob/user)
	var/obj/effect/overmap/supply_beacon/B = SSsupply_beacons.beacons["[beacon_id]"]
	if(!B)
		return "No such beacon."
	if(!databaseCheckConnection("supplyBeaconsRemove"))
		return "Database connection failed."

	var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_supply_beacon_commodities WHERE beacon_id = :id", list("id" = beacon_id))
	dq.Execute()
	databaseCheckQueryResult(dq, "supplyBeaconsRemove delete commodities")
	qdel(dq)
	var/datum/db_query/bq = SSdbcore.NewQuery("DELETE FROM ss13_supply_beacons WHERE beacon_id = :id", list("id" = beacon_id))
	bq.Execute()
	databaseCheckQueryResult(bq, "supplyBeaconsRemove delete beacon")
	qdel(bq)

	SSsupply_beacons.beacons -= "[beacon_id]"
	GLOB.supply_beacon_positions -= "[B.x],[B.y]"
	log_and_message_admins("removed Supply Beacon #[beacon_id] (was at [B.x],[B.y]).", user)
	qdel(B)
	return null

/// Admin tool to place, remove, or reprice Supply Beacons -- same
/// tgui_input_list "menu loop" shape as Manage Stock Market
/// (persistence_stock_market.dm) and Modify Cargo Imports
/// (persistence_cargo_imports.dm).
/datum/admins/proc/modify_cargo_beacons()
	set name = "Modify Cargo Beacons"
	set category = "Persistence"
	set desc = "Place, remove, or reprice Supply Beacon Terminal trade depots."

	if(!check_rights(R_ADMIN))
		return
	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- Supply Beacons cannot be saved."))
		return
	if(!SSatlas.current_map.use_overmap || !SSatlas.current_map.overmap_z)
		to_chat(usr, SPAN_WARNING("This map has no overmap."))
		return

	while(usr && usr.client)
		var/choice = tgui_input_list(usr, "Supply Beacons ([length(SSsupply_beacons.beacons)] placed):", "Modify Cargo Beacons", list("Place Beacon", "Remove Beacon", "Set Commodity Price", "View Beacons", "Done"))
		if(!choice || choice == "Done")
			return

		if(choice == "Place Beacon")
			var/map_low = OVERMAP_EDGE
			var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
			var/default_x = (usr.z == SSatlas.current_map.overmap_z) ? usr.x : map_low
			var/default_y = (usr.z == SSatlas.current_map.overmap_z) ? usr.y : map_low
			var/pick_x = tgui_input_number(usr, "Overmap X ([map_low]-[map_high])[usr.z == SSatlas.current_map.overmap_z ? " -- defaulting to your current tile" : ""]:", "Modify Cargo Beacons", default_x, map_high, map_low)
			if(isnull(pick_x))
				continue
			var/pick_y = tgui_input_number(usr, "Overmap Y ([map_low]-[map_high]):", "Modify Cargo Beacons", default_y, map_high, map_low)
			if(isnull(pick_y))
				continue
			pick_x = clamp(pick_x, map_low, map_high)
			pick_y = clamp(pick_y, map_low, map_high)

			var/turf/target_tile = locate(pick_x, pick_y, SSatlas.current_map.overmap_z)
			if(!target_tile)
				to_chat(usr, SPAN_WARNING("No overmap tile at ([pick_x],[pick_y])."))
				continue
			// Hard refusal, not a warn-and-confirm -- mirrors Generate Away
			// Site's own occupied-tile check exactly. Covers ships, sectors,
			// and away sites alike (anything /visitable).
			var/obj/effect/overmap/visitable/occupant = locate() in target_tile
			if(occupant)
				to_chat(usr, SPAN_WARNING("([pick_x],[pick_y]) is already occupied by '[occupant.name]' -- pick another tile."))
				continue
			var/obj/effect/overmap/supply_beacon/existing_beacon = locate() in target_tile
			if(existing_beacon)
				to_chat(usr, SPAN_WARNING("([pick_x],[pick_y]) already has Supply Beacon #[existing_beacon.beacon_id] on it -- pick another tile."))
				continue

			var/notes = sanitize(input(usr, "Optional label for this beacon:", "Modify Cargo Beacons", "") as null|text)

			var/list/result = SSpersistence.supplyBeaconsPlace(pick_x, pick_y, notes, usr)
			if(result["error"])
				to_chat(usr, SPAN_WARNING(result["error"]))
			else
				var/obj/effect/overmap/supply_beacon/B = result["beacon"]
				to_chat(usr, SPAN_GOOD("Placed Supply Beacon #[B.beacon_id] at ([pick_x],[pick_y])."))

		if(choice == "Remove Beacon")
			if(!length(SSsupply_beacons.beacons))
				to_chat(usr, SPAN_WARNING("No beacons placed."))
				continue
			var/list/beacon_choices = list()
			for(var/bid in SSsupply_beacons.beacons)
				var/obj/effect/overmap/supply_beacon/B = SSsupply_beacons.beacons[bid]
				beacon_choices["#[B.beacon_id] ([B.x],[B.y])[B.notes ? " -- \"[B.notes]\"" : ""]"] = B
			var/remove_pick = tgui_input_list(usr, "Remove which beacon?", "Modify Cargo Beacons", beacon_choices)
			if(!remove_pick)
				continue
			var/obj/effect/overmap/supply_beacon/target = beacon_choices[remove_pick]
			var/confirm = tgui_alert(usr, "Remove Supply Beacon #[target.beacon_id] at ([target.x],[target.y])? Cannot be undone.", "Modify Cargo Beacons", list("Remove", "Cancel"))
			if(confirm != "Remove")
				continue
			var/reason = SSpersistence.supplyBeaconsRemove(target.beacon_id, usr)
			if(reason)
				to_chat(usr, SPAN_WARNING(reason))
			else
				to_chat(usr, SPAN_GOOD("Beacon removed."))

		if(choice == "Set Commodity Price")
			if(!length(SSsupply_beacons.beacons))
				to_chat(usr, SPAN_WARNING("No beacons placed."))
				continue
			var/list/beacon_choices2 = list()
			for(var/bid in SSsupply_beacons.beacons)
				var/obj/effect/overmap/supply_beacon/B = SSsupply_beacons.beacons[bid]
				beacon_choices2["#[B.beacon_id] ([B.x],[B.y])[B.notes ? " -- \"[B.notes]\"" : ""]"] = B
			var/beacon_pick = tgui_input_list(usr, "Which beacon?", "Modify Cargo Beacons", beacon_choices2)
			if(!beacon_pick)
				continue
			var/obj/effect/overmap/supply_beacon/chosen_beacon = beacon_choices2[beacon_pick]

			var/list/commodity_choices = list()
			for(var/key in GLOB.supply_beacon_commodities)
				var/list/commodity = GLOB.supply_beacon_commodities[key]
				commodity_choices["[commodity["name"]] ([chosen_beacon.commodity_prices[key]] cr)"] = key
			var/commodity_pick = tgui_input_list(usr, "Which commodity?", "Modify Cargo Beacons", commodity_choices)
			if(!commodity_pick)
				continue
			var/commodity_key = commodity_choices[commodity_pick]

			var/old_price = chosen_beacon.commodity_prices[commodity_key]
			var/new_price = tgui_input_number(usr, "New price for '[GLOB.supply_beacon_commodities[commodity_key]["name"]]' at beacon #[chosen_beacon.beacon_id] (floor [SUPPLY_BEACON_PRICE_FLOOR] cr):", "Modify Cargo Beacons", old_price, 1000000, SUPPLY_BEACON_PRICE_FLOOR)
			if(isnull(new_price))
				continue
			new_price = max(SUPPLY_BEACON_PRICE_FLOOR, new_price)
			chosen_beacon.commodity_prices[commodity_key] = new_price
			chosen_beacon.commodity_price_high[commodity_key] = max(chosen_beacon.commodity_price_high[commodity_key], new_price)
			chosen_beacon.commodity_price_low[commodity_key] = min(chosen_beacon.commodity_price_low[commodity_key], new_price)
			SSpersistence.supplyBeaconsSaveAll()
			log_and_message_admins("set Supply Beacon #[chosen_beacon.beacon_id]'s [commodity_key] price from [old_price] to [new_price] cr via Modify Cargo Beacons.", usr)
			to_chat(usr, SPAN_GOOD("[commodity_key] at beacon #[chosen_beacon.beacon_id]: [old_price] -> [new_price] cr."))

		if(choice == "View Beacons")
			if(!length(SSsupply_beacons.beacons))
				to_chat(usr, SPAN_NOTICE("No beacons placed."))
				continue
			var/msg = "<b>Supply Beacons:</b>\n"
			for(var/bid in SSsupply_beacons.beacons)
				var/obj/effect/overmap/supply_beacon/B = SSsupply_beacons.beacons[bid]
				msg += "  #[B.beacon_id] ([B.x],[B.y])[B.notes ? " -- \"[B.notes]\"" : ""]:\n"
				for(var/key in GLOB.supply_beacon_commodities)
					var/list/commodity = GLOB.supply_beacon_commodities[key]
					msg += "    [commodity["name"]]: [B.commodity_prices[key]] cr\n"
			to_chat(usr, SPAN_NOTICE(msg))
