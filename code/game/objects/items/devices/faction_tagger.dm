/*
 * Faction Tagger
 * Handheld configurator that sets/releases the faction ownership of any
 * compatible machine (modular computers, telepads, cryopods, lace storage,
 * telecomms, the faction beacon -- see faction_tagger_compatible() overrides
 * in code/controllers/subsystems/persistence/persistence_faction_tagger.dm)
 * through one consistent TGUI window, instead of each type's own scattered
 * right-click verbs.
 */
/obj/item/faction_tagger
	name = "faction tagger"
	desc = "A configurator for tagging station infrastructure to a faction network. Point and click on a compatible machine to open its network settings."
	// Borrowed sprite (red-tinted) from the cargo destination tagger --
	// PLACEHOLDER until dedicated sprite work is done, same approach
	// already used for the security telepad's tint over the cargo pad.
	icon = 'icons/obj/item/dest_tagger.dmi'
	icon_state = "dest_tagger"
	item_state = "dest_tagger"
	color = "#ff4444"
	contained_sprite = TRUE
	w_class = WEIGHT_CLASS_SMALL
	slot_flags = SLOT_BELT

	/// The atom currently open in this tagger's UI, if any.
	var/atom/movable/current_target

/obj/item/faction_tagger/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag)
		return
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
