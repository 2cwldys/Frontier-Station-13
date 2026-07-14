/mob/proc/set_fullscreen(condition, screen_name, screen_type, arg)
	condition ? overlay_fullscreen(screen_name, screen_type, arg) : clear_fullscreen(screen_name)

/mob/proc/overlay_fullscreen(category, type, severity, animated = 0)
	var/atom/movable/screen/fullscreen/screen = screens[category]

	if(screen)
		if(screen.type != type)
			clear_fullscreen(category, FALSE)
			screen = null
		else if(!severity || severity == screen.severity)
			return null

	if(!screen)
		screen = new type()
		if(animated)
			screen.alpha = 0

	screen.icon_state = "[initial(screen.icon_state)][severity]"
	screen.severity = severity

	screens[category] = screen
	if(client && (stat != DEAD || screen.allstate))
		client.screen += screen
		if(animated)
			animate(screen, alpha = initial(screen.alpha), time = animated)
	return screen

/mob/proc/clear_fullscreen(category, animated = 10)
	var/atom/movable/screen/fullscreen/screen = screens[category]
	if(!screen)
		return

	screens -= category

	if(!QDELETED(src) && animated)
		animate(screen, alpha = 0, time = animated)
		addtimer(CALLBACK(src, PROC_REF(clear_fullscreen_after_animate), screen), animated, TIMER_CLIENT_TIME)
	else
		if(client)
			client.screen -= screen
		qdel(screen)

/mob/proc/clear_fullscreen_after_animate(atom/movable/screen/fullscreen/screen)
	if(client)
		client.screen -= screen
	qdel(screen)

/mob/proc/clear_fullscreens()
	for(var/category in screens)
		clear_fullscreen(category)

/mob/proc/hide_fullscreens()
	if(client)
		for(var/category in screens)
			client.screen -= screens[category]

/mob/proc/reload_fullscreen()
	if(client)
		for(var/category in screens)
			client.screen |= screens[category]

/atom/movable/screen/fullscreen
	icon = 'icons/hud/mob/full.dmi'
	icon_state = "default"
	screen_loc = "CENTER-7,CENTER-7"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	plane = FULLSCREEN_PLANE
	layer = FULLSCREEN_LAYER
	var/severity = 0
	var/allstate = 0 //shows if it should show up for dead people too

/atom/movable/screen/fullscreen/Destroy()
	severity = 0
	return ..()

/atom/movable/screen/fullscreen/brute
	icon_state = "brutedamageoverlay"
	layer = DAMAGE_LAYER

/atom/movable/screen/fullscreen/oxy
	icon_state = "oxydamageoverlay"
	layer = DAMAGE_LAYER

/atom/movable/screen/fullscreen/crit
	icon_state = "passage"
	layer = CRIT_LAYER

/atom/movable/screen/fullscreen/strong_pain
	icon_state = "strong_pain"
	layer = CRIT_LAYER

/atom/movable/screen/fullscreen/blind
	icon_state = "blackimageoverlay"
	layer = BLIND_LAYER

/atom/movable/screen/fullscreen/blackout
	icon_state = "blackout"
	layer = BLIND_LAYER

/atom/movable/screen/fullscreen/impaired
	icon_state = "impairedoverlay"

/atom/movable/screen/fullscreen/closet_impaired
	icon_state = "impairedoverlay2"

/atom/movable/screen/fullscreen/blurry
	icon = 'icons/hud/mob/effects.dmi'
	screen_loc = "WEST,SOUTH to EAST,NORTH"
	icon_state = "blurry"
	alpha = 100

/atom/movable/screen/fullscreen/pain
	icon_state = "brutedamageoverlay6"
	alpha = 0

/atom/movable/screen/fullscreen/robot_pain
	icon = 'icons/hud/mob/robot_pain.dmi'
	alpha = 255

/atom/movable/screen/fullscreen/flash
	icon = 'icons/hud/mob/effects.dmi'
	screen_loc = "WEST,SOUTH to EAST,NORTH"
	icon_state = "flash"

/atom/movable/screen/fullscreen/flash/noise
	icon_state = "noise"
	alpha = 127

/atom/movable/screen/fullscreen/noise
	icon = 'icons/effects/static.dmi'
	icon_state = "1 light"
	screen_loc = ui_entire_screen
	alpha = 127

/atom/movable/screen/fullscreen/fadeout
	icon = 'icons/hud/mob/effects.dmi'
	icon_state = "black"
	screen_loc = ui_entire_screen
	alpha = 0
	allstate = 1

/atom/movable/screen/fullscreen/fadeout/Initialize()
	. = ..()
	animate(src, alpha = 255, time = 10)

/atom/movable/screen/fullscreen/scanline
	icon = 'icons/effects/static.dmi'
	icon_state = "scanlines"
	screen_loc = ui_entire_screen
	alpha = 50

/atom/movable/screen/fullscreen/frenzy
	icon_state = "frenzyoverlay"
	layer = BLIND_LAYER

/atom/movable/screen/fullscreen/teleport
	icon_state = "teleport"

/atom/movable/screen/fullscreen/blueprints
	icon = 'icons/effects/blueprints.dmi'
	icon_state = "base"
	screen_loc = ui_entire_screen
	alpha = 100

/atom/movable/screen/fullscreen/blueprints/less_alpha
	alpha = 35

/atom/movable/screen/fullscreen/lighting_backdrop
	icon = 'icons/hud/mob/white.dmi'
	icon_state = "flash"
	transform = matrix(200, 0, 0, 0, 200, 0)
	plane = LIGHTING_PLANE
	blend_mode = BLEND_OVERLAY

//Provides darkness to the back of the lighting plane
/atom/movable/screen/fullscreen/lighting_backdrop/lit_secondary
	invisibility = INVISIBILITY_LIGHTING
	layer = BACKGROUND_LAYER + LIGHTING_PRIMARY_DIMMER_LAYER
	color = "#000"
	alpha = 60

/atom/movable/screen/fullscreen/lighting_backdrop/backplane
	invisibility = INVISIBILITY_LIGHTING
	layer = LIGHTING_BACKPLANE_LAYER
	color = "#000"
	blend_mode = BLEND_ADD
	//show_when_dead = TRUE

/atom/movable/screen/fullscreen/see_through_darkness
	icon_state = "nightvision"
	plane = LIGHTING_PLANE
	layer = LIGHTING_PRIMARY_LAYER
	blend_mode = BLEND_ADD

// Post-cryo "chilled" cold border (see apply_cryo_chill). The bare .png is a
// single 480x480 icon state named "", on the standard fullscreen anchor --
// larger icons would force BYOND to expand the client viewport (zoom-out).
// apply_cryo_chill() scales it to the client's dynamic view via transform,
// which does NOT trigger view expansion (same trick as lighting_backdrop).
// CHILLED_LAYER puts it above the decorative gameui_border (see below) so
// the cold effect is always visible even with the border showing.
/atom/movable/screen/fullscreen/chilled
	icon = 'icons/hud/chilled.png'
	icon_state = ""
	layer = CHILLED_LAYER

// Persistent, preference-gated edge-darkening vignette (see toggle_vignette()
// / HUD build in code/_onclick/hud/human.dm). Same "large single-state PNG
// scaled via transform" trick as chilled above -- deliberately the lowest
// layer in FULLSCREEN_PLANE so it never bleeds over any other fullscreen
// effect (chilled, blind, damage overlays, etc.) or the main HUD above it.
/atom/movable/screen/fullscreen/vignette
	icon = 'icons/hud/vignette.png'
	icon_state = ""
	layer = VIGNETTE_LAYER

/// Applies (or re-scales, if already present) the persistent vignette --
/// scaled to the client's dynamic viewport via transform, same technique as
/// apply_cryo_chill_visuals(), not overlay_fullscreen()'s built-in severity
/// scaling. Shared by toggle_vignette() and the HUD-build application so the
/// scaling math only lives in one place.
/mob/living/carbon/human/proc/apply_vignette()
	var/atom/movable/screen/fullscreen/vignette/v = overlay_fullscreen("vignette", /atom/movable/screen/fullscreen/vignette)
	if(v && client)
		var/list/vs = getviewsize(client.view)
		var/scale = max(vs[1], vs[2]) * WORLD_ICON_SIZE / 480
		if(scale > 1)
			v.transform = matrix(scale, 0, 0, 0, scale, 0)

// Preference-gated (CRT_SCANLINES) old-CRT roll band: a faint DARK band
// (the classic CRT "rolling shutter") that periodically sweeps down the
// entire game window with a slight horizontal waver. Sized by
// apply_crt_scanlines() below; the art is the same solid 32x32 white tile
// the lighting backdrop uses, tinted black and stretched via transform.
// Self-driving: timer-armed single-sweep animates (the codebase's reliable
// pattern for screen-object pixel animation -- progressbar/langchat), NOT a
// looping animate() chain, whose delay-step/loop semantics proved flaky.
/atom/movable/screen/fullscreen/crt_scanlines
	icon = 'icons/hud/mob/white.dmi'
	icon_state = "flash"
	screen_loc = "CENTER,CENTER"
	layer = CRT_SCANLINES_LAYER
	color = "#000000"
	alpha = 25
	/// Sweep span in pixels -- the client's view pixel height, kept current
	/// by apply_crt_scanlines(). 480 = the 15x15 default view.
	var/sweep_px_h = 480
	/// Horizontal stretch factor (view px width / 32), kept current by
	/// apply_crt_scanlines().
	var/sweep_scale_x = 15
	/// One-shot latch so re-applies never stack extra roll timer loops.
	var/rolling = FALSE

/// This band's transform at a given sweep position (c = x-translate,
/// f = y-translate, plus the width/thickness scale). ALL movement is done
/// through transform translation: transform rendering on fullscreen screens
/// is proven in-game (vignette/gameui_border/chilled), while pixel_x/pixel_y
/// offsets proved not to render on them at all (two failed rounds).
/atom/movable/screen/fullscreen/crt_scanlines/proc/band_matrix(x_off, y_off)
	return matrix(sweep_scale_x, 0, x_off, 0, 2 / 32, y_off)

/atom/movable/screen/fullscreen/crt_scanlines/proc/start_rolling()
	if(rolling)
		return
	rolling = TRUE
	addtimer(CALLBACK(src, PROC_REF(crt_roll)), rand(2 SECONDS, 6 SECONDS))

/// One top-to-bottom sweep with a gentle side-to-side waver (segmented
/// eased chain), then re-arms itself at a randomized interval -- the
/// randomized hold is the "occasional" pacing (mirrors the fast-roll/
/// long-tail feel of the Serenity character doll's baked animation).
/atom/movable/screen/fullscreen/crt_scanlines/proc/crt_roll()
	if(QDELETED(src))
		return
	// +16px so the band starts/ends fully clipped off the view edges.
	var/top = sweep_px_h / 2 + 16
	var/step_y = (top * 2) / 6
	transform = band_matrix(0, top)
	// 6 x 0.5s steps = a ~3s glide down the screen (1.5s read too fast,
	// 6s too slow -- eyeball-tuned midpoint).
	animate(src, transform = band_matrix(3, top - step_y), time = 0.5 SECONDS, easing = SINE_EASING)
	animate(transform = band_matrix(-3, top - 2 * step_y), time = 0.5 SECONDS, easing = SINE_EASING)
	animate(transform = band_matrix(3, top - 3 * step_y), time = 0.5 SECONDS, easing = SINE_EASING)
	animate(transform = band_matrix(-3, top - 4 * step_y), time = 0.5 SECONDS, easing = SINE_EASING)
	animate(transform = band_matrix(3, top - 5 * step_y), time = 0.5 SECONDS, easing = SINE_EASING)
	animate(transform = band_matrix(0, top - 6 * step_y), time = 0.5 SECONDS, easing = SINE_EASING)
	addtimer(CALLBACK(src, PROC_REF(crt_roll)), rand(8 SECONDS, 16 SECONDS))

/// Applies (or re-scales, if already present) the preference-gated CRT
/// scanline roll. Same transform-scaling approach as apply_vignette() above.
/mob/living/carbon/human/proc/apply_crt_scanlines()
	overlay_fullscreen("crt_scanlines", /atom/movable/screen/fullscreen/crt_scanlines)
	// overlay_fullscreen() returns null when the overlay already exists --
	// fetch it back out of screens[] (same as apply_gameui_border() below)
	// so re-applies still rescale.
	var/atom/movable/screen/fullscreen/crt_scanlines/s = screens["crt_scanlines"]
	if(!s || !client)
		return
	var/list/vs = getviewsize(client.view)
	s.sweep_scale_x = vs[1] * WORLD_ICON_SIZE / 32
	s.sweep_px_h = vs[2] * WORLD_ICON_SIZE
	// Park the band off the top edge until the first roll fires.
	s.transform = s.band_matrix(0, s.sweep_px_h / 2 + 16)
	s.start_rolling()

// Decorative game window border. GAMEUI_BORDER_LAYER sits above film grain
// and vignette but below CHILLED_LAYER (chilled must stay visible over it)
// and still below HUD_PLANE. Same 480x480 single-state convention as
// chilled/vignette above -- this is what makes the CENTER-7,CENTER-7 anchor
// land the icon's center exactly on the view's center at any view size, so
// a transform scale from that anchor stays symmetric instead of magnifying
// an off-center chunk of the art. allstate = 1 so it also shows for
// DEAD-stat mobs (ghosts) and the new_player/lobby mob, since
// overlay_fullscreen() otherwise skips adding to client.screen for anyone
// read as dead -- see /fadeout above for the same reasoning.
/atom/movable/screen/fullscreen/gameui_border
	icon = 'icons/hud/gameui_border.png'
	icon_state = ""
	layer = GAMEUI_BORDER_LAYER
	allstate = 1

/// Universal (not human-only, and not gated on mob type at all -- shows on
/// the main menu/lobby mob too) HUD window border -- called from every mob
/// type's HUD (re)build via /datum/hud/proc/instantiate(), and again from
/// OnResize() so it re-fits live when the window is resized. Unlike
/// apply_vignette()/film_grain (human-scoped call sites), and unlike
/// overlay_fullscreen()'s own severity-based no-op-if-unchanged behavior,
/// this always recomputes the transform -- overlay_fullscreen() returns
/// null on repeat calls once the screen already exists, so the object is
/// fetched back out of screens[] to update its transform every time.
///
/// Scales to the map CONTROL rect (the view PLUS the letterbox margin
/// OnResize() reserves around it: 3 tiles each side, 1 tile top/bottom --
/// see client_procs.dm) rather than the view itself, so the border's arms
/// render in that margin (same space the gear HUD/status doll already
/// occupy) and the actual game view sits inside the border's transparent
/// opening, instead of the frame overlapping the map tiles.
/mob/proc/apply_gameui_border()
	overlay_fullscreen("gameui_border", /atom/movable/screen/fullscreen/gameui_border)
	var/atom/movable/screen/fullscreen/gameui_border/b = screens["gameui_border"]
	if(b && client)
		var/list/vs = getviewsize(client.view)
		b.transform = matrix((vs[1] + 6) * WORLD_ICON_SIZE / 480, 0, 0, 0, (vs[2] + 2) * WORLD_ICON_SIZE / 480, 0)

// Super Hug cap payoff (see apply_euphoric_rainbow) -- a plain tintable white plane, same
// icon/state lighting_backdrop uses above, cycled through hues via animate() at the call site.
/atom/movable/screen/fullscreen/euphoric_rainbow
	icon = 'icons/hud/mob/white.dmi'
	icon_state = "flash"
	blend_mode = BLEND_OVERLAY
	alpha = 120
	color = "#FF0000"
	transform = matrix(200, 0, 0, 0, 200, 0)
