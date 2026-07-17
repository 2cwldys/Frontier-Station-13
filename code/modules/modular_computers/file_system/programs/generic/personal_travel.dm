/*
 * Personal Travel
 * A minimal PDA-compatible program letting any player leap to a nearby,
 * already-materialized away site/sector based on overmap proximity, return
 * to their faction's beacon if currently in range of one, or return to the
 * Hub's own travel pad. Leap itself is deliberately NOT pad-based -- no
 * dependency on telepad_travel.dm's link-code network. Return to Hub is the
 * one exception: it targets a single, fixed, admin-placed
 * telepad_cargo/travel/hub instance directly by type (see telepad_travel.dm),
 * bypassing that pad's normal link_code matching entirely.
 *
 * Leap requires a hardsuit (you may be dropped in open space near the
 * target, or on unsheltered solid ground for asteroid/exoplanet sites --
 * either way, not delivered somewhere sheltered) and only ever targets
 * sectors that already exist as live Zs -- see
 * docs/overmap-traversal-research.md for why on-demand Z materialization
 * for a proximity mechanic is deliberately avoided here. Return to Beacon /
 * Return to Hub need no hardsuit and land at a normal safe spot.
 *
 * All three travel actions share a 15-second interruptible spool-up, a
 * cooldown, and a 10-minute post-combat lockout (see last_combat_time,
 * living_defines.dm/damage_procs.dm/item_attack.dm).
 *
 * Also offers a Sector View toggle -- the same look()/unlook() overmap
 * camera trick the Nav/Sensors consoles use (ship.dm), hosted on this
 * program datum instead of a machine atom, reusing the gameui_border fix
 * from that same system (its scale math assumes client.view tracks the real
 * window size, which a flat overmap view doesn't -- hide rather than
 * mis-scale it).
 */

/// Leap's landing spot on the given Z. Away sites embedded in open space
/// land on a non-dense /turf/space tile; solid-ground away sites (asteroids,
/// exoplanets) have no space turfs at all, so this falls back to a
/// non-dense /turf/simulated/floor/exoplanet tile (covers every
/// asteroid/exoplanet biome floor via inheritance) that isn't blocked by a
/// dense anchored object -- same safety shape as
/// first_responder_clear_turf_near() (first_responder.dm). Picks randomly
/// among whichever candidate list is non-empty, rather than always the
/// first raster-order tile. Returns null only if the whole Z is
/// impassable, which should not happen for any real away site/sector.
/proc/personal_travel_find_space_landing(z)
	var/list/space_candidates = list()
	for(var/turf/space/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(!T.density)
			space_candidates += T
	if(length(space_candidates))
		return pick(space_candidates)

	var/list/ground_candidates = list()
	for(var/turf/simulated/floor/exoplanet/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.density)
			continue
		var/blocked = FALSE
		for(var/obj/O in T)
			if(O.density && O.anchored)
				blocked = TRUE
				break
		if(!blocked)
			ground_candidates += T
	if(length(ground_candidates))
		return pick(ground_candidates)

	return null

/datum/computer_file/program/personal_travel
	filename = "personaltravel"
	filedesc = "Personal Travel"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Leap to nearby away sites, return to your faction beacon, or return to the Hub."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_TABLET
	requires_ntnet = FALSE
	size = 2 // matches scanner.dm's precedent for a minimal utility program
	tgui_id = "PersonalTravel"
	ui_auto_update = TRUE

	var/next_travel_time = 0
	/// Non-null while this program's Sector View is active -- the mob
	/// currently borrowing this program's camera, so kill_program()/the
	/// toggle-off path know exactly who to restore.
	var/mob/viewing_user = null
	/// Sensor-style marker images cast to the viewer while Sector View is
	/// active (requires_contact overmap objects are invisible atoms; ship
	/// sensors reveal them via contact images -- this is the same trick,
	/// program-owned, solo-viewer).
	var/list/sensor_images = list()
	/// Next world.time the sensor markers get rebuilt (ships move).
	var/sensor_refresh_next = 0
	/// "\ref" of the sector primed as leap target by clicking it in Sector
	/// View. Validated live in ui_data and by the normal leap gates.
	var/primed_ref = null
	/// Spool-up generation counter: the 5s/10s spark pulses are scheduled
	/// up front and carry the sequence they belong to -- bumping this on
	/// interrupt/abort invalidates any still-pending pulses.
	var/spool_seq = 0

/datum/computer_file/program/personal_travel/proc/_current_sector(mob/user)
	if(!user)
		return null
	return GLOB.map_sectors["[GET_Z(user)]"]

/datum/computer_file/program/personal_travel/proc/_has_hardsuit(mob/user)
	if(!ishuman(user))
		return FALSE
	var/mob/living/carbon/human/H = user
	return istype(H.wear_suit, /obj/item/clothing/suit/space)

/datum/computer_file/program/personal_travel/ui_data(mob/user)
	var/list/data = initial_data()

	var/obj/effect/overmap/visitable/my_sector = _current_sector(user)
	data["sector_name"] = my_sector ? my_sector.name : "Unknown"
	data["is_away_site"] = my_sector ? is_away_level(GET_Z(user)) : FALSE
	data["viewing"] = (viewing_user == user)

	var/mob/living/L = user
	var/in_combat = istype(L) ? L.in_recent_combat() : FALSE
	data["in_combat"] = in_combat
	data["combat_seconds_left"] = in_combat ? max(0, round((L.last_combat_time + PERSONAL_TRAVEL_COMBAT_LOCKOUT - world.time) / 10)) : 0

	data["cooldown_seconds_left"] = max(0, round((next_travel_time - world.time) / 10))
	data["has_hardsuit"] = _has_hardsuit(user)

	// "You are in X territory." -- any active faction beacon whose coverage
	// (own station Zs, or security_radius around its sector) includes the
	// user's current sector. Same coverage logic as the return-beacon loop
	// below, minus the own-faction filter. First covering beacon wins.
	data["territory_faction"] = null
	if(my_sector)
		for(var/obj/structure/machinery/faction_beacon/B in world)
			if(istype(B, /obj/structure/machinery/faction_beacon/hub))
				continue
			if(!B.active || !B.powered || QDELETED(B))
				continue
			var/covers = (GET_Z(user) in B._station_zs())
			if(!covers && B.security_radius > 0)
				var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
				if(istype(beacon_sector))
					for(var/obj/effect/overmap/visitable/V in range(B.security_radius, beacon_sector))
						if(V == my_sector)
							covers = TRUE
							break
			if(covers)
				data["territory_faction"] = get_faction_name(B.faction_uid)
				break

	// Click-primed leap target (Sector View) -- validated live so a stale
	// or out-of-range prime clears itself.
	data["primed"] = null
	if(primed_ref)
		var/obj/effect/overmap/visitable/primed = locate(primed_ref)
		if(istype(primed) && my_sector && get_dist(my_sector, primed) <= PERSONAL_TRAVEL_LEAP_RANGE && length(primed.map_z))
			data["primed"] = list("ref" = primed_ref, "name" = primed.name, "distance" = get_dist(my_sector, primed))
		else
			primed_ref = null


	data["beacon_destinations"] = list()
	var/obj/item/card/id/ID = user.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	if(own_faction && my_sector)
		for(var/obj/structure/machinery/faction_beacon/B in world)
			if(istype(B, /obj/structure/machinery/faction_beacon/hub))
				continue
			if(!B.active || !B.powered || QDELETED(B))
				continue
			if(normalize_faction_uid(B.faction_uid) != own_faction)
				continue
			var/qualifies = (GET_Z(user) in B._station_zs())
			if(!qualifies && B.security_radius > 0)
				var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
				if(istype(beacon_sector))
					for(var/obj/effect/overmap/visitable/V in range(B.security_radius, beacon_sector))
						if(V == my_sector)
							qualifies = TRUE
							break
			if(qualifies)
				data["beacon_destinations"] += list(list(
					"ref" = "\ref[B]",
					"name" = get_faction_name(B.faction_uid)
				))

	return data

/datum/computer_file/program/personal_travel/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/living/user = usr
	if(!istype(user))
		return TRUE

	if(action == "toggle_view")
		if(viewing_user == user)
			_stop_viewing(user)
		else
			_start_viewing(user)
		return TRUE

	if(!(action in list("leap", "return_beacon", "return_hub")))
		return TRUE

	if(user.in_recent_combat())
		to_chat(user, SPAN_WARNING("\The [computer] flashes: RECENT COMBAT DETECTED -- systems locked."))
		return TRUE
	if(world.time < next_travel_time)
		to_chat(user, SPAN_WARNING("\The [computer] is still recalibrating."))
		return TRUE

	var/turf/destination
	var/target_z // leap only -- kept for the post-spool-up revalidation below

	switch(action)
		if("leap")
			// Checked before the (potentially ~60s) eye-view pick opens --
			// no point making a player sit through an interactive turf
			// choice only to refuse them afterward for lacking a hardsuit.
			if(!_has_hardsuit(user))
				to_chat(user, SPAN_WARNING("You need a hardsuit on to leap into open space."))
				return TRUE
			var/obj/effect/overmap/visitable/target_sector = locate(primed_ref)
			var/obj/effect/overmap/visitable/my_sector = _current_sector(user)
			if(!istype(target_sector) || !my_sector || get_dist(my_sector, target_sector) > PERSONAL_TRAVEL_LEAP_RANGE)
				to_chat(user, SPAN_WARNING("That destination is no longer in range."))
				return TRUE
			if(!length(target_sector.map_z))
				to_chat(user, SPAN_WARNING("That destination is no longer valid."))
				return TRUE
			target_z = target_sector.map_z[1]
			var/turf/anchor = personal_travel_find_space_landing(target_z)
			if(!anchor)
				to_chat(user, SPAN_WARNING("No safe landing point could be found there."))
				return TRUE
			// Eye-view turf-pick (telepad_drydock_boarding.dm) replaces the
			// old random pick outright -- same anti-cheese rule already
			// established there (exterior-only if the Z is faction/pirate
			// beacon claimed, via _drydock_pick_access_mode()). A failed/
			// timed-out/cancelled pick aborts the whole leap -- no cooldown
			// consumed, no travel -- matching how drydock boarding treats it.
			destination = _drydock_pick_destination_turf(user, target_z, anchor)
			if(!destination)
				return TRUE
		if("return_beacon")
			var/obj/structure/machinery/faction_beacon/B = locate(params["beacon_ref"])
			if(!istype(B) || QDELETED(B))
				to_chat(user, SPAN_WARNING("That beacon is no longer available."))
				return TRUE
			destination = get_turf(B)
		if("return_hub")
			for(var/obj/structure/machinery/telepad_cargo/travel/hub/H in world)
				if(QDELETED(H))
					continue
				destination = get_turf(H)
				break
			if(!destination)
				to_chat(user, SPAN_WARNING("No Hub travel pad could be found."))
				return TRUE

	if(!destination)
		return TRUE

	to_chat(user, SPAN_NOTICE("\The [computer] begins calibrating a bluespace jump..."))
	var/turf/spool_turf = get_turf(user)
	var/seq = ++spool_seq
	_travel_spool_pulse(spool_turf, seq)
	addtimer(CALLBACK(src, PROC_REF(_travel_spool_pulse), spool_turf, seq), 5 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(_travel_spool_pulse), spool_turf, seq), 10 SECONDS)
	if(!do_after(user, PERSONAL_TRAVEL_SPOOLUP, user))
		spool_seq++ // invalidate the pending spark pulses above
		to_chat(user, SPAN_WARNING("Bluespace calibration interrupted."))
		return TRUE
	if(user.in_recent_combat())
		spool_seq++ // invalidate the pending spark pulses above
		to_chat(user, SPAN_WARNING("Combat detected -- jump aborted."))
		return TRUE

	if(action == "leap")
		// The pick + spool-up window can span up to ~75s total -- re-verify
		// both that the destination Z is still reachable and that the
		// specific picked turf is still valid (beacon claim state or
		// density may have changed since), mirroring drydock boarding's own
		// post-spool-up recheck (_drydock_board_deliver(),
		// telepad_drydock_boarding.dm).
		var/obj/effect/overmap/visitable/recheck_sector = GLOB.map_sectors["[target_z]"]
		var/obj/effect/overmap/visitable/recheck_my_sector = _current_sector(user)
		if(!istype(recheck_sector) || !istype(recheck_my_sector) || get_dist(recheck_my_sector, recheck_sector) > PERSONAL_TRAVEL_LEAP_RANGE)
			to_chat(user, SPAN_WARNING("You're no longer close enough to leap there."))
			return TRUE
		if(destination.density || !_drydock_pick_turf_valid(destination, user, target_z))
			to_chat(user, SPAN_WARNING("The landing point is no longer available."))
			return TRUE

	_execute_travel(user, destination)
	return TRUE

/datum/computer_file/program/personal_travel/proc/_travel_spool_pulse(turf/T, seq)
	if(!T)
		return
	// Stale pulse from an interrupted/aborted spool-up -- the sparks must
	// stop the moment the calibration does.
	if(seq != spool_seq)
		return
	spark(T, 2, GLOB.alldirs)
	playsound(T, 'sound/effects/sparks4.ogg', 20, 1)

/// forceMove, NOT do_teleport -- same reasoning as first_responder_jump():
/// the science teleport datum scatters anyone carrying a bag of holding up
/// to 100 tiles. We supply our own portal/spark/sound effects at both ends.
/datum/computer_file/program/personal_travel/proc/_execute_travel(mob/user, turf/dest)
	var/turf/origin = get_turf(user)
	var/atom/movable/pulled = user.pulling
	if(origin)
		new /obj/effect/portal/decorative(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
		playsound(origin, 'sound/effects/phasein.ogg', 30, 1)
	new /obj/effect/portal/decorative(dest, null, null, 5 SECONDS, 0)
	spark(dest, 3, GLOB.alldirs)
	user.forceMove(dest)
	if(pulled && !QDELETED(pulled))
		pulled.forceMove(dest)
	playsound(dest, 'sound/effects/phasein.ogg', 30, 1)
	to_chat(user, SPAN_GOOD("You leap through a bluespace rift."))
	next_travel_time = world.time + PERSONAL_TRAVEL_COOLDOWN

/// world.view is a "WxH" string in this fork (world.dm), not a bare
/// number -- naive `world.view + N` string-concatenates instead of
/// computing a wider view (e.g. "15x15" + 4 -> "15x154", a malformed
/// viewport). Parse out the numeric base and return a plain int for
/// client.view (a square NxN view).
/proc/expanded_client_view(extra)
	var/list/parts = splittext("[world.view]", "x")
	return (text2num(parts[1]) || 15) + extra

/// Sector View -- same look() trick computer/ship uses (ship.dm), hosted on
/// this program datum instead of a machine atom.
/datum/computer_file/program/personal_travel/proc/_start_viewing(mob/user)
	var/obj/effect/overmap/visitable/my_sector = _current_sector(user)
	if(!my_sector)
		to_chat(user, SPAN_WARNING("No overmap position could be found."))
		return
	// Self-heal markers stranded off the overmap (failed/raced placement)
	// before pointing the camera at them -- see repair_stray_overmap_marker
	// (sectors.dm).
	repair_stray_overmap_marker(my_sector)
	// check_eye()'s sight grant (the full-reveal trio) only flows while the
	// hosting computer IS the mob's polled `machine` -- claim it explicitly
	// (PDAs in hand never set it on their own).
	user.set_machine(computer)
	user.reset_view(my_sector)
	if(user.client)
		// Cache the real dynamic view so _stop_viewing() can restore it
		// directly instead of asking refit_dynamic_view() to re-derive it
		// live -- that recompute is only reliable right after a genuine
		// window resize event, not this transition (Sector View Bug D).
		user.client.saved_dynamic_view = user.client.view
		user.client.view = expanded_client_view(PERSONAL_TRAVEL_EXTRA_VIEW)
		if(user.client.skybox)
			user.client.screen -= user.client.skybox
		user.reload_fullscreen()
		// apply_gameui_border()'s scale math assumes client.view tracks the
		// real map-window pixel size -- a flat overmap view doesn't. Hide
		// rather than mis-scale it (same fix as the Nav/Sensors sector view).
		user.clear_fullscreen("gameui_border", FALSE)
	// No COMSIG_MOVABLE_MOVED cancel here, deliberately: a handheld program
	// travels WITH the user (drifting in zero-g fires Move() constantly and
	// used to kill the view within seconds anywhere without gravity). Ship
	// consoles keep their walk-away cancel; this one exits via the toggle,
	// logout, or kill_program().
	// Aghosting/disconnecting is a key transfer, not a Move -- without this
	// hook viewing_user dangles across the round-trip, inverting the toggle
	// (first click "exits" a phantom session) and leaving check_eye()
	// answering for a session that no longer exists.
	RegisterSignal(user, COMSIG_MOB_LOGOUT, PROC_REF(_stop_viewing))
	// Click-to-prime: clicking a sensor-revealed sector marks it as the
	// pending leap target (see _sector_click below).
	RegisterSignal(user, COMSIG_MOB_CLICKON, PROC_REF(_sector_click))
	viewing_user = user
	_refresh_sensor_view(user)

/datum/computer_file/program/personal_travel/proc/_stop_viewing(mob/user)
	if(!user)
		return
	user.reset_view()
	var/client/c = user.client
	if(c)
		c.pixel_x = 0
		c.pixel_y = 0
		// Restore the exact dynamic view cached by _start_viewing() rather
		// than asking refit_dynamic_view() to re-derive it live -- see
		// ship.dm's unlook() for the full explanation (Sector View Bug D).
		if(c.saved_dynamic_view)
			c.view = c.saved_dynamic_view
			c.saved_dynamic_view = null
		else
			c.refit_dynamic_view()
		c.update_skybox(TRUE)
		if(c.mob)
			c.mob.reload_fullscreen()
			c.mob.apply_gameui_border()
	if(user.machine == computer)
		user.unset_machine()
	if(user.client)
		for(var/image/I in sensor_images)
			user.client.images -= I
	sensor_images.Cut()
	UnregisterSignal(user, list(COMSIG_MOB_LOGOUT, COMSIG_MOB_CLICKON))
	viewing_user = null

/// Shows the viewer the same overmap objects ship sensors would reveal:
/// requires_contact effects are INVISIBLE atoms (INVISIBILITY_OVERMAP,
/// overmap_object.dm:134) -- ship sensors render them via contact images
/// cast to navigation_viewers (contacts/_contacts.dm). Same trick here,
/// program-owned and cast only to this viewer. Rebuilt periodically from
/// process_tick() while viewing, since ships move.
/datum/computer_file/program/personal_travel/proc/_refresh_sensor_view(mob/user)
	if(!user?.client)
		return
	for(var/image/I in sensor_images)
		user.client.images -= I
	sensor_images.Cut()
	var/obj/effect/overmap/visitable/my_sector = _current_sector(user)
	if(!my_sector)
		return
	var/turf/T = get_turf(my_sector)
	if(!T)
		return
	// view() (not range) -- the same opacity-respecting scan ship sensors
	// use (contact_sensors.dm), so hazard clouds block this too.
	for(var/obj/effect/overmap/O in view(PERSONAL_TRAVEL_LEAP_RANGE, T))
		if(O == my_sector || !O.requires_contact)
			continue
		var/image/marker = image(null, O)
		marker.appearance = O.appearance
		// The appearance copy inherits the effect's INVISIBILITY_OVERMAP --
		// reset it (and alpha) or the marker hides exactly like the atom.
		marker.invisibility = 0
		marker.alpha = 255
		marker.mouse_opacity = MOUSE_OPACITY_ICON
		user.client.images += marker
		sensor_images += marker

/datum/computer_file/program/personal_travel/process_tick()
	. = ..()
	if(viewing_user && world.time >= sensor_refresh_next)
		sensor_refresh_next = world.time + 2 SECONDS
		_refresh_sensor_view(viewing_user)

/// COMSIG_MOB_CLICKON handler while Sector View is active: clicking a
/// sensor-revealed sector primes it as the pending leap target. The actual
/// leap still flows through the normal "leap" ui_act gates (range,
/// hardsuit, spool-up, combat lockout) -- priming is just target selection.
/datum/computer_file/program/personal_travel/proc/_sector_click(mob/source, atom/A, params)
	SIGNAL_HANDLER
	if(source != viewing_user)
		return
	if(!istype(A, /obj/effect/overmap))
		return
	if((!istype(A, /obj/effect/overmap/visitable/sector) && !istype(A, /obj/effect/overmap/visitable/ship)) || istype(A, /obj/effect/overmap/visitable/sector/temporary))
		to_chat(source, SPAN_WARNING("\The [A] cannot be primed as a leap destination."))
		return COMSIG_MOB_CANCEL_CLICKON
	var/obj/effect/overmap/visitable/target = A
	var/obj/effect/overmap/visitable/my_sector = _current_sector(source)
	if(!my_sector || get_dist(my_sector, target) > PERSONAL_TRAVEL_LEAP_RANGE || !length(target.map_z))
		to_chat(source, SPAN_WARNING("\The [target] is out of leap range."))
		return COMSIG_MOB_CANCEL_CLICKON
	primed_ref = "\ref[target]"
	to_chat(source, SPAN_GOOD("Primed [target.name] as the leap destination."))
	return COMSIG_MOB_CANCEL_CLICKON

/// handle_vision() (life.dm) polls machine.check_eye() every tick and
/// snaps the camera back to the mob on any negative return. The base
/// program check_eye() is an unconditional -1 (program.dm), which yanked
/// Sector View shut whenever user.machine happened to be set to this
/// computer. Same override pattern as the camera monitor program.
/datum/computer_file/program/personal_travel/check_eye(mob/user)
	if(viewing_user == user)
		// Full-reveal trio (camera XRay pattern) -- see ship.dm's check_eye
		// note: hides nothing on the overmap plane behind opaque hazards.
		return SEE_THRU|SEE_TURFS|SEE_OBJS|SEE_MOBS
	// FALSE (0), not -1: negative means "actively cancel the view NOW,
	// every tick" (handle_vision, life.dm) -- correct only for a session
	// this program owns that went invalid. A stale `machine` ref can point
	// here long after use (aghost closes the TGUI without the ui_status
	// recheck that calls unset_machine()), and -1 would then yank ANY
	// other console's sector view back to the mob every tick. Same
	// semantics as the ship console's !viewing_overmap() branch (ship.dm).
	return FALSE

/datum/computer_file/program/personal_travel/kill_program(forced = 0)
	if(viewing_user)
		_stop_viewing(viewing_user)
	return ..()
