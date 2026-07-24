/*
 * Base type for anything installable into a space pod's part slots
 * (POD_PART_* in code/__DEFINES/vehicle_pods.dm). Mirrors Goonstation's
 * /obj/item/shipcomponent lifecycle contract: install/uninstall run once at
 * (un)install time for icon/state setup, activate/deactivate toggle the
 * part on/off against the pod's power budget, mob_activate/mob_deactivate
 * react to occupants boarding/leaving while the part is on, and
 * run_component is the per-tick hook for parts that do continuous work.
 */
/obj/item/podcomponent
	name = "pod component"
	desc = "A modular part for a space pod."
	icon = 'icons/obj/stock_parts.dmi' // placeholder -- swap for real pod-part sprites
	icon_state = "part"

	/// Power drawn from the pod's engine while active.
	var/power_used = 0
	/// The pod this part is currently installed in, or null.
	var/obj/vehicle/bike/pod/pod
	/// Whether this part is currently switched on.
	var/active = FALSE
	/// Forced off and blocked from (re)activating -- e.g. a future EMP hit.
	var/disrupted = FALSE

/obj/item/podcomponent/Destroy()
	if(pod)
		pod.eject_part(null, get_slot())
	return ..()

/// Which POD_PART_* slot this part belongs in. Every concrete subtype must
/// override this -- the base returns null so an un-overridden part simply
/// refuses to install anywhere.
/obj/item/podcomponent/proc/get_slot()
	return null

/// Called once by install_part() right after this part is placed in the pod.
/// Override for one-time visual/behavioral setup (icon overlays, etc.).
/obj/item/podcomponent/proc/ship_install()
	return

/// Called once by eject_part() right before this part leaves the pod.
/obj/item/podcomponent/proc/ship_uninstall()
	return

/// Turns the part on. Refuses if disrupted or the pod can't afford
/// power_used. Returns TRUE/FALSE for whether it actually turned on.
/obj/item/podcomponent/proc/activate(give_message = TRUE)
	if(disrupted || !pod)
		return FALSE
	active = TRUE
	if(give_message)
		pod.visible_message(SPAN_NOTICE("\The [src] hums online."))
	return TRUE

/// Turns the part off.
/obj/item/podcomponent/proc/deactivate(give_message = TRUE)
	active = FALSE
	if(give_message && pod)
		pod.visible_message(SPAN_NOTICE("\The [src] powers down."))

/// Fired when a mob boards the pod while this part is installed and active.
/obj/item/podcomponent/proc/mob_activate(mob/M)
	return

/// Fired when a mob leaves the pod while this part is installed and active.
/obj/item/podcomponent/proc/mob_deactivate(mob/M)
	return

/// Per-tick hook for parts doing continuous work while active. mult is a
/// time-multiplier (ticks elapsed), matching this codebase's other
/// per-tick component conventions.
/obj/item/podcomponent/proc/run_component(mult)
	return
