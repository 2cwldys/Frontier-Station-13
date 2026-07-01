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
/atom/movable/screen/fov
	icon          = 'icons/mob/hide.dmi'
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

// ── Film grain screen object ───────────────────────────────────────────────

/atom/movable/screen/film_grain
	icon          = 'icons/effects/film_grain.dmi'
	icon_state    = "1"
	screen_loc    = "WEST,SOUTH to EAST,NORTH"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	plane         = FULLSCREEN_PLANE
	layer         = FULLSCREEN_LAYER
	alpha         = 255

// ── Cone geometry ──────────────────────────────────────────────────────────

/atom/proc/InCone(atom/center = usr, dir = NORTH)
	if(get_dist(center, src) == 0 || src == center) return FALSE
	var/d = get_dir(center, src)
	if(!d || d == dir) return TRUE
	if(dir & (dir-1))
		return (d & ~dir) ? FALSE : TRUE
	if(!(d & dir)) return FALSE
	var/dx = abs(x - center.x)
	var/dy = abs(y - center.y)
	if(dx == dy) return TRUE
	if(dy > dx)
		return (dir & (NORTH|SOUTH)) ? TRUE : FALSE
	return (dir & (EAST|WEST)) ? TRUE : FALSE

/mob/dead/InCone(mob/center = usr, dir = NORTH)
	return FALSE

/proc/cone(atom/center = usr, dir = NORTH, list/atoms = oview(center))
	for(var/turf/T in atoms)
		for(var/mob/M in T.contents)
			if(!M.InCone(center, dir)) atoms -= M
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

	// Hide mobs behind the player using override images
	if(client && fov.alpha)
		for(var/mob/living/M in cone(src, OPPOSITE_DIR(src.dir), view(src)))
			I = image(null, M)
			I.override = TRUE
			src.client.images    += I
			src.client.hidden_atoms += I
			src.hidden_mobs      += M
			M.in_vision_cones[src.client] = TRUE
			if(src.pulling == M)
				I.override = FALSE

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
	if(resting || lying)
		hide_cone()
	else
		show_cone()

// ── Direction change hook ─────────────────────────────────────────────────

/mob/living/carbon/human/set_dir(new_dir)
	. = ..()
	if(fov) update_vision_cone()

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
