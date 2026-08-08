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

	/// Stable identity tag, lazily minted once (never position-derived --
	/// this device can be moved before it's finally wrenched in place, unlike
	/// docking_beacon's own position-derived landmark_tag). Lets a
	/// ship_commissioning console's saved link survive a restart -- see
	/// GLOB.drydock_linkable_devices_by_tag's own doc comment
	/// (ship_commissioning_console.dm).
	var/id_tag

/obj/structure/machinery/docking_transponder/Initialize()
	. = ..()
	if(!id_tag)
		id_tag = "transponder_[REF(src)]"
	GLOB.drydock_linkable_devices_by_tag[id_tag] = src
	if(GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/obj/structure/machinery/docking_transponder/Destroy()
	GLOB.drydock_linkable_devices_by_tag -= id_tag
	return ..()

/// Only id_tag needs saving -- everything else (position/dir/anchored) is
/// already covered separately by the generic tracked-object save path.
/obj/structure/machinery/docking_transponder/persistent_objects_get_content()
	var/list/content = list()
	content["id_tag"] = id_tag
	return content

/obj/structure/machinery/docking_transponder/persistent_objects_apply_content(content, x, y, z)
	..()
	if(content["id_tag"])
		GLOB.drydock_linkable_devices_by_tag -= id_tag
		id_tag = content["id_tag"]
		GLOB.drydock_linkable_devices_by_tag[id_tag] = src

/obj/structure/machinery/docking_transponder/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/choice = tgui_alert(user, "Buffer this transponder into the multitool, or rotate its facing?", "Docking Transponder", list("Buffer", "Rotate"))
		if(QDELETED(src) || QDELETED(user) || !user.Adjacent(src))
			return TRUE
		if(choice == "Buffer")
			if(!istype(attacking_item, /obj/item/multitool))
				to_chat(user, SPAN_WARNING("\The [attacking_item] can't hold a buffer."))
				return TRUE
			var/obj/item/multitool/tool = attacking_item
			tool.set_buffer(src)
			to_chat(user, SPAN_NOTICE("You buffer \the [src] into \the [tool]."))
			return TRUE
		if(choice == "Rotate")
			if(anchored)
				to_chat(user, SPAN_WARNING("\The [src] is secured in place -- unwrench it before changing its facing."))
				return TRUE
			dir = turn(dir, -90)
			to_chat(user, SPAN_NOTICE("You rotate \the [src] -- it now faces [dir2text(dir)]."))
			return TRUE
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Docking transponder secured in place.") : SPAN_NOTICE("Docking transponder unsecured."))
		return TRUE
	return ..(attacking_item, user, params)
