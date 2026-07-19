/*
 * Faction Tagger
 * Handheld configurator that sets/releases the faction ownership of any
 * compatible machine (modular computers, telepads, cryopods, lace storage,
 * telecomms, the faction beacon -- see faction_tagger_compatible() overrides
 * in code/controllers/subsystems/persistence/persistence_faction_tagger.dm)
 * through one consistent TGUI window, instead of each type's own scattered
 * right-click verbs.
 *
 * Four of those types (modular computers/PDAs, cryopods, autodocs, cargo
 * telepads) also support a second, mutually-exclusive tag mode: PERSONAL use
 * (personal_tagger_get_owner()/personal_tagger_set(), same file) -- tags the
 * device to the tagging character themselves, not a faction. An untagged
 * device can be personally tagged by anyone; a faction-tagged one needs
 * officer access in that faction to convert; a device already personally
 * tagged to someone else can't be touched by anyone but an admin, via the
 * "Override Tag" action.
 */
/obj/item/faction_tagger
	name = "faction tagger"
	desc = "A configurator for tagging station infrastructure to a faction network. Point and click on a compatible machine to open its network settings."
	// Borrowed sprite (blue-tinted) from the cargo destination tagger --
	// PLACEHOLDER until dedicated sprite work is done, same approach
	// already used for the security telepad's tint over the cargo pad.
	icon = 'icons/obj/item/dest_tagger.dmi'
	icon_state = "dest_tagger"
	item_state = "dest_tagger"
	color = "#4488ff"
	contained_sprite = TRUE
	w_class = WEIGHT_CLASS_SMALL
	slot_flags = SLOT_BELT

	/// The atom currently open in this tagger's UI, if any.
	var/atom/movable/current_target

// Never let a click target's own attackby() consume this click (e.g. an
// airlock opening/closing, a locker toggling open) -- the tagger is a
// deliberate, single-purpose tool, and its own afterattack() below should
// always get the chance to decide what happens, not whatever generic
// "unrecognized item" fallback the target happens to have. Exempts storage
// containers specifically -- attackby() is how "click the backpack sprite
// while holding an item" insertion actually happens, so that needs to run
// normally (matches afterattack()'s own storage exemption below).
/obj/item/faction_tagger/resolve_attackby(atom/A, mob/user, click_parameters)
	if(!istype(A, /obj/item/storage))
		pre_attack(A, user)
		add_fingerprint(user)
		log_attack("[A] at [A?.loc]/[A.x]-[A.y]-[A.z] got ITEM attacked by [usr]/[usr?.ckey] on INTENT [usr?.a_intent] with [src]")
		return FALSE
	return ..()

/obj/item/faction_tagger/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag)
		return
	if(target == user)
		return // accidental self-click (e.g. default use-in-hand keybind) shouldn't produce a warning
	if(istype(target, /obj/item/storage))
		return // let normal storage insertion happen -- don't second-guess it as a tag target
	if(!istype(target, /atom/movable))
		return
	var/atom/movable/AM = target
	if(!AM.faction_tagger_compatible())
		to_chat(user, SPAN_WARNING("\The [src] can't tag \the [target] -- not a faction-configurable machine."))
		return
	current_target = AM
	ui_interact(user)

/obj/item/faction_tagger/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FactionTagger", "Faction Tagger", 380, 260)
		ui.open()

/obj/item/faction_tagger/ui_data(mob/user)
	var/list/data = list()
	if(!current_target || QDELETED(current_target))
		return data
	var/current_uid = current_target.faction_tagger_get_uid()
	data["target_name"] = current_target.name
	data["current_uid"] = current_uid
	data["current_name"] = current_uid ? get_faction_name(current_uid) : null

	var/is_admin = check_rights(R_ADMIN, 0, user)
	data["is_admin"] = is_admin

	// Personal tag state -- "ckey|char_name" composite, split for display.
	var/personal_owner = current_target.personal_tagger_get_owner()
	var/personal_char_name = null
	if(personal_owner)
		var/list/parts = splittext(personal_owner, "|")
		personal_char_name = parts[2]
	data["personal_owner_name"] = personal_char_name
	data["is_own_personal_tag"] = personal_owner && (personal_owner == "[user.ckey]|[user.real_name]")
	data["can_personal_tag"] = current_target.faction_tagger_compatible() && (istype(current_target, /obj/item/modular_computer) || istype(current_target, /obj/structure/machinery/cryopod) || istype(current_target, /obj/structure/machinery/autodoc) || istype(current_target, /obj/structure/machinery/telepad_cargo))

	// Crew tag state -- boolean only, "crew" is resolved dynamically per-ship
	// rather than a stored identity (see crew_tagger_is_set()).
	data["is_crew_tagged"] = current_target.crew_tagger_is_set()
	data["can_crew_tag"] = current_target.faction_tagger_compatible() && (istype(current_target, /obj/item/modular_computer) || istype(current_target, /obj/structure/machinery/cryopod) || istype(current_target, /obj/structure/machinery/autodoc) || istype(current_target, /obj/structure/machinery/telepad_cargo) || istype(current_target, /obj/structure/machinery/door/airlock))
	var/turf/tag_turf = get_turf(current_target)
	var/datum/drydock_ship/tag_ship = tag_turf ? _drydock_ship_at(tag_turf.z) : null
	data["can_manage_crew"] = tag_ship && (is_admin || tag_ship.owned_by(user) || (tag_ship.faction_uid && can_configure_faction_shackle(user, tag_ship.faction_uid, 1)))

	// Non-admins can only ever use their own faction anyway (the rank check
	// refuses anything else) -- scope the list to that instead of dumping
	// every faction in the game into a confusing dropdown. Admins keep the
	// full list since they bypass rank checks entirely.
	var/obj/item/card/id/ID = user.GetIdCard()
	var/own_uid = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	data["own_uid"] = own_uid
	data["own_name"] = own_uid ? get_faction_name(own_uid) : null

	data["factions"] = list()
	if(is_admin && islist(GLOB.persistence_faction_cache))
		for(var/uid in GLOB.persistence_faction_cache)
			data["factions"] += list(list("uid" = uid, "name" = get_faction_name(uid)))
	else if(own_uid)
		data["factions"] += list(list("uid" = own_uid, "name" = data["own_name"]))

	if(is_admin && istype(current_target, /obj/structure/machinery/cryopod))
		var/obj/structure/machinery/cryopod/pod = current_target
		data["is_cryopod"] = TRUE
		data["persistent_spawn"] = pod.persistent_spawn && (pod.persistent_network == "public")

	if(is_admin && istype(current_target, /obj/structure/machinery/telecomms))
		data["is_telecomms"] = TRUE
		data["is_public_comms"] = (current_uid == "public")

	if(is_admin && istype(current_target, /obj/structure/machinery/autodoc))
		data["is_autodoc"] = TRUE
		data["is_public_autodoc"] = (current_uid == "public")

	if(is_admin && istype(current_target, /obj/structure/machinery/lace_storage))
		data["is_lace_storage"] = TRUE
		data["is_public_lace"] = (current_uid == "public")

	if(istype(current_target, /obj/structure/machinery/door/airlock))
		data["is_airlock"] = TRUE
		data["is_public_airlock"] = (current_uid == "public")

	if(istype(current_target, /obj/structure/machinery/porta_turret))
		var/obj/structure/machinery/porta_turret/PT = current_target
		data["is_turret"] = TRUE
		data["turret_enabled"] = PT.enabled
		data["turret_lethal"] = PT.lethal
		data["turret_target_mode"] = PT.turret_faction_target_mode
		data["is_public_turret"] = (current_uid == "public")

	return data

/obj/item/faction_tagger/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(!current_target || QDELETED(current_target))
		return
	var/mob/user = usr

	switch(action)
		if("set")
			var/new_uid = normalize_faction_uid(params["uid"])
			if(!new_uid)
				return
			if(!can_configure_faction_shackle(user, new_uid, 1))
				to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(new_uid)] to tag machines to it."))
				return
			var/old_uid = current_target.faction_tagger_get_uid()
			if(old_uid && old_uid != new_uid && !can_configure_faction_shackle(user, old_uid, 1))
				to_chat(user, SPAN_WARNING("\The [current_target] is already tagged to [get_faction_name(old_uid)] -- you need officer access there to retag it."))
				return
			// Territory check: even an UNCLAIMED target (no old_uid yet) can't
			// be claimed for a foreign faction if this Z is already under a
			// different faction's active beacon -- closes the gap for types
			// the beacon's own sweep doesn't cover (e.g. lace storage), which
			// would otherwise let a visitor claim things inside someone
			// else's territory.
			var/obj/structure/machinery/faction_beacon/beacon = GLOB.faction_beacon_by_z["[GET_Z(current_target)]"]
			if(beacon && !QDELETED(beacon) && beacon.active && beacon.faction_uid && beacon.faction_uid != new_uid)
				if(!check_rights(R_ADMIN, 0, user))
					to_chat(user, SPAN_WARNING("This Z-level belongs to [get_faction_name(beacon.faction_uid)]'s territory -- you can't tag machines here to a different faction."))
					return
			if(current_target.faction_tagger_set(new_uid, user))
				to_chat(user, SPAN_GOOD("\The [current_target] tagged to [get_faction_name(new_uid)]."))
				log_game("[key_name(user)] used a faction tagger to set [current_target] at [get_turf(current_target)] to faction '[new_uid]'.")
			. = TRUE
		if("release")
			// Personal tag takes priority -- release whichever one is actually set.
			var/personal_owner = current_target.personal_tagger_get_owner()
			if(personal_owner)
				if(personal_owner != "[user.ckey]|[user.real_name]" && !check_rights(R_ADMIN, 0, user))
					to_chat(user, SPAN_WARNING("\The [current_target] is personally tagged to someone else -- an admin must override it."))
					return
				if(current_target.faction_tagger_set(null, user))
					to_chat(user, SPAN_NOTICE("\The [current_target] released from personal use."))
					log_game("[key_name(user)] used a faction tagger to release [current_target] at [get_turf(current_target)] from personal use.")
				. = TRUE
				return
			if(current_target.crew_tagger_is_set())
				var/turf/release_turf = get_turf(current_target)
				var/datum/drydock_ship/release_ship = release_turf ? _drydock_ship_at(release_turf.z) : null
				var/is_admin_user = check_rights(R_ADMIN, 0, user)
				var/can_manage = is_admin_user || (release_ship && (release_ship.owned_by(user) || (release_ship.faction_uid && can_configure_faction_shackle(user, release_ship.faction_uid, 1))))
				if(!can_manage)
					to_chat(user, SPAN_WARNING("You must be this ship's owner[(release_ship && release_ship.faction_uid) ? " or a faction officer" : ""] to release this crew tag."))
					return
				if(current_target.faction_tagger_set(null, user))
					to_chat(user, SPAN_NOTICE("Released from crew use."))
					log_game("[key_name(user)] used a faction tagger to release [current_target] at [get_turf(current_target)] from crew use.")
				. = TRUE
				return
			var/old_uid = current_target.faction_tagger_get_uid()
			if(!old_uid)
				return
			if(!can_configure_faction_shackle(user, old_uid, 1))
				to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(old_uid)] to release this tag."))
				return
			if(current_target.faction_tagger_set(null, user))
				to_chat(user, SPAN_NOTICE("\The [current_target] released from [get_faction_name(old_uid)]."))
				log_game("[key_name(user)] used a faction tagger to release [current_target] at [get_turf(current_target)] from faction '[old_uid]'.")
			. = TRUE
		if("set_personal")
			if(!current_target.faction_tagger_compatible())
				return
			var/personal_owner = current_target.personal_tagger_get_owner()
			if(personal_owner && personal_owner != "[user.ckey]|[user.real_name]")
				to_chat(user, SPAN_WARNING("\The [current_target] is already personally tagged to someone else -- an admin must override it."))
				return
			var/old_uid = current_target.faction_tagger_get_uid()
			if(old_uid && !can_configure_faction_shackle(user, old_uid, 1))
				to_chat(user, SPAN_WARNING("\The [current_target] is already tagged to [get_faction_name(old_uid)] -- you need officer access there to convert it to personal use."))
				return
			// A beacon's own territory is never personal -- its periodic sweep
			// would just claim an unassigned device for the faction anyway, and
			// unlike the faction "set" action above there's no "same faction"
			// exception that could apply to a personal tag.
			var/obj/structure/machinery/faction_beacon/personal_beacon = GLOB.faction_beacon_by_z["[GET_Z(current_target)]"]
			if(personal_beacon && !QDELETED(personal_beacon) && personal_beacon.active && personal_beacon.faction_uid && !check_rights(R_ADMIN, 0, user))
				to_chat(user, SPAN_WARNING("This Z-level belongs to [get_faction_name(personal_beacon.faction_uid)]'s territory -- you can't personally tag machines here."))
				return
			if(current_target.personal_tagger_set(user))
				to_chat(user, SPAN_GOOD("\The [current_target] personally tagged to you."))
				log_game("[key_name(user)] used a faction tagger to personally tag [current_target] at [get_turf(current_target)] to themselves.")
			. = TRUE
		if("override_personal")
			if(!check_rights(R_ADMIN, 0, user))
				return
			if(current_target.personal_tagger_set(user))
				to_chat(user, SPAN_GOOD("\The [current_target] force-tagged to you (admin override)."))
				log_admin("[key_name(user)] used a faction tagger to FORCE personal-tag [current_target] at [get_turf(current_target)] to themselves (override).")
			. = TRUE
		if("set_crew")
			if(!current_target.faction_tagger_compatible())
				return
			var/turf/set_crew_turf = get_turf(current_target)
			var/datum/drydock_ship/set_crew_ship = set_crew_turf ? _drydock_ship_at(set_crew_turf.z) : null
			if(!set_crew_ship)
				to_chat(user, SPAN_WARNING("This isn't aboard a deployed drydock ship -- crew tagging doesn't apply here."))
				return
			var/is_admin_user = check_rights(R_ADMIN, 0, user)
			var/can_manage = is_admin_user || set_crew_ship.owned_by(user) || (set_crew_ship.faction_uid && can_configure_faction_shackle(user, set_crew_ship.faction_uid, 1))
			if(!can_manage)
				to_chat(user, SPAN_WARNING("You must be this ship's owner[set_crew_ship.faction_uid ? " or a faction officer" : ""] to crew-tag its equipment."))
				return
			var/personal_owner = current_target.personal_tagger_get_owner()
			if(personal_owner && personal_owner != "[user.ckey]|[user.real_name]" && !is_admin_user)
				to_chat(user, SPAN_WARNING("This is personally tagged to someone else -- an admin must override it."))
				return
			var/old_uid = current_target.faction_tagger_get_uid()
			if(old_uid && !can_configure_faction_shackle(user, old_uid, 1))
				to_chat(user, SPAN_WARNING("This is already tagged to [get_faction_name(old_uid)] -- you need officer access there to convert it to crew use."))
				return
			if(current_target.crew_tagger_set(user))
				to_chat(user, SPAN_GOOD("Tagged to this ship's crew."))
				log_game("[key_name(user)] used a faction tagger to crew-tag [current_target] at [get_turf(current_target)] to its ship's crew.")
			. = TRUE
		if("toggle_public_spawn")
			if(!check_rights(R_ADMIN, 0, user) || !istype(current_target, /obj/structure/machinery/cryopod))
				return
			var/obj/structure/machinery/cryopod/pod = current_target
			if(pod.persistent_network == "public")
				pod.persistent_network = ""
				pod.persistent_spawn   = FALSE
				to_chat(user, SPAN_GOOD("Cryopod cleared -- no longer a public spawn point."))
				log_admin("[key_name(user)] cleared the public spawn designation on a cryopod at [get_turf(pod)] via faction tagger.")
			else
				pod.persistent_network = "public"
				pod.persistent_spawn   = TRUE
				to_chat(user, SPAN_GOOD("Cryopod marked as a public spawn point."))
				log_admin("[key_name(user)] marked a cryopod at [get_turf(pod)] as a public spawn point via faction tagger.")
			if(!pod.persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
				SSpersistence.objectsRegisterTrack(pod)
			. = TRUE
		if("toggle_public_comms")
			if(!check_rights(R_ADMIN, 0, user) || !istype(current_target, /obj/structure/machinery/telecomms))
				return
			var/obj/structure/machinery/telecomms/T = current_target
			if(T.persistent_network == "public")
				T.persistent_network = ""
				to_chat(user, SPAN_GOOD("Telecomms cleared -- no longer public."))
				log_admin("[key_name(user)] cleared the public designation on telecomms at [get_turf(T)] via faction tagger.")
			else
				T.persistent_network = "public"
				to_chat(user, SPAN_GOOD("Telecomms marked public -- open to all factions in range."))
				log_admin("[key_name(user)] marked telecomms at [get_turf(T)] public via faction tagger.")
			. = TRUE
		if("toggle_public_autodoc")
			if(!check_rights(R_ADMIN, 0, user) || !istype(current_target, /obj/structure/machinery/autodoc))
				return
			var/obj/structure/machinery/autodoc/AD = current_target
			if(AD.persistent_network == "public")
				AD.persistent_network = ""
				to_chat(user, SPAN_GOOD("Autodoc cleared -- no longer public."))
				log_admin("[key_name(user)] cleared the public designation on an autodoc at [get_turf(AD)] via faction tagger.")
			else
				AD.persistent_network = "public"
				to_chat(user, SPAN_GOOD("Autodoc marked public -- open to anyone."))
				log_admin("[key_name(user)] marked an autodoc at [get_turf(AD)] public via faction tagger.")
			. = TRUE
		if("toggle_public_lace")
			if(!check_rights(R_ADMIN, 0, user) || !istype(current_target, /obj/structure/machinery/lace_storage))
				return
			var/obj/structure/machinery/lace_storage/LS = current_target
			if(LS.persistent_network == "public")
				LS.persistent_network = ""
				to_chat(user, SPAN_GOOD("Lace vault cleared -- no longer public."))
				log_admin("[key_name(user)] cleared the public designation on a lace vault at [get_turf(LS)] via faction tagger.")
			else
				LS.persistent_network = "public"
				to_chat(user, SPAN_GOOD("Lace vault marked public -- receives anyone's auto-transferred laces."))
				log_admin("[key_name(user)] marked a lace vault at [get_turf(LS)] public via faction tagger.")
			. = TRUE
		if("configure_door_access")
			if(!istype(current_target, /obj/structure/machinery/door/airlock))
				return
			var/obj/structure/machinery/door/airlock/AL = current_target
			var/door_uid = AL.faction_tagger_get_uid()
			if(!door_uid || door_uid == "public")
				to_chat(user, SPAN_WARNING("Tag this door to a faction first."))
				return
			if(!can_configure_faction_shackle(user, door_uid, 1))
				to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(door_uid)] to configure this door's access."))
				return
			_configure_airlock_access(AL, user)
			. = TRUE
		if("toggle_public_airlock")
			if(!check_rights(R_ADMIN, 0, user) || !istype(current_target, /obj/structure/machinery/door/airlock))
				return
			var/obj/structure/machinery/door/airlock/AL = current_target
			if(AL.req_access_faction == "public")
				AL.req_access_faction = ""
				to_chat(user, SPAN_GOOD("Airlock cleared -- no longer public."))
				log_admin("[key_name(user)] cleared the public designation on an airlock at [get_turf(AL)] via faction tagger.")
			else
				AL.req_access_faction = "public"
				to_chat(user, SPAN_GOOD("Airlock marked public -- open to anyone."))
				log_admin("[key_name(user)] marked an airlock at [get_turf(AL)] public via faction tagger.")
			. = TRUE
		if("toggle_turret_power")
			if(!istype(current_target, /obj/structure/machinery/porta_turret))
				return
			var/obj/structure/machinery/porta_turret/PT = current_target
			var/turret_uid = PT.faction_tagger_get_uid()
			if(!turret_uid)
				to_chat(user, SPAN_WARNING("Tag this turret to a faction first."))
				return
			if(!can_configure_faction_shackle(user, turret_uid, 1))
				to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(turret_uid)] to control this turret."))
				return
			PT.set_enabled(!PT.enabled)
			to_chat(user, SPAN_GOOD("\The [PT] [PT.enabled ? "enabled" : "disabled"]."))
			log_game("[key_name(user)] [PT.enabled ? "enabled" : "disabled"] [PT] at [get_turf(PT)] via faction tagger.")
			. = TRUE
		if("toggle_turret_lethal")
			if(!istype(current_target, /obj/structure/machinery/porta_turret))
				return
			var/obj/structure/machinery/porta_turret/PT = current_target
			var/turret_uid = PT.faction_tagger_get_uid()
			if(!turret_uid)
				to_chat(user, SPAN_WARNING("Tag this turret to a faction first."))
				return
			if(!can_configure_faction_shackle(user, turret_uid, 1))
				to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(turret_uid)] to control this turret."))
				return
			PT.lethal = !PT.lethal
			PT.lethal_icon = PT.lethal
			to_chat(user, SPAN_GOOD("\The [PT] set to [PT.lethal ? "lethal" : "stun"]."))
			log_game("[key_name(user)] set [PT] at [get_turf(PT)] to [PT.lethal ? "lethal" : "stun"] via faction tagger.")
			. = TRUE
		if("set_turret_mode")
			if(!istype(current_target, /obj/structure/machinery/porta_turret))
				return
			var/obj/structure/machinery/porta_turret/PT = current_target
			var/turret_uid = PT.faction_tagger_get_uid()
			if(!turret_uid)
				to_chat(user, SPAN_WARNING("Tag this turret to a faction first."))
				return
			if(!can_configure_faction_shackle(user, turret_uid, 1))
				to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(turret_uid)] to configure this turret's targeting."))
				return
			var/new_mode = params["mode"]
			if(!(new_mode in list(TURRET_FACTION_MODE_NONFACTION, TURRET_FACTION_MODE_WILDLIFE, TURRET_FACTION_MODE_BOTH)))
				return
			if(turret_uid == "public" && new_mode != TURRET_FACTION_MODE_WILDLIFE)
				to_chat(user, SPAN_WARNING("A public turret can only target wildlife."))
				return
			PT.turret_faction_target_mode = new_mode
			to_chat(user, SPAN_GOOD("\The [PT] targeting mode set to [new_mode]."))
			log_game("[key_name(user)] set turret targeting mode on [PT] at [get_turf(PT)] to '[new_mode]' via faction tagger.")
			. = TRUE
		if("toggle_public_turret")
			if(!check_rights(R_ADMIN, 0, user) || !istype(current_target, /obj/structure/machinery/porta_turret))
				return
			var/obj/structure/machinery/porta_turret/PT = current_target
			if(PT.persistent_network == "public")
				PT.persistent_network = ""
				to_chat(user, SPAN_GOOD("Turret cleared -- no longer public."))
				log_admin("[key_name(user)] cleared the public designation on a turret at [get_turf(PT)] via faction tagger.")
			else
				PT.persistent_network = "public"
				PT.turret_faction_target_mode = TURRET_FACTION_MODE_WILDLIFE
				to_chat(user, SPAN_GOOD("Turret marked public -- targets wildlife only."))
				log_admin("[key_name(user)] marked a turret at [get_turf(PT)] public via faction tagger.")
			. = TRUE

/// Same sequential add/remove access-code picker "Manage Faction Jobs" uses
/// (persistence_factions.dm), reused here so a faction officer can pick
/// which access codes gate a door they've already tagged to their faction --
/// writes into req_one_access (any-of), clearing req_access, replacing
/// whatever the door had left over from mapping.
/obj/item/faction_tagger/proc/_configure_airlock_access(obj/structure/machinery/door/airlock/AL, mob/user)
	var/list/new_access = LAZYLEN(AL.req_one_access) ? AL.req_one_access.Copy() : list()
	while(TRUE)
		var/summary = length(new_access) ? "[length(new_access)] codes set" : "none (all faction members)"
		var/sub = tgui_input_list(user, "Door access -- currently: [summary]", "Configure Door Access", list("Add Access Code", "Add by Region", "Remove Access Code", "Done"))
		if(!sub || sub == "Done")
			break
		if(sub == "Add Access Code")
			var/list/all_acc = get_all_station_access()
			var/list/addable = list()
			for(var/acc in all_acc)
				if(!(acc in new_access))
					addable["[get_access_desc(acc)] ([acc])"] = acc
			if(!length(addable))
				to_chat(user, SPAN_NOTICE("All access codes already assigned."))
				continue
			var/add_pick = tgui_input_list(user, "Select access to add:", "Add Access Code", addable)
			if(!add_pick) continue
			new_access += addable[add_pick]
		else if(sub == "Add by Region")
			var/list/regions = list()
			for(var/ri = 1; ri <= 7; ri++)
				regions[get_region_accesses_name(ri)] = ri
			var/reg_pick = tgui_input_list(user, "Select a region:", "Add by Region", regions)
			if(!reg_pick) continue
			var/list/reg_acc = get_region_accesses(regions[reg_pick])
			for(var/racc in reg_acc)
				if(!(racc in new_access))
					new_access += racc
		else if(sub == "Remove Access Code")
			if(!length(new_access))
				to_chat(user, SPAN_NOTICE("No access codes to remove."))
				continue
			var/list/removable = list()
			for(var/rem_acc in new_access)
				removable["[get_access_desc(rem_acc)] ([rem_acc])"] = rem_acc
			var/rem_pick = tgui_input_list(user, "Select access to remove:", "Remove Access Code", removable)
			if(!rem_pick) continue
			new_access -= removable[rem_pick]

	AL.req_access = null
	AL.req_one_access = length(new_access) ? new_access : null
	to_chat(user, SPAN_GOOD("\The [AL] now requires: [length(new_access) ? "[new_access.len] access code(s)" : "no extra access (all faction members)"]."))
	log_game("[key_name(user)] set door access on [AL] at [get_turf(AL)] via faction tagger: [length(new_access) ? new_access.Join(", ") : "(cleared)"].")
