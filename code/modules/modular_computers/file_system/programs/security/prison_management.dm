/*
 * Prison Management
 * Remote counterpart to a cryogenic prison storage pod's own physical TGUI
 * (code/game/objects/structures/machinery/cryopod_prison.dm) -- lets
 * security manage every prisoner tied to THIS console's own faction network
 * (computer.persistent_network) without needing to walk to each individual
 * cell. Respects the same security-access gate the pod itself uses, and the
 * same frozen/thawed (parole) and sentence-adjustment concepts.
 */
/datum/computer_file/program/prison_management
	filename = "prisonmgmt"
	filedesc = "Prison Management"
	program_icon_state = "security"
	program_key_icon_state = "yellow_key"
	extended_desc = "Remotely manage cryogenic prison storage sentences for your faction."
	required_access_run = ACCESS_SECURITY
	required_access_download = ACCESS_SECURITY
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 6
	color = LIGHT_COLOR_ORANGE
	tgui_id = "PrisonManagement"
	ui_auto_update = TRUE

/// TRUE if user's worn ID grants ACCESS_SECURITY and (when net is set)
/// matches it -- mirrors cryopod_prison.dm's own _prison_access_ok().
/datum/computer_file/program/prison_management/proc/_access_ok(mob/user, net)
	var/obj/item/card/id/ID = user.GetIdCard()
	if(!ID || !(ACCESS_SECURITY in ID.access))
		return FALSE
	if(net && normalize_faction_uid(ID.employer_faction) != net)
		return FALSE
	return TRUE

/datum/computer_file/program/prison_management/ui_data(mob/user)
	var/list/data = initial_data()
	var/net = normalize_faction_uid(computer.persistent_network)
	data["faction_uid"] = net
	data["faction_name"] = net ? get_faction_name(net) : null
	data["prisoners"] = list()
	if(!net || !GLOB.config.sql_enabled || !SSdbcore.Connect())
		return data

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT ckey, char_name FROM ss13_mob_position WHERE imprisoned = 1", list())
	q.Execute()
	var/list/candidates = list()
	if(SSpersistence.databaseCheckQueryResult(q, "prison_management list"))
		while(q.NextRow())
			candidates += list(list("ckey" = q.item[1], "char_name" = q.item[2]))
	qdel(q)

	for(var/list/c in candidates)
		// _record(), not _status() -- an unlocked/paroled prisoner should
		// still be manageable here, not just ones actively blocked from playing.
		var/list/rec = persistence_character_imprisonment_record(c["ckey"], c["char_name"])
		if(!rec)
			continue
		// The faction recorded at the moment of imprisonment is authoritative
		// for "who owns this prisoner" -- not the cell's current tag, which
		// could have drifted since (a beacon re-tagging its territory
		// shouldn't silently transfer custody of an existing prisoner).
		if(normalize_faction_uid(rec["faction_uid"]) != net)
			continue
		data["prisoners"] += list(list(
			"ckey"              = c["ckey"],
			"char_name"         = c["char_name"],
			"indefinite"        = rec["indefinite"],
			"remaining_seconds" = rec["remaining_seconds"],
			"frozen"            = rec["frozen"]
		))
	return data

/datum/computer_file/program/prison_management/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/user = usr
	var/net = normalize_faction_uid(computer.persistent_network)
	if(!net || !_access_ok(user, net))
		to_chat(user, SPAN_WARNING("Security access for this faction is required."))
		return TRUE

	var/target_ckey = params["ckey"]
	var/target_char_name = params["char_name"]
	if(!target_ckey || !target_char_name)
		return TRUE

	// Re-verify the target is still a genuine prisoner tied to THIS faction's
	// own cell before allowing any mutation -- never trust a stale client-
	// side row (the record could have been released/expired/rehomed since
	// the last ui_data() refresh).
	var/list/rec = persistence_character_imprisonment_record(target_ckey, target_char_name)
	if(!rec)
		to_chat(user, SPAN_WARNING("That prisoner is no longer imprisoned."))
		return TRUE
	// The faction recorded at imprisonment time is authoritative -- see the
	// matching comment in ui_data().
	if(normalize_faction_uid(rec["faction_uid"]) != net)
		to_chat(user, SPAN_WARNING("That prisoner isn't held by [get_faction_name(net)]."))
		return TRUE
	var/obj/structure/machinery/cryopod/prison/cell = rec["cell"]

	switch(action)
		if("release")
			persistence_set_imprisoned(target_ckey, target_char_name, FALSE)
			to_chat(user, SPAN_GOOD("Released [target_char_name] ([target_ckey]) from imprisonment."))
			log_and_message_admins("released [target_char_name] ([target_ckey]) from cryogenic prison storage via Prison Management ([get_faction_name(net)]).", user)
			. = TRUE

		if("toggle_freeze")
			cell.frozen = !cell.frozen
			if(cell.frozen)
				// Forcibly end any live session(s) in that cell right now --
				// mirrors cryopod_prison.dm's own toggle_freeze handler.
				for(var/mob/living/carbon/O in cell.prison_occupants.Copy())
					if(O.client)
						cell.persistence_force_store(O)
						cell.prison_occupants -= O
			to_chat(user, SPAN_GOOD("[target_char_name]'s cell is now [cell.frozen ? "FROZEN" : "THAWED"]."))
			log_and_message_admins("[cell.frozen ? "froze" : "thawed"] [target_char_name] ([target_ckey])'s cryogenic prison storage via Prison Management ([get_faction_name(net)]).", user)
			. = TRUE

		if("adjust")
			var/indefinite_choice = tgui_alert(user, "Set a new fixed sentence, or make it indefinite?", "Adjust Sentence", list("Fixed Duration", "Indefinite", "Cancel"))
			if(!indefinite_choice || indefinite_choice == "Cancel")
				return TRUE
			var/minutes = null
			if(indefinite_choice == "Fixed Duration")
				minutes = tgui_input_number(user, "New sentence length in minutes (from now):", "Adjust Sentence", 60, 100000, 1)
				if(isnull(minutes) || minutes <= 0)
					return TRUE
			persistence_set_imprisoned(target_ckey, target_char_name, TRUE, minutes, net)
			to_chat(user, SPAN_GOOD("[target_char_name]'s sentence updated[minutes ? " -- [minutes] minute(s) remaining" : " -- now indefinite"]."))
			log_and_message_admins("adjusted [target_char_name] ([target_ckey])'s cryogenic prison sentence[minutes ? " to [minutes] minute(s)" : " to indefinite"] via Prison Management ([get_faction_name(net)]).", user)
			. = TRUE
