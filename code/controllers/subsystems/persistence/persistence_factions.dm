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

/// In-memory founding petitions keyed by faction_uid: list("founder_ckey"=...,
/// "founder_name"=...,"faction_name"=...,"abbreviation"=...,"supporters"=list of ckeys,
/// "created_at"=...). Populated by faction_manage.dm's "start_founding" action,
/// mutated by tap-consent/terminal self-consent, consumed on finalization.
GLOBAL_LIST_EMPTY(persistence_faction_founding_petitions)

// ============================================================
// INITIALIZE
// ============================================================

/datum/controller/subsystem/persistence/proc/factionInitialize()
	PRIVATE_PROC(TRUE)
	if(!islist(GLOB.persistence_faction_cache))
		GLOB.persistence_faction_cache = list()
	if(!islist(GLOB.persistence_faction_jobs_cache))
		GLOB.persistence_faction_jobs_cache = list()
	if(!islist(GLOB.persistence_faction_members_cache))
		GLOB.persistence_faction_members_cache = list()

	if(!databaseCheckConnection("factionInitialize"))
		return

	// Load faction info + balances
	try
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"SELECT f.uid, f.name, f.abbreviation, COALESCE(a.balance, 0), COALESCE(a.cards_epoch, 0), f.founder_ckey, COALESCE(a.master_card_lost, 0), f.color, COALESCE(f.auto_payroll, 1)
			FROM ss13_factions f
			LEFT JOIN ss13_faction_accounts a ON a.faction_uid = f.uid"},
			list()
		)
		q.Execute()
		if(databaseCheckQueryResult(q, "factionInitialize factions"))
			var/list/loaded = list()
			while(q.NextRow())
				// Normalize keys on load -- legacy rows may carry raw display-name uids
				loaded[normalize_faction_uid(q.item[1])] = list(
					"name"             = q.item[2],
					"abbreviation"     = q.item[3],
					"balance"          = text2num(q.item[4]) || 0,
					"cards_epoch"      = text2num(q.item[5]) || 0,
					"founder_ckey"     = q.item[6],
					"master_card_lost" = !!text2num(q.item[7]),
					"color"            = q.item[8],
					"auto_payroll"     = !!text2num(q.item[9])
				)
			GLOB.persistence_faction_cache = loaded // only replace on confirmed success
		else
			message_admins("Faction load query failed -- factions may be running on stale/empty data. Check DB schema (db_update?).")
		qdel(q)
	catch(var/exception/faction_info_e)
		message_admins("Faction load threw an exception: [faction_info_e] -- factions may be running on stale/empty data.")
		log_subsystem_persistence_error("Factions: failed to load faction info: [faction_info_e]")

	// Load faction jobs
	try
		var/datum/db_query/jq = SSdbcore.NewQuery(
			"SELECT id, faction_uid, title, access_json, pay_rate, rank FROM ss13_faction_jobs ORDER BY faction_uid, rank DESC, title ASC",
			list()
		)
		jq.Execute()
		if(databaseCheckQueryResult(jq, "factionInitialize jobs"))
			var/list/loaded_jobs = list()
			while(jq.NextRow())
				var/fuid = normalize_faction_uid(jq.item[2])
				if(!(fuid in loaded_jobs))
					loaded_jobs[fuid] = list()
				var/list/job_access = list()
				if(jq.item[4])
					try
						var/decoded = json_decode(jq.item[4])
						if(islist(decoded))
							job_access = decoded
					catch(var/exception/access_decode_e)
						log_subsystem_persistence_error("Factions: bad access_json for job '[jq.item[3]]' in faction '[fuid]' (id [jq.item[1]]): [access_decode_e] -- treating as no access.")
				loaded_jobs[fuid] += list(list(
					"id"       = text2num(jq.item[1]),
					"title"    = jq.item[3],
					"access"   = job_access,
					"pay_rate" = text2num(jq.item[5]) || 500,
					"rank"     = text2num(jq.item[6]) || 0
				))
			GLOB.persistence_faction_jobs_cache = loaded_jobs // only replace on confirmed success
		else
			message_admins("Faction jobs load query failed -- faction jobs may be running on stale/empty data. Check DB schema (db_update?).")
		qdel(jq)
	catch(var/exception/faction_jobs_e)
		message_admins("Faction jobs load threw an exception: [faction_jobs_e] -- faction jobs may be running on stale/empty data.")
		log_subsystem_persistence_error("Factions: failed to load faction jobs: [faction_jobs_e]")

	// Load faction members (include account_number for payroll; column may not exist yet on old DBs)
	try
		var/datum/db_query/mq = SSdbcore.NewQuery(
			"SELECT ckey, faction_uid, real_name, job_title, rank, IFNULL(account_number, 0) FROM ss13_faction_members",
			list()
		)
		mq.Execute()
		if(databaseCheckQueryResult(mq, "factionInitialize members"))
			var/list/loaded_members = list()
			while(mq.NextRow())
				var/mkey = "[mq.item[1]]|[normalize_faction_uid(mq.item[2])]"
				loaded_members[mkey] = list(
					"real_name"      = mq.item[3],
					"job_title"      = mq.item[4],
					"rank"           = text2num(mq.item[5]) || 0,
					"account_number" = text2num(mq.item[6]) || 0
				)
			GLOB.persistence_faction_members_cache = loaded_members // only replace on confirmed success
		else
			message_admins("Faction members load query failed -- faction members may be running on stale/empty data. Check DB schema (db_update?).")
		qdel(mq)
	catch(var/exception/faction_members_e)
		message_admins("Faction members load threw an exception: [faction_members_e] -- faction members may be running on stale/empty data.")
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

		// Auto-payroll: runs unconditionally on every autosave cycle (every 30
		// minutes, persistence.dm) for any faction with automatic payroll
		// enabled -- no interval/timestamp reconciliation needed since the
		// subsystem itself already guarantees the cadence.
		if(data["auto_payroll"])
			factionPayroll(uid)

	log_subsystem_persistence_info("Factions: Saved [length(GLOB.persistence_faction_cache)] faction accounts.")

// ============================================================
// FOUNDING PETITIONS
// ============================================================

/datum/controller/subsystem/persistence/proc/factionFoundingInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_faction_founding_petitions = list()

	if(!databaseCheckConnection("factionFoundingInitialize"))
		return

	try
		var/datum/db_query/q = SSdbcore.NewQuery(
			"SELECT faction_uid, founder_ckey, founder_name, faction_name, abbreviation FROM ss13_faction_founding_petitions",
			list()
		)
		q.Execute()
		if(databaseCheckQueryResult(q, "factionFoundingInitialize petitions"))
			while(q.NextRow())
				GLOB.persistence_faction_founding_petitions[q.item[1]] = list(
					"founder_ckey" = q.item[2],
					"founder_name" = q.item[3],
					"faction_name" = q.item[4],
					"abbreviation" = q.item[5],
					"supporters"   = list()
				)
		qdel(q)
	catch(var/exception/founding_e)
		log_subsystem_persistence_error("Factions: failed to load founding petitions: [founding_e]")

	try
		var/datum/db_query/sq = SSdbcore.NewQuery(
			"SELECT faction_uid, supporter_ckey FROM ss13_faction_founding_supporters",
			list()
		)
		sq.Execute()
		if(databaseCheckQueryResult(sq, "factionFoundingInitialize supporters"))
			while(sq.NextRow())
				var/list/petition = GLOB.persistence_faction_founding_petitions[sq.item[1]]
				if(islist(petition))
					petition["supporters"] += sq.item[2]
		qdel(sq)
	catch(var/exception/supporters_e)
		log_subsystem_persistence_error("Factions: failed to load founding supporters: [supporters_e]")

	log_subsystem_persistence_info("Factions: Loaded [length(GLOB.persistence_faction_founding_petitions)] founding petitions.")

/datum/controller/subsystem/persistence/proc/startFoundingPetition(faction_uid, founder_ckey, founder_name, faction_name, abbreviation)
	faction_uid = normalize_faction_uid(faction_uid)
	if(!databaseCheckConnection("startFoundingPetition"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_founding_petitions (faction_uid, founder_ckey, founder_name, faction_name, abbreviation) VALUES (:uid, :ckey, :name, :fname, :abbr)",
		list("uid" = faction_uid, "ckey" = founder_ckey, "name" = founder_name, "fname" = faction_name, "abbr" = abbreviation)
	)
	q.Execute()
	var/ok = databaseCheckQueryResult(q, "startFoundingPetition")
	qdel(q)
	if(ok)
		GLOB.persistence_faction_founding_petitions[faction_uid] = list(
			"founder_ckey" = founder_ckey,
			"founder_name" = founder_name,
			"faction_name" = faction_name,
			"abbreviation" = abbreviation,
			"supporters"   = list()
		)
	return ok

/// Returns TRUE only if ckey was newly added -- FALSE if they were already
/// a supporter (dedup chokepoint, backed by the supporters table's
/// composite primary key so a race between tap and terminal consent can't
/// double-count the same ckey).
/datum/controller/subsystem/persistence/proc/addFoundingSupporter(faction_uid, ckey)
	faction_uid = normalize_faction_uid(faction_uid)
	var/list/petition = GLOB.persistence_faction_founding_petitions[faction_uid]
	if(!islist(petition))
		return FALSE
	if(ckey in petition["supporters"])
		return FALSE
	if(!databaseCheckConnection("addFoundingSupporter"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_founding_supporters (faction_uid, supporter_ckey) VALUES (:uid, :ckey) ON DUPLICATE KEY UPDATE supported_at = supported_at",
		list("uid" = faction_uid, "ckey" = ckey)
	)
	q.Execute()
	var/ok = databaseCheckQueryResult(q, "addFoundingSupporter")
	qdel(q)
	if(ok)
		petition["supporters"] += ckey
	return ok

/datum/controller/subsystem/persistence/proc/cancelFoundingPetition(faction_uid)
	faction_uid = normalize_faction_uid(faction_uid)
	if(databaseCheckConnection("cancelFoundingPetition"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_faction_founding_petitions WHERE faction_uid = :uid",
			list("uid" = faction_uid)
		)
		q.Execute()
		databaseCheckQueryResult(q, "cancelFoundingPetition")
		qdel(q)
	GLOB.persistence_faction_founding_petitions -= faction_uid

/// Attempts to finalize a founding petition that has already reached its
/// supporter threshold. Offline-safe: resolves the founder's bank account
/// purely by ckey (cache first, DB fallback -- same lookup
/// give_credits_to_player() uses), so this does NOT require the founder to
/// be connected, let alone looking at a specific terminal. Called
/// immediately when the threshold is reached (faction_manage.dm's
/// _try_add_supporter()), opportunistically while the founder has Faction
/// Management open (ui_data()), and by factionFoundingSweep() below on
/// every persistence save cycle -- that sweep is what actually closes the
/// gap where a petition could sit forever if the founder never happened to
/// reopen the one terminal that started it. Returns TRUE if it actually
/// created the faction.
/datum/controller/subsystem/persistence/proc/tryFinalizeFounding(faction_uid)
	faction_uid = normalize_faction_uid(faction_uid)
	var/list/petition = GLOB.persistence_faction_founding_petitions[faction_uid]
	if(!petition)
		return FALSE
	if(length(petition["supporters"]) < FACTION_FOUNDING_REQUIRED_SUPPORTERS)
		return FALSE
	if(islist(GLOB.persistence_faction_cache) && (faction_uid in GLOB.persistence_faction_cache))
		cancelFoundingPetition(faction_uid)
		return FALSE

	var/founder_ckey = petition["founder_ckey"]

	// Resolve the founder's bank account purely by ckey -- cache first, DB
	// fallback -- same pattern give_credits_to_player() uses. Works whether
	// or not the founder is currently connected.
	var/acct_num = 0
	for(var/cache_key in GLOB.persistence_economy_cache)
		if(findtext(cache_key, "[founder_ckey]|") == 1)
			acct_num = GLOB.persistence_economy_cache[cache_key]["account_number"] || 0
			break
	if(!acct_num && databaseCheckConnection("tryFinalizeFounding account lookup"))
		var/datum/db_query/aq = SSdbcore.NewQuery(
			"SELECT account_number FROM ss13_money_accounts WHERE ckey = :ckey ORDER BY id DESC LIMIT 1",
			list("ckey" = founder_ckey)
		)
		aq.Execute()
		if(aq.NextRow())
			acct_num = text2num(aq.item[1]) || 0
		qdel(aq)

	var/datum/money_account/acc = acct_num ? SSeconomy.get_account(acct_num) : null
	if(!acc || acc.money < FACTION_CREATION_COST)
		return FALSE // stays queued -- retried next sweep/poll

	if(!databaseCheckConnection("tryFinalizeFounding"))
		return FALSE

	SSeconomy.charge_to_account(acct_num, "Faction Founding", "Founded faction '[petition["faction_name"]]'", null, -FACTION_CREATION_COST)

	var/datum/db_query/cf_q1 = SSdbcore.NewQuery(
		"INSERT INTO ss13_factions (uid, name, abbreviation, is_lore, founder_ckey) VALUES (:uid, :name, :abbr, 0, :founder)",
		list("uid" = faction_uid, "name" = petition["faction_name"], "abbr" = petition["abbreviation"], "founder" = founder_ckey)
	)
	cf_q1.Execute()
	databaseCheckQueryResult(cf_q1, "tryFinalizeFounding insert")
	qdel(cf_q1)

	var/datum/db_query/cf_q2 = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance) ON DUPLICATE KEY UPDATE balance = VALUES(balance), saved_at = NOW()",
		list("uid" = faction_uid, "balance" = FACTION_CREATION_COST)
	)
	cf_q2.Execute()
	databaseCheckQueryResult(cf_q2, "tryFinalizeFounding account")
	qdel(cf_q2)

	if(!islist(GLOB.persistence_faction_cache))
		GLOB.persistence_faction_cache = list()
	GLOB.persistence_faction_cache[faction_uid] = list("name" = petition["faction_name"], "abbreviation" = petition["abbreviation"], "balance" = FACTION_CREATION_COST, "founder_ckey" = founder_ckey, "master_card_lost" = FALSE)
	if(!islist(GLOB.persistence_faction_jobs_cache))
		GLOB.persistence_faction_jobs_cache = list()
	GLOB.persistence_faction_jobs_cache[faction_uid] = list()

	factionRegisterMember(founder_ckey, petition["founder_name"], faction_uid, null, 2)

	// Master card spawn point: the founder's own turf if they're currently
	// online, else any existing terminal already shackled to this network
	// (the one that started the petition, if nothing else) -- same
	// world-scan-by-persistent_network shape persistence_cryo's telepad
	// delivery lookup already uses.
	var/client/founder_client = GLOB.directory[founder_ckey]
	var/mob/founder_mob = founder_client ? founder_client.mob : null
	var/turf/spawn_turf = founder_mob ? get_turf(founder_mob) : null
	if(!spawn_turf)
		for(var/obj/item/modular_computer/MC in world)
			if(normalize_faction_uid(MC.persistent_network) == faction_uid)
				spawn_turf = get_turf(MC)
				break
	if(spawn_turf)
		var/obj/item/card/id/faction_master/master_card = new(spawn_turf)
		master_card.employer_faction = faction_uid
		master_card.update_name()
	else
		message_admins("Faction '[petition["faction_name"]]' ([faction_uid]) founded, but no valid location was found to print its master card -- spawn one manually.")

	if(founder_mob)
		to_chat(founder_mob, SPAN_GOOD("Founding petition successful! '[petition["faction_name"]]' ([faction_uid]) is now a registered faction with a starting balance of [FACTION_CREATION_COST] credits.[spawn_turf ? " A faction master card has been printed." : ""]"))
	log_game("Founding petition for '[faction_uid]' ([petition["faction_name"]]) succeeded -- founder [petition["founder_name"]] ([founder_ckey]), [length(petition["supporters"])] supporters, [FACTION_CREATION_COST] credits paid.")
	message_admins("A founding petition succeeded: '[petition["faction_name"]]' ([faction_uid]), founded by [petition["founder_name"]] ([founder_ckey]) with [length(petition["supporters"])] supporters, paying [FACTION_CREATION_COST] credits.[founder_mob ? " (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[founder_mob.x];Y=[founder_mob.y];Z=[founder_mob.z]'>JMP</a>)" : ""]")

	cancelFoundingPetition(faction_uid)
	return TRUE

/// Periodic catch-all, called from forceSaveAll() (every persistence save
/// cycle): sweeps every founding petition that has reached its supporter
/// threshold and retries finalization. This is the actual fix for the gap
/// where a finished petition could sit forever unless the founder
/// specifically reopened the one terminal that started it -- now it
/// finalizes automatically as soon as they're online (anywhere) with
/// sufficient funds, no terminal required.
/datum/controller/subsystem/persistence/proc/factionFoundingSweep()
	if(!islist(GLOB.persistence_faction_founding_petitions))
		return
	for(var/faction_uid in GLOB.persistence_faction_founding_petitions.Copy())
		var/list/petition = GLOB.persistence_faction_founding_petitions[faction_uid]
		if(islist(petition) && length(petition["supporters"]) >= FACTION_FOUNDING_REQUIRED_SUPPORTERS)
			tryFinalizeFounding(faction_uid)

// ============================================================
// FACTION CREATION TOGGLE
// ============================================================

/datum/controller/subsystem/persistence/proc/factionCreationToggleInitialize()
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("factionCreationToggleInitialize"))
		return
	try
		var/datum/db_query/q = SSdbcore.NewQuery("SELECT enabled FROM ss13_faction_creation_toggle WHERE id = 1", list())
		q.Execute()
		if(databaseCheckQueryResult(q, "factionCreationToggleInitialize") && q.NextRow())
			GLOB.faction_creation_enabled = text2num(q.item[1])
		qdel(q)
	catch(var/exception/toggle_e)
		log_subsystem_persistence_error("Factions: failed to load faction creation toggle: [toggle_e]")

/datum/controller/subsystem/persistence/proc/setFactionCreationEnabled(enabled)
	GLOB.faction_creation_enabled = enabled
	if(!databaseCheckConnection("setFactionCreationEnabled"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_creation_toggle (id, enabled) VALUES (1, :enabled) ON DUPLICATE KEY UPDATE enabled = VALUES(enabled)",
		list("enabled" = enabled ? 1 : 0)
	)
	q.Execute()
	databaseCheckQueryResult(q, "setFactionCreationEnabled")
	qdel(q)

/datum/admins/proc/toggle_faction_creation()
	set name = "Toggle Faction Creation"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/new_state = !GLOB.faction_creation_enabled
	if(tgui_alert(usr, "Faction creation is currently [GLOB.faction_creation_enabled ? "ENABLED" : "DISABLED"]. [new_state ? "Enable" : "Disable"] it?", "Toggle Faction Creation", list("Yes", "No")) != "Yes")
		return

	SSpersistence.setFactionCreationEnabled(new_state)
	log_and_message_admins("[new_state ? "enabled" : "disabled"] player self-service faction creation.", usr)
	feedback_add_details("admin_verb", "TFC")

/// Loads the faction raiding toggle from ss13_faction_raiding_toggle at boot.
/// Mirrors factionCreationToggleInitialize() above.
/datum/controller/subsystem/persistence/proc/factionRaidingToggleInitialize()
	if(!databaseCheckConnection("factionRaidingToggleInitialize"))
		return
	try
		var/datum/db_query/q = SSdbcore.NewQuery("SELECT enabled FROM ss13_faction_raiding_toggle WHERE id = 1", list())
		q.Execute()
		if(databaseCheckQueryResult(q, "factionRaidingToggleInitialize") && q.NextRow())
			GLOB.faction_raiding_enabled = text2num(q.item[1])
		qdel(q)
	catch(var/exception/toggle_e)
		log_subsystem_persistence_error("Factions: failed to load faction raiding toggle: [toggle_e]")

/datum/controller/subsystem/persistence/proc/setFactionRaidingEnabled(enabled)
	GLOB.faction_raiding_enabled = enabled
	if(!databaseCheckConnection("setFactionRaidingEnabled"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_raiding_toggle (id, enabled) VALUES (1, :enabled) ON DUPLICATE KEY UPDATE enabled = VALUES(enabled)",
		list("enabled" = enabled ? 1 : 0)
	)
	q.Execute()
	databaseCheckQueryResult(q, "setFactionRaidingEnabled")
	qdel(q)

/// Admin kill-switch: when disabled, non-members are blocked outright from
/// entering any claimed (non-Hub) faction's own Z-level(s) -- see
/// _drydock_pick_access_mode()/_drydock_pick_turf_valid()
/// (telepad_drydock_boarding.dm) for the actual enforcement.
/datum/admins/proc/toggle_faction_raiding()
	set name = "Toggle Faction Raiding"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/new_state = !GLOB.faction_raiding_enabled
	if(tgui_alert(usr, "Faction raiding is currently [GLOB.faction_raiding_enabled ? "ENABLED" : "DISABLED"]. [new_state ? "Enable" : "Disable"] it? Disabling blocks non-members from entering any claimed faction's territory (Hub excluded).", "Toggle Faction Raiding", list("Yes", "No")) != "Yes")
		return

	SSpersistence.setFactionRaidingEnabled(new_state)
	to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Faction raiding has been [new_state ? SPAN_WARNING("enabled") : SPAN_GOOD("disabled")] by an administrator.[new_state ? "" : " Non-members can no longer enter claimed faction territory."]")))
	log_and_message_admins("[new_state ? "enabled" : "disabled"] faction raiding.", usr)

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

/// The ckey of the faction's original founder, set once at founding and
/// never reassigned -- null for factions founded before this feature
/// existed, or created via the admin "create faction" verb (no player
/// founder). This is the one identity that survives even a full Panic
/// Purge (faction_manage.dm), gating the founder-only "Print Master Card"
/// action so a founder can always recover from a lost/compromised card
/// even if it cost them their own rank-2 access in the process.
/proc/get_faction_founder_ckey(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return null
	return GLOB.persistence_faction_cache[uid]["founder_ckey"]

/// Whether a faction's master card is currently considered lost (revoked via
/// Panic Purge and not yet replaced) -- gates the "Print Master Card" action
/// so a fresh one can't be minted while the existing one is still presumably
/// valid and in someone's hands.
/proc/get_faction_master_card_lost(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	return !!GLOB.persistence_faction_cache[uid]["master_card_lost"]

/// Sets whether a faction's master card is considered lost, persisting the
/// flag so it survives a reboot (a compromised master card shouldn't become
/// valid again just because the server restarted).
/proc/set_faction_master_card_lost(uid, lost)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	GLOB.persistence_faction_cache[uid]["master_card_lost"] = lost
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/mq = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_accounts (faction_uid, master_card_lost) VALUES (:uid, :lost)
			ON DUPLICATE KEY UPDATE master_card_lost = VALUES(master_card_lost), saved_at = NOW()"},
			list("uid" = uid, "lost" = lost ? 1 : 0)
		)
		mq.Execute()
		qdel(mq)
	return TRUE

/// A faction's current color (hex string "#rrggbb"), or null if never set.
/// Used to tint clothing/equipment tagged to this faction with the faction
/// tagger (persistence_faction_tagger.dm) -- tagged items never store their
/// own frozen color, they always resolve it live from here.
/proc/get_faction_color(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return null
	return GLOB.persistence_faction_cache[uid]["color"]

/// Sets a faction's color, persists it, and immediately re-tints every
/// currently-tagged /obj/item/clothing in the world (wherever it currently
/// is -- worn, in a bag, in a locker, on the floor) so "faction color"
/// always means the CURRENT color, never a stale one from tag time.
/proc/set_faction_color(uid, new_color)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	GLOB.persistence_faction_cache[uid]["color"] = new_color
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/cq = SSdbcore.NewQuery(
			"UPDATE ss13_factions SET color = :color WHERE uid = :uid",
			list("uid" = uid, "color" = new_color)
		)
		cq.Execute()
		qdel(cq)
	for(var/obj/item/clothing/C in world)
		if(C.faction_tag_uid == uid)
			C.color = new_color
			C.update_icon()
			C.update_clothing_icon()
	return TRUE

/// Whether a faction's payroll runs automatically every autosave cycle
/// (factionFinalize()) or only via the manual "Pay Members Now" action.
/// Defaults to TRUE (automatic) if the faction can't be found for any reason.
/proc/get_faction_auto_payroll(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return TRUE
	return !!GLOB.persistence_faction_cache[uid]["auto_payroll"]

/proc/set_faction_auto_payroll(uid, enabled)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	GLOB.persistence_faction_cache[uid]["auto_payroll"] = enabled
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/q = SSdbcore.NewQuery(
			"UPDATE ss13_factions SET auto_payroll = :val WHERE uid = :uid",
			list("uid" = uid, "val" = enabled ? 1 : 0)
		)
		q.Execute()
		qdel(q)
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

/**
 * Faction-facing wrapper for the admin "Rename Site" action below: renames
 * the pinned away site occupying the given z, persisting via
 * ss13_persistent_away_sites.custom_name (restored every boot by
 * build_pinned_away_sites(), map.dm). Blank new_name restores the template
 * default. Returns null on success, or a player-readable refusal reason.
 * Resolution is by the z's own template id -- the same authoritative lookup
 * pin/unpin above use -- so unlike the admin verb's last_z path this can
 * never touch a different site through a stale z number.
 */
/proc/persistence_rename_pinned_site_at_z(z, new_name)
	var/datum/map_template/here_template = GLOB.map_templates["[z]"]
	if(!istype(here_template, /datum/map_template/ruin/away_site))
		return "This location is not a renamable away site."
	if(!SSpersistence.databaseCheckConnection("persistence_rename_pinned_site_at_z"))
		return "Database connection unavailable."

	var/datum/db_query/check = SSdbcore.NewQuery(
		"SELECT id FROM ss13_persistent_away_sites WHERE template_name = :tn AND map_path = :mp",
		list("tn" = here_template.id, "mp" = "[SSatlas.current_map.path]")
	)
	check.Execute()
	var/pinned = check.NextRow()
	qdel(check)
	if(!pinned)
		return "This site is not pinned for persistence -- its name cannot persist."

	var/datum/db_query/rnq = SSdbcore.NewQuery(
		"UPDATE ss13_persistent_away_sites SET custom_name = :cn WHERE template_name = :tn AND map_path = :mp",
		list("cn" = (new_name != "" ? new_name : null), "tn" = here_template.id, "mp" = "[SSatlas.current_map.path]")
	)
	rnq.Execute()
	SSpersistence.databaseCheckQueryResult(rnq, "persistence_rename_pinned_site_at_z")
	qdel(rnq)

	// Live apply -- z is the caller's own current z this session, so this
	// marker lookup is direct and always the right site.
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[z]"]
	if(istype(marker))
		marker.name = (new_name != "" ? new_name : initial(marker.name))
	return null

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

		var/action = tgui_input_list(usr, "Select action:", "Persistent Overmap Sites", list("Pin Site I'm At", "Pin From Template List", "Rename Site", "Change Icon", "Move Site", "Toggle Enabled", "Unpin Site", "Close"))
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

		else if(action == "Move Site")
			// Lists BOTH pinned sites (from `rows`) and dynamic ones currently
			// live this session -- Move Site isn't restricted to pinned rows,
			// unlike every other action here, since relocating a dynamic site
			// is still meaningful (it just isn't written to the DB).
			var/list/move_choices = list()
			for(var/list/row in rows)
				move_choices["#[row["id"]] [row["template"]][row["custom_name"] ? " ('[row["custom_name"]]')" : ""] (pinned)"] = row
			for(var/z_key in GLOB.map_sectors)
				var/z_num = text2num(z_key)
				if(!z_num || (z_num in GLOB.persistence_pinned_site_z))
					continue // pinned sites already listed above via their DB row
				var/datum/map_template/dyn_template = GLOB.map_templates[z_key]
				if(!istype(dyn_template, /datum/map_template/ruin/away_site))
					continue
				var/obj/effect/overmap/visitable/dyn_marker = GLOB.map_sectors[z_key]
				if(!istype(dyn_marker) || istype(dyn_marker, /obj/effect/overmap/visitable/sector/exoplanet))
					continue
				move_choices["[dyn_template.id] (dynamic, z=[z_num])"] = list("dynamic" = TRUE, "z" = z_num, "template" = dyn_template.id)
			if(!length(move_choices))
				to_chat(usr, SPAN_WARNING("No movable sites found -- a site must be currently loaded this session to move it."))
				continue
			var/move_pick = tgui_input_list(usr, "Move which site?", "Move Site", move_choices)
			if(!move_pick)
				continue
			var/list/move_row = move_choices[move_pick]
			var/is_dynamic = !!move_row["dynamic"]
			var/move_z = is_dynamic ? move_row["z"] : move_row["last_z"]
			var/obj/effect/overmap/visitable/move_marker = GLOB.map_sectors["[move_z]"]
			if(!istype(move_marker))
				to_chat(usr, SPAN_WARNING("'[move_row["template"]]' isn't currently loaded -- it must be live this session to move."))
				continue
			// Same stale-z guard Rename Site/Change Icon already use -- a pinned
			// row's last_z can go stale if an earlier row failed to load this
			// boot, letting a later site land on the failed row's old z.
			if(!is_dynamic)
				var/datum/map_template/move_template = GLOB.map_templates["[move_z]"]
				if(!move_template || move_template.id != move_row["template"])
					to_chat(usr, SPAN_WARNING("'[move_row["template"]]' isn't actually loaded at z=[move_z] this session (stale record) -- refusing to move a different site."))
					continue

			var/map_low = OVERMAP_EDGE
			var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
			var/new_x = tgui_input_number(usr, "New overmap X ([map_low]-[map_high]):", "Move Site", move_marker.start_x, map_high, map_low)
			if(isnull(new_x))
				continue
			var/new_y = tgui_input_number(usr, "New overmap Y ([map_low]-[map_high]):", "Move Site", move_marker.start_y, map_high, map_low)
			if(isnull(new_y))
				continue
			new_x = clamp(new_x, map_low, map_high)
			new_y = clamp(new_y, map_low, map_high)

			var/turf/move_dest = locate(new_x, new_y, SSatlas.current_map.overmap_z)
			if(!move_dest)
				to_chat(usr, SPAN_WARNING("No overmap tile at ([new_x],[new_y])."))
				continue
			var/obj/effect/overmap/visitable/move_occupant = locate() in move_dest
			if(move_occupant && move_occupant != move_marker)
				to_chat(usr, SPAN_WARNING("([new_x],[new_y]) is already occupied by '[move_occupant.name]' -- pick another tile."))
				continue

			move_marker.start_x = new_x
			move_marker.start_y = new_y
			move_marker.forceMove(move_dest)

			if(!is_dynamic)
				var/datum/db_query/mvq = SSdbcore.NewQuery(
					"UPDATE ss13_persistent_away_sites SET overmap_x = :ox, overmap_y = :oy WHERE id = :id",
					list("ox" = new_x, "oy" = new_y, "id" = move_row["id"])
				)
				mvq.Execute()
				SSpersistence.databaseCheckQueryResult(mvq, "persistent_overmap_sites move")
				qdel(mvq)

			// Immediate re-sync instead of waiting on the next periodic beacon
			// sweep -- see _apply_security_radius_grant() (faction_beacon.dm).
			for(var/obj/structure/machinery/faction_beacon/B in world)
				if(B.active && B.powered)
					B._apply_security_radius_grant()
			zone_security_update_overmap()

			to_chat(usr, SPAN_GOOD("Moved '[move_row["template"]]' to overmap ([new_x],[new_y])[is_dynamic ? " (dynamic -- not saved, resets next boot)" : " -- persists across reboots"]."))
			log_and_message_admins("moved overmap site '[move_row["template"]]' to ([new_x],[new_y])", usr)

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
			// Same stale-z guard Rename Site/Change Icon already use -- last_z
			// can point at a DIFFERENT site's z if an earlier row failed to
			// load this boot and a later site landed on the failed row's old z
			// (sequential z-allocation in build_pinned_away_sites()). Without
			// this, purging/evicting by a stale last_z silently destroys an
			// unrelated, still-live site's saved persistence data.
			var/datum/map_template/unpin_template = unpin_row["last_z"] ? GLOB.map_templates["[unpin_row["last_z"]]"] : null
			var/unpin_z_matches = unpin_template && (unpin_template.id == unpin_row["template"])
			if(purge_choice == "Purge" && unpin_row["last_z"])
				if(unpin_z_matches)
					SSpersistence.purgeZRows(unpin_row["last_z"])
				else
					to_chat(usr, SPAN_WARNING("z=[unpin_row["last_z"]] no longer matches '[unpin_row["template"]]' this session (stale record) -- skipped purging live data to avoid deleting an unrelated site's saved rows."))
			if(unpin_row["last_z"] && unpin_z_matches && (unpin_row["last_z"] in GLOB.persistence_pinned_site_z))
				GLOB.persistence_pinned_site_z -= unpin_row["last_z"]
				GLOB.persistence_zlevel_allow -= unpin_row["last_z"]
			to_chat(usr, SPAN_GOOD("Unpinned '[unpin_row["template"]]'[(purge_choice == "Purge" && unpin_z_matches) ? " and purged its saved rows" : " (saved rows kept)"]. Dynamic again from next boot."))
			log_and_message_admins("unpinned overmap site '[unpin_row["template"]]'[(purge_choice == "Purge" && unpin_z_matches) ? " (rows purged)" : ""]", usr)

/// Picks a random unoccupied overmap tile -- optionally (avoid_unsecured_zones)
/// excluding any tile within an active+powered faction beacon's claimed
/// medsec/highsec security_radius, the same range()-based geometry
/// zone_security_update_overmap_borders() uses to paint that territory,
/// checked here proactively at selection time instead of reactively after
/// spawning. Returns null if no valid tile turns up after a handful of
/// random attempts.
/proc/_pick_free_overmap_tile(avoid_unsecured_zones = FALSE)
	if(!SSatlas.current_map.overmap_z)
		return null
	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE

	var/list/secured_sectors = list()
	if(avoid_unsecured_zones)
		for(var/obj/structure/machinery/faction_beacon/B in world)
			if(!B.active || !B.powered || B.security_radius <= 0 || B.guaranteed_security_tier < ZONE_MEDSEC)
				continue
			var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
			if(istype(beacon_sector))
				secured_sectors += list(list("sector" = beacon_sector, "radius" = B.security_radius))

	for(var/attempt in 1 to 20)
		var/turf/candidate = locate(rand(map_low, map_high), rand(map_low, map_high), SSatlas.current_map.overmap_z)
		if(!candidate)
			continue
		if(locate(/obj/effect/overmap/visitable) in candidate)
			continue
		var/blocked = FALSE
		for(var/list/entry in secured_sectors)
			if(get_dist(candidate, entry["sector"]) <= entry["radius"])
				blocked = TRUE
				break
		if(!blocked)
			return candidate
	return null

/**
 * Core away-site placement logic shared by "Generate Away Site" and the
 * missions auto-gen system (accept_mission()). If target_tile is given, the
 * site loads there directly -- the admin-verb path, which already prompted
 * for and validated a specific tile. If target_tile is null, a free tile is
 * picked instead (_pick_free_overmap_tile()) -- if avoid_unsecured_zones is
 * also TRUE (the missions auto-gen path), the search itself excludes every
 * active beacon's claimed radius up front, so the result is nullsec by
 * construction rather than spawned-then-checked-then-retried. Returns the
 * new Z on success, or null (template already loaded without
 * TEMPLATE_FLAG_ALLOW_DUPLICATES, no overmap, no valid tile found, or the
 * load itself failed).
 *
 * Tries the shared Z reuse pool (GLOB.reusable_z_pool,
 * persistence_ship_interiors.dm) first via load_into_z() before falling
 * back to a fresh load_new_z() -- the same mitigation player-ship retrieve
 * uses, since BYOND can never shrink world.maxz back down. Multi-Z site
 * templates (traits.len > 1) can't use a pooled single Z, so they always
 * fall back to load_new_z().
 */
/proc/_spawn_away_site_for_template(datum/map_template/ruin/away_site/site, turf/target_tile, avoid_unsecured_zones = FALSE)
	if(!site)
		return null
	if(site.loaded && !(site.template_flags & TEMPLATE_FLAG_ALLOW_DUPLICATES))
		return null
	if(!SSatlas.current_map.overmap_z)
		return null

	if(!target_tile)
		target_tile = _pick_free_overmap_tile(avoid_unsecured_zones)
		if(!target_tile)
			return null

	var/pick_x = target_tile.x
	var/pick_y = target_tile.y

	// Suspend ZAS during the load or the freshly loaded site gets vented
	// (same recipe as the Map Template - Place In New Z verb).
	var/pool_z = (length(site.traits) == 1) ? SSpersistence.acquireReusableZ() : 0
	var/site_z
	var/bounds
	SSair.can_fire = FALSE
	if(pool_z)
		bounds = site.load_into_z(pool_z)
		site_z = pool_z
	else
		var/z_before = world.maxz
		bounds = site.load_new_z(FALSE)
		site_z = z_before + 1
	SSair.can_fire = TRUE
	if(!bounds)
		if(pool_z)
			SSpersistence.poolReusableZ(pool_z) // hand it back, this attempt never claimed it
		return null

	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[site_z]"]
	if(marker)
		marker.start_x = pick_x
		marker.start_y = pick_y
		if(marker.loc)
			marker.forceMove(target_tile)

	// Grant the real security tier immediately if this landed inside an
	// active beacon's radius, instead of waiting up to one sweep interval
	// for process()'s periodic _apply_security_radius_grant() to catch it.
	for(var/obj/structure/machinery/faction_beacon/B in world)
		if(B.active && B.powered)
			B._apply_security_radius_grant()

	if(avoid_unsecured_zones && zone_security_get(site_z) != ZONE_NULLSEC)
		// Shouldn't happen -- the tile search above already excluded every
		// claimed radius -- but guard against a beacon powering on in the
		// same tick as this load.
		_despawn_away_site_z(site_z, FALSE)
		return null

	// Paint the new marker's zone-security outline/border immediately --
	// otherwise it sits unpainted until some unrelated later zone change
	// happens to trigger a full repaint (zone_security_update_overmap()
	// is only ever called at boot or on an explicit zone change).
	zone_security_update_overmap()

	if(site.auto_despawn_when_depleted)
		_register_auto_despawn_asteroid(site_z, site.id)

	return site_z

// ============================================================
// ASTEROID AUTO-DESPAWN  mined-out sites tear down and respawn elsewhere
// ============================================================

#define ASTEROID_DEPLETION_CHECK_INTERVAL 2 MINUTES
#define ASTEROID_RESPAWN_DELAY 10 MINUTES

/// z -> template_id, for every currently-loaded away site whose template
/// has auto_despawn_when_depleted set. Populated by
/// _register_auto_despawn_asteroid(), drained as each site despawns.
GLOBAL_LIST_EMPTY(auto_despawn_asteroid_zs)

/// TRUE if this z has no ore left, checking BOTH forms mineable asteroid
/// content actually takes here -- confirmed by direct inspection of the
/// three flagged templates' own .dmm content, since assuming one mechanic
/// covered all of them would have been wrong:
/// - Wall veins (/turf/simulated/mineral and subtypes, e.g. cursed.dmm's
///   and overgrown_mining_station.dmm's own deposits) -- GetDrilled()
///   (mine_turfs.dm) converts a mined vein to its mined_turf, which is NOT
///   a /turf/simulated/mineral subtype, so it drops out of this scan the
///   moment it's mined -- a plain existence check is enough.
/// - Floor resources (/turf/simulated/floor/exoplanet/asteroid and
///   subtypes, e.g. phoron_deposit's own dedicated turf subtype, which
///   sets has_resources/resources[ORE_PHORON] in its own Initialize()) --
///   drained by the automated mining drill (drill.dm). Manual pickaxe
///   digging (gets_dug(), mine_turfs.dm) never decrements resources, but a
///   fully dug tile eventually turns to /turf/space on its own (mine_turfs.dm's
///   dug counter), dropping out of this scan naturally either way.
/proc/_away_site_asteroid_depleted(z)
	for(var/turf/simulated/mineral/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		return FALSE // an unmined wall vein still exists
	for(var/turf/simulated/floor/exoplanet/asteroid/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.has_resources && length(T.resources))
			return FALSE
	return TRUE

/// Stricter than zlevel_has_players() -- excludes a dead body with a
/// lingering client/ckey, since this feature only cares whether anyone
/// LIVING is still here. The neural lace half is identical to
/// zlevel_has_players()'s own -- a lace's mere presence still blocks
/// despawn regardless of aliveness, since it represents someone's saved
/// consciousness, not a corpse.
/proc/_zlevel_has_living_or_lace(z)
	for(var/mob/M in GLOB.mob_list)
		if(M.z == z && M.stat != DEAD && (M.client || M.ckey))
			return TRUE
	for(var/obj/item/organ/internal/neural_lace/L in world)
		if(!length(L.registered_ckey))
			continue
		var/turf/T = get_turf(L)
		if(T && T.z == z)
			return TRUE
	return FALSE

/// Registers z for periodic depletion/despawn checking -- called once
/// right after a flagged template successfully loads (both the RNG-pool
/// boot loader, build_away_sites() in map.dm, and this file's own
/// _spawn_away_site_for_template(), which covers mission auto-gen, admin
/// manual gen, and this feature's own respawns). Deliberately never called
/// from build_pinned_away_sites() -- an admin-pinned instance stays
/// permanent regardless of depletion, same as it's already excluded from
/// the RNG budget entirely.
/proc/_register_auto_despawn_asteroid(z, template_id)
	GLOB.auto_despawn_asteroid_zs[z] = template_id
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_check_asteroid_depletion_and_despawn), z), ASTEROID_DEPLETION_CHECK_INTERVAL)

/// Modeled on _try_cleanup_mission_sector() (persistence_missions.dm) --
/// recheck on an interval, reschedule via addtimer() if not yet safe to
/// tear down, act once every condition (depleted, no one living/laced
/// still here, not inside claimed territory) is finally met.
/proc/_check_asteroid_depletion_and_despawn(z)
	var/template_id = GLOB.auto_despawn_asteroid_zs[z]
	if(!template_id)
		return // already handled/cancelled (e.g. an admin manually removed it)

	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[z]"]
	var/not_ready = !_away_site_asteroid_depleted(z) || _zlevel_has_living_or_lace(z) || (istype(marker) && _overmap_tile_hazard_excluded(get_turf(marker)))
	if(not_ready)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_check_asteroid_depletion_and_despawn), z), ASTEROID_DEPLETION_CHECK_INTERVAL)
		return

	GLOB.auto_despawn_asteroid_zs -= z
	_despawn_away_site_z(z)
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_respawn_asteroid_site), template_id), ASTEROID_RESPAWN_DELAY)

/// One-shot delayed respawn after a mined-out site tears itself down --
/// reuses the same _spawn_away_site_for_template() call the "Generate Away
/// Site" admin verb and mission auto-gen already use, letting it pick a
/// fresh random overmap tile the normal way.
/proc/_respawn_asteroid_site(template_id)
	var/datum/map_template/ruin/away_site/template = SSmapping.away_sites_templates[template_id]
	if(!template)
		return
	if(!_spawn_away_site_for_template(template, null))
		// No free overmap tile right now -- try again after the same
		// cooldown rather than losing this site permanently.
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_respawn_asteroid_site), template_id), ASTEROID_RESPAWN_DELAY)

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

	var/site_z = _spawn_away_site_for_template(site, target_tile)
	if(!site_z)
		to_chat(usr, SPAN_WARNING("Failed to load '[tmpl_pick]'."))
		log_and_message_admins("failed to generate away site '[tmpl_pick]'", usr)
		return

	to_chat(usr, SPAN_GOOD("Generated '[tmpl_pick]' at overmap ([pick_x],[pick_y]), z=[site_z]. It is DYNAMIC (gone on reboot, not saved) -- pin it via Persistent Overmap Sites to make it permanent."))
	log_and_message_admins("generated away site '[tmpl_pick]' at overmap ([pick_x],[pick_y]), z=[site_z]", usr)

// ============================================================
// AWAY SITE FREEZE/THAW  pause an unoccupied away/ruin site's machinery
// and powernets out of SSmachinery's live lists, same rationale and
// mechanism as the drydock ship freeze/thaw (_drydock_freeze_ship()/
// _drydock_thaw_ship(), persistence_shuttles.dm) -- an idle site otherwise
// costs exactly as much per-tick as an occupied one. ZAS zone/edge geometry
// is left completely untouched here too, for the same reason.
//
// Deliberately does NOT freeze mobs the way the ship version does: an away
// site can hold hostile wildlife/NPCs mid-mission, and unlike drydock
// boarding -- which funnels through one chokepoint, _drydock_board_deliver(),
// that thaws BEFORE anyone lands -- away sites have no single entry
// chokepoint (teleporters, shuttles, personal travel, mission accept-and-
// travel all deliver players independently). A player could walk in up to
// AWAY_SITE_FREEZE_RECONCILE_INTERVAL seconds before the sweep below thaws
// the site, which would be a real (if brief) "the monster doesn't react"
// bug for a frozen mob -- not worth it for the AI-tick savings. Machinery/
// powernets have no such stakes: a light or vending machine coming back
// online a few seconds late is unnoticeable.
// ============================================================

/// z (as a string key, "[z]") -> list("machinery" = list(machine -> its
/// processing_flags), "powernets" = list of paused /datum/powernet refs) --
/// absence of a key means that z isn't frozen. Kept separate from
/// GLOB.drydock_ships since away sites have no equivalent per-site datum to
/// hang state off of.
GLOBAL_LIST_EMPTY(away_site_freeze_state)

/// How often the reconciliation sweep below re-checks every loaded away/
/// ruin site -- there's no instant board/disembark-style hook here (see the
/// section header above), so this interval is the only thing driving
/// freeze/thaw for these Zs. Bounded by loaded-site count, not world size.
#define AWAY_SITE_FREEZE_RECONCILE_INTERVAL 30 SECONDS

/// Starts the recurring away-site reconciliation sweep -- called once from
/// SSpersistence's own Initialize(), alongside the drydock ship equivalent
/// (_drydock_freeze_reconcile_start(), persistence_shuttles.dm).
/proc/_away_site_freeze_reconcile_start()
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_away_site_freeze_reconcile)), AWAY_SITE_FREEZE_RECONCILE_INTERVAL, TIMER_LOOP)

/// Walks every currently-loaded, non-station, non-drydock-ship template Z
/// (GLOB.map_templates covers away sites, space ruins, and exoplanet ruins
/// alike -- ship Zs are excluded via GLOB.persistence_ship_z, which are
/// handled by their own dedicated mechanism instead) and freezes/thaws it
/// based on zlevel_has_players().
/proc/_away_site_freeze_reconcile()
	for(var/key in GLOB.map_templates)
		var/z = text2num(key)
		if(!z || is_station_level(z) || GLOB.persistence_ship_z[key])
			continue
		if(GLOB.away_site_freeze_state[key])
			if(zlevel_has_players(z))
				_away_site_thaw(z)
		else
			if(!zlevel_has_players(z))
				_away_site_freeze(z)

/// Pauses every machine and powernet on z -- see the section header above
/// for why mobs are deliberately left alone here, unlike the drydock ship
/// version. Single turf-scoped pass, same idiom as this session's other
/// FinalizeZ/sweep rewrites.
/proc/_away_site_freeze(z)
	if(!z || GLOB.away_site_freeze_state["[z]"])
		return
	var/list/frozen_machinery = list()
	var/list/frozen_powernets = list()
	var/list/seen_powernets = list()
	var/machines_frozen = 0
	var/powernets_frozen = 0

	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		CHECK_TICK
		for(var/atom/movable/AM in T.contents)
			if(istype(AM, /obj/structure/machinery))
				var/obj/structure/machinery/M = AM
				if(M.processing_flags)
					frozen_machinery[M] = M.processing_flags
					STOP_PROCESSING_MACHINE(M, M.processing_flags)
					machines_frozen++
				if(istype(M, /obj/structure/machinery/power))
					var/obj/structure/machinery/power/PM = M
					if(PM.powernet)
						seen_powernets[PM.powernet] = TRUE

			else if(istype(AM, /obj/structure/cable))
				var/obj/structure/cable/C = AM
				if(C.powernet)
					seen_powernets[C.powernet] = TRUE

	for(var/datum/powernet/PN in seen_powernets)
		if(QDELETED(PN) || !(PN.datum_flags & DF_ISPROCESSING))
			continue
		frozen_powernets += PN
		STOP_PROCESSING_POWERNET(PN)
		powernets_frozen++

	GLOB.away_site_freeze_state["[z]"] = list("machinery" = frozen_machinery, "powernets" = frozen_powernets)
	if(machines_frozen || powernets_frozen)
		log_subsystem_persistence_info("Away site freeze: froze z=[z] -- [machines_frozen] machine(s), [powernets_frozen] powernet(s).")

/// Reverses _away_site_freeze().
/proc/_away_site_thaw(z)
	var/list/state = GLOB.away_site_freeze_state["[z]"]
	if(!state)
		return
	var/list/frozen_machinery = state["machinery"]
	var/list/frozen_powernets = state["powernets"]

	for(var/obj/structure/machinery/M in frozen_machinery)
		if(!QDELETED(M))
			START_PROCESSING_MACHINE(M, frozen_machinery[M])

	for(var/datum/powernet/PN in frozen_powernets)
		if(!QDELETED(PN))
			START_PROCESSING_POWERNET(PN)

	GLOB.away_site_freeze_state -= "[z]"
	log_subsystem_persistence_info("Away site freeze: thawed z=[z].")

/**
 * Core away-site teardown shared by "Remove Away Site" and the missions
 * auto-gen cleanup (turn-in-triggered despawn of a mission-spawned sector).
 * Wipes every turf on z to space, deletes the overmap marker, and cleans
 * zone-security/persistence-toggle state. purge_incidental controls whether
 * incidental persistence rows for z are also purged (SSpersistence.purgeZRows) --
 * defaults TRUE (dynamic/mission-spawned sites always want this); callers
 * tearing down a PINNED site pass the admin's own Purge/Keep choice instead.
 * Caller is responsible for confirming no one is still on z
 * (zlevel_has_players()) and, for pinned sites, its own
 * ss13_persistent_away_sites row cleanup -- this proc only ever handles the
 * always-safe, non-pin-specific teardown.
 *
 * purge_incidental TRUE also releases z into the shared Z reuse pool
 * (GLOB.reusable_z_pool, persistence_ship_interiors.dm) once wiped, so a
 * later away/mission spawn (or ship retrieve) can load onto it instead of
 * permanently allocating a new Z-level. FALSE (a "Keep" choice tearing down
 * a pinned site) skips pooling -- the admin explicitly wants this z's
 * content left alone, not silently handed to something else.
 */
/proc/_despawn_away_site_z(z, purge_incidental = TRUE)
	if(!z)
		return

	// Defensive: don't leave stale freeze bookkeeping behind for whatever
	// (possibly unrelated) content loads onto this z number next, if it's
	// ever released back into the Z reuse pool below. Harmless either way
	// (_away_site_thaw()'s own QDELETED guards would just no-op on
	// everything), but this keeps a reused z starting from a clean slate.
	GLOB.away_site_freeze_state -= "[z]"

	// The template's own .loaded counter (map_template.dm: "times loaded
	// this round") was never decremented anywhere in this codebase -- so
	// for any template without TEMPLATE_FLAG_ALLOW_DUPLICATES, the very
	// first time it's ever spawned this round permanently latches loaded
	// > 0, and both the "Generate Away Site" admin verb (line ~1731) and
	// this file's own _spawn_away_site_for_template() (line ~1544) share
	// the exact same "already loaded somewhere, does not allow duplicates"
	// refusal check -- so every later attempt to spawn that same template
	// again, including this file's own automatic respawn-after-despawn,
	// silently fails forever. Also clears the stale GLOB.map_templates
	// entry for z, mirroring the equivalent cleanup ship teardown already
	// does for its own scope.
	var/datum/map_template/here_template = GLOB.map_templates["[z]"]
	if(here_template && here_template.loaded > 0)
		here_template.loaded--
	GLOB.map_templates -= "[z]"

	if(purge_incidental)
		SSpersistence.purgeZRows(z)

	// Clean up zone security + persistence-toggle rows/state for this z too --
	// otherwise a stale tier/toggle could silently apply to whatever different
	// site happens to load at this same Z number on a future boot.
	if(SSpersistence.databaseCheckConnection("_despawn_away_site_z cleanup"))
		var/datum/db_query/del_sec = SSdbcore.NewQuery(
			"DELETE FROM ss13_zone_security WHERE z = :z AND map_path = :mp",
			list("z" = z, "mp" = "[SSatlas.current_map.path]")
		)
		del_sec.Execute()
		qdel(del_sec)
		var/datum/db_query/del_persist = SSdbcore.NewQuery(
			"DELETE FROM ss13_zlevel_persistence WHERE z = :z AND map_path = :mp",
			list("z" = z, "mp" = "[SSatlas.current_map.path]")
		)
		del_persist.Execute()
		qdel(del_persist)
	GLOB.zone_security_by_z -= "[z]"
	GLOB.persistence_zlevel_skip -= z
	GLOB.persistence_zlevel_allow -= z

	// Delete every remaining atom/mob (caller already guaranteed player-free),
	// wipe turfs to plain space, then remove the overmap marker. Snapshot each
	// turf's contents first -- can't qdel while iterating a turf's live
	// contents list (same gotcha reset_zlevel() already works around).
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/list/contents_snapshot = T.contents.Copy()
		for(var/atom/movable/AM in contents_snapshot)
			qdel(AM)
		T.ChangeTurf(/turf/space)
		CHECK_TICK

	// Area reassignment back to the world default -- ChangeTurf() only
	// touches the turf's type, not its area (a separate .loc assignment), so
	// without this a future occupant's turfs would silently inherit this
	// site's now-qdeleted custom area instances. Only matters once z can
	// actually be reused (see the pool release below); harmless otherwise.
	var/area/default_area = locate(world.area)
	if(default_area)
		for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/area/current = T.loc
			if(current != default_area)
				T.change_area(current, default_area)
			CHECK_TICK

	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[z]"]
	if(marker)
		qdel(marker)
	GLOB.map_sectors -= "[z]"
	zone_security_update_overmap()

	if(purge_incidental)
		SSpersistence.poolReusableZ(z)

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
	var/purge_incidental = TRUE

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
			purge_incidental = (purge_choice == "Purge")
		GLOB.persistence_pinned_site_z -= z_pick
		GLOB.persistence_zlevel_allow -= z_pick

	_despawn_away_site_z(z_pick, purge_incidental)

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

		// Revoke this faction's bearer master card, if it has one -- same
		// revoke-by-scan idiom dispense_faction_id uses for superseded
		// personal IDs (card.dm)
		for(var/obj/item/card/id/faction_master/old_master in world)
			if(!old_master.revoked && normalize_faction_uid(old_master.employer_faction) == chosen_uid)
				old_master.revoked = TRUE
				old_master.access = list()
				old_master.update_name()

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

/// -1 = non-member, 0+ = member rank, 99 = admin. Also grants rank 2
/// (command) to whoever is holding that faction's bearer master card
/// (cards_ids.dm), regardless of DB membership -- the card isn't tied to
/// any ckey, so this can't be resolved via get_faction_member() alone.
/proc/get_effective_faction_rank(mob/user, faction_uid)
	if(!user || !faction_uid)
		return -1
	faction_uid = normalize_faction_uid(faction_uid)
	if(check_rights(R_ADMIN, 0, user))
		return 99
	var/list/member = user.ckey ? get_faction_member(user.ckey, faction_uid) : null
	var/rank = member ? (isnull(member["rank"]) ? 0 : (member["rank"] + 0)) : -1
	var/obj/item/card/id/ID = user.GetIdCard()
	if(ID && ID.is_faction_master && !ID.revoked && normalize_faction_uid(ID.employer_faction) == faction_uid)
		rank = max(rank, 2)
	return rank

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

