/*
 * Faction Chat
 * IRC-style live chat scoped to a faction's registered membership -- a real
 * faction-issued ID with a roster row, not just a printed civilian card.
 * PDA pings reach the current holder of any device with this program
 * installed, whether or not the window is open.
 */
/datum/computer_file/program/faction_chat
	filename = "factionchat"
	filedesc = "Faction Chat"
	program_icon_state = "generic"
	program_key_icon_state = "yellow_key"
	extended_desc = "Chat live with other members of your faction."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 4
	tgui_id = "FactionChat"
	ui_auto_update = TRUE

	var/page = 0
	/// ckey -> world.time of last message, flood cooldown.
	var/static/list/last_sent_by_ckey = list()

/// Strict membership check -- requires both a faction-issued ID AND a real
/// roster row, not just a printed card (a default civilian ID has no
/// employer_faction at all and fails at the first check).
/datum/computer_file/program/faction_chat/proc/_member_net(mob/user)
	var/obj/item/card/id/ID = user.GetIdCard()
	if(!ID || !ID.employer_faction)
		return null
	var/net = normalize_faction_uid(ID.employer_faction)
	if(!get_faction_member(user.ckey, net))
		return null
	return net

/datum/computer_file/program/faction_chat/ui_data(mob/user)
	var/list/data = initial_data()
	var/net = _member_net(user)
	data["is_member"] = !!net
	data["faction_name"] = net ? get_faction_name(net) : null
	data["page"] = page
	data["messages"] = list()
	data["db_error"] = FALSE
	if(net)
		if(!SSpersistence.databaseCheckConnection("faction chat ui_data"))
			data["db_error"] = TRUE
		else
			var/datum/db_query/q = SSdbcore.NewQuery(
				"SELECT sender_name, message, sent_at FROM ss13_faction_chat WHERE faction_uid = :net ORDER BY msg_id DESC LIMIT 50 OFFSET :off",
				list("net" = net, "off" = page * 50)
			)
			q.Execute()
			if(SSpersistence.databaseCheckQueryResult(q, "faction chat select"))
				while(q.NextRow())
					data["messages"] += list(list("sender" = q.item[1], "message" = q.item[2], "sent_at" = q.item[3]))
			else
				data["db_error"] = TRUE
			qdel(q)
	return data

/datum/computer_file/program/faction_chat/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/user = usr
	switch(action)
		if("send")
			var/net = _member_net(user)
			if(!net)
				to_chat(user, SPAN_WARNING("You need a faction-issued ID with a real job assignment to use this."))
				return TRUE
			if(last_sent_by_ckey[user.ckey] && (world.time - last_sent_by_ckey[user.ckey] < 20))
				to_chat(user, SPAN_WARNING("You're sending messages too quickly -- wait a moment."))
				return TRUE
			var/message = sanitize(params["message"], 512)
			if(!message || !length(message))
				to_chat(user, SPAN_WARNING("Message cannot be empty."))
				return TRUE
			last_sent_by_ckey[user.ckey] = world.time
			var/sender_name = user.real_name || "Unknown"
			if(!SSpersistence.databaseCheckConnection("faction chat send"))
				to_chat(user, SPAN_WARNING("Database connection failed -- message not sent."))
				return TRUE
			var/datum/db_query/iq = SSdbcore.NewQuery(
				"INSERT INTO ss13_faction_chat (faction_uid, sender_name, sender_ckey, message) VALUES (:net, :name, :ckey, :msg)",
				list("net" = net, "name" = sender_name, "ckey" = user.ckey, "msg" = message)
			)
			iq.Execute()
			if(!SSpersistence.databaseCheckQueryResult(iq, "faction chat insert"))
				to_chat(user, SPAN_WARNING("Database error -- message not sent."))
				qdel(iq)
				return TRUE
			qdel(iq)
			_deliver_pings(net, sender_name, message)
			return TRUE
		if("next_page")
			page++
			return TRUE
		if("prev_page")
			page = max(0, page - 1)
			return TRUE

/// Holder-based delivery: only currently-carried PDAs whose holder is a
/// verified member of this faction get pinged. A PDA on a table, or held by
/// a non-member, gets nothing.
/datum/computer_file/program/faction_chat/proc/_deliver_pings(net, sender_name, message)
	for(var/obj/item/modular_computer/MC in world)
		if(!get_turf(MC))
			continue
		if(!MC.enabled || !MC.computer_use_power())
			continue
		if(!MC.hard_drive || !MC.hard_drive.find_file_by_name("factionchat"))
			continue
		var/mob/holder = MC.get_holding_mob()
		if(!holder)
			continue
		if(_member_net(holder) != net)
			continue
		// message_range=0 -- private to_chat() straight to the holder
		// (output_message()'s message_range==0 branch), not an audible
		// broadcast anyone standing nearby could also see/hear.
		MC.get_notification("[sender_name]: [message]", 0, "Faction Chat")
		CHECK_TICK
