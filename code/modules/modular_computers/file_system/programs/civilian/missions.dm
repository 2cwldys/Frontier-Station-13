/*
 * Missions Board
 * Browse admin-authored missions (fetch-item or kill-NPC) and accept one.
 * Single-claim-at-a-time -- once accepted, that mission is locked to you
 * until you complete, abandon it, or an admin frees it. Kill missions spawn
 * their targets only once you actually reach the target sector (see
 * /datum/mission_instance, persistence_missions.dm), and require turning in
 * away from the sector once every target is dead (objective_complete) --
 * same as fetch missions, which are completed by turning in the required
 * items via this same program. Turning in specifically requires a full
 * console or laptop -- a handheld/tablet can still browse, accept, and
 * abandon, but not turn in (see the hardware check in ui_act() below).
 */

/datum/computer_file/program/civilian/missions
	filename = "missions"
	filedesc = "Missions Board"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Browse and accept fetch/kill missions, or turn in a completed fetch mission."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_TABLET
	requires_ntnet = FALSE
	size = 2
	tgui_id = "Missions"
	ui_auto_update = TRUE

	var/status_message = ""

/datum/computer_file/program/civilian/missions/ui_data(mob/user)
	var/list/data = initial_data()
	data["status_message"] = status_message
	data["my_ckey"] = user.ckey

	var/list/mission_list = list()
	for(var/list/tmpl in GLOB.mission_templates)
		if(!tmpl["enabled"])
			continue
		var/datum/mission_instance/instance = tmpl["instance"]
		mission_list += list(list(
			"id"                 = tmpl["id"],
			"mission_type"       = tmpl["mission_type"],
			"title"              = tmpl["title"],
			"description"        = tmpl["description"],
			"fetch_count"        = tmpl["fetch_count"],
			"kill_count"         = tmpl["kill_count"],
			"sector_template_id" = tmpl["sector_template_id"],
			"reward"             = tmpl["reward"],
			"claimed_by_me"      = (tmpl["current_accepter_ckey"] == user.ckey),
			"claimed"            = !!tmpl["current_accepter_ckey"],
			"objective_complete" = (istype(instance) && instance.objective_complete)
		))
	data["missions"] = mission_list
	return data

/datum/computer_file/program/civilian/missions/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/living/carbon/human/user = usr
	if(!istype(user))
		return TRUE

	switch(action)
		if("accept_mission")
			var/template_id = text2num(params["id"])
			if(!template_id)
				return TRUE
			if(accept_mission(template_id, user))
				status_message = "Mission accepted."
			else
				status_message = "Failed to accept -- it may already be taken, disabled, or its target sector isn't currently loaded."
			return TRUE

		if("turn_in_mission")
			if(istype(computer, /obj/item/modular_computer/handheld))
				status_message = "Turning in a mission requires a full console or laptop -- your handheld can only track progress."
				return TRUE
			var/template_id = text2num(params["id"])
			if(!template_id)
				return TRUE
			var/list/tmpl = get_mission_template(template_id)
			if(!tmpl)
				return TRUE
			var/success = (tmpl["mission_type"] == "fetch") ? turn_in_fetch_mission(template_id, user) : turn_in_kill_mission(template_id, user)
			if(success)
				status_message = "Mission turned in. Reward paid."
			else if(tmpl["mission_type"] == "fetch")
				status_message = "You don't have the required items, or this isn't your mission to turn in."
			else
				status_message = "Can't turn in yet -- make sure every target is eliminated and you've left the sector."
			return TRUE

		if("abandon_mission")
			var/template_id = text2num(params["id"])
			if(!template_id)
				return TRUE
			var/list/tmpl = get_mission_template(template_id)
			if(!tmpl || tmpl["current_accepter_ckey"] != user.ckey)
				status_message = "You can only abandon your own accepted missions."
				return TRUE
			if(abandon_mission(template_id))
				status_message = "Mission abandoned."
			else
				status_message = "Failed to abandon."
			return TRUE
