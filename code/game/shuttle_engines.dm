/obj/structure/shuttle
	name = "shuttle"
	icon = 'icons/turf/shuttle.dmi'
	opacity = 1

/obj/structure/shuttle/window
	name = "shuttle window"
	icon = 'icons/obj/podwindows.dmi'
	icon_state = "1"
	density = 1
	opacity = 0
	anchored = 1
	atmos_canpass = CANPASS_NEVER

/obj/structure/shuttle/window/CanPass(atom/movable/mover, turf/target, height, air_group)
	if(!height || air_group) return 0
	else return ..()

/obj/structure/shuttle/engine
	name = "engine"
	density = 1
	anchored = 1
	atmos_canpass = CANPASS_NEVER

/obj/structure/shuttle/engine/heater
	name = "heater"
	icon_state = "heater"

/obj/structure/shuttle/engine/platform
	name = "platform"
	icon_state = "platform"

/obj/structure/shuttle/engine/propulsion
	name = "propulsion"
	icon_state = "propulsion"

/// Cargo-orderable variant a player can build into their own commissioned
/// hull (ship_commissioning_console.dm) -- unlike the base type above
/// (always pre-anchored, used only as mapped-in decoration on template
/// hulls), this one starts loose like every other kit part and needs a
/// wrench first. Purely structural -- no functional vars/behavior beyond
/// that, same as its parent.
/obj/structure/shuttle/engine/propulsion/buildable
	anchored = FALSE

/obj/structure/shuttle/engine/propulsion/buildable/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Propulsion unit secured in place.") : SPAN_NOTICE("Propulsion unit unsecured."))
		return TRUE
	// Purely cosmetic (this whole type has no functional vars, see the doc
	// comment above) -- lets a player orient the exhaust to match their
	// hull layout. Only while unsecured, same gate docking_transponder's
	// own multitool-rotate uses.
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		if(anchored)
			to_chat(user, SPAN_WARNING("\The [src] is secured in place -- unwrench it before changing its facing."))
			return TRUE
		dir = turn(dir, -90)
		to_chat(user, SPAN_NOTICE("You rotate \the [src] -- it now faces [dir2text(dir)]."))
		return TRUE
	return ..(attacking_item, user, params)

/obj/structure/shuttle/engine/propulsion/burst
	name = "burst"

/obj/structure/shuttle/engine/propulsion/burst/left
	name = "left"
	icon_state = "burst_l"

/obj/structure/shuttle/engine/propulsion/burst/right
	name = "right"
	icon_state = "burst_r"

/obj/structure/shuttle/engine/router
	name = "router"
	icon_state = "router"
