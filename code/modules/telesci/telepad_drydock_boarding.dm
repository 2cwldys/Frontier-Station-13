/*
 * Drydock Boarding Pad
 *
 * A retrieved drydock ship materializes on its own dedicated Z with no
 * walkable connection to anywhere -- Retrieve places its overmap marker
 * near a beacon's sector, it doesn't dock there. This pad is the
 * station-side way on: deliver a player to the target ship's own
 * navigation console (shuttle_control), not a dedicated ship-side pad --
 * every ship template already MUST place a console for the ship to be
 * flyable at all, so this needs zero extra map content in any current or
 * future ship template. Unlike corvette boarding (telepad_corvette_boarding.dm,
 * always faction-owned, one deployed at a time, matched by a pad manually
 * placed in that hull's own .dmm), a drydock ship can be personally owned
 * and more than one can be deployed at once, so there's no single "the"
 * ship to route to -- offers a picker when there's more than one
 * candidate (same tgui_input_list pattern the First Responder telepad
 * picker uses).
 *
 * Getting back off is a mob verb (disembark_drydock_ship(), below), not a
 * second pad -- same reasoning: no ship-side object to place. Only works
 * while the ship is genuinely docked at a beacon (you can't step off
 * mid-flight).
 *
 * Faction tagger-compatible, inherited for free from the base
 * telepad_cargo hooks -- untagged/public (the default) offers every ship
 * the boarding mob owns, personal or any faction; tagging it to a faction
 * restricts that specific pad to that faction's own ships only (personal
 * ships don't board through a faction-tagged pad, same shape as
 * corvette_boarding's own network scoping).
 */
/obj/structure/machinery/telepad_cargo/drydock_boarding
	name = "drydock boarding pad"
	desc = "A tuned telepad that boards you onto one of your currently deployed drydock ships, at its navigation console. Untagged, it's open to any ship you own; tag it with a faction tagger to restrict it to that faction's ships only."
	color = "#44aaff"
	accepts_cargo = FALSE

	/// Per-ckey flood/spam cooldown, mirrors corvette_boarding's own idiom.
	var/static/list/last_boarded_by_ckey = list()

/obj/structure/machinery/telepad_cargo/drydock_boarding/Initialize()
	. = ..()
	verbs -= /obj/structure/machinery/telepad_cargo/verb/configure_supply_network

/obj/structure/machinery/telepad_cargo/drydock_boarding/attack_hand(mob/user)
	if(..())
		return TRUE
	drydock_board_mob(user, src)
	return TRUE

/// Core boarding delivery, shared by the physical drydock_boarding pad and
/// the Drydock program's "Enter Ship" action -- only the trigger differs,
/// candidate/destination logic is identical either way. pad_network null
/// means public (personal ownership + any faction the mob belongs to); a
/// normalized faction uid restricts candidates to that faction's ships
/// only. cooldown is a per-ckey world.time list owned by the caller (a
/// pad or a program instance), so different trigger points don't share a
/// single cooldown.
/proc/_drydock_board_core(mob/living/L, pad_network, list/cooldown)
	if(!istype(L))
		return FALSE
	if(L.buckled_to)
		to_chat(L, SPAN_WARNING("You can't board while buckled."))
		return FALSE
	if(L.stat == DEAD)
		to_chat(L, SPAN_WARNING("You can't board while dead."))
		return FALSE
	if(cooldown[L.ckey] && (world.time - cooldown[L.ckey] < 30))
		to_chat(L, SPAN_WARNING("Still recalibrating -- wait a moment."))
		return FALSE

	var/list/candidates = list()
	var/obj/item/card/id/ID = L.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed)
			continue
		if(pad_network)
			if(DS.faction_uid == pad_network)
				candidates += DS
			continue
		if((DS.owner_ckey && DS.owner_ckey == L.ckey) || (DS.faction_uid && DS.faction_uid == own_faction))
			candidates += DS

	if(!length(candidates))
		to_chat(L, SPAN_WARNING(pad_network ? "[get_faction_name(pad_network)] has no drydock ships currently deployed." : "You have no drydock ships currently deployed."))
		return FALSE

	var/datum/drydock_ship/target
	if(length(candidates) == 1)
		target = candidates[1]
	else
		var/list/choices = list()
		for(var/datum/drydock_ship/DS in candidates)
			choices["[DS.template_id] #[DS.shuttle_id]"] = DS
		var/pick = tgui_input_list(L, "Board which ship?", "Drydock Boarding", choices)
		if(!pick)
			return FALSE
		target = choices[pick]
		// Re-validate after the async picker -- world state may have moved on.
		if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
			return FALSE

	var/turf/destination = _drydock_console_turf(target.z)
	if(!destination)
		to_chat(L, SPAN_WARNING("Could not locate that ship's navigation console."))
		log_drydock_error("_drydock_board_core: no shuttle_control console found on z=[target.z] for shuttle_id=[target.shuttle_id].")
		return FALSE
	if(destination.density)
		to_chat(L, SPAN_WARNING("The boarding point is obstructed."))
		return FALSE

	cooldown[L.ckey] = world.time
	persistence_telepad_deliver(list(L), destination)
	to_chat(L, SPAN_GOOD("You board the ship."))
	log_drydock("_drydock_board_core: [key_name(L)] boarded shuttle_id=[target.shuttle_id].")
	return TRUE

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

/// Step off a currently-deployed, docked drydock ship -- available from
/// anywhere aboard (no ship-side object needed, matching how boarding
/// needs none either), refused if the ship isn't genuinely docked at a
/// beacon (you can't step off mid-flight).
/mob/living/verb/disembark_drydock_ship()
	set name = "Disembark Drydock Ship"
	set category = "IC"
	set desc = "Step off a docked drydock ship, back onto its beacon."

	var/here_z = GET_Z(src)
	var/datum/drydock_ship/DS
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/candidate = GLOB.drydock_ships[sid]
		if(candidate && !candidate.stashed && candidate.z == here_z)
			DS = candidate
			break
	if(!DS)
		to_chat(src, SPAN_WARNING("You're not aboard a deployed drydock ship."))
		return

	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
	var/datum/shuttle/shuttle_datum = istype(marker) ? SSshuttle.shuttles[marker.shuttle] : null
	if(!shuttle_datum || !istype(shuttle_datum.current_location, /obj/effect/shuttle_landmark/player_dock))
		to_chat(src, SPAN_WARNING("The ship must be docked at a beacon before you can disembark."))
		return
	var/turf/destination = get_turf(shuttle_datum.current_location)
	if(!destination || destination.density)
		to_chat(src, SPAN_WARNING("The disembark point is obstructed."))
		return

	persistence_telepad_deliver(list(src), destination)
	to_chat(src, SPAN_GOOD("You disembark the ship."))
	log_drydock("disembark_drydock_ship: [key_name(src)] disembarked shuttle_id=[DS.shuttle_id] at its docked beacon.")
