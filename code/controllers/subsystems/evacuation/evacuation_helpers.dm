/datum/evacuation_controller/proc/set_launch_time(var/val)
	evac_launch_time = val

/datum/evacuation_controller/proc/set_arrival_time(var/val)
	evac_arrival_time = val

/datum/evacuation_controller/proc/is_prepared()
	return (state == EVAC_LAUNCHING)

/datum/evacuation_controller/proc/is_in_transit()
	return (state == EVAC_IN_TRANSIT)

/datum/evacuation_controller/proc/is_idle()
	return (state == EVAC_IDLE)

/datum/evacuation_controller/proc/has_evacuated()
	return (!isnull(evac_launch_time) && world.time > evac_launch_time)

/datum/evacuation_controller/proc/round_over()
	return state == EVAC_COMPLETE

/datum/evacuation_controller/proc/is_on_cooldown()
	return state == EVAC_COOLDOWN

/datum/evacuation_controller/proc/is_evacuating()
	return state != EVAC_IDLE

/// TRUE when this persistent world has been configured to never go through a
/// traditional round end -- shuttle calls, round-end votes, and nuke
/// round-ending are all gated behind this, admins included, but only while
/// persistence (sql_enabled) is actually active.
/proc/round_end_locked()
	return GLOB.config.disable_round_end && GLOB.config.sql_enabled

/datum/evacuation_controller/proc/can_evacuate(var/mob/user, var/forced)
	if(round_end_locked())
		return FALSE

	if(!isnull(evac_called_at))
		return FALSE

	if (!GLOB.universe.OnShuttleCall(null))
		return FALSE

	if(!forced)
		for(var/predicate in evacuation_predicates)
			var/datum/evacuation_predicate/esp = predicate
			if(!esp.is_valid())
				evacuation_predicates -= esp
				qdel(esp)
			else
				if(!esp.can_call(user))
					return FALSE
	return TRUE

/datum/evacuation_controller/proc/waiting_to_leave()
	return FALSE

/datum/evacuation_controller/proc/can_cancel()
	// Are we evacuating?
	if(isnull(evac_called_at))
		return FALSE
	// Have we already launched?
	if(state != EVAC_PREPPING)
		return FALSE
	// Are we already committed?
	if(world.time > evac_no_return)
		return FALSE
	return TRUE

/datum/evacuation_controller/proc/is_arriving()
	if(state == EVAC_LAUNCHING)
		return FALSE
	return has_eta()

/datum/evacuation_controller/proc/is_departing()
	if(state == EVAC_LAUNCHING)
		return TRUE
