/*
 * Shuttle Drydock
 * Lets a player buy/stash/retrieve/remove their own (or their faction's)
 * drydock ships from any modular computer near an active docking beacon.
 * Retrieve materializes a real Aurora ship near the beacon's overmap
 * sector -- the player flies it in themselves using its own navigation
 * console. Stash only becomes available once it's genuinely docked at a
 * registered beacon. No admin verb needed -- see
 * SSpersistence.drydockStash()/drydockRetrieve()/drydockBuy()
 * (persistence_shuttles.dm) for the actual ledger/materialization engine
 * this program calls into.
 */
/datum/computer_file/program/drydock
	filename = "drydock"
	filedesc = "Shuttle Drydock"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Buy, stash, retrieve, or remove your drydock ships."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 4
	tgui_id = "ShuttleDrydock"
	ui_auto_update = TRUE

	/// landmark_tag of the beacon this program instance is currently pointed at.
	var/selected_beacon_tag
	/// Per-ckey Enter Ship cooldown, same shape/spam-guard as the physical
	/// drydock_boarding pad's own last_boarded_by_ckey -- kept separate so
	/// the program and any physical pad don't share a single cooldown.
	var/list/last_boarded_by_ckey = list()

/datum/computer_file/program/drydock/proc/_nearby_beacons()
	. = list()
	var/turf/T = get_turf(computer)
	if(!T)
		return
	for(var/obj/structure/machinery/docking_beacon/B in world)
		if(!B.beacon_active)
			continue
		if(GET_Z(B) != T.z)
			continue
		. += B

/datum/computer_file/program/drydock/proc/_selected_beacon()
	var/list/beacons = _nearby_beacons()
	if(!length(beacons))
		return null
	if(selected_beacon_tag)
		for(var/obj/structure/machinery/docking_beacon/B in beacons)
			if(B.landmark_tag == selected_beacon_tag)
				return B
	selected_beacon_tag = beacons[1].landmark_tag
	return beacons[1]

/datum/computer_file/program/drydock/ui_data(mob/user)
	var/list/data = initial_data()

	var/list/beacons = _nearby_beacons()
	data["beacons"] = list()
	for(var/obj/structure/machinery/docking_beacon/B in beacons)
		data["beacons"] += list(list(
			"tag" = B.landmark_tag,
			"label" = B.dock_label || B.landmark_tag,
			"faction_restricted" = B.faction_restricted
		))
	var/obj/structure/machinery/docking_beacon/selected = _selected_beacon()
	data["selected_beacon"] = selected ? selected.landmark_tag : null

	var/obj/item/card/id/ID = user.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	data["own_faction_name"] = own_faction ? get_faction_name(own_faction) : null

	data["personal_shuttles"] = list()
	data["faction_shuttles"] = list()
	if(SSpersistence.databaseCheckConnection("drydock ui_data"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"SELECT shuttle_id, template_id, owner_ckey, faction_uid, stashed FROM ss13_drydock_ships WHERE owner_ckey = :ckey OR faction_uid = :net",
			list("ckey" = user.ckey, "net" = own_faction)
		)
		q.Execute()
		if(SSpersistence.databaseCheckQueryResult(q, "drydock ui_data select"))
			while(q.NextRow())
				var/list/row = list(
					"shuttle_id" = text2num(q.item[1]), "template_id" = q.item[2],
					"owner_ckey" = q.item[3], "faction_uid" = q.item[4],
					"stashed" = text2num(q.item[5])
				)
				if(row["owner_ckey"] == user.ckey)
					data["personal_shuttles"] += list(row)
				else
					data["faction_shuttles"] += list(row)
		qdel(q)

	data["is_admin"] = check_rights(R_ADMIN, 0, user)
	data["can_buy_faction"] = own_faction && can_configure_faction_shackle(user, own_faction, 1)

	var/board_ready_at = last_boarded_by_ckey[user.ckey] ? (last_boarded_by_ckey[user.ckey] + 30) : 0
	data["can_board"] = world.time >= board_ready_at
	data["board_cooldown"] = max(0, round((board_ready_at - world.time) / 10))

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

	switch(action)
		if("select_beacon")
			var/tag = params["tag"]
			for(var/obj/structure/machinery/docking_beacon/B in _nearby_beacons())
				if(B.landmark_tag == tag)
					selected_beacon_tag = tag
					log_drydock("drydock ui_act: [key_name(user)] selected beacon '[tag]'.")
					break
			return TRUE

		if("retrieve")
			var/obj/structure/machinery/docking_beacon/beacon = _selected_beacon()
			var/shuttle_id = text2num(params["shuttle_id"])
			if(!beacon)
				to_chat(user, SPAN_WARNING("No docking beacon in range."))
				log_drydock_warning("drydock ui_act: [key_name(user)] tried to retrieve shuttle_id=[shuttle_id] but no beacon is in range.")
				return TRUE
			log_drydock("drydock ui_act: [key_name(user)] requested retrieve of shuttle_id=[shuttle_id] near beacon '[beacon.landmark_tag]'.")
			SSpersistence.drydockRetrieve(shuttle_id, beacon, user)
			return TRUE

		if("stash")
			var/shuttle_id = text2num(params["shuttle_id"])
			log_drydock("drydock ui_act: [key_name(user)] requested stash of shuttle_id=[shuttle_id].")
			SSpersistence.drydockStash(shuttle_id, user)
			return TRUE

		if("board")
			log_drydock("drydock ui_act: [key_name(user)] requested Enter Ship.")
			_drydock_board_core(user, null, last_boarded_by_ckey)
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
				to_chat(user, SPAN_GOOD("Ship removed."))
				log_drydock("drydock ui_act: [key_name(user)] permanently deleted shuttle_id=[shuttle_id] from the drydock DB.")
			else
				log_drydock_error("drydock ui_act: sell DB delete failed for shuttle_id=[shuttle_id].")
			qdel(dq)
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
