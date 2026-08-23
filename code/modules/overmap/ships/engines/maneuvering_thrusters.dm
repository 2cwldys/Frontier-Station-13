/datum/ship_engine/maneuvering
	name = "maneuvering thruster"
	var/obj/structure/machinery/maneuvering_engine/thruster

/datum/ship_engine/maneuvering/New(obj/structure/machinery/_holder)
	..()
	thruster = _holder

/datum/ship_engine/maneuvering/Destroy()
	thruster = null
	. = ..()

/datum/ship_engine/maneuvering/get_status()
	return thruster.get_status()

/datum/ship_engine/maneuvering/get_thrust()
	return thruster.get_thrust()

/datum/ship_engine/maneuvering/burn(var/power_modifier = 1, play_sound = TRUE)
	return thruster.burn(power_modifier, play_sound)

/datum/ship_engine/maneuvering/set_thrust_limit(new_limit)
	thruster.thrust_limit = new_limit

/datum/ship_engine/maneuvering/get_thrust_limit()
	return thruster.thrust_limit

/datum/ship_engine/maneuvering/is_on()
	return thruster.on

/datum/ship_engine/maneuvering/toggle()
	thruster.on = !thruster.on

/datum/ship_engine/maneuvering/can_burn()
	return thruster.on

/obj/structure/machinery/maneuvering_engine
	name = "pulse-maneuvering device"
	desc = "This engine is outfitted with an internal reservoir of pressurized gas. It's primarily intended to slowly move the vessel into dock, but can be used as very low level thrusters in a pinch."
	icon = 'icons/obj/ship_engine.dmi'
	icon_state = "nozzle"
	anchored = TRUE
	component_types = list(
		/obj/item/circuitboard/engine/maneuvering,
		/obj/item/stack/cable_coil = 2,
		/obj/item/stock_parts/matter_bin,
		/obj/item/stock_parts/capacitor = 2
	)

	var/datum/ship_engine/maneuvering/controller
	var/thrust_limit = 1
	var/on = TRUE
	var/generated_thrust = 2

/obj/structure/machinery/maneuvering_engine/Initialize()
	. = ..()
	controller = new(src)
	sync_ship_registration()

/// Finds this engine's own ship (if any) and registers its controller into
/// S.engines -- mirrors ion_thruster.dm's own proc of the same name exactly.
/// Without this, the controller created above is never actually reachable
/// from ship.engines/the engine control terminal/_update_engine_hum()'s
/// any_on check at all, mapped-in or captured alike -- this type never had
/// it, so a maneuvering-thruster-only ship's engines were invisible to all
/// three even where mapped.
/obj/structure/machinery/maneuvering_engine/proc/sync_ship_registration()
	if(!(length(SSshuttle.shuttle_areas) && !length(SSshuttle.shuttles_to_initialize) && SSshuttle.initialized))
		return
	for(var/obj/effect/overmap/visitable/ship/S as anything in SSshuttle.ships)
		if(S.check_ownership(src))
			S.engines |= controller
			return

/obj/structure/machinery/maneuvering_engine/Destroy()
	QDEL_NULL(controller)
	return ..()

/obj/structure/machinery/maneuvering_engine/attackby(obj/item/attacking_item, mob/user)
	. = ..()
	if(default_deconstruction_screwdriver(user, attacking_item))
		return TRUE
	if(default_deconstruction_crowbar(user, attacking_item))
		return TRUE
	if(default_part_replacement(user, attacking_item))
		return TRUE

/obj/structure/machinery/maneuvering_engine/proc/get_status()
	. = list()

	. += list(list(
		"text" = "Location: [get_area(src)].",
		"severity" = "info"
	))

/obj/structure/machinery/maneuvering_engine/proc/burn(var/power_modifier = 1, play_sound = TRUE)
	if(play_sound)
		playsound(loc, 'sound/machines/thruster.ogg', (50 * thrust_limit * power_modifier), FALSE, world.view * 4, 0.1)
	. = thrust_limit * generated_thrust * power_modifier

/obj/structure/machinery/maneuvering_engine/proc/get_thrust()
	return thrust_limit * generated_thrust * on
