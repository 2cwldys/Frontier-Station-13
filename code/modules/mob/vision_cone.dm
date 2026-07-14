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
	if(resting || lying)
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
// this needs the same recompute set_dir() already triggers.

/mob/living/carbon/human/Moved(atom/old_loc, movement_dir, forced, list/old_locs)
	. = ..()
	if(fov) update_vision_cone()
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
/mob/living/carbon/human/proc/_ping_rear_observers()
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
		var/image/ping = image('icons/mob/hide.dmi', T, "behind")
		// FULLSCREEN_PLANE + a layer above the cone overlay so the pulse
		// shows THROUGH the black rear-arc cone instead of under it.
		ping.plane = FULLSCREEN_PLANE
		ping.layer = GAMEUI_BORDER_LAYER
		ping.alpha = 160
		H.client.images += ping
		addtimer(CALLBACK(GLOBAL_PROC, /proc/_behind_ping_cleanup, H.client, ping), 1 SECOND)

/proc/_behind_ping_cleanup(client/C, image/I)
	if(C)
		C.images -= I
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
