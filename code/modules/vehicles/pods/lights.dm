/*
 * Pod running lights -- POD_PART_LIGHTS has been a defined slot since
 * Phase 1 with nothing to install in it; this fills that gap. Just toggles
 * the pod's own light source via the generic /atom/proc/set_light().
 */
/obj/item/podcomponent/lights
	name = "running lights"
	desc = "An exterior light fixture for a space pod."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "star_lights"
	power_used = 5

	var/light_range_on = 3
	var/light_power_on = 1

/obj/item/podcomponent/lights/get_slot()
	return POD_PART_LIGHTS

/obj/item/podcomponent/lights/activate(give_message = TRUE)
	. = ..()
	if(. && pod)
		pod.set_light(light_range_on, light_power_on)

/obj/item/podcomponent/lights/deactivate(give_message = TRUE)
	..()
	if(pod)
		pod.set_light(0)

/obj/item/podcomponent/lights/Destroy()
	if(pod && active)
		pod.set_light(0)
	return ..()
