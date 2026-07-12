/*
 * Corvette Boarding Pad
 *
 * A telepad_cargo subtype that moves a faction member's mob instead of
 * cargo -- boards them onto their faction's currently-deployed corvette
 * (persistence_corvettes.dm) from any station-side pad networked to that
 * faction, reusing the exact same "any pad on my network" lookup shape
 * persistence_find_cargo_telepad() already uses for cargo, keyed off the
 * corvette ledger instead of a flat pad scan. The corvette's own boarding
 * pad (map-placed in its .dmm, same tag pattern) is the return trip's
 * destination -- no dynamic creation needed, matches how the corvette
 * itself is a fixed piece of that hull's map content.
 */
/obj/structure/machinery/telepad_cargo/corvette_boarding
	name = "corvette boarding pad"
	desc = "A tuned telepad that boards a faction member onto their faction's deployed corvette. Use a faction tagger to tie it to a faction network."
	color = "#44aaff"
	accepts_cargo = FALSE

	/// Per-ckey flood/spam cooldown, mirrors the Faction Chat idiom (faction_chat.dm).
	var/static/list/last_boarded_by_ckey = list()

/obj/structure/machinery/telepad_cargo/corvette_boarding/Initialize()
	. = ..()
	verbs -= /obj/structure/machinery/telepad_cargo/verb/configure_supply_network

/obj/structure/machinery/telepad_cargo/corvette_boarding/verb/configure_boarding_network()
	set name = "Configure Boarding Network"
	set category = "Admin"
	set desc = "Set this pad's faction boarding network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	var/current = "[persistent_network ? persistent_network : "(none)"] | active=[persistent_spawn]"
	to_chat(usr, SPAN_NOTICE("Current config: [current]"))

	var/new_network = tgui_input_text(usr, "Enter network ID (a faction UID, or leave blank to clear):", "Configure Boarding Network", persistent_network, max_length = 32)
	if(new_network == null)
		return

	persistent_network = normalize_faction_uid(new_network)
	persistent_spawn = persistent_network ? TRUE : FALSE

	var/label = persistent_network ? "[persistent_network][persistent_spawn ? " (active)" : " (inactive)"]" : "unmanaged"
	to_chat(usr, SPAN_GOOD("Corvette boarding pad network set to: [label]"))
	log_admin("[key_name(usr)] configured corvette boarding pad at ([x],[y],[z]) network='[persistent_network]'.")

/obj/structure/machinery/telepad_cargo/corvette_boarding/attack_hand(mob/user)
	if(..())
		return TRUE
	corvette_board_mob(user, src)
	return TRUE

/// Core boarding delivery, shared by the physical corvette_boarding pad and
/// the Faction Ship program's "Enter Ship" action -- only the trigger
/// differs, candidate/destination logic is identical either way. Always
/// delivers to the corvette's own map-placed corvette_boarding pad (never
/// a console lookup) -- that pad is guaranteed, curated map content on
/// every corvette template. cooldown is a per-ckey world.time list owned
/// by the caller (a pad or a program instance), so different trigger
/// points don't share a single cooldown.
/proc/_corvette_board_core(mob/living/L, network, list/cooldown)
	if(!istype(L))
		return FALSE
	if(!network)
		to_chat(L, SPAN_WARNING("No faction network to board through."))
		log_corvette_warning("_corvette_board_core: refused -- [key_name(L)] has no faction network.")
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

	var/target_z
	for(var/cid in GLOB.faction_corvettes)
		var/datum/faction_corvette/C = GLOB.faction_corvettes[cid]
		if(C && !C.stashed && C.faction_uid == network)
			target_z = C.z
			break
	if(!target_z)
		to_chat(L, SPAN_WARNING("Your faction has no corvette currently deployed."))
		log_corvette_warning("_corvette_board_core: refused -- [key_name(L)] found no deployed corvette for faction [network].")
		return FALSE

	var/obj/structure/machinery/telepad_cargo/corvette_boarding/ship_pad
	for(var/obj/structure/machinery/telepad_cargo/corvette_boarding/pad in world)
		if(pad.z == target_z)
			ship_pad = pad
			break
	if(!ship_pad)
		to_chat(L, SPAN_WARNING("No boarding pad found aboard the corvette."))
		log_corvette_error("_corvette_board_core: no corvette_boarding pad found at z=[target_z] for faction [network].")
		return FALSE

	var/turf/destination = get_turf(ship_pad)
	if(!destination || destination.density)
		to_chat(L, SPAN_WARNING("The boarding pad's destination is obstructed."))
		log_corvette_warning("_corvette_board_core: refused -- destination turf at z=[target_z] is invalid or dense.")
		return FALSE

	cooldown[L.ckey] = world.time
	persistence_telepad_deliver(list(L), destination)
	to_chat(L, SPAN_GOOD("You board the corvette."))
	log_corvette("_corvette_board_core: [key_name(L)] boarded the faction [network] corvette at z=[target_z].")
	return TRUE

/// Wrapper for the physical corvette boarding pad -- reads the pad's own
/// faction network and per-pad cooldown, delegates to the shared core.
/// Same flat world-scan lookup shape as persistence_find_cargo_telepad()
/// (persistence_cryo.dm:628-647), keyed off GLOB.faction_corvettes instead
/// of a pad's own persistent_spawn.
/proc/corvette_board_mob(mob/living/L, obj/structure/machinery/telepad_cargo/corvette_boarding/from_pad)
	if(!istype(from_pad))
		return FALSE
	var/network = normalize_faction_uid(from_pad.persistent_network)
	if(!network)
		to_chat(L, SPAN_WARNING("This pad isn't networked to a faction."))
		log_corvette_warning("corvette_board_mob: refused -- pad at ([from_pad.x],[from_pad.y],[from_pad.z]) has no faction network.")
		return FALSE
	return _corvette_board_core(L, network, from_pad.last_boarded_by_ckey)
