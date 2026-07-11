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
