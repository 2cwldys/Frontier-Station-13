//electric engine, should be very rare
/datum/ship_engine/ion
	name = "ion thruster"
	var/obj/structure/machinery/ion_engine/thruster

/datum/ship_engine/ion/New(obj/structure/machinery/_holder)
	..()
	thruster = _holder

/datum/ship_engine/ion/Destroy()
	thruster = null
	. = ..()

/datum/ship_engine/ion/get_status()
	return thruster.get_status()

/datum/ship_engine/ion/get_thrust()
	return thruster.get_thrust()

/datum/ship_engine/ion/burn(var/power_modifier = 1)
	return thruster.burn(power_modifier)

/datum/ship_engine/ion/set_thrust_limit(new_limit)
	thruster.thrust_limit = new_limit

/datum/ship_engine/ion/get_thrust_limit()
	return thruster.thrust_limit

/datum/ship_engine/ion/is_on()
	return thruster.on && thruster.powered()

/datum/ship_engine/ion/toggle()
	thruster.on = !thruster.on

/datum/ship_engine/ion/can_burn()
	return thruster.on && thruster.powered()

/obj/structure/machinery/ion_engine
	name = "ion propulsion device"
	desc = "An advanced ion propulsion device, converting stored electrical charge directly into thrust -- no piped fuel gas needed."
	icon = 'icons/obj/ship_engine.dmi'
	icon_state = "nozzle"
	power_channel = AREA_USAGE_ENVIRON
	idle_power_usage = 19600
	anchored = TRUE
	component_types = list(
		/obj/item/circuitboard/engine/ion,
		/obj/item/stack/cable_coil = 2,
		/obj/item/stock_parts/matter_bin,
		/obj/item/stock_parts/capacitor = 2
	)

	var/datum/ship_engine/ion/controller
	var/thrust_limit = 1
	var/on = TRUE
	var/burn_cost = 36000
	var/generated_thrust = 2.5

/obj/structure/machinery/ion_engine/Initialize()
	. = ..()
	controller = new(src)
	sync_ship_registration()

/// Finds this engine's own ship (if any) and registers its controller into
/// S.engines -- mirrors gas_thruster.dm's own proc of the same name exactly.
/// Without this, the controller created above is never actually reachable
/// from ship.engines/the engine control terminal at all, mapped-in or
/// captured alike -- this type never had it, so it never actually worked
/// even where mapped.
/obj/structure/machinery/ion_engine/proc/sync_ship_registration()
	if(!(length(SSshuttle.shuttle_areas) && !length(SSshuttle.shuttles_to_initialize) && SSshuttle.initialized))
		return
	for(var/obj/effect/overmap/visitable/ship/S as anything in SSshuttle.ships)
		if(S.check_ownership(src))
			S.engines |= controller
			return

/obj/structure/machinery/ion_engine/Destroy()
	QDEL_NULL(controller)
	. = ..()

/// Cargo-orderable variant a player can build into their own commissioned
/// hull (ship_commissioning_console.dm) -- starts loose like every other kit
/// part this session added, needing only a wrench. Entirely self-contained:
/// no piped fuel gas or fuel_port needed, only electrical power -- an
/// alternate way to satisfy the same commission engine requirement the real
/// nozzle engine (gas_thruster.dm) satisfies.
/obj/structure/machinery/ion_engine/buildable
	anchored = FALSE

/obj/structure/machinery/ion_engine/buildable/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Ion engine secured in place.") : SPAN_NOTICE("Ion engine unsecured."))
		return TRUE
	return ..(attacking_item, user)

/obj/structure/machinery/ion_engine/proc/get_status()
	. = list()

	. += list(list(
		"text" = "Location: [get_area(src)].",
		"severity" = "info"
	))

	if(!powered())
		. += list(list("text" = "Insufficient power to operate.", "severity" = "bad"))

/obj/structure/machinery/ion_engine/proc/burn(var/power_modifier = 1)
	if(!on && !powered())
		return 0
	use_power_oneoff(thrust_limit * burn_cost * power_modifier)
	playsound(loc, 'sound/machines/thruster.ogg', (50 * thrust_limit * power_modifier), FALSE, world.view * 4, 0.1)
	. = thrust_limit * generated_thrust * power_modifier

/obj/structure/machinery/ion_engine/proc/get_thrust()
	return thrust_limit * generated_thrust * on

/obj/structure/machinery/ion_engine/attackby(obj/item/attacking_item, mob/user)
	. = ..()
	if(default_deconstruction_screwdriver(user, attacking_item))
		return TRUE
	if(default_deconstruction_crowbar(user, attacking_item))
		return TRUE
	if(default_part_replacement(user, attacking_item))
		return TRUE
