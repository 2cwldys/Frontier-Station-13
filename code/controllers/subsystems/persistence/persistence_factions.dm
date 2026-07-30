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

	// Load faction info + balances -- CORE columns only, stable since long
	// before the recent burst of schema growth (cargo category/leader/
	// company-tier). Keep this list frozen to long-established columns: a
	// missing NEW column here would fail the whole query and silently empty
	// the entire faction cache (every faction-uid lookup in the game then
	// treats every faction as nonexistent), which is exactly the cascade
	// _factionLoadExtendedColumns() below exists to avoid. Add future new
	// ss13_factions columns to that proc, not this query.
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
					"auto_payroll"     = !!text2num(q.item[9]),
					// Safe defaults for the newer, migration-dependent columns
					// -- _factionLoadExtendedColumns() below fills these in
					// for real if the schema has caught up; if it hasn't,
					// every OTHER faction feature (membership, rank, ID
					// tagging, balances, payroll) keeps working normally
					// instead of the whole cache going empty.
					"allowed_cargo_category" = null,
					"leader_ckey"      = null,
					"leader_char_name" = null,
					"is_company_tier"  = FALSE
				)
			GLOB.persistence_faction_cache = loaded // only replace on confirmed success
			_factionLoadExtendedColumns()
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

	// Load faction members -- CORE columns only (account_number is a newer,
	// migration-dependent column, split out below via _factionLoadAccountNumbers()
	// so a schema that hasn't caught up yet only leaves payroll account
	// numbers at their 0 default instead of failing the whole members load,
	// same reasoning as _factionLoadExtendedColumns() above).
	try
		var/datum/db_query/mq = SSdbcore.NewQuery(
			"SELECT ckey, faction_uid, real_name, job_title, rank FROM ss13_faction_members",
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
					"account_number" = 0,
					"clocked_in"     = FALSE
				)
			GLOB.persistence_faction_members_cache = loaded_members // only replace on confirmed success
			_factionLoadAccountNumbers()
		else
			message_admins("Faction members load query failed -- faction members may be running on stale/empty data. Check DB schema (db_update?).")
		qdel(mq)
	catch(var/exception/faction_members_e)
		message_admins("Faction members load threw an exception: [faction_members_e] -- faction members may be running on stale/empty data.")
		log_subsystem_persistence_error("Factions: failed to load faction members: [faction_members_e]")

	log_subsystem_persistence_info("Factions: Loaded [length(GLOB.persistence_faction_cache)] factions, [length(GLOB.persistence_faction_members_cache)] members.")

/// Best-effort enrichment of GLOB.persistence_faction_cache with newer,
/// migration-dependent ss13_factions columns (allowed_cargo_category/
/// leader_ckey/leader_char_name/is_company_tier) -- kept in its own query,
/// separate from factionInitialize()'s core faction load, specifically so a
/// schema that hasn't caught up yet (a migration that hasn't been run)
/// only leaves THESE particular fields at their safe defaults instead of
/// failing the entire faction cache load. Add the next new ss13_factions
/// column here, not to the core query.
/datum/controller/subsystem/persistence/proc/_factionLoadExtendedColumns()
	PRIVATE_PROC(TRUE)
	try
		var/datum/db_query/eq = SSdbcore.NewQuery(
			"SELECT uid, allowed_cargo_category, leader_ckey, leader_char_name, is_company_tier FROM ss13_factions",
			list()
		)
		eq.Execute()
		if(databaseCheckQueryResult(eq, "factionInitialize extended columns"))
			while(eq.NextRow())
				var/uid = normalize_faction_uid(eq.item[1])
				if(!(uid in GLOB.persistence_faction_cache))
					continue
				GLOB.persistence_faction_cache[uid]["allowed_cargo_category"] = eq.item[2]
				GLOB.persistence_faction_cache[uid]["leader_ckey"] = eq.item[3]
				GLOB.persistence_faction_cache[uid]["leader_char_name"] = eq.item[4]
				GLOB.persistence_faction_cache[uid]["is_company_tier"] = !!text2num(eq.item[5])
		else
			message_admins("Faction extended-columns load failed -- cargo category/leader/company-tier data unavailable until the schema is updated (db_update?). Core faction data is unaffected.")
		qdel(eq)
	catch(var/exception/ext_e)
		message_admins("Faction extended-columns load threw an exception: [ext_e] -- cargo category/leader/company-tier data unavailable. Core faction data is unaffected.")
		log_subsystem_persistence_error("Factions: failed to load extended columns: [ext_e]")

/// Best-effort enrichment of GLOB.persistence_faction_members_cache with the
/// newer, migration-dependent account_number column -- same reasoning as
/// _factionLoadExtendedColumns() above, split out so a schema that hasn't
/// caught up only leaves payroll account numbers at their 0 default instead
/// of failing the entire members load.
/datum/controller/subsystem/persistence/proc/_factionLoadAccountNumbers()
	PRIVATE_PROC(TRUE)
	try
		var/datum/db_query/aq = SSdbcore.NewQuery(
			"SELECT ckey, faction_uid, account_number, clocked_in FROM ss13_faction_members",
			list()
		)
		aq.Execute()
		if(databaseCheckQueryResult(aq, "factionInitialize account numbers"))
			while(aq.NextRow())
				var/mkey = "[aq.item[1]]|[normalize_faction_uid(aq.item[2])]"
				if(!(mkey in GLOB.persistence_faction_members_cache))
					continue
				GLOB.persistence_faction_members_cache[mkey]["account_number"] = text2num(aq.item[3]) || 0
				GLOB.persistence_faction_members_cache[mkey]["clocked_in"] = !!text2num(aq.item[4])
		else
			message_admins("Faction member account-number load failed -- payroll account numbers unavailable until the schema is updated (db_update?). Core member data is unaffected.")
		qdel(aq)
	catch(var/exception/acct_e)
		message_admins("Faction member account-number load threw an exception: [acct_e] -- payroll account numbers unavailable. Core member data is unaffected.")
		log_subsystem_persistence_error("Factions: failed to load member account numbers: [acct_e]")

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

/// Resolves the founding cost/supporter-threshold for a petition's tier --
/// FACTION_CREATION_COST_COMPANY/FACTION_FOUNDING_REQUIRED_SUPPORTERS_COMPANY
/// (25,000cr/5) for a Company, or the original full-faction constants
/// (100,000cr/10) otherwise. The only OTHER difference between tiers --
/// cargo access -- is handled directly in tryFinalizeFounding() via
/// FACTION_CARGO_CATEGORY_ALL, not through these helpers.
/proc/faction_founding_cost(is_company)
	return is_company ? FACTION_CREATION_COST_COMPANY : FACTION_CREATION_COST

/proc/faction_founding_required_supporters(is_company)
	return is_company ? FACTION_FOUNDING_REQUIRED_SUPPORTERS_COMPANY : FACTION_FOUNDING_REQUIRED_SUPPORTERS

/datum/controller/subsystem/persistence/proc/factionFoundingInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_faction_founding_petitions = list()

	if(!databaseCheckConnection("factionFoundingInitialize"))
		return

	try
		var/datum/db_query/q = SSdbcore.NewQuery(
			"SELECT faction_uid, founder_ckey, founder_name, faction_name, abbreviation, cargo_category, is_company FROM ss13_faction_founding_petitions",
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
					"cargo_category" = q.item[6],
					"is_company"   = !!text2num(q.item[7]),
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

/datum/controller/subsystem/persistence/proc/startFoundingPetition(faction_uid, founder_ckey, founder_name, faction_name, abbreviation, cargo_category, is_company = FALSE)
	faction_uid = normalize_faction_uid(faction_uid)
	if(!databaseCheckConnection("startFoundingPetition"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_founding_petitions (faction_uid, founder_ckey, founder_name, faction_name, abbreviation, cargo_category, is_company) VALUES (:uid, :ckey, :name, :fname, :abbr, :cat, :company)",
		list("uid" = faction_uid, "ckey" = founder_ckey, "name" = founder_name, "fname" = faction_name, "abbr" = abbreviation, "cat" = cargo_category, "company" = is_company ? 1 : 0)
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
			"cargo_category" = cargo_category,
			"is_company"   = is_company,
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
	var/is_company = petition["is_company"]
	var/founding_cost = faction_founding_cost(is_company)
	if(length(petition["supporters"]) < faction_founding_required_supporters(is_company))
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
	if(!acc || acc.money < founding_cost)
		return FALSE // stays queued -- retried next sweep/poll

	if(!databaseCheckConnection("tryFinalizeFounding"))
		return FALSE

	SSeconomy.charge_to_account(acct_num, "Faction Founding", "Founded faction '[petition["faction_name"]]'", null, -founding_cost)

	// Full-tier (non-Company) factions get unrestricted cargo access across
	// every category, the same FACTION_CARGO_CATEGORY_ALL sentinel Hub and
	// the admin "(All)" override already use -- a Company stays limited to
	// the single category it picked during founding, same as every faction
	// works today. Meaningless (and left alone) when the feature is off.
	var/founding_category = petition["cargo_category"]
#ifdef FACTION_CARGO_SPECIALIZATION
	if(!is_company)
		founding_category = FACTION_CARGO_CATEGORY_ALL
#endif //FACTION_CARGO_SPECIALIZATION

	var/datum/db_query/cf_q1 = SSdbcore.NewQuery(
		"INSERT INTO ss13_factions (uid, name, abbreviation, is_lore, founder_ckey, allowed_cargo_category, cargo_category_changed_at, is_company_tier) VALUES (:uid, :name, :abbr, 0, :founder, :cat, NOW(), :company)",
		list("uid" = faction_uid, "name" = petition["faction_name"], "abbr" = petition["abbreviation"], "founder" = founder_ckey, "cat" = founding_category, "company" = is_company ? 1 : 0)
	)
	cf_q1.Execute()
	databaseCheckQueryResult(cf_q1, "tryFinalizeFounding insert")
	qdel(cf_q1)

	var/datum/db_query/cf_q2 = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance) ON DUPLICATE KEY UPDATE balance = VALUES(balance), saved_at = NOW()",
		list("uid" = faction_uid, "balance" = founding_cost)
	)
	cf_q2.Execute()
	databaseCheckQueryResult(cf_q2, "tryFinalizeFounding account")
	qdel(cf_q2)

	if(!islist(GLOB.persistence_faction_cache))
		GLOB.persistence_faction_cache = list()
	GLOB.persistence_faction_cache[faction_uid] = list("name" = petition["faction_name"], "abbreviation" = petition["abbreviation"], "balance" = founding_cost, "founder_ckey" = founder_ckey, "master_card_lost" = FALSE, "allowed_cargo_category" = founding_category, "is_company_tier" = is_company)
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

	// Company tier only -- auto-list on the stock exchange and seed the
	// founder at 100% shares (CEO), the exact same two steps the manual
	// "List on Stock Exchange" officer action performs (faction_manage.dm).
	// Both procs are offline-safe (founder_mob may be null here) -- matches
	// this whole proc's own offline-safe design. A listing failure is
	// logged but never blocks faction creation itself, same as a failed
	// master card spawn a few lines below.
	if(is_company)
		var/list_fail = stockMarketListFaction(faction_uid, founder_mob)
		if(list_fail)
			message_admins("Company '[petition["faction_name"]]' ([faction_uid]) founded, but auto-listing on the stock exchange failed: [list_fail]")
		else
			factionGrantShareholder(faction_uid, founder_ckey, petition["founder_name"], 100, "Company Founding", null)

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
		to_chat(founder_mob, SPAN_GOOD("Founding petition successful! '[petition["faction_name"]]' ([faction_uid]) is now a registered [is_company ? "company" : "faction"] with a starting balance of [founding_cost] credits.[spawn_turf ? " A faction master card has been printed." : ""][is_company ? " It has been automatically listed on the stock exchange -- you hold 100% of its shares." : ""]"))
	log_game("Founding petition for '[faction_uid]' ([petition["faction_name"]]) succeeded -- founder [petition["founder_name"]] ([founder_ckey]), [length(petition["supporters"])] supporters, [founding_cost] credits paid, tier [is_company ? "Company" : "Full Faction"].")
	message_admins("A founding petition succeeded: '[petition["faction_name"]]' ([faction_uid]), founded by [petition["founder_name"]] ([founder_ckey]) with [length(petition["supporters"])] supporters, paying [founding_cost] credits ([is_company ? "Company" : "Full Faction"] tier).[founder_mob ? " (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[founder_mob.x];Y=[founder_mob.y];Z=[founder_mob.z]'>JMP</a>)" : ""]")

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
		if(islist(petition) && length(petition["supporters"]) >= faction_founding_required_supporters(petition["is_company"]))
			tryFinalizeFounding(faction_uid)

/// Simple to_chat notification for faction-wide events -- messages every
/// currently-connected human mob whose ID card marks them a member of uid,
/// so the whole faction finds out immediately instead of only noticing next
/// time they happen to open Faction Management. Not alliance-specific (used
/// by Leave Faction, card.dm, too) -- kept always-compiled rather than
/// under #ifdef FACTION_ALLIANCES, even though that's the feature that
/// first introduced it.
/proc/notify_faction_members(uid, message)
	uid = normalize_faction_uid(uid)
	if(!uid)
		return
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.client)
			continue
		var/obj/item/card/id/ID = H.GetIdCard()
		if(!ID || !ID.employer_faction)
			continue
		if(normalize_faction_uid(ID.employer_faction) != uid)
			continue
		to_chat(H, message)

// ============================================================
// FACTION ALLIANCES
// ============================================================

#ifdef FACTION_ALLIANCES
/// Adjacency list: uid -> list of allied uids, populated in BOTH directions
/// regardless of which column order a row was stored under.
GLOBAL_LIST_EMPTY(persistence_faction_alliances)
/// Pending one-directional proposals: list(list("proposer"=uid, "target"=uid)).
GLOBAL_LIST_EMPTY(persistence_faction_alliance_requests)

/datum/controller/subsystem/persistence/proc/factionAlliancesInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_faction_alliances = list()
	GLOB.persistence_faction_alliance_requests = list()

	if(!databaseCheckConnection("factionAlliancesInitialize"))
		return

	try
		var/datum/db_query/q = SSdbcore.NewQuery("SELECT faction_a, faction_b FROM ss13_faction_alliances", list())
		q.Execute()
		if(databaseCheckQueryResult(q, "factionAlliancesInitialize alliances"))
			while(q.NextRow())
				_cache_faction_alliance(q.item[1], q.item[2])
		qdel(q)
	catch(var/exception/alliances_e)
		log_subsystem_persistence_error("Factions: failed to load alliances: [alliances_e]")

	try
		var/datum/db_query/rq = SSdbcore.NewQuery("SELECT proposer_uid, target_uid FROM ss13_faction_alliance_requests", list())
		rq.Execute()
		if(databaseCheckQueryResult(rq, "factionAlliancesInitialize requests"))
			while(rq.NextRow())
				GLOB.persistence_faction_alliance_requests += list(list("proposer" = rq.item[1], "target" = rq.item[2]))
		qdel(rq)
	catch(var/exception/requests_e)
		log_subsystem_persistence_error("Factions: failed to load alliance requests: [requests_e]")

	log_subsystem_persistence_info("Factions: Loaded [length(GLOB.persistence_faction_alliances)] allied faction(s), [length(GLOB.persistence_faction_alliance_requests)] pending alliance request(s).")

/proc/_cache_faction_alliance(uid_a, uid_b)
	if(!islist(GLOB.persistence_faction_alliances[uid_a]))
		GLOB.persistence_faction_alliances[uid_a] = list()
	GLOB.persistence_faction_alliances[uid_a] |= uid_b
	if(!islist(GLOB.persistence_faction_alliances[uid_b]))
		GLOB.persistence_faction_alliances[uid_b] = list()
	GLOB.persistence_faction_alliances[uid_b] |= uid_a

/proc/_uncache_faction_alliance(uid_a, uid_b)
	if(islist(GLOB.persistence_faction_alliances[uid_a]))
		GLOB.persistence_faction_alliances[uid_a] -= uid_b
	if(islist(GLOB.persistence_faction_alliances[uid_b]))
		GLOB.persistence_faction_alliances[uid_b] -= uid_a

/// TRUE if the two faction uids are currently allied. FALSE for null/blank/
/// identical uids -- same-faction is a different, already-handled case at
/// every call site.
/proc/factions_are_allied(uid_a, uid_b)
	uid_a = normalize_faction_uid(uid_a)
	uid_b = normalize_faction_uid(uid_b)
	if(!uid_a || !uid_b || uid_a == uid_b)
		return FALSE
	return islist(GLOB.persistence_faction_alliances[uid_a]) && (uid_b in GLOB.persistence_faction_alliances[uid_a])

/proc/_find_faction_alliance_request(proposer_uid, target_uid)
	if(!islist(GLOB.persistence_faction_alliance_requests))
		return FALSE
	for(var/list/req in GLOB.persistence_faction_alliance_requests)
		if(req["proposer"] == proposer_uid && req["target"] == target_uid)
			return TRUE
	return FALSE

/// Proposes an alliance from proposer_uid to target_uid. Returns "allied" if
/// this immediately completed a mutual handshake (the target had already
/// proposed to the proposer -- both sides offering a hand completes it right
/// there instead of leaving two redundant pending requests), "proposed" if a
/// new one-directional request was created (or one already existed), or
/// null on failure (invalid uids, already allied, or a DB error).
/proc/propose_faction_alliance(proposer_uid, target_uid)
	proposer_uid = normalize_faction_uid(proposer_uid)
	target_uid = normalize_faction_uid(target_uid)
	if(!proposer_uid || !target_uid || proposer_uid == target_uid)
		return null
	if(factions_are_allied(proposer_uid, target_uid))
		return null
	if(_find_faction_alliance_request(target_uid, proposer_uid))
		return accept_faction_alliance(proposer_uid, target_uid) ? "allied" : null
	if(_find_faction_alliance_request(proposer_uid, target_uid))
		return "proposed" // already pending, nothing new to do
	if(!SSpersistence.databaseCheckConnection("propose_faction_alliance"))
		return null
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_alliance_requests (proposer_uid, target_uid) VALUES (:p, :t)",
		list("p" = proposer_uid, "t" = target_uid)
	)
	q.Execute()
	var/ok = SSpersistence.databaseCheckQueryResult(q, "propose_faction_alliance")
	qdel(q)
	if(!ok)
		return null
	GLOB.persistence_faction_alliance_requests += list(list("proposer" = proposer_uid, "target" = target_uid))
	return "proposed"

/// Called with accepting_uid = the TARGET of a pending request, finalizing
/// the alliance with proposer_uid. Also used internally by
/// propose_faction_alliance() when a mutual handshake completes it early.
/proc/accept_faction_alliance(accepting_uid, proposer_uid)
	accepting_uid = normalize_faction_uid(accepting_uid)
	proposer_uid = normalize_faction_uid(proposer_uid)
	if(!_find_faction_alliance_request(proposer_uid, accepting_uid))
		return FALSE
	if(!SSpersistence.databaseCheckConnection("accept_faction_alliance"))
		return FALSE
	var/uid_a = proposer_uid
	var/uid_b = accepting_uid
	if(uid_a > uid_b)
		var/tmp_swap = uid_a
		uid_a = uid_b
		uid_b = tmp_swap
	var/datum/db_query/insert_q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_alliances (faction_a, faction_b) VALUES (:a, :b) ON DUPLICATE KEY UPDATE allied_at = allied_at",
		list("a" = uid_a, "b" = uid_b)
	)
	insert_q.Execute()
	var/ok = SSpersistence.databaseCheckQueryResult(insert_q, "accept_faction_alliance insert")
	qdel(insert_q)
	if(!ok)
		return FALSE
	var/datum/db_query/del_q = SSdbcore.NewQuery(
		"DELETE FROM ss13_faction_alliance_requests WHERE proposer_uid = :p AND target_uid = :t",
		list("p" = proposer_uid, "t" = accepting_uid)
	)
	del_q.Execute()
	SSpersistence.databaseCheckQueryResult(del_q, "accept_faction_alliance delete request")
	qdel(del_q)
	for(var/i = length(GLOB.persistence_faction_alliance_requests); i >= 1; i--)
		var/list/req = GLOB.persistence_faction_alliance_requests[i]
		if(req["proposer"] == proposer_uid && req["target"] == accepting_uid)
			GLOB.persistence_faction_alliance_requests.Cut(i, i + 1)
	_cache_faction_alliance(uid_a, uid_b)
	return TRUE

/// Deletes a pending request -- used by both "Decline" (target's own
/// perspective) and "Withdraw" (proposer's own perspective); the caller
/// supplies proposer_uid/target_uid however it likes, this doesn't care
/// which side is acting.
/proc/cancel_faction_alliance_request(proposer_uid, target_uid)
	proposer_uid = normalize_faction_uid(proposer_uid)
	target_uid = normalize_faction_uid(target_uid)
	if(SSpersistence.databaseCheckConnection("cancel_faction_alliance_request"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_faction_alliance_requests WHERE proposer_uid = :p AND target_uid = :t",
			list("p" = proposer_uid, "t" = target_uid)
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "cancel_faction_alliance_request")
		qdel(q)
	for(var/i = length(GLOB.persistence_faction_alliance_requests); i >= 1; i--)
		var/list/req = GLOB.persistence_faction_alliance_requests[i]
		if(req["proposer"] == proposer_uid && req["target"] == target_uid)
			GLOB.persistence_faction_alliance_requests.Cut(i, i + 1)
	return TRUE

/// Dissolves an existing alliance -- either side can call this at any time,
/// no cooldown, no confirmation beyond whatever the UI itself asks for.
/proc/break_faction_alliance(uid_a, uid_b)
	uid_a = normalize_faction_uid(uid_a)
	uid_b = normalize_faction_uid(uid_b)
	if(SSpersistence.databaseCheckConnection("break_faction_alliance"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM ss13_faction_alliances WHERE (faction_a = :a AND faction_b = :b) OR (faction_a = :b AND faction_b = :a)",
			list("a" = uid_a, "b" = uid_b)
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "break_faction_alliance")
		qdel(q)
	_uncache_faction_alliance(uid_a, uid_b)
	return TRUE
#endif //FACTION_ALLIANCES

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
	play_announcer_voice_to_all(new_state ? 'sound/AI/announcements/raiding_allowed.ogg' : 'sound/AI/announcements/raiding_prohibited.ogg')
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

/// An admin-designated faction leader (list("ckey"=, "char_name"=)), or null
/// if none is set. Distinct from founder_ckey -- set/cleared at any time via
/// "Manage Faction Account" -> "Set Faction Leader", meant for factions
/// created via the admin "create faction" verb that have no organic founder
/// to fall back on for the "Print Master Card" action.
/proc/get_faction_leader(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return null
	var/list/data = GLOB.persistence_faction_cache[uid]
	if(!data["leader_ckey"])
		return null
	return list("ckey" = data["leader_ckey"], "char_name" = data["leader_char_name"])

/// Whether (ckey, char_name) is the currently-designated leader of uid.
/proc/is_faction_designated_leader(uid, ckey, char_name)
	var/list/leader = get_faction_leader(uid)
	if(!leader)
		return FALSE
	return leader["ckey"] == ckey && leader["char_name"] == char_name

/// Whether uid was founded through the cheaper Company tier (vs a Full
/// Faction) -- permanent, set once at tryFinalizeFounding() and never
/// changed afterward. Unrelated to stock market listing/CEO status -- a
/// Full Faction that later lists and gets a CEO is still not "company
/// tier". FALSE for admin-made factions (no tier concept at all) and for
/// every faction founded before this existed.
/proc/is_company_tier_faction(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	return !!GLOB.persistence_faction_cache[uid]["is_company_tier"]

/// Sets (or, with null/null, clears) a faction's designated leader, updating
/// the cache and persisting it so it survives a reboot.
/proc/set_faction_leader(uid, ckey, char_name)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	GLOB.persistence_faction_cache[uid]["leader_ckey"] = ckey
	GLOB.persistence_faction_cache[uid]["leader_char_name"] = char_name
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/lq = SSdbcore.NewQuery(
			"UPDATE ss13_factions SET leader_ckey = :ckey, leader_char_name = :name WHERE uid = :uid",
			list("ckey" = ckey, "name" = char_name, "uid" = uid)
		)
		lq.Execute()
		qdel(lq)
	return TRUE

/// Whether an unrevoked faction_master card for uid currently exists
/// anywhere in the world -- distinguishes "never printed yet" (admin-made
/// factions, which skip the organic founding flow that spawns one
/// automatically) from "printed, then lost/compromised" (master_card_lost),
/// both of which "Print Master Card" needs to treat as mintable.
/proc/has_live_faction_master_card(uid)
	uid = normalize_faction_uid(uid)
	for(var/obj/item/card/id/faction_master/c in world)
		if(!c.revoked && normalize_faction_uid(c.employer_faction) == uid)
			return TRUE
	return FALSE

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

/// FACTION_CARGO_SPECIALIZATION -- the ONE cargo order category (or null,
/// "hasn't chosen one yet") a real faction is currently allowed to order
/// from. Callers are responsible for excluding "hub" before calling this --
/// it is never itself the thing that decides Hub is unrestricted.
/proc/get_faction_allowed_cargo_category(uid)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return null
	return GLOB.persistence_faction_cache[uid]["allowed_cargo_category"]

/// Seconds remaining before a faction's cargo category can next be changed
/// by an OFFICER (see set_faction_allowed_cargo_category()'s own re-check),
/// 0 if clear/never-set. Live DB read (real calendar time, not world.time --
/// must survive reboots) -- same TIMESTAMPDIFF/NOW() shape already shipped
/// for imprisonment expiry (persistence_mobs.dm).
/proc/get_faction_cargo_category_cooldown_remaining(uid)
	uid = normalize_faction_uid(uid)
	if(!SSpersistence.databaseCheckConnection("get_faction_cargo_category_cooldown_remaining"))
		return 0
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT TIMESTAMPDIFF(SECOND, NOW(), DATE_ADD(cargo_category_changed_at, INTERVAL 1 MONTH)) FROM ss13_factions WHERE uid = :uid AND cargo_category_changed_at IS NOT NULL",
		list("uid" = uid)
	)
	q.Execute()
	. = 0
	if(SSpersistence.databaseCheckQueryResult(q, "get_faction_cargo_category_cooldown_remaining") && q.NextRow())
		. = max(0, text2num(q.item[1]) || 0)
	qdel(q)

/// Sets a real faction's single allowed cargo category. Refuses (returns
/// FALSE) if the 1-month real-world cooldown since the last change hasn't
/// elapsed yet, unless bypass_cooldown is set (admin override,
/// manage_faction_account()) -- cargo_category_changed_at is stamped to
/// NOW() either way, so an admin override still restarts the normal clock
/// for the next OFFICER-initiated change rather than leaving it bypassable.
/proc/set_faction_allowed_cargo_category(uid, category, bypass_cooldown = FALSE)
	uid = normalize_faction_uid(uid)
	if(!islist(GLOB.persistence_faction_cache) || !(uid in GLOB.persistence_faction_cache))
		return FALSE
	if(!bypass_cooldown && get_faction_cargo_category_cooldown_remaining(uid) > 0)
		return FALSE
	if(!SSpersistence.databaseCheckConnection("set_faction_allowed_cargo_category"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_factions SET allowed_cargo_category = :cat, cargo_category_changed_at = NOW() WHERE uid = :uid",
		list("uid" = uid, "cat" = category)
	)
	q.Execute()
	var/ok = SSpersistence.databaseCheckQueryResult(q, "set_faction_allowed_cargo_category")
	qdel(q)
	if(ok)
		GLOB.persistence_faction_cache[uid]["allowed_cargo_category"] = category
	return ok

/// Whether uid has been granted "(All)" cargo access -- an admin-only override
/// (Set Cargo Category) that lifts the single-category restriction for a real
/// faction without making it Hub. Distinct from Hub's own unrestricted access,
/// which every caller already checks separately via a plain uid comparison
/// (see get_faction_allowed_cargo_category()'s own doc comment).
/proc/faction_cargo_unrestricted(uid)
	return get_faction_allowed_cargo_category(uid) == FACTION_CARGO_CATEGORY_ALL

/// Whether `user` is authorized to travel/warp/disembark into the CentCom
/// ("Frontier Beacon Depot") sector -- Hub-affiliated personnel above
/// baseline civilian rank (get_effective_faction_rank()'s own "0 = civilian
/// member, no elevation" reading), or an admin (rank 99, same bypass every
/// other faction-rank gate in this codebase already grants). Checked by
/// every way of physically reaching that sector: Personal Travel's leap
/// (personal_travel.dm), travel pad "pod warp" (telepad_travel.dm), and
/// drydock disembark (telepad_drydock_boarding.dm).
/proc/can_access_hub_depot(mob/user)
	return get_effective_faction_rank(user, "hub") > 0

/// Called right after a faction's stored display name changes (Rename
/// Faction), so every physical item that baked the OLD name into its own
/// .name at print/insert time shows the new one immediately -- ID cards
/// (including the bearer master card, via update_name()), PDAs/consoles
/// with a card currently inserted (card_slot.dm normally only does this
/// naming once, at insert time), and faction charge cards. Everything else
/// that displays a faction's name (examine text, to_chat, UI panels, access
/// checks) already resolves it live via get_faction_name(uid) every time
/// it's shown and needs no help. Invoices are deliberately left alone --
/// they're historical receipts of a completed transaction, not live
/// identity, and shouldn't be rewritten after the fact.
/proc/refresh_faction_display_names(uid)
	uid = normalize_faction_uid(uid)

	for(var/obj/item/card/id/ID in world)
		if(normalize_faction_uid(ID.employer_faction) != uid)
			continue
		ID.update_name()
		var/obj/item/computer_hardware/card_slot/slot = ID.loc
		if(istype(slot) && slot.parent_computer && slot.stored_card == ID)
			var/obj/item/modular_computer/pc = slot.parent_computer
			pc.name = "[pc.initial_name] - [ID.registered_name] ([get_faction_name(ID.employer_faction) || ID.employer_faction]) ([ID.assignment])"

	for(var/obj/item/spacecash/ewallet/faction_charge_card/FC in world)
		if(normalize_faction_uid(FC.faction_uid) != uid)
			continue
		FC.name = "[get_faction_name(uid)] charge card"
		FC.owner_name = get_faction_name(uid)

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

/// 10% cargo tariff/duty rate for trade happening inside a faction beacon's
/// claimed territory (direct Z or radius reach, get_owning_faction_beacon()).
#define CARGO_TERRITORY_TAX_RATE 0.10

/// Resolves which faction (if any) should receive cargo tax for a
/// transaction at z -- null if the territory is unclaimed, or if the trader
/// is exempt as a member of the claiming faction. trader_faction_uid is the
/// transaction's own faction (delivery_network/exp_net/a ship's faction_uid),
/// checked first; trader (a mob) is a fallback for transactions with no
/// faction of their own (personal orders) -- exempt if the mob's own ID
/// shows membership in the claiming faction.
/proc/get_cargo_tax_beneficiary(z, trader_faction_uid, mob/trader)
	var/obj/structure/machinery/faction_beacon/owner = get_owning_faction_beacon(z)
	if(!owner || !owner.faction_uid)
		return null
	var/owner_uid = normalize_faction_uid(owner.faction_uid)
	if(trader_faction_uid && normalize_faction_uid(trader_faction_uid) == owner_uid)
		return null
	if(!trader_faction_uid && trader)
		var/obj/item/card/id/ID = trader.GetIdCard()
		var/mob_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
		if(mob_faction && mob_faction == owner_uid)
			return null
	return owner.faction_uid

/// Applies the territory cargo tax to a base amount, crediting the territory
/// faction's cut via faction_credit() as a side effect. Returns the amount
/// the OTHER party should actually pay/receive: base_amount + tax for an
/// import (buyer pays more), base_amount - tax for an export (seller nets
/// less). Returns base_amount unchanged if untaxed (no claiming faction, or
/// the trader is exempt).
/proc/apply_cargo_territory_tax(z, base_amount, is_import, trader_faction_uid, mob/trader, reason)
	var/beneficiary = get_cargo_tax_beneficiary(z, trader_faction_uid, trader)
	if(!beneficiary)
		return base_amount
	var/tax = round(base_amount * CARGO_TERRITORY_TAX_RATE)
	if(tax <= 0)
		return base_amount
	faction_credit(beneficiary, tax, reason)
	return is_import ? (base_amount + tax) : (base_amount - tax)

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
		// uid is an internal lookup key (lowercased, spaces->underscores by
		// normalize_faction_uid()) -- never display it raw. Covers the "hub"
		// sentinel (the default/unclaimed network, which has no real founded-
		// faction row to look up) and any other uncached/stale uid.
		return capitalize_first_letters(replacetext(uid, "_", " "))
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
	// CentCom is a bare, template-less Z built directly by atlas.dm at boot --
	// no ruin/away_site template ever loads there, so the DB-row pinning
	// below (meant for regenerating a ruin at the same overmap spot next
	// boot) doesn't apply and never will. It always exists at boot
	// regardless, so it just needs the same persistence-allow marking a
	// real pinned site gets, with no DB row of its own.
	if(is_centcom_level(z))
		GLOB.persistence_pinned_site_z |= z
		GLOB.persistence_zlevel_allow |= z
		return TRUE
	var/datum/map_template/here_template = GLOB.map_templates["[z]"]
	if(!istype(here_template, /datum/map_template/ruin/away_site))
		return FALSE
	if(!SSpersistence.databaseCheckConnection("persistence_pin_site_at_z"))
		return FALSE

	// Matches the DB's actual unique key (template_name, overmap_x, overmap_y)
	// -- V103__multi_instance_pinned_sites.sql -- not just template+map, so a
	// second site sharing a template at a DIFFERENT position (two factions
	// each claiming their own instance, say) doesn't silently no-op here
	// instead of actually getting pinned.
	var/datum/db_query/check = SSdbcore.NewQuery(
		"SELECT id FROM ss13_persistent_away_sites WHERE template_name = :tn AND map_path = :mp AND overmap_x = :ox AND overmap_y = :oy",
		list("tn" = here_template.id, "mp" = "[SSatlas.current_map.path]", "ox" = (here_marker ? here_marker.start_x : 0), "oy" = (here_marker ? here_marker.start_y : 0))
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
			// Matches the DB's actual unique key (template_name, overmap_x,
			// overmap_y) -- multiple pinned instances of the same template are
			// allowed at different positions, only a literal duplicate at the
			// exact same coordinates isn't.
			var/already_pinned = FALSE
			for(var/list/row in rows)
				if(row["template"] == here_template.id && row["om_x"] == here_marker.start_x && row["om_y"] == here_marker.start_y)
					already_pinned = TRUE
					break
			if(already_pinned)
				to_chat(usr, SPAN_WARNING("'[here_template.id]' is already pinned at this exact position."))
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
			// A template is only unpickable while it has a PENDING pin still
			// sitting at the placeholder (0,0)/unspawned position -- two
			// simultaneously-pending pins of the same template would collide
			// there. Once a pinned row has actually spawned once,
			// build_pinned_away_sites() overwrites its coordinates with its
			// real position, freeing the template up for another instance.
			var/list/pinnable = list()
			for(var/site_id in SSmapping.away_sites_templates)
				var/id_taken = FALSE
				for(var/list/row in rows)
					if(row["template"] == site_id && !row["om_x"] && !row["om_y"] && !row["last_z"])
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
			CHECK_TICK
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
		CHECK_TICK
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

	maybe_populate_away_site_with_pirates(site_z, site.id)

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
		CHECK_TICK
		return FALSE // an unmined wall vein still exists
	for(var/turf/simulated/floor/exoplanet/asteroid/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		CHECK_TICK
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
		CHECK_TICK
		if(M.z == z && M.stat != DEAD && (M.client || M.ckey))
			return TRUE
	for(var/obj/item/organ/internal/neural_lace/L in world)
		CHECK_TICK
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
	// wipe turfs to plain space, then remove the overmap marker. Pass 1 is a
	// type-indexed world scan (the safe pattern): qdel'ing an object can
	// itself spawn/drop a new movable as a side effect (an APC ejecting its
	// cell is normal APC behavior), which a one-shot turf/contents snapshot
	// taken before that qdel would never catch. Passes 2+ mop up whatever
	// pass 1's qdel cascade freshly ejected -- those land directly on a turf
	// (never nested), so a Z-scoped turf/contents re-check is safe there and,
	// critically, bounded to this Z's own turf count instead of a second full
	// for(TYPE in world) sweep. Repeating the world-wide scan every pass was
	// a real hang: qdel() only calls Destroy() immediately (SSgarbage defers
	// the real del()), so a just-qdel'd object with its .loc/.z untouched
	// keeps matching on every subsequent pass, guaranteeing all 5 passes ran
	// as full-world scans every time.
	for(var/atom/movable/AM in world)
		CHECK_TICK
		if(AM.z != z)
			continue
		qdel(AM)

	var/pass = 1
	var/found_any = TRUE
	while(found_any && pass < 5)
		found_any = FALSE
		pass++
		for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			CHECK_TICK
			var/list/contents_snapshot = T.contents.Copy()
			for(var/atom/movable/AM in contents_snapshot)
				qdel(AM)
				found_any = TRUE

	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
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
		// The issuing faction IS this ID's employer -- sync the mob before
		// set_id_info() copies employer_faction onto the card, otherwise it
		// stamps the holder's old prefs faction straight back over chosen_uid.
		H.employer_faction = chosen_uid
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

	var/list/top_actions = list("Create New Faction", "Rename Faction", "Modify Faction Balance", "Remove Faction", "Set Faction Leader")
#ifdef FACTION_CARGO_SPECIALIZATION
	top_actions += "Set Cargo Category"
#endif //FACTION_CARGO_SPECIALIZATION
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

		if(islist(GLOB.persistence_faction_cache))
			for(var/existing_uid in GLOB.persistence_faction_cache)
				var/list/existing = GLOB.persistence_faction_cache[existing_uid]
				if(lowertext(existing["name"]) == lowertext(new_name))
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

	//  Rename
	else if(top == "Rename Faction")
		if(!islist(GLOB.persistence_faction_cache) || !length(GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("No factions exist yet. Create one first."))
			return

		var/list/faction_options = list()
		for(var/uid in GLOB.persistence_faction_cache)
			var/list/data = GLOB.persistence_faction_cache[uid]
			faction_options["[data["name"]] ([uid])"] = uid

		var/chosen_label = tgui_input_list(usr, "Select a faction to rename:", "Rename Faction", faction_options)
		if(!chosen_label) return
		var/chosen_uid = faction_options[chosen_label]

		var/renamed  = tgui_input_text(usr, "New name for '[get_faction_name(chosen_uid)]':", "Rename Faction", get_faction_name(chosen_uid), max_length = 64)
		if(!renamed) return

		for(var/existing_uid in GLOB.persistence_faction_cache)
			if(existing_uid == chosen_uid)
				continue
			var/list/existing = GLOB.persistence_faction_cache[existing_uid]
			if(lowertext(existing["name"]) == lowertext(renamed))
				to_chat(usr, SPAN_WARNING("A faction named '[renamed]' already exists (uid '[existing_uid]')."))
				return

		if(!SSpersistence.databaseCheckConnection("rename_faction"))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return

		var/datum/db_query/rn_q = SSdbcore.NewQuery(
			"UPDATE ss13_factions SET name = :name WHERE uid = :uid",
			list("name" = renamed, "uid" = chosen_uid)
		)
		rn_q.Execute()
		if(!SSpersistence.databaseCheckQueryResult(rn_q, "rename_faction"))
			qdel(rn_q)
			to_chat(usr, SPAN_WARNING("Database write failed."))
			return
		qdel(rn_q)

		var/old_name = GLOB.persistence_faction_cache[chosen_uid]["name"]
		GLOB.persistence_faction_cache[chosen_uid]["name"] = renamed
		refresh_faction_display_names(chosen_uid)

		to_chat(usr, SPAN_GOOD("Renamed '[old_name]' ([chosen_uid]) to '[renamed]'."))
		log_and_message_admins("renamed faction '[chosen_uid]' from '[old_name]' to '[renamed]'", usr)

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

		if(!SSpersistence.removeFactionCompletely(chosen_uid, usr))
			to_chat(usr, SPAN_WARNING("DB connection failed."))
			return

		to_chat(usr, SPAN_GOOD("Faction '[chosen_uid]' removed."))

	//  Set Leader
	else if(top == "Set Faction Leader")
		if(!islist(GLOB.persistence_faction_cache) || !length(GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("No factions exist yet. Create one first."))
			return

		var/list/faction_options = list()
		for(var/uid in GLOB.persistence_faction_cache)
			var/list/data = GLOB.persistence_faction_cache[uid]
			var/leader_txt = data["leader_ckey"] ? " -- leader: [data["leader_char_name"]] ([data["leader_ckey"]])" : ""
			faction_options["[get_faction_name(uid)][leader_txt]"] = uid

		var/chosen_label = tgui_input_list(usr, "Select a faction:", "Set Faction Leader", faction_options)
		if(!chosen_label) return
		var/chosen_uid = faction_options[chosen_label]

		var/how = tgui_input_list(usr, "How would you like to set the leader for '[get_faction_name(chosen_uid)]'?", "Set Faction Leader", list("Pick online player", "Enter ckey manually", "Clear leader"))
		if(!how) return

		if(how == "Clear leader")
			set_faction_leader(chosen_uid, null, null)
			to_chat(usr, SPAN_GOOD("Cleared the designated leader for [get_faction_name(chosen_uid)]."))
			log_and_message_admins("cleared the designated leader for faction '[chosen_uid]'", usr)
		else
			var/target_ckey
			var/target_name

			if(how == "Pick online player")
				var/mob/target = tgui_input_list(usr, "Choose leader:", "Set Faction Leader", GLOB.player_list)
				if(!target) return
				target_ckey = target.ckey
				target_name = target.real_name
			else
				target_ckey = tgui_input_text(usr, "Enter ckey:", "Set Faction Leader", max_length = 32)
				if(!target_ckey) return
				target_ckey = ckey(target_ckey)

				if(!SSpersistence.databaseCheckConnection("set_faction_leader_lookup"))
					to_chat(usr, SPAN_WARNING("DB connection failed."))
					return
				var/datum/db_query/cq = SSdbcore.NewQuery(
					"SELECT name FROM ss13_characters WHERE ckey = :ckey AND deleted_at IS NULL ORDER BY id ASC",
					list("ckey" = target_ckey)
				)
				cq.Execute()
				SSpersistence.databaseCheckQueryResult(cq, "set_faction_leader_lookup")
				var/list/names = list()
				while(cq.NextRow())
					names += cq.item[1]
				qdel(cq)
				if(!length(names))
					to_chat(usr, SPAN_WARNING("No saved characters found for ckey '[target_ckey]'."))
					return
				target_name = tgui_input_list(usr, "Select [target_ckey]'s character to designate as leader:", "Set Faction Leader", names)
				if(!target_name) return

			set_faction_leader(chosen_uid, target_ckey, target_name)

			// If this faction is already listed on the stock exchange, the
			// designated leader should also become its CEO immediately --
			// reset the cap table to 100% in their favor rather than leaving
			// the new leader printing master cards while someone else still
			// holds (or shares) real equity/dividend rights over the same
			// faction.
			var/datum/stock_company/existing_listing = get_faction_stock_company(chosen_uid)
			if(existing_listing)
				SSpersistence.factionClearShareholders(chosen_uid)
				SSpersistence.factionGrantShareholder(chosen_uid, target_ckey, target_name, 100, "Admin Reassignment", null)
				to_chat(usr, SPAN_GOOD("Set [target_name] ([target_ckey]) as the designated leader of [get_faction_name(chosen_uid)], and reset its stock listing to 100% in their favor (making them CEO)."))
				log_and_message_admins("set faction '[chosen_uid]' leader to [target_name] ([target_ckey]) and reset its shareholder cap table to 100% in their favor (already listed)", usr)
			else
				to_chat(usr, SPAN_GOOD("Set [target_name] ([target_ckey]) as the designated leader of [get_faction_name(chosen_uid)]. They can print a master card at any Faction Management console."))
				log_and_message_admins("set faction '[chosen_uid]' leader to [target_name] ([target_ckey])", usr)

#ifdef FACTION_CARGO_SPECIALIZATION
	else if(top == "Set Cargo Category")
		if(!islist(GLOB.persistence_faction_cache) || !length(GLOB.persistence_faction_cache))
			to_chat(usr, SPAN_WARNING("No factions exist."))
			return

		var/list/faction_options = list()
		for(var/uid in GLOB.persistence_faction_cache)
			faction_options[get_faction_name(uid)] = uid

		var/faction_label = tgui_input_list(usr, "Which faction?", "Set Cargo Category", faction_options)
		if(!faction_label) return
		var/target_uid = faction_options[faction_label]

		var/list/category_options = list("(Clear -- nothing orderable)" = null, "(All -- no restriction)" = FACTION_CARGO_CATEGORY_ALL)
		for(var/cat_name in SScargo.cargo_categories)
			var/singleton/cargo_category/cc = SScargo.cargo_categories[cat_name]
			category_options[cc.display_name] = cc.name

		var/category_label = tgui_input_list(usr, "Cargo category for '[get_faction_name(target_uid)]':", "Set Cargo Category", category_options)
		if(isnull(category_label)) return

		set_faction_allowed_cargo_category(target_uid, category_options[category_label], bypass_cooldown = TRUE)
		to_chat(usr, SPAN_NOTICE("'[get_faction_name(target_uid)]'s cargo category set to '[category_label]'."))
		log_and_message_admins("set faction '[target_uid]'s allowed cargo category to '[category_label]'", usr)
#endif //FACTION_CARGO_SPECIALIZATION

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

/// Removes a ckey's membership record entirely -- the missing inverse of
/// factionRegisterMember(). Distinct from _revoke_member_id_now()
/// (faction_manage.dm), which only invalidates physical ID cards without
/// touching this roster; callers that mean "gone for good" (Remove Member,
/// Leave Faction) call both.
/datum/controller/subsystem/persistence/proc/factionRemoveMember(ckey, faction_uid)
	faction_uid = normalize_faction_uid(faction_uid)
	if(!databaseCheckConnection("factionRemoveMember"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_faction_members WHERE ckey = :ckey AND faction_uid = :uid",
		list("ckey" = ckey, "uid" = faction_uid)
	)
	q.Execute()
	var/ok = databaseCheckQueryResult(q, "factionRemoveMember")
	qdel(q)
	if(ok)
		GLOB.persistence_faction_members_cache -= "[ckey]|[faction_uid]"
	return ok

/// Sets a member's on-shift state -- gates factionPayroll() on top of the
/// existing online/actively-played-character requirement. Cleared
/// automatically by persistStoreCharacter() (persistence_cryo.dm) whenever
/// a member is stored via the persistence cryo system, normal or prison.
/datum/controller/subsystem/persistence/proc/factionSetClockedIn(ckey, faction_uid, clocked_in)
	faction_uid = normalize_faction_uid(faction_uid)
	if(!databaseCheckConnection("factionSetClockedIn"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_faction_members SET clocked_in = :clocked WHERE ckey = :ckey AND faction_uid = :uid",
		list("clocked" = clocked_in ? 1 : 0, "ckey" = ckey, "uid" = faction_uid)
	)
	q.Execute()
	var/ok = databaseCheckQueryResult(q, "factionSetClockedIn")
	qdel(q)
	if(ok)
		var/list/member = GLOB.persistence_faction_members_cache["[ckey]|[faction_uid]"]
		if(islist(member))
			member["clocked_in"] = clocked_in
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
		"SELECT ckey, real_name, job_title, account_number, clocked_in FROM ss13_faction_members WHERE faction_uid = :uid AND account_number > 0",
		list("uid" = faction_uid)
	)
	mq.Execute()
	if(!databaseCheckQueryResult(mq, "factionPayroll members"))
		qdel(mq)
		return FALSE

	var/fname = get_faction_name(faction_uid)
	var/paid = 0
	var/skipped = 0
	while(mq.NextRow())
		var/mckey = mq.item[1]
		var/mreal_name = mq.item[2]
		var/mjob  = mq.item[3]
		var/macct = text2num(mq.item[4]) || 0
		var/mclocked_in = text2num(mq.item[5])
		if(!macct || !mjob)
			skipped++
			continue
		// Must be clocked in (ID Card Modification, self-service) to draw a
		// paycheck -- being online and actively playing isn't enough on its
		// own anymore, matches the on-shift toggle's whole purpose.
		if(!mclocked_in)
			skipped++
			continue
		var/pay = get_faction_job_pay(faction_uid, mjob)
		if(pay <= 0)
			skipped++
			continue
		// Only pay a member who is actively playing this exact character
		// right now -- ckey alone isn't enough, since the same ckey could be
		// online on an unrelated character. Same online-mob lookup idiom as
		// announce_faction_event() above.
		var/mob/living/carbon/human/online_mob = null
		for(var/mob/living/carbon/human/H in GLOB.player_list)
			if(!H.client || H.ckey != mckey || H.real_name != mreal_name)
				continue
			online_mob = H
			break
		if(!online_mob)
			skipped++
			continue
		if(!faction_debit(faction_uid, pay, "Payroll to [mckey]"))
			log_game("Faction [faction_uid] payroll: insufficient funds, stopping.")
			break
		SSeconomy.charge_to_account(macct, "Faction Payroll", "Salary from [fname]", null, pay)
		to_chat(online_mob, SPAN_GOOD("Payroll: you've been paid [pay] credits by [fname]."))
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

/// Permanently deletes a faction: DB row (cascades to ss13_faction_accounts/
/// ss13_faction_jobs via foreign key), both in-memory caches, and revokes any
/// outstanding bearer master card. Shared by the admin "Remove Faction"
/// branch (manage_faction_account(), user set) and the automatic stock-
/// exchange bankruptcy path (stockMarketRevokeFaction(),
/// persistence_stock_market.dm, user null) -- a faction that goes bankrupt
/// while listed on the exchange doesn't just lose its territory (see
/// _power_down_faction_beacons_on_bankruptcy(), faction_beacon.dm), it
/// ceases to exist entirely and would have to be founded again from
/// scratch via the normal petition process (start_founding, faction_manage.dm).
/// Returns TRUE on success.
/datum/controller/subsystem/persistence/proc/removeFactionCompletely(faction_uid, mob/user)
	faction_uid = normalize_faction_uid(faction_uid)
	if(!faction_uid || !islist(GLOB.persistence_faction_cache) || !(faction_uid in GLOB.persistence_faction_cache))
		return FALSE
	if(!databaseCheckConnection("removeFactionCompletely"))
		return FALSE

	var/fname = get_faction_name(faction_uid)

	// Delist from the stock exchange first, if listed -- stockMarketRevokeFaction()
	// buys out every holder from the faction's OWN treasury, so it needs to run
	// while that treasury (and the faction row itself) still exists.
	var/datum/stock_company/listed = get_faction_stock_company(faction_uid)
	if(listed)
		stockMarketRevokeFaction(listed.company_id, user)

	// Whatever's left in the treasury after the stock buyout above (or the
	// whole treasury, for a faction that was never listed) gets distributed
	// rather than destroyed by the cascade delete below. Listed with a real
	// cap table: paid to EVERY real shareholder proportionally by their
	// equity percentage (persistence_faction_shareholders.dm -- always sums
	// to exactly 100 for a listed faction), not just the top holder(s).
	// Not listed (or listed with an empty cap table): goes to the leader --
	// the founder via their current membership record (so a stale
	// founder_ckey who has since left the faction doesn't wrongly receive
	// it), falling back to the admin-designated leader if the founder isn't
	// currently resolvable -- the same two identities Print Master Card
	// already trusts as this faction's top authority. If neither resolves,
	// the balance is destroyed, same as before this feature existed.
	var/leftover_balance = get_faction_account_balance(faction_uid) || 0
	if(leftover_balance > 0)
		var/list/held = GLOB.persistence_faction_shareholders_cache[faction_uid]
		if(islist(held) && length(held))
			var/list/recipient_names = list()
			for(var/list/h in held)
				if(h["percent"] <= 0)
					continue
				var/share_amount = round(leftover_balance * h["percent"] / 100)
				if(share_amount <= 0)
					continue
				var/datum/money_account/payout_acc = SSeconomy.get_account_by_ckey_and_name(h["ckey"], h["char_name"])
				if(payout_acc)
					payout_acc.adjust_money(share_amount)
				else
					economyCreditOfflineAccount(h["ckey"], h["char_name"], share_amount)
				recipient_names += "[h["char_name"]] ([h["percent"]]%: [share_amount] cr)"
			if(length(recipient_names))
				log_and_message_admins("faction '[faction_uid]' ([fname]) disbanded with [leftover_balance] cr remaining -- distributed to shareholders by equity: [jointext(recipient_names, ", ")].", user)
		else
			var/leftover_founder_ckey = GLOB.persistence_faction_cache[faction_uid]["founder_ckey"]
			var/list/founder_member = leftover_founder_ckey ? get_faction_member(leftover_founder_ckey, faction_uid) : null
			var/payout_ckey
			var/payout_char_name
			if(founder_member)
				payout_ckey = leftover_founder_ckey
				payout_char_name = founder_member["real_name"]
			else
				var/list/leader = get_faction_leader(faction_uid)
				if(leader)
					payout_ckey = leader["ckey"]
					payout_char_name = leader["char_name"]
			if(payout_ckey && payout_char_name)
				var/datum/money_account/payout_acc = SSeconomy.get_account_by_ckey_and_name(payout_ckey, payout_char_name)
				if(payout_acc)
					payout_acc.adjust_money(leftover_balance)
				else
					economyCreditOfflineAccount(payout_ckey, payout_char_name, leftover_balance)
				log_and_message_admins("faction '[faction_uid]' ([fname]) disbanded with [leftover_balance] cr remaining -- paid to leader [payout_char_name] ([payout_ckey]).", user)

	// Release every drydock ship this faction owned -- leaves any personal
	// ownership on the same ship untouched, only clears the faction link.
	for(var/shuttle_id in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[shuttle_id]
		if(!DS || normalize_faction_uid(DS.faction_uid) != faction_uid)
			continue
		DS.faction_uid = null
		var/datum/db_query/ship_q = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET faction_uid = NULL WHERE shuttle_id = :id",
			list("id" = shuttle_id)
		)
		ship_q.Execute()
		databaseCheckQueryResult(ship_q, "removeFactionCompletely ship release")
		qdel(ship_q)

	// Faction beacons need their own full release (security tier grants,
	// persistence save flag, site pin, swept-object release) -- the generic
	// faction_tagger_set(null) release below only clears faction_uid/active.
	for(var/obj/structure/machinery/faction_beacon/B in world)
		if(QDELETED(B) || normalize_faction_uid(B.faction_uid) != faction_uid)
			continue
		if(B.powered)
			B._power_down(user, "faction disbanded")
		B.faction_uid = ""
		B.update_icon()

	// Generic release for everything else the faction tagger can configure
	// (airlocks, turrets, cargo/security telepads, cryopods, autodoc,
	// telecomms, modular computers, clothing) -- declarative, so any type
	// that adopts the tagger hook in the future is automatically covered
	// too, same reasoning as persistence_faction_tagger.dm's own header.
	for(var/atom/movable/AM in world)
		if(istype(AM, /obj/structure/machinery/faction_beacon))
			continue // already fully released above
		if(!AM.faction_tagger_compatible())
			continue
		if(normalize_faction_uid(AM.faction_tagger_get_uid()) != faction_uid)
			continue
		AM.faction_tagger_set(null, user)

	// CASCADE in DB handles faction_accounts and faction_jobs via foreign key
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_factions WHERE uid = :uid",
		list("uid" = faction_uid)
	)
	q.Execute()
	databaseCheckQueryResult(q, "removeFactionCompletely delete")
	qdel(q)

	// Remove from in-memory caches
	GLOB.persistence_faction_cache      -= faction_uid
	GLOB.persistence_faction_jobs_cache -= faction_uid

#ifdef FACTION_ALLIANCES
	// No FK cascade on the alliance tables (they're not tied to
	// ss13_factions specifically) -- clean up manually so a removed faction
	// doesn't leave dangling entries other factions still reference.
	var/datum/db_query/alliance_del_q = SSdbcore.NewQuery(
		"DELETE FROM ss13_faction_alliances WHERE faction_a = :uid OR faction_b = :uid",
		list("uid" = faction_uid)
	)
	alliance_del_q.Execute()
	databaseCheckQueryResult(alliance_del_q, "removeFactionCompletely alliances")
	qdel(alliance_del_q)
	var/datum/db_query/alliance_req_del_q = SSdbcore.NewQuery(
		"DELETE FROM ss13_faction_alliance_requests WHERE proposer_uid = :uid OR target_uid = :uid",
		list("uid" = faction_uid)
	)
	alliance_req_del_q.Execute()
	databaseCheckQueryResult(alliance_req_del_q, "removeFactionCompletely alliance requests")
	qdel(alliance_req_del_q)
	if(islist(GLOB.persistence_faction_alliances[faction_uid]))
		for(var/other_uid in GLOB.persistence_faction_alliances[faction_uid].Copy())
			_uncache_faction_alliance(faction_uid, other_uid)
	GLOB.persistence_faction_alliances -= faction_uid
	if(islist(GLOB.persistence_faction_alliance_requests))
		for(var/i = length(GLOB.persistence_faction_alliance_requests); i >= 1; i--)
			var/list/req = GLOB.persistence_faction_alliance_requests[i]
			if(req["proposer"] == faction_uid || req["target"] == faction_uid)
				GLOB.persistence_faction_alliance_requests.Cut(i, i + 1)
#endif //FACTION_ALLIANCES

	// Revoke this faction's bearer master card, if it has one -- same
	// revoke-by-scan idiom dispense_faction_id uses for superseded personal
	// IDs (card.dm)
	for(var/obj/item/card/id/faction_master/old_master in world)
		if(!old_master.revoked && normalize_faction_uid(old_master.employer_faction) == faction_uid)
			old_master.revoked = TRUE
			old_master.access = list()
			old_master.update_name()

	log_and_message_admins("removed faction '[faction_uid]' ([fname])[user ? "" : " -- stock exchange bankruptcy, faction dissolved"]", user)
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

