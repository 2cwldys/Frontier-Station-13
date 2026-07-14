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
 * Leap requires a hardsuit (you're dropped on open space near the target,
 * not delivered somewhere sheltered) and only ever targets sectors that
 * already exist as live Zs -- see docs/overmap-traversal-research.md for why
 * on-demand Z materialization for a proximity mechanic is deliberately
 * avoided here. Return to Beacon / Return to Hub need no hardsuit and land
 * at a normal safe spot.
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

/// Any /turf/space-type turf found on the given Z -- Leap's landing spot.
/// Returns null if somehow no space turf exists on that Z (should not
/// happen for any real away site/sector, which are always embedded in
/// open space).
/proc/personal_travel_find_space_landing(z)
	for(var/turf/space/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		return T
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

	data["leap_destinations"] = list()
	if(my_sector)
		var/list/seen = list()
		for(var/key in GLOB.map_sectors)
			var/obj/effect/overmap/visitable/candidate = GLOB.map_sectors[key]
			if(!istype(candidate, /obj/effect/overmap/visitable/sector))
				continue
			if(istype(candidate, /obj/effect/overmap/visitable/sector/temporary))
				continue
			if(candidate == my_sector)
				continue
			if(candidate in seen)
				continue
			seen += candidate
			var/dist = get_dist(my_sector, candidate)
			if(dist > PERSONAL_TRAVEL_LEAP_RANGE)
				continue
			data["leap_destinations"] += list(list(
				"ref" = "\ref[candidate]",
				"name" = candidate.name,
				"is_away_site" = length(candidate.map_z) ? is_away_level(candidate.map_z[1]) : FALSE,
				"distance" = dist
			))

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
	var/require_hardsuit = FALSE

	switch(action)
		if("leap")
			require_hardsuit = TRUE
			var/obj/effect/overmap/visitable/target_sector = locate(params["sector_ref"])
			var/obj/effect/overmap/visitable/my_sector = _current_sector(user)
			if(!istype(target_sector) || !my_sector || get_dist(my_sector, target_sector) > PERSONAL_TRAVEL_LEAP_RANGE)
				to_chat(user, SPAN_WARNING("That destination is no longer in range."))
				return TRUE
			if(!length(target_sector.map_z))
				to_chat(user, SPAN_WARNING("That destination is no longer valid."))
				return TRUE
			destination = personal_travel_find_space_landing(target_sector.map_z[1])
			if(!destination)
				to_chat(user, SPAN_WARNING("No safe landing point could be found there."))
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

	if(require_hardsuit && !_has_hardsuit(user))
		to_chat(user, SPAN_WARNING("You need a hardsuit on to leap into open space."))
		return TRUE

	to_chat(user, SPAN_NOTICE("\The [computer] begins calibrating a bluespace jump..."))
	var/turf/spool_turf = get_turf(user)
	_travel_spool_pulse(spool_turf)
	addtimer(CALLBACK(src, PROC_REF(_travel_spool_pulse), spool_turf), 5 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(_travel_spool_pulse), spool_turf), 10 SECONDS)
	if(!do_after(user, PERSONAL_TRAVEL_SPOOLUP, user))
		to_chat(user, SPAN_WARNING("Bluespace calibration interrupted."))
		return TRUE
	if(user.in_recent_combat())
		to_chat(user, SPAN_WARNING("Combat detected -- jump aborted."))
		return TRUE

	_execute_travel(user, destination)
	return TRUE

/datum/computer_file/program/personal_travel/proc/_travel_spool_pulse(turf/T)
	if(!T)
		return
	spark(T, 2, GLOB.alldirs)
	playsound(T, 'sound/effects/sparks4.ogg', 20, 1)

/// forceMove, NOT do_teleport -- same reasoning as first_responder_jump():
/// the science teleport datum scatters anyone carrying a bag of holding up
/// to 100 tiles. We supply our own portal/spark/sound effects at both ends.
/datum/computer_file/program/personal_travel/proc/_execute_travel(mob/user, turf/dest)
	var/turf/origin = get_turf(user)
	if(origin)
		new /obj/effect/portal(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
		playsound(origin, 'sound/effects/phasein.ogg', 30, 1)
	new /obj/effect/portal(dest, null, null, 5 SECONDS, 0)
	spark(dest, 3, GLOB.alldirs)
	user.forceMove(dest)
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
	// _stop_viewing() takes a single mob/user param -- COMSIG_MOVABLE_MOVED
	// dispatches as (target_mob, old_loc, forced); DM silently drops the
	// extra args for a single-param proc, so target_mob lands correctly in
	// user. (A prior version routed this through a two-param
	// COMSIG_TGUI_CLOSE-shaped wrapper, which received old_loc -- a turf,
	// not a mob -- as user and crashed on user.reset_view(), aborting
	// cleanup before client.view/gameui_border were ever restored.)
	RegisterSignal(user, COMSIG_MOVABLE_MOVED, PROC_REF(_stop_viewing))
	// Aghosting/disconnecting is a key transfer, not a Move -- without this
	// hook viewing_user dangles across the round-trip, inverting the toggle
	// (first click "exits" a phantom session) and leaving check_eye()
	// answering for a session that no longer exists.
	RegisterSignal(user, COMSIG_MOB_LOGOUT, PROC_REF(_stop_viewing))
	viewing_user = user

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
	UnregisterSignal(user, list(COMSIG_MOVABLE_MOVED, COMSIG_MOB_LOGOUT))
	viewing_user = null

/// handle_vision() (life.dm) polls machine.check_eye() every tick and
/// snaps the camera back to the mob on any negative return. The base
/// program check_eye() is an unconditional -1 (program.dm), which yanked
/// Sector View shut whenever user.machine happened to be set to this
/// computer. Same override pattern as the camera monitor program.
/datum/computer_file/program/personal_travel/check_eye(mob/user)
	if(viewing_user == user)
		return SEE_THRU
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
