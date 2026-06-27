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

// ============================================================
// INITIALIZE
// ============================================================

/datum/controller/subsystem/persistence/proc/factionInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_faction_cache      = list()
	GLOB.persistence_faction_jobs_cache = list()

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

	log_subsystem_persistence_info("Factions: Loaded [length(GLOB.persistence_faction_cache)] factions.")

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
	return TRUE

/proc/faction_credit(uid, amount, reason = "transaction")
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	if(amount <= 0)
		return FALSE
	GLOB.persistence_faction_cache[uid]["balance"] += amount
	log_game("Faction [uid] credited [amount] credits: [reason]")
	return TRUE

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

		var/starting  = tgui_input_number(usr, "Starting balance (credits):", "Create Faction", 1000000, 0, 100000000)
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
			"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance)",
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

		var/amount = tgui_input_number(usr, "Amount (credits):", "Modify Balance", 0, 0, 100000000)
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

	var/list/actions = list("Add Job", "Remove Job")
	var/action = tgui_input_list(usr, "Action:", "Manage Faction Jobs", actions)
	if(!action) return

	if(action == "Add Job")
		var/title = tgui_input_text(usr, "Job title:", "Add Faction Job", max_length = 64)
		if(!title) return
		var/pay = tgui_input_number(usr, "Pay rate (credits/cycle):", "Add Faction Job", 500, 0, 50000)
		if(isnull(pay)) return
		var/rank = tgui_input_number(usr, "Rank (0=crew, 1=officer, 2=command):", "Add Faction Job", 0, 0, 2)
		if(isnull(rank)) return

		if(!SSpersistence.databaseCheckConnection("manage_faction_jobs"))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return

		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_jobs (faction_uid, title, access_json, pay_rate, rank)
			VALUES (:uid, :title, NULL, :pay, :rank)
			ON DUPLICATE KEY UPDATE pay_rate = VALUES(pay_rate), rank = VALUES(rank)"},
			list("uid" = chosen_uid, "title" = title, "pay" = pay, "rank" = rank)
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "manage_faction_jobs add")
		qdel(q)

		// Reload jobs cache for this faction
		if(!(chosen_uid in GLOB.persistence_faction_jobs_cache))
			GLOB.persistence_faction_jobs_cache[chosen_uid] = list()
		GLOB.persistence_faction_jobs_cache[chosen_uid] += list(list("title"=title,"access"=list(),"pay_rate"=pay,"rank"=rank))
		to_chat(usr, SPAN_GOOD("Added job '[title]' to [get_faction_name(chosen_uid)]."))
		log_and_message_admins("added faction job '[title]' to [chosen_uid]", usr)

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
