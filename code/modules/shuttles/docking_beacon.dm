/*
 * Docking Beacon
 *
 * Drydock is a buy/stash/retrieve system for real Aurora ships (the same
 * ship/landable + /datum/shuttle/autodock/overmap family faction corvettes
 * use -- see persistence_corvettes.dm and persistence_shuttles.dm for the
 * actual ledger/materialization engine). This file's only job is the
 * docking beacon itself: a portable, wrench+screwdriver-activated machine
 * that registers a real navigation landmark any ship's own
 * shuttle_control/explore console can already discover and fly to
 * (get_possible_destinations(), overmap_shuttle.dm) -- the same mechanism
 * exoplanet landing already uses. It is the only way a player can create a
 * landable destination somewhere with no pre-existing mapped landmark
 * (an away site's own landmarks, and every landable ship's own built-in
 * FORE/PORT/AFT/STARBOARD visiting slots, cover docking to those locations
 * specifically -- a beacon is for anywhere else). Drydock retrieve/stash
 * themselves are sector-relative and don't depend on this at all; a beacon
 * only matters to ships actually flying and landing under their own power.
 */

// ============================================================
// Player docking landmark — supports faction restriction
// ============================================================

/obj/effect/shuttle_landmark/player_dock
	/// If set, only ships belonging to this faction can dock here.
	var/faction_restricted = ""
	var/beacon_shackled    = FALSE
	/// 0 = unrestricted. Otherwise the max hull footprint (tiles) a shuttle
	/// may have to dock here -- see /datum/shuttle/proc/get_footprint(),
	/// shuttle.dm. Lets a beacon placed at a player-built cycler's airlock
	/// (or a mapped hangar berth, drydock_ship.dm) restrict itself to
	/// SUBSHIP_FOOTPRINT_X/Y-sized craft so an oversized ship never sees it
	/// as a valid destination in the first place.
	var/max_footprint_x = 0
	var/max_footprint_y = 0

/// Registered into a sector's generic_waypoints (see docking_beacon's
/// _register_landmark()/_deregister_landmark()) so any ship's own
/// navigation console already discovers this landmark for free -- the
/// faction gate lives here instead of restricted_waypoints (which is
/// keyed by a single exact shuttle name, not a faction) so it applies to
/// every ship of the right faction uniformly.
/obj/effect/shuttle_landmark/player_dock/is_valid(datum/shuttle/shuttle)
	. = ..()
	if(!.)
		return FALSE
	if(max_footprint_x || max_footprint_y)
		var/list/footprint = shuttle.get_footprint()
		if(max_footprint_x && footprint[1] > max_footprint_x)
			return FALSE
		if(max_footprint_y && footprint[2] > max_footprint_y)
			return FALSE
	// Entirely opt-in -- a ship carrying no docking_transponder at all skips
	// this check completely and docks here exactly like it always could.
	// One that DOES carry one must face the exact opposite direction from
	// this beacon, same as two real airlocks meeting (docking_transponder.dm).
	var/obj/structure/machinery/docking_transponder/transponder = shuttle.find_docking_transponder()
	if(istype(transponder) && turn(transponder.dir, 180) != dir)
		return FALSE
	if(!faction_restricted)
		return
	var/shuttle_faction
	if(istype(shuttle, /datum/shuttle/autodock/overmap/drydock_ship))
		var/datum/shuttle/autodock/overmap/drydock_ship/DS = shuttle
		shuttle_faction = DS.faction_uid
	if(faction_restricted != shuttle_faction)
		return FALSE

/// A public, size-gated proxy standing in for a sub-ship's own mapped home
/// landmark (Xanu Fighter's "xanufrigate_hangar", etc.) -- see
/// _drydock_register_subship_waypoints() (persistence_shuttles.dm/Part 5).
/// The real home landmark stays exactly as it is (whatever type it was
/// mapped as, still restricted to its own bound sub-ship's name for the
/// "return to hangar" waypoint) -- this sits at the same turf and is
/// registered as a normal generic waypoint instead, so any appropriately
/// sized outside ship can find and dock there too, but only while the
/// bound sub-ship isn't physically sitting there right now.
/obj/effect/shuttle_landmark/player_dock/hangar_slot
	/// The sub-ship this slot shadows.
	var/datum/shuttle/bound_sub_shuttle
	/// The real, mapped-in home landmark this slot sits on top of --
	/// occupied (and therefore invalid) exactly when bound_sub_shuttle is
	/// currently parked there.
	var/obj/effect/shuttle_landmark/real_home

/obj/effect/shuttle_landmark/player_dock/hangar_slot/is_valid(datum/shuttle/shuttle)
	. = ..()
	if(!.)
		return FALSE
	if(bound_sub_shuttle && real_home && bound_sub_shuttle.current_location == real_home)
		return FALSE

// ============================================================
// Docking Beacon — players place at desired destinations
// ============================================================

/obj/structure/machinery/docking_beacon
	name = "docking beacon"
	desc = "Wrench to secure, then use a screwdriver to activate the docking port. Shuttle- and sub-ship-sized craft can navigate to any active beacon -- full-size drydock ships are too large to dock here."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "pad-idle"
	// Flush with the floor, same as docking_transponder.dm -- meant to be
	// mounted right at an airlock cycler's exterior door, and must not stop
	// that door opening or closing over it.
	density = FALSE
	layer = ABOVE_TILE_LAYER
	anchored = FALSE  // starts unanchored — won't register while in a crate or being carried
	use_power = POWER_USE_IDLE
	idle_power_usage = 10
	// A ship's own hull can legally materialize directly on top of an active
	// beacon's turf (check_collision(), landmarks.dm, only checks turf
	// density, never object density) -- shuttle_moved() (shuttle.dm) then
	// qdel()s any simulated, non-living object on that turf when the
	// landing ship squishes (the default for every ship here). Matching
	// /obj/effect/shuttle_landmark's own simulated = 0 (landmarks.dm) is
	// what keeps the landmark itself alive through the exact same pass --
	// the beacon machine needs the same protection.
	simulated = FALSE

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
	// Initialize() already ran and decided against registering a landmark
	// (beacon_active was still the default FALSE at that point) -- this is
	// the only remaining chance to do it, now that the real saved value has
	// been restored. _register_landmark() is idempotent and will just claim
	// a landmark shuttleStateRestore() already created, if any.
	if(beacon_active && !landmark_registered)
		landmark_tag = "dock_[x]_[y]_[z]"
		_register_landmark()
	var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L)
		if(dock_label) L.name = dock_label
		_sync_landmark_faction()
		// dir itself is restored generically (the __dir/__anchored handling
		// in objectsApplyTrackContent(), persistence_objects.dm) by the time
		// this runs -- push the now-correct value onto the landmark too, in
		// case _register_landmark() above created it before that happened.
		_sync_landmark_facing()

/obj/structure/machinery/docking_beacon/attackby(obj/item/attacking_item, mob/user, params)
	// Rotates the beacon's own facing (and, live, its registered landmark's --
	// _sync_landmark_facing() below) -- what player_dock/is_valid() actually
	// compares a docking_transponder's facing against. Only while unsecured --
	// wrench it down to lock the facing in, same as the transponder's own
	// multitool rotate (docking_transponder.dm).
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		if(anchored)
			to_chat(user, SPAN_WARNING("\The [src] is secured in place -- unwrench it before changing its facing."))
			return TRUE
		dir = turn(dir, -90)
		_sync_landmark_facing()
		to_chat(user, SPAN_NOTICE("You rotate \the [src] -- it now faces [dir2text(dir)]."))
		return TRUE
	// Faction ID swipe — claim or release beacon (same pattern as cryopods/telepads)
	if(istype(attacking_item, /obj/item/card/id) && beacon_active)
		var/obj/item/card/id/I = attacking_item
		if(!I.employer_faction)
			to_chat(user, SPAN_WARNING("Your ID is not issued by a faction."))
			log_drydock_warning("docking_beacon/attackby: refused -- [key_name(user)] swiped a non-faction ID at beacon '[landmark_tag]'.")
			return TRUE

		var/card_faction = I.employer_faction

		if(beacon_shackled && faction_restricted != card_faction)
			to_chat(user, SPAN_WARNING("This beacon is claimed by [get_faction_name(faction_restricted)]. Only their officers can release it."))
			log_drydock_warning("docking_beacon/attackby: refused -- [key_name(user)] (faction [card_faction]) tried to use beacon '[landmark_tag]' claimed by [faction_restricted].")
			return TRUE

		if(beacon_shackled && faction_restricted == card_faction)
			// Release — requires officer+
			var/list/member = get_faction_member(user.ckey, card_faction)
			var/rank = member ? (member["rank"] || 0) : -1
			if(rank < 1 && !check_rights(R_ADMIN, 0, user))
				to_chat(user, SPAN_WARNING("You need officer rank in [get_faction_name(card_faction)] to release this beacon."))
				log_drydock_warning("docking_beacon/attackby: refused release -- [key_name(user)] lacks officer rank in [card_faction] for beacon '[landmark_tag]'.")
				return TRUE
			var/confirm = tgui_alert(user, "Make this beacon public? Any shuttle will be able to dock here.", "Release Beacon", list("Release", "Cancel"))
			if(confirm != "Release") return TRUE
			faction_restricted = ""
			beacon_shackled    = FALSE
			_sync_landmark_faction()
			to_chat(user, SPAN_GOOD("Beacon is now public — any shuttle can dock here."))
			log_drydock("docking_beacon/attackby: [key_name(user)] released beacon '[landmark_tag]' from faction [card_faction] -- now public.")
			return TRUE

		// Unclaimed — restrict to this faction (officer+)
		var/list/member = get_faction_member(user.ckey, card_faction)
		var/rank = member ? (member["rank"] || 0) : -1
		if(rank < 1 && !check_rights(R_ADMIN, 0, user))
			to_chat(user, SPAN_WARNING("You need officer rank in [get_faction_name(card_faction)] to restrict this beacon."))
			log_drydock_warning("docking_beacon/attackby: refused restrict -- [key_name(user)] lacks officer rank in [card_faction] for beacon '[landmark_tag]'.")
			return TRUE
		var/confirm = tgui_alert(user, "Restrict this beacon to [get_faction_name(card_faction)] shuttles only?", "Restrict Beacon", list("Restrict", "Cancel"))
		if(confirm != "Restrict") return TRUE
		faction_restricted = card_faction
		beacon_shackled    = TRUE
		_sync_landmark_faction()
		to_chat(user, SPAN_GOOD("Beacon restricted to [get_faction_name(card_faction)] shuttles."))
		log_drydock("docking_beacon/attackby: [key_name(user)] restricted beacon '[landmark_tag]' to faction [card_faction].")
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
			_deregister_landmark()
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

/// Pushes faction_restricted/beacon_shackled from the beacon machine onto
/// its live registered landmark (if any) -- used by both the ID-swipe
/// claim/release flow above and the faction tagger hooks (see
/// persistence_faction_tagger.dm).
/obj/structure/machinery/docking_beacon/proc/_sync_landmark_faction()
	var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L)
		L.faction_restricted = faction_restricted
		L.beacon_shackled    = beacon_shackled

/// Pushes this beacon's own dir onto its live registered landmark -- the
/// landmark (not the beacon machine) is what player_dock/is_valid() actually
/// checks a docking_transponder's facing against, so a multitool rotation
/// has to propagate here to have any effect. Same pattern as
/// _sync_landmark_faction() above.
/obj/structure/machinery/docking_beacon/proc/_sync_landmark_facing()
	var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L)
		L.dir = dir

/obj/structure/machinery/docking_beacon/proc/_register_landmark()
	if(landmark_registered) return
	// If shuttleStateRestore already created this landmark, just claim it
	if(SSshuttle.registered_shuttle_landmarks[landmark_tag])
		landmark_registered = TRUE
		var/obj/effect/shuttle_landmark/player_dock/existing = SSshuttle.registered_shuttle_landmarks[landmark_tag]
		_add_to_sector_waypoints(existing)
		log_drydock("docking_beacon/_register_landmark: '[landmark_tag]' claimed pre-existing landmark (restored by shuttleStateRestore) at ([x],[y],[z]).")
		return
	// Create faction-aware player dock landmark
	var/obj/effect/shuttle_landmark/player_dock/L = new /obj/effect/shuttle_landmark/player_dock(get_turf(src))
	L.landmark_tag       = landmark_tag
	L.name               = dock_label ? dock_label : "Docking Port ([x],[y],[z])"
	L.base_turf          = /turf/simulated/floor/plating
	L.faction_restricted = faction_restricted
	L.beacon_shackled    = beacon_shackled
	L.dir                = dir
	// Unconditional -- a docking beacon is reserved for shuttle/sub-ship
	// sized craft only (SUBSHIP_FOOTPRINT_X/Y, overmap.dm), not a general-
	// purpose dock for full-size drydock ships. Docking is real physical
	// relocation (attempt_move()/shuttle_moved(), shuttle.dm -- see Part 8,
	// even-when-they-are-federated-hopcroft.md), not an abstract marker
	// visit, so a full-size hull's real turfs simply can't fit materializing
	// at a small cycler pad.
	L.max_footprint_x    = SUBSHIP_FOOTPRINT_X
	L.max_footprint_y    = SUBSHIP_FOOTPRINT_Y
	landmark_registered = TRUE
	_add_to_sector_waypoints(L)
	log_drydock("docking_beacon/_register_landmark: '[landmark_tag]' created new landmark at ([x],[y],[z]), faction_restricted=[faction_restricted || "none"].")
	// Save to DB if not already there -- skipped entirely on a
	// persistence-excluded Z (e.g. a dynamic, unpinned away site) so no row
	// ever gets written that a future boot's Z-reshuffle could later
	// misinterpret as pointing somewhere else entirely. Mirrors
	// objectsFinalize()'s own write-time exclusion check for the beacon
	// machine's tracked-object row (persistence_objects.dm).
	if(GLOB.config.sql_enabled && SSdbcore.Connect() && !persistence_z_excluded(z))
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT IGNORE INTO ss13_player_docking_beacons (landmark_tag, x, y, z, label)
			VALUES (:tag, :x, :y, :z, :label)"},
			list("tag" = landmark_tag, "x" = x, "y" = y, "z" = z, "label" = dock_label)
		)
		q.Execute()
		if(!SSpersistence.databaseCheckQueryResult(q, "docking_beacon register_landmark insert"))
			log_drydock_error("docking_beacon/_register_landmark: DB insert failed for '[landmark_tag]'.")
		qdel(q)

/// Adds the landmark to its own Z's overmap sector generic waypoint list --
/// this is what makes it discoverable by get_possible_destinations() on any
/// ship's own navigation console (overmap_shuttle.dm), same as any other
/// registered nav point. Faction gating happens at is_valid() (above), not
/// here -- generic_waypoints, not restricted_waypoints, since
/// restricted_waypoints is keyed by one exact shuttle name, not a faction.
/obj/structure/machinery/docking_beacon/proc/_add_to_sector_waypoints(obj/effect/shuttle_landmark/player_dock/L)
	var/obj/effect/overmap/visitable/sector = GLOB.map_sectors["[z]"]
	if(sector)
		sector.add_landmark(L, null)

/obj/structure/machinery/docking_beacon/proc/_deregister_landmark()
	var/obj/effect/shuttle_landmark/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L)
		var/obj/effect/overmap/visitable/sector = GLOB.map_sectors["[GET_Z(L)]"]
		if(sector)
			sector.remove_landmark(L, null)
		qdel(L)
	landmark_registered = FALSE

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
	// Remove landmark (deregistering from its sector's waypoints first) and
	// DB entry when beacon is deconstructed
	_deregister_landmark()
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_player_docking_beacons WHERE landmark_tag = :tag",
			list("tag" = landmark_tag)
		)
		q.Execute()
		qdel(q)
	return ..()
