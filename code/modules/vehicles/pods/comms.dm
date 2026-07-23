/*
 * Pod comms array -- a pure gate flag for the cockpit's Navigation panel and
 * warp jumps. No external-speaker chat or hangar-door remote -- out of
 * scope for this system for now -- without an installed, active comms
 * part, the cockpit's Navigation panel stays locked and warp.dm's
 * attempt_jump() refuses outright.
 */
/obj/item/podcomponent/comms
	name = "comms array"
	desc = "A short-range communications and navigation-network transceiver for a space pod."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "com"
	power_used = 10

/obj/item/podcomponent/comms/get_slot()
	return POD_PART_COMMS
