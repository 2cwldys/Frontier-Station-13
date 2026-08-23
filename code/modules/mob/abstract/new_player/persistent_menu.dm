/datum/persistent_menu
	var/mob/abstract/new_player/new_player_mob
	var/spawning = FALSE  // set TRUE when Play is clicked; prevents ui_close() from reopening
	var/opening = FALSE   // guards the window between ui.open() start and open_uis registration;
	                      // ui_data's blocking DB query defeats try_update_ui during that gap

/datum/persistent_menu/New(mob/abstract/new_player/NP)
	src.new_player_mob = NP

/datum/persistent_menu/ui_state(mob/user)
	return GLOB.always_state

/datum/persistent_menu/ui_close(mob/user)
	if(spawning) return
	var/mob/abstract/new_player/NP = new_player_mob
	if(!NP || QDELETED(NP) || !NP.client) return
	addtimer(CALLBACK(NP, TYPE_PROC_REF(/mob/abstract/new_player, show_persistent_menu)), 5)

/datum/persistent_menu/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		if(opening)
			return
		opening = TRUE
		try
			ui = new /datum/tgui(user, src, "PersistentMenu", "Character Select", 420, 520)
			ui.open()
		catch(var/exception/menu_e)
			log_debug("persistent_menu: ui open failed: [menu_e]")
		opening = FALSE
		// If Play was clicked while this open() was suspended in ui_data()'s
		// blocking DB query, close_uis() (from PersistentAutoSpawn()) ran too
		// early to see this not-yet-registered UI. Catch it here instead --
		// control only returns to us after registration has actually happened.
		if(spawning && ui)
			ui.close()

/datum/persistent_menu/ui_data(mob/user)
	var/list/data = list()
	var/ckey = user.client ? user.client.ckey : null

	var/list/chars_out = list()
	var/any_imprisoned = FALSE
	if(ckey && GLOB.config.sql_saves && SSdbcore.Connect())
		var/datum/db_query/cq = SSdbcore.NewQuery(
			"SELECT name FROM ss13_characters WHERE ckey = :ckey AND deleted_at IS NULL ORDER BY id ASC",
			list("ckey" = ckey))
		cq.Execute()
		while(cq.NextRow())
			var/char_name = cq.item[1]
			var/list/entry = list("name" = char_name)
			var/list/status = persistence_character_imprisonment_status(ckey, char_name)
			entry["imprisoned"] = !!status
			entry["indefinite"] = status ? !!status["indefinite"] : FALSE
			entry["remaining_seconds"] = status ? status["remaining_seconds"] : 0
			if(status)
				any_imprisoned = TRUE
			chars_out += list(entry)
		qdel(cq)
	data["characters"] = chars_out
	// Blocks the empty-slot "Create Character" button while any of this
	// ckey's characters is imprisoned -- otherwise a fresh alt in another
	// slot is a trivial way to sidestep an active sentence entirely, same
	// motivation as blocking Delete on the imprisoned character itself
	// (see "delete_char"/"create" below).
	data["any_imprisoned"] = any_imprisoned

	var/slot_limit = ckey ? persistence_get_character_slots(ckey) : 1
	data["slot_limit"]        = slot_limit
	data["can_create"]        = length(chars_out) < slot_limit && !any_imprisoned
	data["persistence_ready"] = GLOB.persistence_ready
	// Admins can still Play while a save is in progress -- matches
	// PersistentAutoSpawn()'s own admin bypass (new_player.dm) and this
	// same enter_allowed/whitelisted pattern just below.
	data["save_in_progress"]  = (SSpersistence.save_in_progress && !check_rights(R_ADMIN, 0, user)) ? TRUE : FALSE
	// Whitelist gate mirrors enter_allowed: applies to non-admins only
	data["whitelisted"]       = (check_rights(R_ADMIN, 0, user) || persistence_is_whitelisted(ckey)) ? TRUE : FALSE
	// Admins can still Play while joining is locked -- matches PersistentAutoSpawn()'s
	// own admin bypass. NOTE: with AUTO_LOCAL_ADMIN in the config, any connection
	// from the host machine is silently full-admin, so the button will NOT grey
	// out for a host-connected account even when the server is locked -- that is
	// the bypass working as intended, not the lock failing.
	data["enter_allowed"]     = GLOB.config.enter_allowed || check_rights(R_ADMIN, 0, user)
	// Presence-lock backing store -- see docs/cross_server_persistence.md.
	// Always TRUE when central_sql_enabled is off (centralDatabaseReachable()
	// itself handles that), so this never gates anything on an ordinary
	// standalone server.
	data["central_reachable"] = SSpersistence.centralDatabaseReachable()

	return data

/datum/persistent_menu/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..()) return
	var/mob/abstract/new_player/NP = new_player_mob
	if(!NP || QDELETED(NP)) return

	switch(action)
		if("play")
			// Cheap double-click guard -- a rapid second click before ui.close()
			// visually removes the button could otherwise call
			// PersistentAutoSpawn() twice on the same new_player mob.
			if(spawning) return TRUE
			// Defense-in-depth: the frontend already greys the Play button out
			// for these same conditions (ui_data()'s enter_allowed/persistence_ready),
			// but never trust client-side disabling alone -- a bypassed/replayed
			// action could still reach here. Checking before committing to
			// spawning = TRUE / ui.close() means a blocked attempt leaves the
			// menu open with a message instead of closing on a doomed spawn
			// (closing it here with nothing to ever reset spawning back to
			// FALSE would otherwise strand the player with no menu at all).
			if(!GLOB.persistence_ready)
				to_chat(NP, SPAN_WARNING("The server is still loading. Please wait a moment and try again."))
				return TRUE
			if(SSpersistence.save_in_progress && !check_rights(R_ADMIN, 0, NP))
				to_chat(NP, SPAN_WARNING("Cannot join server while a save is in progress."))
				return TRUE
			if(!GLOB.config.enter_allowed && !check_rights(R_ADMIN, 0, NP))
				to_chat(NP, SPAN_NOTICE("Joining is currently disabled by an administrator."))
				return TRUE
			if(!persistence_is_whitelisted(NP.ckey) && !check_rights(R_ADMIN, 0, NP))
				to_chat(NP, SPAN_WARNING("You are not whitelisted to join this server. Contact an administrator."))
				return TRUE
			if(SSticker.current_state != GAME_STATE_PLAYING)
				to_chat(NP, SPAN_WARNING("The round is not ready yet."))
				return TRUE
			var/char_name = params["name"]
			// Defense-in-depth, same reasoning as the checks above -- the
			// frontend already greys Play out per-character for this, but
			// never trust client-side disabling alone.
			var/ckey_check = NP.client ? NP.client.ckey : null
			var/list/imprison_status = (ckey_check && char_name) ? persistence_character_imprisonment_status(ckey_check, char_name) : null
			if(imprison_status)
				to_chat(NP, imprison_status["indefinite"] \
					? SPAN_WARNING("This character is imprisoned indefinitely.") \
					: SPAN_WARNING("This character is imprisoned, time left: [round(imprison_status["remaining_seconds"] / 60)] minute(s)."))
				return TRUE
			spawning = TRUE
			NP.PersistentAutoSpawn(char_name)
			if(ui)
				ui.close()
			return TRUE

		if("create")
			if(!NP.client) return
			var/ckey = NP.client.ckey
			// Defense-in-depth, same reasoning as "play"/"delete_char" below --
			// the frontend already greys Create out for this, but never trust
			// client-side disabling alone. A fresh alt in an empty slot would
			// otherwise be a trivial way to sidestep an active sentence.
			if(persistence_ckey_has_imprisoned_character(ckey))
				to_chat(NP, SPAN_WARNING("You are imprisoned."))
				return TRUE
			var/slot_limit = persistence_get_character_slots(ckey)
			var/char_count = 0
			if(GLOB.config.sql_saves && SSdbcore.Connect())
				var/datum/db_query/cntq = SSdbcore.NewQuery(
					"SELECT COUNT(*) FROM ss13_characters WHERE ckey = :ckey AND deleted_at IS NULL",
					list("ckey" = ckey))
				cntq.Execute()
				if(cntq.NextRow())
					char_count = text2num(cntq.item[1]) || 0
				qdel(cntq)
			if(char_count >= slot_limit)
				to_chat(NP, SPAN_WARNING("All character slots are full. Delete a character to create a new one."))
				return TRUE
			var/new_name = tgui_input_text(NP, "Enter your character's name:", "Character Name", "", max_length = MAX_NAME_LEN)
			if(!new_name) return TRUE
			NP.client.prefs.new_setup(1)
			NP.client.prefs.can_edit_character = TRUE
			NP.client.prefs.can_edit_name      = TRUE
			NP.client.prefs.can_edit_ipc_tag   = TRUE
			NP.client.prefs.player_setup.sanitize_setup(TRUE)
			var/sanitized = sanitize_name(new_name, NP.client.prefs.species)
			if(!sanitized)
				to_chat(NP, SPAN_WARNING("Invalid name. Try again."))
				return TRUE
			NP.client.prefs.real_name = sanitized
			// Enforce global name uniqueness — checked now so the player gets immediate feedback.
			// The actual row INSERT happens in save_character() when they click Save Character.
			if(GLOB.config.sql_saves && SSdbcore.Connect())
				var/datum/db_query/name_q = SSdbcore.NewQuery(
					"SELECT COUNT(*) FROM ss13_characters WHERE name = :name AND deleted_at IS NULL",
					list("name" = sanitized))
				name_q.Execute()
				var/name_taken = FALSE
				if(name_q.NextRow())
					name_taken = text2num(name_q.item[1]) > 0
				qdel(name_q)
				if(name_taken)
					to_chat(NP, SPAN_WARNING("The name '[sanitized]' is already taken. Please choose a different name."))
					return TRUE
			// current_character stays 0 — the row is created only when Save Character is clicked
			NP.client.prefs.current_character = 0
			NP.client.prefs.ShowChoices(NP)
			return TRUE

		if("delete_char")
			var/char_name = params["name"]
			if(!char_name) return
			var/ckey = NP.client ? NP.client.ckey : null
			if(!ckey) return
			// Defense-in-depth, same reasoning as "play" above -- the frontend
			// already greys Delete out for this, but never trust client-side
			// disabling alone. Deleting the character outright would otherwise
			// free the slot and dodge the sentence entirely, worse than just
			// switching to an alt.
			if(persistence_character_imprisonment_status(ckey, char_name))
				to_chat(NP, SPAN_WARNING("You are imprisoned."))
				return TRUE
			var/confirm = tgui_alert(NP, "Permanently delete '[char_name]'? This cannot be undone.", "Delete Character", list("Delete", "Cancel"))
			if(confirm != "Delete") return TRUE
			if(GLOB.config.sql_saves && SSdbcore.Connect())
				var/datum/db_query/dq = SSdbcore.NewQuery(
					"UPDATE ss13_characters SET deleted_at = NOW() WHERE ckey = :ckey AND name = :name AND deleted_at IS NULL",
					list("ckey" = ckey, "name" = char_name))
				dq.Execute()
				qdel(dq)
				// The soft-delete above only flags ss13_characters -- this is
				// what actually clears health/inventory/position data (SQL +
				// caches) and the character's bank account, so it stops
				// showing up as if it still existed everywhere else
				// (persistence_get_saved_characters() and everything built on
				// it: Give Credits, the rename picker, PersistentAutoSpawn's
				// no-name fallback).
				persistence_delete_character_data(ckey, char_name)
			if(NP.client && NP.client.prefs)
				NP.client.prefs.current_character = 0
			message_admins(SPAN_DANGER("PERSISTENCE: [ckey] deleted character <b>[char_name]</b>."))
			to_chat(NP, SPAN_GOOD("Character '[char_name]' deleted. The slot is now available."))
			return TRUE
