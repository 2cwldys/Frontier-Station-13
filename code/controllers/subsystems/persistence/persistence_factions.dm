/*
 * Persistence - Faction System
 * Manages faction financial accounts and custom job definitions.
 * Faction data (name, balance, jobs) loads at startup and saves on every persist cycle.
 *
 * Tables: ss13_factions, ss13_faction_accounts, ss13_faction_jobs
 */

/// In-memory faction data keyed by uid: list("name"=..., "abbreviation"=..., "balance"=N)
GLOBAL_LIST_EMPTY(persistence_faction_cache)

/// In-memory faction jobs keyed by faction_uid: list of lists("id"=N,"title"=...,"access"=list(),"pay_rate"=N,"rank"=N)
GLOBAL_LIST_EMPTY(persistence_faction_jobs_cache)

/// In-memory faction members keyed by "ckey|faction_uid": list("real_name"=...,"job_title"=...,"rank"=N)
GLOBAL_LIST_EMPTY(persistence_faction_members_cache)

// ============================================================
// INITIALIZE
// ============================================================

/datum/controller/subsystem/persistence/proc/factionInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_faction_cache         = list()
	GLOB.persistence_faction_jobs_cache    = list()
	GLOB.persistence_faction_members_cache = list()

	if(!databaseCheckConnection("factionInitialize"))
		return

	// Load faction info + balances
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"SELECT f.uid, f.name, f.abbreviation, COALESCE(a.balance, 0)
		FROM ss13_factions f
		LEFT JOIN ss13_faction_accounts a ON a.faction_uid = f.uid"},
		list()
	)
	q.Execute()
	if(databaseCheckQueryResult(q, "factionInitialize factions"))
		while(q.NextRow())
			GLOB.persistence_faction_cache[q.item[1]] = list(
				"name"         = q.item[2],
				"abbreviation" = q.item[3],
				"balance"      = text2num(q.item[4]) || 0
			)
	qdel(q)

	// Load faction jobs
	var/datum/db_query/jq = SSdbcore.NewQuery(
		"SELECT id, faction_uid, title, access_json, pay_rate, rank FROM ss13_faction_jobs ORDER BY faction_uid, rank DESC, title ASC",
		list()
	)
	jq.Execute()
	if(databaseCheckQueryResult(jq, "factionInitialize jobs"))
		while(jq.NextRow())
			var/fuid = jq.item[2]
			if(!(fuid in GLOB.persistence_faction_jobs_cache))
				GLOB.persistence_faction_jobs_cache[fuid] = list()
			GLOB.persistence_faction_jobs_cache[fuid] += list(list(
				"id"       = text2num(jq.item[1]),
				"title"    = jq.item[3],
				"access"   = jq.item[4] ? json_decode(jq.item[4]) : list(),
				"pay_rate" = text2num(jq.item[5]) || 500,
				"rank"     = text2num(jq.item[6]) || 0
			))
	qdel(jq)

	// Load faction members (include account_number for payroll; column may not exist yet on old DBs)
	var/datum/db_query/mq = SSdbcore.NewQuery(
		"SELECT ckey, faction_uid, real_name, job_title, rank, IFNULL(account_number, 0) FROM ss13_faction_members",
		list()
	)
	mq.Execute()
	if(databaseCheckQueryResult(mq, "factionInitialize members"))
		while(mq.NextRow())
			var/mkey = "[mq.item[1]]|[mq.item[2]]"
			GLOB.persistence_faction_members_cache[mkey] = list(
				"real_name"      = mq.item[3],
				"job_title"      = mq.item[4],
				"rank"           = text2num(mq.item[5]) || 0,
				"account_number" = text2num(mq.item[6]) || 0
			)
	qdel(mq)

	log_subsystem_persistence_info("Factions: Loaded [length(GLOB.persistence_faction_cache)] factions, [length(GLOB.persistence_faction_members_cache)] members.")

// ============================================================
// FINALIZE
// ============================================================

/datum/controller/subsystem/persistence/proc/factionFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("factionFinalize"))
		return

	for(var/uid in GLOB.persistence_faction_cache)
		var/list/data = GLOB.persistence_faction_cache[uid]
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance)
			ON DUPLICATE KEY UPDATE balance = VALUES(balance), saved_at = NOW()"},
			list("uid" = uid, "balance" = data["balance"])
		)
		q.Execute()
		databaseCheckQueryResult(q, "factionFinalize upsert [uid]")
		qdel(q)

		// Auto-payroll: check if interval has elapsed (default 3600 seconds = 1 real hour)
		var/interval = data["payroll_interval"] || 3600
		var/last_pay = data["last_payroll_at"] || 0
		if(world.time - last_pay >= interval * 10)  // world.time in deciseconds
			factionPayroll(uid)

	log_subsystem_persistence_info("Factions: Saved [length(GLOB.persistence_faction_cache)] faction accounts.")

// ============================================================
// ACCOUNT OPERATIONS
// ============================================================

/proc/get_faction_account_balance(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return null
	return GLOB.persistence_faction_cache[uid]["balance"]

/proc/faction_debit(uid, amount, reason = "transaction")
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	if(amount <= 0)
		return FALSE
	var/list/data = GLOB.persistence_faction_cache[uid]
	if(data["balance"] < amount)
		return FALSE  // insufficient funds
	data["balance"] -= amount
	log_game("Faction [uid] debited [amount] credits: [reason]")
	_faction_balance_write(uid, data["balance"])
	_faction_transaction_log(uid, -amount, reason)
	return TRUE

/proc/faction_credit(uid, amount, reason = "transaction")
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	if(amount <= 0)
		return FALSE
	GLOB.persistence_faction_cache[uid]["balance"] += amount
	log_game("Faction [uid] credited [amount] credits: [reason]")
	_faction_balance_write(uid, GLOB.persistence_faction_cache[uid]["balance"])
	_faction_transaction_log(uid, amount, reason)
	return TRUE

/// Log a faction transaction (debit negative, credit positive). Fire-and-forget.
/proc/_faction_transaction_log(uid, amount, reason)
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return
	var/datum/db_query/tq = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_transactions (faction_uid, amount, reason) VALUES (:uid, :amount, :reason)",
		list("uid" = uid, "amount" = amount, "reason" = reason)
	)
	tq.Execute()
	qdel(tq)

/// Write a faction's balance to DB immediately. Called after every balance mutation.
/proc/_faction_balance_write(uid, balance)
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return
	var/datum/db_query/bq = SSdbcore.NewQuery(
		{"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance)
		ON DUPLICATE KEY UPDATE balance = VALUES(balance), saved_at = NOW()"},
		list("uid" = uid, "balance" = balance)
	)
	bq.Execute()
	qdel(bq)

// ============================================================
// JOB OPERATIONS
// ============================================================

/proc/get_faction_jobs(uid)
	if(!islist(GLOB.persistence_faction_jobs_cache))
		return list()
	return GLOB.persistence_faction_jobs_cache[uid] || list()

/proc/get_faction_name(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return uid
	return GLOB.persistence_faction_cache[uid]["name"]

// ============================================================
// FACTION RESEARCH
// ============================================================

/// Cached faction research keyed by faction_uid: list of {id, level, progress}
GLOBAL_LIST_EMPTY(persistence_faction_research_cache)

/datum/controller/subsystem/persistence/proc/factionResearchInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_faction_research_cache = list()

	if(!databaseCheckConnection("factionResearchInitialize"))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT faction_uid, tech_data FROM ss13_faction_research WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	q.Execute()
	if(databaseCheckQueryResult(q, "factionResearchInitialize"))
		while(q.NextRow())
			var/fuid     = q.item[1]
			var/tech_raw = q.item[2]
			var/list/tech_list = tech_raw ? json_decode(tech_raw) : list()
			if(islist(tech_list))
				GLOB.persistence_faction_research_cache[fuid] = tech_list
	qdel(q)
	log_subsystem_persistence_info("FactionResearch: Loaded research for [length(GLOB.persistence_faction_research_cache)] factions.")

/datum/controller/subsystem/persistence/proc/factionResearchFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("factionResearchFinalize"))
		return

	var/saved = 0
	// Aggregate tech per faction by scanning R&D servers with employer_faction set
	var/list/faction_tech = list()
	for(var/obj/structure/machinery/r_n_d/server/server in world)
		if(!server.files)
			continue
		// employer_faction is not defined on all R&D server subtypes  use try/catch
		var/fuid = null
		try
			fuid = server.vars["employer_faction"]
		catch
			continue  // var not defined on this server type  skip it
		if(!fuid || !istext(fuid))
			continue
		if(!(fuid in faction_tech))
			faction_tech[fuid] = list()
		for(var/tech_id in server.files.known_tech)
			var/datum/tech/tech = server.files.known_tech[tech_id]
			if(!faction_tech[fuid][tech_id] || tech.level > faction_tech[fuid][tech_id]["level"])
				faction_tech[fuid][tech_id] = list("id"=tech_id, "level"=tech.level, "progress"=tech.next_level_progress)

	for(var/fuid in faction_tech)
		var/list/tech_list = list()
		for(var/tid in faction_tech[fuid])
			tech_list += list(faction_tech[fuid][tid])
		var/tech_json = json_encode(tech_list)
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_research (faction_uid, map_path, tech_data, saved_at)
			VALUES (:uid, :map, :data, NOW())
			ON DUPLICATE KEY UPDATE tech_data = VALUES(tech_data), saved_at = NOW()"},
			list("uid"=fuid, "map"="[SSatlas.current_map.path]", "data"=tech_json)
		)
		q.Execute()
		databaseCheckQueryResult(q, "factionResearchFinalize upsert [fuid]")
		qdel(q)
		saved++

	log_subsystem_persistence_info("FactionResearch: Saved research for [saved] factions.")

// ============================================================
// ADMIN VERBS
// ============================================================

/datum/admins/proc/toggle_zlevel_persistence()
	set name = "Toggle Z-Level Persistence"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	// Build status display
	var/msg = "Current Z-Level Persistence:\n"
	for(var/z = 1 to world.maxz)
		var/skipped = (z in GLOB.persistence_zlevel_skip)
		msg += "  Z=[z]: [skipped ? "SKIP (regenerates each restart)" : "PERSIST (saves/loads)"]\n"

	var/z_pick = tgui_input_number(usr, "[msg]\nZ=[usr.z] is your current level. Enter Z level to toggle:", "Toggle Z Persistence", usr.z, world.maxz, 1)
	if(isnull(z_pick) || z_pick < 1 || z_pick > world.maxz)
		return

	var/cur_notes = ""
	if(!SSpersistence.databaseCheckConnection("toggle_zlevel_persistence"))
		to_chat(usr, SPAN_WARNING("DB connection failed."))
		return

	// Get current notes if any
	var/datum/db_query/nq = SSdbcore.NewQuery(
		"SELECT notes FROM ss13_zlevel_persistence WHERE z = :z",
		list("z" = z_pick)
	)
	nq.Execute()
	if(nq.NextRow()) cur_notes = nq.item[1] || ""
	qdel(nq)

	var/new_notes = tgui_input_text(usr, "Label for Z=[z_pick] (optional, e.g. 'Mining'):", "Z Level Label", cur_notes, max_length = 128)

	var/currently_skipped = (z_pick in GLOB.persistence_zlevel_skip)
	var/new_enabled = currently_skipped ? 1 : 0  // toggle

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_zlevel_persistence (z, enabled, notes)
		VALUES (:z, :enabled, :notes)
		ON DUPLICATE KEY UPDATE enabled = VALUES(enabled), notes = VALUES(notes)"},
		list("z" = z_pick, "enabled" = new_enabled, "notes" = (new_notes != "" ? new_notes : null))
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "toggle_zlevel_persistence")
	qdel(q)

	// Update in-memory skip list immediately
	if(new_enabled)
		GLOB.persistence_zlevel_skip -= z_pick
	else
		GLOB.persistence_zlevel_skip |= z_pick

	var/state = new_enabled ? "PERSIST" : "SKIP"
	to_chat(usr, SPAN_GOOD("Z=[z_pick] set to [state][new_notes != "" ? " ([new_notes])" : ""]. Takes effect on next save/load cycle."))
	log_and_message_admins("set Z=[z_pick] persistence to [state][new_notes != "" ? " ([new_notes])" : ""]", usr)

/datum/admins/proc/give_credits_to_player()
	set name = "Give Credits"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/target_ckey = tgui_input_text(usr, "Enter ckey (leave blank to use your own):", "Give Credits", usr.ckey, max_length = 32)
	if(!target_ckey) return
	target_ckey = ckey(target_ckey)

	var/amount = tgui_input_number(usr, "Credits to add to [target_ckey]'s account:", "Give Credits", 1000, 10000000, 0)
	if(isnull(amount) || amount <= 0) return

	// Find account number from cache first, then DB
	var/acct_num = 0
	for(var/cache_key in GLOB.persistence_economy_cache)
		if(findtext(cache_key, "[target_ckey]|") == 1)
			acct_num = GLOB.persistence_economy_cache[cache_key]["account_number"] || 0
			break
	if(!acct_num && SSpersistence.databaseCheckConnection("give_credits"))
		var/datum/db_query/aq = SSdbcore.NewQuery(
			"SELECT account_number FROM ss13_money_accounts WHERE ckey = :ckey ORDER BY id DESC LIMIT 1",
			list("ckey" = target_ckey)
		)
		aq.Execute()
		if(aq.NextRow()) acct_num = text2num(aq.item[1]) || 0
		qdel(aq)

	if(!acct_num)
		to_chat(usr, SPAN_WARNING("No bank account found for '[target_ckey]'. They need to get an ID first."))
		return

	SSeconomy.charge_to_account(acct_num, "Admin", "Admin credit gift by [usr.key]", null, amount)
	to_chat(usr, SPAN_GOOD("Added [amount] credits to [target_ckey]'s account (#[acct_num])."))
	log_and_message_admins("gave [amount] credits to [target_ckey] (account #[acct_num])", usr)

/datum/admins/proc/reset_player_bank_account()
	set name = "Reset Player Bank Account"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/target_ckey = tgui_input_text(usr, "Enter player ckey to wipe Idris bank account(s):", "Reset Bank Account", max_length = 32)
	if(!target_ckey) return
	target_ckey = ckey(target_ckey)

	var/confirm = tgui_alert(usr, "Delete ALL Idris accounts for '[target_ckey]'? They will go through fresh account creation next ID dispense.", "Confirm", list("Delete", "Cancel"))
	if(confirm != "Delete") return

	if(!SSpersistence.databaseCheckConnection("reset_player_bank_account"))
		to_chat(usr, SPAN_WARNING("DB connection failed."))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_money_accounts WHERE ckey = :ckey",
		list("ckey" = target_ckey)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "reset_player_bank_account")
	qdel(q)

	// Purge from in-memory economy cache so the change is immediate
	var/list/to_remove = list()
	for(var/cache_key in GLOB.persistence_economy_cache)
		if(findtext(cache_key, "[target_ckey]|") == 1)
			to_remove += cache_key
	for(var/cache_key in to_remove)
		GLOB.persistence_economy_cache -= cache_key

	to_chat(usr, SPAN_GOOD("Bank account for '[target_ckey]' wiped. They will receive fresh account setup on next ID dispense."))
	log_and_message_admins("wiped Idris bank account for '[target_ckey]'", usr)

/datum/admins/proc/debug_character_spawn_lock()
	set name = "Debug Character Spawn Lock"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/target_ckey = tgui_input_text(usr, "Enter ckey to inspect:", "Spawn Lock Debug", max_length = 32)
	if(!target_ckey) return
	target_ckey = ckey(target_ckey)

	if(!SSpersistence.databaseCheckConnection("debug_character_spawn_lock"))
		to_chat(usr, SPAN_WARNING("DB connection failed."))
		return

	var/datum/db_query/dq = SSdbcore.NewQuery(
		"SELECT name, first_spawned_at, deleted_at FROM ss13_characters WHERE ckey = :ckey ORDER BY id ASC",
		list("ckey" = target_ckey)
	)
	dq.Execute()
	SSpersistence.databaseCheckQueryResult(dq, "debug_character_spawn_lock query")

	var/msg = "Characters for '[target_ckey]':\n"
	var/list/unlockable = list()
	while(dq.NextRow())
		var/cname       = dq.item[1]
		var/spawned_at  = dq.item[2] || "(never spawned)"
		var/deleted_txt = dq.item[3] ? " (DELETED)" : ""
		msg += "  [cname]: first_spawned=[spawned_at][deleted_txt]\n"
		if(!dq.item[3])
			unlockable += cname
	qdel(dq)

	var/action = tgui_alert(usr, msg, "Spawn Lock Debug", list("Unlock a Character", "Close"))
	if(action != "Unlock a Character" || !length(unlockable))
		return

	var/chosen = tgui_input_list(usr, "Select character to unlock:", "Unlock Character", unlockable)
	if(!chosen) return

	var/datum/db_query/uq = SSdbcore.NewQuery(
		"UPDATE ss13_characters SET first_spawned_at = NULL WHERE ckey = :ckey AND name = :name",
		list("ckey" = target_ckey, "name" = chosen)
	)
	uq.Execute()
	SSpersistence.databaseCheckQueryResult(uq, "debug_character_spawn_lock unlock")
	qdel(uq)

	to_chat(usr, SPAN_GOOD("Spawn lock cleared for '[chosen]' ([target_ckey]). They can now edit preferences."))
	log_and_message_admins("cleared spawn lock for [target_ckey] character '[chosen]'", usr)

/datum/admins/proc/give_faction_id()
	set name = "Give Faction ID"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(!islist(GLOB.persistence_faction_cache) || !length(GLOB.persistence_faction_cache))
		to_chat(usr, SPAN_WARNING("No factions exist. Create one via 'Manage Faction Account' first."))
		return

	// Pick target mob
	var/mob/target = tgui_input_list(usr, "Give faction ID to:", "Give Faction ID", GLOB.player_list)
	if(!target) return

	// Pick faction
	var/list/faction_options = list()
	for(var/uid in GLOB.persistence_faction_cache)
		faction_options[get_faction_name(uid)] = uid
	var/chosen_label = tgui_input_list(usr, "Choose faction:", "Give Faction ID", faction_options)
	if(!chosen_label) return
	var/chosen_uid = faction_options[chosen_label]

	// Pick job (or skip to give a blank faction ID)
	var/list/jobs = get_faction_jobs(chosen_uid)
	var/job_title = null
	var/job_rank = 0
	var/list/job_access = list()
	if(length(jobs))
		var/list/job_names = list("(Blank  no job assigned)")
		for(var/list/j in jobs)
			job_names += "[j["title"]] (rank [j["rank"]], [j["pay_rate"]] cr)"
		var/chosen_job_label = tgui_input_list(usr, "Choose job:", "Give Faction ID", job_names)
		if(!chosen_job_label) return
		if(chosen_job_label != "(Blank  no job assigned)")
			for(var/list/j in jobs)
				if(findtext(chosen_job_label, j["title"]) == 1)
					job_title    = j["title"]
					job_rank     = j["rank"] || 0
					job_access   = j["access"] || list()
					break
	else
		to_chat(usr, SPAN_NOTICE("No jobs defined for this faction yet. Issuing a blank faction ID."))

	// Create and issue the card
	var/obj/item/card/id/new_card = new /obj/item/card/id(get_turf(target))
	new_card.registered_name  = target.real_name
	new_card.assignment       = job_title || "Member"
	new_card.rank             = job_title || "Member"
	new_card.employer_faction = chosen_uid
	new_card.name             = "[target.real_name]'s ID Card ([new_card.assignment])"
	new_card.access          |= job_access

	if(istype(target, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = target
		H.set_id_info(new_card)

	target.put_in_hands(new_card)

	// Register member record in DB
	if(target.ckey)
		SSpersistence.factionRegisterMember(target.ckey, target.real_name, chosen_uid, job_title, job_rank || 0)

	to_chat(target, SPAN_GOOD("You have been issued a [get_faction_name(chosen_uid)] ID card[job_title ? " as [job_title]" : ""]."))
	to_chat(usr, SPAN_GOOD("Issued [get_faction_name(chosen_uid)] ID ([job_title || "Member"]) to [target.real_name]."))
	log_and_message_admins("issued [chosen_uid] faction ID ([job_title || "Member"]) to [target.real_name]", usr)
	feedback_add_details("admin_verb", "GFI")

/datum/admins/proc/manage_faction_account()
	set name = "Manage Faction Account"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/list/top_actions = list("Create New Faction", "Modify Faction Balance", "Remove Faction")
	var/top = tgui_input_list(usr, "What would you like to do?", "Manage Factions", top_actions)
	if(!top) return

	//  Create 
	if(top == "Create New Faction")
		var/new_uid = tgui_input_text(usr, "Enter a unique faction ID (lowercase, no spaces, e.g. 'zavodskoi'):", "Create Faction", max_length = 32)
		if(!new_uid) return
		new_uid = lowertext(replacetext(new_uid, " ", "_"))

		if(islist(GLOB.persistence_faction_cache) && (new_uid in GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("A faction with UID '[new_uid]' already exists."))
			return

		var/new_name  = tgui_input_text(usr, "Full faction name:", "Create Faction", max_length = 64)
		if(!new_name) return

		var/new_abbr  = tgui_input_text(usr, "Abbreviation (2-4 letters, e.g. 'ZI'):", "Create Faction", max_length = 8)
		if(!new_abbr) return

		var/starting  = tgui_input_number(usr, "Starting balance (credits):", "Create Faction", 1000000, 100000000, 0)
		if(isnull(starting)) return

		if(!SSpersistence.databaseCheckConnection("create_faction"))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return

		var/datum/db_query/q1 = SSdbcore.NewQuery(
			"INSERT INTO ss13_factions (uid, name, abbreviation, is_lore) VALUES (:uid, :name, :abbr, 0)",
			list("uid" = new_uid, "name" = new_name, "abbr" = new_abbr)
		)
		q1.Execute()
		SSpersistence.databaseCheckQueryResult(q1, "create_faction insert")
		qdel(q1)

		var/datum/db_query/q2 = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance)
			ON DUPLICATE KEY UPDATE balance = VALUES(balance), saved_at = NOW()"},
			list("uid" = new_uid, "balance" = starting)
		)
		q2.Execute()
		SSpersistence.databaseCheckQueryResult(q2, "create_faction account")
		qdel(q2)

		// Add to in-memory cache immediately
		if(!islist(GLOB.persistence_faction_cache))
			GLOB.persistence_faction_cache = list()
		GLOB.persistence_faction_cache[new_uid] = list("name" = new_name, "abbreviation" = new_abbr, "balance" = starting)

		to_chat(usr, SPAN_GOOD("Faction '[new_name]' ([new_uid]) created with [starting] credits."))
		log_and_message_admins("created faction '[new_uid]' ([new_name])", usr)

	//  Modify Balance 
	else if(top == "Modify Faction Balance")
		if(!islist(GLOB.persistence_faction_cache) || !length(GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("No factions exist yet. Create one first."))
			return

		var/list/faction_options = list()
		for(var/uid in GLOB.persistence_faction_cache)
			var/list/data = GLOB.persistence_faction_cache[uid]
			faction_options["[data["name"]] ([uid])  [data["balance"]] cr"] = uid

		var/chosen_label = tgui_input_list(usr, "Select a faction:", "Modify Balance", faction_options)
		if(!chosen_label) return
		var/chosen_uid = faction_options[chosen_label]

		var/action = tgui_input_list(usr, "Action:", "Modify Balance", list("Add Credits", "Remove Credits", "Set Balance"))
		if(!action) return

		var/amount = tgui_input_number(usr, "Amount (credits):", "Modify Balance", 0, 100000000, 0)
		if(isnull(amount)) return

		switch(action)
			if("Add Credits")
				faction_credit(chosen_uid, amount, "Admin adjustment by [usr.key]")
				to_chat(usr, SPAN_GOOD("Added [amount] cr to [get_faction_name(chosen_uid)]. Balance: [get_faction_account_balance(chosen_uid)]"))
			if("Remove Credits")
				GLOB.persistence_faction_cache[chosen_uid]["balance"] = max(0, GLOB.persistence_faction_cache[chosen_uid]["balance"] - amount)
				to_chat(usr, SPAN_GOOD("Removed [amount] cr from [get_faction_name(chosen_uid)]. Balance: [get_faction_account_balance(chosen_uid)]"))
			if("Set Balance")
				GLOB.persistence_faction_cache[chosen_uid]["balance"] = amount
				to_chat(usr, SPAN_GOOD("Set [get_faction_name(chosen_uid)] balance to [amount] cr."))

		// faction_credit/debit already write to DB; handle Set Balance / Remove Credits manually
		if(action != "Add Credits")
			_faction_balance_write(chosen_uid, get_faction_account_balance(chosen_uid))

		log_and_message_admins("[action] [amount] credits for faction [chosen_uid]", usr)

	//  Remove 
	else if(top == "Remove Faction")
		if(!islist(GLOB.persistence_faction_cache) || !length(GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("No factions exist."))
			return

		var/list/faction_options = list()
		for(var/uid in GLOB.persistence_faction_cache)
			faction_options[get_faction_name(uid)] = uid

		var/chosen_label = tgui_input_list(usr, "Select faction to remove:", "Remove Faction", faction_options)
		if(!chosen_label) return
		var/chosen_uid = faction_options[chosen_label]

		var/confirm = tgui_alert(usr, "Permanently delete faction '[get_faction_name(chosen_uid)]' ([chosen_uid]) and all its jobs/data? This cannot be undone.", "Confirm Delete", list("Delete", "Cancel"))
		if(confirm != "Delete") return

		if(!SSpersistence.databaseCheckConnection("remove_faction"))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return

		// CASCADE in DB handles faction_accounts and faction_jobs via foreign key
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_factions WHERE uid = :uid",
			list("uid" = chosen_uid)
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "remove_faction delete")
		qdel(q)

		// Remove from in-memory caches
		GLOB.persistence_faction_cache      -= chosen_uid
		GLOB.persistence_faction_jobs_cache -= chosen_uid

		to_chat(usr, SPAN_GOOD("Faction '[chosen_uid]' removed."))
		log_and_message_admins("removed faction '[chosen_uid]'", usr)

	feedback_add_details("admin_verb", "MFA")

/datum/admins/proc/manage_faction_jobs()
	set name = "Manage Faction Jobs"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(!islist(GLOB.persistence_faction_cache) || !length(GLOB.persistence_faction_cache))
		to_chat(usr, SPAN_WARNING("No factions loaded."))
		return

	var/list/faction_options = list()
	for(var/uid in GLOB.persistence_faction_cache)
		faction_options[get_faction_name(uid)] = uid

	var/chosen_label = tgui_input_list(usr, "Select a faction:", "Manage Faction Jobs", faction_options)
	if(!chosen_label) return
	var/chosen_uid = faction_options[chosen_label]

	var/list/actions = list("Add Job", "Edit Job Access", "Remove Job")
	var/action = tgui_input_list(usr, "Action:", "Manage Faction Jobs", actions)
	if(!action) return

	if(action == "Add Job")
		var/title = tgui_input_text(usr, "Job title:", "Add Faction Job", max_length = 64)
		if(!title) return
		var/pay = tgui_input_number(usr, "Pay rate (credits/cycle):", "Add Faction Job", 500, 50000, 0)
		if(isnull(pay)) return
		var/rank = tgui_input_number(usr, "Rank (0=crew, 1=officer, 2=command):", "Add Faction Job", 0, 2, 0)
		if(isnull(rank)) return

		// Set access codes inline before saving
		var/list/new_job_access = list()
		while(TRUE)
			var/nacc_summary = length(new_job_access) ? "[length(new_job_access)] codes set" : "none"
			var/nacc_sub = tgui_input_list(usr, "Job: [title] -- Access: [nacc_summary]", "Set Job Access", list("Add Access Code", "Add by Region", "Remove Access Code", "Done (no access)"))
			if(!nacc_sub || nacc_sub == "Done (no access)") break
			if(nacc_sub == "Add Access Code")
				var/list/nacc_all_acc = get_all_station_access()
				var/list/nacc_addable = list()
				for(var/nacc_acc in nacc_all_acc)
					if(!(nacc_acc in new_job_access))
						nacc_addable["[get_access_desc(nacc_acc)] ([nacc_acc])"] = nacc_acc
				if(!length(nacc_addable))
					to_chat(usr, SPAN_NOTICE("All access codes already assigned."))
					continue
				var/nacc_add_pick = tgui_input_list(usr, "Select access to add:", "Add Access Code", nacc_addable)
				if(!nacc_add_pick) continue
				new_job_access += nacc_addable[nacc_add_pick]
			else if(nacc_sub == "Add by Region")
				var/list/nacc_regions = list()
				for(var/ri3 = 1; ri3 <= 7; ri3++)
					nacc_regions[get_region_accesses_name(ri3)] = ri3
				var/nacc_reg_pick = tgui_input_list(usr, "Select a region:", "Add by Region", nacc_regions)
				if(!nacc_reg_pick) continue
				var/list/nacc_reg_acc = get_region_accesses(nacc_regions[nacc_reg_pick])
				for(var/nracc in nacc_reg_acc)
					if(!(nracc in new_job_access))
						new_job_access += nracc
			else if(nacc_sub == "Remove Access Code")
				if(!length(new_job_access))
					to_chat(usr, SPAN_NOTICE("No access codes to remove."))
					continue
				var/list/nacc_removable = list()
				for(var/nacc_rem_acc in new_job_access)
					nacc_removable["[get_access_desc(nacc_rem_acc)] ([nacc_rem_acc])"] = nacc_rem_acc
				var/nacc_rem_pick = tgui_input_list(usr, "Select access to remove:", "Remove Access Code", nacc_removable)
				if(!nacc_rem_pick) continue
				new_job_access -= nacc_removable[nacc_rem_pick]

		if(!SSpersistence.databaseCheckConnection("manage_faction_jobs"))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return

		var/new_job_access_json = length(new_job_access) ? json_encode(new_job_access) : null
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_jobs (faction_uid, title, access_json, pay_rate, rank)
			VALUES (:uid, :title, :access, :pay, :rank)
			ON DUPLICATE KEY UPDATE pay_rate = VALUES(pay_rate), rank = VALUES(rank), access_json = VALUES(access_json)"},
			list("uid" = chosen_uid, "title" = title, "access" = new_job_access_json, "pay" = pay, "rank" = rank)
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "manage_faction_jobs add")
		qdel(q)

		// Reload jobs cache for this faction
		if(!(chosen_uid in GLOB.persistence_faction_jobs_cache))
			GLOB.persistence_faction_jobs_cache[chosen_uid] = list()
		GLOB.persistence_faction_jobs_cache[chosen_uid] += list(list("title"=title,"access"=new_job_access,"pay_rate"=pay,"rank"=rank))
		to_chat(usr, SPAN_GOOD("Added job '[title]' to [get_faction_name(chosen_uid)] with [length(new_job_access)] access code(s)."))
		log_and_message_admins("added faction job '[title]' to [chosen_uid] ([length(new_job_access)] access codes)", usr)

	else if(action == "Edit Job Access")
		var/list/edit_jobs = get_faction_jobs(chosen_uid)
		if(!length(edit_jobs))
			to_chat(usr, SPAN_WARNING("No jobs defined for this faction."))
			return
		var/list/edit_job_labels = list()
		for(var/list/ej in edit_jobs)
			var/list/ej_descs = list()
			if(islist(ej["access"]))
				for(var/ej_acc in ej["access"])
					ej_descs += get_access_desc(ej_acc)
			var/ej_acc_label = length(ej_descs) ? jointext(ej_descs, ", ") : "no access"
			edit_job_labels["[ej["title"]] -- [ej_acc_label]"] = ej["title"]
		var/edit_chosen_label = tgui_input_list(usr, "Select job to edit:", "Edit Job Access", edit_job_labels)
		if(!edit_chosen_label) return
		var/edit_title = edit_job_labels[edit_chosen_label]

		// Copy current access list so we can modify without touching cache yet
		var/list/current_access = list()
		for(var/list/ej2 in edit_jobs)
			if(ej2["title"] == edit_title)
				if(islist(ej2["access"]))
					current_access = ej2["access"].Copy()
				break

		// Interactive add/remove loop
		while(TRUE)
			var/acc_summary = length(current_access) ? "[length(current_access)] codes set" : "none"
			var/edit_sub = tgui_input_list(usr, "Job: [edit_title] -- Access: [acc_summary]", "Edit Job Access", list("Add Access Code", "Add by Region", "Remove Access Code", "Save and Done", "Cancel"))
			if(!edit_sub || edit_sub == "Cancel")
				return
			if(edit_sub == "Save and Done")
				break

			if(edit_sub == "Add Access Code")
				var/list/all_acc = get_all_station_access()
				var/list/addable = list()
				for(var/acc in all_acc)
					if(!(acc in current_access))
						addable["[get_access_desc(acc)] ([acc])"] = acc
				if(!length(addable))
					to_chat(usr, SPAN_NOTICE("All access codes already assigned."))
					continue
				var/add_pick = tgui_input_list(usr, "Select access to add:", "Add Access Code", addable)
				if(!add_pick) continue
				current_access += addable[add_pick]

			else if(edit_sub == "Add by Region")
				var/list/ev_regions = list()
				for(var/ri4 = 1; ri4 <= 7; ri4++)
					ev_regions[get_region_accesses_name(ri4)] = ri4
				var/ev_reg_pick = tgui_input_list(usr, "Select a region:", "Add by Region", ev_regions)
				if(!ev_reg_pick) continue
				var/list/ev_reg_acc = get_region_accesses(ev_regions[ev_reg_pick])
				for(var/evracc in ev_reg_acc)
					if(!(evracc in current_access))
						current_access += evracc

			else if(edit_sub == "Remove Access Code")
				if(!length(current_access))
					to_chat(usr, SPAN_NOTICE("No access codes to remove."))
					continue
				var/list/removable = list()
				for(var/rem_acc in current_access)
					removable["[get_access_desc(rem_acc)] ([rem_acc])"] = rem_acc
				var/rem_pick = tgui_input_list(usr, "Select access to remove:", "Remove Access Code", removable)
				if(!rem_pick) continue
				current_access -= removable[rem_pick]

		// Persist to DB
		if(!SSpersistence.databaseCheckConnection("edit_job_access"))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return
		var/new_access_json = length(current_access) ? json_encode(current_access) : null
		var/datum/db_query/uq = SSdbcore.NewQuery(
			"UPDATE ss13_faction_jobs SET access_json = :json WHERE faction_uid = :uid AND title = :title",
			list("json" = new_access_json, "uid" = chosen_uid, "title" = edit_title)
		)
		uq.Execute()
		SSpersistence.databaseCheckQueryResult(uq, "edit_job_access update")
		qdel(uq)

		// Update in-memory cache
		var/list/cached_jobs = GLOB.persistence_faction_jobs_cache[chosen_uid]
		if(islist(cached_jobs))
			for(var/list/cj in cached_jobs)
				if(cj["title"] == edit_title)
					cj["access"] = current_access
					break

		to_chat(usr, SPAN_GOOD("Updated access for '[edit_title]': [length(current_access)] code(s)."))
		log_and_message_admins("edited access for faction job '[edit_title]' in [chosen_uid] ([length(current_access)] codes)", usr)

	else if(action == "Remove Job")
		var/list/jobs = get_faction_jobs(chosen_uid)
		if(!length(jobs))
			to_chat(usr, SPAN_WARNING("No jobs defined for this faction."))
			return
		var/list/job_titles = list()
		for(var/list/j in jobs)
			job_titles += j["title"]
		var/chosen_title = tgui_input_list(usr, "Select job to remove:", "Remove Faction Job", job_titles)
		if(!chosen_title) return

		if(!SSpersistence.databaseCheckConnection("manage_faction_jobs"))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return

		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_faction_jobs WHERE faction_uid = :uid AND title = :title",
			list("uid" = chosen_uid, "title" = chosen_title)
		)
		q.Execute()
		qdel(q)

		// Remove from cache
		var/list/new_jobs = list()
		for(var/list/j in jobs)
			if(j["title"] != chosen_title)
				new_jobs += list(j)
		GLOB.persistence_faction_jobs_cache[chosen_uid] = new_jobs
		to_chat(usr, SPAN_GOOD("Removed job '[chosen_title]' from [get_faction_name(chosen_uid)]."))
		log_and_message_admins("removed faction job '[chosen_title]' from [chosen_uid]", usr)

	feedback_add_details("admin_verb", "MFJ")

// ============================================================
// MEMBER OPERATIONS
// ============================================================

/proc/get_faction_member(ckey, faction_uid)
	if(!islist(GLOB.persistence_faction_members_cache))
		return null
	return GLOB.persistence_faction_members_cache["[ckey]|[faction_uid]"]

/datum/controller/subsystem/persistence/proc/factionRegisterMember(ckey, real_name, faction_uid, job_title = null, rank = 0)
	if(!databaseCheckConnection("factionRegisterMember"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_faction_members (ckey, real_name, faction_uid, job_title, rank)
		VALUES (:ckey, :real_name, :uid, :job, :rank)
		ON DUPLICATE KEY UPDATE real_name = VALUES(real_name), job_title = VALUES(job_title), rank = VALUES(rank)"},
		list("ckey" = ckey, "real_name" = real_name, "uid" = faction_uid, "job" = job_title, "rank" = rank)
	)
	q.Execute()
	var/ok = databaseCheckQueryResult(q, "factionRegisterMember")
	qdel(q)
	if(ok)
		var/mkey = "[ckey]|[faction_uid]"
		GLOB.persistence_faction_members_cache[mkey] = list(
			"real_name" = real_name,
			"job_title" = job_title,
			"rank"      = rank
		)
	return ok

/proc/get_faction_job_access(faction_uid, job_title)
	if(!islist(GLOB.persistence_faction_jobs_cache)) return list()
	var/list/jobs = GLOB.persistence_faction_jobs_cache[faction_uid]
	if(!islist(jobs)) return list()
	for(var/list/j in jobs)
		if(j["title"] == job_title)
			return islist(j["access"]) ? j["access"] : list()
	return list()

/proc/get_faction_job_pay(faction_uid, job_title)
	if(!islist(GLOB.persistence_faction_jobs_cache)) return 0
	var/list/jobs = GLOB.persistence_faction_jobs_cache[faction_uid]
	if(!islist(jobs)) return 0
	for(var/list/j in jobs)
		if(j["title"] == job_title)
			return isnull(j["pay_rate"]) ? 0 : (j["pay_rate"] + 0)
	return 0

// ============================================================
// PAYROLL OPERATIONS
// ============================================================

/datum/controller/subsystem/persistence/proc/factionUpdateMemberAccount(ckey, faction_uid, account_number)
	if(!databaseCheckConnection("factionUpdateMemberAccount"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_faction_members SET account_number = :acct WHERE ckey = :ckey AND faction_uid = :uid",
		list("acct" = account_number, "ckey" = ckey, "uid" = faction_uid)
	)
	q.Execute()
	var/ok = databaseCheckQueryResult(q, "factionUpdateMemberAccount")
	qdel(q)
	// Update cache
	var/mkey = "[ckey]|[faction_uid]"
	if(islist(GLOB.persistence_faction_members_cache) && (mkey in GLOB.persistence_faction_members_cache))
		GLOB.persistence_faction_members_cache[mkey]["account_number"] = account_number
	return ok

/datum/controller/subsystem/persistence/proc/factionPayroll(faction_uid)
	if(!databaseCheckConnection("factionPayroll"))
		return FALSE
	// Load members with valid account numbers
	var/datum/db_query/mq = SSdbcore.NewQuery(
		"SELECT ckey, job_title, account_number FROM ss13_faction_members WHERE faction_uid = :uid AND account_number > 0",
		list("uid" = faction_uid)
	)
	mq.Execute()
	if(!databaseCheckQueryResult(mq, "factionPayroll members"))
		qdel(mq)
		return FALSE

	var/paid = 0
	var/skipped = 0
	while(mq.NextRow())
		var/mkey = mq.item[1]
		var/mjob  = mq.item[2]
		var/macct = text2num(mq.item[3]) || 0
		if(!macct || !mjob)
			skipped++
			continue
		var/pay = get_faction_job_pay(faction_uid, mjob)
		if(pay <= 0)
			skipped++
			continue
		if(!faction_debit(faction_uid, pay, "Payroll to [mkey]"))
			log_game("Faction [faction_uid] payroll: insufficient funds, stopping.")
			break
		SSeconomy.charge_to_account(macct, "Faction Payroll", "Salary from [get_faction_name(faction_uid)]", null, pay)
		paid++
	qdel(mq)

	// Update last_payroll_at in DB
	var/datum/db_query/uq = SSdbcore.NewQuery(
		"UPDATE ss13_factions SET last_payroll_at = NOW() WHERE uid = :uid",
		list("uid" = faction_uid)
	)
	uq.Execute()
	qdel(uq)

	// Update cache timestamp (world.time = deciseconds since server start; resets each session)
	if(islist(GLOB.persistence_faction_cache) && (faction_uid in GLOB.persistence_faction_cache))
		GLOB.persistence_faction_cache[faction_uid]["last_payroll_at"] = world.time

	log_game("Faction [faction_uid] payroll: paid [paid] members, skipped [skipped].")
	return TRUE

