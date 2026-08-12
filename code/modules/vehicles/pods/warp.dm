/*
 * Pod warp engine -- subtypes the Phase 1 engine and adds sector-to-sector
 * jumping. Reuses the base engine's own phoron fuel_tank (engine.dm) for
 * jump fuel too -- attempt_jump() drains a further fixed amount from the
 * same tank ignition already depends on, no separate jump-fuel slot.
 *
 * Destination selection is not a server-computed reachable-sector list --
 * it's whatever the pilot primed by clicking a sector in the pod's Sector
 * View (sector_view.dm, almost entirely lifted from personal_travel.dm's
 * eye-view trick). attempt_jump() just re-validates that prime and executes,
 * mirroring personal_travel.dm's own "prime via click, re-validate at
 * execute time" flow -- including its spark/portal/sound travel flourish
 * (_execute_travel()), reused near-verbatim below.
 *
 * Making the pod itself sensor-detectable during a jump (rather than giving
 * it a permanent overmap presence, which Aurora's one-marker-per-z-level
 * invariant forbids for a single-tile vehicle -- see pod_contact.dm) is
 * handled by a lightweight, non-z-level-owning /obj/effect/overmap/pod_contact
 * marker spawned only for the jump's spool duration -- Aurora's real
 * contact_sensors.dm scan picks it up with zero changes to that code, since
 * it's just another /obj/effect/overmap on the grid.
 */
/obj/item/podcomponent/engine/warp
	name = "warp engine"
	desc = "A compact drive engine for a space pod, fitted with a bluespace warp coil."
	var/last_jump = 0

/**
 * Attempts a warp jump to whatever the pilot last primed via the pod's
 * Sector View (sector_view.dm). Validates comms, the prime itself, cooldown,
 * and fuel (server-side re-check -- never trust a stale client-side prime),
 * then spools, drains fuel, spawns a transient sensor-detectable marker for
 * the spool duration, and forceMoves the pod (and its buckled pilot) to a
 * landing turf -- with the same spark/portal/sound travel flourish
 * personal_travel.dm's _execute_travel() uses.
 */
/obj/item/podcomponent/engine/warp/proc/attempt_jump(mob/user)
	if(!active || disrupted || !pod)
		return FALSE
	var/obj/item/podcomponent/comms/C = pod.get_part(POD_PART_COMMS)
	if(!istype(C) || !C.active)
		to_chat(user, SPAN_WARNING("\The [pod]'s navigation network is offline -- install and activate a comms array."))
		return FALSE
	var/obj/effect/overmap/visitable/destination = pod.get_primed_destination()
	if(!destination)
		to_chat(user, SPAN_WARNING("No jump destination primed -- use Sector View to select one."))
		return FALSE
	if(ship_shields_block_travel(destination, user))
		to_chat(user, SPAN_WARNING("\The [destination]'s shields are still up -- bluespace calibration cannot lock onto its interior."))
		return FALSE
	if(world.time < last_jump + POD_JUMP_COOLDOWN)
		to_chat(user, SPAN_WARNING("\The [src] hasn't finished recharging."))
		return FALSE
	if(!fuel_tank || fuel_tank.air_contents.get_by_flag(XGM_GAS_FUEL) < POD_JUMP_FUEL_MOLES)
		to_chat(user, SPAN_WARNING("\The [src] doesn't have enough fuel for a jump."))
		return FALSE

	// Landing turf is picked now, before the spool, instead of after --
	// lets destination-side spark pulses (below) warn anyone already there,
	// same as every other spool-travel mechanic. Re-validated after the wait
	// since the pick can go stale during the spool window.
	var/chosen_z = pick(destination.map_z)
	var/turf/landing = pick_area_turf_in_connected_z_levels(list(), list(/proc/turf_clear, /proc/_drydock_pick_turf_valid = list(user, chosen_z)), chosen_z)
	if(!landing)
		to_chat(user, SPAN_WARNING("\The [pod] fails to find a safe place to land -- the jump is aborted."))
		return FALSE

	var/obj/effect/overmap/visitable/origin = pod.get_current_sector()
	var/obj/effect/overmap/pod_contact/blip = new(get_turf(origin))
	to_chat(user, SPAN_NOTICE("\The [pod] begins calibrating a bluespace jump..."))
	var/list/spool_token = list(TRUE)
	_start_travel_spool_pulses(get_turf(pod), landing, POD_JUMP_SPOOL_TIME, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_spool_token_valid), spool_token))
	if(!do_after(user, POD_JUMP_SPOOL_TIME, pod))
		spool_token[1] = FALSE
		qdel(blip)
		to_chat(user, SPAN_WARNING("Bluespace calibration interrupted."))
		return FALSE
	if(QDELETED(src) || QDELETED(pod) || pod.get_part(POD_PART_ENGINE) != src)
		qdel(blip)
		return FALSE
	// Prime can go stale during the spool window (destination re-validated
	// live, same as personal_travel.dm's own post-spool-up recheck).
	destination = pod.get_primed_destination()
	if(!destination)
		qdel(blip)
		to_chat(user, SPAN_WARNING("The jump destination is no longer valid."))
		return FALSE
	if(ship_shields_block_travel(destination, user))
		qdel(blip)
		to_chat(user, SPAN_WARNING("\The [destination]'s shields came back up -- the jump is aborted."))
		return FALSE
	// The specific landing turf picked before the spool can also go stale
	// (something else may have moved onto/claimed it since) -- re-check it's
	// still clear rather than trusting the pre-spool pick blindly.
	if(!(chosen_z in destination.map_z) || !turf_clear(landing) || !_drydock_pick_turf_valid(landing, user, chosen_z))
		qdel(blip)
		to_chat(user, SPAN_WARNING("\The [pod]'s landing spot is no longer safe -- the jump is aborted."))
		return FALSE

	fuel_tank.remove_air_by_flag(XGM_GAS_FUEL, POD_JUMP_FUEL_MOLES)
	last_jump = world.time

	qdel(blip)
	pod.primed_ref = null

	// Spark/portal/sound at both ends -- lifted from personal_travel.dm's
	// _execute_travel(). forceMove, not do_teleport: same reasoning as that
	// proc's own comment (a science teleport datum would scatter anyone
	// carrying a bag of holding up to 100 tiles).
	var/turf/origin_turf = get_turf(pod)
	if(origin_turf)
		new /obj/effect/portal/decorative/fading(origin_turf, null, null, 5 SECONDS, 0)
		spark(origin_turf, 3, GLOB.alldirs)
		playsound(origin_turf, 'sound/effects/phasein.ogg', 30, 1)
	new /obj/effect/portal/decorative/fading(landing, null, null, 5 SECONDS, 0)
	spark(landing, 3, GLOB.alldirs)

	// /obj/vehicle's own Move() explicitly forceMoves its buckled load along
	// with it (vehicle.dm:78) -- a raw forceMove() on the pod alone does not
	// carry the pilot, so it's repeated here.
	pod.forceMove(landing)
	if(pod.load && !istype(pod.load, /datum/vehicle_dummy_load))
		pod.load.forceMove(landing)
	playsound(landing, 'sound/effects/phasein.ogg', 30, 1)
	to_chat(user, SPAN_GOOD("You leap through a bluespace rift."))
	return TRUE

/obj/vehicle/bike/pod/proc/get_current_sector()
	return GLOB.map_sectors["[z]"]

/*
 * A transient, non-z-level-owning overmap marker spawned only for the
 * duration of a pod's warp-jump spool, so Aurora's real ship-scale sensor
 * scan (contact_sensors.dm's process(), unmodified) can detect a jumping pod
 * as a genuine overmap contact. Deliberately subtypes the plain
 * /obj/effect/overmap base, NOT /obj/effect/overmap/visitable -- the
 * /visitable subtype's Initialize() unconditionally calls find_z_levels()/
 * register_z_levels() (sectors.dm), which would wrongly try to register
 * this marker as owning the overmap z-level it's spawned on. A pod's real
 * body never needs a z-level of its own -- it's forceMove()'d directly
 * between EXISTING sectors' EXISTING z-levels (see attempt_jump() above).
 */
/obj/effect/overmap/pod_contact
	name = "unidentified contact"
	desc = "A faint bluespace signature."
	icon_state = "object"
	anchored = TRUE
	requires_contact = TRUE
	scannable = TRUE
	sensor_visibility = 20
