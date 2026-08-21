//Get Server Status
/datum/topic_command/get_serverstatus
	name = "get_serverstatus"
	description = "Gets the server status."
	no_auth = TRUE
	// Meant to be polled frequently by external tools (server browsers,
	// Discord Rich Presence, uptime monitors) -- exempt from fail2topic so
	// normal use of those doesn't look like Topic API abuse.
	no_fail2topic = TRUE

/datum/topic_command/get_serverstatus/run_command(queryparams)
	var/list/s[] = list()
	s["version"] = GLOB.game_version
	s["mode"] = GLOB.master_mode
	s["respawn"] = GLOB.config.abandon_allowed
	s["enter"] = GLOB.config.enter_allowed
	s["vote"] = GLOB.config.allow_vote_mode
	s["ai"] = GLOB.config.allow_ai
	s["stationtime"] = worldtime2text()
	s["roundduration"] = get_round_duration_formatted()
	s["gameid"] = GLOB.round_id
	s["game_state"] = SSticker ? SSticker.current_state : 0
	s["transferring"] = GLOB.evacuation_controller?.is_evacuating()
	// FALSE for a while after the world already answers Topic queries fine --
	// SSpersistence_world_ready is deliberately the LAST subsystem to
	// Initialize() (init_order = -100, after away sites/Z-levels/faction
	// sweeps), so a poller checking only "did I get a 200" can report a
	// server as fully up several minutes before it actually is. External
	// tools (the Discord status bot) should show this as still-initializing,
	// not as live and ready.
	s["persistence_ready"] = GLOB.persistence_ready ? TRUE : FALSE

	s["players"] = GLOB.clients.len
	s["staff"] = GLOB.staff.len

	// Network-wide total across every server sharing this one's central
	// database (see docs/cross_server_persistence.md) -- omitted entirely,
	// not zero, when central_sql_enabled is off, so a non-central server's
	// response is byte-identical to before this existed, and "players"
	// above always means only this server, never the group. Cached by
	// SSstatistics.fire() once a minute, not queried live here -- this
	// endpoint is deliberately cheap and polled frequently by external
	// tools (see no_fail2topic above).
	if(GLOB.config.central_sql_enabled)
		s["central_players"] = SSstatistics.central_player_total
		s["central_server_count"] = SSstatistics.central_server_count
		// This server's own identity within the central group -- lets the
		// "Advertise to Players" embed (discord_status_bot.py's
		// post_advert()) name which specific server is asking, so two
		// different central-linked servers/shards advertising to the same
		// channel don't look identical. Omitted (not blank) when central
		// is off, same as the two fields above -- a non-central server's
		// advert embed is byte-identical to before this existed.
		if(GLOB.config.central_server_id)
			s["central_server_id"] = GLOB.config.central_server_id

	// Same three toggles the BYOND hub status block shows
	// (/world/proc/update_status(), world.dm) -- deliberately reading the exact
	// same globals so the hub and any external status tool can never disagree.
	// "enter" above is the third of them (the GATE).
	s["whitelist"] = GLOB.persistence_join_whitelist_enabled
	s["raiding"] = GLOB.faction_raiding_enabled
	// A save is the state where the server is up but unresponsive, which looks
	// identical to "fine" from the outside -- update_status() surfaces it on the
	// hub for that reason, so surface it here too.
	s["saving"] = (SSpersistence && SSpersistence.save_in_progress) ? TRUE : FALSE
	// Seconds since the last save FINISHED, or -1 if none has this round.
	//
	// "saving" on its own is close to unobservable: a full save runs ~18s and
	// pollers sample less often than that, so the flag is usually back to
	// FALSE again before anyone looks and the save goes entirely unnoticed.
	// This lets a poller spot a save it never caught in progress.
	// Pending "Advertise to Players" request, if any (persistence_advertise.dm).
	// The status bot is what actually posts it -- DM has no bot token and can
	// only reach webhook URLs, never the channel id the bot holds. Reported
	// only while unexpired, so a stale advert cannot be picked up long after
	// it stopped being true.
	var/advertising = advert_pending()
	s["advert_id"] = advertising ? GLOB.advert_id : ""
	s["advert_by"] = advertising ? GLOB.advert_by : ""
	s["advert_players"] = advertising ? GLOB.advert_players : 0

#ifdef ALLOW_CENTRAL_SHARD_SPAWNING
	// Most recent shard creation, if any -- same delivery mechanism as the
	// advert fields just above (DM has no bot token, only webhook URLs, so
	// scripts/discord_status_bot.py is what actually posts this). Unlike
	// advert_id, deliberately no expiry check here -- see GLOB.shard_advert_id's
	// own doc comment, code/modules/admin/verbs/shards.dm.
	if(GLOB.shard_advert_id)
		s["shard_advert_id"] = GLOB.shard_advert_id
		s["shard_advert_shard_id"] = GLOB.shard_advert_shard_id
		s["shard_advert_port"] = GLOB.shard_advert_port
		s["shard_advert_host"] = world.internet_address || world.address

	// Most recent start/stop, if any -- same delivery mechanism, separate
	// from shard_advert_* above (that's creation-only). See
	// GLOB.shard_lifecycle_id's own doc comment, shards.dm.
	if(GLOB.shard_lifecycle_id)
		s["shard_lifecycle_id"] = GLOB.shard_lifecycle_id
		s["shard_lifecycle_shard_id"] = GLOB.shard_lifecycle_shard_id
		s["shard_lifecycle_event"] = GLOB.shard_lifecycle_event
#endif

	s["saved_ago"] = (SSpersistence && SSpersistence.last_save_completed) \
		? round((world.realtime - SSpersistence.last_save_completed) / 10) \
		: -1

	var/admin_count = 0

	for(var/S in GLOB.staff)
		var/client/C = S
		if(C.holder.fakekey)
			continue
		if(C.holder.rights & (R_MOD|R_ADMIN))
			admin_count++

	s["admins"] = admin_count

	statuscode = 200
	response = "Server status fetched."
	data = s
	return TRUE


//Get a Staff List
/datum/topic_command/get_stafflist
	name = "get_stafflist"
	description = "Gets a list of connected staffmembers"

/datum/topic_command/get_stafflist/run_command(queryparams)
	var/list/l_staff = list()
	for (var/s in GLOB.staff)
		var/client/C = s
		l_staff[C] = C.holder.rank

	statuscode = 200
	response = "Staff list fetched"
	data = l_staff
	return TRUE

//Char Names
/datum/topic_command/get_char_list
	name = "get_char_list"
	description = "Provides a list of all characters ingame"

/datum/topic_command/get_char_list/run_command(queryparams)
	var/list/chars = list()

	var/list/mobs = sortmobs()
	for(var/mob/M in mobs)
		if(!M.ckey) continue
		chars[M.name] += M.key ? (M.client ? M.key : "[M.key] (DC)") : "No key"

	statuscode = 200
	response = "Char list fetched"
	data = chars
	return TRUE

/datum/topic_command/get_staff_by_flag
	name = "get_staff_by_flag"
	description = "Gets the list of staff, selected by flag values."
	params = list(
		"flags" = list("name"="flags","desc"="The flags to query based on.","req"=1,"type"="int"),
		"strict" = list("name"="strict","desc"="Set to 1 if you want all flags to be present on the holder.","req"=0,"type"="int"),
		"show_fakekeys" = list("name"="strict","desc"="Set to 1 if you want to show fake key holders as well.","req"=0,"type"="int")
	)

/datum/topic_command/get_staff_by_flag/run_command(queryparams)
	var/flags = text2num(queryparams["flags"])

	flags &= R_ALL

	var/strict = !!(queryparams["strict"] && (text2num(queryparams["strict"]) == 1))
	var/show_fakes = !!(queryparams["show_fakekeys"] && (text2num(queryparams["show_fakekeys"]) == 1))

	var/list/ckeys_found = list()

	for (var/client/client in GLOB.clients)
		if (!client.holder)
			continue

		if (!show_fakes && client.holder.fakekey)
			continue

		if (strict)
			if (client.holder.rights == flags)
				ckeys_found += client.ckey
		else
			if (client.holder.rights & flags)
				ckeys_found += client.ckey

	statuscode = 200
	response = "Staff count and list fetched."
	data = list(
		"ckeys" = ckeys_found
	)

	return TRUE

//Player Count
/datum/topic_command/get_count_player
	name = "get_count_player"
	description = "Gets the number of players connected"
	no_auth = TRUE
	// Same reasoning as get_serverstatus above -- cheap, public, meant for
	// frequent external polling.
	no_fail2topic = TRUE

/datum/topic_command/get_count_player/run_command(queryparams)
	var/n = 0
	for(var/mob/M in GLOB.player_list)
		if(M.client)
			n++

	statuscode = 200
	response = "Player count fetched"
	data = n
	return TRUE

//Get Ghosts
/datum/topic_command/get_ghosts
	name = "get_ghosts"
	description = "Gets the ghosts"

/datum/topic_command/get_ghosts/run_command(queryparams)
	var/list/ghosts[] = list()
	ghosts = get_ghosts(1,1)

	statuscode = 200
	response = "Fetched Ghost list"
	data = ghosts
	return TRUE

// Crew Manifest
/datum/topic_command/get_manifest
	name = "get_manifest"
	description = "Gets the crew manifest"

/datum/topic_command/get_manifest/run_command(queryparams)
	var/list/positions = list()
	var/list/set_names = list(
			"Command" = command_positions,
			"Command Support" = command_support_positions,
			"Security" = security_positions,
			"Engineering" = engineering_positions,
			"Medical" = medical_positions,
			"Science" = science_positions,
			"Operations" = cargo_positions,
			"Service" = service_positions,
			"Civilian" = civilian_positions,
			"Equipment" = nonhuman_positions
		)

	for(var/datum/record/general/R in SSrecords.records)
		var/name = R.name
		var/rank = R.rank
		var/real_rank = make_list_rank(R.real_rank)

		var/department = 0
		for(var/k in set_names)
			if(real_rank in set_names[k])
				if(!positions[k])
					positions[k] = list()
				positions[k][name] = rank
				department = 1
		if(!department)
			if(!positions["misc"])
				positions["misc"] = list()
			positions["misc"][name] = rank

	statuscode = 200
	response = "Manifest fetched"
	data = positions
	return TRUE

//Player Ckeys
/datum/topic_command/get_player_list
	name = "get_player_list"
	description = "Gets a list of connected players"
	params = list(
		"showadmins" = list("name"="show admins","desc"="A boolean to toggle whether or not hidden admins should be shown with proper or improper ckeys.","req"=0,"type"="int")
		)

/datum/topic_command/get_player_list/run_command(queryparams)
	var/show_hidden_admins = 0

	if (!isnull(queryparams["showadmins"]))
		show_hidden_admins = text2num(queryparams["showadmins"])

	var/list/players = list()
	for (var/client/C in GLOB.clients)
		if (!show_hidden_admins && C.holder?.fakekey)
			players += ckey(C.holder.fakekey)
		else
			players += C.ckey

	statuscode = 200
	response = "Player list fetched"
	data = players
	return TRUE

//Get info about a specific player
/datum/topic_command/get_player_info
	name = "get_player_info"
	description = "Gets information about a specific player"
	params = list(
		"search" = list("name"="search","desc"="List with strings that should be searched for","req"=1,"type"="lst")
		)

/datum/topic_command/get_player_info/run_command(queryparams)
	var/list/search = queryparams["search"]

	var/list/ckeysearch = list()
	for(var/text in search)
		ckeysearch += ckey(text)

	var/list/match = list()

	for(var/mob/M in GLOB.mob_list)
		var/strings = list(M.name, M.ckey)
		if(M.mind)
			strings += M.mind.assigned_role
			strings += M.mind.special_role
		for(var/text in strings)
			if(ckey(text) in ckeysearch)
				match[M] += 10 // an exact match is far better than a partial one
			else
				for(var/searchstr in search)
					if(findtext(text, searchstr))
						match[M] += 1

	var/maxstrength = 0
	for(var/mob/M in match)
		maxstrength = max(match[M], maxstrength)
	for(var/mob/M in match)
		if(match[M] < maxstrength)
			match -= M

	if(!match.len)
		statuscode = 449
		response = "No match found"
		data = null
		return TRUE
	else if(match.len == 1)
		var/mob/M = match[1]
		var/info = list()
		info["key"] = M.key
		if (M.client)
			var/client/C = M.client
			info["discordmuted"] = C.mute_discord ? "Yes" : "No"
		info["name"] = M.name == M.real_name ? M.name : "[M.name] ([M.real_name])"
		info["role"] = M.mind ? (M.mind.assigned_role ? M.mind.assigned_role : "No role") : "No mind"
		var/turf/MT = get_turf(M)
		info["loc"] = M.loc ? "[M.loc]" : "null"
		info["turf"] = MT ? "[MT] @ [MT.x], [MT.y], [MT.z]" : "null"
		info["area"] = MT ? "[MT.loc]" : "null"
		info["antag"] = M.mind ? (M.mind.special_role ? M.mind.special_role : "Not antag") : "No mind"
		info["hasbeenrev"] = M.mind ? M.mind.has_been_rev : "No mind"
		info["stat"] = M.stat
		info["type"] = M.type
		if(isliving(M))
			var/mob/living/L = M
			info["damage"] = list2params(list(
						oxy = L.getOxyLoss(),
						tox = L.getToxLoss(),
						fire = L.getFireLoss(),
						brute = L.getBruteLoss(),
						clone = L.getCloneLoss(),
						brain = L.getBrainLoss()
					))
		else
			info["damage"] = "non-living"
		info["gender"] = M.gender
		statuscode = 200
		response = "Client data fetched"
		data = info
		return TRUE
	else
		statuscode = 449
		response = "Multiple Matches found"
		data = null
		return TRUE
