/*
 * Faction Beacon
 * A single placeable object that anchors a faction's territory to an entire
 * Z-level. Every compatible object/area on that Z-level automatically
 * inherits the faction's persistent_network, so admins configure one object
 * instead of each cryopod, telepad, console, telecomms machine, and
 * blueprint-created area individually. Every site this codebase deals with
 * is single-faction territory, so whole-Z-level scope (not a configurable
 * radius) is the intended design -- see GLOB.faction_beacon_by_z below for
 * how a second beacon on the same Z-level is handled.
 */

/obj/structure/machinery/faction_beacon
	name = "faction beacon"
	desc = "An anchor beacon that ties nearby infrastructure to a faction network."
	icon = 'icons/obj/machinery/telecomms.dmi'
	icon_state = "bspacerelay"
	anchored = TRUE
	density = FALSE
	layer = OBJ_LAYER

	/// Faction UID this beacon represents (e.g. "nanotrasen", "zavodskoi")
	var/faction_uid = ""
	/// Whether this beacon is actively networked
	var/active = FALSE

/// Z-number (as text) -> the faction beacon currently claiming that whole
/// Z-level. Only one beacon may be active per Z at a time -- first-placed/
/// configured takes precedence; a second beacon on the same Z is refused
/// until the first is destroyed or its faction is cleared.
GLOBAL_LIST_EMPTY(faction_beacon_by_z)

/obj/structure/machinery/faction_beacon/Initialize(mapload)
	. = ..()
	if(faction_uid)
		_apply_network()

/obj/structure/machinery/faction_beacon/Destroy()
	_release_z_claim()
	return ..()

/obj/structure/machinery/faction_beacon/worldstate_get_content()
	if(!faction_uid)
		return list()
	return list("faction_uid" = faction_uid)

/obj/structure/machinery/faction_beacon/worldstate_apply_content(list/content)
	faction_uid = content["faction_uid"] || ""
	if(faction_uid)
		_apply_network()

/// TRUE if this beacon currently holds (or can freely take) the Z claim --
/// FALSE if a different, still-existing beacon already holds it.
/obj/structure/machinery/faction_beacon/proc/_can_claim_z()
	var/obj/structure/machinery/faction_beacon/holder = GLOB.faction_beacon_by_z["[GET_Z(src)]"]
	if(!holder || holder == src || QDELETED(holder))
		return TRUE
	return FALSE

/obj/structure/machinery/faction_beacon/proc/_release_z_claim()
	var/key = "[GET_Z(src)]"
	if(GLOB.faction_beacon_by_z[key] == src)
		GLOB.faction_beacon_by_z -= key

/// Scan every compatible object/area on this beacon's Z-level and set their
/// persistent_network to our faction_uid. Refuses to run (and logs why) if
/// a different, still-active beacon already claims this Z -- callers that
/// need to tell an admin why should check _can_claim_z() themselves first
/// (see configure_faction_beacon()) for a proper chat message.
/obj/structure/machinery/faction_beacon/proc/_apply_network()
	faction_uid = normalize_faction_uid(faction_uid)
	if(!faction_uid)
		active = FALSE
		_release_z_claim()
		return

	if(!_can_claim_z())
		active = FALSE
		log_game("Faction beacon at ([x],[y],[z]): refused to activate -- z-level [GET_Z(src)] is already claimed by another active beacon.")
		return

	var/beacon_z = GET_Z(src)
	GLOB.faction_beacon_by_z["[beacon_z]"] = src
	active = TRUE
	var/configured = 0

	for(var/obj/structure/machinery/cryopod/pod in world)
		if(GET_Z(pod) != beacon_z)
			continue
		pod.persistent_network = faction_uid
		pod.persistent_spawn   = TRUE
		configured++

	for(var/obj/structure/machinery/telepad_cargo/pad in world)
		if(GET_Z(pad) != beacon_z)
			continue
		if(pad.faction_shackled && pad.persistent_network != faction_uid)
			continue  // respect player shackle to a different faction
		pad.persistent_network = faction_uid
		pad.persistent_spawn   = TRUE
		configured++

	// Configure modular computers directly (machine-level persistent_network).
	// Skips computers already shackled to a different faction, and skips
	// handheld PDAs/wristbound computers entirely -- those are personal
	// devices a crew member carries, not station/faction infrastructure.
	for(var/obj/item/modular_computer/MC in world)
		if(GET_Z(MC) != beacon_z)
			continue
		if(istype(MC, /obj/item/modular_computer/handheld))
			continue
		if(MC.faction_shackled && MC.persistent_network != faction_uid)
			continue  // respect player shackle to a different faction
		MC.persistent_network = faction_uid
		configured++

	for(var/obj/structure/machinery/telecomms/T in world)
		if(GET_Z(T) != beacon_z)
			continue
		T.persistent_network = faction_uid
		configured++

	for(var/area/A in GLOB.areas)
		if(!A.is_blueprint_area)
			continue
		var/on_z = FALSE
		for(var/turf/AT in A.contents)
			if(GET_Z(AT) == beacon_z)
				on_z = TRUE
				break
		if(!on_z)
			continue
		A.persistent_network = faction_uid
		configured++

	log_game("Faction beacon at ([x],[y],[z]): networked [configured] objects/areas to faction '[faction_uid]' across z-level [beacon_z].")
	update_icon()

/obj/structure/machinery/faction_beacon/update_icon()
	if(active && faction_uid)
		icon_state = "bspacerelay"
	else
		icon_state = "bspacerelay"

/obj/structure/machinery/faction_beacon/verb/configure_faction_beacon()
	set name = "Configure Faction Beacon"
	set category = "Persistence"
	set desc = "Set this beacon's faction UID and activate the network across its entire z-level."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	var/current = faction_uid ? "[faction_uid] (active=[active])" : "(unconfigured)"
	to_chat(usr, SPAN_NOTICE("Current config: [current]"))

	var/new_uid = tgui_input_text(usr, "Enter faction UID (e.g. 'nanotrasen', 'zavodskoi') or leave blank to clear:", "Configure Faction Beacon", faction_uid, max_length = 32)
	if(new_uid == null)
		return
	new_uid = normalize_faction_uid(new_uid)

	if(new_uid == "")
		faction_uid = ""
		active = FALSE
		_release_z_claim()
		update_icon()
		to_chat(usr, SPAN_WARNING("Faction beacon cleared. Objects are no longer networked."))
		log_admin("[key_name(usr)] cleared faction beacon at ([x],[y],[z]).")
		return

	// Validate faction exists
	if(islist(GLOB.persistence_faction_cache) && length(GLOB.persistence_faction_cache))
		if(!(new_uid in GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("Warning: '[new_uid]' is not in the faction cache. Make sure to run db_update.bat and that the faction exists."))

	if(!_can_claim_z())
		var/obj/structure/machinery/faction_beacon/holder = GLOB.faction_beacon_by_z["[GET_Z(src)]"]
		to_chat(usr, SPAN_WARNING("Z-level [GET_Z(src)] is already claimed by another active faction beacon (faction '[holder.faction_uid]'). Destroy or clear that beacon first."))
		return

	faction_uid = new_uid
	_apply_network()

	to_chat(usr, SPAN_GOOD("Faction beacon set to '[faction_uid]', networked across z-level [GET_Z(src)]. [active ? "Network active." : "Failed to activate."]"))
	log_admin("[key_name(usr)] configured faction beacon at ([x],[y],[z]) to faction '[faction_uid]' (whole z-level [GET_Z(src)]).")
