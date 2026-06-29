/*
 * Player-Built Shuttle System
 *
 * Flow:
 *   1. Player builds a hull (walls + floors) in some area
 *   2. Player places a Shuttle Core inside the hull
 *   3. Player places Docking Beacons at desired destinations
 *   4. Player activates the Shuttle Core → hull scanned, shuttle registered
 *   5. Player uses the Flight Console (inside hull) to travel to any beacon
 *
 * Key technical approach:
 *   /datum/shuttle/player_built stores hull turfs by position (not by area),
 *   and overrides attempt_move() to build the turf translation from that list.
 *   This avoids needing to reassign turfs to new areas at runtime.
 */

// ============================================================
// Player shuttle datum
// ============================================================

/datum/shuttle/player_built
	defer_initialisation = TRUE  // Not initialized by SSshuttle from map
	var/list/hull_turfs = list() // In-memory list of turf references that move
	var/owner_ckey = ""
	var/faction_uid = ""

/datum/shuttle/player_built/New(_name, obj/effect/shuttle_landmark/initial_location, list/turfs)
	// Skip parent's shuttle_area validation — we use hull_turfs instead
	src.name = _name
	if(turfs && length(turfs))
		hull_turfs = turfs

	if(initial_location)
		current_location = initial_location
	else if(istext(current_location))
		current_location = SSshuttle.get_landmark(current_location)
	if(!istype(current_location))
		CRASH("Player shuttle \"[name]\" could not find its starting location.")

	if(src.name in SSshuttle.shuttles)
		CRASH("A player shuttle with name '[name]' is already registered.")
	SSshuttle.shuttles[src.name] = src

	shuttle_area = list()  // kept empty — movement uses hull_turfs

/datum/shuttle/player_built/Destroy()
	SSshuttle.shuttles -= src.name
	SSshuttle.process_shuttles -= src
	. = ..()

/datum/shuttle/player_built/attempt_move(obj/effect/shuttle_landmark/destination)
	if(current_location == destination)
		return FALSE
	if(!destination.is_valid(src))
		return FALSE
	if(current_location.cannot_depart(src))
		return FALSE

	// Build translation and check for collisions BEFORE moving
	var/list/translation = get_turf_translation(
		get_turf(current_location),
		get_turf(destination),
		hull_turfs
	)

	if(check_collision(list_values(translation)))
		for(var/obj/structure/machinery/computer/shuttle_control/SC in shuttle_computers)
			to_chat(SC.loc, SPAN_WARNING("Cannot dock at [destination.clean_name] — destination is obstructed."))
		return FALSE

	// Check beacon faction restriction
	if(istype(destination, /obj/effect/shuttle_landmark/player_dock))
		var/obj/effect/shuttle_landmark/player_dock/PD = destination
		if(PD.faction_restricted && PD.faction_restricted != faction_uid)
			for(var/obj/structure/machinery/computer/shuttle_control/SC in shuttle_computers)
				to_chat(SC.loc, SPAN_WARNING("Cannot dock at [destination.clean_name] — this port is restricted to [get_faction_name(PD.faction_restricted)]."))
			return FALSE

	var/old_location = current_location
	GLOB.shuttle_pre_move_event.raise_event(src, old_location, destination)
	shuttle_moved(destination, translation)
	GLOB.shuttle_moved_event.raise_event(src, old_location, destination)
	destination.shuttle_arrived(src)
	return TRUE

// ============================================================
// Player docking landmark — supports faction restriction
// ============================================================

/obj/effect/shuttle_landmark/player_dock
	/// If set, only shuttles with matching faction_uid can dock here
	var/faction_restricted = ""
	var/beacon_shackled    = FALSE

// ============================================================
// Global proc: create or restore a player shuttle
// ============================================================

/proc/create_player_shuttle(shuttle_name, list/hull_turfs, turf/home_turf, owner_ckey, faction_uid)
	if(!home_turf || !shuttle_name || !length(hull_turfs))
		return null

	// Create home landmark
	var/obj/effect/shuttle_landmark/home_lm = new /obj/effect/shuttle_landmark(home_turf)
	home_lm.landmark_tag = "[shuttle_name]_home"
	home_lm.name         = "Home ([shuttle_name])"
	home_lm.base_turf    = /turf/simulated/floor/plating

	// Create the shuttle datum
	var/datum/shuttle/player_built/S = new /datum/shuttle/player_built(shuttle_name, home_lm, hull_turfs)
	S.owner_ckey  = owner_ckey || ""
	S.faction_uid = faction_uid || ""

	return S

// ============================================================
// Shuttle Core machine — players place this inside the hull
// ============================================================

/obj/structure/machinery/shuttle_core
	name = "shuttle core"
	desc = "A modular flight core. Install inside a hull, then activate to register the hull as a shuttle."
	icon = 'icons/obj/primitive_computer.dmi'
	density = TRUE
	anchored = TRUE
	use_power = POWER_USE_IDLE
	idle_power_usage = 50

	var/shuttle_name = ""          // assigned on finalization
	var/finalized    = FALSE       // TRUE once shuttle has been registered
	var/max_hull_size = 200        // max tiles in hull scan

/obj/structure/machinery/shuttle_core/Initialize()
	. = ..()
	// Register with persistent objects so the machine itself saves/loads
	if(GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/obj/structure/machinery/shuttle_core/persistent_objects_get_content()
	var/list/content = list()
	content["shuttle_name"] = shuttle_name
	content["finalized"]    = finalized
	return content

/obj/structure/machinery/shuttle_core/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!isnull(content["shuttle_name"])) shuttle_name = content["shuttle_name"]
	if(!isnull(content["finalized"]))    finalized    = !!content["finalized"]

/obj/structure/machinery/shuttle_core/verb/preview_hull()
	set name = "Preview Hull"
	set category = "Object"
	set src in oview(1)

	var/mob/user = usr

	// Flood-fill (same as finalize, no commit)
	var/list/hull = list()
	var/list/frontier = list(get_turf(src))
	var/list/visited = list()
	visited[get_turf(src)] = TRUE

	while(length(frontier) && length(hull) < max_hull_size)
		var/turf/current = frontier[1]
		frontier.Remove(current)
		if(!istype(current, /turf/simulated)) continue
		if(istype(current, /turf/simulated/wall) || istype(current, /turf/simulated/open)) continue
		hull += current
		for(var/direction in list(NORTH, SOUTH, EAST, WEST))
			var/turf/neighbor = get_step(current, direction)
			if(neighbor && !(neighbor in visited))
				visited[neighbor] = TRUE
				frontier += neighbor

	if(!length(hull))
		to_chat(user, SPAN_WARNING("No hull tiles found from this position."))
		return

	// Place shuttle_warning effects on each hull tile
	var/list/warnings = list()
	for(var/turf/T in hull)
		var/obj/effect/shuttle_warning/W = new /obj/effect/shuttle_warning(T)
		warnings += W
	spawn(150) // 15 seconds
		for(var/obj/effect/shuttle_warning/W in warnings)
			if(!QDELETED(W)) qdel(W)

	// Build ASCII grid relative to the shuttle core
	var/turf/anchor = get_turf(src)
	var/min_dx = 0; var/max_dx = 0
	var/min_dy = 0; var/max_dy = 0
	for(var/turf/T in hull)
		var/dx = T.x - anchor.x
		var/dy = T.y - anchor.y
		min_dx = min(min_dx, dx); max_dx = max(max_dx, dx)
		min_dy = min(min_dy, dy); max_dy = max(max_dy, dy)

	var/grid_html = "<pre style='font-family:monospace; font-size:14px; line-height:1.2;'>"
	for(var/row = max_dy; row >= min_dy; row--)
		for(var/col = min_dx; col <= max_dx; col++)
			if(col == 0 && row == 0)
				grid_html += "<span style='color:#FFD700'>&#9733;</span>"  // ★ anchor
				continue
			var/found = FALSE
			for(var/turf/T in hull)
				if(T.x - anchor.x == col && T.y - anchor.y == row)
					found = TRUE; break
			grid_html += found ? "<span style='color:#FF8800'>&#9632;</span>" : "&#xB7;"
		grid_html += "\n"
	grid_html += "</pre>"
	grid_html += "<small>&#9733; = shuttle core (anchor) &nbsp; &#9632; = hull tile<br>"
	grid_html += "Extends: [abs(max_dy)]N [abs(min_dy)]S [abs(max_dx)]E [abs(min_dx)]W &nbsp; Total: [length(hull)] tiles</small>"

	var/datum/browser/win = new(user, "hull_preview", "Hull Preview — [length(hull)] tiles", 380, 260)
	win.set_content("<body style='background:#1a1a1a; color:#ccc; padding:8px;'>[grid_html]</body>")
	win.open()

/obj/structure/machinery/shuttle_core/verb/finalize_shuttle()
	set name = "Finalize Shuttle"
	set category = "Object"
	set src in oview(1)

	if(finalized)
		to_chat(usr, SPAN_WARNING("This shuttle has already been registered. Use the flight console to launch."))
		return

	var/mob/user = usr

	// Prompt for shuttle name
	var/chosen_name = tgui_input_text(user, "Name this shuttle:", "Register Shuttle", "MyShuttle", max_length = 32)
	if(!chosen_name) return

	// Sanitize: lowercase, underscores for spaces
	chosen_name = lowertext(replacetext(trim(chosen_name), " ", "_"))

	// Check uniqueness
	if(chosen_name in SSshuttle.shuttles)
		to_chat(user, SPAN_WARNING("A shuttle named '[chosen_name]' already exists. Choose a different name."))
		return

	// Flood-fill to find hull tiles
	var/list/hull = list()
	var/list/frontier = list(get_turf(src))
	var/list/visited = list()
	visited[get_turf(src)] = TRUE

	while(length(frontier) && length(hull) < max_hull_size)
		var/turf/current = frontier[1]
		frontier.Remove(current)

		if(!istype(current, /turf/simulated))
			continue
		if(istype(current, /turf/simulated/wall) || istype(current, /turf/simulated/open))
			continue

		hull += current

		for(var/direction in list(NORTH, SOUTH, EAST, WEST))
			var/turf/neighbor = get_step(current, direction)
			if(neighbor && !(neighbor in visited))
				visited[neighbor] = TRUE
				frontier += neighbor

	if(!length(hull))
		to_chat(user, SPAN_WARNING("No valid hull tiles found. Build a floor inside the hull first."))
		return

	if(length(hull) >= max_hull_size)
		to_chat(user, SPAN_WARNING("Hull is too large ([max_hull_size]+ tiles). Reduce the size."))
		return

	// Confirm
	var/confirm = tgui_alert(user, "Register shuttle '[chosen_name]' with [length(hull)] hull tiles?", "Confirm", list("Register", "Cancel"))
	if(confirm != "Register") return

	// Create the shuttle
	var/datum/shuttle/player_built/S = create_player_shuttle(chosen_name, hull, get_turf(src), user.ckey,
		user.GetIdCard() ? user.GetIdCard().employer_faction : null)
	if(!S)
		to_chat(user, SPAN_WARNING("Failed to register shuttle. Check that this location is valid."))
		return

	shuttle_name = chosen_name
	finalized    = TRUE

	// Save to DB
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/list/pos_list = list()
		for(var/turf/T in hull)
			pos_list += "[T.x],[T.y],[T.z]"
		var/hull_json = json_encode(pos_list)
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT INTO ss13_player_shuttles
			(shuttle_name, owner_ckey, faction_uid, home_x, home_y, home_z, hull_json)
			VALUES (:name, :ckey, :faction, :hx, :hy, :hz, :hull)
			ON DUPLICATE KEY UPDATE hull_json=VALUES(hull_json)"},
			list("name"    = chosen_name,
			     "ckey"    = user.ckey,
			     "faction" = S.faction_uid,
			     "hx"      = x, "hy" = y, "hz" = z,
			     "hull"    = hull_json)
		)
		q.Execute()
		qdel(q)

	to_chat(user, SPAN_GOOD("Shuttle '[chosen_name]' registered with [length(hull)] tiles! Place a flight console inside the hull and set its shuttle_tag to '[chosen_name]'."))
	log_game("[key_name(user)] registered player shuttle '[chosen_name]' at ([x],[y],[z]) with [length(hull)] hull tiles.")

// ============================================================
// Docking Beacon — players place at desired destinations
// ============================================================

/obj/structure/machinery/docking_beacon
	name = "docking beacon"
	desc = "Wrench to secure, then use a screwdriver to activate the docking port. Shuttles can navigate to any active beacon."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "pad-idle"
	density = TRUE
	anchored = FALSE  // starts unanchored — won't register while in a crate or being carried
	use_power = POWER_USE_IDLE
	idle_power_usage = 10

	var/landmark_tag  = ""
	var/dock_label    = ""
	var/landmark_registered = FALSE
	var/beacon_active = FALSE       // TRUE only after screwdriver activation
	var/faction_restricted = ""     // "" = public; faction UID = restricted
	var/beacon_shackled    = FALSE  // TRUE when claimed by a faction

/obj/structure/machinery/docking_beacon/Initialize()
	. = ..()
	// Restore anchored+active beacons on restart (placed by shuttleStateRestore)
	if(anchored && beacon_active)
		landmark_tag = "dock_[x]_[y]_[z]"
		_register_landmark()
	// Register with persistent objects so the machine itself saves/loads
	if(GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/obj/structure/machinery/docking_beacon/persistent_objects_get_content()
	var/list/content = list()
	content["dock_label"]        = dock_label
	content["beacon_active"]     = beacon_active
	content["faction_restricted"] = faction_restricted
	content["beacon_shackled"]   = beacon_shackled
	return content

/obj/structure/machinery/docking_beacon/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!isnull(content["dock_label"]))         dock_label         = content["dock_label"]
	if(!isnull(content["beacon_active"]))      beacon_active      = !!content["beacon_active"]
	if(!isnull(content["faction_restricted"])) faction_restricted = content["faction_restricted"]
	if(!isnull(content["beacon_shackled"]))    beacon_shackled    = !!content["beacon_shackled"]
	var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L)
		if(dock_label) L.name = dock_label
		L.faction_restricted = faction_restricted
		L.beacon_shackled    = beacon_shackled

/obj/structure/machinery/docking_beacon/attackby(obj/item/attacking_item, mob/user, params)
	// Faction ID swipe — claim or release beacon (same pattern as cryopods/telepads)
	if(istype(attacking_item, /obj/item/card/id) && beacon_active)
		var/obj/item/card/id/I = attacking_item
		if(!I.employer_faction)
			to_chat(user, SPAN_WARNING("Your ID is not issued by a faction."))
			return TRUE

		var/card_faction = I.employer_faction

		if(beacon_shackled && faction_restricted != card_faction)
			to_chat(user, SPAN_WARNING("This beacon is claimed by [get_faction_name(faction_restricted)]. Only their officers can release it."))
			return TRUE

		if(beacon_shackled && faction_restricted == card_faction)
			// Release — requires officer+
			var/list/member = get_faction_member(user.ckey, card_faction)
			var/rank = member ? (member["rank"] || 0) : -1
			if(rank < 1 && !check_rights(R_ADMIN, 0, user))
				to_chat(user, SPAN_WARNING("You need officer rank in [get_faction_name(card_faction)] to release this beacon."))
				return TRUE
			var/confirm = tgui_alert(user, "Make this beacon public? Any shuttle will be able to dock here.", "Release Beacon", list("Release", "Cancel"))
			if(confirm != "Release") return TRUE
			faction_restricted = ""
			beacon_shackled    = FALSE
			var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
			if(L) { L.faction_restricted = ""; L.beacon_shackled = FALSE }
			to_chat(user, SPAN_GOOD("Beacon is now public — any shuttle can dock here."))
			return TRUE

		// Unclaimed — restrict to this faction (officer+)
		var/list/member = get_faction_member(user.ckey, card_faction)
		var/rank = member ? (member["rank"] || 0) : -1
		if(rank < 1 && !check_rights(R_ADMIN, 0, user))
			to_chat(user, SPAN_WARNING("You need officer rank in [get_faction_name(card_faction)] to restrict this beacon."))
			return TRUE
		var/confirm = tgui_alert(user, "Restrict this beacon to [get_faction_name(card_faction)] shuttles only?", "Restrict Beacon", list("Restrict", "Cancel"))
		if(confirm != "Restrict") return TRUE
		faction_restricted = card_faction
		beacon_shackled    = TRUE
		var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
		if(L) { L.faction_restricted = card_faction; L.beacon_shackled = TRUE }
		to_chat(user, SPAN_GOOD("Beacon restricted to [get_faction_name(card_faction)] shuttles."))
		return TRUE

	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		if(beacon_active)
			to_chat(user, SPAN_WARNING("Deactivate the beacon with a screwdriver before moving it."))
			return TRUE
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Docking beacon secured in place. Use a screwdriver to activate it.") : SPAN_NOTICE("Docking beacon unsecured."))
		return TRUE

	if(attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
		attacking_item.play_tool_sound(get_turf(src), 50)
		if(!anchored)
			to_chat(user, SPAN_WARNING("Secure the beacon with a wrench before activating it."))
			return TRUE
		if(beacon_active)
			// Deactivate
			beacon_active = FALSE
			var/obj/effect/shuttle_landmark/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
			if(L) qdel(L)
			landmark_registered = FALSE
			to_chat(user, SPAN_NOTICE("Docking beacon deactivated. It is no longer a shuttle destination."))
		else
			// Activate — prompt for label
			var/new_label = tgui_input_text(user, "Name this docking port (shown in flight consoles):", "Activate Beacon", dock_label || "Docking Port", max_length = 64)
			if(!new_label) return TRUE
			dock_label   = new_label
			beacon_active = TRUE
			landmark_tag  = "dock_[x]_[y]_[z]"
			_register_landmark()
			to_chat(user, SPAN_GOOD("Docking beacon activated as '[dock_label]'. Shuttles can now dock here."))
		return TRUE

	return ..(attacking_item, user, params)

/obj/structure/machinery/docking_beacon/persistent_objects_get_content()
	var/list/content = list()
	content["dock_label"] = dock_label
	return content

/obj/structure/machinery/docking_beacon/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!isnull(content["dock_label"])) dock_label = content["dock_label"]
	// Update landmark name if it already exists
	var/obj/effect/shuttle_landmark/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L && dock_label) L.name = dock_label

/obj/structure/machinery/docking_beacon/proc/_register_landmark()
	if(landmark_registered) return
	// If shuttleStateRestore already created this landmark, just claim it
	if(SSshuttle.registered_shuttle_landmarks[landmark_tag])
		landmark_registered = TRUE
		return
	// Create faction-aware player dock landmark
	var/obj/effect/shuttle_landmark/player_dock/L = new /obj/effect/shuttle_landmark/player_dock(get_turf(src))
	L.landmark_tag       = landmark_tag
	L.name               = dock_label ? dock_label : "Docking Port ([x],[y],[z])"
	L.base_turf          = /turf/simulated/floor/plating
	L.faction_restricted = faction_restricted
	L.beacon_shackled    = beacon_shackled
	landmark_registered = TRUE
	// Save to DB if not already there
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT IGNORE INTO ss13_player_docking_beacons (landmark_tag, x, y, z, label)
			VALUES (:tag, :x, :y, :z, :label)"},
			list("tag" = landmark_tag, "x" = x, "y" = y, "z" = z, "label" = dock_label)
		)
		q.Execute()
		qdel(q)

/obj/structure/machinery/docking_beacon/verb/set_dock_label()
	set name = "Set Dock Name"
	set category = "Object"
	set src in oview(1)

	var/new_label = tgui_input_text(usr, "Set a name for this docking port:", "Dock Name", dock_label, max_length = 64)
	if(!new_label) return
	dock_label = new_label
	// Update the landmark name
	var/obj/effect/shuttle_landmark/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L) L.name = dock_label
	// Update DB
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/q = SSdbcore.NewQuery(
			"UPDATE ss13_player_docking_beacons SET label = :label WHERE landmark_tag = :tag",
			list("label" = dock_label, "tag" = landmark_tag)
		)
		q.Execute()
		qdel(q)
	to_chat(usr, SPAN_NOTICE("Docking port renamed to '[dock_label]'."))

/obj/structure/machinery/docking_beacon/Destroy()
	// Remove landmark and DB entry when beacon is deconstructed
	var/obj/effect/shuttle_landmark/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L) qdel(L)
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_player_docking_beacons WHERE landmark_tag = :tag",
			list("tag" = landmark_tag)
		)
		q.Execute()
		qdel(q)
	return ..()
