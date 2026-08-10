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
	/// 0 = unrestricted, and falls through to max_footprint_x/y above
	/// unchanged. When set, REPLACES (not adds to) the generic check above
	/// for a player-built ship specifically -- a template ship docking at
	/// this same beacon is entirely unaffected by this pair either way.
	/// Configured per-beacon via multitool (docking_beacon.dm's attackby()).
	var/max_player_built_footprint_x = 0
	var/max_player_built_footprint_y = 0

/// Registered into a sector's generic_waypoints (see docking_beacon's
/// _register_landmark()/_deregister_landmark()) so any ship's own
/// navigation console already discovers this landmark for free -- the
/// faction gate lives here instead of restricted_waypoints (which is
/// keyed by a single exact shuttle name, not a faction) so it applies to
/// every ship of the right faction uniformly.
/// reason_out/check_objects -- see the base is_valid()'s own doc comment
/// (landmarks.dm).
/obj/effect/shuttle_landmark/player_dock/is_valid(datum/shuttle/shuttle, list/reason_out, check_objects = TRUE)
	. = ..(shuttle, reason_out, check_objects)
	if(!.)
		return FALSE
	// A player-built ship checks against this beacon's own player-built-
	// specific max instead of the generic one below, if one's been set --
	// a template ship never looks at max_player_built_footprint_x/y at all,
	// so configuring it here can never change how templates dock anywhere.
	var/is_player_built = istype(shuttle, /datum/shuttle/autodock/overmap/drydock_ship) && shuttle:player_built
	var/check_x = max_footprint_x
	var/check_y = max_footprint_y
	if(is_player_built && (max_player_built_footprint_x || max_player_built_footprint_y))
		check_x = max_player_built_footprint_x
		check_y = max_player_built_footprint_y
	if(check_x || check_y)
		var/list/footprint = shuttle.get_footprint()
		if((check_x && footprint[1] > check_x) || (check_y && footprint[2] > check_y))
			if(reason_out)
				reason_out += is_player_built \
					? "Your player built ship cannot dock due to being larger than acceptable parameters (hull [footprint[1]]x[footprint[2]], max [check_x]x[check_y])." \
					: "hull footprint [footprint[1]]x[footprint[2]] exceeds this beacon's max [check_x]x[check_y]"
			return FALSE
	// Entirely opt-in -- a ship carrying no docking_transponder at all skips
	// this check completely and docks here exactly like it always could.
	// One that DOES carry one must face the exact opposite direction from
	// this beacon, same as two real airlocks meeting (docking_transponder.dm).
	var/obj/structure/machinery/docking_transponder/transponder = shuttle.find_docking_transponder()
	if(istype(transponder) && turn(transponder.dir, 180) != dir)
		if(reason_out)
			reason_out += "docking transponder faces [dir2text(transponder.dir)] (needs [dir2text(turn(dir, 180))] to meet this beacon's [dir2text(dir)] facing)"
		return FALSE
	var/shuttle_faction
	if(istype(shuttle, /datum/shuttle/autodock/overmap/drydock_ship))
		var/datum/shuttle/autodock/overmap/drydock_ship/DS = shuttle
		shuttle_faction = DS.faction_uid
	else
		// A bound sub-ship (Xanu Fighter/Boarder, etc.) never carries its own
		// faction_uid -- resolve it through whichever mothership currently
		// claims it instead, or this would always read as "no faction" and
		// get blocked below from docking anywhere claimed, even its own
		// faction's own territory. See _drydock_sub_shuttle_owner_faction()'s
		// own doc comment (persistence_shuttles.dm).
		shuttle_faction = _drydock_sub_shuttle_owner_faction(shuttle.name)
	// Independent of this beacon's own opt-in faction_restricted claim below
	// -- this checks whether the Z it sits on is itself someone else's
	// claimed territory (a real /obj/structure/machinery/faction_beacon,
	// GLOB.faction_beacon_by_z) with raiding currently disabled, same gate
	// telepad/personal travel already enforce for a mob walking in
	// (_faction_raid_blocked_for(), telepad_drydock_boarding.dm) -- a
	// public/unrestricted docking_beacon can still sit on claimed ground.
	if(_faction_raid_blocked_for(z, shuttle_faction))
		if(reason_out)
			reason_out += "this z is claimed territory and faction raiding is currently disabled"
		return FALSE
	if(!faction_restricted)
		return
	if(faction_restricted != shuttle_faction)
		if(reason_out)
			reason_out += "beacon is restricted to [get_faction_name(faction_restricted)], this shuttle belongs to [shuttle_faction ? get_faction_name(shuttle_faction) : "no faction"]"
		return FALSE

/// A public, size-gated proxy standing in for a sub-ship's own mapped home
/// landmark (Xanu Fighter's "xanufrigate_hangar", etc.) -- see
/// _drydock_register_subship_waypoints() (persistence_shuttles.dm).
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

/obj/effect/shuttle_landmark/player_dock/hangar_slot/is_valid(datum/shuttle/shuttle, list/reason_out, check_objects = TRUE)
	. = ..(shuttle, reason_out, check_objects)
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
	// Same holopad sprite docking_transponder.dm reuses, tinted green instead
	// of the transponder's dark blackish-orange -- visually pairs the two
	// devices as "one system, two ends" at a glance.
	icon = 'icons/obj/holopad.dmi'
	icon_state = "holopad0"
	color = "#008000"
	// Flush with the floor, same as docking_transponder.dm -- meant to be
	// mounted right at an airlock cycler's exterior door, and must not stop
	// that door opening or closing over it.
	density = FALSE
	layer = ABOVE_TILE_LAYER
	anchored = FALSE  // starts unanchored — won't register while in a crate or being carried
	use_power = POWER_USE_IDLE
	idle_power_usage = 10
	// A ship's own hull is meant to materialize directly on top of an active
	// beacon's turf (that's the point of docking at one) -- density = FALSE
	// means it never trips check_collision()'s dense/anchored-object refusal
	// (landmarks.dm) either way, but shuttle_moved() (shuttle.dm) still
	// qdel()s any simulated, non-living object on a landing turf regardless
	// of density when the ship squishes onto it. Matching
	// /obj/effect/shuttle_landmark's own simulated = 0 (landmarks.dm) is
	// what keeps the landmark itself alive through that same pass -- the
	// beacon machine needs the same protection.
	simulated = FALSE

	var/landmark_tag  = ""
	var/dock_label    = ""
	var/landmark_registered = FALSE
	var/beacon_active = FALSE       // TRUE only after screwdriver activation
	var/faction_restricted = ""     // "" = public; faction UID = restricted
	var/beacon_shackled    = FALSE  // TRUE when claimed by a faction
	/// Source of truth for the registered landmark's own
	/// max_player_built_footprint_x/y (see _sync_landmark_player_built_footprint()
	/// below) -- set via multitool. 0 = unrestricted.
	var/max_player_built_footprint_x = 0
	var/max_player_built_footprint_y = 0

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
	content["max_player_built_footprint_x"] = max_player_built_footprint_x
	content["max_player_built_footprint_y"] = max_player_built_footprint_y
	return content

/obj/structure/machinery/docking_beacon/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!isnull(content["dock_label"]))         dock_label         = content["dock_label"]
	if(!isnull(content["beacon_active"]))      beacon_active      = !!content["beacon_active"]
	if(!isnull(content["faction_restricted"])) faction_restricted = content["faction_restricted"]
	if(!isnull(content["beacon_shackled"]))    beacon_shackled    = !!content["beacon_shackled"]
	if(!isnull(content["max_player_built_footprint_x"])) max_player_built_footprint_x = content["max_player_built_footprint_x"]
	if(!isnull(content["max_player_built_footprint_y"])) max_player_built_footprint_y = content["max_player_built_footprint_y"]
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
		_sync_landmark_player_built_footprint()

/obj/structure/machinery/docking_beacon/attackby(obj/item/attacking_item, mob/user, params)
	// Buffer (link this specific beacon into the multitool's own existing
	// device-buffer, multitool.dm -- the same mechanism airlock controller
	// wiring already uses) or Rotate its facing (and, live, its registered
	// landmark's -- _sync_landmark_facing() below) -- what
	// player_dock/is_valid() actually compares a docking_transponder's
	// facing against. Rotate only while unsecured -- wrench it down to lock
	// the facing in, same as the transponder's own multitool rotate
	// (docking_transponder.dm).
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/choice = tgui_alert(user, "Buffer this beacon into the multitool, rotate its facing, or set its max player-built ship size?", "Docking Beacon", list("Buffer", "Rotate", "Set Max Player-Built Size"))
		if(QDELETED(src) || QDELETED(user) || !user.Adjacent(src))
			return TRUE
		if(choice == "Buffer")
			if(!istype(attacking_item, /obj/item/multitool))
				to_chat(user, SPAN_WARNING("\The [attacking_item] can't hold a buffer."))
				return TRUE
			var/obj/item/multitool/tool = attacking_item
			tool.set_buffer(src)
			to_chat(user, SPAN_NOTICE("You buffer \the [src] into \the [tool]."))
			return TRUE
		if(choice == "Rotate")
			if(anchored)
				to_chat(user, SPAN_WARNING("\The [src] is secured in place -- unwrench it before changing its facing."))
				return TRUE
			dir = turn(dir, -90)
			_sync_landmark_facing()
			to_chat(user, SPAN_NOTICE("You rotate \the [src] -- it now faces [dir2text(dir)]."))
			return TRUE
		if(choice == "Set Max Player-Built Size")
			var/new_x = tgui_input_number(user, "Max player-built ship width (X), 0 = unrestricted:", "Docking Beacon", max_player_built_footprint_x, 100, 0)
			if(isnull(new_x))
				return TRUE
			var/new_y = tgui_input_number(user, "Max player-built ship height (Y), 0 = unrestricted:", "Docking Beacon", max_player_built_footprint_y, 100, 0)
			if(isnull(new_y))
				return TRUE
			max_player_built_footprint_x = new_x
			max_player_built_footprint_y = new_y
			_sync_landmark_player_built_footprint()
			to_chat(user, SPAN_NOTICE("Max player-built ship size set to [new_x ? "[new_x]" : "unrestricted"]x[new_y ? "[new_y]" : "unrestricted"]."))
			return TRUE
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

/// Bottom-left corner of the size_x by size_y block extending out from this
/// beacon in whichever direction it currently faces, starting one tile clear
/// of the beacon itself (so the beacon always sits just OUTSIDE the block it
/// defines, like a real dock marker standing clear of the airlock it serves).
///
/// Shared geometry -- the commissioning console's build envelope
/// (_get_envelope_corner(), ship_commissioning_console.dm) and the
/// save-time/admin pad cleanup sweeps (drydockForgetBeaconEnvelopes(),
/// clear_docking_beacons(), persistence_shuttles.dm) all resolve a beacon's
/// footprint through this one proc, so they can never disagree about which
/// tiles belong to a given pad.
/proc/docking_beacon_envelope_corner(obj/structure/machinery/docking_beacon/beacon, size_x, size_y)
	var/turf/center = beacon ? get_turf(beacon) : null
	if(!center)
		return null
	var/half_x = round((size_x - 1) / 2)
	var/half_y = round((size_y - 1) / 2)
	switch(beacon.dir)
		if(WEST)
			return locate(center.x - size_x, center.y - half_y, center.z)
		if(EAST)
			return locate(center.x + 1, center.y - half_y, center.z)
		if(SOUTH)
			return locate(center.x - half_x, center.y - size_y, center.z)
		if(NORTH)
			return locate(center.x - half_x, center.y + 1, center.z)
	// Non-cardinal dir shouldn't be reachable (rotate only ever turns by
	// 90 degrees from a cardinal start) -- fall back to centered rather
	// than error.
	return locate(center.x - half_x, center.y - half_y, center.z)

/// Every turf in this beacon's own landing envelope, sized to the LARGEST
/// hull that could legally dock here (the generic subship cap, or this
/// beacon's own player-built override if it's been configured larger) --
/// so a cleanup sweep over this block always covers whatever actually landed.
/// Null if the beacon isn't on a real turf.
/obj/structure/machinery/docking_beacon/proc/get_envelope_turfs()
	var/size_x = max(SUBSHIP_FOOTPRINT_X, max_player_built_footprint_x)
	var/size_y = max(SUBSHIP_FOOTPRINT_Y, max_player_built_footprint_y)
	var/turf/corner = docking_beacon_envelope_corner(src, size_x, size_y)
	if(!corner)
		return null
	return block(corner, locate(corner.x + size_x - 1, corner.y + size_y - 1, corner.z))

/// Pushes faction_restricted/beacon_shackled from the beacon machine onto
/// its live registered landmark (if any) -- used by both the ID-swipe
/// claim/release flow above and the faction tagger hooks (see
/// persistence_faction_tagger.dm).
/obj/structure/machinery/docking_beacon/proc/_sync_landmark_faction()
	var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L)
		L.faction_restricted = faction_restricted
		L.beacon_shackled    = beacon_shackled

/// Pushes max_player_built_footprint_x/y from the beacon machine onto its
/// live registered landmark -- same pattern as _sync_landmark_faction()
/// above, needed because player_dock/is_valid() (the actual check) reads
/// these off the landmark, not the machine.
/obj/structure/machinery/docking_beacon/proc/_sync_landmark_player_built_footprint()
	var/obj/effect/shuttle_landmark/player_dock/L = SSshuttle.registered_shuttle_landmarks[landmark_tag]
	if(L)
		L.max_player_built_footprint_x = max_player_built_footprint_x
		L.max_player_built_footprint_y = max_player_built_footprint_y

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
	// Registers the beacon MACHINE itself (not its landmark, which is a
	// separate object) under its own stable landmark_tag -- lets
	// ship_commissioning's saved linked_beacon_tag (ship_commissioning_console.dm)
	// be resolved back to this specific beacon after a restart re-creates it
	// fresh from the DB. Idempotent, safe to repeat on the "already
	// registered" early-return path below too.
	GLOB.drydock_linkable_devices_by_tag[landmark_tag] = src
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
	// relocation (attempt_move()/shuttle_moved(), shuttle.dm), not an
	// abstract marker visit, so a full-size hull's real turfs simply can't
	// fit materializing at a small cycler pad.
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
	if(landmark_tag)
		GLOB.drydock_linkable_devices_by_tag -= landmark_tag
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_player_docking_beacons WHERE landmark_tag = :tag",
			list("tag" = landmark_tag)
		)
		q.Execute()
		qdel(q)
	return ..()
