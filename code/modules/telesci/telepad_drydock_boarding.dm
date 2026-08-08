/*
 * Drydock Boarding Pad
 *
 * A retrieved drydock ship materializes on its own dedicated Z with no
 * walkable connection to anywhere -- Retrieve places its overmap marker
 * in the target sector, it doesn't dock there. This pad is the
 * station-side way on: deliver a player to the target ship's own
 * navigation console (shuttle_control), not a dedicated ship-side pad --
 * every ship template already MUST place a console for the ship to be
 * flyable at all, so this needs zero extra map content in any current or
 * future ship template. A drydock ship can be personally owned or faction-
 * owned, and more than one can be deployed at once, so there's no single
 * "the" ship to route to -- offers a picker when there's more than one
 * candidate (same tgui_input_list pattern the First Responder telepad
 * picker uses). Being listed on a ship's crew list (drydockAddCrew(),
 * persistence_shuttles.dm) grants boarding access the same as ownership or
 * faction membership -- through both this pad and the Drydock program's
 * "Enter Ship" button alike, since both funnel through the same
 * _drydock_board_core() below. Candidates are filtered to ships in the same
 * or an adjacent overmap sector as the boarding mob -- being crew (or an
 * owner/faction member) grants visibility to board, but only once actually
 * nearby. Boarding itself takes a DRYDOCK_BOARDING_SPOOLUP-second
 * interruptible spool-up (do_after + in_recent_combat() recheck, mirroring
 * personal_travel.dm's own pattern) so a fight can't be fled from by
 * instantly teleporting aboard.
 *
 * Getting back off is a mob verb (disembark_drydock_ship(), below), not a
 * second pad -- same reasoning: no ship-side object to place. Only works
 * while the ship is genuinely landed/docked somewhere (you can't step off
 * mid-flight) -- not delayed, unlike boarding, since stepping off isn't an
 * escape vector the same way boarding is.
 *
 * Faction tagger-compatible, inherited for free from the base
 * telepad_cargo hooks -- untagged/public (the default) offers every ship
 * the boarding mob owns, personal or any faction; tagging it to a faction
 * restricts that specific pad to that faction's own ships only (personal
 * ships don't board through a faction-tagged pad).
 */
/obj/structure/machinery/telepad_cargo/drydock_boarding
	name = "drydock boarding pad"
	desc = "A tuned telepad that boards you onto one of your currently deployed drydock ships, at its navigation console. Untagged, it's open to any ship you own; tag it with a faction tagger to restrict it to that faction's ships only. Wrench to secure before use -- it won't function while unanchored."
	color = "#44aaff"
	accepts_cargo = FALSE
	anchored = FALSE // starts unanchored when cargo-ordered -- won't function until wrenched down, same convention as every other player-placed anchor machine

	/// Per-ckey flood/spam cooldown, mirrors corvette_boarding's own idiom.
	var/static/list/last_boarded_by_ckey = list()

/obj/structure/machinery/telepad_cargo/drydock_boarding/Initialize()
	. = ..()
	verbs -= /obj/structure/machinery/telepad_cargo/verb/configure_supply_network

/obj/structure/machinery/telepad_cargo/drydock_boarding/attack_hand(mob/user)
	if(..())
		return TRUE
	if(!anchored)
		to_chat(user, SPAN_WARNING("\The [src] needs to be secured to the floor with a wrench first."))
		return TRUE
	drydock_board_mob(user, src)
	return TRUE

/// Sector the mob L is currently in, or null if L isn't on any registered
/// overmap Z -- shared by the candidate proximity filter and its post-delay
/// recheck below.
/proc/_drydock_boarder_sector(mob/living/L)
	var/turf/T = get_turf(L)
	return T ? GLOB.map_sectors["[T.z]"] : null

/*
 * Turf-Pick Eye View (additive -- does not replace the instant delivery
 * paths above/below)
 *
 * An optional alternative to instant delivery for both boarding and
 * disembarking: opens a temporary remote view of a real physical Z (not the
 * abstract overmap grid) and lets the player click any valid turf to choose
 * exactly where they arrive, instead of the single fixed destination.
 * Reuses the same reset_view()/sight-flag/expanded-view trick the ship
 * computer's own sector camera view (look()/unlook(), computers/ship.dm)
 * and Personal Travel's Sector View (personal_travel.dm) already use --
 * just aimed at a real turf instead of an overmap object, and click-to-
 * target instead of click-to-prime.
 *
 * Access control (the anti-cheese rule): a target Z the picking mob doesn't
 * have legitimate access to -- another player's deployed ship they're not
 * owner/faction/crew of, or an away site/station currently claimed by an
 * active faction beacon -- only accepts open-space/exterior turfs, never
 * real floor/interior tiles. You can't portal straight through someone's
 * walls and security; you have to land outside and walk in. Your own
 * ship's interior, and any unclaimed site, has no such restriction.
 */
/obj/effect/drydock_pick_anchor
	name = ""
	invisibility = INVISIBILITY_ABSTRACT
	anchored = TRUE
	density = FALSE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	var/mob/living/user
	var/target_z
	var/turf/picked_turf
	var/state = DRYDOCK_PICK_STATE_WAITING
	/// The free-look eye possessing the user for the duration of the pick --
	/// gives keyboard panning around target_z for free via the same
	/// mechanism ghosts/observers already use (mob_movement.dm redirects
	/// movement keys to EyeMove() whenever mob.eyeobj is set), instead of a
	/// static camera fixed on this anchor's own turf.
	var/mob/abstract/eye/pick_eye

/// Opens the remote view for L onto target_z, anchored at this object's own
/// turf. Mirrors ship.dm's look() almost exactly, applied directly to one
/// stored mob instead of a shared viewers list (this anchor only ever
/// serves the one mob that requested it).
/obj/effect/drydock_pick_anchor/proc/begin(mob/living/L, target_z)
	src.user = L
	src.target_z = target_z
	L.set_machine(src)
	pick_eye = new(get_turf(src))
	// living_eye = TRUE (the default) routes through update_living_sight()
	// (life.dm) -- normal lighting-respecting vision, which can render an
	// unlit remote Z as solid black. FALSE routes through
	// update_dead_sight() instead (full SEE_TURFS|SEE_MOBS|SEE_OBJS,
	// regardless of lighting) -- the same lever the AI eye already uses
	// (freelook/ai/eye.dm) to see through dark areas.
	pick_eye.living_eye = FALSE
	pick_eye.possess(L)
	// possess() unconditionally snaps the eye back onto the owner's own
	// turf as its last step (setLoc(owner), eye.dm) -- reassert the real
	// intended position (this anchor's own turf, on target_z) immediately
	// after. Shared by Exit Ship disembark and Enter Ship's "Choose Landing
	// Spot" boarding option -- fixes both.
	pick_eye.setLoc(get_turf(src))
	if(L.client)
		L.client.saved_dynamic_view = L.client.view
		L.client.view = expanded_client_view(DRYDOCK_PICK_EXTRA_VIEW)
		if(L.client.skybox)
			L.client.screen -= L.client.skybox
		L.reload_fullscreen()
		L.clear_fullscreen("gameui_border", FALSE)
		if(istype(L, /mob/living/carbon/human))
			var/mob/living/carbon/human/H = L
			if(H.eye_view_cancel_button)
				L.client.screen |= H.eye_view_cancel_button
	RegisterSignal(L, COMSIG_MOB_LOGOUT, PROC_REF(_on_cancel_signal))
	RegisterSignal(L, COMSIG_MOVABLE_MOVED, PROC_REF(_on_cancel_signal))
	RegisterSignal(L, COMSIG_MOB_CLICKON, PROC_REF(_on_click))
	ADD_TRAIT(L, TRAIT_COMPUTER_VIEW, REF(src))

/// COMSIG_MOB_CLICKON handler while picking is active: validates the
/// clicked turf and either confirms it or rejects with a reason, staying
/// WAITING either way until a valid pick lands. Always consumes the click
/// so browsing the remote view never triggers normal movement/attack.
/obj/effect/drydock_pick_anchor/proc/_on_click(mob/source, atom/A, params)
	SIGNAL_HANDLER
	if(state != DRYDOCK_PICK_STATE_WAITING)
		return
	if(istype(A, /atom/movable/screen))
		return
	var/turf/T = get_turf(A)
	if(!T || T.z != target_z)
		to_chat(source, SPAN_WARNING("That's outside the area you're viewing."))
		return COMSIG_MOB_CANCEL_CLICKON
	if(T.density)
		to_chat(source, SPAN_WARNING("That spot is obstructed."))
		return COMSIG_MOB_CANCEL_CLICKON
	if(!_drydock_pick_turf_valid(T, source, target_z))
		to_chat(source, SPAN_WARNING("You don't have clearance to land there -- try open space instead."))
		return COMSIG_MOB_CANCEL_CLICKON
	picked_turf = T
	state = DRYDOCK_PICK_STATE_CONFIRMED
	return COMSIG_MOB_CANCEL_CLICKON

/// Shared handler for both COMSIG_MOB_LOGOUT and COMSIG_MOVABLE_MOVED --
/// mirrors ship.dm's own unlook() being registered for both signals
/// identically. A real move or a disconnect both silently cancel an
/// in-progress pick, same as the ship computer's own camera view does.
/obj/effect/drydock_pick_anchor/proc/_on_cancel_signal()
	SIGNAL_HANDLER
	if(state == DRYDOCK_PICK_STATE_WAITING)
		state = DRYDOCK_PICK_STATE_CANCELLED

/// Deliberate, explicit cancel -- the "Exit Eye View" HUD button. Unlike
/// the silent move/logout cancel above, this is a purposeful player action,
/// so it gets its own clear confirmation instead of just quietly tearing
/// down.
/obj/effect/drydock_pick_anchor/proc/cancel(mob/user)
	if(state != DRYDOCK_PICK_STATE_WAITING)
		return
	state = DRYDOCK_PICK_STATE_CANCELLED
	to_chat(user, SPAN_NOTICE("Landing selection cancelled."))

/// Single teardown path for every exit (confirmed pick, timeout, cancel,
/// disconnect, or a forced qdel) -- mirrors ship.dm's unlook() applied
/// directly to the stored user.
/obj/effect/drydock_pick_anchor/Destroy()
	if(user)
		UnregisterSignal(user, list(COMSIG_MOB_LOGOUT, COMSIG_MOVABLE_MOVED, COMSIG_MOB_CLICKON))
		REMOVE_TRAIT(user, TRAIT_COMPUTER_VIEW, REF(src))
		if(!QDELETED(user))
			if(pick_eye)
				pick_eye.release(user)
			var/client/c = user.client
			if(c)
				c.pixel_x = 0
				c.pixel_y = 0
				if(c.saved_dynamic_view)
					c.view = c.saved_dynamic_view
					c.saved_dynamic_view = null
				else
					c.refit_dynamic_view()
				c.update_skybox(TRUE)
				if(c.mob)
					c.mob.reload_fullscreen()
					c.mob.apply_gameui_border()
				if(istype(user, /mob/living/carbon/human))
					var/mob/living/carbon/human/H = user
					if(H.eye_view_cancel_button)
						c.screen -= H.eye_view_cancel_button
			if(user.machine == src)
				user.unset_machine()
		user = null
	QDEL_NULL(pick_eye)
	. = ..()

/// Blocking picker -- spawns the anchor, polls until a valid pick, a
/// cancellation, or a timeout, then tears the anchor down and returns the
/// chosen turf (or null, having already reported why). extra_checks is
/// invoked every poll tick so a caller can abort early with its own
/// reason (e.g. the target ship got stashed while the mob was still
/// browsing) -- same shape as do_after_detailed()'s own extra_checks.
/proc/_drydock_pick_destination_turf(mob/living/L, target_z, turf/anchor_turf, datum/callback/extra_checks, timeout = DRYDOCK_PICK_TIMEOUT)
	if(!anchor_turf)
		return null
	var/obj/effect/drydock_pick_anchor/anchor = new(anchor_turf)
	anchor.begin(L, target_z)
	to_chat(L, SPAN_NOTICE("Click a turf to choose your landing point."))
	var/end_time = world.time + timeout
	var/abort_reason
	while(anchor.state == DRYDOCK_PICK_STATE_WAITING)
		if(world.time >= end_time)
			abort_reason = "You took too long to choose."
			break
		if(QDELETED(L) || !L.client)
			break
		if(L.stat == DEAD)
			abort_reason = "You can't pick a landing point while dead."
			break
		if(L.buckled_to)
			abort_reason = "You can't pick a landing point while buckled."
			break
		if(extra_checks && !extra_checks.Invoke())
			break
		stoplag(1)
	var/turf/result
	if(anchor.state == DRYDOCK_PICK_STATE_CONFIRMED)
		result = anchor.picked_turf
	else if(abort_reason)
		to_chat(L, SPAN_WARNING(abort_reason))
	qdel(anchor)
	return result

/// The shared four-case access rule -- see the file header above.
/proc/_drydock_pick_access_mode(mob/living/L, target_z)
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed || DS.z != target_z)
			continue
		if(_drydock_full_access_check(L, target_z))
			return DRYDOCK_PICK_MODE_OPEN
		return DRYDOCK_PICK_MODE_EXTERIOR_ONLY
	// Any other ship-type marker (non-drydock -- NPC/faction ships, the
	// Horizon, etc.) has no ownership concept to open up -- always exterior.
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[target_z]"]
	if(istype(marker, /obj/effect/overmap/visitable/ship))
		return DRYDOCK_PICK_MODE_EXTERIOR_ONLY
	// Explicit .powered check rather than trusting GLOB.faction_beacon_by_z
	// presence alone -- a beacon comment states an unpowered beacon can
	// never hold a Z claim, but this verifies it directly instead of
	// relying on that invariant silently.
	var/obj/structure/machinery/faction_beacon/B = GLOB.faction_beacon_by_z["[target_z]"]
	if(istype(B) && B.powered)
		// Same ownership parity as the drydock-ship case above -- a member of
		// the claiming faction gets full interior access to their own site,
		// not just the exterior-only default a stranger gets.
		var/obj/item/card/id/ID = L.GetIdCard()
		var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
#ifdef FACTION_ALLIANCES
		if(B.faction_uid && own_faction && (B.faction_uid == own_faction || factions_are_allied(own_faction, B.faction_uid)))
			return DRYDOCK_PICK_MODE_OPEN
#else
		if(B.faction_uid && own_faction && B.faction_uid == own_faction)
			return DRYDOCK_PICK_MODE_OPEN
#endif //FACTION_ALLIANCES
		// Admin-toggled raiding kill-switch (GLOB.faction_raiding_enabled,
		// persistence_factions.dm) -- the Hub's own beacon subtype is always
		// exempt (istype check below), and a faction can opt its own
		// territory out of the lockout entirely via public_territory
		// (faction_beacon.dm's "toggle_public_territory" TGUI action).
		if(!GLOB.faction_raiding_enabled && !B.public_territory && !istype(B, /obj/structure/machinery/faction_beacon/hub))
			return DRYDOCK_PICK_MODE_BLOCKED
		return DRYDOCK_PICK_MODE_EXTERIOR_ONLY
	// piracy_beacon never claims territory or touches zone security the way
	// a faction beacon does (piracy_beacon.dm) -- it's tracked in its own
	// flat GLOB.piracy_beacons list, not GLOB.faction_beacon_by_z, so it
	// needs its own explicit check here or a pirate-held Z is wrongly
	// treated as open. piracy_beacon_active_on_z() (not _present_on_z())
	// already requires .powered (via is_operational()), so an unpowered
	// pirate beacon correctly leaves the Z open.
	if(piracy_beacon_active_on_z(target_z))
		return DRYDOCK_PICK_MODE_EXTERIOR_ONLY
	return DRYDOCK_PICK_MODE_OPEN

/// "Exterior" turfs -- true vacuum, or (since solid-ground away
/// sites/exoplanets have no vacuum turfs at all) open exoplanet surface, as
/// opposed to a real mapped indoor floor tile.
/proc/_drydock_is_exterior_turf(turf/T)
	return istype(T, /turf/space) || istype(T, /turf/simulated/floor/exoplanet)

/// Combines the density + access-mode checks -- re-evaluated live on every
/// click and again in the post-channel recheck (never cached), so a beacon
/// claimed/lifted mid-pick is honored immediately.
/proc/_drydock_pick_turf_valid(turf/T, mob/living/L, target_z)
	if(!istype(T) || T.density)
		return FALSE
	var/mode = _drydock_pick_access_mode(L, target_z)
	if(mode == DRYDOCK_PICK_MODE_BLOCKED)
		return FALSE
	if(mode == DRYDOCK_PICK_MODE_EXTERIOR_ONLY && !_drydock_is_exterior_turf(T))
		return FALSE
	return TRUE

/// TRUE if L should be refused entry to target_z outright because faction
/// raiding is currently disabled, the Z is claimed by an ordinary (non-Hub)
/// powered faction beacon, and L isn't a member of that faction. Checked up
/// front where practical (mirrors personal_travel.dm's hardsuit pre-check)
/// so a blocked player gets an immediate message instead of clicking
/// through an eye-view pick that can never succeed -- _drydock_pick_access_mode()
/// above is still the authoritative check, re-verified on every click.
/// Thin wrapper around _faction_raid_blocked_for() (shuttles/docking_beacon.dm
/// consumes that shared proc directly for a docking ship's own faction_uid,
/// which has no mob/ID card to resolve one from) -- resolves L's own faction
/// from their ID card, same as before this was split out.
/proc/_drydock_raid_blocked(mob/living/L, target_z)
	var/obj/item/card/id/ID = L.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	return _faction_raid_blocked_for(target_z, own_faction)

/// Shared core of the raiding gate: TRUE if acting_faction_uid should be
/// refused entry to target_z because faction raiding is currently disabled,
/// the Z is claimed by an ordinary (non-Hub) powered, non-public-territory
/// faction beacon, and acting_faction_uid isn't a member of (or allied with,
/// under FACTION_ALLIANCES) that faction. acting_faction_uid may be null
/// (an unaffiliated player, or a personally-owned drydock ship) -- always
/// blocked in that case, same as before this was split out.
/proc/_faction_raid_blocked_for(target_z, acting_faction_uid)
	if(GLOB.faction_raiding_enabled)
		return FALSE
	if(zone_security_get(target_z) == ZONE_HIGHSEC)
		return FALSE
	var/obj/structure/machinery/faction_beacon/B = GLOB.faction_beacon_by_z["[target_z]"]
	if(!istype(B) || !B.powered || B.public_territory || istype(B, /obj/structure/machinery/faction_beacon/hub))
		return FALSE
#ifdef FACTION_ALLIANCES
	return !(B.faction_uid && acting_faction_uid && (B.faction_uid == acting_faction_uid || factions_are_allied(acting_faction_uid, B.faction_uid)))
#else
	return !(B.faction_uid && acting_faction_uid && B.faction_uid == acting_faction_uid)
#endif //FACTION_ALLIANCES

/// Plays the raiding-prohibited announcer cue to L, gated by ASFX_ANNOUNCER
/// like every other announcer line -- call alongside _drydock_raid_blocked()'s
/// "you cannot enter" chat message so a blocked player also gets an audio cue.
/// Local to L only, not a broadcast.
/proc/play_raid_blocked_sound(mob/living/L)
	if(!isdeaf(L) && (L.client?.prefs.sfx_toggles & ASFX_ANNOUNCER))
		sound_to(L, 'sound/AI/announcements/raiding_prohibited.ogg')

/// Delivery with full portal VFX (spark + portal sprite + sound at BOTH
/// ends) -- a direct adaptation of personal_travel.dm's _execute_travel().
/// Used only by the new "choose landing spot" pick flows; the existing
/// instant-delivery paths keep calling persistence_telepad_deliver() (which
/// only sparks the destination, no portal object, no origin effect)
/// exactly as before.
/proc/_drydock_deliver_with_portal(mob/living/L, turf/destination)
	var/turf/origin = get_turf(L)
	var/atom/movable/pulled = L.pulling
	if(origin)
		new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
		playsound(origin, 'sound/effects/phasein.ogg', 30, 1)
	new /obj/effect/portal/decorative/fading(destination, null, null, 5 SECONDS, 0)
	spark(destination, 3, GLOB.alldirs)
	L.forceMove(destination)
	if(pulled && !QDELETED(pulled))
		pulled.forceMove(destination)
	playsound(destination, 'sound/effects/phasein.ogg', 30, 1)

/// Resolves which ship L has boarding rights to nearby -- ownership/crew/
/// faction check, DS.ready, and same/adjacent overmap sector proximity,
/// with a picker if more than one candidate matches. Split out from the
/// delivery tail (_drydock_board_deliver(), below) so invite-to-board
/// (_drydock_invite_board_core()) can resolve rights against the INVITER
/// while delivering a different mob (the invited target). pad_network null
/// means public (personal ownership, any faction the mob belongs to, or
/// being listed on a ship's own crew list -- drydockAddCrew(),
/// persistence_shuttles.dm); a normalized faction uid restricts candidates
/// to that faction's ships only. Reports any refusal reason to L directly;
/// returns null on refusal.
/proc/_drydock_board_resolve_ship(mob/living/L, pad_network)
	var/obj/effect/overmap/visitable/mob_sector = _drydock_boarder_sector(L)

	var/list/candidates = list()
	var/found_not_ready = FALSE
	// Every ship L genuinely owns/has crew access to, but got excluded from
	// candidates anyway, with the SPECIFIC reason why -- shown directly to
	// the player, not just logged, so "no ships nearby" (misleading when a
	// ship the player owns actually exists) becomes an exact, actionable
	// fact instead of a mystery.
	var/list/exclusion_reasons = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed)
			continue
		if(pad_network)
			if(DS.faction_uid != pad_network)
				continue
		else if(!_drydock_full_access_check(L, DS.z))
			continue
		// Everything below this point is a ship L genuinely has access to --
		// worth naming exactly why it's excluded, not just silently skipped.
		// Still mid-load (deferred atmos settle, persistence_ship_interiors.dm)
		// -- not offered as a candidate at all yet, distinct from "no ships."
		if(!DS.ready)
			found_not_ready = TRUE
			continue
		// Ownership/faction/crew only grants VISIBILITY to board -- the ship
		// still has to actually be nearby (same or an adjacent sector, or up
		// to DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX if it got hazard-overflow-
		// placed -- shipPlaceOvermapMarker(), persistence_shuttles.dm).
		// _drydock_ship_sector(), not a bare GLOB.map_sectors["[DS.z]"] lookup
		// -- DS's own marker may currently be nested (docked, on_landing(),
		// landable.dm), which would give get_dist() a meaningless result.
		var/obj/effect/overmap/visitable/ship_sector = _drydock_ship_sector(DS)
		if(!istype(mob_sector))
			exclusion_reasons += "[DS.display_name()]: your own position has no resolvable overmap sector (z=[GET_Z(L)])."
			continue
		if(!istype(ship_sector))
			exclusion_reasons += "[DS.display_name()]: the ship's own position has no resolvable overmap sector (ship z=[DS.z])."
			continue
		var/board_dist = get_dist(mob_sector, ship_sector)
		if(board_dist > DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX)
			exclusion_reasons += "[DS.display_name()]: too far -- you're at [mob_sector] ([mob_sector.x],[mob_sector.y]), it's at [ship_sector] ([ship_sector.x],[ship_sector.y]), distance [board_dist] > max [DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX]."
			continue
		candidates += DS

	if(!length(candidates))
		if(found_not_ready)
			to_chat(L, SPAN_WARNING("Your ship is still initializing -- try again in a moment."))
		else if(length(exclusion_reasons))
			// A ship L has access to genuinely exists -- name exactly why
			// each one was excluded instead of the generic "none nearby."
			to_chat(L, SPAN_WARNING("Found [length(exclusion_reasons)] accessible ship(s), but none close enough to board:"))
			for(var/reason in exclusion_reasons)
				to_chat(L, SPAN_WARNING("- [reason]"))
		else
			to_chat(L, SPAN_WARNING(pad_network ? "[get_faction_name(pad_network)] has no drydock ships currently deployed nearby." : "You have no drydock ships currently deployed nearby."))
		return null

	if(length(candidates) == 1)
		return candidates[1]

	var/list/choices = list()
	for(var/datum/drydock_ship/DS in candidates)
		choices["[DS.template_id] #[DS.shuttle_id]"] = DS
	var/pick = tgui_input_list(L, "Board which ship?", "Drydock Boarding", choices)
	if(!pick)
		return null
	// Re-validate after the async picker -- world state may have moved on.
	if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
		return null
	return choices[pick]

/// Delivers L aboard target_ship -- buckled/dead/combat/cooldown guards,
/// console-turf-or-picked-spot choice, 15s interruptible spool-up, full
/// re-validation, then delivery. Shared tail for self-board (L asked and is
/// delivered, via _drydock_board_core() below) and invite-to-board (the
/// inviter asked via _drydock_board_resolve_ship(), but L here is the
/// invited target actually being delivered). cooldown is a per-ckey
/// world.time list owned by the caller, keyed to whichever mob is actually
/// delivered.
///
/// forced_destination (invite-to-board only, see
/// _drydock_invite_board_core()): when set, skips the console lookup and the
/// Land at Console/Choose Landing Spot prompt entirely and delivers straight
/// there -- the inviter already made the placement decision by inviting L to
/// wherever they themselves are standing. Null for self-board (default),
/// which is completely unaffected.
/proc/_drydock_board_deliver(mob/living/L, datum/drydock_ship/target, list/cooldown, turf/forced_destination)
	if(!istype(L) || !istype(target))
		return FALSE
	if(L.buckled_to)
		to_chat(L, SPAN_WARNING("You can't board while buckled."))
		return FALSE
	if(L.stat == DEAD)
		to_chat(L, SPAN_WARNING("You can't board while dead."))
		return FALSE
	if(L.in_recent_combat())
		to_chat(L, SPAN_WARNING("You're still in combat -- try again in [round((L.last_combat_time + PERSONAL_TRAVEL_COMBAT_LOCKOUT - world.time) / 10)] seconds."))
		return FALSE
	if(cooldown[L.ckey] && (world.time - cooldown[L.ckey] < 30))
		to_chat(L, SPAN_WARNING("Still recalibrating -- wait a moment."))
		return FALSE

	var/use_picker = FALSE
	var/turf/destination

	if(forced_destination)
		destination = forced_destination
	else
		destination = _drydock_console_turf(target.z)
		if(!destination)
			to_chat(L, SPAN_WARNING("Could not locate that ship's navigation console."))
			log_drydock_error("_drydock_board_deliver: no shuttle_control console found on z=[target.z] for shuttle_id=[target.shuttle_id].")
			return FALSE
		if(destination.density)
			to_chat(L, SPAN_WARNING("The boarding point is obstructed."))
			return FALSE

		// Additive choice -- "Land at Console" is today's exact instant-delivery
		// path, byte-for-byte unchanged; "Choose Landing Spot" opens the turf-
		// pick eye view (telepad_drydock_boarding.dm's picker block, above),
		// anchored at the same console turf, instead of forcing it as the
		// destination.
		use_picker = (tgui_alert(L, "Board how?", "Enter Ship", list("Land at Console", "Choose Landing Spot")) == "Choose Landing Spot")
		if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
			return FALSE
		if(use_picker)
			destination = _drydock_pick_destination_turf(L, target.z, destination)
			if(!destination)
				return FALSE

	// Right here, not after the delivery below -- this is the moment
	// boarding is actually committed and, for the picker path, exactly when
	// the eye-view camera lets go and control returns to L's own body. The
	// 15-second spool-up and portal still follow same as before; only the
	// confirmation cue moved to mark "boarding started" instead of
	// "boarding finished."
	play_announcer_sound_priority(L, 'sound/AI/announcements/boarding_the_ship.ogg')
	cooldown[L.ckey] = world.time
	L.visible_message(SPAN_NOTICE("[L] begins boarding a ship."), SPAN_NOTICE("You begin boarding the ship..."))
	// Sparks at both the boarder's own tile and the ship-side landing spot --
	// warns anyone already aboard that someone's about to portal in.
	var/list/spool_token = list(TRUE)
	_start_travel_spool_pulses(get_turf(L), destination, DRYDOCK_BOARDING_SPOOLUP, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_spool_token_valid), spool_token))
	if(!do_after(L, DRYDOCK_BOARDING_SPOOLUP, L))
		spool_token[1] = FALSE
		to_chat(L, SPAN_WARNING("Boarding interrupted."))
		return FALSE
	if(L.in_recent_combat())
		to_chat(L, SPAN_WARNING("Combat detected -- boarding aborted."))
		return FALSE

	// Full re-validation -- the spool-up gives plenty of time for the ship
	// to be stashed, its marker destroyed, or the mob to have moved out of
	// range or into a bad state.
	var/datum/drydock_ship/recheck = GLOB.drydock_ships["[target.shuttle_id]"]
	if(!recheck || recheck != target || recheck.stashed)
		to_chat(L, SPAN_WARNING("The ship is no longer available to board."))
		return FALSE
	if(!recheck.ready)
		to_chat(L, SPAN_WARNING("The ship started re-initializing -- try again in a moment."))
		return FALSE
	if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
		return FALSE
	var/obj/effect/overmap/visitable/recheck_mob_sector = _drydock_boarder_sector(L)
	var/obj/effect/overmap/visitable/recheck_ship_sector = _drydock_ship_sector(target)
	if(!istype(recheck_mob_sector) || !istype(recheck_ship_sector) || get_dist(recheck_mob_sector, recheck_ship_sector) > DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX)
		to_chat(L, SPAN_WARNING("You're no longer close enough to board."))
		return FALSE
	// Picked-spot flow re-validates the SPECIFIC chosen turf (it may have
	// become dense/inaccessible during the spool-up); the forced-destination
	// (invite) flow re-checks its own turf is still open the same way, but
	// deliberately skips _drydock_pick_turf_valid()'s exterior-only access
	// gate -- that exists to stop an outsider picking their way past a
	// claimed Z's walls, and doesn't apply to a guest a rightful crew member
	// just invited aboard their own ship; the console flow re-fetches the
	// console fresh, exactly as before.
	var/turf/final_destination
	if(use_picker)
		final_destination = destination
	else if(forced_destination)
		final_destination = forced_destination
	else
		final_destination = _drydock_console_turf(target.z)
	if(!final_destination || final_destination.density || (use_picker && !_drydock_pick_turf_valid(final_destination, L, target.z)))
		to_chat(L, SPAN_WARNING("The boarding point is no longer available."))
		return FALSE

	_drydock_deliver_with_portal(L, final_destination)
	to_chat(L, SPAN_GOOD("You board the ship."))
	log_drydock("_drydock_board_deliver: [key_name(L)] boarded shuttle_id=[target.shuttle_id].")
	return TRUE

/// Core boarding entry point, shared by the physical drydock_boarding pad
/// and the Drydock program's "Enter Ship" action -- only the trigger
/// differs, candidate/destination logic is identical either way. Fails
/// fast on buckled/dead/combat/cooldown before bothering to resolve
/// candidates (matching this proc's original, single-piece behavior);
/// _drydock_board_deliver() re-checks the same guards on its own so it
/// stays correct when called standalone for a mob nobody's pre-checked
/// (invite-to-board's target). cooldown is a per-ckey world.time list
/// owned by the caller (a pad or a program instance), so different trigger
/// points don't share a single cooldown.
/proc/_drydock_board_core(mob/living/L, pad_network, list/cooldown)
	if(!istype(L))
		return FALSE
	if(L.buckled_to)
		to_chat(L, SPAN_WARNING("You can't board while buckled."))
		return FALSE
	if(L.stat == DEAD)
		to_chat(L, SPAN_WARNING("You can't board while dead."))
		return FALSE
	if(L.in_recent_combat())
		to_chat(L, SPAN_WARNING("You're still in combat -- try again in [round((L.last_combat_time + PERSONAL_TRAVEL_COMBAT_LOCKOUT - world.time) / 10)] seconds."))
		return FALSE
	if(cooldown[L.ckey] && (world.time - cooldown[L.ckey] < 30))
		to_chat(L, SPAN_WARNING("Still recalibrating -- wait a moment."))
		return FALSE

	var/datum/drydock_ship/target = _drydock_board_resolve_ship(L, pad_network)
	if(!target)
		return FALSE
	return _drydock_board_deliver(L, target, cooldown)

/// Portal+spark visual cue at T only -- no forceMove, this just marks where
/// an invitation is being extended. A lighter cousin of
/// _drydock_deliver_with_portal() (which does the same VFX plus the actual
/// move).
/proc/_drydock_invite_vfx(turf/T)
	if(!T)
		return
	new /obj/effect/portal/decorative/fading(T, null, null, 5 SECONDS, 0)
	spark(T, 3, GLOB.alldirs)
	playsound(T, 'sound/effects/phasein.ogg', 30, 1)

/// Finds a passable, unobstructed turf adjacent to center, falling back to
/// center itself if it's non-dense, or null if nothing usable is found.
/// Mirrors first_responder_clear_turf_near() (first_responder.dm) -- that one
/// is scoped to a first_responder program instance and can't be called from
/// here, so this is a standalone copy for delivering an invited boarder next
/// to their inviter instead of always at the ship's console
/// (_drydock_invite_board_core() below).
/proc/_drydock_adjacent_open_turf(turf/center)
	if(!center)
		return null
	var/list/candidates = list()
	for(var/check_dir in GLOB.alldirs)
		var/turf/T = get_step(center, check_dir)
		if(!T || T.density)
			continue
		var/blocked = FALSE
		for(var/obj/O in T)
			if(O.density && O.anchored)
				blocked = TRUE
				break
		if(!blocked)
			candidates += T
	if(length(candidates))
		return pick(candidates)
	if(!center.density)
		return center
	return null

/// Lets an existing crew member invite a specific nearby player aboard,
/// instead of that player self-boarding -- same underlying rights/proximity
/// rule as self-board (_drydock_board_resolve_ship(), resolved against the
/// INVITER), but delivery (_drydock_board_deliver(), same 15s spool-up and
/// combat checks) applies to the TARGET once they accept. "Nearby" is
/// sector-adjacency: the target's own overmap sector must be within
/// DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX of the ship's (mirrors the existing
/// sector-proximity rule everywhere else in this system) -- this is a
/// PDA-mediated invite, not a click-to-target interaction, so the target
/// isn't expected to be standing physically next to the inviter or at any
/// console. cooldown is the same per-ckey world.time list the caller
/// already owns for self-board, keyed to whichever mob ends up delivered --
/// so an invited target's own cooldown is tracked the same way a
/// self-boarder's would be.
/proc/_drydock_invite_board_core(mob/living/inviter, list/cooldown)
	if(!istype(inviter))
		return FALSE
	var/datum/drydock_ship/target_ship = _drydock_board_resolve_ship(inviter, null)
	if(!target_ship)
		return FALSE
	// _drydock_ship_sector(), not a bare GLOB.map_sectors["[target_ship.z]"]
	// lookup -- see _drydock_board_resolve_ship()'s own identical fix above.
	// Derived once here and reused unchanged below (lines checking
	// candidate/target proximity) rather than re-deriving each time.
	var/obj/effect/overmap/visitable/ship_sector = _drydock_ship_sector(target_ship)

	// "Nearby" is sector-adjacency to the ship, same rule self-boarding uses
	// (_drydock_board_resolve_ship) -- not physical same-Z proximity to the
	// inviter. Ships/away-sites/stations each live on their own dedicated Z,
	// so a target on a different map from the inviter could never appear
	// here under the old view(1, inviter) check, even when their sector was
	// right next to the ship's on the overmap -- which is the whole point of
	// inviting someone aboard "instead of that player self-boarding".
	var/list/nearby = list()
	for(var/mob/living/candidate in GLOB.living_mob_list)
		if(candidate == inviter || candidate.stat == DEAD || !candidate.client)
			continue
		var/obj/effect/overmap/visitable/candidate_sector = _drydock_boarder_sector(candidate)
		if(!istype(candidate_sector) || !istype(ship_sector) || get_dist(candidate_sector, ship_sector) > DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX)
			continue
		nearby += candidate
	if(!length(nearby))
		to_chat(inviter, SPAN_WARNING("There's no one nearby to invite aboard."))
		return FALSE

	var/mob/living/target
	if(length(nearby) == 1)
		target = nearby[1]
	else
		var/list/choices = list()
		for(var/mob/living/candidate in nearby)
			choices["[candidate.name]"] = candidate
		var/pick = tgui_input_list(inviter, "Invite who aboard?", "Boarding Invitation", choices)
		if(!pick)
			return FALSE
		target = choices[pick]

	// Recheck sector-adjacency (candidates may have moved during the picker
	// delay above) instead of a same-Z physical distance, for the same
	// reason the gathering loop above no longer uses one.
	var/obj/effect/overmap/visitable/target_sector = _drydock_boarder_sector(target)
	if(QDELETED(inviter) || QDELETED(target) || target.stat == DEAD || !istype(target_sector) || !istype(ship_sector) || get_dist(target_sector, ship_sector) > DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX)
		to_chat(inviter, SPAN_WARNING("[target] is too far from the ship to invite aboard."))
		return FALSE

	var/ship_display_name = target_ship.display_name()
	var/turf/target_turf = get_turf(target)
	_drydock_invite_vfx(target_turf)
	var/response = tgui_alert(target, "[inviter] wants to bring you aboard [ship_display_name]. Board?", "Boarding Invitation", list("Accept", "Deny"), DRYDOCK_INVITE_TIMEOUT)

	if(QDELETED(inviter) || QDELETED(target))
		return FALSE
	if(response != "Accept")
		to_chat(inviter, SPAN_WARNING(response == "Deny" ? "[target] declined." : "[target] didn't respond in time."))
		return FALSE
	target_sector = _drydock_boarder_sector(target)
	if(target.stat == DEAD || !istype(target_sector) || get_dist(target_sector, ship_sector) > DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX)
		to_chat(inviter, SPAN_WARNING("[target] is no longer in range to board."))
		return FALSE

	var/datum/drydock_ship/recheck_ship = GLOB.drydock_ships["[target_ship.shuttle_id]"]
	if(!recheck_ship || recheck_ship != target_ship || recheck_ship.stashed || !recheck_ship.ready)
		to_chat(inviter, SPAN_WARNING("The ship is no longer available to board."))
		return FALSE

	to_chat(inviter, SPAN_NOTICE("[target] accepted -- boarding..."))
	// Deliver next to the inviter if they're still aboard the ship's own Z
	// right now -- that's the whole point of an invite, as opposed to self-
	// boarding, which always lands at the console/picker spot. Falls back to
	// the ordinary console/picker delivery (forced_destination left null) if
	// the inviter isn't actually on the ship, died, or disconnected between
	// the invite and the accept.
	var/turf/forced_destination
	if(!QDELETED(inviter) && inviter.stat != DEAD && GET_Z(inviter) == target_ship.z)
		forced_destination = _drydock_adjacent_open_turf(get_turf(inviter))
	var/boarded = _drydock_board_deliver(target, target_ship, cooldown, forced_destination)
	to_chat(inviter, boarded ? SPAN_GOOD("[target] boarded the ship.") : SPAN_WARNING("[target]'s boarding attempt failed."))
	return boarded

/// Wrapper for the physical drydock boarding pad -- reads the pad's own
/// Faction Tagger network and per-pad cooldown, delegates to the shared
/// core. Untagged/public: any ship the mob owns, personal or any faction
/// they belong to. Tagged to a faction: only that faction's own ships --
/// personal ownership doesn't apply through a faction-restricted pad,
/// same shape as corvette_boarding's own network scoping.
/proc/drydock_board_mob(mob/living/L, obj/structure/machinery/telepad_cargo/drydock_boarding/from_pad)
	if(!istype(from_pad))
		return FALSE
	var/pad_network = normalize_faction_uid(from_pad.persistent_network)
	if(pad_network == "public")
		pad_network = null
	return _drydock_board_core(L, pad_network, from_pad.last_boarded_by_ckey)

/// Finds the deployed ship's own navigation console turf -- the one piece
/// of map content every ship template is already guaranteed to have.
/// Prefers the shuttle datum's own linked shuttle_computers (populated by
/// shuttle_control/Initialize() matching shuttle_tag); falls back to any
/// shuttle_control physically on that z in case linkage ever fails.
/proc/_drydock_console_turf(z)
	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[z]"]
	var/datum/shuttle/shuttle_datum = istype(marker) ? SSshuttle.shuttles[marker.shuttle] : null
	if(istype(shuttle_datum))
		for(var/obj/structure/machinery/computer/shuttle_control/console in shuttle_datum.shuttle_computers)
			return get_turf(console)
	for(var/obj/structure/machinery/computer/shuttle_control/console in world)
		if(GET_Z(console) == z)
			return get_turf(console)
	return null

/// Finds the deployed, non-stashed drydock ship whose interior L is
/// currently standing on, or null if L isn't aboard one -- shared by the
/// core disembark proc and the Drydock program's ui_data() "am I aboard a
/// ship" check (can_disembark), so both agree on exactly the same
/// condition.
/proc/_drydock_ship_at(z)
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/candidate = GLOB.drydock_ships[sid]
		if(candidate && !candidate.stashed && candidate.z == z)
			return candidate
	return null

/// TRUE if M counts as "crew" of whichever drydock ship currently occupies
/// z -- the ship's owner or anyone on its crew_ckeys list. FALSE (fails
/// closed) if no deployed ship resolves at all. Each ship's crew list is
/// independent -- this only ever checks the ONE ship actually at z, so two
/// different ships' crews never cross. Admin bypass is the caller's own
/// responsibility (mirrors every other tag-mode gate this session), not
/// baked in here.
/proc/_drydock_crew_check(mob/M, z)
	return _drydock_crew_check_identity(M.ckey, M.real_name, z)

/// TRUE if L has full owner/faction/crew access to whichever drydock ship
/// currently occupies z -- its owner, a member of its faction, or on its
/// crew_ckeys list. FALSE (fails closed) if no deployed ship resolves at z
/// at all. The shared shape of the access rule duplicated at
/// _drydock_pick_access_mode() and _drydock_board_resolve_ship() below --
/// also reused by overmap's is_detectable() viewer exemption
/// (overmap_object.dm) so a cloaked ship stays visible to its own
/// owner/faction/crew.
/proc/_drydock_full_access_check(mob/L, z)
	var/datum/drydock_ship/DS = _drydock_ship_at(z)
	if(!DS || !L)
		return FALSE
	var/obj/item/card/id/ID = L.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	return DS.owned_by(L) || (DS.faction_uid && DS.faction_uid == own_faction) || ("[L.ckey]|[L.real_name]" in DS.crew_ckeys)

/// Ship-level counterpart to _drydock_full_access_check() for contexts with
/// no specific mob to check -- e.g. a sensor console's own shared
/// identification tick (contact_sensors.dm's process()), which runs once per
/// console, not once per viewer. TRUE if the drydock ships deployed at z1
/// and z2 are the same ship or share a (non-null) faction_uid. Reaching a
/// ship's own console already requires being crew/allowed aboard it, so
/// "this console's ship" stands in for "whoever's using it" -- a coarser
/// approximation than the mob-level check, but correct for the stated
/// requirement (crew/faction see their own/allied ships).
/proc/_drydock_ships_share_ownership(z1, z2)
	var/datum/drydock_ship/A = _drydock_ship_at(z1)
	var/datum/drydock_ship/B = _drydock_ship_at(z2)
	if(!A || !B)
		return FALSE
	if(A == B)
		return TRUE
	return A.faction_uid && A.faction_uid == B.faction_uid

/// Identity-based counterpart to _drydock_crew_check() -- for callers that
/// only have a (ckey, char_name) pair on hand, not a live mob (e.g. cryopod
/// spawn/save lookups, which run before a mob object necessarily exists).
/proc/_drydock_crew_check_identity(ckey, char_name, z)
	var/datum/drydock_ship/DS = _drydock_ship_at(z)
	if(!DS)
		return FALSE
	return (DS.owner_ckey == ckey && DS.owner_char_name == char_name) || ("[ckey]|[char_name]" in DS.crew_ckeys)

/// Core disembark delivery, shared by the mob verb below and the Drydock
/// program's "Exit Ship" action -- only the trigger differs. Step off a
/// currently-deployed drydock ship -- available from anywhere aboard (no
/// ship-side object needed, matching how boarding needs none either). Two
/// kinds of destination: wherever the ship is genuinely docked (today's
/// original behavior, instant), or any away-site/station sector within
/// DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX tiles of the ship's own overmap
/// position (lets crew portal to a nearby site without needing to actually
/// dock there first). If more than one
/// candidate exists, or the docked one is chosen, an additive choice offers
/// the turf-pick eye view alongside the original instant delivery.
/proc/_drydock_disembark_core(mob/living/L)
	if(!istype(L))
		return FALSE
	if(L.buckled_to)
		to_chat(L, SPAN_WARNING("You can't disembark while buckled."))
		return FALSE
	if(L.stat == DEAD)
		to_chat(L, SPAN_WARNING("You can't disembark while dead."))
		return FALSE
	if(L.in_recent_combat())
		to_chat(L, SPAN_WARNING("You're still in combat -- try again in [round((L.last_combat_time + PERSONAL_TRAVEL_COMBAT_LOCKOUT - world.time) / 10)] seconds."))
		return FALSE

	var/here_z = GET_Z(L)
	var/datum/drydock_ship/DS = _drydock_ship_at(here_z)
	if(!DS)
		to_chat(L, SPAN_WARNING("You're not aboard a deployed drydock ship."))
		return FALSE

	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
	var/datum/shuttle/shuttle_datum = istype(marker) ? SSshuttle.shuttles[marker.shuttle] : null

	var/list/candidate_turfs = list()
	if(shuttle_datum && marker.status == SHIP_STATUS_LANDED)
		var/turf/dock_turf = get_turf(shuttle_datum.current_location)
		if(dock_turf)
			candidate_turfs["Docked location"] = dock_turf
	else
		var/turf/here_turf = personal_travel_find_space_landing(DS.z)
		if(here_turf)
			candidate_turfs["Current position"] = here_turf
	if(istype(marker))
		var/list/seen_sectors = list()
		for(var/z_key in GLOB.map_sectors)
			var/obj/effect/overmap/visitable/nearby = GLOB.map_sectors[z_key]
			if(nearby == marker || (nearby in seen_sectors))
				continue
			if(!istype(nearby, /obj/effect/overmap/visitable/sector) && !istype(nearby, /obj/effect/overmap/visitable/ship))
				continue
			if(istype(nearby, /obj/effect/overmap/visitable/sector/temporary))
				continue
			seen_sectors += nearby
			// Adjacent sectors only -- DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX (the
			// doubled radius) is sized for "can a ship dock near this beacon,"
			// not "how far can someone walk off the ship to a neighboring
			// sector." The base radius keeps this Chebyshev distance from
			// reading as several sectors away by eye.
			if(get_dist(marker, nearby) > DRYDOCK_SHIP_PLACEMENT_RADIUS)
				continue
			if(!length(nearby.map_z))
				continue
			var/turf/site_turf = personal_travel_find_space_landing(nearby.map_z[1])
			if(site_turf)
				candidate_turfs["[nearby.name]"] = site_turf

	if(!length(candidate_turfs))
		to_chat(L, SPAN_WARNING("The ship must be docked, or near an away site, before you can disembark."))
		return FALSE

	var/turf/anchor_turf
	if(length(candidate_turfs) == 1)
		anchor_turf = candidate_turfs[candidate_turfs[1]]
	else
		var/pick = tgui_input_list(L, "Disembark to where?", "Disembark", candidate_turfs)
		if(!pick)
			return FALSE
		anchor_turf = candidate_turfs[pick]
		if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
			return FALSE

	var/target_z = GET_Z(anchor_turf)
	// Checked up front, before the instant "Land at Dock" branch below can
	// bypass the eye-view picker (and its _drydock_pick_turf_valid() check)
	// entirely -- without this, a ship already docked at a foreign faction's
	// Z could let its passengers step off with zero access check at all.
	if(_drydock_raid_blocked(L, target_z))
		to_chat(L, SPAN_WARNING("Faction raiding is currently disabled -- you cannot disembark into that territory."))
		play_raid_blocked_sound(L)
		return FALSE
	if(is_centcom_level(target_z) && !can_access_hub_depot(L))
		to_chat(L, SPAN_WARNING("That sector is restricted to Hub personnel."))
		return FALSE
	var/is_dock_target = (shuttle_datum && marker.status == SHIP_STATUS_LANDED && target_z == GET_Z(shuttle_datum.current_location))
	var/is_hub_target = (zone_security_get(target_z) == ZONE_HIGHSEC)

	var/turf/destination
	var/use_picker = TRUE

	if(is_hub_target)
		// Highsec (the Hub) is never eye-view-pickable, even exterior-only --
		// "people should enter the hub, just not anywhere." Route straight to
		// the Hub's own dedicated travel telepad instead, the same fixed
		// arrival point Personal Travel's "Return to Hub" already uses. Still
		// goes through the same spool-up/combat-recheck/portal tail below --
		// only the eye-view CLICKING step is skipped, not the safety window.
		use_picker = FALSE
		// Match the SPECIFIC away site the player actually picked (target_z)
		// -- with more than one highsec/hub-tier site in existence, a plain
		// "first one found in world" grab (the original shape here) ignores
		// the player's own selection entirely and can send them to a
		// completely different site's hub pad instead of the one they
		// picked. Falls back to any hub pad at all only if this specific
		// site genuinely doesn't have one of its own.
		for(var/obj/structure/machinery/telepad_cargo/travel/hub/H in world)
			if(QDELETED(H))
				continue
			if(GET_Z(H) == target_z)
				destination = get_turf(H)
				break
		if(!destination)
			for(var/obj/structure/machinery/telepad_cargo/travel/hub/H in world)
				if(QDELETED(H))
					continue
				destination = get_turf(H)
				break
		if(!destination)
			to_chat(L, SPAN_WARNING("No Hub travel pad could be found."))
			return FALSE
	else if(is_dock_target)
		// Only the actual dock target has an "instant" option -- a nearby
		// away-site pick never had a fixed landmark turf to begin with, so it
		// always goes straight to the eye view.
		use_picker = (tgui_alert(L, "Disembark how?", "Disembark", list("Land at Dock", "Choose Landing Spot")) == "Choose Landing Spot")
		if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
			return FALSE
		if(!use_picker)
			destination = get_turf(shuttle_datum.current_location)
			if(!destination || destination.density)
				to_chat(L, SPAN_WARNING("The disembark point is obstructed."))
				return FALSE
			// _drydock_deliver_with_portal() forceMoves L.pulling itself, so no
			// need to build a deliver_items list -- also brings this branch up
			// to the same spark+portal-at-both-ends VFX the picker branch below
			// already has, instead of persistence_telepad_deliver()'s
			// destination-only spark.
			_drydock_deliver_with_portal(L, destination)
			to_chat(L, SPAN_GOOD("You disembark the ship."))
			play_announcer_sound_priority(L, 'sound/AI/announcements/exiting_ship.ogg')
			log_drydock("_drydock_disembark_core: [key_name(L)] disembarked shuttle_id=[DS.shuttle_id] at its docked beacon.")
			return TRUE

	if(use_picker)
		destination = _drydock_pick_destination_turf(L, target_z, anchor_turf)
		if(!destination)
			return FALSE

	// Right here, not after the delivery below -- see the matching comment
	// in _drydock_board_deliver(). For the picker path this is exactly when
	// the eye-view camera releases back to L; for the hub route there's no
	// eye view step, but the destination is equally committed at this point.
	play_announcer_sound_priority(L, 'sound/AI/announcements/exiting_ship.ogg')

	// Sparks at both the disembarking player's own tile and the landing
	// spot -- warns anyone already there that someone's about to portal in.
	var/list/spool_token = list(TRUE)
	_start_travel_spool_pulses(get_turf(L), destination, DRYDOCK_DISEMBARK_SPOOLUP, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_spool_token_valid), spool_token))
	if(!do_after(L, DRYDOCK_DISEMBARK_SPOOLUP, L))
		spool_token[1] = FALSE
		to_chat(L, SPAN_WARNING("Disembarking interrupted."))
		return FALSE
	if(L.in_recent_combat())
		to_chat(L, SPAN_WARNING("Combat detected -- disembarking aborted."))
		return FALSE
	if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
		return FALSE
	// _drydock_pick_turf_valid() (the exterior-only access check) only
	// applies to an actual player-clicked turf -- the Hub telepad is a
	// sanctioned fixed point, exempt from that check, but still needs the
	// basic obstruction check.
	if(destination.density || (use_picker && !_drydock_pick_turf_valid(destination, L, target_z)))
		to_chat(L, SPAN_WARNING("The landing point is no longer available."))
		return FALSE
	// A pick onto the actual dock target can lose its precondition (the
	// ship taking off mid-pick/channel) -- a nearby-away-site pick, or a
	// hub-route delivery, never had one to lose.
	if(is_dock_target)
		var/datum/drydock_ship/recheck_ds = GLOB.drydock_ships["[DS.shuttle_id]"]
		var/obj/effect/overmap/visitable/ship/landable/recheck_marker = istype(recheck_ds) ? GLOB.map_sectors["[recheck_ds.z]"] : null
		var/datum/shuttle/recheck_shuttle = istype(recheck_marker) ? SSshuttle.shuttles[recheck_marker.shuttle] : null
		if(!recheck_ds || recheck_ds.stashed || !recheck_shuttle || recheck_marker.status != SHIP_STATUS_LANDED)
			to_chat(L, SPAN_WARNING("The ship is no longer docked there."))
			return FALSE

	_drydock_deliver_with_portal(L, destination)
	to_chat(L, SPAN_GOOD("You disembark the ship."))
	log_drydock("_drydock_disembark_core: [key_name(L)] disembarked shuttle_id=[DS.shuttle_id][is_hub_target ? " via the Hub telepad" : " choosing a landing spot"].")
	return TRUE

/mob/living/verb/disembark_drydock_ship()
	set name = "Disembark Drydock Ship"
	set category = "IC"
	set desc = "Step off a docked drydock ship, back onto its beacon."

	_drydock_disembark_core(src)
