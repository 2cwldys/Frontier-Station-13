//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:33

/mob/abstract/new_player
	var/ready = 0
	var/spawning = 0 //Referenced when you want to delete the new_player later on in the code
	var/datum/late_choices/late_choices_ui = null
	universal_speak = 1

	invisibility = 101

	density = FALSE
	stat = DEAD
	canmove = 0

	anchored = 1	//  don't get pushed around
	simulated = FALSE

	var/last_ready_name // This has to be saved because the client is nulled prior to Logout()

INITIALIZE_IMMEDIATE(/mob/abstract/new_player)

/mob/abstract/new_player/Initialize(mapload)
	. = ..()
	GLOB.dead_mob_list -= src
	attempt_moving_new_player_on_marker_turf()

/mob/abstract/new_player/proc/attempt_moving_new_player_on_marker_turf()
	//If it's set, move the new_player mob to it, otherwise reschedule to check in a bit
	if(istype(GLOB.lobby_mobs_location))
		src.forceMove(GLOB.lobby_mobs_location)

	else
		//Atoms loading have finished supposedly, there should be a marker down for this, if not found throw a stack trace
		if(SSATOMS_IS_PROBABLY_DONE)
			stack_trace("The map is supposedly loaded, but GLOB.lobby_mobs_location is not set, unable to move the lobby mob!")
			return

		addtimer(CALLBACK(src, PROC_REF(attempt_moving_new_player_on_marker_turf)), 5 SECONDS, TIMER_STOPPABLE | TIMER_DELETE_ME)

/mob/abstract/new_player/Destroy()
	QDEL_NULL(late_choices_ui)
	return ..()

/mob/abstract/new_player/get_status_tab_items()
	. = ..()

	if(!istype(SSticker))
		return

	if(SSticker.hide_mode == ROUNDTYPE_SECRET)
		. += "Game Mode: Secret"
	else if (SSticker.hide_mode == ROUNDTYPE_MIXED_SECRET)
		. += "Game Mode: Mixed Secret"
	else
		. += "Game Mode: [GLOB.master_mode]" // Old setting for showing the game mode

	if(SSticker.current_state == GAME_STATE_PREGAME)
		. += "Time To Start: [SSticker.pregame_timeleft][GLOB.round_progressing ? "" : " (DELAYED)"]"
		. += "Players: [length(GLOB.player_list)] Players Ready: [SSticker.total_players_ready]"
		if(LAZYLEN(SSticker.ready_player_jobs))
			. += ""
			. += ""
			. += "Group antagonists ready:"

			var/list/ready_special_roles = list()

			//Get the list of all the players, if they are ready, get their special roles (aka antagonists) preferences and count them up in a list
			for(var/mob/abstract/new_player/player in GLOB.player_list)
				if(!player.ready)
					continue
				for(var/special_role in player?.client?.prefs?.be_special_role)
					ready_special_roles[special_role] += 1

			//Get the list of all antagonist types, if they require more than one person to spawn, check that there's at least one candidate and if so list the number of candidates for it
			for(var/antag_type in GLOB.all_antag_types)
				var/datum/antagonist/possible_antag_type = GLOB.all_antag_types[antag_type]

				if(possible_antag_type.initial_spawn_req > 1)
					if(ready_special_roles[possible_antag_type.role_type])
						. += "[possible_antag_type.role_text_plural]: [ready_special_roles[possible_antag_type.role_type]]"


			. += ""
			. += ""
			. += "Characters ready:"
			for(var/dept in SSticker.ready_player_jobs)
				if(LAZYLEN(SSticker.ready_player_jobs[dept]))
					. += "[uppertext(dept)]"
				for(var/char in SSticker.ready_player_jobs[dept])
					. += "[copytext_char(char, 1, 18)]: [SSticker.ready_player_jobs[dept][char]]"


/mob/abstract/new_player/Topic(href, href_list[])
	if(!client)	return 0

	if(href_list["show_preferences"])
		to_chat(src, SPAN_WARNING("Character setup is only available when creating a new character from the main menu."))
		return 1

	if(href_list["ready"])
		if(SSticker.current_state <= GAME_STATE_PREGAME) // Make sure we don't ready up after the round has started
			// Cannot join without a saved character, if we're on SQL saves.
			if (GLOB.config.sql_saves && !client.prefs.current_character)
				alert(src, "You have not saved your character yet. Please do so before readying up.")
				return
			if(client.unacked_warning_count > 0)
				alert(src, "You can not ready up, because you have unacknowledged warnings or notifications. Acknowledge them in OOC->Warnings and Notifications.")
				return

			var/new_ready_state = text2num(href_list["ready"])

			if(SSticker.prevent_unready && new_ready_state == FALSE)
				tgui_alert(src, "You may not unready during Odyssey setup!", "Odyssey")
				return

			ready = new_ready_state
		else
			ready = 0

	if(href_list["observe"])
		new_player_observe()
		return TRUE

	if(href_list["late_join"])

		if(SSticker.current_state != GAME_STATE_PLAYING)
			to_chat(usr, SPAN_WARNING("The round is either not ready, or has already finished..."))
			return

		// Cannot join without a saved character, if we're on SQL saves.
		if (GLOB.config.sql_saves && !client.prefs.current_character)
			alert(src, "You have not saved your character yet. Please do so before attempting to join.")
			return

		if(!check_rights(R_ADMIN, 0))
			var/datum/species/S = GLOB.all_species[client.prefs.species]
			if((S.spawn_flags & IS_WHITELISTED) && !is_alien_whitelisted(src, client.prefs.species) && GLOB.config.usealienwhitelist)
				to_chat(usr, SPAN_DANGER("You are currently not whitelisted to play [client.prefs.species]."))
				return 0

			if(!(S.spawn_flags & CAN_JOIN))
				to_chat(usr, SPAN_DANGER("Your current species, [client.prefs.species], is not available for play on the [station_name(TRUE)]."))
				return 0

		PersistentAutoSpawn()

	if(href_list["manifest"])
		ViewManifest()

	if(href_list["ghostspawner"])
		if(!ROUND_IS_STARTED)
			to_chat(usr, SPAN_WARNING("The round hasn't started yet!"))
			return
		SSghostroles.ui_interact(usr)

	if(href_list["SelectedJob"])

		if(!GLOB.config.enter_allowed)
			to_chat(usr, SPAN_NOTICE("There is an administrative lock on entering the game!"))
			return
		else if(SSticker.mode && SSticker.mode.explosion_in_progress)
			to_chat(usr, SPAN_DANGER("The [station_name(TRUE)] is currently exploding. Joining would go poorly."))
			return

		if(client.unacked_warning_count > 0)
			alert(usr, "You can not join the game, because you have unacknowledged warnings or notifications. Acknowledge them in OOC->Warnings and Notifications.")
			return

		var/datum/species/S = GLOB.all_species[client.prefs.species]
		if((S.spawn_flags & IS_WHITELISTED) && !is_alien_whitelisted(src, client.prefs.species) && GLOB.config.usealienwhitelist)
			to_chat(usr, SPAN_DANGER("You are currently not whitelisted to play [client.prefs.species]."))
			return 0

		if(!(S.spawn_flags & CAN_JOIN))
			to_chat(usr, SPAN_DANGER("Your current species, [client.prefs.species], is not available for play on the [station_name(TRUE)]."))
			return 0

		AttemptLateSpawn(href_list["SelectedJob"],client.prefs.spawnpoint)
		return

	if(!ready && href_list["preference"])
		if(client)
			client.prefs.process_link(src, href_list)

	if(href_list["showpoll"])
		handle_player_polling()
		return

	if(href_list["showpolllink"])
		show_poll_link(href_list["showpolllink"])
		return

	if(href_list["pollid"])

		var/pollid = href_list["pollid"]
		if(istext(pollid))
			pollid = text2num(pollid)
		if(isnum(pollid))
			src.poll_player(pollid)
		return

	if(href_list["votepollid"] && href_list["votetype"])
		var/pollid = text2num(href_list["votepollid"])
		var/votetype = href_list["votetype"]
		switch(votetype)
			if("OPTION")
				var/optionid = text2num(href_list["voteoptionid"])
				vote_on_poll(pollid, optionid)
			if("TEXT")
				var/replytext = href_list["replytext"]
				log_text_poll_reply(pollid, replytext)
			if("NUMVAL")
				var/id_min = text2num(href_list["minid"])
				var/id_max = text2num(href_list["maxid"])

				if( (id_max - id_min) > 100 )	//Basic exploit prevention
					to_chat(usr, "The option ID difference is too big. Please contact administration or the database admin.")
					return

				for(var/optionid = id_min; optionid <= id_max; optionid++)
					if(!isnull(href_list["o[optionid]"]))	//Test if this optionid was replied to
						var/rating
						if(href_list["o[optionid]"] == "abstain")
							rating = null
						else
							rating = text2num(href_list["o[optionid]"])
							if(!isnum(rating))
								return

						vote_on_numval_poll(pollid, optionid, rating)
			if("MULTICHOICE")
				var/id_min = text2num(href_list["minoptionid"])
				var/id_max = text2num(href_list["maxoptionid"])

				if( (id_max - id_min) > 100 )	//Basic exploit prevention
					to_chat(usr, "The option ID difference is too big. Please contact administration or the database admin.")
					return

				for(var/optionid = id_min; optionid <= id_max; optionid++)
					if(!isnull(href_list["option_[optionid]"]))	//Test if this optionid was selected
						vote_on_poll(pollid, optionid, 1)

/mob/abstract/new_player/proc/IsJobAvailable(rank)
	var/datum/job/job = SSjobs.GetJob(rank)
		// Check if the job is open in-round.
	if (!job || !job.is_position_available() \
			/* check for job bans */\
		|| jobban_isbanned(src,rank) \
			/* check for species blacklists */\
		|| (job.blacklisted_species && (GLOB.all_species[client.prefs.species].name in job.blacklisted_species)) \
			/* check for citizenship restrictions */\
		|| job.blacklisted_citizenship && (astype(SSrecords.citizenships[client.prefs.citizenship], /datum/citizenship).name in job.blacklisted_citizenship))
		return FALSE

	// Checks for faction requirements.
	var/datum/faction/faction = SSjobs.name_factions[client.prefs.faction] || SSjobs.default_faction
	var/list/faction_allowed_roles = unpacklist(faction.allowed_role_types)
	if (!(job.type in faction_allowed_roles) \
		|| !faction.can_select(client.prefs,src) \
		|| !(client.prefs.GetPlayerAltTitle(job) in client.prefs.GetValidTitles(job)))
		return FALSE

	// Checks for skill requirements.
	for (var/key,value in job.skill_requirements)
		if (key && client.prefs.skills[key] < value)
			return FALSE

	return TRUE

/mob/abstract/new_player/proc/AttemptLateSpawn(rank,var/spawning_at)
	if(src != usr)
		return 0
	if(SSticker.current_state != GAME_STATE_PLAYING)
		to_chat(usr, SPAN_WARNING("The round is either not ready, or has already finished..."))
		return 0
	if(!GLOB.config.enter_allowed)
		to_chat(usr, SPAN_NOTICE("There is an administrative lock on entering the game!"))
		return 0
	if(GLOB.config.sql_saves && !client.prefs.current_character)
		alert(usr, "You have not saved your character yet. Please do so before attempting to join.")
		return 0
	if(!IsJobAvailable(rank))
		to_chat(usr, SPAN_NOTICE("[rank] is not available. Please try another."))
		return 0
	if(!(spawning_at in SSatlas.current_map.allowed_spawns))
		to_chat(usr, SPAN_NOTICE("Spawn location [spawning_at] invalid for [SSatlas.current_map]. Defaulting to [SSatlas.current_map.default_spawn]."))
		spawning_at = SSatlas.current_map.default_spawn

	spawning = 1
	close_spawn_windows()

	SSjobs.AssignRole(src, rank, 1)

	var/mob/living/character = create_character()	//creates the human and transfers vars and mind

	equip_custom_items(character, body_only = TRUE) // Equips body-related custom items, like augments and prosthetics.
	SSjobs.EquipAugments(character, character.client.prefs)
	character = SSjobs.EquipRank(character, rank, TRUE, spawning_at)					//equips the human
	equip_custom_items(character, body_only = FALSE) // Equips all other custom items.

	// AIs don't need a spawnpoint, they must spawn at an empty core
	if(character.mind.assigned_role == "AI")

		character = character.AIize(move=0) // AIize the character, but don't move them yet

		// IsJobAvailable for AI checks that there is an empty core available in this list
		var/obj/structure/AIcore/deactivated/C = GLOB.empty_playable_ai_cores[1]
		GLOB.empty_playable_ai_cores -= C

		character.forceMove(C.loc)
		character.eyeobj.forceMove(C.loc)

		AnnounceCyborg(character, rank, "has been downloaded to the empty core in \the [character.loc.loc]")
		SSticker.mode.handle_latejoin(character)

		qdel(C)
		qdel(src)
		return

	//Find our spawning point.
	var/join_message = SSjobs.LateSpawn(character, rank)

	character.lastarea = get_area(loc)
	// Moving wheelchair if they have one
	if(character.buckled_to && istype(character.buckled_to, /obj/structure/bed/stool/chair/office/wheelchair))
		character.buckled_to.forceMove(character.loc)
		character.buckled_to.set_dir(character.dir)

	SSticker.mode.handle_latejoin(character)
	GLOB.universe.OnPlayerLatejoin(character)
	if(SSjobs.ShouldCreateRecords(character.mind))
		if(character.mind.assigned_role != "Cyborg")
			SSrecords.generate_record(character)
			SSticker.minds += character.mind//Cyborgs and AIs handle this in the transform proc.	//TODO!!!!! ~Carn

		//Grab some data from the character prefs for use in random news procs.

			AnnounceArrival(character, rank, join_message)
			announce_faction_cryo_exit(character)
		else
			AnnounceCyborg(character, rank, join_message)

	qdel(src)

/mob/abstract/new_player/proc/AnnounceCyborg(var/mob/living/character, var/rank, var/join_message)
	if (SSticker.current_state == GAME_STATE_PLAYING)
		if(character.mind.role_alt_title)
			rank = character.mind.role_alt_title
		// can't use their name here, since cyborg namepicking is done post-spawn, so we'll just say "A new Cyborg has arrived"/"A new Robot has arrived"/etc.
		GLOB.global_announcer.autosay("A new[rank ? " [rank]" : " visitor" ] [join_message ? join_message : "has arrived on the [SSatlas.current_map.station_type]"].", "Arrivals Announcer")

/mob/abstract/new_player/proc/LateChoices()
	if(!istype(late_choices_ui))
		late_choices_ui = new(src)
	else // if the UI exists force refresh it
		SStgui.update_uis(late_choices_ui)
	late_choices_ui.ui_interact(src)

/mob/abstract/new_player/proc/create_character()
	spawning = 1
	close_spawn_windows()

	var/mob/living/carbon/human/new_character

	var/use_species_name
	var/datum/species/chosen_species
	if(client.prefs.species)
		chosen_species = GLOB.all_species[client.prefs.species]
		use_species_name = chosen_species.get_station_variant() //Only used by pariahs atm.

	if(chosen_species && use_species_name)
		// Have to recheck admin due to no usr at roundstart. Latejoins are fine though.
		if(is_species_whitelisted(chosen_species) || has_admin_rights())
			new_character = new(GLOB.newplayer_start, use_species_name)

	if(!new_character)
		new_character = new(GLOB.newplayer_start)

	new_character.lastarea = get_area(loc)

	for(var/lang in client.prefs.alternate_languages)
		var/datum/language/chosen_language = GLOB.all_languages[lang]
		if(chosen_language)
			if(!GLOB.config.usealienwhitelist || !(chosen_language.flags & WHITELISTED) || is_alien_whitelisted(src, lang) || has_admin_rights() \
				|| (new_character.species && (chosen_language.name in new_character.species.secondary_langs)))
				new_character.add_language(lang)

	if(SSticker.random_players)
		new_character.gender = pick(MALE, FEMALE)
		client.prefs.real_name = random_name(new_character.gender)
		client.prefs.randomize_appearance_for(new_character)
	else
		client.prefs.copy_to(new_character)

	client.autohiss_mode = client.prefs.autohiss_setting

	src.stop_sound_channel(CHANNEL_LOBBYMUSIC) // MAD JAMS cant last forever yo)

	if(mind)
		mind.active = 0					//we wish to transfer the key manually
		mind.original = new_character
		mind.transfer_to(new_character)					//won't transfer key since the mind is not active

	new_character.name = real_name
	new_character.dna.ready_dna(new_character)
	new_character.dna.b_type = client.prefs.b_type
	new_character.sync_organ_dna()
	new_character.fixblood() // now that dna is set
	if(client.prefs.disabilities & NEARSIGHTED)
		// Set defer to 1 if you add more crap here so it only recalculates struc_enzymes once. - N3X
		new_character.dna.SetSEState(GLASSESBLOCK,1,0)

	// And uncomment this, too.
	//new_character.dna.UpdateSE()

	// Do the initial caching of the player's body icons.
	new_character.force_update_limbs()
	new_character.update_eyes()
	new_character.regenerate_icons()

	client.prefs.log_character(new_character)

	new_character.key = key		//Manually transfer the key to log them in

	new_character.client.init_verbs()

	return new_character

/**
 * Persistent-world spawn: bypasses job selection entirely.
 * Shows a character selection menu for players with multiple saved characters,
 * auto-selects for single-character players, and spawns fresh for first-timers.
 * Called in place of LateChoices() for all normal joins.
 */
/mob/abstract/new_player/proc/PersistentAutoSpawn(selected_from_menu = null)
	set waitfor = FALSE
	// This is a long, fully synchronous chain (record generation, inventory/
	// identity restore, DB lookups) called directly from ui_act("play") --
	// without waitfor=FALSE, any slow step in it (worse under DB/connection
	// contention) blocks the ENTIRE server for every player, not just this
	// one, until it returns. The caller doesn't use the return value or touch
	// NP/character afterward, so running this async is safe here.
	if(!GLOB.persistence_ready)
		to_chat(src, SPAN_WARNING("The server is still loading. Please wait a moment and try again."))
		return

	if(SSpersistence.save_in_progress)
		to_chat(src, SPAN_WARNING("Cannot join server while a save is in progress."))
		return

	if(!GLOB.config.enter_allowed && !check_rights(R_ADMIN, 0))
		to_chat(src, SPAN_NOTICE("Joining is currently disabled by an administrator."))
		return

	if(!persistence_is_whitelisted(ckey) && !check_rights(R_ADMIN, 0))
		to_chat(src, SPAN_WARNING("You are not whitelisted to join this server. Contact an administrator."))
		return

	if(SSticker.current_state != GAME_STATE_PLAYING)
		to_chat(src, SPAN_WARNING("The round is not ready yet."))
		return

	// Species whitelist check
	if(!check_rights(R_ADMIN, 0))
		var/datum/species/sp = GLOB.all_species[client.prefs.species]
		if(sp)
			if((sp.spawn_flags & IS_WHITELISTED) && !is_alien_whitelisted(src, client.prefs.species) && GLOB.config.usealienwhitelist)
				to_chat(src, SPAN_DANGER("You are not whitelisted to play [client.prefs.species]."))
				return
			if(!(sp.spawn_flags & CAN_JOIN))
				to_chat(src, SPAN_DANGER("[client.prefs.species] is not available for play on the [station_name(TRUE)]."))
				return

	// Close the character-select window NOW, while this mob still owns the
	// client -- the rejoin paths below reassign the key before ui_act() gets
	// a chance to close it, which strands the physical window on the player's
	// screen being fed null-client (1-slot, empty) data forever. Also flags
	// spawning for the legacy Topic("late_join") entry path so the menu's
	// ui_close reopen timer can't fire mid-spawn.
	if(persistent_menu_datum)
		persistent_menu_datum.spawning = TRUE
		SStgui.close_uis(persistent_menu_datum)

	var/ckey_lower = ckey(client.ckey)

	// Live lace_mob reconnect -- a captured consciousness the player never got
	// resleeved before disconnecting. Must be checked BEFORE the cryo/live-body
	// loops below: extraction moves the mind OUT of the corpse and into this
	// lace_mob, so the corpse itself has no mind left to reconnect to.
	for(var/mob/living/carbon/lace_mob/LM in GLOB.dead_mob_list)
		if(LM.key || QDELETED(LM))
			continue
		var/obj/item/organ/internal/neural_lace/lace = LM.neural_lace
		if(!lace || QDELETED(lace) || ckey(lace.registered_ckey) != ckey_lower)
			continue
		if(selected_from_menu && lace.registered_name != selected_from_menu)
			continue
		LM.key = client.ckey
		LM.stop_sound_channel(CHANNEL_LOBBYMUSIC)
		to_chat(LM, SPAN_NOTICE("You regain your bearings. Your consciousness remains within your neural lace."))
		log_subsystem_persistence_info("Cryo: [lace.registered_name] ([ckey_lower]) reconnected to a live lace_mob.")
		qdel(src)
		return

	// Check if their cryo'd mob is still in the world — if so, rejoin it immediately
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.persistence_in_cryo)
			continue
		if(ckey(H.persistence_stored_ckey) == ckey_lower || ckey(H.ckey) == ckey_lower)
			// Player explicitly selected a different character — skip this cryo'd mob
			if(selected_from_menu && H.real_name != selected_from_menu)
				continue
			H.persistence_in_cryo = FALSE
			if(H.persistence_cryo_timer)
				deltimer(H.persistence_cryo_timer)
				H.persistence_cryo_timer = null
			H.key = client.ckey
			H.stop_sound_channel(CHANNEL_LOBBYMUSIC) // Lobby music doesn't stop on its own when persistent-spawning into the world -- see create_character()'s equivalent call
			if(H.stat == DEAD)
				// Dead-in-body: reattach without waking them -- they're a corpse awaiting rescue/extraction.
				to_chat(H, SPAN_NOTICE("Your awareness stirs within your dead body. You cannot move or act -- you can only observe. Seek rescue."))
				log_subsystem_persistence_info("Cryo: [H.real_name] ([ckey_lower]) reconnected to their dead body.")
			else
				// Wake inside their last-used pod if it's still valid, otherwise an
				// available pod (faction -> public). NOTE: H.key was assigned above,
				// which moved the client OFF this new_player mob -- src.client
				// is null from here on, so only ckey_lower may be used.
				var/obj/structure/machinery/cryopod/spawn_pod = persistence_find_saved_cryopod(ckey_lower, H.real_name)
				if(!spawn_pod)
					var/rejoiner_faction = GLOB.config.sql_enabled ? persistence_get_player_faction(ckey_lower) : null
					spawn_pod = persistence_find_available_cryopod(rejoiner_faction, ckey_lower, H.real_name)
				// If they were stored inside a pod, detach them from it cleanly
				// before waking (they may be re-inserted into spawn_pod below).
				if(istype(H.loc, /obj/structure/machinery/cryopod))
					var/obj/structure/machinery/cryopod/stored_pod = H.loc
					if(stored_pod.occupant == H)
						stored_pod.occupant = null
					H.forceMove(get_step(stored_pod, stored_pod.dir) || get_turf(stored_pod))
					stored_pod.update_icon()
				H.stat = CONSCIOUS
				H.density = TRUE
				H.status_flags &= ~GODMODE
				if(H.client && !H.client.auto_shown_revision_info)
					H.client.auto_shown_revision_info = TRUE
					// Called directly (not deferred) so it lands before both
					// the wake-up message right below and the sector/zone
					// -security chat description (SSjobs.EquipRank(), job.dm),
					// which fires later via its own async path.
					H.client.show_revision_info()
				if(spawn_pod)
					// Wake INSIDE the pod: closed sprite, camera on the pod;
					// set_occupant applies the chill visuals, and stepping out
					// (relaymove() -> go_out()) finishes the effect.
					spawn_pod.set_occupant(H)
					to_chat(H, SPAN_NOTICE("You stir awake inside the cryopod. Welcome back, [H.real_name]. Move in any direction to step out."))
				else
					// LateLogin() fired while the mob could still be inside a pod,
					// locking client.eye onto it (EYE_PERSPECTIVE) -- re-anchor the
					// camera to the mob now that they're on a turf.
					H.reset_view()
					to_chat(H, SPAN_NOTICE("You eject from cryosleep. Welcome back, [H.real_name]."))
					// No pod exit will ever fire -- run the whole effect now.
					H.apply_cryo_chill()
				log_subsystem_persistence_info("Cryo: [H.real_name] ([ckey_lower]) woke from cryosleep.")
				persistence_set_char_state(ckey_lower, H.real_name, "alive")
			if(H.client)
				addtimer(CALLBACK(H.client, /client/proc/start_ambient_playlist), 5 SECONDS)
			qdel(src)
			return

	// Reconnect to any live (non-cryo) mob still in the world with this key
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(H.persistence_in_cryo) continue
		if(ckey(H.ckey) != ckey_lower && ckey(H.persistence_stored_ckey) != ckey_lower) continue
		if(H.client) continue
		// Player explicitly selected a different character — skip this live mob
		if(selected_from_menu && H.real_name != selected_from_menu)
			continue
		H.key = client.ckey
		H.stop_sound_channel(CHANNEL_LOBBYMUSIC) // Lobby music doesn't stop on its own when persistent-spawning into the world -- see create_character()'s equivalent call
		to_chat(H, SPAN_NOTICE("Connection restored. Welcome back, [H.real_name]."))
		log_subsystem_persistence_info("Cryo: [H.real_name] ([ckey_lower]) reconnected to live mob.")
		if(H.client)
			addtimer(CALLBACK(H.client, /client/proc/start_ambient_playlist), 5 SECONDS)
		qdel(src)
		return

	// ── Character selection ──────────────────────────────────
	// When called from the TGUI persistent menu, selected_from_menu is the name
	// the player explicitly clicked. Use it directly to bypass cache-based selection.
	var/selected_char = selected_from_menu

	if(!selected_char)
		// Cache-based fallback for callers that don't pass a name (e.g. join_game button)
		var/list/saved_chars = persistence_get_saved_characters(client.ckey)
		var/slot_limit       = persistence_get_character_slots(client.ckey)
		if(length(saved_chars) > slot_limit)
			saved_chars = saved_chars.Copy(1, slot_limit + 1)

		if(!length(saved_chars))
			selected_char = null
		else if(length(saved_chars) == 1)
			selected_char = saved_chars[1]
		else
			var/list/options = saved_chars.Copy()
			if(length(saved_chars) < slot_limit)
				options += "-- New Character --"
			selected_char = tgui_input_list(src, "Choose a character to play:", "Character Selection", options)
			if(QDELETED(src))
				return
			if(!selected_char)
				reopen_menu_after_failed_spawn()
				return
			if(selected_char == "-- New Character --")
				selected_char = null

	// ── Lace-aware reconnect: dead/in-lace characters never get a free respawn ──
	// After a server restart the round-local mob is gone, so we fall back to the
	// char_state persisted by mobPositionSave()/lacePositionSave() to figure out
	// where this character actually is.
	var/restoring_dead_body = FALSE
	if(selected_char)
		var/list/pos_entry = GLOB.persistence_position_cache["[client.ckey]|[selected_char]"]
		var/saved_char_state = (islist(pos_entry) && pos_entry["char_state"]) ? pos_entry["char_state"] : "alive"

		if(saved_char_state == "in_lace")
			var/obj/item/organ/internal/neural_lace/found_lace = null
			for(var/obj/item/organ/internal/neural_lace/L in world)
				if(QDELETED(L) || L.owner)
					continue
				if(ckey(L.registered_ckey) != ckey_lower || L.registered_name != selected_char)
					continue
				found_lace = L
				break
			if(!found_lace || found_lace.lace_occupied)
				to_chat(src, SPAN_WARNING("Your neural lace could not be located. Contact an administrator."))
				reopen_menu_after_failed_spawn()
				return
			var/mob/living/carbon/lace_mob/new_lm = new /mob/living/carbon/lace_mob(get_turf(found_lace))
			new_lm.name              = selected_char
			new_lm.real_name         = selected_char
			new_lm.neural_lace       = found_lace
			found_lace.lace_mob      = new_lm
			found_lace.lace_occupied = TRUE
			new_lm.forceMove(found_lace)
			new_lm.ckey = client.ckey
			new_lm.mind_initialize()
			to_chat(new_lm, SPAN_NOTICE("You regain consciousness. Your body is gone, but your mind survives within your neural lace. Seek medical staff for resleeving."))
			log_subsystem_persistence_info("PersistentAutoSpawn: [selected_char] ([ckey_lower]) restored into neural lace at ([found_lace.x],[found_lace.y],[found_lace.z]).")
			qdel(src)
			return

		if(saved_char_state == "dead_body")
			restoring_dead_body = TRUE

	// Resolve the cryopod choice NOW, while src (the lobby mob) still owns the
	// client -- create_character() below is what transfers key/client onto the
	// new mob and places it at GLOB.newplayer_start, so waiting until after
	// that to show the picker means the player is already a live, clickable,
	// movable body in the world for however long they take to answer.
	// random_players mode randomizes real_name inside create_character()
	// itself, so identity isn't knowable yet in that one case -- falls through
	// to the post-creation call further down instead.
	var/obj/structure/machinery/cryopod/pre_chosen_spawn_pod
	if(!restoring_dead_body && !SSticker.random_players)
		var/pending_char_name = selected_char || client.prefs.real_name
		var/pending_faction = GLOB.config.sql_enabled ? persistence_get_player_faction(ckey_lower) : null
		pre_chosen_spawn_pod = persistence_prompt_cryopod_choice(src, ckey_lower, pending_char_name, pending_faction)
		if(QDELETED(src))
			return

	// ── Load this character's full SQL data into prefs before spawning ──────
	// create_character() uses client.prefs to build appearance/species/DNA.
	// Loading by character ID ensures the correct character's data is used,
	// regardless of which character was last edited in this session.
	if(selected_char && GLOB.config.sql_saves && SSdbcore.Connect())
		var/datum/db_query/idq = SSdbcore.NewQuery(
			"SELECT id FROM ss13_characters WHERE ckey = :ckey AND name = :name AND deleted_at IS NULL LIMIT 1",
			list("ckey" = client.ckey, "name" = selected_char))
		idq.Execute()
		if(idq.NextRow())
			client.prefs.current_character = text2num(idq.item[1]) || 0
		qdel(idq)
		if(client.prefs.current_character && SSdbcore.Connect())
			var/datum/db_query/cq = SSdbcore.NewQuery(
				{"SELECT name, gender, pronouns, age, metadata, spawnpoint, species, height,
				floating_chat_color, speech_bubble_type,
				hair_colour, facial_colour, grad_colour, skin_tone, skin_colour, eyes_colour,
				hair_style, facial_style, gradient_style, tail_style, b_type,
				disabilities, organs_data, organs_robotic, body_markings, bgstate
				FROM ss13_characters WHERE id = :id AND deleted_at IS NULL LIMIT 1"},
				list("id" = client.prefs.current_character))
			cq.Execute()
			if(cq.NextRow())
				var/datum/preferences/P = client.prefs
				P.real_name           = cq.item[1]
				P.gender              = cq.item[2]
				P.pronouns            = cq.item[3]
				P.age                 = text2num(cq.item[4]) || 30
				P.metadata            = cq.item[5]
				P.spawnpoint          = cq.item[6]
				P.species             = cq.item[7]
				P.height              = text2num(cq.item[8]) || 170
				P.floating_chat_color = cq.item[9]
				P.speech_bubble_type  = cq.item[10]
				P.hair_colour         = cq.item[11]
				P.facial_colour       = cq.item[12]
				P.grad_colour         = cq.item[13]
				P.s_tone              = cq.item[14]
				P.skin_colour         = cq.item[15]
				P.eyes_colour         = cq.item[16]
				P.h_style             = cq.item[17]
				P.f_style             = cq.item[18]
				P.g_style             = cq.item[19]
				P.tail_style          = cq.item[20]
				P.b_type              = cq.item[21]
				P.disabilities        = cq.item[22]
				P.organ_data          = cq.item[23]
				P.rlimb_data          = cq.item[24]
				P.body_markings       = cq.item[25]
				P.bgstate             = cq.item[26]
				// sanitize_setup(TRUE) parses hex colors → r/g/b, json_decode, params2list
				client.prefs.player_setup.sanitize_setup(TRUE)
			qdel(cq)

			// The block above only reloads ss13_characters -- neural_lace lives on
			// ss13_characters_flavour, a separate table, and would otherwise be left
			// at whatever character was last loaded into this shared prefs object.
			var/datum/db_query/lq = SSdbcore.NewQuery(
				"SELECT neural_lace FROM ss13_characters_flavour WHERE char_id = :id",
				list("id" = client.prefs.current_character))
			lq.Execute()
			if(lq.NextRow())
				client.prefs.neural_lace = text2num(lq.item[1])
			qdel(lq)

	// ── Lock character preferences on first spawn (by specific character ID) ────
	// Targets only the character being spawned, not all unspawned characters by ckey.
	var/is_first_ever_spawn = FALSE
	if(client.prefs.current_character && GLOB.config.sql_saves && SSdbcore.Connect())
		// Read before the lock flips it -- this is the only way to know whether
		// this specific character has ever spawned before, to gate the one-time
		// starter PDA grant below.
		var/datum/db_query/spawnedq = SSdbcore.NewQuery(
			"SELECT first_spawned_at FROM ss13_characters WHERE id = :id AND deleted_at IS NULL",
			list("id" = client.prefs.current_character))
		spawnedq.Execute()
		if(spawnedq.NextRow())
			is_first_ever_spawn = isnull(spawnedq.item[1])
		qdel(spawnedq)

		var/datum/db_query/fq = SSdbcore.NewQuery(
			{"UPDATE ss13_characters SET first_spawned_at = NOW()
			WHERE id = :id AND deleted_at IS NULL AND first_spawned_at IS NULL"},
			list("id" = client.prefs.current_character))
		fq.Execute()
		qdel(fq)

	// ── Spawn ────────────────────────────────────────────────
	spawning = 1
	close_spawn_windows()

	// Remove any offline hold mob for this player before spawning.
	// Gear is already saved to DB by persistCharacterOnLogout() and will be
	// restored by applyPersistentInventory() below — the hold mob is cosmetic only.
	for(var/mob/living/carbon/human/H in world)
		if(H.persistence_stored_ckey == client.ckey && !H.ckey)
			qdel(H)
			break

	// create_character() ends by transferring the key -- and with it the client --
	// onto the new mob, so src.client is null for the rest of this proc. Capture
	// the prefs datum now while the client is still attached.
	var/datum/preferences/spawn_prefs = client.prefs

	// Create mob from character preferences (appearance, species, DNA)
	// prefs are now populated with the selected character's specific row data
	var/mob/living/carbon/human/character = create_character()

	// Restore saved state — each call is isolated so one failure can't crash the others
	if(GLOB.config.sql_enabled)
		try
			character.applyPersistentHealthData()
		catch(var/exception/health_e)
			log_subsystem_persistence_error("PersistentAutoSpawn: health restore failed: [health_e]")
		try
			// Materialize this character's saved bank account into SSeconomy so ATMs
			// can find it. Restores only -- never mints; accounts are created at the
			// ID console. Runs before inventory restore so the ID relink sees it.
			var/datum/money_account/restored_account = SSeconomy.restoreAccountFromPersistence(character)
			if(restored_account && character.mind)
				character.mind.initial_account = restored_account
		catch(var/exception/acct_e)
			log_subsystem_persistence_error("PersistentAutoSpawn: account restore failed: [acct_e]")
		try
			character.applyPersistentInventory()
		catch(var/exception/inv_e)
			log_subsystem_persistence_error("PersistentAutoSpawn: inventory restore failed: [inv_e]")
		try
			// Runs after inventory restore so any ID card the character was
			// carrying is present to be swept -- see applyPendingFactionRevokes().
			character.applyPendingFactionRevokes()
		catch(var/exception/revoke_e)
			log_subsystem_persistence_error("PersistentAutoSpawn: pending faction revoke apply failed: [revoke_e]")
		try
			character.applyPersistentIdentity()
		catch(var/exception/id_e)
			log_subsystem_persistence_error("PersistentAutoSpawn: identity restore failed: [id_e]")
		// Refresh visual icons after equipping saved items so the character doesn't appear naked
		character.force_update_limbs()
		character.update_body()
		character.regenerate_icons()

	// Starter PDA -- this server's spawn flow bypasses job/outfit equip
	// entirely (see create_character()'s own doc comment), so a genuinely
	// new character has nothing at all, including no way to reach any
	// console/PDA program. Granted exactly once, gated on the same
	// first-spawn-ever flag used to lock character preferences above.
	if(is_first_ever_spawn)
		character.equip_or_collect(new /obj/item/modular_computer/handheld/pda(character), slot_wear_id)

	// Neural lace — wire up any lace restored by health persistence, or install fresh if preference is on
	var/obj/item/organ/internal/neural_lace/existing_lace = null
	for(var/obj/item/organ/internal/neural_lace/L in character.internal_organs)
		existing_lace = L
		break
	if(!existing_lace)
		var/obj/item/organ/external/head_chk = character.get_organ(BP_HEAD)
		if(head_chk)
			for(var/obj/item/organ/internal/neural_lace/L in head_chk.internal_organs)
				existing_lace = L
				break

	if(existing_lace)
		existing_lace.registered_name = character.real_name
		if(character.ckey) existing_lace.registered_ckey = character.ckey
		character.internal_organs     |= existing_lace
		character.internal_organs_by_name[existing_lace.organ_tag] = existing_lace
		// Ensure head membership -- the health save serializes augments from the
		// EXTERNAL organ's internal_organs list, so a lace missing from it would
		// silently drop from the next save.
		var/obj/item/organ/external/lace_head = character.get_organ(BP_HEAD)
		if(lace_head)
			lace_head.internal_organs |= existing_lace
		add_verb(character, /mob/living/carbon/human/proc/check_neural_lace_status)
	else if(GLOB.config.sql_enabled && spawn_prefs && spawn_prefs.neural_lace)
		var/obj/item/organ/internal/neural_lace/new_lace = new /obj/item/organ/internal/neural_lace(character)
		new_lace._bind_to_owner(character)
		var/obj/item/organ/external/head = character.get_organ(BP_HEAD)
		if(head) head.internal_organs |= new_lace
		character.internal_organs |= new_lace
		character.internal_organs_by_name[new_lace.organ_tag] = new_lace

	if(restoring_dead_body)
		// Recreate the corpse exactly where it was left -- no cryopod spawn, no
		// wake. char_state stays "dead_body" until someone actually revives them.
		// client is null here -- create_character() transferred the key (and the
		// client with it) onto the character mob. Only ckey_lower is safe.
		var/list/pos_entry = GLOB.persistence_position_cache["[ckey_lower]|[selected_char]"]
		var/turf/dead_turf = (islist(pos_entry) && pos_entry["z"]) ? locate(pos_entry["x"], pos_entry["y"], pos_entry["z"]) : null
		if(dead_turf)
			character.forceMove(dead_turf)
		else
			character.applyPersistentPosition()
		character.set_stat(DEAD)
		to_chat(character, SPAN_NOTICE("You reconnect to your body. It's dead -- you can only observe. Seek rescue."))
		log_subsystem_persistence_info("PersistentAutoSpawn: [character.real_name] ([ckey_lower]) restored into their corpse (dead_body state).")
		qdel(src)
		return

	// Cryopod choice was already resolved above, before this mob existed, so
	// the player was never placed in the world with a decision still
	// pending. random_players is the one mode where identity wasn't knowable
	// yet at that point -- resolve it here instead, same as before this fix.
	var/spawner_faction = GLOB.config.sql_enabled ? persistence_get_player_faction(ckey_lower) : null
	var/obj/structure/machinery/cryopod/spawn_pod = pre_chosen_spawn_pod
	if(!spawn_pod && SSticker.random_players)
		spawn_pod = persistence_prompt_cryopod_choice(character, ckey_lower, character.real_name, spawner_faction)

	// Wake inside the character's last-used cryopod when still valid, else
	// faction pods -> public pods, any free working pod as last resort
	if(!spawn_pod)
		spawn_pod = persistence_find_saved_cryopod(ckey_lower, character.real_name)
	if(!spawn_pod)
		spawn_pod = persistence_find_available_cryopod(spawner_faction, ckey_lower, character.real_name)
	if(!spawn_pod)
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(_cryopod_ignored_for_discovery(pod)) continue
			if(pod.occupant || (pod.stat & (NOPOWER|BROKEN))) continue
			var/turf/pt = get_turf(pod)
			if(!pt || !pt.z) continue
			spawn_pod = pod
			break

	if(spawn_pod)
		// Interim placement on the pod's turf -- the wake block below force-
		// ejects mobs whose loc is a cryopod, so the actual insertion happens
		// after the wake completes.
		character.forceMove(get_turf(spawn_pod))
	else
		// Absolute last resort — saved position or landmark
		character.applyPersistentPosition()

	// Fully wake the character from cryosleep.
	// The life proc re-applies UNCONSCIOUS every tick if sleeping/drowsy/resting are set,
	// so we must clear those root causes — setting stat directly is not enough.
	if(character.stat != DEAD)
		// If they're inside a cryopod somehow, eject them first
		if(istype(character.loc, /obj/structure/machinery/cryopod))
			var/obj/structure/machinery/cryopod/pod = character.loc
			if(pod.occupant == character)
				pod.occupant = null
			var/turf/exit_t = get_step(pod, pod.dir) || get_turf(pod)
			character.forceMove(exit_t)
		// Clear sleep-causing vars before calling set_stat so the life proc doesn't re-apply UNCONSCIOUS
		character.sleeping   = 0
		character.resting    = FALSE
		character.drowsiness = 0
		character.set_stat(CONSCIOUS)
		persistence_set_char_state(ckey_lower, character.real_name, "alive")
		if(character.client && !character.client.auto_shown_revision_info)
			character.client.auto_shown_revision_info = TRUE
			// Called directly (not deferred) so it lands before both the
			// wake-up message right below and the sector/zone-security chat
			// description and arrival announcement that fire later in this
			// same spawn flow (below), via their own async path.
			character.client.show_revision_info()
		if(spawn_pod && !QDELETED(spawn_pod) && !spawn_pod.occupant)
			// Wake INSIDE the pod: closed sprite, camera on the pod;
			// set_occupant applies the chill visuals, and stepping out
			// (relaymove() -> go_out()) finishes the effect.
			spawn_pod.set_occupant(character)
			to_chat(character, SPAN_NOTICE("You stir awake inside the cryopod. Welcome [selected_char ? "back" : "aboard"], [character.real_name]. Move in any direction to step out."))
		else
			to_chat(character, SPAN_NOTICE("You eject from cryosleep. Welcome [selected_char ? "back" : "aboard"], [character.real_name]."))
			// No pod exit will ever fire -- run the whole effect now.
			character.apply_cryo_chill()
	character.status_flags &= ~GODMODE
	character.density = TRUE

	GLOB.universe.OnPlayerLatejoin(character)
	if(SSjobs.ShouldCreateRecords(character.mind))
		SSrecords.generate_record(character)
		SSticker.minds += character.mind
		AnnounceArrival(character, null, null)
		announce_faction_cryo_exit(character)

	// Lobby music doesn't stop on its own when persistent-spawning into the
	// world -- see create_character()'s equivalent call. Left running, it
	// keeps actively playing on its own channel right through the moment
	// start_ambient_playlist() below tries to start a second large chained
	// track on a different channel.
	character.stop_sound_channel(CHANNEL_LOBBYMUSIC)

	// One-off local cue for the player whose character just finished loading --
	// only this client hears it, not a world broadcast.
	if(character.client)
		character.playsound_local(get_turf(character), 'sound/AI/theclockstartsticking.ogg', 5)

	// Start the in-round ambient music playlist once prefs have settled
	if(character.client)
		addtimer(CALLBACK(character.client, /client/proc/start_ambient_playlist), 5 SECONDS)

	qdel(src)

/mob/abstract/new_player/proc/ViewManifest()
	SSrecords.open_manifest_tgui(src)

/mob/abstract/new_player/Move()
	return TRUE

/mob/abstract/new_player/hear_message(datum/say_message/msg)
	return FALSE

/mob/abstract/new_player/proc/close_spawn_windows()
	src << browse(null, "window=playersetup") //closes the player setup window

/mob/abstract/new_player/proc/has_admin_rights()
	return check_rights(R_ADMIN, 0, src)

/mob/abstract/new_player/proc/is_species_whitelisted(datum/species/S)
	if(!S) return 1
	return is_alien_whitelisted(src, S.name) || !GLOB.config.usealienwhitelist || !(S.spawn_flags & IS_WHITELISTED)

/mob/abstract/new_player/get_species(var/reference = 0)
	var/datum/species/chosen_species
	if(client.prefs.species)
		chosen_species = GLOB.all_species[client.prefs.species]

	if(!chosen_species)
		return SPECIES_HUMAN

	if(is_species_whitelisted(chosen_species) || has_admin_rights())
		if (reference)
			return chosen_species
		else
			return chosen_species.name

	return SPECIES_HUMAN

/mob/abstract/new_player/get_gender()
	if(!client || !client.prefs)
		..()
	return client.prefs.gender

/mob/abstract/new_player/is_ready()
	return ready && ..()

/mob/abstract/new_player/MayRespawn()
	return 1

/mob/abstract/new_player/show_message(msg, type, alt, alt_type)
	return
