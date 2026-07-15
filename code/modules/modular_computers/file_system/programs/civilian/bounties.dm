/*
 * Bounties Board
 * Players post a cash bounty on a specific character (escrowed from their
 * personal account, see post_bounty()); anyone can accept an open bounty;
 * landing the killing blow on the target automatically pays the bounty to
 * the accepter's personal account (check_bounty_kill(), hooked from
 * /mob/living/carbon/human/death()). Single-accepter-at-a-time -- once
 * accepted, no one else can also accept the same bounty.
 */

/datum/computer_file/program/civilian/bounties
	filename = "bounties"
	filedesc = "Bounties Board"
	program_icon_state = "generic"
	program_key_icon_state = "red_key"
	extended_desc = "Post a cash bounty on a person, or browse and accept open bounties."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_TABLET
	requires_ntnet = FALSE
	size = 4
	tgui_id = "Bounties"
	ui_auto_update = TRUE

	var/status_message = ""

/datum/computer_file/program/civilian/bounties/ui_data(mob/user)
	var/list/data = initial_data()
	data["status_message"] = status_message
	data["my_ckey"] = user.ckey

	var/list/bounty_list = list()
	for(var/list/row in GLOB.active_bounties)
		bounty_list += list(list(
			"id"            = row["id"],
			"target_name"   = row["target_name"],
			"reward"        = row["reward"],
			"status"        = row["status"],
			"poster_ckey"   = row["poster_ckey"],
			"accepter_ckey" = row["accepter_ckey"]
		))
	data["bounties"] = bounty_list
	return data

/datum/computer_file/program/civilian/bounties/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/living/carbon/human/user = usr
	if(!istype(user))
		return TRUE

	switch(action)
		if("post_bounty")
			var/target_name = tgui_input_text(user, "Name of the character to put a bounty on:", "Post Bounty", "", max_length = 128)
			if(!target_name)
				return TRUE
			var/list/matches = list()
			for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
				if(H.real_name == target_name && H.ckey)
					matches += H
			if(!length(matches))
				status_message = "No character named '[target_name]' found this round."
				return TRUE
			var/mob/living/carbon/human/target
			if(length(matches) == 1)
				target = matches[1]
			else
				// Same displayed name, different ckeys -- disambiguate by ckey.
				var/list/pick_choices = list()
				for(var/mob/living/carbon/human/H in matches)
					pick_choices["[target_name] (played by [H.ckey])"] = H
				var/pick = tgui_input_list(user, "Multiple characters named '[target_name]' found -- which one?", "Post Bounty", pick_choices)
				if(!pick)
					return TRUE
				target = pick_choices[pick]
			if(target == user)
				status_message = "You cannot put a bounty on yourself."
				return TRUE
			var/reward = tgui_input_number(user, "Bounty reward (credits):", "Post Bounty", 1000, 1000000, 1)
			if(isnull(reward) || reward <= 0)
				return TRUE
			var/list/new_row = post_bounty(user, target.ckey, target.real_name, reward)
			if(new_row)
				status_message = "Posted a [reward] cr bounty on [target.real_name]."
				log_and_message_admins("[key_name(user)] posted a [reward] cr bounty on '[target.real_name]' via Bounties Board.")
			else
				status_message = "Failed to post bounty -- check you have a linked account with sufficient funds."
			return TRUE

		if("accept_bounty")
			var/bounty_id = text2num(params["id"])
			if(!bounty_id)
				return TRUE
			if(accept_bounty(bounty_id, user.ckey))
				status_message = "Bounty accepted. Kill the target to collect the reward."
			else
				status_message = "Failed to accept -- it may already be taken."
			return TRUE

		if("cancel_bounty")
			var/bounty_id = text2num(params["id"])
			if(!bounty_id)
				return TRUE
			var/list/row = get_bounty_by_id(bounty_id)
			if(!row || row["poster_ckey"] != user.ckey)
				status_message = "You can only cancel bounties you posted."
				return TRUE
			if(cancel_bounty(bounty_id))
				status_message = "Bounty cancelled and refunded."
			else
				status_message = "Failed to cancel."
			return TRUE
