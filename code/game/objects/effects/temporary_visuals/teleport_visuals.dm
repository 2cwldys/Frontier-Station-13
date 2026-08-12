/obj/effect/temp_visual/phase
	icon = 'icons/mob/mob.dmi'
	icon_state = "phasein"
	layer = ABOVE_HUMAN_LAYER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	duration = 15

/obj/effect/temp_visual/phase/out
	icon_state = "phaseout"

/// Continuous variant used for the "someone is about to teleport here" cue
/// during a channeled travel spool-up (drydock board/disembark, Personal
/// Travel -- see _start_travel_spool_pulses(), telepad_travel.dm). A
/// cyan-leaning light blue instead of green so it stays visually distinct
/// from the rig teleporter's own instant phase flash. `duration` is just a
/// dead-man's-switch backstop -- actual removal is driven by
/// _travel_spool_visual_tick(), which always finishes first for every
/// current caller's 15-second channel.
/obj/effect/temp_visual/phase/spool
	color = "#4de8ff"
	duration = 20 SECONDS

/obj/effect/temp_visual/phase/rift
	icon = 'icons/obj/rig_modules.dmi'
	icon_state = "rift"
	layer = LYING_HUMAN_LAYER
	alpha = 125

/obj/effect/temp_visual/phase/rift/Initialize(mapload, dir)
	. = ..()
	SpinAnimation()
