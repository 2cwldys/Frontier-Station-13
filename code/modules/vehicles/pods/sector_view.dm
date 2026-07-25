/*
 * Pod Sector View -- almost entirely lifted from Personal Travel's eye-view
 * trick (code/modules/modular_computers/file_system/programs/generic/
 * personal_travel.dm's _start_viewing()/_stop_viewing()/_refresh_sensor_view()/
 * _sector_click()), just hosted on the pod object instead of a handheld
 * program, and folded into the pod's own cockpit tgui instead of a separate
 * program window: possesses the pilot's client with a free-look eye on the
 * overmap plane at the pod's current sector, reveals nearby requires_contact
 * sectors/ships as real images if the pod's sensors part is installed and
 * active (known sectors are already plane-visible, no reveal needed -- see
 * sensors.dm), and lets the pilot click one to prime it as the pod's warp
 * destination (consumed by warp.dm's attempt_jump()).
 */
/obj/vehicle/bike/pod
	/// The mob currently borrowing this pod's Sector View camera, or null.
	var/mob/viewing_user
	/// The free-look eye possessing viewing_user for the duration of Sector
	/// View -- /mob/abstract/eye (code/modules/mob/abstract/freelook/eye.dm),
	/// the same mechanism ghosts/observers and Personal Travel already use.
	var/mob/abstract/eye/sector_eye
	/// Sensor-style marker images cast to the viewer while Sector View is
	/// active (requires_contact overmap objects are invisible atoms).
	var/list/sensor_images = list()
	/// "\ref" of the sector primed as the pending warp target by clicking it
	/// in Sector View. Re-validated live (get_primed_destination()).
	var/primed_ref = null
	/// Bumped on every start/stop -- invalidates any still-pending
	/// self-rescheduled refresh_sector_view() timers from a prior session.
	var/sector_view_seq = 0
	/// Whether this pod's own QDELETING self-cleanup hook has been
	/// registered yet (avoids re-registering every time Sector View starts).
	var/sector_view_cleanup_hooked = FALSE

/obj/vehicle/bike/pod/proc/toggle_sector_view(mob/user)
	if(viewing_user == user)
		stop_sector_view(user)
	else
		start_sector_view(user)

/obj/vehicle/bike/pod/proc/start_sector_view(mob/user)
	if(viewing_user)
		return
	var/obj/effect/overmap/visitable/current = get_current_sector()
	if(!current)
		to_chat(user, SPAN_WARNING("No overmap position could be found."))
		return

	if(!sector_view_cleanup_hooked)
		RegisterSignal(src, COMSIG_QDELETING, PROC_REF(_sector_view_pod_qdeleting))
		sector_view_cleanup_hooked = TRUE

	// Self-heal a marker stranded off the overmap before pointing the
	// camera at it -- see repair_stray_overmap_marker() (sectors.dm).
	repair_stray_overmap_marker(current)
	sector_eye = new(get_turf(current))
	// living_eye = FALSE routes through update_dead_sight() (full
	// SEE_TURFS|SEE_MOBS|SEE_OBJS regardless of lighting) instead of normal
	// lighting-respecting vision, which would render the unlit overmap
	// plane as solid black -- same lever the AI eye already uses.
	sector_eye.living_eye = FALSE
	sector_eye.possess(user)
	// possess() unconditionally snaps the eye back onto the owner's own
	// turf as its last step -- reassert the intended position immediately.
	sector_eye.setLoc(get_turf(current))
	if(user.client)
		user.client.saved_dynamic_view = user.client.view
		user.client.view = expanded_client_view(PERSONAL_TRAVEL_EXTRA_VIEW)
		if(user.client.skybox)
			user.client.screen -= user.client.skybox
		user.reload_fullscreen()
		// apply_gameui_border()'s scale math assumes client.view tracks the
		// real map-window pixel size -- a flat overmap view doesn't. Hide
		// rather than mis-scale it (same fix as the Nav/Sensors sector view
		// and Personal Travel's own Sector View).
		user.clear_fullscreen("gameui_border", FALSE)
	RegisterSignal(user, COMSIG_MOB_LOGOUT, PROC_REF(stop_sector_view))
	RegisterSignal(user, COMSIG_MOB_CLICKON, PROC_REF(sector_view_click))
	viewing_user = user
	sector_view_seq++
	refresh_sector_view()

/obj/vehicle/bike/pod/proc/stop_sector_view(mob/user)
	if(!viewing_user)
		return
	var/mob/former = viewing_user
	sector_view_seq++
	if(sector_eye)
		sector_eye.release(former)
	QDEL_NULL(sector_eye)
	var/client/c = former.client
	if(c)
		c.pixel_x = 0
		c.pixel_y = 0
		// Restore the exact cached dynamic view rather than re-deriving it
		// live -- re-derivation is only reliable right after a genuine
		// window resize event, not this transition.
		if(c.saved_dynamic_view)
			c.view = c.saved_dynamic_view
			c.saved_dynamic_view = null
		else
			c.refit_dynamic_view()
		c.update_skybox(TRUE)
		if(c.mob)
			c.mob.reload_fullscreen()
			c.mob.apply_gameui_border()
	if(former.client)
		for(var/image/I in sensor_images)
			former.client.images -= I
	sensor_images.Cut()
	UnregisterSignal(former, list(COMSIG_MOB_LOGOUT, COMSIG_MOB_CLICKON))
	viewing_user = null

/// Reveals nearby requires_contact overmap objects to the viewer (same
/// image-copy trick real ship sensors / Personal Travel use), gated on the
/// pod's sensors part being installed and active. Reschedules itself every
/// 2 seconds while viewing (ships move).
/obj/vehicle/bike/pod/proc/refresh_sector_view()
	if(!viewing_user?.client || !sector_eye)
		return
	for(var/image/I in sensor_images)
		viewing_user.client.images -= I
	sensor_images.Cut()

	var/obj/item/podcomponent/sensors/Sn = get_part(POD_PART_SENSORS)
	if(istype(Sn) && Sn.active)
		var/turf/T = get_turf(sector_eye)
		var/obj/effect/overmap/visitable/current = get_current_sector()
		if(T)
			for(var/obj/effect/overmap/O in view(Sn.range, T))
				if(!O.requires_contact)
					continue
				// Never give away another ship's position through this
				// free-look trick from a distance -- only real ship
				// navigation/sensor machinery (which gates on actual
				// detection, contact_sensors.dm) should reveal one from
				// afar. Your own current ship (if any) is exempt so it
				// still renders normally, and any ship (own or not) within
				// SECTOR_VIEW_SHIP_PROXIMITY_RANGE tiles of the eye's
				// current position reveals too -- close enough to target
				// for warp, which is click-to-prime only.
				if(istype(O, /obj/effect/overmap/visitable/ship) && O != current)
					// Cloaked ships never reveal via this trick regardless
					// of proximity -- the 4-tile exemption exists for
					// ordinary warp targeting, not to defeat a cloak.
					if(!O.is_detectable())
						continue
					if(get_dist(O, T) > SECTOR_VIEW_SHIP_PROXIMITY_RANGE)
						continue
				var/image/marker = image(null, O)
				marker.appearance = O.appearance
				// The appearance copy inherits the effect's
				// INVISIBILITY_OVERMAP -- reset it (and alpha) or the
				// marker hides exactly like the real atom does.
				marker.invisibility = 0
				marker.alpha = 255
				marker.mouse_opacity = MOUSE_OPACITY_ICON
				viewing_user.client.images += marker
				sensor_images += marker

	var/seq = sector_view_seq
	addtimer(CALLBACK(src, PROC_REF(_sector_view_refresh_tick), seq), 2 SECONDS)

/obj/vehicle/bike/pod/proc/_sector_view_refresh_tick(seq)
	if(seq != sector_view_seq || !viewing_user)
		return
	refresh_sector_view()

/// COMSIG_MOB_CLICKON handler while Sector View is active: clicking a
/// revealed sector/ship primes it as the pending jump target. The actual
/// jump still flows through warp.dm's normal attempt_jump() gates (comms,
/// cooldown, fuel) -- priming is just target selection.
/obj/vehicle/bike/pod/proc/sector_view_click(mob/source, atom/A, params)
	SIGNAL_HANDLER
	if(source != viewing_user)
		return
	if(!istype(A, /obj/effect/overmap))
		return
	if((!istype(A, /obj/effect/overmap/visitable/sector) && !istype(A, /obj/effect/overmap/visitable/ship)) || istype(A, /obj/effect/overmap/visitable/sector/temporary))
		to_chat(source, SPAN_WARNING("\The [A] cannot be primed as a jump destination."))
		return COMSIG_MOB_CANCEL_CLICKON
	var/obj/effect/overmap/visitable/target = A
	var/obj/effect/overmap/visitable/current = get_current_sector()
	if(target == current)
		to_chat(source, SPAN_WARNING("You're already here."))
		return COMSIG_MOB_CANCEL_CLICKON
	if(!current || get_dist(current, target) > POD_WARP_RANGE || !length(target.map_z))
		to_chat(source, SPAN_WARNING("\The [target] is out of jump range."))
		return COMSIG_MOB_CANCEL_CLICKON
	primed_ref = "\ref[target]"
	to_chat(source, SPAN_GOOD("Primed [target.name] as the jump destination."))
	return COMSIG_MOB_CANCEL_CLICKON

/// Live-validates and returns the currently primed destination, or null
/// (clearing primed_ref) if it's stale/out of range/gone.
/obj/vehicle/bike/pod/proc/get_primed_destination()
	if(!primed_ref)
		return null
	var/obj/effect/overmap/visitable/primed = locate(primed_ref)
	var/obj/effect/overmap/visitable/current = get_current_sector()
	if(!istype(primed) || !current || get_dist(current, primed) > POD_WARP_RANGE || !length(primed.map_z))
		primed_ref = null
		return null
	return primed

/// Sector View can't outlive the pod it's attached to -- release the
/// pilot's camera immediately if the pod is destroyed while someone's
/// viewing through it.
/obj/vehicle/bike/pod/proc/_sector_view_pod_qdeleting()
	SIGNAL_HANDLER
	if(viewing_user)
		stop_sector_view(viewing_user)
