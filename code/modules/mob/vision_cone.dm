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
	// No pulled-mob exemption: dragging someone behind you does not let you see
	// them, it just means the thing you can't see is attached to you. They hide
	// like anything else and get the same movement ping, which -- since a
	// dragged body moves whenever you do, and is always adjacent -- means a
	// steady marker trailing you rather than nothing at all.
	return target.InCone(H, OPPOSITE_DIR(H.dir))

/proc/cone(atom/center = usr, dir = NORTH, list/atoms = oview(center))
	for(var/turf/T in atoms)
		for(var/mob/M in T.contents)
			if(!M.InCone(center, dir)) atoms -= M
		for(var/obj/item/It in T.contents)
			if(!It.InCone(center, dir)) atoms -= It
		// Vehicles/pods are neither /mob nor /obj/item, so without their own
		// pass here they'd stay in the returned list unfiltered -- and the
		// caller would hide every vehicle in view rather than only the ones
		// actually behind the viewer.
		for(var/obj/vehicle/V in T.contents)
			if(!V.InCone(center, dir)) atoms -= V
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

	// A ping marks movement you cannot see, so it must never outlive the
	// override image that was hiding its mover. _refresh_rear_observers()'s own
	// clear only fires when the MOVER moves, which leaves every observer-side
	// route uncovered -- turning, stepping, entering or leaving a mech or pod,
	// switching to computer view, or simply lying down. All of them land here:
	// check_fov() above is hide_cone()/show_cone()'s only caller, and this proc
	// is check_fov()'s only caller, so fov.alpha cannot change anywhere else.
	//
	// Runs after check_fov() so fov.alpha is current -- fov_hides_target()
	// returns FALSE at !alpha, which is what makes the cone-off cases clear
	// through the same single test -- and before the !fov return below, since a
	// null fov reads the same way and still needs clearing.
	//
	// The test is bare fov_hides_target() rather than the full ping condition
	// on purpose: a clear predicate stricter than the create predicate would
	// destroy a ping the instant after it was made. Range and line of sight
	// stay creation-side gates with the timer handling decay, so a mover who
	// walks out of range or slips behind cover fades out over the linger, while
	// one who becomes VISIBLE is cancelled immediately.
	//
	// Copy(): _clear_behind_silhouette() mutates the list being walked, and DM
	// list iteration is index-based, so removing during the walk skips entries.
	if(client && LAZYLEN(client.behind_silhouettes))
		for(var/atom/movable/marked in client.behind_silhouettes.Copy())
			if(!QDELETED(marked) && fov_hides_target(src, marked))
				continue
			_clear_behind_silhouette(client, marked)

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
		for(var/obj/item/It in hidden_candidates)
			if(!isturf(It.loc))
				continue
			if(istype(It, /obj/item/modular_computer/console) || istype(It, /obj/item/radio/intercom/ship))
				continue // anchored fixtures -- not loose floor items, always visible
			I = image(null, It)
			I.override = TRUE
			src.client.images    += I
			src.client.hidden_atoms += I
		// Vehicles/pods hide on the same terms. Mechs need no case here --
		// /mob/living/heavy_vehicle is a /mob/living, so the mob loop above
		// already covers them.
		for(var/obj/vehicle/V in hidden_candidates)
			if(!isturf(V.loc))
				continue
			I = image(null, V)
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
// every living mob (not just humans) so the rear-observer cue below fires
// for ANY mover stepping behind a human's cone -- the cone itself stays
// human-only, gated by the ishuman() check.

/// How close a mover has to be for its ping to show. Deliberately much tighter
/// than the cone's own hiding range: being hidden is the default, the cue is
/// only for something practically on top of you.
#define BEHIND_PING_RANGE 3
/// How long a ping lingers after the mover's LAST step. Has to stay longer than
/// one step or a continuously-walking mover strobes once per tile instead of
/// showing a steady marker, and an unhurried walk is ~4 deciseconds per step
/// (GLOB.config.walk_speed, configuration.dm) -- so this is deliberately close
/// to that floor and should not go lower. A mover slowed well past a normal
/// walk (dragging a body, hurt legs, heavily loaded) can still outrun it and
/// blink; raise this if that reads badly in play.
#define BEHIND_SILHOUETTE_LINGER (0.5 SECONDS)

/mob/living/Moved(atom/old_loc, movement_dir, forced, list/old_locs)
	. = ..()
	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		if(H.fov) H.update_vision_cone()
	_refresh_rear_observers()

// Vehicles/pods are hidden by the cone like anything else (update_vision_cone()
// above), so they need the same hook -- otherwise a pod that drove out from
// behind a standing player would stay invisible to them, and one driving past
// behind them would give no ping at all. Deliberately hooked here on
// /obj/vehicle specifically rather than on /atom/movable: every bullet, thrown
// item and piece of debris in the game goes through Moved(), and none of them
// should be paying for an observer scan.
//
// Mechs need no hook of their own -- /mob/living/heavy_vehicle is a /mob/living
// and its Move() calls ..(), so the /mob/living hook above already covers them.
/obj/vehicle/Moved(atom/old_loc, movement_dir, forced, list/old_locs)
	. = ..()
	_refresh_rear_observers()

/// Reconciles every nearby observer's cached hide-state for THIS mover against
/// the live cone test, correcting only the entries that actually changed.
///
/// update_vision_cone() only ever runs for the mob whose own cone it is -- from
/// its own set_dir() and Moved() hooks above -- so nothing else would ever
/// touch a STATIONARY viewer's cache when somebody walks across their rear arc.
/// Without this pass, walking out from behind a standing player leaves that
/// player's override image in place and the mover stays invisible to them until
/// they happen to turn or move, and walking in has the mirror problem. This is
/// a straight cache-vs-truth reconciliation, so it covers both directions.
///
/// The sec/med HUD copes with the same staleness by ORing the cache with a live
/// test (hud.dm); the override images that actually hide people need the cache
/// itself to be correct, which is what this keeps true.
///
/// Single-mob add/remove rather than a full H.update_vision_cone() per
/// observer: a rebuild walks every turf in view() and re-creates every override
/// image, and would run whenever anyone crossed any nearby observer's cone
/// boundary. This does exactly the work that rebuild would have done for this
/// one mob, and nothing at all when the cache already agrees -- the common case.
/// Defined on /atom/movable rather than /mob/living so vehicles can reuse it
/// verbatim -- /obj/vehicle is neither a mob nor an item, and gets its own
/// Moved() hook below. Nothing else calls it, so this stays limited to the two
/// hooks rather than firing for every movable in the game.
///
/// Also does the movement ping in the same pass (see show_behind_silhouette()),
/// because both jobs need the identical walk and the identical rear-arc answer.
///
/// Deliberately NOT viewers(): this fires on every step of every living mob and
/// every vehicle, ambient wildlife included, and viewers() is a 15x15 scan with
/// line-of-sight each time. Only a human holding an active cone can ever matter
/// here, so walking the human list with a z + distance check scales with how
/// many people are online rather than with how much is moving on the map.
/// Ignoring walls in that check is deliberate and harmless for the HIDE state --
/// reconciling it for someone who cannot currently see this atom costs nothing
/// and leaves their cache correct for the moment the wall stops being in the
/// way. The ping is the one exception and does test line of sight; see there.
/atom/movable/proc/_refresh_rear_observers()
	var/turf/my_turf = get_turf(src)
	if(!my_turf)
		return
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(H == src || !H.client || !H.fov || !H.fov.alpha)
			continue
		var/turf/their_turf = get_turf(H)
		if(!their_turf || their_turf.z != my_turf.z)
			continue
		var/distance = get_dist(my_turf, their_turf)
		if(distance > world.view)
			continue
		// No pulled-atom special case here either -- see fov_hides_target().
		// Something you are dragging behind you is exactly as out of sight as
		// anything else back there.
		var/should_hide = !!fov_hides_target(H, src)
		// Movement ping, same pass and same answer. Deliberately BEFORE the
		// cache-agrees early-out below: someone already hidden and still walking
		// is exactly the case this cue exists for, so it must not be skipped just
		// because their hide state didn't change this step.
		//
		// can_see() is the one place this loop does care about walls, unlike the
		// hide reconciliation below it (see the note there). A contact marker is
		// information the observer is being given, so it must not carry through
		// solid cover -- otherwise the rear arc leaks "someone is back there"
		// straight through a wall you are standing against. Cheap here: a
		// step-towards opacity walk bounded at BEHIND_PING_RANGE, reached only
		// once something is already both hidden and within 3 tiles.
		if(should_hide && distance <= BEHIND_PING_RANGE && can_see(H, src, BEHIND_PING_RANGE))
			H.client.show_behind_silhouette(src)
		// Ground truth is the override image itself, not hidden_mobs: that list
		// only ever tracks mobs (update_vision_cone()), so items and vehicles
		// would always read as "not hidden" and get re-added on every step.
		var/is_hidden = FALSE
		for(var/image/existing in H.client.hidden_atoms)
			if(existing.loc != src)
				continue
			is_hidden = TRUE
			break
		if(should_hide == is_hidden)
			continue
		// hidden_mobs / in_vision_cones are mob-only bookkeeping (hud.dm reads the
		// former for sec/med icons), so they're only touched for mobs -- exactly
		// how update_vision_cone() treats its own item pass.
		var/mob/living/living_src = isliving(src) ? src : null
		if(should_hide)
			// Mirrors update_vision_cone()'s own hide block.
			var/image/hide_image = image(null, src)
			hide_image.override = TRUE
			H.client.images += hide_image
			H.client.hidden_atoms += hide_image
			if(living_src)
				H.hidden_mobs += living_src
				living_src.in_vision_cones[H.client] = TRUE
		else
			// They just became visible to this observer, so any ping still
			// lingering on them has to go NOW rather than waiting out its timer --
			// otherwise the real, now-visible atom keeps a contact marker sitting
			// on it for up to BEHIND_SILHOUETTE_LINGER.
			_clear_behind_silhouette(H.client, src)
			// Mirrors leave_vision_cones()'s own removal, scoped to this observer.
			for(var/image/hide_image in H.client.hidden_atoms)
				if(hide_image.loc != src)
					continue
				hide_image.override = FALSE
				H.client.hidden_atoms -= hide_image
				qdel(hide_image)
			if(living_src)
				H.hidden_mobs -= living_src
				living_src.in_vision_cones -= H.client

// ── Behind-you movement ping ───────────────────────────────────────────────
// A personal-only cue shown to a player when something moves inside their
// blind rear arc, up to BEHIND_PING_RANGE tiles away -- they can't see the
// mover (the FOV cone hides them), but they can make out roughly where it is.
//
// Position is the whole point: an abstract ring marks WHERE something is,
// while deliberately saying nothing about what it is.

/// Per-client map of mover -> its live ping image, so a second step by the same
/// mover refreshes the existing ping instead of stacking another one. Also what
/// makes the throttle per (observer, mover) rather than one blanket cue per
/// observer -- two things moving behind you produce two pings.
/client/var/list/behind_silhouettes

/// Shows (or refreshes) one movement ping marking `mover` for this client.
///
/// Anchored to the mover itself rather than their turf, so it FOLLOWS them for
/// free -- which is why the image is only ever built when one doesn't already
/// exist. A continuous walk therefore costs one image, not one per tile. The
/// consequence worth knowing: the ring animation plays once on creation and
/// then holds its last frame while travelling with them, so a long walk reads
/// as one marker tracking them rather than a pulse per step.
///
/// Deliberately left on the ordinary game plane, UNDER the cone: the cone is
/// black at ~53% opacity (hide_fov_darker.dmi, measured mean alpha 136/255), so
/// a pale ring still reads through it and looks like something picked up in the
/// dark, rather than a HUD sticker pasted over the cone -- and it gets a free
/// falloff with depth into the arc, since the cone's own darkness is uneven.
///
/// The mob is separately blanked for this client by update_vision_cone()'s
/// override image; `override` replaces the ATOM's own appearance, not other
/// images attached to it (hud.dm's sec/med icons already rely on several
/// independent client.images entries per mob), so this renders on top of the
/// blanked mob rather than fighting it.
/client/proc/show_behind_silhouette(atom/movable/mover)
	if(!mover)
		return
	LAZYINITLIST(behind_silhouettes)
	if(!behind_silhouettes[mover])
		// An abstract contact marker, never the mover's own appearance -- the
		// rear arc must only leak THAT something is back there, not what.
		// "sonar_ping" is an expanding ring, 6 frames at 1 decisecond with
		// loop = 1, so it plays out over 0.6s and then holds its last frame.
		var/image/silhouette = image('icons/effects/effects.dmi', mover, "sonar_ping")
		silhouette.override = FALSE
		// Nothing to inherit a layer from, so set one explicitly -- the same
		// layer /obj/effect/temp_visual uses for short-lived world cues.
		silhouette.layer = ABOVE_HUMAN_LAYER
		// Flatten the ring to one tone. 20-value colour matrix, same form as
		// human.dm's own channel swap: each group of four is one input channel's
		// contribution to (R,G,B,A), the fifth group is a constant added on top.
		// Every channel contributes nothing except alpha -> alpha, so only the
		// constant colours it. A plain colour string cannot do this job -- it
		// multiplies, so it could darken the source art's cyan but never
		// neutralise it. Kept a light blue-grey rather than dark: the cone
		// underneath is black, so a dark cue loses all contrast against it.
		silhouette.color = list(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,1, 0.62,0.70,0.76,0)
		// The one knob if this gives away too much (or too little). Note this is
		// NOT what you actually see: the ping sits on the game plane UNDER the
		// cone, so the cone's own black (mean 136/255, up to 178) composites
		// over it. Net visibility is roughly this value x 0.47, so ~20% here --
		// an edge-of-vision hint rather than a marker you read directly. Drop
		// toward 80 to make it fainter still, raise toward 190 for a ping that
		// is unmistakable the moment it appears.
		silhouette.alpha = 110
		images += silhouette
		behind_silhouettes[mover] = silhouette
	// Re-armed on every step, so the ping lasts until they actually stop.
	addtimer(CALLBACK(GLOBAL_PROC, /proc/_clear_behind_silhouette, src, mover), BEHIND_SILHOUETTE_LINGER, TIMER_UNIQUE | TIMER_OVERRIDE)

/// Timer target for show_behind_silhouette(). Self-contained on purpose:
/// leave_vision_cones() (below) looks like the natural death/disconnect
/// teardown hook but is dead code -- defined and called from nowhere -- so this
/// cue cannot depend on it and instead guards its own inputs.
/proc/_clear_behind_silhouette(client/C, atom/movable/mover)
	if(!C)
		return
	var/image/silhouette = LAZYACCESS(C.behind_silhouettes, mover)
	if(!silhouette)
		return
	C.images -= silhouette
	C.behind_silhouettes -= mover
	qdel(silhouette)

#undef BEHIND_PING_RANGE
#undef BEHIND_SILHOUETTE_LINGER

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
