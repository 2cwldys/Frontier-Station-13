/*
 * Travel Pad
 *
 * A player-buildable telepad_cargo subtype that links to any other travel pad
 * sharing its access code, letting a player step directly between them --
 * "beam me to my paired pad, wherever it is," reusing the exact same flat
 * world-search-by-shared-key model persistence_find_cargo_telepad() already
 * uses for cargo delivery (persistence_cryo.dm), just matched on a
 * player-set link_code instead of persistent_network, and delivering a
 * living mob instead of items.
 *
 * Deliberately independent of faction membership -- any player can build and
 * link one, no faction tagger/officer rank involved, unlike every other
 * telepad_cargo subtype in this codebase.
 */

/// One spark+sound pulse at each of origin/destination (either may be null to
/// skip -- e.g. a system that only wants a destination-side warning). Shared
/// by every "channel for N seconds, then arrive somewhere" mechanic
/// (personal_travel.dm, drydock board/disembark, pod warp) so a bystander at
/// the destination gets the same "something's about to portal in" warning the
/// traveler's own origin tile already gave. still_valid is a CALLBACK
/// returning FALSE once the travel this pulse belongs to has been aborted or
/// has already completed -- callers must flip whatever it checks on every one
/// of their own abort paths, or a pulse scheduled before the abort will still
/// fire after the fact.
/proc/_travel_spool_pulse(turf/origin, turf/destination, datum/callback/still_valid)
	if(still_valid && !still_valid.Invoke())
		return
	if(origin)
		spark(origin, 2, GLOB.alldirs)
		playsound(origin, 'sound/effects/sparks4.ogg', 20, 1)
	if(destination)
		spark(destination, 2, GLOB.alldirs)
		playsound(destination, 'sound/effects/sparks4.ogg', 20, 1)

/// Fires _travel_spool_pulse() immediately, then every 5 seconds until
/// duration -- personal_travel.dm's original 15s/3-pulse cadence (t=0/5/10),
/// generalized to any duration so a 3-second channel (pod warp) still gets
/// its one t=0 pulse without extra repeats.
/proc/_start_travel_spool_pulses(turf/origin, turf/destination, duration, datum/callback/still_valid)
	_travel_spool_pulse(origin, destination, still_valid)
	var/t = 5 SECONDS
	while(t < duration)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_travel_spool_pulse), origin, destination, still_valid), t)
		t += 5 SECONDS

/// Generic still_valid callback target for callers with no existing sequence
/// var of their own (drydock board/disembark, pod warp) -- token is a
/// one-element list acting as a mutable box, e.g. `list(TRUE)`; set
/// `token[1] = FALSE` on whatever abort path ends the spool-up early.
/proc/_spool_token_valid(list/token)
	return token && token[1]

/obj/structure/machinery/telepad_cargo/travel
	name = "travel pad"
	desc = "A tuned telepad that links to any other travel pad sharing its access code, letting you step directly between them."
	color = "#44ff88"
	accepts_cargo = FALSE
	component_types = list(
		/obj/item/circuitboard/travel_pad,
		/obj/item/bluespace_crystal/artificial,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/console_screen,
		/obj/item/stack/cable_coil = 2
	)

	/// Player-set string; any pad sharing this exact (normalized) code is a
	/// valid destination. Empty = inert -- can't travel from or to it.
	var/link_code = ""
	/// Static/shared across every pad instance -- matches drydock_boarding's
	/// and corvette_boarding's own last_boarded_by_ckey convention exactly
	/// (a single global spam-guard, not per-pad).
	var/static/list/last_used_by_ckey = list()

/obj/structure/machinery/telepad_cargo/travel/Initialize(mapload, ...)
	. = ..()
	verbs -= /obj/structure/machinery/telepad_cargo/verb/configure_supply_network

/obj/structure/machinery/telepad_cargo/travel/attack_hand(mob/user)
	if(..())
		return TRUE
	ui_interact(user)
	return TRUE

/obj/structure/machinery/telepad_cargo/travel/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TravelPad", "Travel Pad")
		ui.open()

/obj/structure/machinery/telepad_cargo/travel/ui_data(mob/user)
	var/list/data = list()
	data["link_code"] = link_code

	data["linked_pads"] = list()
	for(var/obj/structure/machinery/telepad_cargo/travel/pad in _linked_pads())
		data["linked_pads"] += list(list(
			"ref" = "\ref[pad]",
			"name" = pad.name,
			"location" = "([pad.x],[pad.y],[pad.z])"
		))

	var/cooldown_end = last_used_by_ckey[user.ckey] ? (last_used_by_ckey[user.ckey] + 30) : 0
	data["can_travel"] = world.time >= cooldown_end
	data["cooldown"] = max(0, round((cooldown_end - world.time) / 10))
	return data

/obj/structure/machinery/telepad_cargo/travel/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("set_code")
			// Open to any player, no rights/faction gate -- this is a
			// personal/small-group travel network, not administrative
			// infrastructure like the faction beacon or the other
			// telepad_cargo subtypes.
			var/new_code = tgui_input_text(user, "Set this pad's access code (any pad sharing this code becomes a valid destination):", "Travel Pad", link_code, max_length = 32)
			if(isnull(new_code))
				return TRUE
			// normalize_faction_uid() is a plain lowercase/underscore string
			// canonicalizer despite the name -- no faction lookup involved
			// (persistence_factions.dm:134-137) -- reused here purely for
			// the case/whitespace-insensitive matching it already gives
			// every other network-code field in this codebase.
			link_code = normalize_faction_uid(new_code)
			// Belt-and-suspenders alongside the automatic registration a
			// frame-built machine already gets from
			// /obj/structure/machinery/Initialize() itself --
			// objectsRegisterTrack() is documented safe to call more than
			// once, and this covers any spawn path that ISN'T frame-
			// construction (e.g. an admin-spawned instance).
			if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
				SSpersistence.objectsRegisterTrack(src)
			to_chat(user, link_code ? SPAN_NOTICE("Travel pad code set to '[link_code]'.") : SPAN_NOTICE("Travel pad code cleared -- this pad is now inert."))
			. = TRUE
		if("travel")
			if(isliving(user))
				_travel(user, params["target"])
			. = TRUE
		if("send_cargo")
			_send_cargo(user, params["target"])
			. = TRUE

/// Every OTHER travel pad sharing this pad's link_code -- empty list if
/// unlinked (no code set) or no matches. Flat world-search, same shape as
/// persistence_find_cargo_telepad() (persistence_cryo.dm:628-647), just
/// matched on link_code instead of persistent_network, and returning every
/// match (not just one) since more than one destination can share a code.
/obj/structure/machinery/telepad_cargo/travel/proc/_linked_pads()
	. = list()
	if(!link_code)
		return
	for(var/obj/structure/machinery/telepad_cargo/travel/pad in world)
		if(pad == src)
			continue
		if(!pad.z)
			continue
		if(pad.link_code == link_code)
			. += pad

/// Cooldown/delivery shape directly mirrors _drydock_board_core()
/// (telepad_drydock_boarding.dm) -- same buckled/dead/cooldown checks, same
/// persistence_telepad_deliver() + destination.density obstruction guard.
/// target_ref selects a specific pad from the TGUI's own list (each row has
/// its own Travel button) -- falls back to auto-picking the only candidate
/// if there's just one and no ref was given.
/obj/structure/machinery/telepad_cargo/travel/proc/_travel(mob/living/L, target_ref)
	if(!istype(L))
		return FALSE
	if(!link_code)
		to_chat(L, SPAN_WARNING("This pad has no access code set."))
		return FALSE
	if(L.buckled_to)
		to_chat(L, SPAN_WARNING("You can't travel while buckled."))
		return FALSE
	if(L.stat == DEAD)
		to_chat(L, SPAN_WARNING("You can't travel while dead."))
		return FALSE
	if(last_used_by_ckey[L.ckey] && (world.time - last_used_by_ckey[L.ckey] < 30))
		to_chat(L, SPAN_WARNING("The pad is still recalibrating -- wait a moment."))
		return FALSE

	var/list/candidates = _linked_pads()
	if(!length(candidates))
		to_chat(L, SPAN_WARNING("No other pad shares this access code."))
		return FALSE

	var/obj/structure/machinery/telepad_cargo/travel/target
	if(target_ref)
		target = locate(target_ref) in candidates
		if(!target)
			to_chat(L, SPAN_WARNING("That pad is no longer available."))
			return FALSE
	else if(length(candidates) == 1)
		target = candidates[1]
	else
		to_chat(L, SPAN_WARNING("Select a destination pad first."))
		return FALSE

	if(is_centcom_level(target.z) && !can_access_hub_depot(L))
		to_chat(L, SPAN_WARNING("That pad's destination is restricted to Hub personnel."))
		return FALSE

	var/turf/destination = get_turf(target)
	if(!destination || destination.density)
		to_chat(L, SPAN_WARNING("The destination pad is obstructed."))
		return FALSE

	// Cosmetic-only portal + spark burst at both ends, matching First
	// Responder's own jump effect (first_responder.dm's first_responder_jump())
	// -- null target/creator means this never actually teleports anything
	// itself, the real move is still the forceMove() inside
	// persistence_telepad_deliver() below.
	var/turf/origin = get_turf(L)
	if(origin)
		new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
	new /obj/effect/portal/decorative/fading(destination, null, null, 5 SECONDS, 0)
	spark(destination, 3, GLOB.alldirs)

	last_used_by_ckey[L.ckey] = world.time
	var/list/payload = list(L)
	if(L.pulling && !QDELETED(L.pulling))
		payload += L.pulling
	persistence_telepad_deliver(payload, destination)
	to_chat(L, SPAN_GOOD("You step through the pad."))
	return TRUE

/// Standalone cargo transfer -- moves whatever's sitting on THIS pad's own
/// tile (a crate, dropped items) to a linked pad without requiring anyone to
/// travel themselves. Living mobs are deliberately excluded here -- a
/// bystander shouldn't get scooped up by someone else sending cargo; mobs
/// only travel via _travel() above (and now bring along whatever they're
/// personally pulling, same as Personal Travel).
/obj/structure/machinery/telepad_cargo/travel/proc/_send_cargo(mob/user, target_ref)
	if(!link_code)
		to_chat(user, SPAN_WARNING("This pad has no access code set."))
		return FALSE

	var/list/candidates = _linked_pads()
	if(!length(candidates))
		to_chat(user, SPAN_WARNING("No other pad shares this access code."))
		return FALSE

	var/obj/structure/machinery/telepad_cargo/travel/target
	if(target_ref)
		target = locate(target_ref) in candidates
		if(!target)
			to_chat(user, SPAN_WARNING("That pad is no longer available."))
			return FALSE
	else if(length(candidates) == 1)
		target = candidates[1]
	else
		to_chat(user, SPAN_WARNING("Select a destination pad first."))
		return FALSE

	var/turf/destination = get_turf(target)
	if(!destination || destination.density)
		to_chat(user, SPAN_WARNING("The destination pad is obstructed."))
		return FALSE

	var/list/payload = list()
	for(var/atom/movable/AM in get_turf(src))
		if(AM == src || QDELETED(AM) || AM.anchored || isliving(AM))
			continue
		payload += AM
	if(!length(payload))
		to_chat(user, SPAN_WARNING("There's nothing on the pad to send."))
		return FALSE

	if(last_used_by_ckey[user.ckey] && (world.time - last_used_by_ckey[user.ckey] < 30))
		to_chat(user, SPAN_WARNING("The pad is still recalibrating -- wait a moment."))
		return FALSE

	var/turf/origin = get_turf(src)
	new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
	spark(origin, 3, GLOB.alldirs)
	new /obj/effect/portal/decorative/fading(destination, null, null, 5 SECONDS, 0)
	spark(destination, 3, GLOB.alldirs)

	last_used_by_ckey[user.ckey] = world.time
	persistence_telepad_deliver(payload, destination)
	to_chat(user, SPAN_GOOD("The pad hums and sends its contents through to the linked pad."))
	return TRUE

// Persistence -- both paths, matching the cryopod template
// (persistence_cryo.dm:386+) telepad_cargo's own base persistence
// (telepad.dm) now also follows:
/obj/structure/machinery/telepad_cargo/travel/worldstate_get_content()
	var/list/content = ..()
	if(!content)
		content = list()
	content["link_code"] = link_code
	return content

/obj/structure/machinery/telepad_cargo/travel/worldstate_apply_content(list/content)
	..()
	if(!isnull(content["link_code"]))
		link_code = content["link_code"]

/obj/structure/machinery/telepad_cargo/travel/persistent_objects_get_content()
	var/list/content = ..()
	content["link_code"] = link_code
	return content

/obj/structure/machinery/telepad_cargo/travel/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && !isnull(content["link_code"]))
		link_code = content["link_code"]

/*
 * Hub Travel Pad -- a single, admin-placed instance marking the Hub's own
 * arrival point. Personal Travel's Return to Hub action
 * (personal_travel.dm) locates this by type directly, bypassing the normal
 * link_code matching every other travel pad uses -- no code needs to be set
 * for Return to Hub to work. Still a full travel pad otherwise (inherits
 * attackby/repair/persistence from the base machine), so it can also be
 * given a link_code if admins want it to additionally participate in the
 * normal player-built pad network.
 */
/obj/structure/machinery/telepad_cargo/travel/hub
	name = "hub travel pad"
	desc = "A permanently-installed travel pad marking Hub territory. Personal Travel's Return to Hub delivers here directly."
	color = "#6699ff" // matches the hub faction beacon's own blue tint
