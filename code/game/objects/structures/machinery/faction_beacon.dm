/*
 * Faction Beacon
 * A single placeable object that anchors a faction's territory.
 * All compatible objects within network_radius automatically inherit
 * the faction's persistent_network, so admins configure one object
 * instead of each cryopod, telepad, and console individually.
 */

/obj/structure/machinery/faction_beacon
	name = "faction beacon"
	desc = "An anchor beacon that ties nearby infrastructure to a faction network."
	icon = 'icons/obj/machinery/cryopod.dmi'
	icon_state = "cryo_pod"
	anchored = TRUE
	density = FALSE
	layer = OBJ_LAYER

	/// Faction UID this beacon represents (e.g. "nanotrasen", "zavodskoi")
	var/faction_uid = ""
	/// Radius in tiles to scan for compatible objects
	var/network_radius = 30
	/// Whether this beacon is actively networked
	var/active = FALSE

/obj/structure/machinery/faction_beacon/Initialize(mapload)
	. = ..()
	if(faction_uid)
		_apply_network()

/obj/structure/machinery/faction_beacon/worldstate_get_content()
	if(!faction_uid)
		return list()
	return list("faction_uid" = faction_uid, "network_radius" = network_radius)

/obj/structure/machinery/faction_beacon/worldstate_apply_content(list/content)
	faction_uid     = content["faction_uid"] || ""
	network_radius  = text2num(content["network_radius"]) || 30
	if(faction_uid)
		_apply_network()

/// Scan nearby objects and set their persistent_network to our faction_uid
/obj/structure/machinery/faction_beacon/proc/_apply_network()
	if(!faction_uid)
		active = FALSE
		return

	active = TRUE
	var/configured = 0

	for(var/obj/structure/machinery/cryopod/pod in range(network_radius, src))
		pod.persistent_network = faction_uid
		pod.persistent_spawn   = TRUE
		configured++

	for(var/obj/structure/machinery/telepad_cargo/pad in range(network_radius, src))
		pad.persistent_network = faction_uid
		pad.persistent_spawn   = TRUE
		configured++

	// Configure programs running on nearby modular computers
	for(var/obj/item/modular_computer/MC in range(network_radius, src))
		if(!MC.hard_drive) continue
		for(var/datum/computer_file/program/P in MC.hard_drive.stored_files)
			if(istype(P, /datum/computer_file/program/card_mod))
				var/datum/computer_file/program/card_mod/CM = P
				CM.persistent_network = faction_uid
				configured++
			if(istype(P, /datum/computer_file/program/civilian/cargocontrol))
				var/datum/computer_file/program/civilian/cargocontrol/CC = P
				CC.persistent_network = faction_uid
				configured++

	log_game("Faction beacon at ([x],[y],[z]): networked [configured] objects to faction '[faction_uid]'.")
	update_icon()

/obj/structure/machinery/faction_beacon/update_icon()
	if(active && faction_uid)
		icon_state = "cryo_pod"
	else
		icon_state = "cryo_pod"

/obj/structure/machinery/faction_beacon/verb/configure_faction_beacon()
	set name = "Configure Faction Beacon"
	set category = "Persistence"
	set desc = "Set this beacon's faction UID and activate the network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	var/current = faction_uid ? "[faction_uid] (active=[active], radius=[network_radius])" : "(unconfigured)"
	to_chat(usr, SPAN_NOTICE("Current config: [current]"))

	var/new_uid = tgui_input_text(usr, "Enter faction UID (e.g. 'nanotrasen', 'zavodskoi') or leave blank to clear:", "Configure Faction Beacon", faction_uid, max_length = 32)
	if(new_uid == null)
		return

	if(new_uid == "")
		faction_uid = ""
		active = FALSE
		update_icon()
		to_chat(usr, SPAN_WARNING("Faction beacon cleared. Objects are no longer networked."))
		log_admin("[key_name(usr)] cleared faction beacon at ([x],[y],[z]).")
		return

	// Validate faction exists
	if(islist(GLOB.persistence_faction_cache) && length(GLOB.persistence_faction_cache))
		if(!(new_uid in GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("Warning: '[new_uid]' is not in the faction cache. Make sure to run db_update.bat and that the faction exists."))

	var/new_radius = tgui_input_number(usr, "Network radius (tiles):", "Configure Faction Beacon", network_radius, 5, 200)
	if(isnull(new_radius))
		return

	faction_uid    = new_uid
	network_radius = new_radius
	_apply_network()

	to_chat(usr, SPAN_GOOD("Faction beacon set to '[faction_uid]' with radius [network_radius]. [active ? "Network active." : "Failed to activate."]"))
	log_admin("[key_name(usr)] configured faction beacon at ([x],[y],[z]) to faction '[faction_uid]' radius=[network_radius].")
