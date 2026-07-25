/obj/skybox
	name = "skybox"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	anchored = TRUE
	simulated = FALSE
	screen_loc = "CENTER:-224,CENTER:-224"
	plane = SKYBOX_PLANE

/client
	var/obj/skybox/skybox

/client/proc/update_skybox(rebuild)
	if(!skybox)
		skybox = new()
		rebuild = TRUE
	// Unconditional: previously nested inside `if(T)` below, so a call that
	// landed on a null turf (eye mid-transition -- notably unlook()/
	// stop_sector_view() calling this right after reset_view()) silently
	// skipped re-adding a skybox that look()/start_sector_view() had
	// deliberately stripped from screen, leaving space turfs' raw white
	// base sprite (icons/turf/space.dmi "white") visible with nothing
	// multiplying real starfield art over it until the next real z-change
	// or relog.
	screen |= skybox

	var/turf/T = get_turf(eye)
	if(!T)
		return
	if(rebuild)
		skybox.overlays.Cut()
		skybox.overlays += SSskybox.get_skybox(T.z)
	skybox.screen_loc = "CENTER:[-224 - T.x],CENTER:[-224 - T.y]"

/mob/Move(atom/newloc, direct, glide_size_override, update_dir)
	var/old_z = GET_Z(src)
	. = ..()
	if(. && client)
		client.update_skybox(old_z != GET_Z(src))
