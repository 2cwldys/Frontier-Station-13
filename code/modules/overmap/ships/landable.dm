// These come with shuttle functionality. Need to be assigned a (unique) shuttle datum name.
// Mapping location doesn't matter, so long as on a map loaded at the same time as the shuttle areas.
// Multiz shuttles currently not supported. Non-autodock shuttles currently not supported.

/obj/effect/overmap/visitable/ship/landable
	var/shuttle                                         // Name of associated shuttle. Must be autodock.
	var/obj/effect/shuttle_landmark/ship/landmark       // Record our open space landmark for easy reference.
	var/multiz = 0										// Index of multi-z levels, starts at 0
	var/status = SHIP_STATUS_LANDED
	///If true, it will use the z-level it's mapped on as the "Open Space" level, if false it will create a new level for that.
	var/use_mapped_z_levels = FALSE //If you use this, use /obj/effect/shuttle_landmark/ship as the landmark (set the landmark_tag to match on the shuttle, no other setup needed)
	icon_state = "shuttle"
	moving_state = "shuttle_moving"
	layer = OVERMAP_SHUTTLE_LAYER

/obj/effect/overmap/visitable/ship/landable/Destroy()
	GLOB.shuttle_moved_event.unregister(SSshuttle.shuttles[shuttle], src)
	return ..()

/obj/effect/overmap/visitable/ship/landable/can_burn()
	if(status != SHIP_STATUS_OVERMAP)
		return 0
	return ..()

/obj/effect/overmap/visitable/ship/landable/burn()
	if(status != SHIP_STATUS_OVERMAP)
		return 0
	return ..()

/obj/effect/overmap/visitable/ship/landable/check_ownership(obj/object)
	var/datum/shuttle/shuttle_datum = SSshuttle.shuttles[shuttle]
	if(!shuttle_datum)
		return
	var/list/areas = shuttle_datum.find_childfree_areas()
	if(get_area(object) in areas)
		return 1

// We autobuild our z levels.
/obj/effect/overmap/visitable/ship/landable/find_z_levels()
	// Must happen before the landmarks below are built: the home landmark's
	// tag is "ship_[shuttle_name]" (/obj/effect/shuttle_landmark/ship's own
	// Initialize), so without a per-instance name here two hulls of the same
	// class produce the same tag and register_landmark() silently drops the
	// second one -- leaving that ship pointed at the first ship's landmark.
	// No-op outside a drydock template load. The shuttle DATUM picks up the
	// same suffix in /datum/shuttle/New(), so the two still match.
	shuttle = drydock_apply_instance_suffix(shuttle)
	if(!use_mapped_z_levels)
		for(var/i = 0 to multiz)
			var/datum/space_level/S = SSmapping.add_new_zlevel("Landable Landmark [i] for [shuttle]", list(ZTRAIT_RESERVED = TRUE), contain_turfs = FALSE)
			map_z += S.z_value
		var/turf/center_loc = locate(round(world.maxx/2), round(world.maxy/2), map_z[length(map_z)])
		landmark = new (center_loc, shuttle)
		add_landmark(landmark, shuttle)
		var/visitor_dir = fore_dir
		for(var/landmark_name in list("FORE", "PORT", "AFT", "STARBOARD"))
			var/turf/visitor_turf = get_ranged_target_turf(get_turf(landmark), visitor_dir, round(min(world.maxx/4, world.maxy/4)))
			var/obj/effect/shuttle_landmark/visiting_shuttle/visitor_landmark = new (visitor_turf, landmark, landmark_name)
			add_landmark(visitor_landmark)
			visitor_dir = turn(visitor_dir, 90)

		if(multiz)
			new /obj/effect/landmark/map_data(locate(1, 1, map_z[length(map_z)]), (multiz + 1))
	else
		..()

/obj/effect/overmap/visitable/ship/landable/move_to_starting_location()
	if(!use_mapped_z_levels)
		return
	else
		..() // this picks a random turf

/obj/effect/overmap/visitable/ship/landable/get_areas()
	var/datum/shuttle/shuttle_datum = SSshuttle.shuttles[shuttle]
	if(!shuttle_datum)
		return list()
	return shuttle_datum.find_childfree_areas()

/obj/effect/overmap/visitable/ship/landable/populate_sector_objects()
	..()
	var/datum/shuttle/shuttle_datum = SSshuttle.shuttles[shuttle]
	if(!shuttle_datum)
		// Shuttle datum construction (initialize_shuttles(), shuttle.dm) is
		// supposed to always precede this proc (see its own doc comment,
		// sectors.dm) but evidently isn't airtight for a dynamically-loaded
		// retrieve -- retry shortly instead of crashing through
		// on_landing()/dock-link setup and the visitor-landmark loop below.
		stack_trace("populate_sector_objects: shuttle datum for '[shuttle]' not yet registered on [src] ([type]), retrying shortly.")
		addtimer(CALLBACK(src, PROC_REF(populate_sector_objects)), 2 SECONDS)
		return
	if(use_mapped_z_levels)
		var/obj/effect/shuttle_landmark/ship/ship_landmark = shuttle_datum.current_location
		if(!istype(ship_landmark))
			stack_trace("Landable ship [src] with shuttle [shuttle] was mapped with a starting landmark type [ship_landmark.type], but should be /obj/effect/shuttle_landmark/ship.")
			ship_landmark = new(ship_landmark.loc, shuttle)
			qdel(shuttle_datum.current_location)
			shuttle_datum.current_location = ship_landmark
		landmark = ship_landmark
		landmark.shuttle_name = shuttle
		LAZYDISTINCTADD(initial_generic_waypoints, landmark.landmark_tag) // this is us being user-friendly: it means we register it properly regardless of whether the mapper put the tag in initial_restricted_waypoints

		var/visitor_dir = fore_dir
		for(var/landmark_name in list("FORE", "PORT", "AFT", "STARBOARD"))
			var/turf/visitor_turf = get_ranged_target_turf(get_turf(landmark), visitor_dir, round(min(world.maxx/4, world.maxy/4)))
			var/obj/effect/shuttle_landmark/visiting_shuttle/visitor_landmark = new (visitor_turf, landmark, landmark_name)
			add_landmark(visitor_landmark)
			visitor_dir = turn(visitor_dir, 90)

	//Configure shuttle datum
	GLOB.shuttle_moved_event.register(shuttle_datum, src, PROC_REF(on_shuttle_jump))
	on_landing(landmark, shuttle_datum.current_location) // We "land" at round start to properly place ourselves on the overmap.
	if(landmark == shuttle_datum.current_location)
		status = SHIP_STATUS_OVERMAP

	var/obj/effect/overmap/visitable/mothership = GLOB.map_sectors["[shuttle_datum.current_location.z]"]
	if(mothership)
		for(var/obj/structure/machinery/computer/ship/sensors/sensor_console in consoles)
			sensor_console.datalink_add_ship_datalink(mothership)
			break

/obj/effect/shuttle_landmark/ship
	name = "Open Space"
	landmark_tag = "ship"
	landmark_flags = SLANDMARK_FLAG_AUTOSET | SLANDMARK_FLAG_ZERO_G
	base_turf = /turf/space
	var/shuttle_name
	var/list/visitors // landmark -> visiting shuttle stationed there

/obj/effect/shuttle_landmark/ship/Initialize(mapload, shuttle_name)
	if(!src.shuttle_name)
		landmark_tag += "_[shuttle_name]"
		src.shuttle_name = shuttle_name
	. = ..()

/obj/effect/shuttle_landmark/ship/Destroy()
	var/obj/effect/overmap/visitable/ship/landable/ship = GLOB.map_sectors["[z]"]
	if(istype(ship) && ship.landmark == src)
		ship.landmark = null
	. = ..()

/obj/effect/shuttle_landmark/ship/cannot_depart(datum/shuttle/shuttle)
	if(LAZYLEN(visitors))
		return "Grappled by other shuttle; cannot manouver."
	// Same backref pattern this landmark type's own Destroy() already uses
	// to reach its owning ship marker. Single choke point -- attempt_move()
	// (shuttle.dm), process_launch() (shuttle_autodock.dm), and the
	// console's own can_move() (shuttle_console.dm) all call cannot_depart()
	// on this exact landmark, so one check here blocks every jump/dock path
	// a tractored ship's own crew could otherwise use to escape.
	var/obj/effect/overmap/visitable/ship/landable/ship = GLOB.map_sectors["[z]"]
	if(istype(ship) && ship.tractored_by)
		return "Held by an enemy tractor beam; cannot manouver."

/obj/effect/shuttle_landmark/visiting_shuttle
	landmark_flags = SLANDMARK_FLAG_AUTOSET | SLANDMARK_FLAG_ZERO_G
	var/obj/effect/shuttle_landmark/ship/core_landmark

/obj/effect/shuttle_landmark/visiting_shuttle/Initialize(mapload, obj/effect/shuttle_landmark/ship/master, _name)
	core_landmark = master
	name = _name
	landmark_tag = master.shuttle_name + _name
	RegisterSignal(master, COMSIG_QDELETING, TYPE_PROC_REF(/datum, qdel_self))
	. = ..()

/obj/effect/shuttle_landmark/visiting_shuttle/Destroy()
	UnregisterSignal(core_landmark, COMSIG_QDELETING)
	LAZYREMOVE(core_landmark.visitors, src)
	core_landmark = null
	. = ..()

/obj/effect/shuttle_landmark/visiting_shuttle/is_valid(datum/shuttle/shuttle, list/reason_out, check_objects = TRUE)
	. = ..(shuttle, reason_out, check_objects)
	if(!.)
		return
	var/datum/shuttle/boss_shuttle = SSshuttle.shuttles[core_landmark.shuttle_name]
	if(boss_shuttle.current_location != core_landmark)
		return FALSE // Only available when our governing shuttle is in space.
	if(shuttle == boss_shuttle) // Boss shuttle only lands on main landmark
		return FALSE

/obj/effect/shuttle_landmark/visiting_shuttle/shuttle_arrived(datum/shuttle/shuttle)
	..()
	LAZYSET(core_landmark.visitors, src, shuttle)
	GLOB.shuttle_moved_event.register(shuttle, src, PROC_REF(shuttle_left))

/obj/effect/shuttle_landmark/visiting_shuttle/proc/shuttle_left(datum/shuttle/shuttle, obj/effect/shuttle_landmark/old_landmark, obj/effect/shuttle_landmark/new_landmark)
	if(old_landmark == src)
		GLOB.shuttle_moved_event.unregister(shuttle, src)
		LAZYREMOVE(core_landmark.visitors, src)

/obj/effect/overmap/visitable/ship/landable/proc/on_shuttle_jump(datum/shuttle/given_shuttle, obj/effect/shuttle_landmark/from, obj/effect/shuttle_landmark/into)
	if(given_shuttle != SSshuttle.shuttles[shuttle])
		return
	var/datum/shuttle/autodock/auto = given_shuttle
	if(into == auto.landmark_transition)
		status = SHIP_STATUS_TRANSIT
		on_takeoff(from, into)
		return
	if(into == landmark)
		status = SHIP_STATUS_OVERMAP
		on_takeoff(from, into)
		return
	status = SHIP_STATUS_LANDED
	on_landing(from, into)

/obj/effect/overmap/visitable/ship/landable/proc/on_landing(obj/effect/shuttle_landmark/from, obj/effect/shuttle_landmark/into)
	// Safety net, not the real gate -- cannot_depart() (this file, the
	// /ship landmark subtype above) is what actually stops a tractored ship
	// from ever reaching a real dock/land in normal play. This just makes
	// sure a lock can never survive one anyway, in case some unanticipated
	// path lands here despite that.
	if(tractored_by)
		tractored_by._release_lock()

	// Neither shields nor a cloak can be sustained at an away site -- silently
	// switch both off rather than playing their usual offline sound/announcer,
	// which would otherwise be heard by everyone else already on that site's
	// own z. Covers pinned/persistent away sites too, since those are
	// stamped with the same ZTRAIT_AWAY trait (is_away_level(),
	// level_traits.dm). No back-reference var exists from the ship to its own
	// cloak (unlike shield_generator, below) -- same SSmachinery.machinery
	// scan _ship_gun.dm's own fire() already uses to force-uncloak a firing
	// ship.
	// Engines come off the moment we touch down anywhere -- a station pad or an
	// away site alike -- rather than being left burning while parked. Clears
	// the ship-wide toggle AND each engine individually: engines_state alone
	// only gates new burns, and marker.engines (the datum/ship_engine registry)
	// is not reliably populated, so the real machines are swept directly the
	// same way _drydock_power_down_ship_systems() (persistence_shuttles.dm) has
	// to.
	engines_state = FALSE
	for(var/datum/ship_engine/E as anything in engines)
		if(E.is_on())
			E.toggle()
	for(var/zlevel in map_z)
		for(var/obj/structure/machinery/atmospherics/unary/engine/nozzle in SSmachinery.machinery)
			if(GET_Z(nozzle) == zlevel && nozzle.use_power)
				nozzle.update_use_power(POWER_USE_OFF)
		for(var/obj/structure/machinery/ion_engine/ion in SSmachinery.machinery)
			if(GET_Z(ion) == zlevel && ion.on)
				ion.on = FALSE
	// Pre-sync the hum state so _update_engine_hum() (ship.dm) never sees this
	// as an on->off TRANSITION, which is what queues the "engines powered off"
	// voice line and the shutdown stinger. Docking is real turf relocation, so
	// once landed the engine console is physically on the host site's own z --
	// that announcer's GET_Z(M) != GET_Z(console) audience filter stops
	// isolating our crew and broadcasts to everyone standing nearby. Same
	// reasoning as the silent shield/cloak shutdown just below; a player
	// toggling the engines by hand still gets the announcer normally.
	// The hum loop is still stopped correctly -- that cleanup runs off
	// engine_hum_listeners, outside the transition branch.
	engine_hum_active = FALSE

	if(is_away_level(into.z))
		if(shield_generator && shield_generator.active)
			shield_generator._set_active(FALSE, silent = TRUE)
		for(var/obj/structure/machinery/ship_cloaking_device/CD in SSmachinery.machinery)
			if(CD.linked != src || !CD.active)
				continue
			CD._set_active(FALSE, silent = TRUE)
		// Same reasoning -- toggle_tractor() already refuses to ENGAGE the
		// beam at an away site (ship_tractor_beam.dm), but doesn't cover
		// flying there and landing while a lock from open space is still
		// held; this is that other half.
		if(tractor_beam && tractor_beam.active)
			tractor_beam._release_lock(silent = TRUE)
	var/obj/effect/overmap/visitable/target = GLOB.map_sectors["[into.z]"]
	var/datum/shuttle/shuttle_datum = SSshuttle.shuttles[shuttle]
	if(into.landmark_tag == shuttle_datum.motherdock) // If our motherdock is a landable ship, it won't be found properly here so we need to find it manually.
		for(var/obj/effect/overmap/visitable/ship/landable/landable in SSshuttle.ships)
			if(landable.shuttle == shuttle_datum.mothershuttle)
				target = landable
				break
	if(!target || target == src)
		return
	forceMove(target)
	halt()

/obj/effect/overmap/visitable/ship/landable/proc/on_takeoff(obj/effect/shuttle_landmark/from, obj/effect/shuttle_landmark/into)
	if(!isturf(loc))
		forceMove(get_turf(loc))
		unhalt()

/obj/effect/overmap/visitable/ship/landable/get_landed_info()
	switch(status)
		if(SHIP_STATUS_LANDED)
			var/obj/effect/overmap/visitable/location = loc
			if(istype(loc, /obj/effect/overmap/visitable/sector))
				return "Landed on \the [location.name]. Use secondary thrust to get clear before activating primary engines."
			if(istype(loc, /obj/effect/overmap/visitable/ship))
				return "Docked with \the [location.name]. Use secondary thrust to get clear before activating primary engines."
			return "Docked with an unknown object."
		if(SHIP_STATUS_TRANSIT)
			return "Maneuvering under secondary thrust."
		if(SHIP_STATUS_OVERMAP)
			return "In open space."
