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

/// Core boarding delivery, shared by the physical drydock_boarding pad and
/// the Drydock program's "Enter Ship" action -- only the trigger differs,
/// candidate/destination logic is identical either way. pad_network null
/// means public (personal ownership, any faction the mob belongs to, or
/// being listed on a ship's own crew list -- drydockAddCrew(),
/// persistence_shuttles.dm); a normalized faction uid restricts candidates
/// to that faction's ships only. cooldown is a per-ckey world.time list
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
	if(cooldown[L.ckey] && (world.time - cooldown[L.ckey] < 30))
		to_chat(L, SPAN_WARNING("Still recalibrating -- wait a moment."))
		return FALSE

	var/obj/effect/overmap/visitable/mob_sector = _drydock_boarder_sector(L)

	var/list/candidates = list()
	var/found_not_ready = FALSE
	var/obj/item/card/id/ID = L.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed)
			continue
		if(pad_network)
			if(DS.faction_uid != pad_network)
				continue
		else if(!((DS.owner_ckey && DS.owner_ckey == L.ckey) || (DS.faction_uid && DS.faction_uid == own_faction) || (L.ckey in DS.crew_ckeys)))
			continue
		// Still mid-load (deferred atmos settle, persistence_ship_interiors.dm)
		// -- not offered as a candidate at all yet, distinct from "no ships."
		if(!DS.ready)
			found_not_ready = TRUE
			continue
		// Ownership/faction/crew only grants VISIBILITY to board -- the ship
		// still has to actually be nearby (same or an adjacent sector).
		var/obj/effect/overmap/visitable/ship_sector = GLOB.map_sectors["[DS.z]"]
		if(!istype(mob_sector) || !istype(ship_sector) || get_dist(mob_sector, ship_sector) > 1)
			continue
		candidates += DS

	if(!length(candidates))
		if(found_not_ready)
			to_chat(L, SPAN_WARNING("Your ship is still initializing -- try again in a moment."))
		else
			to_chat(L, SPAN_WARNING(pad_network ? "[get_faction_name(pad_network)] has no drydock ships currently deployed nearby." : "You have no drydock ships currently deployed nearby."))
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
	to_chat(L, SPAN_NOTICE("You begin boarding the ship..."))
	if(!do_after(L, DRYDOCK_BOARDING_SPOOLUP, L))
		to_chat(L, SPAN_WARNING("Boarding interrupted."))
		return FALSE
	if(L.in_recent_combat())
		to_chat(L, SPAN_WARNING("Combat detected -- boarding aborted."))
		return FALSE

	// Full re-validation -- the spool-up gives plenty of time for the ship
	// to be stashed, its marker destroyed, or the mob to have moved out of
	// range or into a bad state.
	var/datum/drydock_ship/recheck = GLOB.drydock_ships[target.shuttle_id]
	if(!recheck || recheck != target || recheck.stashed)
		to_chat(L, SPAN_WARNING("The ship is no longer available to board."))
		return FALSE
	if(!recheck.ready)
		to_chat(L, SPAN_WARNING("The ship started re-initializing -- try again in a moment."))
		return FALSE
	if(QDELETED(L) || L.stat == DEAD || L.buckled_to)
		return FALSE
	var/obj/effect/overmap/visitable/recheck_mob_sector = _drydock_boarder_sector(L)
	var/obj/effect/overmap/visitable/recheck_ship_sector = GLOB.map_sectors["[target.z]"]
	if(!istype(recheck_mob_sector) || !istype(recheck_ship_sector) || get_dist(recheck_mob_sector, recheck_ship_sector) > 1)
		to_chat(L, SPAN_WARNING("You're no longer close enough to board."))
		return FALSE
	var/turf/final_destination = _drydock_console_turf(target.z)
	if(!final_destination || final_destination.density)
		to_chat(L, SPAN_WARNING("The boarding point is no longer available."))
		return FALSE

	persistence_telepad_deliver(list(L), final_destination)
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
	if(!shuttle_datum || marker.status != SHIP_STATUS_LANDED)
		to_chat(src, SPAN_WARNING("The ship must be docked before you can disembark."))
		return
	var/turf/destination = get_turf(shuttle_datum.current_location)
	if(!destination || destination.density)
		to_chat(src, SPAN_WARNING("The disembark point is obstructed."))
		return

	persistence_telepad_deliver(list(src), destination)
	to_chat(src, SPAN_GOOD("You disembark the ship."))
	log_drydock("disembark_drydock_ship: [key_name(src)] disembarked shuttle_id=[DS.shuttle_id] at its docked beacon.")
