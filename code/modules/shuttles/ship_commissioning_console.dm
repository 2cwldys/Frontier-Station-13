/*
 * Ship Commissioning Console
 *
 * A player-buildable, cargo-orderable machine that turns a hull someone
 * physically built themselves into a real, independently-owned drydock
 * shuttle -- own ledger row (/datum/drydock_ship, persistence_shuttles.dm),
 * own schematic, own dedicated Z, stashes/retrieves exactly like any
 * template-bought ship from that point on. See docs on drydockCommission()
 * (persistence_shuttles.dm) for the actual capture/payment/ledger logic --
 * this file is only the console: previewing the buildable envelope and
 * collecting the player's choices before handing off to that proc.
 *
 * Deliberately separate from, but tied to, a nearby docking_beacon
 * (docking_beacon.dm) -- the beacon marks the spot; this console is where
 * you stand to build around it and commission the result. The console
 * itself is never consumed or destroyed by a successful commission -- it's
 * a reusable shipyard fixture, ready for the next hull the moment the
 * previous one launches.
 */
/obj/structure/machinery/computer/ship_commissioning
	name = "ship commissioning console"
	desc = "Surveys a build envelope and files the paperwork to commission a completed hull as a real, independently-owned shuttle."
	icon = 'icons/obj/modular_computers/modular_terminal.dmi'
	icon_screen = "engines"
	icon_keyboard = "tech_key"
	icon_keyboard_emis = "tech_key_mask"
	is_connected = TRUE
	has_off_keyboards = TRUE
	can_pass_under = FALSE
	light_power_on = 1
	anchored = FALSE // starts unanchored -- won't register while in a crate or being carried
	use_power = POWER_USE_IDLE
	idle_power_usage = 20
	component_types = list(
		/obj/item/circuitboard/ship_commissioning,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/console_screen,
		/obj/item/stack/cable_coil = 2
	)

	/// Turf-highlight indicators from the last Preview Build Envelope, if any
	/// -- cleared/replaced on the next preview or on commission.
	var/list/obj/effect/shuttle_warning/envelope_indicators = list()
	/// Snapshot from the last Preview: TRUE if every envelope tile was
	/// either open space or genuinely empty floor (no walls, no mobs, no
	/// objects) -- what gates "Generate Build Floor" in the TGUI. Only a UI
	/// convenience; _generate_build_floor() below always re-checks fresh
	/// before actually touching anything, never trusts this alone.
	var/envelope_clean_for_generate = FALSE

/obj/structure/machinery/computer/ship_commissioning/Initialize()
	. = ..()
	if(GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/obj/structure/machinery/computer/ship_commissioning/Destroy()
	QDEL_LIST(envelope_indicators)
	return ..()

/// Base /obj/structure/machinery/computer's own attackby() only ever handles
/// the screwdriver (deconstruct-if-anchored-and-broken) -- wrench-to-secure
/// has to be added here ourselves, same pattern docking_beacon.dm uses.
/obj/structure/machinery/computer/ship_commissioning/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Commissioning console secured in place.") : SPAN_NOTICE("Commissioning console unsecured."))
		return TRUE
	return ..(attacking_item, user, params)

/obj/structure/machinery/computer/ship_commissioning/attack_hand(mob/user)
	if(..())
		return TRUE
	if(!anchored)
		to_chat(user, SPAN_WARNING("\The [src] needs to be secured to the floor with a wrench first."))
		return TRUE
	ui_interact(user)
	return TRUE

/obj/structure/machinery/computer/ship_commissioning/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShipCommissioning", "Ship Commissioning")
		ui.open()

/obj/structure/machinery/computer/ship_commissioning/ui_data(mob/user)
	var/list/data = list()
	var/obj/structure/machinery/docking_beacon/beacon = _find_nearby_beacon()
	data["beacon_found"] = !!beacon
	data["beacon_label"] = beacon ? (beacon.dock_label || "Docking Port") : null
	data["footprint_x"] = SUBSHIP_FOOTPRINT_X
	data["footprint_y"] = SUBSHIP_FOOTPRINT_Y
	data["price"] = SHIP_COMMISSION_PRICE
	var/obj/item/card/id/ID = user.GetIdCard()
	data["own_faction"] = (ID && ID.employer_faction) ? ID.employer_faction : null
	data["own_faction_name"] = data["own_faction"] ? get_faction_name(data["own_faction"]) : null
	// Live-polled every UI update, same as beacon_found -- greys the
	// Commission buttons out (not just refused after the fact) whenever
	// anyone, dead or alive, is still standing in the build envelope. See
	// _drydock_envelope_has_occupants() (persistence_shuttles.dm), the same
	// check drydockCommission() itself enforces server-side.
	var/list/turf/envelope = _get_envelope_turfs()
	data["envelope_occupied"] = envelope ? _drydock_envelope_has_occupants(envelope) : FALSE
	// Same live-polled shape for the required docking_transponder --
	// _drydock_envelope_find_transponder()/drydockCommission() (both
	// persistence_shuttles.dm) are the actual source of truth this mirrors.
	var/obj/structure/machinery/docking_transponder/transponder = envelope ? _drydock_envelope_find_transponder(envelope) : null
	data["transponder_found"] = !!transponder
	data["transponder_aligned"] = (transponder && beacon) ? (turn(transponder.dir, 180) == beacon.dir) : FALSE
	// Same shape again for the required shuttle_control console --
	// _drydock_envelope_find_console()/drydockCommission() (both
	// persistence_shuttles.dm) are the actual source of truth this mirrors.
	data["console_found"] = envelope ? !!_drydock_envelope_find_console(envelope) : FALSE
	// Snapshot from the last Preview -- see envelope_clean_for_generate's
	// own doc comment for why this isn't re-checked live here.
	data["can_generate_floor"] = data["beacon_found"] && envelope_clean_for_generate
	return data

/obj/structure/machinery/computer/ship_commissioning/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("preview")
			_show_envelope_preview(user)
			. = TRUE
		if("generate_floor")
			_generate_build_floor(user)
			. = TRUE
		if("commission")
			var/as_faction = params["as_faction"] ? TRUE : FALSE
			var/dock_at_beacon = params["dock_at_beacon"] ? TRUE : FALSE
			var/obj/item/card/id/ID = user.GetIdCard()
			var/faction_uid = as_faction ? ((ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null) : null
			var/new_name = tgui_input_text(user, "Name this shuttle:", "Commission Shuttle", max_length = 64)
			if(!new_name)
				return TRUE
			SSpersistence.drydockCommission(src, user, faction_uid, new_name, dock_at_beacon)
			. = TRUE

/// Nearest active docking_beacon within BUILD_ENVELOPE_BEACON_RANGE tiles --
/// the build envelope is anchored to ITS turf (see _get_envelope_corner()),
/// not the console's own (the console can sit off to the side, "past the
/// interior cycler", while the beacon marks the ship's actual future dock
/// position).
/obj/structure/machinery/computer/ship_commissioning/proc/_find_nearby_beacon()
	var/obj/structure/machinery/docking_beacon/closest
	var/closest_dist
	for(var/obj/structure/machinery/docking_beacon/beacon in oview(BUILD_ENVELOPE_BEACON_RANGE, src))
		if(!beacon.anchored || !beacon.beacon_active)
			continue
		var/dist = get_dist(src, beacon)
		if(isnull(closest_dist) || dist < closest_dist)
			closest = beacon
			closest_dist = dist
	return closest

/// Bottom-left corner turf of the build envelope for the given beacon (or
/// null if it/its turf is gone) -- the shared reference point
/// _get_envelope_turfs(), _show_envelope_preview(), and
/// _drydockCommissionRun() (persistence_shuttles.dm) all derive the same
/// SUBSHIP_FOOTPRINT_X x SUBSHIP_FOOTPRINT_Y block from, so the preview and
/// the actual capture can never disagree about which tiles are covered.
///
/// The box sits flush against the beacon on whichever side it's currently
/// facing, not centered on it -- rotate the beacon (multitool) to choose
/// which of the four cardinal directions the hull gets built in. The
/// beacon's own tile sits on the box's edge nearest it either way (already
/// excluded from capture/wipe by object reference, see
/// _drydockCommissionRun()), which is also the exact edge
/// _show_envelope_preview() tints -- turn(beacon.dir, 180), the direction a
/// docking_transponder needs to face, always lands on that same edge.
/obj/structure/machinery/computer/ship_commissioning/proc/_get_envelope_corner(obj/structure/machinery/docking_beacon/beacon)
	var/turf/center = beacon ? get_turf(beacon) : null
	if(!center)
		return null
	var/half_x = round((SUBSHIP_FOOTPRINT_X - 1) / 2)
	var/half_y = round((SUBSHIP_FOOTPRINT_Y - 1) / 2)
	switch(beacon.dir)
		if(WEST)
			return locate(center.x - (SUBSHIP_FOOTPRINT_X - 1), center.y - half_y, center.z)
		if(EAST)
			return locate(center.x, center.y - half_y, center.z)
		if(SOUTH)
			return locate(center.x - half_x, center.y - (SUBSHIP_FOOTPRINT_Y - 1), center.z)
		if(NORTH)
			return locate(center.x - half_x, center.y, center.z)
	// Non-cardinal dir shouldn't be reachable (rotate only ever turns by
	// 90 degrees from a cardinal start) -- fall back to centered rather
	// than error.
	return locate(center.x - half_x, center.y - half_y, center.z)

/// The SUBSHIP_FOOTPRINT_X x SUBSHIP_FOOTPRINT_Y block of turfs the build
/// envelope covers, positioned per _get_envelope_corner() -- null if no
/// beacon is currently in range. Shared by the preview and the commission
/// validation so they always agree on exactly the same tiles.
/obj/structure/machinery/computer/ship_commissioning/proc/_get_envelope_turfs()
	var/obj/structure/machinery/docking_beacon/beacon = _find_nearby_beacon()
	var/turf/corner = _get_envelope_corner(beacon)
	if(!corner)
		return null
	return block(corner, locate(corner.x + SUBSHIP_FOOTPRINT_X - 1, corner.y + SUBSHIP_FOOTPRINT_Y - 1, corner.z))

/// Highlights the build envelope, same shuttle_warning indicator any ship
/// landing preview already uses -- except the one edge matching where the
/// docking transponder needs to face (the exact opposite of the beacon's
/// own dir, same comparison drydockCommission() enforces) is tinted to
/// match the transponder's own color, so it's visually obvious which side
/// of the box to build your airlock on instead of having to reason about
/// facings abstractly.
/obj/structure/machinery/computer/ship_commissioning/proc/_show_envelope_preview(mob/user)
	QDEL_LIST(envelope_indicators)
	envelope_clean_for_generate = FALSE
	var/obj/structure/machinery/docking_beacon/beacon = _find_nearby_beacon()
	if(!beacon)
		to_chat(user, SPAN_WARNING("No active docking beacon in range -- place and activate one first."))
		return
	var/turf/corner = _get_envelope_corner(beacon)
	if(!corner)
		to_chat(user, SPAN_WARNING("The build envelope runs off the edge of the map."))
		return
	var/list/turf/envelope = block(corner, locate(corner.x + SUBSHIP_FOOTPRINT_X - 1, corner.y + SUBSHIP_FOOTPRINT_Y - 1, corner.z))
	envelope_clean_for_generate = !_envelope_generate_conflict(envelope, beacon)
	var/required_facing = turn(beacon.dir, 180)
	for(var/turf/T in envelope)
		var/is_airlock_edge = FALSE
		switch(required_facing)
			if(EAST)
				is_airlock_edge = (T.x == corner.x + SUBSHIP_FOOTPRINT_X - 1)
			if(WEST)
				is_airlock_edge = (T.x == corner.x)
			if(NORTH)
				is_airlock_edge = (T.y == corner.y + SUBSHIP_FOOTPRINT_Y - 1)
			if(SOUTH)
				is_airlock_edge = (T.y == corner.y)
		var/obj/effect/shuttle_warning/indicator = new(T)
		if(is_airlock_edge)
			indicator.color = "#3a2210"
		envelope_indicators += indicator
	addtimer(CALLBACK(src, PROC_REF(_clear_envelope_preview)), 10 SECONDS)
	to_chat(user, SPAN_NOTICE("Build envelope highlighted -- [SUBSHIP_FOOTPRINT_X]x[SUBSHIP_FOOTPRINT_Y] tiles, extending [dir2text(beacon.dir)] from the beacon. The tinted edge (facing [dir2text(required_facing)]) is where your airlock and transponder need to go."))
	to_chat(user, envelope_clean_for_generate \
		? SPAN_NOTICE("Envelope is clear -- Generate Build Floor is available.") \
		: SPAN_WARNING("Envelope already has something built or standing in it -- Generate Build Floor is unavailable until it's clear."))

/obj/structure/machinery/computer/ship_commissioning/proc/_clear_envelope_preview()
	QDEL_LIST(envelope_indicators)

/// TRUE if any tile in the envelope is neither open space nor genuinely
/// empty floor -- a dense turf (wall), a dense or loose object, or a mob
/// (dead or alive) all count. The beacon's own tile and this console's own
/// tile (if it happens to sit inside the envelope) are never a conflict --
/// same exclusion _drydockCommissionRun()'s own capture pass uses -- and
/// /obj/effect instances (indicators, landmarks) don't count either, since
/// they're not real placed structures.
/obj/structure/machinery/computer/ship_commissioning/proc/_envelope_generate_conflict(list/turf/envelope, obj/structure/machinery/docking_beacon/beacon)
	for(var/turf/T in envelope)
		if(T == get_turf(beacon) || T == get_turf(src))
			continue
		if(isspaceturf(T) || isopenspace(T))
			continue // open space -- exactly what Generate is meant to fill in
		if(T.density)
			return TRUE
		for(var/atom/movable/M in T)
			if(istype(M, /obj/effect))
				continue
			return TRUE // something is already built or standing here
	return FALSE

/// Fills every currently-open-space tile in the envelope with plain
/// plating -- an unfinished subfloor, not a finished floor, so the sealed-
/// hull check at commission time still requires the player to actually
/// wall it in. Never touches a tile that already has anything on it (walls,
/// objects, mobs) or that's already ordinary floor -- re-verifies the
/// conflict check fresh here rather than trusting whatever the TGUI showed
/// from the last Preview, since the envelope could have changed since then.
/obj/structure/machinery/computer/ship_commissioning/proc/_generate_build_floor(mob/user)
	var/obj/structure/machinery/docking_beacon/beacon = _find_nearby_beacon()
	if(!beacon)
		to_chat(user, SPAN_WARNING("No active docking beacon in range -- place and activate one first."))
		return
	var/turf/corner = _get_envelope_corner(beacon)
	if(!corner)
		to_chat(user, SPAN_WARNING("The build envelope runs off the edge of the map."))
		return
	var/list/turf/envelope = block(corner, locate(corner.x + SUBSHIP_FOOTPRINT_X - 1, corner.y + SUBSHIP_FOOTPRINT_Y - 1, corner.z))
	if(_envelope_generate_conflict(envelope, beacon))
		to_chat(user, SPAN_WARNING("Can't generate a build floor -- something's already built or standing in the envelope. Preview again to see what's blocking it."))
		return
	var/filled = 0
	for(var/turf/T in envelope)
		if(T == get_turf(beacon) || T == get_turf(src))
			continue
		if(isspaceturf(T) || isopenspace(T))
			T.ChangeTurf(/turf/simulated/floor/plating)
			filled++
	to_chat(user, SPAN_GOOD("Build floor generated -- [filled] tile[filled == 1 ? "" : "s"] filled in. Wall it in and build your hull."))
