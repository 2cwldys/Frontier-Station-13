/*
 * Pod passenger seat -- a second occupant slot alongside the existing
 * single-slot pilot mechanic (buckled/load, inherited from /obj/vehicle).
 * Handled in parallel to the generic single-slot buckle system
 * (code/game/objects/buckling.dm) rather than through it: /obj/proc/buckle()
 * only supports one occupant per object (its own buckled/buckled_to vars
 * are scalar), and calling it a second time would silently steal the
 * pilot's own buckle link rather than fail cleanly. The passenger only ever
 * rides along -- no cockpit/weapon/warp access, which stays gated on
 * `buckled` (the pilot) everywhere it already was.
 *
 * Also fixes the buckled pilot's mob sprite rendering on top of the pod.
 * First attempt (pushing layer below the pod's own) only partly worked --
 * a human mob composites multiple part overlays (head included) that don't
 * all respect a single relative layer change the same way. alpha = 0 hides
 * every composited part regardless of how the rendering pipeline layers
 * them, with no per-part edge cases to chase.
 */
/obj/vehicle/bike/pod
	/// Second occupant -- rides along, doesn't drive. See board_passenger()/
	/// eject_passenger() below.
	var/mob/living/passenger
	/// Snapshot of each occupant's pre-boarding `cloaked` state, restored on
	/// exit by unhide_occupant() -- see that proc for why this can't just be
	/// hardcoded back to FALSE.
	var/pilot_was_cloaked = FALSE
	var/passenger_was_cloaked = FALSE

/// Also the ID-lock boarding gate (access.dm): a locked, owned pod refuses
/// to load anyone (pilot or passenger) whose ID doesn't match the claim --
/// boarding was never actually gated on `locked` before this. Also refuses
/// anyone holding an item in either hand -- see hands_full() below.
/obj/vehicle/bike/pod/load(atom/movable/thing_to_load)
	if(ismob(thing_to_load) && !pod_allowed(thing_to_load))
		to_chat(thing_to_load, SPAN_WARNING("\The [src] refuses to let you board -- access denied."))
		return FALSE
	if(ismob(thing_to_load) && hands_full(thing_to_load))
		to_chat(thing_to_load, SPAN_WARNING("You need your hands free to board \the [src]."))
		return FALSE
	if(load && ismob(thing_to_load))
		return board_passenger(thing_to_load)
	. = ..()
	if(. && ismob(thing_to_load))
		pilot_was_cloaked = hide_occupant(thing_to_load)

/// TRUE if either hand is holding something -- boarding (both seats) refuses
/// outright until both are empty, and nothing can be picked up while seated
/// either (see the /mob/living/carbon/human/equip_to_slot_if_possible()
/// override below) -- so an occupant's hands stay empty for the whole ride.
/obj/vehicle/bike/pod/proc/hands_full(mob/living/M)
	return M.l_hand || M.r_hand

/// unload() doesn't null `load` until after it internally calls unbuckle()
/// (vehicle.dm) -- capture the mob reference before calling ..() so hiding
/// can be undone on the right mob afterward.
/obj/vehicle/bike/pod/unload(mob/user, direction)
	var/atom/movable/former = load
	. = ..()
	if(ismob(former))
		unhide_occupant(former, pilot_was_cloaked)

/**
 * Fully hides an occupant, not just their base sprite. `alpha = 0` alone
 * (the original Phase 6 fix) only hides the mob's own composited icon --
 * worn/held equipment overlays are built with appearance_flags =
 * RESET_ALPHA (code/game/objects/items/items_icon.dm's get_mob_overlay(),
 * deliberately so those overlays don't fade from unrelated mob-alpha
 * effects), so they ignore the mob's alpha entirely and stayed visible.
 * Reuses the human mob's own real cloaking mechanism instead of fighting
 * that: /mob/living/carbon/human/update_icon() (update_icons.dm) already has
 * a `cloaked` branch that renders a reduced overlay set, exercised today by
 * code/game/objects/items/weapons/cloaking_device.dm -- confirmed nothing
 * else in the codebase reads or writes `cloaked` (living_defines.dm), so
 * toggling it here has no combat/detection side effects. alpha = 0 is kept
 * too as the fallback for any non-human occupant, since `cloaked` is only
 * ever checked by the human-specific render branch.
 * Returns the occupant's pre-existing `cloaked` value so a genuinely active
 * cloaking device isn't clobbered -- see unhide_occupant().
 *
 * Also grants TRAIT_PRESSURE_IMMUNITY -- the pod's own desc already claims
 * to be "pressurized," but it isn't an actual sealed atmos room, so without
 * this an occupant's own tile is genuine vacuum while flying through space.
 * This trait is the exact, real, already-used mechanism a hardsuit's own
 * protection relies on -- checked by pressure_resistant() (blocks vacuum
 * brute/oxygen damage, human_helpers.dm) and short-circuits breathe()
 * entirely (breathe.dm) -- so boarding now genuinely delivers what the pod
 * claims. Source-tagged so it can't conflict with any other real reason a
 * mob might independently have the same trait (e.g. a hardsuit).
 */
/obj/vehicle/bike/pod/proc/hide_occupant(mob/living/M)
	M.alpha = 0
	. = M.cloaked
	M.cloaked = TRUE
	M.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	M.update_icon()
	ADD_TRAIT(M, TRAIT_PRESSURE_IMMUNITY, "pod_occupant")
	M.update_vision_cone() // re-checks check_fov() now that buckled_to is set -- suppresses the rider's own cone immediately instead of waiting for their next turn/move

/// Restores what hide_occupant() changed -- was_cloaked is the value it
/// returned when this occupant boarded, not a hardcoded FALSE, so a real
/// cloaking device that was already active stays active after the ride.
/obj/vehicle/bike/pod/proc/unhide_occupant(mob/living/M, was_cloaked)
	M.alpha = initial(M.alpha)
	M.cloaked = was_cloaked
	M.mouse_opacity = initial(M.mouse_opacity)
	M.update_icon()
	REMOVE_TRAIT(M, TRAIT_PRESSURE_IMMUNITY, "pod_occupant")
	M.update_vision_cone() // buckled_to is already cleared by this point -- restores the normal cone immediately instead of waiting for their next turn/move

/**
 * Right-click the pod to eject an occupant without needing to be the one
 * driving -- refuses outright on a locked pod. Prompts for which seat if
 * both are filled; ejects the only occupied one directly otherwise.
 */
/obj/vehicle/bike/pod/RightClick(mob/user)
	if(!buckled && !passenger)
		return ..()
	if(use_check_and_message(user))
		return
	if(locked)
		to_chat(user, SPAN_WARNING("\The [src] is locked."))
		return
	var/mob/living/target
	if(buckled && passenger)
		var/list/choices = list("Pilot ([buckled])" = buckled, "Passenger ([passenger])" = passenger)
		var/pick = tgui_input_list(user, "Eject who from \the [src]?", "Eject Occupant", choices)
		if(!pick)
			return
		target = choices[pick]
	else
		target = buckled || passenger
	if(target == buckled)
		unload(user)
	else if(target == passenger)
		eject_passenger()

/// Only the pilot's (buckled's) movement input actually drives the pod --
/// without this, the passenger's own buckled_to would redirect their WASD
/// into relaymove() same as the pilot's, letting them drive too.
/obj/vehicle/bike/pod/relaymove(mob/living/user, direction)
	if(user != buckled)
		return FALSE
	return ..()

/obj/vehicle/bike/pod/proc/board_passenger(mob/living/user)
	if(passenger || user.buckled_to || !user.can_be_buckled)
		return FALSE
	if(hands_full(user))
		to_chat(user, SPAN_WARNING("You need your hands free to board \the [src]."))
		return FALSE
	if(user.loc != loc)
		step_towards(user, src)
		if(user.loc != loc)
			return FALSE
	user.buckled_to = src
	user.set_dir(dir)
	user.facing_dir = null
	user.update_canmove()
	user.throw_alert(ALERT_BUCKLED, /atom/movable/screen/alert/buckled)
	passenger_was_cloaked = hide_occupant(user)
	passenger = user
	user.visible_message(SPAN_NOTICE("[user] climbs into \the [src]'s passenger seat."), SPAN_NOTICE("You climb into \the [src]'s passenger seat."))
	return TRUE

/obj/vehicle/bike/pod/proc/eject_passenger()
	var/mob/living/former = passenger
	if(!former)
		return FALSE
	passenger = null
	former.buckled_to = null
	unhide_occupant(former, passenger_was_cloaked)
	former.update_canmove()
	former.clear_alert(ALERT_BUCKLED)
	former.visible_message(SPAN_NOTICE("[former] climbs out of \the [src]'s passenger seat."), SPAN_NOTICE("You climb out of \the [src]'s passenger seat."))
	return TRUE

/// Called from cockpit.dm's attack_hand() override -- lets the passenger
/// eject themselves by clicking the pod empty-handed, same as the pilot
/// already does (via ui_interact()) and bike.dm's own unbuckle-someone-else
/// flow does for onlookers.
/obj/vehicle/bike/pod/proc/passenger_attack_hand(mob/user)
	if(user == passenger)
		eject_passenger()
		return TRUE
	return FALSE

/// Passengers get stunned and ejected alongside the pilot on destruction,
/// same as explode()'s existing handling of `load` (vehicle.dm:236-238).
/obj/vehicle/bike/pod/explode()
	if(passenger)
		var/mob/living/P = passenger
		P.apply_effects(5, 5)
		eject_passenger()
	return ..()

/**
 * Nothing can be put into either hand while seated in a pod -- the boarding
 * gate above already refuses entry with a full hand, so this keeps that
 * true for the whole ride, not just at the door. equip_to_slot_if_possible()
 * (code/modules/mob/inventory.dm:35) is the single real choke point every
 * hand-equip path funnels through -- put_in_active_hand()/
 * put_in_inactive_hand() (human/inventory.dm:500-506) both call it directly,
 * and so does every drag-and-drop/click-to-take/handed-an-item path in the
 * game. Overridden here (not edited in the shared file) and scoped tightly
 * to pods specifically via buckled_to's type -- bikes, wheelchairs, beds,
 * and every other buckle-capable object keep working exactly as today.
 */
/mob/living/carbon/human/equip_to_slot_if_possible(obj/item/item_to_equip, slot, delete_on_fail = FALSE, disable_warning = FALSE, redraw_mob = TRUE, bypass_blocked_check = FALSE, assisted_equip = FALSE)
	if((slot == slot_l_hand || slot == slot_r_hand) && istype(buckled_to, /obj/vehicle/bike/pod))
		if(!disable_warning)
			to_chat(src, SPAN_WARNING("Your hands are occupied riding \the [buckled_to] -- you can't hold anything else."))
		return FALSE
	return ..()
