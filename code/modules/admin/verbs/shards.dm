// Local game-server shards -- see docs/cross_server_persistence.md and
// code/_compile_options.dm's ALLOW_CENTRAL_SHARD_SPAWNING doc comment. Everything
// in this file is compiled out entirely unless that define is set.
#ifdef ALLOW_CENTRAL_SHARD_SPAWNING

/// Extends /datum/configuration's var block from here rather than
/// configuration.dm -- keeps everything shard-related self-contained in
/// this one ifdef'd file. The load() parse case still has to live in
/// configuration.dm itself (a proc body can't be split across files the
/// way a var block can) -- ifdef-wrapped there too, see that file.
/datum/configuration
	/// Population threshold for optional automatic shard spawning
	/// (statistics.dm fire()). 0 = automatic spawning off -- the admin
	/// panel is still always available regardless of this value. Off by
	/// default even when ALLOW_CENTRAL_SHARD_SPAWNING is compiled in AND
	/// central_sql_enabled is on -- three independent gates (compile-time,
	/// central_sql_enabled, this) before anything spawns on its own.
	var/auto_central_shard_population_threshold = 0

/// Minimum real time between automatic shard spawns -- without this,
/// population staying above the threshold for a while would spawn a new
/// shard on every single statistics fire() tick (every minute).
#define AUTO_SHARD_SPAWN_COOLDOWN (30 MINUTES)
GLOBAL_VAR_INIT(last_auto_shard_spawn_time, 0)

/// Most recent successful shard creation -- surfaced by get_serverstatus
/// (server_query.dm) as shard_advert_id/shard_advert_shard_id/
/// shard_advert_port/shard_advert_host, mirroring persistence_advertise.dm's
/// GLOB.advert_* exactly, so scripts/discord_status_bot.py can relay it to
/// the milestone channel the same way it already relays "Advertise to
/// Players". No expiry (unlike GLOB.advert_expires_at) -- "a shard exists
/// and is joinable" stays true and worth posting even if the bot was
/// offline when it happened, unlike a time-sensitive "come play now" ping.
/// Dedup happens bot-side (it remembers the last shard_advert_id it
/// posted), not here.
GLOBAL_VAR_INIT(shard_advert_id, "")
GLOBAL_VAR_INIT(shard_advert_shard_id, "")
GLOBAL_VAR_INIT(shard_advert_port, 0)

/// Shards currently advertised to arriving lobby clients -- list of
/// list("advert_id"=, "shard_id"=, "port"=). Unlike shard_advert_id above
/// (single most-recent value, consumed by the Discord bot with its own
/// dedup), every entry here needs to persist and be shown to EVERY client
/// that reaches the lobby after it was added, not just whoever happened
/// to already be there -- see the catch-up loop in LateLogin()
/// (mob/abstract/new_player/login.dm). Entries are removed when their
/// shard is permanently removed (verb == "remove" below) so a dead join
/// link is never advertised to a new arrival.
GLOBAL_LIST_EMPTY(active_shard_adverts)

/// Per-connection dedup for active_shard_adverts above -- lives on
/// /client, not the new_player mob, same reasoning as
/// welcomed_this_connection (login.dm): survives a mob returning to
/// character select mid-connection (cryo, prison force-store, failed
/// spawn), so a client already shown an advert isn't shown it again every
/// time they cycle back through the lobby.
/client/var/list/seen_shard_adverts = list()

/// Shared by the immediate broadcast (verb == "add" below) and the
/// lobby-entry catch-up (LateLogin(), login.dm), so the two can never
/// drift out of sync.
/proc/_shard_join_advert_message(shard_id, port)
	return FONT_LARGE(SPAN_NOTICE("A new shard is available: <a href='byond://[world.internet_address || world.address]:[port]'>[shard_id] (click to join)</a>"))

/// Most recent start/stop -- separate from shard_advert_* above (that's
/// the one-time "a shard now exists, here's how to join" post; this is a
/// lifecycle ping for an already-known shard). Same no-expiry/bot-side-dedup
/// reasoning as shard_advert_id's own doc comment.
GLOBAL_VAR_INIT(shard_lifecycle_id, "")
GLOBAL_VAR_INIT(shard_lifecycle_shard_id, "")
GLOBAL_VAR_INIT(shard_lifecycle_event, "") // "started" or "stopped"

/// Checked from SSstatistics.fire() -- see that proc's own call site for
/// why this lives here rather than there (keeps every shard-specific
/// piece in this one ifdef'd file). Auto-generates a shard id and port
/// rather than asking anyone, since nobody's present to ask.
/proc/_check_auto_shard_spawn()
	if(!GLOB.config.central_sql_enabled)
		return
	if(!GLOB.config.auto_central_shard_population_threshold)
		return
	if(world.time < GLOB.last_auto_shard_spawn_time + AUTO_SHARD_SPAWN_COOLDOWN)
		return
	if(GLOB.clients.len < GLOB.config.auto_central_shard_population_threshold)
		return

	GLOB.last_auto_shard_spawn_time = world.time

	var/shard_id = "auto-[time2text(world.realtime, "YYYYMMDD-hhmmss")]"
	var/port = _next_free_shard_port()

	message_admins(SPAN_NOTICE("Population ([GLOB.clients.len]) crossed the auto-shard threshold ([GLOB.config.auto_central_shard_population_threshold]) -- spawning shard '[shard_id]' on port [port] automatically."))
	_run_shard_script(null, "add", shard_id, "-Port [port]", "--port [port]", "Auto-spawning shard '[shard_id]' on port [port]...")

/// MAX(port) + 1 across every registered shard, or a fixed starting point
/// if none exist yet -- simple, avoids needing a separate "next port"
/// counter to keep in sync with ss13_shards. Not perfectly race-safe
/// against a second server picking the same port at the exact same
/// moment, same as any other "read max, add one" scheme -- acceptable
/// here since db_central_add_shard.*'s own uniqueness check (a real
/// UNIQUE KEY on port) still refuses a genuine collision outright rather
/// than corrupting anything.
/proc/_next_free_shard_port()
	var/static/default_start_port = 27500
	if(!SSpersistence.centralDatabaseReachable())
		return default_start_port
	var/datum/db_query/q = SScentraldb.NewQuery("SELECT MAX(port) FROM `ss13_shards`")
	q.Execute()
	var/highest = null
	if(q.NextRow())
		highest = text2num(q.item[1])
	qdel(q)
	return highest ? highest + 1 : default_start_port

/datum/admins/proc/open_shard_panel()
	set name = "Manage Shards"
	set category = "Persistence.Misc"
	set desc = "Create, start, stop, or remove local game-server shards sharing this server's central database."

	if(!check_rights(R_SERVER))
		return
	if(!GLOB.config.central_sql_enabled)
		to_chat(usr, SPAN_WARNING("Shards only make sense on a server that's part of a central database group -- CENTRAL_SQL_ENABLED is off on this server."))
		return

	var/static/datum/tgui_module/admin/shard_panel/global_shard_panel = new()
	global_shard_panel.ui_interact(usr)

/datum/tgui_module/admin/shard_panel

/datum/tgui_module/admin/shard_panel/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShardPanel", "Manage Shards", 640, 480)
		ui.open()

/datum/tgui_module/admin/shard_panel/ui_data(mob/user)
	var/list/data = list()
	data["shards"] = list()
	data["auto_threshold"] = GLOB.config.auto_central_shard_population_threshold

	if(!GLOB.config.central_sql_enabled)
		data["central_unreachable"] = TRUE
		return data

	// centralDatabaseReachable() (persistence_cryo.dm) -- not
	// databaseCheckCentralConnection(), which is PRIVATE_PROC(TRUE) and
	// only callable from within SSpersistence itself.
	if(!SSpersistence.centralDatabaseReachable())
		data["central_unreachable"] = TRUE
		return data

	var/datum/db_query/q = SScentraldb.NewQuery(
		"SELECT shard_id, port, status, created_at, started_at FROM `ss13_shards` ORDER BY shard_id")
	q.Execute()
	while(q.NextRow())
		data["shards"] += list(list(
			"shard_id" = q.item[1],
			"port" = q.item[2],
			"status" = q.item[3],
			"created_at" = q.item[4],
			"started_at" = q.item[5] || "",
		))
	qdel(q)

	return data

/datum/tgui_module/admin/shard_panel/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(!check_rights(R_SERVER))
		return
	// Backstop, matching the verb's own gate -- the panel shouldn't
	// normally even be open if this is off, but ui_act() can in principle
	// be reached directly, same reasoning as every other "don't trust the
	// disabled button alone" gate added this session.
	if(!GLOB.config.central_sql_enabled)
		to_chat(usr, SPAN_WARNING("CENTRAL_SQL_ENABLED is off on this server -- shard actions are unavailable."))
		return

	switch(action)
		if("create")
			var/shard_id = params["shard_id"]
			var/port = text2num(params["port"])
			if(!shard_id || !_shard_id_valid(shard_id))
				to_chat(usr, SPAN_WARNING("Shard id must be letters, digits, hyphens, or underscores only."))
				return TRUE
			if(!port || port < 1024 || port > 65535)
				to_chat(usr, SPAN_WARNING("Port must be between 1024 and 65535."))
				return TRUE
			_run_shard_script(usr, "add", shard_id, "-Port [port]", "--port [port]", "Creating shard '[shard_id]' -- this can take a while the first time (image build).")
			. = TRUE

		if("start")
			var/shard_id = params["shard_id"]
			if(!shard_id || !_shard_id_valid(shard_id))
				return TRUE
			_run_shard_script(usr, "start", shard_id, "", "", "Starting shard '[shard_id]'...")
			. = TRUE

		if("stop")
			var/shard_id = params["shard_id"]
			if(!shard_id || !_shard_id_valid(shard_id))
				return TRUE
			_run_shard_script(usr, "stop", shard_id, "", "", "Stopping shard '[shard_id]'...")
			. = TRUE

		if("remove")
			var/shard_id = params["shard_id"]
			if(!shard_id || !_shard_id_valid(shard_id))
				return TRUE
			// -Force/--force -- this call has no human present to answer the
			// scripts' own interactive confirmation prompt, so the TGUI's own
			// confirm (frontend-side, before this action even fires) is the
			// only confirmation that happens for this path.
			_run_shard_script(usr, "remove", shard_id, "-Force", "--force", "Removing shard '[shard_id]'...")
			. = TRUE

/proc/_shard_id_valid(shard_id)
	if(!length(shard_id))
		return FALSE
	var/static/regex/disallowed_chars = regex(@"[^A-Za-z0-9_-]")
	return !disallowed_chars.Find(shard_id)

/**
 * Shells out to scripts/central/db_central_<verb>_shard.ps1/.sh -- same
 * Trusted-security-level gate every other world.shelleo() call site in
 * this codebase already requires (trigger_deployment_sync(), deploy.dm;
 * _autoBackupSecurityOK(), persistence_backups.dm). Async (set waitfor =
 * FALSE) so the blocking shelleo() call doesn't freeze the whole world --
 * unlike deploy.dm's own background+log-poll approach, this doesn't need
 * a separate detached process: shelleo() already returns full stdout/
 * stderr synchronously once the script finishes, and this proc itself
 * runs off the main thread of execution, not the world's.
 *
 * user is null for the automatic-spawn path (_check_auto_shard_spawn())
 * -- same triggered_by-nullable pattern trigger_deployment_sync() already
 * uses, reporting via message_admins()/to_world() instead of to_chat() in
 * that case.
 */
/proc/_run_shard_script(mob/user, verb, shard_id, ps1_extra_args, sh_extra_args, busy_message)
	set waitfor = FALSE

	var/current_security = world.TgsSecurityLevel()
	if(!isnull(current_security) && current_security != TGS_SECURITY_TRUSTED)
		var/security_msg = "can't run while this server's security level is Safe/Ultrasafe -- it shells out to Docker, which BYOND blocks under anything but Trusted. Set the server's security level to Trusted first."
		if(user)
			to_chat(user, SPAN_WARNING("Shard management [security_msg]"))
		else
			message_admins(SPAN_WARNING("Automatic shard spawn [security_msg]"))
		return

	if(user)
		to_chat(user, SPAN_NOTICE(busy_message))

	var/command
	if(world.system_type == UNIX)
		command = "sh scripts/central/db_central_[verb]_shard.sh --shard-id [shard_id] [sh_extra_args]"
	else
		command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"scripts\\central\\db_central_[verb]_shard.ps1\" -ShardId [shard_id] [ps1_extra_args]"
	command = prefix_server_root_cd(command)

	var/list/result = world.shelleo(command)
	var/errorcode = result[1]
	var/output = result[2]

	if(errorcode != 0)
		if(user)
			to_chat(user, SPAN_WARNING("Shard [verb] for '[shard_id]' failed (exit [errorcode]):"))
			to_chat(user, output)
		else
			message_admins(SPAN_WARNING("Automatic shard [verb] for '[shard_id]' failed (exit [errorcode]): [output]"))
		return

	if(user)
		to_chat(user, SPAN_GOOD("Shard [verb] for '[shard_id]' finished:"))
		to_chat(user, output)
		log_and_message_admins("ran shard [verb] on '[shard_id]' ([key_name(user)]).")
	else
		message_admins(SPAN_GOOD("Automatic shard [verb] for '[shard_id]' finished."))
		log_admin("EVENT automatic shard [verb] for '[shard_id]' finished.")

	if(verb == "add")
		var/port = 0
		for(var/line in splittext(output, "\n"))
			if(findtext(line, "is up on port"))
				var/list/parts = splittext(line, "port")
				if(length(parts) >= 2)
					port = text2num(trim(parts[2]))
				break
		if(port)
			GLOB.shard_advert_id = "[shard_id]-[world.time]"
			GLOB.shard_advert_shard_id = shard_id
			GLOB.shard_advert_port = port

			// Clickable join link for this shard -- confirmed with the user
			// this belongs in a chat announcement, not Discord (that's
			// handled separately via shard_advert_* above and
			// get_serverstatus/discord_status_bot.py). Same
			// <a href='byond://...'> convention used pervasively elsewhere
			// in this codebase, just pointed at a host:port instead of a
			// topic callback.
			//
			// A byond:// link is pure client-side navigation -- this server
			// has no way to "refuse" a click once it fires, that's outside
			// server control entirely. What IS controllable is who sees the
			// prompt in the first place: only clients currently in the
			// lobby (no active character here), so a player mid-round on
			// THIS server isn't tempted to abandon their body to hop
			// shards. Once they DO click through, the shard's own
			// character-select is what actually enforces "cryo'd" per
			// character -- the presence lock (presenceLockAcquire(),
			// persistence_cryo.dm) already refuses to spawn a character
			// that's still active on this server, since a shard shares the
			// same central database and always has CENTRAL_SQL_ENABLED on.
			// GLOB.shard_advert_id was just set to this exact string one
			// line ago (same event) -- reused here rather than recomputed,
			// so the two can never drift apart.
			GLOB.active_shard_adverts += list(list("advert_id" = GLOB.shard_advert_id, "shard_id" = shard_id, "port" = port))

			var/join_msg = _shard_join_advert_message(shard_id, port)
			for(var/client/C in GLOB.clients)
				if(istype(C.mob, /mob/abstract/new_player))
					// Marked seen immediately -- otherwise this same client
					// would see it a second time the next time their
					// new_player mob is recreated (LateLogin()'s own
					// catch-up loop, login.dm).
					C.seen_shard_adverts += GLOB.shard_advert_id
					to_chat(C, join_msg)

	if(verb == "start" || verb == "stop")
		// Separate from the "add" advert above -- this is a lifecycle ping
		// for a shard that already exists, relayed to Discord's milestone
		// channel by discord_status_bot.py's post_shard_lifecycle().
		GLOB.shard_lifecycle_id = "[shard_id]-[verb]-[world.time]"
		GLOB.shard_lifecycle_shard_id = shard_id
		GLOB.shard_lifecycle_event = (verb == "start") ? "started" : "stopped"

	if(verb == "remove")
		// The shard is permanently gone -- stop advertising it to any
		// future lobby arrival. shard_id is unique per ss13_shards row
		// (enforced at creation, db_central_add_shard.ps1), so at most one
		// entry ever matches.
		for(var/list/advert in GLOB.active_shard_adverts)
			if(advert["shard_id"] == shard_id)
				GLOB.active_shard_adverts -= list(advert)
				break

#endif
