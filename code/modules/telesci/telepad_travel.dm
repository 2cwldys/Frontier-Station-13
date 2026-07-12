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
		new /obj/effect/portal(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
	new /obj/effect/portal(destination, null, null, 5 SECONDS, 0)
	spark(destination, 3, GLOB.alldirs)

	last_used_by_ckey[L.ckey] = world.time
	persistence_telepad_deliver(list(L), destination)
	to_chat(L, SPAN_GOOD("You step through the pad."))
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
