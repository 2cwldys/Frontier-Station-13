/obj/effect/temp_visual/phase
	icon = 'icons/mob/mob.dmi'
	icon_state = "phasein"
	layer = ABOVE_HUMAN_LAYER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	duration = 15

/obj/effect/temp_visual/phase/out
	icon_state = "phaseout"

/// How long the phasein-blue animation itself runs, in deciseconds (7
/// frames @ 1 decisecond each, per icons/mob/mob.dmi's own metadata) --
/// _loop_animation() below re-flicks it on exactly this cadence so it reads
/// as one continuous loop instead of playing once and freezing on its last
/// frame (loop = 1 in the dmi itself).
#define PHASE_SPOOL_ANIM_LENGTH 7

/// Continuous variant used for the "someone is about to teleport here" cue
/// during a channeled travel spool-up (drydock board/disembark, Personal
/// Travel -- see _start_travel_spool_pulses(), telepad_travel.dm).
/// icons/mob/mob.dmi already ships a purpose-made "phasein-blue" state
/// (used nowhere else in the codebase) -- using it directly reads better
/// than a color multiply over the green "phasein" state. `duration` is just
/// a dead-man's-switch backstop -- actual removal is driven by
/// _travel_spool_visual_tick(), which always finishes first for every
/// current caller's 15-second channel.
/obj/effect/temp_visual/phase/spool
	icon_state = "phasein-blue"
	duration = 20 SECONDS

/obj/effect/temp_visual/phase/spool/Initialize(mapload, new_dir)
	. = ..()
	_loop_animation()

/// Self-rescheduling re-flick loop, ending on its own the moment src is
/// deleted (by _travel_spool_visual_tick() or the duration backstop above)
/// -- no separate still_valid plumbing needed here, unlike the pulses.
/obj/effect/temp_visual/phase/spool/proc/_loop_animation()
	if(QDELETED(src))
		return
	flick(icon_state, src)
	addtimer(CALLBACK(src, PROC_REF(_loop_animation)), PHASE_SPOOL_ANIM_LENGTH)

/obj/effect/temp_visual/phase/rift
	icon = 'icons/obj/rig_modules.dmi'
	icon_state = "rift"
	layer = LYING_HUMAN_LAYER
	alpha = 125

/obj/effect/temp_visual/phase/rift/Initialize(mapload, dir)
	. = ..()
	SpinAnimation()
