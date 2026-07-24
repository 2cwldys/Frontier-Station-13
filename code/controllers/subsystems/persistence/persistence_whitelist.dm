/*
 * Persistence - Join Whitelist
 * Admin-managed ckey whitelist gating the ability to join through the
 * Character Select menu. Non-whitelisted ckeys are denied by default;
 * admins always bypass (same semantics as Toggle Joining/enter_allowed).
 * DB-backed (ss13_join_whitelist, V064) with an in-memory cache so the
 * Play gate never hits the database.
 */

/// Normalized ckeys allowed to join. Loaded at boot, updated live by the
/// Whitelist Players admin verb.
GLOBAL_LIST_EMPTY(persistence_join_whitelist)

/// Whether the join whitelist is enforced at all. Admin-toggled via the
/// Whitelist Players verb's "Toggle" option, DB-persisted
/// (ss13_join_whitelist_toggle, V085) -- same mechanism as
/// GLOB.faction_creation_enabled. Default ON preserves the original
/// always-enforced behavior.
GLOBAL_VAR_INIT(persistence_join_whitelist_enabled, TRUE)

/**
 * Load the whitelist into the cache.
 * Called from SSpersistence.Initialize() before players can join.
 */
/datum/controller/subsystem/persistence/proc/whitelistInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_join_whitelist = list()

	if(!databaseCheckConnection("whitelistInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery("SELECT ckey FROM ss13_join_whitelist", list())
	query.Execute()
	if(!databaseCheckQueryResult(query, "whitelistInitialize"))
		qdel(query)
		return

	while(query.NextRow())
		GLOB.persistence_join_whitelist |= ckey(query.item[1])
	qdel(query)
	log_subsystem_persistence_info("Whitelist: Loaded [length(GLOB.persistence_join_whitelist)] whitelisted ckey(s).")

	try
		var/datum/db_query/tq = SSdbcore.NewQuery("SELECT enabled FROM ss13_join_whitelist_toggle WHERE id = 1", list())
		tq.Execute()
		if(databaseCheckQueryResult(tq, "whitelistInitialize toggle") && tq.NextRow())
			GLOB.persistence_join_whitelist_enabled = text2num(tq.item[1])
		qdel(tq)
	catch(var/exception/toggle_e)
		log_subsystem_persistence_error("Whitelist: failed to load whitelist toggle: [toggle_e]")
	log_subsystem_persistence_info("Whitelist: enforcement is [GLOB.persistence_join_whitelist_enabled ? "ON" : "OFF"].")

/// Sets + persists whether the join whitelist is enforced at all.
/datum/controller/subsystem/persistence/proc/setJoinWhitelistEnabled(enabled)
	GLOB.persistence_join_whitelist_enabled = enabled
	if(!databaseCheckConnection("setJoinWhitelistEnabled"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_join_whitelist_toggle (id, enabled) VALUES (1, :enabled) ON DUPLICATE KEY UPDATE enabled = VALUES(enabled)",
		list("enabled" = enabled ? 1 : 0)
	)
	q.Execute()
	databaseCheckQueryResult(q, "setJoinWhitelistEnabled")
	qdel(q)

/// TRUE when the ckey may join. Inert (always TRUE) without SQL, since the
/// whitelist can't be managed or loaded then anyway.
/proc/persistence_is_whitelisted(target_ckey)
	if(!GLOB.config.sql_enabled)
		return TRUE
	// Enforcement toggled off entirely (Whitelist Players verb -> Toggle).
	if(!GLOB.persistence_join_whitelist_enabled)
		return TRUE
	target_ckey = ckey(target_ckey)
	if(!target_ckey)
		return FALSE
	return (target_ckey in GLOB.persistence_join_whitelist)

/// Add a ckey (online or not) to the whitelist. Returns TRUE on success.
/proc/persistence_whitelist_add(target_ckey, admin_ckey)
	target_ckey = ckey(target_ckey)
	if(!target_ckey || !GLOB.config.sql_enabled)
		return FALSE
	if(!SSpersistence.databaseCheckConnection("persistence_whitelist_add"))
		return FALSE

	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_join_whitelist (ckey, added_by) VALUES (:ckey, :added_by)
		ON DUPLICATE KEY UPDATE added_by = VALUES(added_by)"},
		list("ckey" = target_ckey, "added_by" = admin_ckey || "")
	)
	ins.Execute()
	SSpersistence.databaseCheckQueryResult(ins, "persistence_whitelist_add")
	qdel(ins)

	GLOB.persistence_join_whitelist |= target_ckey
	return TRUE

/// Remove a ckey from the whitelist. Returns TRUE on success.
/proc/persistence_whitelist_remove(target_ckey)
	target_ckey = ckey(target_ckey)
	if(!target_ckey || !GLOB.config.sql_enabled)
		return FALSE
	if(!SSpersistence.databaseCheckConnection("persistence_whitelist_remove"))
		return FALSE

	var/datum/db_query/dq = SSdbcore.NewQuery(
		"DELETE FROM ss13_join_whitelist WHERE ckey = :ckey",
		list("ckey" = target_ckey)
	)
	dq.Execute()
	SSpersistence.databaseCheckQueryResult(dq, "persistence_whitelist_remove")
	qdel(dq)

	GLOB.persistence_join_whitelist -= target_ckey
	return TRUE

// ============================================================
// WHITELIST ADMIN VERB
// ============================================================

/datum/admins/proc/whitelist_players()
	set name = "Whitelist Players"
	set category = "Persistence"
	set desc = "Add or remove ckeys allowed to join through the character menu."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- the join whitelist is inactive."))
		return

	while(usr && usr.client)
		var/toggle_label = "Toggle whitelist (currently [GLOB.persistence_join_whitelist_enabled ? "ON" : "OFF"])"
		var/choice = tgui_input_list(usr, "Join whitelist ([length(GLOB.persistence_join_whitelist)] ckey\s, enforcement [GLOB.persistence_join_whitelist_enabled ? "ON" : "OFF"]):", "Whitelist Players", list("Add ckey", "Remove ckey", "View whitelist", toggle_label, "Done"))
		if(!choice || choice == "Done")
			return

		if(choice == toggle_label)
			var/new_state = !GLOB.persistence_join_whitelist_enabled
			if(tgui_alert(usr, "Join whitelist enforcement is currently [GLOB.persistence_join_whitelist_enabled ? "ENABLED" : "DISABLED"]. [new_state ? "Enable" : "Disable"] it?", "Toggle Whitelist", list("Yes", "No")) != "Yes")
				continue
			SSpersistence.setJoinWhitelistEnabled(new_state)
			log_and_message_admins("[new_state ? "enabled" : "disabled"] join whitelist enforcement.", usr)
			continue

		switch(choice)
			if("Add ckey")
				var/new_ckey = tgui_input_text(usr, "Enter the ckey to whitelist (player may be offline):", "Whitelist Players", max_length = 32)
				new_ckey = ckey(new_ckey)
				if(!new_ckey)
					continue
				if(new_ckey in GLOB.persistence_join_whitelist)
					to_chat(usr, SPAN_NOTICE("'[new_ckey]' is already whitelisted."))
					continue
				if(persistence_whitelist_add(new_ckey, usr.ckey))
					log_and_message_admins("added '[new_ckey]' to the join whitelist", usr)
					var/client/C = GLOB.directory[new_ckey]
					if(C)
						to_chat(C, SPAN_GOOD("You have been whitelisted to join this server."))
				else
					to_chat(usr, SPAN_WARNING("Failed to add '[new_ckey]' -- database error."))

			if("Remove ckey")
				if(!length(GLOB.persistence_join_whitelist))
					to_chat(usr, SPAN_NOTICE("The whitelist is empty."))
					continue
				var/removed_ckey = tgui_input_list(usr, "Select the ckey to remove:", "Whitelist Players", GLOB.persistence_join_whitelist)
				if(!removed_ckey)
					continue
				if(persistence_whitelist_remove(removed_ckey))
					log_and_message_admins("removed '[removed_ckey]' from the join whitelist", usr)
					var/client/C = GLOB.directory[removed_ckey]
					if(C)
						to_chat(C, SPAN_WARNING("You have been removed from this server's join whitelist."))
				else
					to_chat(usr, SPAN_WARNING("Failed to remove '[removed_ckey]' -- database error."))

			if("View whitelist")
				if(!length(GLOB.persistence_join_whitelist))
					to_chat(usr, SPAN_NOTICE("The whitelist is empty."))
					continue
				var/list/sorted = sortList(GLOB.persistence_join_whitelist.Copy())
				to_chat(usr, SPAN_NOTICE("<b>Join whitelist ([length(sorted)]):</b> [sorted.Join(", ")]"))
