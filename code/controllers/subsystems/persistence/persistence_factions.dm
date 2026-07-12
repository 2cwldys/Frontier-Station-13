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
	try
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"SELECT f.uid, f.name, f.abbreviation, COALESCE(a.balance, 0), COALESCE(a.cards_epoch, 0)
			FROM ss13_factions f
			LEFT JOIN ss13_faction_accounts a ON a.faction_uid = f.uid"},
			list()
		)
		q.Execute()
		if(databaseCheckQueryResult(q, "factionInitialize factions"))
			while(q.NextRow())
				// Normalize keys on load -- legacy rows may carry raw display-name uids
				GLOB.persistence_faction_cache[normalize_faction_uid(q.item[1])] = list(
					"name"         = q.item[2],
					"abbreviation" = q.item[3],
					"balance"      = text2num(q.item[4]) || 0,
					"cards_epoch"  = text2num(q.item[5]) || 0
				)
		qdel(q)
	catch(var/exception/faction_info_e)
		log_subsystem_persistence_error("Factions: failed to load faction info: [faction_info_e]")

	// Load faction jobs
	try
		var/datum/db_query/jq = SSdbcore.NewQuery(
			"SELECT id, faction_uid, title, access_json, pay_rate, rank FROM ss13_faction_jobs ORDER BY faction_uid, rank DESC, title ASC",
			list()
		)
		jq.Execute()
		if(databaseCheckQueryResult(jq, "factionInitialize jobs"))
			while(jq.NextRow())
				var/fuid = normalize_faction_uid(jq.item[2])
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
	catch(var/exception/faction_jobs_e)
		log_subsystem_persistence_error("Factions: failed to load faction jobs: [faction_jobs_e]")

	// Load faction members (include account_number for payroll; column may not exist yet on old DBs)
	try
		var/datum/db_query/mq = SSdbcore.NewQuery(
			"SELECT ckey, faction_uid, real_name, job_title, rank, IFNULL(account_number, 0) FROM ss13_faction_members",
			list()
		)
		mq.Execute()
		if(databaseCheckQueryResult(mq, "factionInitialize members"))
			while(mq.NextRow())
				var/mkey = "[mq.item[1]]|[normalize_faction_uid(mq.item[2])]"
				GLOB.persistence_faction_members_cache[mkey] = list(
					"real_name"      = mq.item[3],
					"job_title"      = mq.item[4],
					"rank"           = text2num(mq.item[5]) || 0,
					"account_number" = text2num(mq.item[6]) || 0
				)
		qdel(mq)
	catch(var/exception/faction_members_e)
		log_subsystem_persistence_error("Factions: failed to load faction members: [faction_members_e]")

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

/// Canonical faction uid form: lowercase, underscores for spaces. Faction cache
/// and DB rows are keyed this way (see admin create at manage_faction_account),
/// but ID cards carry display names -- normalize every lookup and every write.
/proc/normalize_faction_uid(uid)
	if(!istext(uid) || !length(uid))
		return uid
	return lowertext(replacetext(uid, " ", "_"))

/// TRUE if a faction-taggable record should be visible to a console on the
/// given (already-normalized) network. Unshackled consoles (console_net "")
/// see everything -- unchanged station-wide behavior, so the base game never
/// regresses. A shackled console only sees its own faction's slice.
/proc/record_faction_visible(record_faction_uid, console_net)
	if(!console_net)
		return TRUE
	return normalize_faction_uid(record_faction_uid) == console_net

/proc/get_faction_account_balance(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return null
	return GLOB.persistence_faction_cache[uid]["balance"]

/// Current charge-card epoch for a faction. Charge cards store the epoch they
/// were printed under; a card is only valid while its epoch matches this.
/proc/get_faction_cards_epoch(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return 0
	return GLOB.persistence_faction_cache[uid]["cards_epoch"] || 0

/// Bumps a faction's charge-card epoch by 1, instantly invalidating every
/// charge card printed under any older epoch -- online, offline in a
/// cryo-serialized inventory, or sitting on the floor -- since validity is
/// checked live at time of use (is_faction_charge_card_valid()), not tracked
/// per-card.
/proc/invalidate_faction_charge_cards(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	var/new_epoch = (GLOB.persistence_faction_cache[uid]["cards_epoch"] || 0) + 1
	GLOB.persistence_faction_cache[uid]["cards_epoch"] = new_epoch
	log_game("Faction [uid] invalidated all charge cards (epoch -> [new_epoch]).")
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/eq = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_accounts (faction_uid, cards_epoch) VALUES (:uid, :epoch)
			ON DUPLICATE KEY UPDATE cards_epoch = VALUES(cards_epoch), saved_at = NOW()"},
			list("uid" = uid, "epoch" = new_epoch)
		)
		eq.Execute()
		qdel(eq)
	return TRUE

/// A faction charge card is valid only if it was printed under the faction's
/// current epoch. Cards printed before this feature existed (issued_epoch
/// defaults to 0) count as invalid as soon as any cutoff has ever been set.
/proc/is_faction_charge_card_valid(obj/item/spacecash/ewallet/faction_charge_card/FC)
	if(!istype(FC) || !FC.faction_uid)
		return FALSE
	return FC.issued_epoch == get_faction_cards_epoch(FC.faction_uid)

/proc/faction_debit(uid, amount, reason = "transaction")
	uid = normalize_faction_uid(uid)
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
	uid = normalize_faction_uid(uid)
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
	uid = normalize_faction_uid(uid)
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
	uid = normalize_faction_uid(uid)
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return
	var/datum/db_query/bq = SSdbcore.NewQuery(
		{"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance)
		ON DUPLICATE KEY UPDATE balance = VALUES(balance), saved_at = NOW()"},
		list("uid" = uid, "balance" = balance)
	)
	bq.Execute()
	qdel(bq)

/// Prunes faction chat history older than the standard persistence
/// expiration window. Called from SSpersistence.Shutdown().
/datum/controller/subsystem/persistence/proc/factionChatPrune()
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("factionChatPrune"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_faction_chat WHERE sent_at < DATE_SUB(NOW(), INTERVAL :days DAY)",
		list("days" = PERSISTENT_DEFAULT_EXPIRATION_DAYS)
	)
	q.Execute()
	databaseCheckQueryResult(q, "factionChatPrune")
	qdel(q)

// ============================================================
// JOB OPERATIONS
// ============================================================

/proc/get_faction_jobs(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_jobs_cache))
		return list()
	return GLOB.persistence_faction_jobs_cache[uid] || list()

/proc/get_faction_name(uid)
	uid = normalize_faction_uid(uid)
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
			try
				var/fuid     = q.item[1]
				var/tech_raw = q.item[2]
				var/list/tech_list = tech_raw ? json_decode(tech_raw) : list()
				if(islist(tech_list))
					GLOB.persistence_faction_research_cache[fuid] = tech_list
			catch(var/exception/e)
				log_subsystem_persistence_error("FactionResearch: failed to load a research row: [e]")
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

/**
 * Shared authorization check for anything that shackles/configures an
 * object's faction ownership (modular computers, telepads, cryopods, lace
 * storage, telecomms, the faction beacon) -- admins always pass; otherwise
 * requires at least rank_required standing (default 1 = officer) in the
 * target faction. Replaces the ad-hoc admin-or-rank checks that used to be
 * copy-pasted (and inconsistently applied) in each type's own verbs.
 */
/proc/can_configure_faction_shackle(mob/user, faction_uid, rank_required = 1)
	if(check_rights(R_ADMIN, 0, user))
		return TRUE
	if(!faction_uid)
		return FALSE
	var/list/member = get_faction_member(user.ckey, faction_uid)
	var/rank = member ? (member["rank"] || 0) : -1
	return rank >= rank_required

/**
 * Private, faction-scoped heads-up notification -- separate from (and layered
 * alongside) the global Arrivals Announcer, which stays untouched. Only other
 * members of the same faction as `character` (resolved via their ID's
 * employer_faction, not the unrelated mob-level lore faction var) see it.
 */
/proc/announce_faction_event(mob/living/carbon/human/character, message_suffix)
	if(SSticker.current_state != GAME_STATE_PLAYING || !istype(character))
		return
	var/obj/item/card/id/ID = character.GetIdCard()
	var/arriving_uid = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	if(!arriving_uid)
		return
	var/fname = get_faction_name(arriving_uid)
	for(var/mob/living/carbon/human/H in GLOB.player_list)
		if(H == character || !H.client)
			continue
		var/obj/item/card/id/HID = H.GetIdCard()
		var/h_uid = (HID && HID.employer_faction) ? normalize_faction_uid(HID.employer_faction) : null
		if(h_uid != arriving_uid)
			continue
		to_chat(H, SPAN_NOTICE("<b>[fname]:</b> [character.real_name] [message_suffix]"))

/proc/announce_faction_cryo_exit(mob/living/carbon/human/character)
	announce_faction_event(character, "has exited cryogenic storage.")

/proc/announce_faction_cryo_enter(mob/living/carbon/human/character)
	announce_faction_event(character, "has entered cryogenic storage.")

/**
 * Write a Z-level's persistence enabled/notes to ss13_zlevel_persistence and
 * update the in-memory allow/skip lists immediately. Shared by the admin
 * toggle verb and by faction beacon claim/destruction (a beacon claiming a
 * Z should make sure it's actually in the save list; losing a beacon should
 * take it back out).
 */
/datum/controller/subsystem/persistence/proc/setZLevelPersistence(z, enabled, notes)
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_zlevel_persistence (map_path, z, enabled, notes)
		VALUES (:mp, :z, :enabled, :notes)
		ON DUPLICATE KEY UPDATE enabled = VALUES(enabled), notes = VALUES(notes)"},
		list("mp" = "[SSatlas.current_map.path]", "z" = z, "enabled" = enabled, "notes" = notes)
	)
	q.Execute()
	databaseCheckQueryResult(q, "setZLevelPersistence")
	qdel(q)
	if(enabled)
		GLOB.persistence_zlevel_skip -= z
		GLOB.persistence_zlevel_allow |= z
	else
		GLOB.persistence_zlevel_skip |= z
		GLOB.persistence_zlevel_allow -= z

// ============================================================
// ADMIN VERBS
// ============================================================

/datum/admins/proc/toggle_zlevel_persistence()
	set name = "Toggle Z-Level Persistence"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	// Build status display. Under MANUAL_AREA_SAVE persistence is opt-in:
	// only z-levels explicitly enabled (allow list) save/load.
	var/manual_mode = GLOB.config.manual_area_save
	var/msg = "Current Z-Level Persistence[manual_mode ? " (MANUAL_AREA_SAVE: opt-in)" : ""]:\n"
	for(var/z = 1 to world.maxz)
		var/persists
		if(manual_mode)
			persists = (z in GLOB.persistence_zlevel_allow)
		else
			persists = !(z in GLOB.persistence_zlevel_skip)
		msg += "  Z=[z]: [persists ? "PERSIST (saves/loads)" : "SKIP (regenerates each restart)"]\n"

	var/z_pick = tgui_input_number(usr, "[msg]\nZ=[usr.z] is your current level. Enter Z level to toggle:", "Toggle Z Persistence", usr.z, world.maxz, 1)
	if(isnull(z_pick) || z_pick < 1 || z_pick > world.maxz)
		return

	var/cur_notes = ""
	if(!SSpersistence.databaseCheckConnection("toggle_zlevel_persistence"))
		to_chat(usr, SPAN_WARNING("DB connection failed."))
		return

	// Get current notes if any
	var/datum/db_query/nq = SSdbcore.NewQuery(
		"SELECT notes FROM ss13_zlevel_persistence WHERE map_path = :mp AND z = :z",
		list("mp" = "[SSatlas.current_map.path]", "z" = z_pick)
	)
	nq.Execute()
	if(nq.NextRow()) cur_notes = nq.item[1] || ""
	qdel(nq)

	var/new_notes = tgui_input_text(usr, "Label for Z=[z_pick] (optional, e.g. 'Mining'):", "Z Level Label", cur_notes, max_length = 128)

	// Toggle off the EFFECTIVE state -- under manual mode a z with no DB row
	// is blocked, so toggling it must write enabled=1 (add to the allow list)
	var/currently_persists
	if(GLOB.config.manual_area_save)
		currently_persists = (z_pick in GLOB.persistence_zlevel_allow)
	else
		currently_persists = !(z_pick in GLOB.persistence_zlevel_skip)
	var/new_enabled = currently_persists ? 0 : 1  // toggle

	SSpersistence.setZLevelPersistence(z_pick, new_enabled, new_notes != "" ? new_notes : null)

	var/state = new_enabled ? "PERSIST" : "SKIP"
	to_chat(usr, SPAN_GOOD("Z=[z_pick] set to [state][new_notes != "" ? " ([new_notes])" : ""]. Takes effect on next save/load cycle."))
	log_and_message_admins("set Z=[z_pick] persistence to [state][new_notes != "" ? " ([new_notes])" : ""]", usr)

/// View and edit the MANUAL_AREA_SAVE allow list as a whole -- add/remove
/// z-levels with labels, backed by ss13_zlevel_persistence (enabled = 1 rows).
/datum/admins/proc/manage_manual_save_list()
	set name = "Manual Z-Level Save List"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(!SSpersistence.databaseCheckConnection("manage_manual_save_list"))
		to_chat(usr, SPAN_WARNING("DB connection failed."))
		return

	while(TRUE)
		// Fetch labels fresh each pass so edits show immediately
		var/list/notes_by_z = list()
		var/datum/db_query/nq = SSdbcore.NewQuery(
			"SELECT z, notes FROM ss13_zlevel_persistence WHERE map_path = :mp AND enabled = 1",
			list("mp" = "[SSatlas.current_map.path]"))
		nq.Execute()
		while(nq.NextRow())
			notes_by_z["[text2num(nq.item[1])]"] = nq.item[2] || ""
		qdel(nq)

		var/msg = "Manual Z-Level Save List [GLOB.config.manual_area_save ? "(MANUAL_AREA_SAVE active -- ONLY listed z-levels save/load)" : "(MANUAL_AREA_SAVE is OFF -- list stored but dormant)"]:\n"
		for(var/z = 1 to world.maxz)
			var/here = (z == usr.z) ? " <- you are here" : ""
			// Identify what this z actually is so admins know what's safe to list
			var/identity = ""
			var/obj/effect/overmap/visitable/z_sector = GLOB.map_sectors["[z]"]
			if(z in GLOB.persistence_pinned_site_z)
				identity = " -- PINNED SITE (auto-saves[z_sector ? ": [z_sector.name]" : ""])"
			else if(is_centcom_level(z))
				identity = " -- CentCom/admin"
			else if(SSmapping.level_trait(z, ZTRAIT_OVERMAP))
				identity = " -- Overmap chart"
			else if(is_reserved_level(z))
				identity = " -- reserved (shuttle transit)"
			else if(is_mining_level(z))
				identity = " -- mining (regenerates)"
			else if(is_away_level(z) || (z in GLOB.persistence_template_loaded_z))
				identity = " -- away site/POI[z_sector ? " ([z_sector.name])" : ""] -- DYNAMIC, do not list; use Persistent Overmap Sites"
			else if(is_station_level(z))
				identity = " -- station deck[z_sector ? " ([z_sector.name])" : ""]"
			else if(SSmapping.z_list && z <= length(SSmapping.z_list))
				identity = " -- [SSmapping.z_list[z].name]"
			if(z in GLOB.persistence_zlevel_allow)
				var/disp_label = notes_by_z["[z]"]
				msg += "  Z=[z]: IN LIST[disp_label ? " ([disp_label])" : ""][identity][here]\n"
			else
				msg += "  Z=[z]: not listed[identity][here]\n"
		to_chat(usr, SPAN_NOTICE(msg))

		var/action = tgui_input_list(usr, "Select action:", "Manual Z-Level Save List", list("Add Z-Level", "Remove Z-Level", "Close"))
		if(!action || action == "Close")
			return

		if(action == "Add Z-Level")
			var/z_pick = tgui_input_number(usr, "Enter Z level to add to the manual save list:", "Add Z-Level", usr.z, world.maxz, 1)
			if(isnull(z_pick) || z_pick < 1 || z_pick > world.maxz)
				continue
			var/add_label = tgui_input_text(usr, "Label for Z=[z_pick] (optional, e.g. 'Start'):", "Z Level Label", notes_by_z["[z_pick]"], max_length = 128)
			var/datum/db_query/q = SSdbcore.NewQuery(
				{"INSERT INTO ss13_zlevel_persistence (map_path, z, enabled, notes)
				VALUES (:mp, :z, 1, :notes)
				ON DUPLICATE KEY UPDATE enabled = 1, notes = VALUES(notes)"},
				list("mp" = "[SSatlas.current_map.path]", "z" = z_pick, "notes" = (add_label != "" ? add_label : null))
			)
			q.Execute()
			SSpersistence.databaseCheckQueryResult(q, "manage_manual_save_list add")
			qdel(q)
			GLOB.persistence_zlevel_allow |= z_pick
			GLOB.persistence_zlevel_skip -= z_pick
			to_chat(usr, SPAN_GOOD("Z=[z_pick] added to the manual save list[add_label ? " ([add_label])" : ""]."))
			log_and_message_admins("added Z=[z_pick] to the manual z-level save list[add_label ? " ([add_label])" : ""]", usr)

		else if(action == "Remove Z-Level")
			if(!length(GLOB.persistence_zlevel_allow))
				to_chat(usr, SPAN_WARNING("The manual save list is empty."))
				continue
			var/list/choices = list()
			for(var/az in GLOB.persistence_zlevel_allow)
				var/rem_label = notes_by_z["[az]"]
				choices["Z=[az][rem_label ? " ([rem_label])" : ""]"] = az
			var/pick = tgui_input_list(usr, "Remove which z-level from the manual save list?", "Remove Z-Level", choices)
			if(!pick)
				continue
			var/z_out = choices[pick]
			// DELETE returns the z to "unlisted" -- blocked under manual mode but
			// NOT added to the normal-mode skip list (that stays the Toggle verb's job)
			var/datum/db_query/dq = SSdbcore.NewQuery(
				"DELETE FROM ss13_zlevel_persistence WHERE map_path = :mp AND z = :z",
				list("mp" = "[SSatlas.current_map.path]", "z" = z_out)
			)
			dq.Execute()
			SSpersistence.databaseCheckQueryResult(dq, "manage_manual_save_list remove")
			qdel(dq)
			GLOB.persistence_zlevel_allow -= z_out
			to_chat(usr, SPAN_GOOD("Z=[z_out] removed from the manual save list."))
			log_and_message_admins("removed Z=[z_out] from the manual z-level save list", usr)

/**
 * Pin the away site occupying z, exactly like the "Persistent Overmap
 * Sites" admin verb's "Pin Site I'm At" action below -- callable from code,
 * no admin mob needed. Returns TRUE if a site is now pinned (including if
 * it already was), FALSE if z isn't a valid pinnable away site (empty, an
 * exoplanet, or not loaded from a ruin/away_site template -- e.g. the main
 * station or a player ship).
 */
/proc/persistence_pin_site_at_z(z, notes)
	var/obj/effect/overmap/visitable/here_marker = GLOB.map_sectors["[z]"]
	// Ships/shuttles (player-flown or the main station itself) are never
	// pinnable -- explicit guard even though the template check below would
	// already exclude them (ships aren't loaded from ruin/away_site
	// templates), so the exclusion is never accidentally dependent on that.
	if(istype(here_marker, /obj/effect/overmap/visitable/ship))
		return FALSE
	if(istype(here_marker, /obj/effect/overmap/visitable/sector/exoplanet))
		return FALSE
	var/datum/map_template/here_template = GLOB.map_templates["[z]"]
	if(!istype(here_template, /datum/map_template/ruin/away_site))
		return FALSE
	if(!SSpersistence.databaseCheckConnection("persistence_pin_site_at_z"))
		return FALSE

	var/datum/db_query/check = SSdbcore.NewQuery(
		"SELECT id FROM ss13_persistent_away_sites WHERE template_name = :tn AND map_path = :mp",
		list("tn" = here_template.id, "mp" = "[SSatlas.current_map.path]")
	)
	check.Execute()
	var/already_pinned = check.NextRow()
	qdel(check)
	if(already_pinned)
		return TRUE

	var/base_z = z
	var/list/live_zs = list(z)
	if(here_marker && length(here_marker.map_z))
		live_zs = here_marker.map_z.Copy()
		base_z = live_zs[1]
		for(var/mz in live_zs)
			base_z = min(base_z, mz)

	var/datum/db_query/iq = SSdbcore.NewQuery(
		{"INSERT INTO ss13_persistent_away_sites (template_name, map_path, overmap_x, overmap_y, last_z, enabled, notes)
		VALUES (:tn, :mp, :ox, :oy, :z, 1, :notes)
		ON DUPLICATE KEY UPDATE enabled = 1, notes = VALUES(notes)"},
		list(
			"tn" = here_template.id, "mp" = "[SSatlas.current_map.path]",
			"ox" = (here_marker ? here_marker.start_x : 0), "oy" = (here_marker ? here_marker.start_y : 0),
			"z"  = base_z, "notes" = notes
		)
	)
	iq.Execute()
	SSpersistence.databaseCheckQueryResult(iq, "persistence_pin_site_at_z")
	qdel(iq)

	for(var/nz in live_zs)
		GLOB.persistence_pinned_site_z |= nz
		GLOB.persistence_zlevel_allow |= nz
	log_game("Site '[here_template.id]' at z=[base_z] auto-pinned: [notes]")
	return TRUE

/**
 * Reverses persistence_pin_site_at_z() -- but only if the site's pin
 * "notes" exactly match expected_notes, so this can never touch a site
 * pinned by an admin (or for a different reason) that a faction beacon
 * merely happened to also be sitting on. Only removes the pin
 * registration itself (DB row + in-memory lists), matching "Unpin Site"'s
 * "Keep" option -- doesn't purge any saved persistence rows.
 */
/proc/persistence_unpin_site_at_z(z, expected_notes)
	var/datum/map_template/here_template = GLOB.map_templates["[z]"]
	if(!istype(here_template, /datum/map_template/ruin/away_site))
		return FALSE
	if(!SSpersistence.databaseCheckConnection("persistence_unpin_site_at_z"))
		return FALSE

	var/datum/db_query/check = SSdbcore.NewQuery(
		"SELECT id, notes, last_z FROM ss13_persistent_away_sites WHERE template_name = :tn AND map_path = :mp",
		list("tn" = here_template.id, "mp" = "[SSatlas.current_map.path]")
	)
	check.Execute()
	if(!SSpersistence.databaseCheckQueryResult(check, "persistence_unpin_site_at_z") || !check.NextRow())
		qdel(check)
		return FALSE
	var/row_id = text2num(check.item[1])
	var/row_notes = check.item[2]
	var/row_last_z = text2num(check.item[3])
	qdel(check)
	if(row_notes != expected_notes)
		return FALSE // pinned by something else (admin, different reason) -- not ours to touch

	var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_persistent_away_sites WHERE id = :id", list("id" = row_id))
	dq.Execute()
	SSpersistence.databaseCheckQueryResult(dq, "persistence_unpin_site_at_z delete")
	qdel(dq)

	var/obj/effect/overmap/visitable/here_marker = GLOB.map_sectors["[row_last_z]"]
	var/list/live_zs = list(row_last_z)
	if(here_marker && length(here_marker.map_z))
		live_zs = here_marker.map_z.Copy()
	for(var/nz in live_zs)
		GLOB.persistence_pinned_site_z -= nz
		GLOB.persistence_zlevel_allow -= nz
	log_game("Site '[here_template.id]' at z=[row_last_z] auto-unpinned: [expected_notes] released.")
	return TRUE

/// Pin/unpin overmap away sites for persistence (ss13_persistent_away_sites).
/// A pinned site always spawns, keeps its overmap position, gets a
/// deterministic z-number, and saves/loads like a station deck. Default for
/// all sites remains dynamic (fresh each boot). Exoplanets cannot be pinned
/// (procedurally generated every boot -- no fixed template to respawn).
/datum/admins/proc/manage_persistent_overmap_sites()
	set name = "Persistent Overmap Sites"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(!SSpersistence.databaseCheckConnection("manage_persistent_overmap_sites"))
		to_chat(usr, SPAN_WARNING("DB connection failed."))
		return

	while(TRUE)
		// Fresh row read each pass so edits show immediately
		var/list/rows = list()
		var/datum/db_query/pq = SSdbcore.NewQuery(
			"SELECT id, template_name, overmap_x, overmap_y, last_z, enabled, notes, custom_name, custom_icon_state FROM ss13_persistent_away_sites WHERE map_path = :mp ORDER BY id ASC",
			list("mp" = "[SSatlas.current_map.path]")
		)
		pq.Execute()
		while(pq.NextRow())
			rows += list(list(
				"id"          = text2num(pq.item[1]),
				"template"    = pq.item[2],
				"om_x"        = text2num(pq.item[3]),
				"om_y"        = text2num(pq.item[4]),
				"last_z"      = text2num(pq.item[5]),
				"enabled"     = text2num(pq.item[6]),
				"notes"       = pq.item[7] || "",
				"custom_name" = pq.item[8] || "",
				"custom_icon" = pq.item[9] || ""
			))
		qdel(pq)

		var/msg = "Persistent Overmap Sites (pinned away sites):\n"
		if(!length(rows))
			msg += "  (none pinned -- every overmap site is dynamic and resets each boot)\n"
		for(var/list/row in rows)
			var/live = (row["last_z"] && (row["last_z"] in GLOB.persistence_pinned_site_z)) ? "live at z=[row["last_z"]]" : "takes effect next boot"
			var/appearance_info = ""
			if(row["custom_name"])
				appearance_info += ", named '[row["custom_name"]]'"
			if(row["custom_icon"])
				appearance_info += ", icon '[row["custom_icon"]]'"
			msg += "  #[row["id"]] [row["template"]][row["notes"] ? " ([row["notes"]])" : ""] -- [row["enabled"] ? "ENABLED" : "disabled"], overmap ([row["om_x"]],[row["om_y"]])[appearance_info], [live]\n"
		to_chat(usr, SPAN_NOTICE(msg))

		var/action = tgui_input_list(usr, "Select action:", "Persistent Overmap Sites", list("Pin Site I'm At", "Pin From Template List", "Rename Site", "Change Icon", "Toggle Enabled", "Unpin Site", "Close"))
		if(!action || action == "Close")
			return

		if(action == "Pin Site I'm At")
			var/obj/effect/overmap/visitable/here_marker = GLOB.map_sectors["[usr.z]"]
			if(istype(here_marker, /obj/effect/overmap/visitable/sector/exoplanet))
				to_chat(usr, SPAN_WARNING("Exoplanets are procedurally generated every boot (no fixed template) and cannot be pinned."))
				continue
			var/datum/map_template/here_template = GLOB.map_templates["[usr.z]"]
			if(!istype(here_template, /datum/map_template/ruin/away_site))
				to_chat(usr, SPAN_WARNING("Z=[usr.z] was not loaded from an away-site template -- stand on the site you want to pin."))
				continue
			var/already_pinned = FALSE
			for(var/list/row in rows)
				if(row["template"] == here_template.id)
					already_pinned = TRUE
					break
			if(already_pinned)
				to_chat(usr, SPAN_WARNING("'[here_template.id]' is already pinned."))
				continue
			var/pin_label = tgui_input_text(usr, "Label for this site (optional):", "Pin Site", "", max_length = 128)
			// The site's base z this session (lowest of its connected z's)
			var/base_z = usr.z
			var/list/live_zs = list(usr.z)
			if(here_marker && length(here_marker.map_z))
				live_zs = here_marker.map_z.Copy()
				base_z = live_zs[1]
				for(var/mz in live_zs)
					base_z = min(base_z, mz)
			var/datum/db_query/iq = SSdbcore.NewQuery(
				{"INSERT INTO ss13_persistent_away_sites (template_name, map_path, overmap_x, overmap_y, last_z, enabled, notes)
				VALUES (:tn, :mp, :ox, :oy, :z, 1, :notes)
				ON DUPLICATE KEY UPDATE enabled = 1, notes = VALUES(notes)"},
				list(
					"tn" = here_template.id,
					"mp" = "[SSatlas.current_map.path]",
					"ox" = (here_marker ? here_marker.start_x : 0),
					"oy" = (here_marker ? here_marker.start_y : 0),
					"z"  = base_z,
					"notes" = (pin_label != "" ? pin_label : null)
				)
			)
			iq.Execute()
			SSpersistence.databaseCheckQueryResult(iq, "persistent_overmap_sites pin")
			qdel(iq)
			// Live activation: the site starts saving from the next save pass
			// this session; next boot it respawns pinned (rows remapped to its
			// deterministic z automatically).
			for(var/nz in live_zs)
				GLOB.persistence_pinned_site_z |= nz
				GLOB.persistence_zlevel_allow |= nz
			to_chat(usr, SPAN_GOOD("Pinned '[here_template.id]'[pin_label ? " ([pin_label])" : ""] -- persisting from the next save, respawns every boot at overmap ([here_marker ? "[here_marker.start_x],[here_marker.start_y]" : "?,?"])."))
			log_and_message_admins("pinned overmap site '[here_template.id]' for persistence[pin_label ? " ([pin_label])" : ""]", usr)

		else if(action == "Pin From Template List")
			var/list/pinnable = list()
			for(var/site_id in SSmapping.away_sites_templates)
				var/id_taken = FALSE
				for(var/list/row in rows)
					if(row["template"] == site_id)
						id_taken = TRUE
						break
				if(!id_taken)
					pinnable += site_id
			if(!length(pinnable))
				to_chat(usr, SPAN_WARNING("Every away-site template is already pinned."))
				continue
			var/tmpl_pick = tgui_input_list(usr, "Pin which away-site template? It will spawn pinned starting next boot.", "Pin From Template List", pinnable)
			if(!tmpl_pick)
				continue
			var/list_label = tgui_input_text(usr, "Label for this site (optional):", "Pin Site", "", max_length = 128)
			var/datum/db_query/lq = SSdbcore.NewQuery(
				{"INSERT INTO ss13_persistent_away_sites (template_name, map_path, overmap_x, overmap_y, last_z, enabled, notes)
				VALUES (:tn, :mp, 0, 0, 0, 1, :notes)
				ON DUPLICATE KEY UPDATE enabled = 1, notes = VALUES(notes)"},
				list("tn" = tmpl_pick, "mp" = "[SSatlas.current_map.path]", "notes" = (list_label != "" ? list_label : null))
			)
			lq.Execute()
			SSpersistence.databaseCheckQueryResult(lq, "persistent_overmap_sites pin-list")
			qdel(lq)
			to_chat(usr, SPAN_GOOD("Pinned '[tmpl_pick]'[list_label ? " ([list_label])" : ""] -- spawns pinned starting next boot (overmap position recorded on first spawn)."))
			log_and_message_admins("pinned overmap site '[tmpl_pick]' for persistence (from template list)", usr)

		else if(action == "Rename Site")
			if(!length(rows))
				to_chat(usr, SPAN_WARNING("No sites are pinned."))
				continue
			var/list/rename_choices = list()
			for(var/list/row in rows)
				rename_choices["#[row["id"]] [row["template"]][row["custom_name"] ? " ('[row["custom_name"]]')" : ""]"] = row
			var/rename_pick = tgui_input_list(usr, "Rename which pinned site?", "Rename Site", rename_choices)
			if(!rename_pick)
				continue
			var/list/rename_row = rename_choices[rename_pick]
			var/new_site_name = tgui_input_text(usr, "New overmap name for '[rename_row["template"]]' (leave blank to restore the template default):", "Rename Site", rename_row["custom_name"], max_length = 128)
			if(isnull(new_site_name))
				continue
			var/datum/db_query/rnq = SSdbcore.NewQuery(
				"UPDATE ss13_persistent_away_sites SET custom_name = :cn WHERE id = :id",
				list("cn" = (new_site_name != "" ? new_site_name : null), "id" = rename_row["id"])
			)
			rnq.Execute()
			SSpersistence.databaseCheckQueryResult(rnq, "persistent_overmap_sites rename")
			qdel(rnq)
			// Apply live if the site is spawned this session -- verify the
			// marker at last_z is actually still THIS site's before trusting
			// it. last_z can go stale if an earlier-id pinned row failed to
			// load this boot (template removed, load_new_z() failure):
			// build_pinned_away_sites()'s sequential-append z allocation
			// then shifts every later row down, and a later site can land
			// exactly on the failed row's old z -- without this check that
			// would rename an unrelated, currently-loaded site's marker.
			if(rename_row["last_z"] && (rename_row["last_z"] in GLOB.persistence_pinned_site_z))
				var/obj/effect/overmap/visitable/rename_marker = GLOB.map_sectors["[rename_row["last_z"]]"]
				var/datum/map_template/rename_template = GLOB.map_templates["[rename_row["last_z"]]"]
				if(rename_marker && rename_template && rename_template.id == rename_row["template"])
					rename_marker.name = (new_site_name != "" ? new_site_name : initial(rename_marker.name))
			to_chat(usr, SPAN_GOOD("'[rename_row["template"]]' [new_site_name != "" ? "renamed to '[new_site_name]'" : "name restored to template default"] -- persists across reboots."))
			log_and_message_admins("[new_site_name != "" ? "renamed pinned overmap site '[rename_row["template"]]' to '[new_site_name]'" : "cleared custom name on pinned overmap site '[rename_row["template"]]'"]", usr)

		else if(action == "Change Icon")
			if(!length(rows))
				to_chat(usr, SPAN_WARNING("No sites are pinned."))
				continue
			var/list/icon_site_choices = list()
			for(var/list/row in rows)
				icon_site_choices["#[row["id"]] [row["template"]][row["custom_icon"] ? " ('[row["custom_icon"]]')" : ""]"] = row
			var/icon_site_pick = tgui_input_list(usr, "Change the overmap icon of which pinned site?", "Change Icon", icon_site_choices)
			if(!icon_site_pick)
				continue
			var/list/icon_row = icon_site_choices[icon_site_pick]
			// Runtime enumeration -- any sprite later added to the sheet becomes pickable
			var/list/icon_options = list("(template default)") + icon_states('icons/obj/overmap/overmap_effects.dmi')
			var/icon_pick = tgui_input_list(usr, "New overmap icon for '[icon_row["template"]]':", "Change Icon", icon_options)
			if(!icon_pick)
				continue
			var/new_icon_state = (icon_pick == "(template default)") ? null : icon_pick
			var/datum/db_query/icq = SSdbcore.NewQuery(
				"UPDATE ss13_persistent_away_sites SET custom_icon_state = :ci WHERE id = :id",
				list("ci" = new_icon_state, "id" = icon_row["id"])
			)
			icq.Execute()
			SSpersistence.databaseCheckQueryResult(icq, "persistent_overmap_sites change icon")
			qdel(icq)
			if(icon_row["last_z"] && (icon_row["last_z"] in GLOB.persistence_pinned_site_z))
				var/obj/effect/overmap/visitable/icon_marker = GLOB.map_sectors["[icon_row["last_z"]]"]
				if(icon_marker)
					icon_marker.icon_state = new_icon_state || initial(icon_marker.icon_state)
					icon_marker.update_icon()
			to_chat(usr, SPAN_GOOD("'[icon_row["template"]]' overmap icon [new_icon_state ? "set to '[new_icon_state]'" : "restored to template default"] -- persists across reboots."))
			log_and_message_admins("[new_icon_state ? "set pinned overmap site '[icon_row["template"]]' icon to '[new_icon_state]'" : "cleared custom icon on pinned overmap site '[icon_row["template"]]'"]", usr)

		else if(action == "Toggle Enabled")
			if(!length(rows))
				to_chat(usr, SPAN_WARNING("No sites are pinned."))
				continue
			var/list/toggle_choices = list()
			for(var/list/row in rows)
				toggle_choices["#[row["id"]] [row["template"]][row["custom_name"] ? " ('[row["custom_name"]]')" : ""] ([row["enabled"] ? "ENABLED" : "disabled"])"] = row
			var/toggle_pick = tgui_input_list(usr, "Toggle which pinned site?", "Toggle Enabled", toggle_choices)
			if(!toggle_pick)
				continue
			var/list/toggle_row = toggle_choices[toggle_pick]
			var/new_state = toggle_row["enabled"] ? 0 : 1
			var/datum/db_query/tq = SSdbcore.NewQuery(
				"UPDATE ss13_persistent_away_sites SET enabled = :en WHERE id = :id",
				list("en" = new_state, "id" = toggle_row["id"])
			)
			tq.Execute()
			SSpersistence.databaseCheckQueryResult(tq, "persistent_overmap_sites toggle")
			qdel(tq)
			if(!new_state && toggle_row["last_z"] && (toggle_row["last_z"] in GLOB.persistence_pinned_site_z))
				GLOB.persistence_pinned_site_z -= toggle_row["last_z"]
				GLOB.persistence_zlevel_allow -= toggle_row["last_z"]
			to_chat(usr, SPAN_GOOD("'[toggle_row["template"]]' is now [new_state ? "ENABLED (persists from next boot)" : "disabled (dynamic again from next boot; saved rows kept)"]."))
			log_and_message_admins("[new_state ? "enabled" : "disabled"] pinned overmap site '[toggle_row["template"]]'", usr)

		else if(action == "Unpin Site")
			if(!length(rows))
				to_chat(usr, SPAN_WARNING("No sites are pinned."))
				continue
			var/list/unpin_choices = list()
			for(var/list/row in rows)
				unpin_choices["#[row["id"]] [row["template"]][row["custom_name"] ? " ('[row["custom_name"]]')" : ""][row["notes"] ? " ([row["notes"]])" : ""]"] = row
			var/unpin_pick = tgui_input_list(usr, "Unpin which site? It returns to the dynamic RNG pool next boot.", "Unpin Site", unpin_choices)
			if(!unpin_pick)
				continue
			var/list/unpin_row = unpin_choices[unpin_pick]
			var/purge_choice = tgui_alert(usr, "Also purge '[unpin_row["template"]]'s saved persistence rows (z=[unpin_row["last_z"]])? 'Keep' leaves them orphaned in the DB.", "Unpin Site", list("Purge", "Keep", "Cancel"))
			if(!purge_choice || purge_choice == "Cancel")
				continue
			var/datum/db_query/uq = SSdbcore.NewQuery(
				"DELETE FROM ss13_persistent_away_sites WHERE id = :id",
				list("id" = unpin_row["id"])
			)
			uq.Execute()
			SSpersistence.databaseCheckQueryResult(uq, "persistent_overmap_sites unpin")
			qdel(uq)
			if(purge_choice == "Purge" && unpin_row["last_z"])
				SSpersistence.purgeZRows(unpin_row["last_z"])
			if(unpin_row["last_z"] && (unpin_row["last_z"] in GLOB.persistence_pinned_site_z))
				GLOB.persistence_pinned_site_z -= unpin_row["last_z"]
				GLOB.persistence_zlevel_allow -= unpin_row["last_z"]
			to_chat(usr, SPAN_GOOD("Unpinned '[unpin_row["template"]]'[purge_choice == "Purge" ? " and purged its saved rows" : " (saved rows kept)"]. Dynamic again from next boot."))
			log_and_message_admins("unpinned overmap site '[unpin_row["template"]]'[purge_choice == "Purge" ? " (rows purged)" : ""]", usr)

/// Inject an away-site template at a chosen overmap tile at runtime -- the
/// same kind of z-level that normally only spawns randomly at boot, placed
/// deliberately mid-session. The site is DYNAMIC (gone on reboot, never saved)
/// unless subsequently pinned via Persistent Overmap Sites, which then
/// respawns it at this exact spot every boot with full persistence.
/datum/admins/proc/generate_away_site()
	set name = "Generate Away Site"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(SSticker.current_state < GAME_STATE_PREGAME)
		to_chat(usr, SPAN_WARNING("Wait for the master controller to initialize before loading maps."))
		return
	if(!SSatlas.current_map.overmap_z)
		to_chat(usr, SPAN_WARNING("This map has no overmap."))
		return

	var/tmpl_pick = tgui_input_list(usr, "Which away-site template to generate?", "Generate Away Site", SSmapping.away_sites_templates)
	if(!tmpl_pick)
		return
	var/datum/map_template/ruin/away_site/site = SSmapping.away_sites_templates[tmpl_pick]
	if(!site)
		return
	if(site.loaded && !(site.template_flags & TEMPLATE_FLAG_ALLOW_DUPLICATES))
		to_chat(usr, SPAN_WARNING("'[tmpl_pick]' is already loaded somewhere in the world and does not allow duplicates."))
		return

	// Position: standing on the overmap chart (ghost flyover) defaults to your
	// tile -- the "visual" picker. Coordinates can always be entered manually.
	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
	var/default_x = (usr.z == SSatlas.current_map.overmap_z) ? usr.x : map_low
	var/default_y = (usr.z == SSatlas.current_map.overmap_z) ? usr.y : map_low
	var/pick_x = tgui_input_number(usr, "Overmap X ([map_low]-[map_high])[usr.z == SSatlas.current_map.overmap_z ? " -- defaulting to your current tile" : ""]:", "Generate Away Site", default_x, map_high, map_low)
	if(isnull(pick_x))
		return
	var/pick_y = tgui_input_number(usr, "Overmap Y ([map_low]-[map_high]):", "Generate Away Site", default_y, map_high, map_low)
	if(isnull(pick_y))
		return
	pick_x = clamp(pick_x, map_low, map_high)
	pick_y = clamp(pick_y, map_low, map_high)

	var/turf/target_tile = locate(pick_x, pick_y, SSatlas.current_map.overmap_z)
	if(!target_tile)
		to_chat(usr, SPAN_WARNING("No overmap tile at ([pick_x],[pick_y])."))
		return
	var/obj/effect/overmap/visitable/occupant = locate() in target_tile
	if(occupant)
		to_chat(usr, SPAN_WARNING("([pick_x],[pick_y]) is already occupied by '[occupant.name]' -- pick another tile."))
		return

	log_and_message_admins("is generating away site '[tmpl_pick]' at overmap ([pick_x],[pick_y])", usr)

	// Suspend ZAS during the load or the freshly loaded site gets vented
	// (same recipe as the Map Template - Place In New Z verb).
	var/z_before = world.maxz
	SSair.can_fire = FALSE
	var/bounds = site.load_new_z(FALSE)
	SSair.can_fire = TRUE
	if(!bounds)
		to_chat(usr, SPAN_WARNING("Failed to load '[tmpl_pick]'."))
		log_and_message_admins("failed to generate away site '[tmpl_pick]'", usr)
		return

	var/site_z = z_before + 1
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[site_z]"]
	if(marker)
		marker.start_x = pick_x
		marker.start_y = pick_y
		if(marker.loc)
			marker.forceMove(target_tile)

	// Paint the new marker's zone-security outline/border immediately --
	// otherwise it sits unpainted until some unrelated later zone change
	// happens to trigger a full repaint (zone_security_update_overmap()
	// is only ever called at boot or on an explicit zone change).
	zone_security_update_overmap()

	to_chat(usr, SPAN_GOOD("Generated '[tmpl_pick]' at overmap ([pick_x],[pick_y]), z=[site_z]. It is DYNAMIC (gone on reboot, not saved) -- pin it via Persistent Overmap Sites to make it permanent."))
	log_and_message_admins("generated away site '[tmpl_pick]' at overmap ([pick_x],[pick_y]), z=[site_z]", usr)

/**
 * Fully removes a currently-loaded away site (pinned or dynamic) -- wipes its
 * turfs to space, deletes its overmap marker, and cleans up any DB rows.
 * Unlike "Unpin Site" (which only returns a pinned site to the dynamic pool
 * for next boot), this removes it immediately. Refuses if zlevel_has_players()
 * finds anyone still on that z, including a disembodied neural-lace
 * consciousness sitting in vault storage with no mob present at all.
 */
/datum/admins/proc/remove_away_site()
	set name = "Remove Away Site"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/list/candidates = list()
	for(var/key in GLOB.map_sectors)
		var/z = text2num(key)
		if(!z)
			continue
		var/datum/map_template/tmpl = GLOB.map_templates[key]
		if(!istype(tmpl, /datum/map_template/ruin/away_site))
			continue
		var/obj/effect/overmap/visitable/marker = GLOB.map_sectors[key]
		var/pinned = (z in GLOB.persistence_pinned_site_z)
		candidates["Z=[z] '[tmpl.id]'[marker ? " ([marker.name])" : ""][pinned ? " -- PINNED" : " -- dynamic"]"] = z

	if(!length(candidates))
		to_chat(usr, SPAN_WARNING("No away sites are currently loaded."))
		return

	var/pick = tgui_input_list(usr, "Remove which away site? This is immediate and cannot be undone.", "Remove Away Site", candidates)
	if(!pick)
		return
	var/z_pick = candidates[pick]

	if(zlevel_has_players(z_pick))
		to_chat(usr, SPAN_DANGER("Cannot remove Z=[z_pick] -- a player (possibly a stored neural-lace consciousness) is still present. Make sure everyone -- and every vaulted lace -- is clear first."))
		return

	var/confirm = tgui_alert(usr, "Remove the away site at Z=[z_pick]? This immediately wipes its turfs and deletes its overmap marker. Cannot be undone.", "Remove Away Site", list("Remove", "Cancel"))
	if(confirm != "Remove")
		return

	var/datum/map_template/tmpl = GLOB.map_templates["[z_pick]"]

	if(z_pick in GLOB.persistence_pinned_site_z)
		var/datum/db_query/find_row = SSdbcore.NewQuery(
			"SELECT id FROM ss13_persistent_away_sites WHERE template_name = :tn AND map_path = :mp",
			list("tn" = tmpl.id, "mp" = "[SSatlas.current_map.path]")
		)
		find_row.Execute()
		var/row_id = find_row.NextRow() ? text2num(find_row.item[1]) : null
		qdel(find_row)
		if(row_id)
			var/purge_choice = tgui_alert(usr, "Also purge '[tmpl.id]'s saved persistence rows (z=[z_pick])? 'Keep' leaves them orphaned in the DB.", "Remove Away Site", list("Purge", "Keep"))
			var/datum/db_query/del_row = SSdbcore.NewQuery(
				"DELETE FROM ss13_persistent_away_sites WHERE id = :id",
				list("id" = row_id)
			)
			del_row.Execute()
			SSpersistence.databaseCheckQueryResult(del_row, "remove_away_site unpin")
			qdel(del_row)
			if(purge_choice == "Purge")
				SSpersistence.purgeZRows(z_pick)
		GLOB.persistence_pinned_site_z -= z_pick
		GLOB.persistence_zlevel_allow -= z_pick
	else
		// Dynamic site -- no away-site row to clean, but purge any incidental
		// persistence rows regardless (harmless no-op if none exist).
		SSpersistence.purgeZRows(z_pick)

	// Clean up zone security + persistence-toggle rows/state for this z too --
	// otherwise a stale tier/toggle could silently apply to whatever different
	// site happens to load at this same Z number on a future boot. Runs
	// unconditionally (pinned or dynamic) since either could independently
	// have accumulated a security tier or persistence toggle.
	if(SSpersistence.databaseCheckConnection("remove_away_site cleanup"))
		var/datum/db_query/del_sec = SSdbcore.NewQuery(
			"DELETE FROM ss13_zone_security WHERE z = :z AND map_path = :mp",
			list("z" = z_pick, "mp" = "[SSatlas.current_map.path]")
		)
		del_sec.Execute()
		qdel(del_sec)
		var/datum/db_query/del_persist = SSdbcore.NewQuery(
			"DELETE FROM ss13_zlevel_persistence WHERE z = :z AND map_path = :mp",
			list("z" = z_pick, "mp" = "[SSatlas.current_map.path]")
		)
		del_persist.Execute()
		qdel(del_persist)
	GLOB.zone_security_by_z -= "[z_pick]"
	GLOB.persistence_zlevel_skip -= z_pick
	GLOB.persistence_zlevel_allow -= z_pick

	// Teardown: delete every remaining atom/mob (already guaranteed
	// player-free by the guard above), wipe turfs to plain space, then remove
	// the overmap marker. Snapshot each turf's contents first -- can't qdel
	// while iterating a turf's live contents list (same gotcha reset_zlevel()
	// already works around).
	for(var/turf/T in block(locate(1, 1, z_pick), locate(world.maxx, world.maxy, z_pick)))
		var/list/contents_snapshot = T.contents.Copy()
		for(var/atom/movable/AM in contents_snapshot)
			qdel(AM)
		T.ChangeTurf(/turf/space)
		CHECK_TICK

	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[z_pick]"]
	if(marker)
		qdel(marker)
	GLOB.map_sectors -= "[z_pick]"
	zone_security_update_overmap()

	to_chat(usr, SPAN_GOOD("Removed the away site at Z=[z_pick]."))
	log_and_message_admins("removed away site at Z=[z_pick]", usr)

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
		new_uid = normalize_faction_uid(new_uid)

		if(islist(GLOB.persistence_faction_cache) && (new_uid in GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("A faction with UID '[new_uid]' already exists."))
			return

		var/new_name  = tgui_input_text(usr, "Full faction name:", "Create Faction", max_length = 64)
		if(!new_name) return
		new_name = lowertext(new_name)

		if(islist(GLOB.persistence_faction_cache))
			for(var/existing_uid in GLOB.persistence_faction_cache)
				var/list/existing = GLOB.persistence_faction_cache[existing_uid]
				if(lowertext(existing["name"]) == new_name)
					to_chat(usr, SPAN_WARNING("A faction named '[new_name]' already exists (uid '[existing_uid]')."))
					return

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
	faction_uid = normalize_faction_uid(faction_uid)
	if(!islist(GLOB.persistence_faction_members_cache))
		return null
	return GLOB.persistence_faction_members_cache["[ckey]|[faction_uid]"]

/datum/controller/subsystem/persistence/proc/factionRegisterMember(ckey, real_name, faction_uid, job_title = null, rank = 0)
	faction_uid = normalize_faction_uid(faction_uid)
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
	faction_uid = normalize_faction_uid(faction_uid)
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
	faction_uid = normalize_faction_uid(faction_uid)
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

// ============================================================
// STAGED (OFFLINE) REVOKES
// ============================================================

/**
 * Consumes any pending ID revokes staged for this character while they were
 * offline (see "revoke_member_id" in faction_manage.dm). Called from
 * PersistentAutoSpawn() after inventory is restored, so any ID card the
 * character was carrying -- worn, held, or in a bag/pocket -- is present to
 * be swept. Marks each row processed so it never re-applies.
 */
/mob/living/carbon/human/proc/applyPendingFactionRevokes()
	if(!GLOB.config.sql_enabled || !ckey)
		return
	if(!SSpersistence.databaseCheckConnection("applyPendingFactionRevokes"))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, faction_uid, target_name FROM ss13_faction_pending_revokes WHERE target_ckey = :ckey AND processed = 0",
		list("ckey" = ckey)
	)
	q.Execute()
	if(!SSpersistence.databaseCheckQueryResult(q, "applyPendingFactionRevokes"))
		qdel(q)
		return

	var/list/pending = list()
	while(q.NextRow())
		pending += list(list(
			"id"          = text2num(q.item[1]),
			"faction_uid" = normalize_faction_uid(q.item[2]),
			"target_name" = q.item[3]
		))
	qdel(q)

	if(!length(pending))
		return

	for(var/list/revoke in pending)
		var/revoked_count = 0
		for(var/obj/item/card/id/ID in get_all_contents_of_type(/obj/item/card/id))
			if(ID.revoked)
				continue
			if(ID.registered_name != revoke["target_name"])
				continue
			if(normalize_faction_uid(ID.employer_faction) != revoke["faction_uid"])
				continue
			ID.revoked = TRUE
			ID.access = list()
			ID.update_name()
			revoked_count++

		var/datum/db_query/uq = SSdbcore.NewQuery(
			"UPDATE ss13_faction_pending_revokes SET processed = 1 WHERE id = :id",
			list("id" = revoke["id"])
		)
		uq.Execute()
		qdel(uq)

		log_subsystem_persistence_info("Applied staged faction ID revoke for [real_name] ([ckey]), faction [revoke["faction_uid"]]: [revoked_count] card(s) revoked.")

