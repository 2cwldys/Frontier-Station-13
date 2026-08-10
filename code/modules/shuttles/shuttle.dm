//shuttle moving state defines are in setup.dm

/datum/shuttle
	var/name = ""
	var/warmup_time = 0
	var/moving_status = SHUTTLE_IDLE

	var/list/shuttle_area //can be both single area type or a list of areas
	var/obj/effect/shuttle_landmark/current_location //This variable is type-abused initially: specify the landmark_tag, not the actual landmark.
	var/list/shuttle_computers = list()

	var/arrive_time = 0	//the time at which the shuttle arrives when long jumping
	var/flags = 0
	var/process_state = IDLE_STATE //Used with SHUTTLE_FLAGS_PROCESS, as well as to store current state.
	var/category = /datum/shuttle
	var/multiz = 0	//how many multiz levels, starts at 0

	var/ceiling_type = /turf/simulated/floor/airless/ceiling

	var/sound_takeoff = 'sound/effects/shuttle_takeoff.ogg'
	var/sound_landing = 'sound/effects/shuttle_landing.ogg'

	var/knockdown = TRUE //whether shuttle downs non-buckled_to people when it moves

	/**
	 * This shuttle will/won't be initialised automatically.
	 * If set to `TRUE`, you are responsible for initialzing the shuttle manually.
	 * Useful for shuttles that are initialed by map_template loading, or shuttles that are created in-game or not used.
	 */
	var/defer_initialisation = FALSE
	var/logging_home_tag   //Whether in-game logs will be generated whenever the shuttle leaves/returns to the landmark with this landmark_tag.
	var/logging_access     //Controls who has write access to log-related stuff; should correlate with pilot access.

	var/mothershuttle //tag of mothershuttle
	var/motherdock    //tag of mothershuttle landmark, defaults to starting location

	var/squishes = TRUE //decides whether or not things get squished when it moves.
	var/cargo_elevator = FALSE // Snowflake variable for the cargo elevator. Decides whether you will take fall damage or not

/datum/shuttle/New(_name, var/obj/effect/shuttle_landmark/initial_location)
	..()
	if(_name)
		src.name = _name

	var/list/areas = list()
	if(!islist(shuttle_area))
		shuttle_area = list(shuttle_area)
	for(var/T in shuttle_area)
		var/area/A = locate(T)
		if(!istype(A))
			CRASH("Shuttle \"[name]\" couldn't locate area [T].")
		areas += A
		RegisterSignal(A, COMSIG_QDELETING, PROC_REF(remove_shuttle_area))
	shuttle_area = areas

	if(initial_location)
		current_location = initial_location
	else
		current_location = SSshuttle.get_landmark(current_location)
	if(!istype(current_location))
		CRASH("Shuttle \"[name]\" could not find its starting location.")

	if(src.name in SSshuttle.shuttles)
		CRASH("A shuttle with the name '[name]' is already defined.")
	SSshuttle.shuttles[src.name] = src
	for(var/obj/structure/machinery/computer/shuttle_control/SC as anything in SSshuttle.lonely_shuttle_computers)
		if(SC.shuttle_tag == name)
			SSshuttle.lonely_shuttle_computers -= SC
			shuttle_computers += SC
	if(flags & SHUTTLE_FLAGS_PROCESS)
		SSshuttle.process_shuttles += src
	if(flags & SHUTTLE_FLAGS_SUPPLY)
		if(SScargo.shuttle)
			CRASH("A supply shuttle is already defined.")
		SScargo.shuttle = src

/datum/shuttle/Destroy()
	current_location = null

	SSshuttle.shuttles -= src.name
	SSshuttle.process_shuttles -= src
	if(SScargo.shuttle == src)
		SScargo.shuttle = null

	. = ..()

/datum/shuttle/proc/short_jump(var/obj/effect/shuttle_landmark/destination)
	if(moving_status != SHUTTLE_IDLE) return

	var/obj/effect/shuttle_landmark/start_location = current_location

	moving_status = SHUTTLE_WARMUP
	callHook("shuttle_moved", list(start_location,destination))
	if(sound_takeoff)
		if(!fuel_check(TRUE)) // Check for fuel, but don't use any.
			return
		playsound(current_location, sound_takeoff, 25, 20)
	spawn(warmup_time*10)
		if(moving_status == SHUTTLE_IDLE)
			return	//someone cancelled the launch

		if(!fuel_check()) //fuel error (probably out of fuel) occured, so cancel the launch
			var/datum/shuttle/autodock/S = src
			if(istype(S))
				S.cancel_launch(null)
			return

		moving_status = SHUTTLE_INTRANSIT //shouldn't matter but just to be safe
		// Return value was previously discarded entirely -- a refused move left
		// the ship at home while the autodock state machine went on to report a
		// successful arrival. Same defect long_jump() had.
		var/list/jump_refusal = list()
		if(!destination.is_valid(src, jump_refusal) || !attempt_move(destination))
			var/datum/shuttle/autodock/failed = src
			if(istype(failed))
				failed._report_launch_abort(jump_refusal)
		moving_status = SHUTTLE_IDLE

/datum/shuttle/proc/long_jump(var/obj/effect/shuttle_landmark/destination, var/obj/effect/shuttle_landmark/interim, var/travel_time)
	if(moving_status != SHUTTLE_IDLE)
		return

	var/obj/effect/shuttle_landmark/start_location = current_location

	moving_status = SHUTTLE_WARMUP
	callHook("shuttle_moved", list(start_location, destination))
	if(sound_takeoff)
		if(!fuel_check(TRUE)) // Check for fuel, but don't use any.
			return
		playsound(current_location, sound_takeoff, 50, 20)
	spawn(warmup_time*10)
		if(moving_status == SHUTTLE_IDLE)
			return	//someone cancelled the launch

		if(!fuel_check()) //fuel error (probably out of fuel) occured, so cancel the launch
			var/datum/shuttle/autodock/S = src
			if(istype(S))
				S.cancel_launch(null)
			return

		arrive_time = world.time + travel_time*10
		moving_status = SHUTTLE_INTRANSIT
		// The transit hop is a visual nicety, NOT a prerequisite. It used to
		// wrap this entire block, so a failed hop silently skipped the whole
		// jump and dropped straight to SHUTTLE_IDLE -- which the autodock
		// state machine then read as a completed arrival, announcing "Arriving
		// at destination" for a ship that never left home. Template sub-ships
		// dodge this entirely by having no landmark_transition at all and
		// short_jump()ing straight to the destination; if our transit hop
		// can't happen, degrade to exactly that rather than abandoning the
		// jump.
		var/reached_interim = attempt_move(interim)
		if(reached_interim)
			on_move_interim()
		var/fwooshed = 0
		destination.deploy_landing_indicators(src)
		while (world.time < arrive_time)
			if(moving_status == SHUTTLE_IDLE)
				destination.clear_landing_indicators()
				return //someone force-recalled us mid-flight
			if(!fwooshed && (arrive_time - world.time) < 100)
				fwooshed = 1
				playsound(destination, sound_landing, 50, 20)
			sleep(5)
		var/list/jump_refusal = list()
		if(!destination.is_valid(src, jump_refusal) || !attempt_move(destination))
			destination.clear_landing_indicators()
			var/datum/shuttle/autodock/failed = src
			if(istype(failed))
				failed._report_launch_abort(jump_refusal)
			// Recovery is ONLY for being genuinely stranded at the interim
			// landmark with nowhere to be -- never for undoing the player's
			// own departure. Re-docking at start_location is what flew a ship
			// straight back onto the beacon it had just undocked from, on
			// every single attempt, with no way to escape.
			//
			// A ship left sitting in transit/open space is a recoverable
			// situation the player can fly out of; a ship forcibly re-docked
			// at the place it is trying to leave is a trap.
			if(reached_interim && current_location == interim && istype(start_location, /obj/effect/shuttle_landmark/ship))
				attempt_move(start_location) //only ever back to our OWN open space, never back onto a dock

		moving_status = SHUTTLE_IDLE

/datum/shuttle/proc/fuel_check()
	return 1 //fuel check should always pass in non-overmap shuttles (they have magic engines)

/*****************
* Shuttle Moved Handling * (Observer Pattern Implementation: Shuttle Moved)
* Shuttle Pre Move Handling * (Observer Pattern Implementation: Shuttle Pre Move)
*****************/

/// The turfs that genuinely make up this hull right now.
///
/// shuttle_area holds area INSTANCES, and BYOND areas are singletons -- so if
/// anything ever stamps one of our areas onto turfs somewhere else (a vacated
/// home whose base_area resolved to the ship's own area, say), A.contents
/// silently starts reporting two footprints as though both were the ship.
///
/// Feeding that straight into get_turf_translation() is catastrophic rather
/// than merely wrong: both footprints get translated by the same offset, so the
/// leftover's sources are the very turfs the real hull is arriving on.
/// translate_turfs() then transports the newly-landed hull straight back out
/// again and reverts those turfs -- its second loop reverts every source
/// unconditionally -- leaving the contents loose on bare space with no hull
/// around them.
///
/// The hull is always where current_location is, so anything of ours outside
/// that z-range is leftover and must never enter a translation.
/datum/shuttle/proc/get_hull_turfs()
	. = list()
	var/turf/here = get_turf(current_location)
	if(!here)
		return
	var/lowest_z = here.z - multiz
	for(var/area/A in shuttle_area)
		for(var/turf/T in A.contents)
			if(T.z > here.z || T.z < lowest_z)
				continue
			. += T

/// Releases a leftover footprint our areas still cover away from the hull.
///
/// The timing is the entire safety argument. This runs only AFTER the move has
/// completed, so the real hull is -- by definition -- on current_location's own
/// z, and "ours, but on another z" identifies the leftover with nothing left to
/// get wrong. An earlier attempt ran BEFORE the move and had to guess which of
/// two footprints was real; it guessed wrong and wiped a crewed hull.
///
/// A turf with a living mob on it is skipped outright, clutter and all.
/datum/shuttle/proc/_clear_stray_footprint()
	var/turf/here = get_turf(current_location)
	if(!here)
		return
	var/lowest_z = here.z - multiz
	var/list/stray = list()
	for(var/area/A in shuttle_area)
		for(var/turf/T in A.contents)
			if(T.z <= here.z && T.z >= lowest_z)
				continue //the hull itself
			stray += T

	if(!length(stray))
		return

	var/area/space_area = locate(/area/space)
	var/cleared = 0
	for(var/turf/T as anything in stray)
		if(locate(/mob/living) in T)
			continue //never clear a turf someone is standing on
		for(var/atom/movable/AM in T)
			if(isliving(AM) || !AM.simulated)
				continue
			qdel(AM)
		if(space_area)
			T.change_area(T.loc, space_area)
		T.ChangeTurf(get_base_turf_by_area(T))
		cleared++

	if(cleared)
		log_world("SHUTTLE: '[name]' released [cleared] leftover turf(s) its areas still covered away from the hull.")

/datum/shuttle/proc/attempt_move(var/obj/effect/shuttle_landmark/destination)
	if(current_location == destination)
		return FALSE

	if(!destination.is_valid(src))
		return FALSE
	if(current_location.cannot_depart(src))
		return FALSE
	testing("[src] moving to [destination]. Areas are [english_list(shuttle_area)]")
	var/list/translation = get_turf_translation(get_turf(current_location), get_turf(destination), get_hull_turfs())
	// An OVERLAPPING move -- one where a turf is both a source and a target --
	// is something translate_turfs() cannot perform safely under any
	// circumstances. Such a turf has contents transported INTO it by one pair
	// and then transported back out (or reverted to base_turf by the second,
	// unconditional loop) by another, with the outcome decided purely by
	// iteration order. The hull is shredded rather than relocated.
	//
	// This is reachable in normal play: a landmark_transition mapped on the
	// ship's OWN z (player_built_shuttle.dm) sits close enough to the home
	// landmark that hopping between them overlaps the hull with itself. Refuse
	// instead of attempting it -- and never "fix" that refusal by letting
	// check_collision() ignore the mover's own hull, which is the change that
	// destroyed a live crewed ship.
	for(var/turf/source in translation)
		var/turf/target = translation[source]
		if(target && (target in translation))
			log_world("SHUTTLE: '[name]' refused a move to [destination] -- the destination footprint overlaps the hull's own current position.")
			return FALSE
	var/old_location = current_location
	GLOB.shuttle_pre_move_event.raise_event(src, old_location, destination)
	shuttle_moved(destination, translation)
	_clear_stray_footprint()
	GLOB.shuttle_moved_event.raise_event(src, old_location, destination)
	destination.shuttle_arrived(src)
	return TRUE

//just moves the shuttle from A to B, if it can be moved
//A note to anyone overriding move in a subtype. shuttle_moved() must absolutely not, under any circumstances, fail to move the shuttle.
//If you want to conditionally cancel shuttle launches, that logic must go in short_jump(), long_jump() or attempt_move()
/datum/shuttle/proc/shuttle_moved(var/obj/effect/shuttle_landmark/destination, var/list/turf_translation)

	if((flags & SHUTTLE_FLAGS_ZERO_G))
		var/new_grav = 1
		if(destination.landmark_flags & SLANDMARK_FLAG_ZERO_G)
			var/area/new_area = get_area(destination)
			new_grav = new_area.has_gravity
		for(var/area/our_area in shuttle_area)
			if(our_area.has_gravity != new_grav)
				our_area.gravitychange(new_grav)

	for(var/turf/src_turf in turf_translation)
		var/turf/dst_turf = turf_translation[src_turf]
		if((squishes || cargo_elevator) && src_turf.is_solid_structure()) //in case someone put a hole in the shuttle and you were lucky enough to be under it
			for(var/atom/movable/AM in dst_turf)
				if(AM.movable_flags & MOVABLE_FLAG_DEL_SHUTTLE)
					qdel(AM)
					continue
				if(!AM.simulated)
					continue
				if(isliving(AM))
					var/mob/living/safety_hater = AM
					if(squishes)
						safety_hater.gib()
					else if(cargo_elevator)
						safety_hater.visible_message(
							SPAN_WARNING("[safety_hater] falls down the cargo elevator hatch!"),
							SPAN_WARNING("You fall down the cargo elevator hatch!")
						)
						shake_camera(safety_hater, 10, 1)
						safety_hater.fall_impact(1)
						safety_hater.apply_damage(20, DAMAGE_PAIN)
				else
					if(squishes)
						qdel(AM) //it just gets atomized I guess? TODO throw it into space somewhere, prevents people from using shuttles as an atom-smasher
	var/list/powernets = list()
	for(var/area/A in shuttle_area)
		// if there was a zlevel above our origin, erase our ceiling now we're leaving
		var/turf/T = get_turf(current_location)
		if(GET_TURF_ABOVE(T))
			for(var/turf/TO in A.contents)
				var/turf/TA = GET_TURF_ABOVE(TO)
				if(istype(TA, ceiling_type))
					TA.ChangeTurf(get_base_turf_by_area(TA), 1, 1)
		if(knockdown)
			for(var/mob/living/carbon/M in A)
				spawn(0)
					if(M.buckled_to)
						to_chat(M, SPAN_WARNING("Sudden acceleration presses you into your chair!"))
						shake_camera(M, 3, 1)
					else if(M.Check_Shoegrip(FALSE))
						to_chat(M, SPAN_WARNING("You feel immense pressure in your feet as you cling to the floor!"))
						M.apply_damage(10, DAMAGE_PAIN, BP_L_FOOT)
						M.apply_damage(10, DAMAGE_PAIN, BP_R_FOOT)
						shake_camera(M, 5, 1)
					else
						to_chat(M, SPAN_WARNING("The floor lurches beneath you!"))
						shake_camera(M, 10, 1)
						M.visible_message(SPAN_WARNING("[M.name] is tossed around by the sudden acceleration!"))
						M.throw_at_random(FALSE, 4, 1)
						M.Weaken(3)

		for(var/obj/structure/cable/C in A)
			powernets |= C.powernet

	translate_turfs(turf_translation, current_location.base_area, current_location.base_turf, TRUE)
	current_location = destination

	// if there's a zlevel above our destination, paint in a ceiling on it so we retain our air
	var/turf/T = get_turf(current_location)
	if(GET_TURF_ABOVE(T))
		for(var/area/A in shuttle_area)
			for(var/turf/TD in A.contents)
				TD.update_above()
				TD.update_icon()
				var/turf/TA = GET_TURF_ABOVE(TD)
				if(istype(TA, get_base_turf_by_area(TA)) || (istype(TA) && TA.is_open()))
					if(get_area(TA) in shuttle_area)
						continue
					TA.ChangeTurf(ceiling_type, TRUE, TRUE, TRUE)

	for(var/area/sub_area in shuttle_area)
		for(var/atom/movable/movable in sub_area)
			movable.afterShuttleMove(destination)

	// Remove all powernets that were affected, and rebuild them.
	var/list/cables = list()
	for(var/datum/powernet/P in powernets)
		cables |= P.cables
		qdel(P)
	for(var/obj/structure/cable/C in cables)
		if(!C.powernet)
			var/datum/powernet/NewPN = new()
			NewPN.add_cable(C)
			propagate_network(C,C.powernet)

	if(mothershuttle)
		var/datum/shuttle/mothership = SSshuttle.shuttles[mothershuttle]
		if(mothership)
			if(current_location.landmark_tag == motherdock)
				mothership.shuttle_area |= shuttle_area
			else
				mothership.shuttle_area -= shuttle_area

//returns 1 if the shuttle has a valid arrive time
/datum/shuttle/proc/has_arrive_time()
	return (moving_status == SHUTTLE_INTRANSIT)

/datum/shuttle/proc/find_children()
	. = list()
	for(var/shuttle_name in SSshuttle.shuttles)
		var/datum/shuttle/shuttle = SSshuttle.shuttles[shuttle_name]
		if(shuttle.mothershuttle == name)
			. += shuttle

//Returns those areas that are not actually child shuttles.
/datum/shuttle/proc/find_childfree_areas()
	. = shuttle_area.Copy()
	for(var/datum/shuttle/child in find_children())
		. -= child.shuttle_area

/datum/shuttle/autodock/proc/get_location_name()
	if(moving_status == SHUTTLE_INTRANSIT)
		return "In transit"
	return current_location.name

/datum/shuttle/autodock/proc/get_destination_name()
	if(!next_location)
		return "None"
	return next_location.name

/datum/shuttle/proc/set_process_state(var/new_state)
	process_state = new_state
	for(var/obj/structure/machinery/computer/shuttle_control/SC as anything in shuttle_computers)
		SC.update_helmets(src)

/datum/shuttle/proc/on_move_interim()
	return

/datum/shuttle/proc/remove_shuttle_area(area/area_to_remove)
	UnregisterSignal(area_to_remove, COMSIG_QDELETING)
	SSshuttle.shuttle_areas -= area_to_remove
	shuttle_area -= area_to_remove
	if(!length(shuttle_area))
		qdel(src)

/// This shuttle's own hull footprint in tiles (width, height), spanning
/// every turf across every area in shuttle_area -- used by size-gated
/// docking landmarks (shuttle_landmark/player_dock's max_footprint_x/y,
/// docking_beacon.dm) to reject an oversized ship before it's ever offered
/// as a destination. Returns list(0, 0) for a shuttle with no area turfs at
/// all (shouldn't normally happen, but a 0x0 footprint fails every size
/// check safely rather than passing one it shouldn't).
/datum/shuttle/proc/get_footprint()
	var/min_x; var/max_x
	var/min_y; var/max_y
	for(var/area/A in shuttle_area)
		for(var/turf/T in get_area_turfs(A))
			if(isnull(min_x) || T.x < min_x)
				min_x = T.x
			if(isnull(max_x) || T.x > max_x)
				max_x = T.x
			if(isnull(min_y) || T.y < min_y)
				min_y = T.y
			if(isnull(max_y) || T.y > max_y)
				max_y = T.y
	if(isnull(min_x))
		return list(0, 0)
	return list(max_x - min_x + 1, max_y - min_y + 1)

/// The first docking_transponder found anywhere across this shuttle's own
/// shuttle_area, or null if it doesn't carry one -- used by
/// player_dock/is_valid() (docking_beacon.dm) for the opt-in facing check.
/// Same area/turf iteration shape as get_footprint() just above.
/datum/shuttle/proc/find_docking_transponder()
	for(var/area/A in shuttle_area)
		for(var/turf/T in get_area_turfs(A))
			var/obj/structure/machinery/docking_transponder/transponder = locate() in T
			if(transponder)
				return transponder
	return null
