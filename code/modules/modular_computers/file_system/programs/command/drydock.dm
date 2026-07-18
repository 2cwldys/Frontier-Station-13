/*
 * Ship Drydock
 * Lets a player buy/stash/retrieve/remove/scuttle their own (or their
 * faction's) drydock ships from any modular computer. Retrieve and stash are
 * sector-relative: a faction-owned ship anchors to its own faction's
 * faction_beacon (claims a whole Z, resolved fresh from the computer's own Z
 * whenever needed -- at most one can exist per Z, so no selection state is
 * needed); a personally-owned ship uses whatever sector the computer is
 * currently in, no beacon required at all -- see the file header in
 * persistence_shuttles.dm for the full rationale. No admin verb needed --
 * see SSpersistence.drydockStash()/drydockRetrieve()/drydockBuy()/
 * drydockScuttle() (persistence_shuttles.dm) for the actual ledger/
 * materialization engine this program calls into.
 */
/datum/computer_file/program/drydock
	filename = "drydock"
	filedesc = "Ship Drydock"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Buy, stash, retrieve, or remove your drydock ships."
	// Widened to include PROGRAM_TABLET so a PDA can run this program at all
	// -- but only Enter Ship is actually usable from a handheld; every other
	// action explicitly refuses on a non-console/laptop device in ui_act()
	// below, since the structural exclusion this used to provide for free
	// (a PDA simply couldn't open the program) is gone now that it can.
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_TABLET
	requires_ntnet = FALSE
	size = 4
	tgui_id = "ShuttleDrydock"
	ui_auto_update = TRUE

	/// Per-ckey Enter Ship cooldown, same shape/spam-guard as the physical
	/// drydock_boarding pad's own last_boarded_by_ckey -- kept separate so
	/// the program and any physical pad don't share a single cooldown.
	var/list/last_boarded_by_ckey = list()

/// The faction beacon claiming the computer's own Z, if any -- at most one
/// can exist per Z, so no separate identifier/selection state is needed.
/datum/computer_file/program/drydock/proc/_nearby_faction_beacon()
	var/turf/T = get_turf(computer)
	if(!T)
		return null
	return GLOB.faction_beacon_by_z["[T.z]"]

/datum/computer_file/program/drydock/ui_data(mob/user)
	var/list/data = initial_data()

	var/obj/structure/machinery/faction_beacon/nearby_faction_beacon = _nearby_faction_beacon()
	data["faction_beacon"] = nearby_faction_beacon ? list(
		"faction_uid" = nearby_faction_beacon.faction_uid,
		"faction_name" = get_faction_name(nearby_faction_beacon.faction_uid)
	) : null

	var/obj/item/card/id/ID = user.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	data["own_faction_name"] = own_faction ? get_faction_name(own_faction) : null

	data["personal_shuttles"] = list()
	data["faction_shuttles"] = list()
	var/list/my_shuttle_ids = list()
	if(SSpersistence.databaseCheckConnection("drydock ui_data"))
		// Personal ownership is scoped to THIS character (ckey + real_name),
		// not the whole account -- see owned_by() (persistence_shuttles.dm) --
		// so a player's other characters don't see a ship one character
		// bought. Faction ships are unaffected by this.
		var/datum/db_query/q = SSdbcore.NewQuery(
			"SELECT shuttle_id, template_id, owner_ckey, owner_char_name, faction_uid, stashed, custom_name, custom_class FROM ss13_drydock_ships WHERE (owner_ckey = :ckey AND owner_char_name = :char_name) OR faction_uid = :net",
			list("ckey" = user.ckey, "char_name" = user.real_name, "net" = own_faction)
		)
		q.Execute()
		if(SSpersistence.databaseCheckQueryResult(q, "drydock ui_data select"))
			while(q.NextRow())
				var/sid = text2num(q.item[1])
				var/datum/drydock_ship/live = GLOB.drydock_ships["[sid]"]
				var/datum/map_template/drydock_ship/row_template = SSmapping.drydock_ship_templates[q.item[2]]
				var/list/row = list(
					"shuttle_id" = sid, "template_id" = q.item[2],
					"owner_ckey" = q.item[3], "owner_char_name" = q.item[4], "faction_uid" = q.item[5],
					"stashed" = text2num(q.item[6]),
					"custom_name" = q.item[7], "custom_class" = q.item[8],
					"ready" = live ? live.ready : TRUE,
					"display_name" = live ? live.display_name() : (q.item[7] || q.item[2]),
					"sub_shuttle_tags" = (row_template && length(row_template.sub_shuttle_tags)) ? row_template.sub_shuttle_tags : list()
				)
				my_shuttle_ids += sid
				if(row["owner_ckey"] == user.ckey && row["owner_char_name"] == user.real_name)
					data["personal_shuttles"] += list(row)
				else
					data["faction_shuttles"] += list(row)
		qdel(q)

	// Crew lists for every ship this user has a claim to -- one query
	// covering all of them, keyed by shuttle_id for the TGUI to look up.
	data["crew_by_ship"] = list()
	if(length(my_shuttle_ids) && SSpersistence.databaseCheckConnection("drydock ui_data crew"))
		var/datum/db_query/crewq = SSdbcore.NewQuery(
			"SELECT shuttle_id, ckey, char_name, label FROM ss13_ship_crew WHERE shuttle_id IN ([my_shuttle_ids.Join(",")])",
			list()
		)
		crewq.Execute()
		if(SSpersistence.databaseCheckQueryResult(crewq, "drydock ui_data crew select"))
			while(crewq.NextRow())
				var/sid_key = "[crewq.item[1]]"
				if(!(sid_key in data["crew_by_ship"]))
					data["crew_by_ship"][sid_key] = list()
				data["crew_by_ship"][sid_key] += list(list("ckey" = crewq.item[2], "char_name" = crewq.item[3], "label" = crewq.item[4]))
		qdel(crewq)

	data["is_admin"] = check_rights(R_ADMIN, 0, user)
	data["can_buy_faction"] = own_faction && can_configure_faction_shackle(user, own_faction, 1)

	var/board_ready_at = last_boarded_by_ckey[user.ckey] ? (last_boarded_by_ckey[user.ckey] + 30) : 0
	data["can_board"] = world.time >= board_ready_at
	data["board_cooldown"] = max(0, round((board_ready_at - world.time) / 10))
	data["can_disembark"] = !!_drydock_ship_at(GET_Z(user))

	data["templates"] = list()
	for(var/tid in SSmapping.drydock_ship_templates)
		var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[tid]
		data["templates"] += list(list(
			"template_id" = tid, "display_name" = T.name,
			"price" = T.price
		))

	return data

/datum/computer_file/program/drydock/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/user = usr

	// PDAs can now open this program at all (usage_flags above), but only
	// to board, invite someone aboard, or exit a ship -- every ownership-
	// changing action still requires a real console/laptop, which
	// usage_flags alone no longer guarantees for free.
	if(action != "board" && action != "invite_board" && action != "disembark" && istype(computer, /obj/item/modular_computer/handheld))
		to_chat(user, SPAN_WARNING("This requires a full console or laptop, not a handheld device."))
		return TRUE

	switch(action)
		if("retrieve")
			var/shuttle_id = text2num(params["shuttle_id"])
			var/obj/structure/machinery/faction_beacon/anchor = _nearby_faction_beacon()
			var/turf/from_turf = get_turf(computer)
			log_drydock("drydock ui_act: [key_name(user)] requested retrieve of shuttle_id=[shuttle_id].")
			SSpersistence.drydockRetrieve(shuttle_id, anchor, from_turf, user)
			return TRUE

		if("stash")
			var/shuttle_id = text2num(params["shuttle_id"])
			log_drydock("drydock ui_act: [key_name(user)] requested stash of shuttle_id=[shuttle_id].")
			SSpersistence.drydockStash(shuttle_id, user)
			return TRUE

		if("scuttle")
			var/shuttle_id = text2num(params["shuttle_id"])
			if(tgui_alert(user, "Permanently scuttle this ship? This costs 25000cr and cannot be undone.", "Scuttle Ship", list("Scuttle", "Cancel")) != "Scuttle")
				return TRUE
			log_drydock("drydock ui_act: [key_name(user)] requested scuttle of shuttle_id=[shuttle_id].")
			SSpersistence.drydockScuttle(shuttle_id, user)
			return TRUE

		if("board")
			log_drydock("drydock ui_act: [key_name(user)] requested Enter Ship.")
			_drydock_board_core(user, null, last_boarded_by_ckey)
			return TRUE

		if("invite_board")
			log_drydock("drydock ui_act: [key_name(user)] requested Invite to Board.")
			_drydock_invite_board_core(user, last_boarded_by_ckey)
			return TRUE

		if("disembark")
			log_drydock("drydock ui_act: [key_name(user)] requested Exit Ship.")
			_drydock_disembark_core(user)
			return TRUE

		if("sell")
			var/shuttle_id = text2num(params["shuttle_id"])
			if(!SSpersistence.databaseCheckConnection("drydock sell"))
				return TRUE
			var/datum/db_query/oq = SSdbcore.NewQuery(
				"SELECT owner_ckey, faction_uid, stashed FROM ss13_drydock_ships WHERE shuttle_id = :id",
				list("id" = shuttle_id)
			)
			oq.Execute()
			if(!SSpersistence.databaseCheckQueryResult(oq, "drydock sell lookup") || !oq.NextRow())
				qdel(oq)
				log_drydock_warning("drydock ui_act: [key_name(user)] tried to sell unknown shuttle_id=[shuttle_id].")
				return TRUE
			var/owner_ckey = oq.item[1]
			var/faction_uid = oq.item[2]
			var/stashed = text2num(oq.item[3])
			qdel(oq)
			if(!stashed)
				to_chat(user, SPAN_WARNING("Stash the ship before removing it."))
				log_drydock_warning("drydock ui_act: [key_name(user)] tried to sell shuttle_id=[shuttle_id] while it's still deployed.")
				return TRUE
			if(!(check_rights(R_ADMIN, 0, user) || owner_ckey == user.ckey || can_configure_faction_shackle(user, faction_uid, 1)))
				to_chat(user, SPAN_WARNING("You don't have permission to remove this ship."))
				log_drydock_warning("drydock ui_act: [key_name(user)] lacks permission to sell shuttle_id=[shuttle_id] (owner=[owner_ckey || "none"], faction=[faction_uid || "none"]).")
				return TRUE
			if(tgui_alert(user, "Permanently remove this ship? This cannot be undone.", "Remove Ship", list("Remove", "Cancel")) != "Remove")
				return TRUE
			var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_drydock_ships WHERE shuttle_id = :id", list("id" = shuttle_id))
			dq.Execute()
			if(SSpersistence.databaseCheckQueryResult(dq, "drydock sell delete"))
				// Purge the ship's saved interior too -- a sold ship's scope
				// must never resurrect onto some future hull that happens to
				// reuse the same shuttle_id (extremely unlikely with
				// AUTO_INCREMENT, but the purge is cheap and closes the hole
				// outright).
				SSpersistence.purgeShipScopeRows("ship:d:[shuttle_id]")
				var/datum/db_query/bdq = SSdbcore.NewQuery("DELETE FROM ss13_drydock_ships_backup WHERE shuttle_id = :id", list("id" = shuttle_id))
				bdq.Execute()
				SSpersistence.databaseCheckQueryResult(bdq, "drydock sell backup delete")
				qdel(bdq)
				var/datum/db_query/crdq = SSdbcore.NewQuery("DELETE FROM ss13_ship_crew WHERE shuttle_id = :id", list("id" = shuttle_id))
				crdq.Execute()
				SSpersistence.databaseCheckQueryResult(crdq, "drydock sell crew delete")
				qdel(crdq)
				to_chat(user, SPAN_GOOD("Ship removed."))
				log_drydock("drydock ui_act: [key_name(user)] permanently deleted shuttle_id=[shuttle_id] from the drydock DB.")
			else
				log_drydock_error("drydock ui_act: sell DB delete failed for shuttle_id=[shuttle_id].")
			qdel(dq)
			return TRUE

		if("rename_ship")
			var/shuttle_id = text2num(params["shuttle_id"])
			var/new_name = tgui_input_text(user, "New display name for this ship (blank to reset to default):", "Rename Ship", "", max_length = 64)
			if(isnull(new_name))
				return TRUE
			var/new_class = tgui_input_text(user, "New class designation (blank to reset to default):", "Rename Ship", "", max_length = 32)
			SSpersistence.drydockRename(shuttle_id, new_name, new_class || "", user)
			return TRUE

		if("rename_subship")
			var/shuttle_id = text2num(params["shuttle_id"])
			var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
			var/datum/map_template/drydock_ship/template = DS ? SSmapping.drydock_ship_templates[DS.template_id] : null
			if(!template || !length(template.sub_shuttle_tags))
				return TRUE
			var/tag = (template.sub_shuttle_tags.len == 1) ? template.sub_shuttle_tags[1] : tgui_input_list(user, "Rename which sub-ship?", "Rename Sub-ship", template.sub_shuttle_tags)
			if(!tag)
				return TRUE
			var/new_name = tgui_input_text(user, "New display name for '[tag]':", "Rename Sub-ship", tag, max_length = 64)
			if(!new_name)
				return TRUE
			SSpersistence.drydockRenameSubship(shuttle_id, tag, new_name, user)
			return TRUE

		if("add_crew")
			var/shuttle_id = text2num(params["shuttle_id"])
			var/target_ckey = tgui_input_text(user, "Ckey to add to this ship's crew:", "Add Crew", "", max_length = 32)
			if(!target_ckey)
				return TRUE
			// Crew access is scoped to one specific CHARACTER, not the whole
			// account -- see owned_by()/drydockAddCrew() (persistence_shuttles.dm)
			// -- so this needs the exact character name, not just a ckey.
			var/target_char_name = tgui_input_text(user, "Exact character name for '[target_ckey]' to grant boarding access to:", "Add Crew", "", max_length = 64)
			if(!target_char_name)
				return TRUE
			var/label = tgui_input_text(user, "Optional label (e.g. their role):", "Add Crew", "", max_length = 64)
			SSpersistence.drydockAddCrew(shuttle_id, target_ckey, target_char_name, label || "", user)
			return TRUE

		if("remove_crew")
			var/shuttle_id = text2num(params["shuttle_id"])
			SSpersistence.drydockRemoveCrew(shuttle_id, params["ckey"], params["char_name"], user)
			return TRUE

		if("buy_template")
			var/template_id = params["template_id"]
			var/as_faction = params["as_faction"] ? TRUE : FALSE
			var/obj/item/card/id/ID = user.GetIdCard()
			var/owner_ckey = null
			var/faction_uid = null
			if(as_faction)
				faction_uid = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
			else
				owner_ckey = user.ckey
			log_drydock("drydock ui_act: [key_name(user)] requested buy_template '[template_id]' ([as_faction ? "faction" : "personal"]).")
			SSpersistence.drydockBuy(template_id, owner_ckey, faction_uid, user)
			return TRUE
