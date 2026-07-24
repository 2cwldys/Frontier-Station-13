/*
 * Hatch lock -- toggles the pod's own existing `locked` var (inherited from
 * /obj/vehicle, already what install_part()/the maintenance panel check,
 * and now also the boarding gate in passenger.dm/access.dm). Used to live
 * under secondary_systems.dm as /secondary/lock, but that made it compete
 * with cargo/shielding for the same POD_PART_SECONDARY slot -- it has its
 * own dedicated POD_PART_LOCK slot (defined since Phase 1, never wired to
 * anything until now).
 */
/obj/item/podcomponent/lock
	name = "hatch locking unit"
	desc = "A passcode-locked hatch control for a space pod."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "lock"
	power_used = 10

/obj/item/podcomponent/lock/get_slot()
	return POD_PART_LOCK

/obj/item/podcomponent/lock/attack_self(mob/user)
	if(!pod)
		return
	pod.locked = !pod.locked
	to_chat(user, SPAN_NOTICE("You [pod.locked ? "lock" : "unlock"] \the [pod]'s hatch."))
