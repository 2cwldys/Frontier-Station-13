/*
 * Docking Transponder
 *
 * A player-buildable, cargo-orderable floor fixture -- placed at a
 * commissioned shuttle's own airlock/exit tile, it declares which way that
 * airlock faces. A docking_beacon (docking_beacon.dm) only accepts a ship
 * carrying one of these if the transponder's facing is the exact OPPOSITE
 * of the beacon's own -- the same way two real airlocks would face each
 * other when docked. See player_dock/is_valid()'s footprint check
 * (docking_beacon.dm) for the size-gating this mirrors the shape of.
 *
 * Entirely opt-in: a ship with no transponder is never checked at all and
 * docks anywhere it always could. This does NOT rotate a ship's hull on
 * landing -- the underlying landing math (get_turf_translation(),
 * __HELPERS/turfs.dm) has no rotation concept for any ship in the game,
 * template or player-built, and this device doesn't change that. It's a
 * compatibility gate on top of the existing size/turf-safety checks, not a
 * physical rotation system.
 */
/obj/structure/machinery/docking_transponder
	name = "docking transponder"
	desc = "A floor-mounted transponder that broadcasts which way this airlock faces, so a compatible docking beacon can recognize it. Doesn't obstruct doors -- safe to mount directly under an airlock."
	icon = 'icons/obj/holopad.dmi'
	icon_state = "holopad0"
	color = "#3a2210"
	// Flush with the floor and never dense -- must sit under an airlock and
	// let it open/close normally, unlike a typical machine.
	density = FALSE
	layer = ABOVE_TILE_LAYER
	anchored = FALSE // starts unanchored -- won't register while in a crate or being carried
	use_power = POWER_USE_IDLE
	idle_power_usage = 5
	component_types = list(
		/obj/item/circuitboard/docking_transponder,
		/obj/item/stock_parts/console_screen,
		/obj/item/stack/cable_coil
	)

/obj/structure/machinery/docking_transponder/Initialize()
	. = ..()
	if(GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/obj/structure/machinery/docking_transponder/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		if(anchored)
			to_chat(user, SPAN_WARNING("\The [src] is secured in place -- unwrench it before changing its facing."))
			return TRUE
		dir = turn(dir, -90)
		to_chat(user, SPAN_NOTICE("You rotate \the [src] -- it now faces [dir2text(dir)]."))
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Docking transponder secured in place.") : SPAN_NOTICE("Docking transponder unsecured."))
		return TRUE
	return ..(attacking_item, user, params)
