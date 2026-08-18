#define DOCK_ATTEMPT_TIMEOUT 200	//how long in ticks we wait before assuming the docking controller is broken or blown up.

/datum/shuttle/autodock
	var/in_use = null  //tells the controller whether this shuttle needs processing, also attempts to prevent double-use
	var/last_dock_attempt_time = 0
	var/current_dock_target

	/// `id_tag`/`master_tag` of the docking controller of this shuttle.
	var/dock_target = null

	var/obj/effect/shuttle_landmark/next_location
	var/datum/computer/file/embedded_program/docking/active_docking_controller

	var/obj/effect/shuttle_landmark/landmark_transition
	var/move_time = 240  //the time spent in the transition area
	var/minimum_move_time = 15  //the time spent in the transition area when both of the locations are located on station z-levels

	category = /datum/shuttle/autodock
	flags = SHUTTLE_FLAGS_PROCESS | SHUTTLE_FLAGS_ZERO_G

/datum/shuttle/autodock/New(var/_name, var/obj/effect/shuttle_landmark/start_waypoint)
	..(_name, start_waypoint)

	//Initial dock
	update_docking_target(current_location)
	active_docking_controller = current_location.docking_controller
	current_dock_target = get_docking_target(current_location)
	dock()

	//Optional transition area
	if(landmark_transition)
		landmark_transition = SSshuttle.get_landmark(landmark_transition)

/datum/shuttle/autodock/Destroy()
	next_location = null
	active_docking_controller = null
	landmark_transition = null

	return ..()

/datum/shuttle/autodock/shuttle_moved()
	force_undock() //bye!
	..()

/datum/shuttle/autodock/proc/update_docking_target(var/obj/effect/shuttle_landmark/location)
	if(location && location.special_dock_targets && location.special_dock_targets[name])
		current_dock_target = location.special_dock_targets[name]
	else
		current_dock_target = dock_target
	active_docking_controller = SSshuttle.docking_registry[current_dock_target]

/datum/shuttle/autodock/proc/get_docking_target(var/obj/effect/shuttle_landmark/location)
	if(location && location.special_dock_targets)
		if(location.special_dock_targets[name])
			return location.special_dock_targets[name]
	return dock_target
/*
	Docking stuff
*/
/datum/shuttle/autodock/proc/dock()
	if(active_docking_controller)
		active_docking_controller.initiate_docking(current_dock_target)
		last_dock_attempt_time = world.time

/datum/shuttle/autodock/proc/undock()
	if(active_docking_controller)
		active_docking_controller.initiate_undocking()

/datum/shuttle/autodock/proc/force_undock()
	if(active_docking_controller)
		active_docking_controller.force_undock()

/datum/shuttle/autodock/proc/check_docked()
	if(active_docking_controller)
		return active_docking_controller.docked()
	return TRUE

/datum/shuttle/autodock/proc/check_undocked()
	if(active_docking_controller)
		return active_docking_controller.can_launch()
	return TRUE

/*
	Please ensure that long_jump() and short_jump() are only called from here. This applies to subtypes as well.
	Doing so will ensure that multiple jumps cannot be initiated in parallel.
*/
/datum/shuttle/autodock/process()
	switch(process_state)
		if (WAIT_LAUNCH)
			if(check_undocked())
				//*** ready to go
				var/list/launch_refusal = list()
				if(next_location.is_valid(src, launch_refusal))
					process_launch()
					set_process_state(WAIT_ARRIVE)
				else
					// Never abort silently -- see _report_launch_abort().
					_report_launch_abort(launch_refusal)
					set_process_state(IDLE_STATE)
					in_use = null

		if (FORCE_LAUNCH)
			process_launch()

		if (WAIT_ARRIVE)
			if (moving_status == SHUTTLE_IDLE)
				// moving_status alone only proves the jump FINISHED, not that
				// it succeeded -- a refused move leaves the ship exactly where
				// it started and still returns to IDLE. Without this check the
				// console cheerfully announced "Arriving at destination now."
				// for a ship that never left its own home Z.
				if(next_location && current_location != next_location)
					set_process_state(IDLE_STATE)
					in_use = null
					next_location = null
					return
				//*** we made it to the destination, update stuff
				process_arrived()
				set_process_state(WAIT_FINISH)

		if (WAIT_FINISH)
			if (world.time > last_dock_attempt_time + DOCK_ATTEMPT_TIMEOUT || check_docked())
				//*** all done here
				set_process_state(IDLE_STATE)
				arrived()

//not to be confused with the arrived() proc
/datum/shuttle/autodock/proc/process_arrived()
	update_docking_target(next_location)
	active_docking_controller = next_location.docking_controller
	current_dock_target = get_docking_target(next_location)
	dock()

	next_location = null
	in_use = null	//release lock

/datum/shuttle/autodock/proc/get_travel_time()
	if(is_station_level(current_location.loc.z) && is_station_level(next_location.loc.z) && move_time > minimum_move_time)
		return minimum_move_time
	else
		return move_time

/// Tells the player who pressed Launch -- and everyone aboard -- exactly why
/// a launch was aborted, instead of dropping back to idle with no feedback at
/// all. Both abort paths below re-run is_valid() STRICTLY, while
/// get_possible_destinations() (overmap_shuttle.dm) lists candidates
/// LENIENTLY, so a destination can legitimately be offered, picked, and
/// accepted and then refused here -- which without this reads to the player
/// as the console saying "Starting Ignition" and then simply never moving.
///
/// Broadcast shape mirrors fuel_check()'s own "engines sputter" failure
/// (overmap_shuttle.dm), so a launch failure always reaches the same people
/// whichever way it failed.
/datum/shuttle/autodock/proc/_report_launch_abort(list/reason)
	var/detail = ""
#ifdef DOCKING_REFUSAL_DIAGNOSTICS
	// Raw turf types/coordinates are diagnostic detail -- the plain "the
	// destination is obstructed" line below always shows regardless.
	if(length(reason))
		detail = " ([jointext(reason, "; ")])"
#endif
	var/message = "Launch aborted -- the destination is obstructed or no longer valid[detail]."
	if(ismob(in_use))
		var/mob/launching_user = in_use
		to_chat(launching_user, SPAN_WARNING(message))
	for(var/area/A in shuttle_area)
		for(var/mob/living/M in A)
			if(M == in_use)
				continue
			M.show_message(SPAN_WARNING(message), 2)

/datum/shuttle/autodock/proc/process_launch()
	var/list/launch_refusal = list()
	if(!next_location.is_valid(src, launch_refusal) || current_location.cannot_depart(src))
		_report_launch_abort(launch_refusal)
		set_process_state(IDLE_STATE)
		in_use = null
		return
	if (get_travel_time() && landmark_transition)
		long_jump(next_location, landmark_transition, get_travel_time())
	else
		short_jump(next_location)
	set_process_state(WAIT_ARRIVE)

/*
	Guards
*/
/datum/shuttle/autodock/proc/can_launch()
	return (next_location && moving_status == SHUTTLE_IDLE && !in_use)

/datum/shuttle/autodock/proc/can_force()
	return (next_location && moving_status == SHUTTLE_IDLE && process_state == WAIT_LAUNCH)

/datum/shuttle/autodock/proc/can_cancel()
	return (moving_status == SHUTTLE_WARMUP || process_state == WAIT_LAUNCH || process_state == FORCE_LAUNCH)

/*
	"Public" procs
*/
/datum/shuttle/autodock/proc/launch(var/user)
	if(!can_launch())
		return

	in_use = user	//obtain an exclusive lock on the shuttle

	set_process_state(WAIT_LAUNCH)
	undock()

/datum/shuttle/autodock/proc/force_launch(var/user)
	if(!can_force())
		return

	in_use = user	//obtain an exclusive lock on the shuttle

	set_process_state(FORCE_LAUNCH)

/datum/shuttle/autodock/proc/cancel_launch(var/user)
	if (!can_cancel()) return

	moving_status = SHUTTLE_IDLE
	set_process_state(WAIT_FINISH)
	in_use = null

	//whatever we were doing with docking: stop it, then redock
	force_undock()
	spawn(1 SECOND)
		dock()

//returns 1 if the shuttle is getting ready to move, but is not in transit yet
/datum/shuttle/autodock/proc/is_launching()
	return (moving_status == SHUTTLE_WARMUP || process_state == WAIT_LAUNCH || process_state == FORCE_LAUNCH)

//This gets called when the shuttle finishes arriving at it's destination
//This can be used by subtypes to do things when the shuttle arrives.
//Note that this is called when the shuttle leaves the WAIT_FINISHED state, the proc name is a little misleading
/datum/shuttle/autodock/proc/arrived()
	_play_landing_sound()

/// Plays the shuttle landing/docking sound to everyone aboard, unconditionally,
/// the moment docking is actually confirmed complete -- the arrival-side
/// counterpart to shuttle_control's own _play_launch_sound() (shuttle_console.dm),
/// same reasoning: a direct cue tied to the real event, not inferred from any
/// engine on/off bookkeeping.
/datum/shuttle/autodock/proc/_play_landing_sound()
	for(var/area/A in shuttle_area)
		for(var/mob/M in A)
			if(!M.client || M.ear_deaf)
				continue
			if(!(M.client.prefs.sfx_toggles & ASFX_ENGINE_HUM))
				continue
			M << sound('sound/effects/shuttle_landing.ogg', volume = 50)

#undef DOCK_ATTEMPT_TIMEOUT
