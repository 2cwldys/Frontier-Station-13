/*
 * Central Database -- the SECOND database connection, shared across every
 * server authorized against one central instance. Carries characters,
 * money, factions, and ship schematics; SSdbcore (dbcore.dm) stays the
 * LOCAL, per-server connection for everything else (worldstate, turfs,
 * atmos, floor items).
 *
 * Deliberately a genuine DM subtype of /datum/controller/subsystem/dbcore,
 * not a parallel reimplementation. dbcore.dm's query lifecycle (fire(),
 * the active/standby queues, timeout handling, async job polling) is
 * already fully instance-scoped -- every var it touches (connection,
 * all_queries, queries_active, ...) is a plain per-instance var, not a
 * static shared one -- so a second instance of the SAME type gets its own
 * completely independent copy of all of it for free, with zero duplicated
 * logic and zero risk of the two connections' query bookkeeping crossing
 * wires.
 *
 * The one piece that needed an actual code change (in dbcore.dm itself,
 * not here) is /datum/db_query: several of its procs used to hardcode the
 * literal global "SSdbcore" rather than reading it from whichever
 * subsystem instance actually owns the query. That's now a var (`owner`,
 * set by NewQuery() to src, defaulting to SSdbcore for every existing
 * caller that never knew this connection existed) -- see dbcore.dm's own
 * comment on that var for the full reasoning. Everything below just relies
 * on that being correct.
 *
 * Only the things that genuinely need to differ from SSdbcore are
 * overridden: which config file to read, which config flag gates whether
 * to connect at all, and Recover()/Shutdown(), which hardcode "SSdbcore" in
 * the base class for the exact same reason db_query used to.
 *
 * NOT declared via SUBSYSTEM_DEF(centraldb) -- that macro can only anchor a
 * new type directly under /datum/controller/subsystem/, and has no way to
 * express "subtype of dbcore". The block below is that macro's expansion,
 * hand-written against /datum/controller/subsystem/dbcore/central instead.
 * Master's subsystem collection (subtypesof(/datum/controller/subsystem))
 * walks the whole hierarchy, not just direct children, so this is picked
 * up and instantiated exactly like any other subsystem despite not using
 * the macro.
 */

GLOBAL_REAL(SScentraldb, /datum/controller/subsystem/dbcore/central)
/datum/controller/subsystem/dbcore/central/New()
	NEW_SS_GLOBAL(SScentraldb)
	PreInit()

/datum/controller/subsystem/dbcore/central
	name = "Central Database"
	// Same priority/ordering as SSdbcore -- ties in sortTim are stable/harmless,
	// and this needs to be connected before persistence's own Initialize()
	// could plausibly touch a central-backed table.
	init_order = INIT_ORDER_DBCORE
	init_stage = INITSTAGE_FIRST
	priority = FIRE_PRIORITY_DATABASE

/// Same shape as the base GetDBConfig(), pointed at a separate credentials
/// file (config/central_dbconfig.txt) so the shared central login is never
/// mixed up with, or accidentally committed alongside, this server's own
/// local DB credentials.
/datum/controller/subsystem/dbcore/central/GetDBConfig()
	var/list/data = list(
		"address" = "localhost",
		"port" = "3306",
		"database" = "aurora_central",
		"login",
		"password",
		"query_timeout_async" = "10",
		"query_timeout_blocking" = "5",
		"min_sql_connections" = "1",
		"max_sql_connections" = "25",
		"max_concurrent_queries" = "25"
	)

	var/list/Lines = file2list("config/central_dbconfig.txt")
	if(!Lines)
		return new /DBConnection()

	for(var/t in Lines)
		if(!t)
			continue
		t = trim(t)
		if(length(t) == 0)
			continue
		else if(copytext(t, 1, 2) == "#")
			continue

		var/pos = findtext(t, " ")
		var/name = lowertext(copytext(t, 1, pos))
		var/value = copytext(t, pos + 1)
		if(!name)
			continue

		if(name in data)
			data[name] = value
		else
			log_subsystem_dbcore("Unknown setting while setting up central database connection. Filename: 'config/central_dbconfig.txt', value: '[value]'.")

	return data

/// Identical to the base Connect() except for the enable-flag it checks --
/// central_sql_enabled, not sql_enabled, so a server can run its normal
/// local DB without ever attempting a central connection at all (the common
/// case: only servers deliberately authorized against a shared central
/// instance should set central_sql_enabled). Everything else -- backoff on
/// repeated failures, connection pooling via rustg -- is identical to the
/// base implementation; there was no clean way to share just the enable
/// check without threading an overridable hook through Connect() for a
/// single caller, so this is a full override rather than a speculative
/// generalization of the base.
/datum/controller/subsystem/dbcore/central/Connect()
	if(IsConnected())
		return TRUE

	if(connection)
		Disconnect()
		connection = null

	if(failed_connection_timeout <= world.time)
		failed_connections = 0
		failed_connection_timeout = 0

	if(failed_connection_timeout > 0)
		return FALSE

	if(!GLOB.config.central_sql_enabled)
		return FALSE

	var/list/dbconfig = GetDBConfig()

	var/user = dbconfig["login"]
	var/pass = dbconfig["password"]
	var/db = dbconfig["database"]
	var/address = dbconfig["address"]
	var/port = text2num(dbconfig["port"])
	var/timeout = max(text2num(dbconfig["query_timeout_async"]), text2num(dbconfig["query_timeout_blocking"]))
	var/min_sql_connections = text2num(dbconfig["min_sql_connections"])
	var/max_sql_connections = text2num(dbconfig["max_sql_connections"])

	var/result = json_decode(rustg_sql_connect_pool(json_encode(list(
		"host" = address,
		"port" = port,
		"user" = user,
		"pass" = pass,
		"db_name" = db,
		"read_timeout" = timeout,
		"write_timeout" = timeout,
		"min_threads" = min_sql_connections,
		"max_threads" = max_sql_connections,
	))))
	. = (result["status"] == "ok")
	if(.)
		connection = result["handle"]
	else
		connection = null
		last_error = result["data"]
		log_subsystem_dbcore("Central Connect() failed | [last_error]")
		++failed_connections
		if(failed_connections > max_connection_failures)
			failed_connection_timeout_count++
			failed_connection_timeout = world.time + ((2 ** failed_connection_timeout_count) SECONDS)

/// Same central_sql_enabled distinction as Connect() above.
/datum/controller/subsystem/dbcore/central/IsConnected()
	PRIVATE_PROC(TRUE)
	if(!GLOB.config.central_sql_enabled)
		return FALSE
	if(!connection)
		return FALSE
	return json_decode(rustg_sql_connected(connection))["status"] == "online"

/// Base version hardcodes "connection = SSdbcore.connection" -- that would
/// pull the LOCAL connection's handle into this subsystem on a world
/// recover, not this subsystem's own previous handle. Same fix shape as the
/// db_query owner var: read from this subsystem's own global, not the
/// unrelated one that happens to share the base type.
/datum/controller/subsystem/dbcore/central/Recover()
	connection = SScentraldb.connection

/// Base version hardcodes "SSdbcore.Connect()" while finishing off
/// in-flight queries during shutdown -- same issue as Recover() above, and
/// for the same reason needs its own copy rather than being safely
/// inheritable.
/datum/controller/subsystem/dbcore/central/Shutdown()
	shutting_down = TRUE
	var/msg = "Clearing Central DB queries standby:[length(queries_standby)] active: [length(queries_active)] all: [length(all_queries)]"
	log_subsystem_dbcore(msg)
	// Not SHUTDOWN_QUERY_TIMELIMIT -- that #define is deliberately scoped to
	// dbcore.dm alone (defined and #undef'd within that one file), so it
	// can't be referenced here regardless of include order. Same value,
	// inlined, rather than widening that macro's scope for one caller.
	var/endtime = REALTIMEOFDAY + (1 MINUTES)
	if(Connect())
		var/queries_to_check = queries_active.Copy()
		queries_active.Cut()

		for(var/datum/db_query/query in queries_standby)
			run_query(query)
			queries_to_check += query
			queries_standby -= query

		for(var/datum/db_query/query in queries_to_check)
			UNTIL(query.process() || REALTIMEOFDAY > endtime)

	msg = "Done clearing Central DB queries standby:[length(queries_standby)] active: [length(queries_active)] all: [length(all_queries)]"
	log_subsystem_dbcore(msg)
	if(IsConnected())
		Disconnect()
