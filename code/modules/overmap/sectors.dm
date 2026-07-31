//===================================================================================
//Overmap object representing zlevel(s)
//===================================================================================
/// Global object used to locate the overmap area.
GLOBAL_DATUM(map_overmap, /area/overmap)

/obj/effect/overmap/visitable
	name = "map object"
	scannable = TRUE
	sensor_range_override = TRUE
	/// Actual name of the object.
	var/designation
	/// Imagine a ship or station's class. "NTCC" Odin, "SCCV" Horizon, ...
	var/class
	unknown_id = "Bogey"
	var/obfuscated_name = "unidentified object"
	var/obfuscated_desc = "This object is not displaying its IFF signature."
	/// Whether we hide our name and class or not.
	var/obfuscated = FALSE

	/// Landmark tags of landmarks that should be added to the actual lists below on init.
	/// Generic, meaning usable by any shuttle.
	/// Can contain nested lists, as it is flattened on init.
	var/list/initial_generic_waypoints
	/// Restricted, meaning that only specific shuttles can use them.
	/// Should be an assoc list like `list("Shuttle" = list("nav_landmark_tag"), ...)`
	var/list/initial_restricted_waypoints
	/// Landmark tags of landmarks of docks that will be tracked in the docks computer program.
	/// Can contain nested lists, as it is flattened on init.
	var/list/tracked_dock_tags

	/// Waypoints that any shuttle can use
	var/list/generic_waypoints = list()
	/// Waypoints for specific shuttles
	var/list/restricted_waypoints = list()

	/// Coordinates for self placing
	var/start_x
	/// Will use random values if unset
	var/start_y

	/// Starting sector, counts as station_levels
	var/base = FALSE
	/// Can be accessed via lucky EVA
	var/in_space = TRUE

	var/has_called_distress_beacon = FALSE
	var/image/applied_distress_overlay

	var/targeting_flags = TARGETING_FLAG_ENTRYPOINTS|TARGETING_FLAG_GENERIC_WAYPOINTS
	var/list/obj/structure/machinery/ship_weapon/ship_weapons
	var/list/obj/effect/landmark/entry_points
	var/obj/effect/overmap/targeting
	var/obj/structure/machinery/leviathan_safeguard/levi_safeguard
	var/obj/structure/machinery/gravity_generator/main/gravity_generator

	/// Whether ghostroles attached to this overmap object spawn with comms
	var/comms_support = FALSE
	/// Snowflake name to apply to comms equipment ("shipboard radio headset", "intercom (shipboard)", "shipboard telecommunications mainframe"), etc.
	var/comms_name = "shipboard"
	/// Snowflake name to label frequency, if not set, frequency defaults to overmap name
	var/freq_name = ""
	/// Whether away ship comms have access to the common channel / PUB_FREQ
	var/use_common = FALSE
	/// list of weakrefs to people viewing the overmap via this ship
	var/list/navigation_viewers
	var/list/consoles

	/// A list of datalink requests that we received
	var/list/datalink_requests = list()
	/// Other effects that we are datalinked with
	var/list/datalinked        = list()

	/// null | num | list. If a num or a (num, num) list, the radius or random bounds for placing this sector near the main map's overmap icon.
	var/list/place_near_main

	var/invisible_until_ghostrole_spawn = FALSE
	var/hide_from_reports = FALSE

/obj/effect/overmap/visitable/Initialize()
	. = ..()
	if(. == INITIALIZE_HINT_QDEL)
		return

	find_z_levels()     // This populates map_z and assigns z levels to the ship.
	register_z_levels() // This makes external calls to update global z level information.

	// Retry any computer/ship (Nav/Sensors/Helm) that lost the init-order race
	// against this exact registration call -- see lonely_ship_computers
	// (shuttle.dm) and computer/ship/Initialize() (ship.dm) for the other half.
	for(var/obj/structure/machinery/computer/ship/SC as anything in SSshuttle.lonely_ship_computers)
		if(!istype(src, SC.linked_type))
			continue
		if(!(SC.z in map_z))
			continue
		if(SC.attempt_hook_up(src))
			SSshuttle.lonely_ship_computers -= SC

	if(!SSatlas.current_map.overmap_z)
		build_overmap()

	initial_generic_waypoints = flatten_list(initial_generic_waypoints)
	tracked_dock_tags = flatten_list(tracked_dock_tags)

	move_to_starting_location()

	update_name()

	log_module_sectors("Located sector \"[name]\" at [start_x],[start_y], containing Z [english_list(map_z)]")

	LAZYADD(SSshuttle.sectors_to_initialize, src) //Queued for further init. Will populate the waypoint lists; waypoints not spawned yet will be added in as they spawn.
	SSshuttle.clear_init_queue()
	START_PROCESSING(SSovermap, src)

/obj/effect/overmap/visitable/process()
	if(get_dist(src, targeting) > 7)
		detarget(targeting)

/obj/effect/overmap/visitable/Destroy()
	for(var/obj/structure/machinery/hologram/holopad/H as anything in SSmachinery.all_holopads)
		if(H.linked == src)
			H.linked = null
	for(var/obj/structure/machinery/telecomms/T in SSmachinery.all_telecomms)
		if(T.linked == src)
			T.linked = null
	if(entry_points)
		entry_points.Cut()
	for(var/obj/structure/machinery/ship_weapon/SW in ship_weapons)
		SW.linked = null
	if(ship_weapons)
		ship_weapons.Cut()
	targeting = null
	levi_safeguard = null
	gravity_generator = null
	STOP_PROCESSING(SSovermap, src)
	. = ..()

/obj/effect/overmap/visitable/proc/move_to_starting_location()
	set waitfor = FALSE
	if(!SSatlas.current_map.use_overmap)
		return
	// build_overmap() can still be mid-build at this point (its
	// add_new_zlevel() call sleeps on the zlevel-add latch/CHECK_TICK
	// before overmap_z is assigned, and it runs waitfor=FALSE). Every
	// locate() below silently resolves to null on z 0, and forceMove(null)
	// is a no-op (atoms_movable.dm) -- which used to strand the marker on
	// its mapped .dmm turf inside the ship's own hull. waitfor=FALSE keeps
	// Initialize() callers from sleeping; placement completes as soon as
	// the overmap exists.
	UNTIL(SSatlas.current_map.overmap_z)
	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
	var/turf/home
	if (place_near_main)
		var/obj/effect/overmap/visitable/main = GLOB.map_sectors["1"] ? GLOB.map_sectors["1"] : GLOB.map_sectors[GLOB.map_sectors[1]]
		if(islist(place_near_main))
			place_near_main = Roundm(Frand(place_near_main[1], place_near_main[2]), 0.1)
		home = CircularRandomTurfAround(main, abs(place_near_main), map_low, map_low, map_high, map_high)
		start_x = home.x
		start_y = home.y
		LOG_DEBUG("place_near_main moving [src] near [main] ([main.x],[main.y]) with radius [place_near_main], got ([home.x],[home.y])")
	else if(start_x && start_y)
		// Fixed coordinates (mapped-in or pinned/injected sites) -- respected untouched
		home = locate(start_x, start_y, SSatlas.current_map.overmap_z)
	else
		// Random placement: avoid tiles that already hold another sector marker
		// (pinned/injected sites and earlier random spawns), so nothing stacks.
		// Bounded random retries first (cheap, succeeds almost always), then an
		// exhaustive scan as a guaranteed fallback -- pinned sites must never be
		// silently displaced/stacked on by a later random spawn.
		var/tries = 10
		while(tries > 0)
			tries--
			var/try_x = start_x || rand(map_low, map_high)
			var/try_y = start_y || rand(map_low, map_high)
			var/turf/candidate = locate(try_x, try_y, SSatlas.current_map.overmap_z)
			if(!(locate(/obj/effect/overmap/visitable) in candidate))
				start_x = try_x
				start_y = try_y
				home = candidate
				break
		if(!home)
			// Random retries exhausted without finding a free tile -- fall back
			// to an exhaustive scan so a crowded map still never stacks a new
			// spawn on top of an existing (especially pinned) site.
			for(var/scan_x = map_low to map_high)
				for(var/scan_y = map_low to map_high)
					var/turf/candidate = locate(scan_x, scan_y, SSatlas.current_map.overmap_z)
					if(!(locate(/obj/effect/overmap/visitable) in candidate))
						start_x = scan_x
						start_y = scan_y
						home = candidate
						break
				if(home)
					break
			if(!home)
				// Genuinely no free tile anywhere -- log loudly rather than
				// silently stacking; last-resort random tile as before.
				log_game("move_to_starting_location(): overmap fully occupied, [src] forced to share a tile.")
				start_x = start_x || rand(map_low, map_high)
				start_y = start_y || rand(map_low, map_high)
				home = locate(start_x, start_y, SSatlas.current_map.overmap_z)

	if(!invisible_until_ghostrole_spawn)
		forceMove(home)

/// Sector view cameras onto a marker's loc -- a marker whose placement
/// never ran or lost an init race (e.g. a retrieved ship's marker left on
/// its mapped .dmm turf inside its own cockpit) shows ship interior
/// instead of the overmap. Walks nested markers to their root (nesting =
/// docked ships, legitimate) and re-places the root if it isn't actually
/// on the overmap z. No-op for healthy markers.
/proc/repair_stray_overmap_marker(obj/effect/overmap/target)
	if(!istype(target))
		return
	var/obj/effect/overmap/root = target
	while(istype(root.loc, /obj/effect/overmap))
		root = root.loc
	var/obj/effect/overmap/visitable/stray = root
	if(!istype(stray) || stray.invisible_until_ghostrole_spawn)
		return
	var/turf/root_turf = get_turf(stray)
	if(!root_turf || root_turf.z != SSatlas.current_map.overmap_z)
		log_module_sectors("repair_stray_overmap_marker: [stray] was at [root_turf ? "[root_turf.x],[root_turf.y],[root_turf.z]" : "nullspace"], re-placing on the overmap.")
		stray.move_to_starting_location()

//This is called later in the init order by SSshuttle to populate sector objects. Importantly for subtypes, shuttles will be created by then.
/obj/effect/overmap/visitable/proc/populate_sector_objects()
	for(var/obj/structure/machinery/hologram/holopad/H as anything in SSmachinery.all_holopads)
		H.attempt_hook_up(src)
	for(var/obj/structure/machinery/telecomms/T in SSmachinery.all_telecomms)
		T.attempt_hook_up(src)

/obj/effect/overmap/visitable/proc/get_areas()
	return get_filtered_areas(list(/proc/area_belongs_to_zlevels = map_z))

/obj/effect/overmap/visitable/proc/find_z_levels()
	map_z = GetConnectedZlevels(z)

/obj/effect/overmap/visitable/proc/register_z_levels()
	for(var/zlevel in map_z)
		GLOB.map_sectors["[zlevel]"] = src

	SSatlas.current_map.player_levels |= map_z
	if(!in_space)
		SSatlas.current_map.sealed_levels |= map_z
	if(base)
		// SSatlas.current_map.station_levels |= map_z
		SSatlas.current_map.contact_levels |= map_z
		SSatlas.current_map.map_levels |= map_z

//Helper for init.
/obj/effect/overmap/visitable/proc/check_ownership(obj/object)
	if((object.z in map_z) && !(get_area(object) in SSshuttle.shuttle_areas))
		return 1

//If shuttle_name is false, will add to generic waypoints; otherwise will add to restricted. Does not do checks.
/obj/effect/overmap/visitable/proc/add_landmark(obj/effect/shuttle_landmark/landmark, shuttle_name)
	landmark.sector_set(src, shuttle_name)
	if(shuttle_name)
		LAZYADD(restricted_waypoints[shuttle_name], landmark)
	else
		generic_waypoints += landmark

/obj/effect/overmap/visitable/proc/remove_landmark(obj/effect/shuttle_landmark/landmark, shuttle_name)
	if(shuttle_name)
		var/list/shuttles = restricted_waypoints[shuttle_name]
		LAZYREMOVE(shuttles, landmark)
	else
		generic_waypoints -= landmark

/obj/effect/overmap/visitable/proc/get_waypoints(var/shuttle_name)
	. = list()
	for(var/obj/effect/overmap/visitable/contained in src)
		. += contained.get_waypoints(shuttle_name)
	for(var/thing in generic_waypoints)
		.[thing] = name
	if(shuttle_name in restricted_waypoints)
		for(var/thing in restricted_waypoints[shuttle_name])
			.[thing] = name

/obj/effect/overmap/visitable/proc/generate_skybox()
	return

/obj/effect/overmap/visitable/proc/toggle_distress_status()
	has_called_distress_beacon = !has_called_distress_beacon
	if(has_called_distress_beacon)
		var/image/distress_overlay = image('icons/obj/overmap/overmap_effects.dmi', "distress")
		applied_distress_overlay = distress_overlay
		AddOverlays(applied_distress_overlay)
		filters = filter(type = "outline", size = 2, color = COLOR_RED)
	else
		CutOverlays(applied_distress_overlay)
		filters = null

/obj/effect/overmap/visitable/proc/update_name()
	if(!designation)
		return
	if(obfuscated)
		return
	if(comms_support)
		update_away_freq(name, get_real_name())
	SEND_SIGNAL(src, COMSIG_BASENAME_SETNAME, args)
	name = get_real_name()

/obj/effect/overmap/visitable/proc/get_real_name()
	return class ? "[class] [designation]" : designation

/obj/effect/overmap/visitable/proc/set_new_designation(var/new_name)
	designation = new_name
	update_name()

/obj/effect/overmap/visitable/proc/set_new_class(var/new_class)
	class = new_class
	update_name()

/obj/effect/overmap/visitable/proc/update_obfuscated(var/new_state) //TRUE is obfuscated.
	if(new_state)
		name = obfuscated_name
		desc = obfuscated_desc
	else
		update_name()

/obj/effect/overmap/visitable/sector
	name = "generic sector"
	desc = "Sector with some stuff in it."
	icon_state = "sector"
	anchored = 1

	/// Ground survey result for use by survey probes to generate survey reports after surveying.
	/// A string. Child implementations should set and/or append to the string.
	/// Stations or ships should keep it null, as they cannot be surveyed with a survey probe.
	/// Lore planets and static away sites that are planets should keep it to static text trivia.
	/// For random planets, should be filled with random trivia or blurbs or the like.
	var/ground_survey_result = null
	/// Fluff descriptions found from soil sampling
	var/list/soil_data = list()
	/// Fluff desctiptions found on water sampling
	var/list/water_data = list()
	/// Magnetic survey result for use by survey probes. Randomly generated by most planets. Lore planets should have static text.
	var/magnet_survey_result = null

/obj/effect/overmap/visitable/sector/Initialize()
	. = ..()
	generate_ground_survey_result()
	generate_magnet_survey_result()

// Because of the way these are spawned, they will potentially have their invisibility adjusted by the turfs they are mapped on
// prior to being moved to the overmap. This blocks that. Use set_invisibility to adjust invisibility as needed instead.
/obj/effect/overmap/visitable/sector/hide()

/obj/effect/overmap/visitable/proc/handle_sensor_state_change(var/on)
	return

/// Generate ground survey result text, by setting the `ground_survey_result` var.
/// Called once at init of the sector.
/// Randomly generated planets should call parent and append to `ground_survey_result`.
/// Lore planets or away sites should just set it to one static string.
/obj/effect/overmap/visitable/sector/proc/generate_ground_survey_result()
	ground_survey_result = ""

/obj/effect/overmap/visitable/sector/proc/generate_magnet_survey_result()
	magnet_survey_result = ""

GLOBAL_VAR_INIT(building_overmap, FALSE)

/proc/build_overmap()
	set waitfor = FALSE
	if(!SSatlas.current_map.use_overmap)
		return 1

	// add_new_zlevel() below can sleep (zlevel-add latch / CHECK_TICK)
	// before overmap_z is assigned; with waitfor=FALSE, every visitable
	// Initialize() racing through that window used to launch its own
	// duplicate build, producing multiple orphaned "Overmap" z-levels with
	// markers scattered across them. One-shot latch: first caller builds,
	// everyone else defers to move_to_starting_location()'s own
	// UNTIL(overmap_z) wait. Deliberately never reset -- the overmap is
	// built exactly once per round.
	if(GLOB.building_overmap)
		return 1
	GLOB.building_overmap = TRUE

	log_module_sectors("Building overmap...")
	var/datum/space_level/overmap_spacelevel = SSmapping.add_new_zlevel("Overmap", ZTRAITS_OVERMAP, contain_turfs = FALSE)
	SSatlas.current_map.overmap_z = overmap_spacelevel.z_value

	log_module_sectors("Putting overmap on [SSatlas.current_map.overmap_z]")
	var/area/overmap/A = new
	GLOB.map_overmap = A
	for (var/square in block(locate(1,1,SSatlas.current_map.overmap_z), locate(SSatlas.current_map.overmap_size,SSatlas.current_map.overmap_size,SSatlas.current_map.overmap_z)))
		var/turf/T = square
		if(T.x == SSatlas.current_map.overmap_size || T.y == SSatlas.current_map.overmap_size)
			T = T.ChangeTurf(/turf/unsimulated/map/edge)
		else
			T = T.ChangeTurf(/turf/unsimulated/map)
		T.change_area(T.loc, A)

	SSatlas.current_map.sealed_levels |= SSatlas.current_map.overmap_z

	// CentCom (admin_levels) never loads a real map file, so nothing can
	// physically spawn there to pick up its map_z the normal way -- this
	// marker hardcodes map_z itself (find_z_levels() override) instead, so
	// it can be spawned here unconditionally now that the overmap exists.
	new /obj/effect/overmap/visitable/sector/centcom()

	log_module_sectors("Overmap build complete.")
	return 1

/// A circular random coordinate pair from 0, unit by default, scaled by radius, then rounded if round.
/proc/CircularRandomCoordinate(radius = 1, round)
	var/angle = rand(0, 359)
	var/x = cos(angle) * radius
	var/y = sin(angle) * radius
	if (round)
		x = round(x)
		y = round(y)
	return list(x, y)

/**
* A circular random coordinate with radius on center_x, center_y,
* reflected into low_x,low_y -> high_x,high_y, clamped in low,high,
* and rounded if round is set
*
* Generally this proc is useful for placement around a point (eg a
* player) that must stay within map boundaries, or some similar circle
* in box constraint
*
* A "donut" pattern can be achieved by varying the number supplied as
* radius outside the scope of the proc, eg as BoundedCircularRandomCoordinate(Frand(1, 3), ...)
*/
/proc/BoundedCircularRandomCoordinate(radius, center_x, center_y, low_x, low_y, high_x, high_y, round)
	var/list/xy = CircularRandomCoordinate(radius, round)
	var/dx = xy[1]
	var/dy = xy[2]
	// Clamp the center into bounds first -- if the caller's anchor is itself
	// outside [low,high] (eg a sector deliberately pinned outside the normal
	// placement band), the "mirror across center" fallback below still lands
	// outside bounds for every possible offset, so the final clamp() used to
	// deterministically collapse every call onto the single corner tile
	// (low_x,low_y) regardless of radius, instead of scattering near the
	// intended anchor.
	var/cx = clamp(center_x, low_x, high_x)
	var/cy = clamp(center_y, low_y, high_y)
	var/x = cx + dx
	var/y = cy + dy
	if (x < low_x || x > high_x)
		x = cx - dx
	if (y < low_y || y > high_y)
		y = cy - dy
	return list(
		clamp(x, low_x, high_x),
		clamp(y, low_y, high_y)
	)

/// Pick a random turf using BoundedCircularRandomCoordinate about x,y on level z
/proc/CircularRandomTurf(radius, z, center_x, center_y, low_x = 1, low_y = 1, high_x = world.maxx, high_y = world.maxy)
	var/list/xy = BoundedCircularRandomCoordinate(radius, center_x, center_y, low_x, low_y, high_x, high_y, TRUE)
	return locate(xy[1], xy[2], z)


/// Pick a random turf using BoundedCircularRandomCoordinate around the turf of target
/proc/CircularRandomTurfAround(atom/target, radius, low_x = 1, low_y = 1, high_x = world.maxx, high_y = world.maxy)
	var/turf/turf = get_turf(target)
	return CircularRandomTurf(radius, turf.z, turf.x, turf.y, low_x, low_y, high_x, high_y)
