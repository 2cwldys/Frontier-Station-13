/*
 * Faction Ship Command
 * Buy/retrieve/stash faction corvettes (persistence_corvettes.dm). Distinct
 * from the drydock program -- corvettes are faction-only, Z-based, and
 * never personally owned. No admin verb needed for normal play; see
 * SSpersistence.corvetteBuy()/corvetteRetrieve()/corvetteStash() for the
 * actual engine this program calls into.
 */
/datum/computer_file/program/faction_ships
	filename = "factionships"
	filedesc = "Faction Ship Command"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Buy, retrieve, or stash your faction's corvettes."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 4
	tgui_id = "FactionShips"
	ui_auto_update = TRUE

	/// Per-ckey Enter Ship cooldown, same shape/spam-guard as the physical
	/// corvette_boarding pad's own last_boarded_by_ckey -- kept separate so
	/// the program and any physical pad don't share a single cooldown.
	var/list/last_boarded_by_ckey = list()

/datum/computer_file/program/faction_ships/proc/_own_faction(mob/user)
	var/obj/item/card/id/ID = user.GetIdCard()
	if(!ID || !ID.employer_faction)
		return null
	return normalize_faction_uid(ID.employer_faction)

/datum/computer_file/program/faction_ships/ui_data(mob/user)
	var/list/data = initial_data()

	var/own_faction = _own_faction(user)
	data["own_faction_name"] = own_faction ? get_faction_name(own_faction) : null
	data["can_manage"] = own_faction && can_configure_faction_shackle(user, own_faction, 1)

	data["corvettes"] = list()
	if(own_faction)
		for(var/cid in GLOB.faction_corvettes)
			var/datum/faction_corvette/C = GLOB.faction_corvettes[cid]
			if(!C || C.faction_uid != own_faction)
				continue
			data["corvettes"] += list(list(
				"corvette_id" = C.corvette_id,
				"template_id" = C.template_id,
				"stashed" = C.stashed,
				"z" = C.z
			))

	data["templates"] = list()
	for(var/tid in SSmapping.faction_corvette_templates)
		var/datum/map_template/faction_corvette/T = SSmapping.faction_corvette_templates[tid]
		data["templates"] += list(list(
			"template_id" = tid,
			"display_name" = T.name,
			"price" = T.price
		))

	data["boarding_pads"] = list()
	if(own_faction)
		for(var/obj/structure/machinery/telepad_cargo/corvette_boarding/pad in world)
			if(normalize_faction_uid(pad.persistent_network) != own_faction)
				continue
			var/turf/T = get_turf(pad)
			data["boarding_pads"] += list(list(
				"location" = T ? "([T.x],[T.y],[T.z])" : "unknown"
			))

	var/board_ready_at = last_boarded_by_ckey[user.ckey] ? (last_boarded_by_ckey[user.ckey] + 30) : 0
	data["can_board"] = world.time >= board_ready_at
	data["board_cooldown"] = max(0, round((board_ready_at - world.time) / 10))

	return data

/datum/computer_file/program/faction_ships/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/user = usr
	var/own_faction = _own_faction(user)

	switch(action)
		if("buy")
			if(!own_faction)
				to_chat(user, SPAN_WARNING("You need a faction-issued ID to buy a corvette."))
				log_corvette_warning("faction_ships ui_act: [key_name(user)] tried to buy without a faction ID.")
				return TRUE
			var/template_id = params["template_id"]
			log_corvette("faction_ships ui_act: [key_name(user)] requested buy of template '[template_id]' for faction [own_faction].")
			SSpersistence.corvetteBuy(template_id, own_faction, user)
			return TRUE

		if("retrieve")
			var/corvette_id = text2num(params["corvette_id"])
			log_corvette("faction_ships ui_act: [key_name(user)] requested retrieve of corvette_id=[corvette_id].")
			SSpersistence.corvetteRetrieve(corvette_id, computer, user)
			return TRUE

		if("stash")
			var/corvette_id = text2num(params["corvette_id"])
			log_corvette("faction_ships ui_act: [key_name(user)] requested stash of corvette_id=[corvette_id].")
			SSpersistence.corvetteStash(corvette_id, user)
			return TRUE

		if("board")
			log_corvette("faction_ships ui_act: [key_name(user)] requested Enter Ship.")
			_corvette_board_core(user, own_faction, last_boarded_by_ckey)
			return TRUE
