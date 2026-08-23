/*
 * Central ban list -- see docs/cross_server_persistence.md. A ban applied
 * on any central_sql_enabled server refuses a connection on every other
 * server sharing the same central database. Layered additively on top of
 * world/IsBanned()'s existing local checks (IsBanned.dm) -- never a
 * replacement for them, and deliberately fail-OPEN when central is
 * unreachable (the opposite of central admin auth's fail-closed): refusing
 * every connection during a brief central DB blip would be worse than the
 * narrow risk of a ban check being skipped for that window, and the local
 * ban list is still fully in effect either way.
 *
 * Structurally modeled on load_admins_from_central_database() (auth.dm) --
 * a full cache reload, not an incremental diff, so an edited or lifted
 * central ban is picked up here exactly the same way a new one is.
 */

/// ckey -> list("reason", "banning_admin", "banned_at", "expires_at") for
/// every currently-active, unexpired central ban. Rebuilt wholesale by
/// load_central_bans() -- never written to directly anywhere else.
GLOBAL_LIST_EMPTY(central_ban_cache)

/// Loads every active, unexpired ban from ss13_central_bans into
/// GLOB.central_ban_cache. Called at boot (SSauth.Initialize()),
/// periodically (SSauth.fire()), and on demand ("Reload Central Bans"
/// verb below). A connection failure leaves the previous cache contents in
/// place rather than clearing them -- losing an already-cached ban list
/// because of a transient DB blip would silently let banned players back
/// in, exactly the outcome the fail-open design elsewhere in this file is
/// trying to avoid causing.
/datum/controller/subsystem/auth/proc/load_central_bans()
	if(!GLOB.config.central_sql_enabled)
		GLOB.central_ban_cache = list()
		return
	if(!SScentraldb.Connect())
		log_world("WARNING: Central ban list: could not connect to the central database -- keeping the previously-loaded list, if any.")
		return

	var/datum/db_query/query = SScentraldb.NewQuery(
		"SELECT ckey, reason, banning_admin, banned_at, expires_at FROM `ss13_central_bans` WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW())"
	)
	query.Execute()

	var/list/fresh_cache = list()
	var/loaded = 0
	while(query.NextRow())
		var/ban_ckey = ckey(query.item[1])
		fresh_cache[ban_ckey] = list(
			"reason"        = query.item[2],
			"banning_admin" = query.item[3],
			"banned_at"     = query.item[4],
			"expires_at"    = query.item[5]
		)
		loaded++
	qdel(query)

	GLOB.central_ban_cache = fresh_cache
	log_world("Central ban list: loaded [loaded] active ban(s).")

/// Returns the cached ban entry for this ckey, or null if not centrally
/// banned. Pure cache read -- world/IsBanned() (IsBanned.dm) is on the hot
/// connection path and must never block on a live query; GLOB.central_ban_cache
/// (kept current by load_central_bans() above) is the only thing it reads.
/proc/get_central_ban(ckey)
	if(!islist(GLOB.central_ban_cache))
		return null
	return GLOB.central_ban_cache[ckey(ckey)]

/// Writes a central ban row -- called from DB_ban_record() (DB ban/functions.dm)
/// alongside its existing local ss13_ban INSERT, only for full-connection
/// ban types (PERMABAN/TEMPBAN, never the JOB_* variants, which only
/// restrict a role -- not something "refuse this connection everywhere"
/// should ever apply to). Non-fatal on failure -- the local ban this
/// always runs alongside already succeeded. duration_minutes <= 0 means
/// permanent, matching DB_ban_record()'s own convention (duration = -1
/// for a permaban); the actual NOW()+INTERVAL math happens in SQL, not
/// DM, same reasoning as every other expiry computation in this codebase.
/proc/apply_central_ban(ckey, reason, banning_admin, duration_minutes = 0)
	if(!GLOB.config.central_sql_enabled || !ckey)
		return
	if(!SScentraldb.Connect())
		log_world("WARNING: Central ban: could not connect to the central database -- ban for [ckey] applied locally only.")
		return

	var/datum/db_query/q
	if(duration_minutes > 0)
		q = SScentraldb.NewQuery(
			"INSERT INTO `ss13_central_bans` (ckey, reason, banning_admin, expires_at) VALUES (:ckey, :reason, :banning_admin, DATE_ADD(NOW(), INTERVAL :minutes MINUTE))",
			list("ckey" = ckey(ckey), "reason" = reason, "banning_admin" = banning_admin, "minutes" = duration_minutes)
		)
	else
		q = SScentraldb.NewQuery(
			"INSERT INTO `ss13_central_bans` (ckey, reason, banning_admin, expires_at) VALUES (:ckey, :reason, :banning_admin, NULL)",
			list("ckey" = ckey(ckey), "reason" = reason, "banning_admin" = banning_admin)
		)
	q.Execute()
	qdel(q)

	// Refresh immediately so THIS server's own next connection check (and
	// any admin looking at the list right now) sees it without waiting for
	// the next periodic cycle -- other servers still only pick it up on
	// their own next cycle or manual reload, same as any poll-based design.
	SSauth.load_central_bans()

/client/proc/reload_central_bans()
	set name = "Reload Central Bans"
	set category = "Debug"

	if(!check_rights(R_SERVER|R_DEV))
		return

	if(!GLOB.config.central_sql_enabled)
		to_chat(usr, SPAN_WARNING("central_sql_enabled is off on this server -- there's no central ban list to reload."))
		return

	SSauth.load_central_bans()
	log_and_message_admins("manually reloaded the central ban list.")
