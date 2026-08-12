/*
 * Vision Cone System
 * Ported from OpenSourceWeb (Farweb) by Matt and Honkertron.
 * Players have directional FOV — mobs behind them are hidden using client image overrides.
 * The cone overlay (hide.dmi) shows the limited-view graphic.
 * A "peripheral" ghost hint is shown via the fov_mask_two/behind3 state.
 */

#define OPPOSITE_DIR(D) turn(D, 180)

// ── Mob vars ───────────────────────────────────────────────────────────────

/mob
	var/list/hidden_mobs = list()

/client
	var/list/hidden_atoms = list()

/mob/living
	var/list/in_vision_cones = list()

// ── Screen object types ────────────────────────────────────────────────────

// Main cone overlay — covers the area outside the player's FOV
// hide_fov_darker.dmi is hide.dmi's own "combat" state (all 4 facings) with
// its alpha channel scaled up -- measured at avg 22/255, max 89/255 in the
// source, so even at fov.alpha = 255 (show_cone(), below) the rear arc never
// got darker than ~35% opacity; that ceiling was baked into the art, not
// anything tunable from code. Same silhouette, same RGB (already pure black,
// tinted again below regardless) -- only the opacity changed. Point back at
// hide.dmi to revert.
/atom/movable/screen/fov
	icon          = 'icons/mob/hide_fov_darker.dmi'
	icon_state    = "combat"
	name          = " "
	screen_loc    = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	layer         = FULLSCREEN_LAYER
	plane         = FULLSCREEN_PLANE
	color         = "#000000"

// Behind-mask — renders on the hidden plane
/atom/movable/screen/fov_mask
	icon          = 'icons/mob/hide.dmi'
	icon_state    = "behind3"
	name          = " "
	screen_loc    = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	layer         = FULLSCREEN_LAYER
	plane         = HIDDEN_SHIT_PLANE

// Secondary mask — changes shape based on eye/helmet state
/atom/movable/screen/fov_mask_two
	icon          = 'icons/mob/hide.dmi'
	icon_state    = "combat_mask"
	name          = " "
	screen_loc    = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	layer         = FULLSCREEN_LAYER
	plane         = HIDDEN_SHIT_PLANE

// Rear-observer "something moved behind you" flash -- see _ping_rear_observers().
/atom/movable/screen/behind_ping
	icon          = 'icons/mob/hide.dmi'
	icon_state    = "behind"
	name          = " "
	screen_loc    = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	layer         = GAMEUI_BORDER_LAYER
	plane         = FULLSCREEN_PLANE
	alpha         = 160

// ── Film grain screen object ───────────────────────────────────────────────

/atom/movable/screen/film_grain
	icon          = 'icons/effects/film_grain.dmi'
	icon_state    = "1"
	screen_loc    = "WEST,SOUTH to EAST,NORTH"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	plane         = FULLSCREEN_PLANE
	layer         = FULLSCREEN_LAYER
	alpha         = 140

// ── Cone geometry ──────────────────────────────────────────────────────────

/atom/proc/InCone(atom/center = usr, dir = NORTH)
	if(get_dist(center, src) == 0 || src == center) return FALSE
	var/d = get_dir(center, src)
	if(!d || d == dir) return TRUE
	if(dir & (dir-1))
		// Diagonal facing: only the single octant directly opposite counts as
		// "in cone" (i.e. hidden when this is called with the opposite-facing
		// dir) -- a subset test here would also match either lone cardinal
		// component of the diagonal, hiding people standing beside you, not
		// just behind you.
		return (d == dir) ? TRUE : FALSE
	if(!(d & dir)) return FALSE
	var/dx = abs(x - center.x)
	var/dy = abs(y - center.y)
	if(dx == dy) return TRUE
	if(dy > dx)
		return (dir & (NORTH|SOUTH)) ? TRUE : FALSE
	return (dir & (EAST|WEST)) ? TRUE : FALSE

/mob/dead/InCone(mob/center = usr, dir = NORTH)
	return FALSE

/// TRUE when `viewer`'s active vision cone should be hiding `target`, tested
/// LIVE against the same rear-arc rule update_vision_cone() uses, rather than
/// reading its cached hidden_mobs list.
///
/// The cache is only rebuilt when the VIEWER turns or moves (set_dir()/Moved()
/// hooks below), so anyone who walked into a stationary viewer's rear arc was
/// never added to it. Sec/med HUD icons are /image/hud_overlay pushed into
/// client.images with APPEARANCE_UI (hud.dm), which no screen-plane mask can
/// occlude -- so not assigning them in the first place is the only lever, and
/// that decision has to be made against live positions.
/proc/fov_hides_target(mob/viewer, atom/target)
	if(!ishuman(viewer) || !target)
		return FALSE
	var/mob/living/carbon/human/H = viewer
	if(!H.fov || !H.fov.alpha)
		return FALSE // no cone active (ghosts, computer view, cone disabled)
	if(H.pulling == target)
		return FALSE // matches update_vision_cone()'s own pulled-mob exemption
	return target.InCone(H, OPPOSITE_DIR(H.dir))

/proc/cone(atom/center = usr, dir = NORTH, list/atoms = oview(center))
	for(var/turf/T in atoms)
		for(var/mob/M in T.contents)
			if(!M.InCone(center, dir)) atoms -= M
		for(var/obj/item/It in T.contents)
			if(!It.InCone(center, dir)) atoms -= It
	return atoms

// ── Vision cone update ────────────────────────────────────────────────────

/mob/proc/update_vision_cone()
	return

/mob/living/carbon/human/update_vision_cone()
	// Clear previous hidden mobs
	var/image/I = null
	var/delay = 0
	for(I in src.client?.hidden_atoms)
		I.override = FALSE
		spawn(delay)
			qdel(I)
		delay += 5
	src.check_fov()
	src.hidden_mobs = list()
	if(client)
		src.client.hidden_atoms = list()

	if(!fov) return

	// Update cone direction
	if(client)
		src.fov.dir         = src.dir
		src.fov_mask.dir    = src.dir
		src.fov_mask_two.dir = src.dir

		// Shape varies by eye/helmet state
		if(right_eye_fucked && !left_eye_fucked)
			src.fov.icon_state         = "right_eye"
			src.fov_mask_two.icon_state = "right_eye_mask"
		else if(!right_eye_fucked && left_eye_fucked)
			src.fov.icon_state         = "left_eye"
			src.fov_mask_two.icon_state = "left_eye_mask"
		else if(right_eye_fucked && left_eye_fucked)
			src.fov.icon_state         = "helmet"
			src.fov_mask_two.icon_state = "helmet_mask"
		else
			src.fov.icon_state         = initial(src.fov.icon_state)
			src.fov_mask_two.icon_state = initial(src.fov_mask_two.icon_state)

	// Hide mobs and loose floor items behind the player using override images
	if(client && fov.alpha)
		var/list/hidden_candidates = cone(src, OPPOSITE_DIR(src.dir), view(src))
		for(var/mob/living/M in hidden_candidates)
			I = image(null, M)
			I.override = TRUE
			src.client.images    += I
			src.client.hidden_atoms += I
			src.hidden_mobs      += M
			M.in_vision_cones[src.client] = TRUE
			if(src.pulling == M)
				I.override = FALSE
		for(var/obj/item/It in hidden_candidates)
			if(!isturf(It.loc))
				continue
			if(istype(It, /obj/item/modular_computer/console) || istype(It, /obj/item/radio/intercom/ship))
				continue // anchored fixtures -- not loose floor items, always visible
			I = image(null, It)
			I.override = TRUE
			src.client.images    += I
			src.client.hidden_atoms += I

// ── Show/hide helpers ─────────────────────────────────────────────────────

/mob/living/carbon/human/proc/show_cone()
	if(fov)
		fov.alpha          = 255
		fov_mask.alpha     = 255
		fov_mask_two.alpha = 255

/mob/living/carbon/human/proc/hide_cone()
	if(fov)
		fov.alpha          = 0
		fov_mask.alpha     = 0
		fov_mask_two.alpha = 0

/mob/living/carbon/human/proc/check_fov()
	if(resting || lying || istype(buckled_to, /obj/vehicle) || istype(loc, /mob/living/heavy_vehicle) || HAS_TRAIT(src, TRAIT_COMPUTER_VIEW))
		hide_cone()
	else
		show_cone()

// ── Direction change hook ─────────────────────────────────────────────────

/mob/living/carbon/human/set_dir(new_dir)
	. = ..()
	if(fov) update_vision_cone()

// ── Movement hook ──────────────────────────────────────────────────────────
// The cone test depends on relative position, not just facing -- walking
// past someone changes whether they're in-cone even with dir unchanged, so
// this needs the same recompute set_dir() already triggers. Generalized to
// every living mob (not just humans) so the rear-observer ping below fires
// for ANY mover stepping behind a human's cone -- the cone itself stays
// human-only, gated by the ishuman() check.

/mob/living/Moved(atom/old_loc, movement_dir, forced, list/old_locs)
	. = ..()
	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		if(H.fov) H.update_vision_cone()
	_ping_rear_observers()

// ── Behind-you awareness ping ──────────────────────────────────────────────
// A personal-only pulse shown to a player when another human moves inside
// their blind rear arc, up to BEHIND_PING_RANGE tiles away -- they can't
// see the mover (FOV cone hides them), but they can tell something is
// moving back there. Art is the hide.dmi "behind" state (Serenity family).

#define BEHIND_PING_RANGE 3

/mob/living/carbon/human
	var/next_behind_ping = 0

/// Called from Moved() above: pulse every nearby player whose ACTIVE cone
/// hides this mover (same InCone rear-arc test update_vision_cone() uses).
/// Defined on /mob/living (not human-only) so any mob type moving behind a
/// human's cone triggers the pulse -- the observers checked below are still
/// always human, since only humans have a real cone to hide behind.
/mob/living/proc/_ping_rear_observers()
	var/turf/T = get_turf(src)
	if(!T)
		return
	for(var/mob/living/carbon/human/H in range(BEHIND_PING_RANGE, T))
		if(H == src || !H.client || !H.fov || !H.fov.alpha)
			continue
		if(world.time < H.next_behind_ping)
			continue
		if(!InCone(H, OPPOSITE_DIR(H.dir)))
			continue
		H.next_behind_ping = world.time + 1 SECOND
		// Screen overlay (not a world-turf image) -- GAMEUI_BORDER_LAYER on
		// FULLSCREEN_PLANE so the pulse shows THROUGH the black rear-arc cone
		// instead of under it, same rendering convention as fov/fov_mask_two.
		var/atom/movable/screen/behind_ping/ping = new()
		H.client.screen += ping
		addtimer(CALLBACK(GLOBAL_PROC, /proc/_behind_ping_cleanup, H.client, ping), 1 SECOND)

/proc/_behind_ping_cleanup(client/C, atom/movable/screen/behind_ping/I)
	if(C)
		C.screen -= I
	qdel(I)

#undef BEHIND_PING_RANGE

// ── Living mob cleanup when dying/disconnecting ───────────────────────────

/mob/living/proc/leave_vision_cones()
	for(var/client/C in in_vision_cones)
		for(var/image/I in C.hidden_atoms)
			if(I.loc == src)
				I.override = FALSE
				qdel(I)
				C.hidden_atoms -= I
		C.mob?.hidden_mobs -= src
	in_vision_cones = list()
