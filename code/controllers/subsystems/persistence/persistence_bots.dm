/*
 * Persistence - Bots
 * Saves and restores player-built bots (/mob/living/bot: cleanbot, medbot,
 * farmbot) across rounds: type, position, name, on/locked/emagged state.
 * Deep per-bot config (medbot thresholds etc) is not persisted yet.
 *
 * Pattern mirrors persistence_floor_items.dm: DELETE-by-map_path + bulk
 * INSERT at save, wipe-and-recreate at boot.
 */

/**
 * Restore saved bots for the current map.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/botsInitialize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("botsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, z, dir, name, is_on, locked, emagged, extra FROM ss13_persistent_bots WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "botsInitialize"))
		qdel(query)
		return

	var/list/rows = list()
	while(query.NextRow())
		rows += list(list(
			"type"    = query.item[1],
			"x"       = text2num(query.item[2]),
			"y"       = text2num(query.item[3]),
			"z"       = text2num(query.item[4]),
			"dir"     = text2num(query.item[5]),
			"name"    = query.item[6],
			"is_on"   = text2num(query.item[7]),
			"locked"  = text2num(query.item[8]),
			"emagged" = text2num(query.item[9]),
			"extra"   = query.item[10]
		))
	qdel(query)

	// Wipe map-placed bots on persistent z-levels first -- the DB is
	// authoritative for the persistent world (same policy as floor items).
	var/wiped = 0
	for(var/mob/living/bot/B in world)
		if(!B.z || persistence_z_excluded(B.z))
			continue
		qdel(B)
		wiped++

	var/restored = 0
	var/skipped = 0
	for(var/list/data in rows)
		if(_botsRestoreRow(data))
			restored++
		else
			skipped++

	log_subsystem_persistence_info("Bots: Restored [restored] bot(s)[skipped ? ", skipped [skipped]" : ""][wiped ? ", wiped [wiped] stale" : ""].")

/**
 * Restore one saved bot row. Returns 1 on success, 0 on skip/failure.
 * Shared by botsInitialize() and the per-ship-Z apply (botsApplyZ()).
 */
/datum/controller/subsystem/persistence/proc/_botsRestoreRow(list/data)
	PRIVATE_PROC(TRUE)
	try
		var/bz = data["z"]
		if(bz < 1 || bz > world.maxz)
			return 0
		var/path = text2path(data["type"])
		if(!path || !ispath(path, /mob/living/bot))
			return 0
		var/turf/T = locate(data["x"], data["y"], bz)
		if(!T)
			return 0
		var/mob/living/bot/B = new path(T)
		if(data["dir"])
			B.set_dir(data["dir"])
		if(data["name"])
			B.name = data["name"]
		B.locked  = data["locked"] ? TRUE : FALSE
		B.emagged = data["emagged"] || 0
		// Restore per-bot appearance quirks (e.g. medbot's randomly-rolled
		// first-aid kit) so the sprite stays consistent across saves.
		if(data["extra"] && istype(B, /mob/living/bot/medbot))
			var/list/extra = json_decode(data["extra"])
			if(islist(extra) && extra["firstaid"])
				var/kit_path = text2path(extra["firstaid"])
				if(kit_path && ispath(kit_path, /obj/item/storage/firstaid))
					var/mob/living/bot/medbot/MB = B
					if(MB.firstaid_item)
						qdel(MB.firstaid_item)
					MB.firstaid_item = new kit_path(MB)
					MB.underlays.Cut()
					MB.update_icon()
		if(data["is_on"])
			B.turn_on()
		else
			B.turn_off()
		return 1
	catch(var/exception/e)
		log_subsystem_persistence_error("Bots: failed to restore a saved bot: [e]")
		return 0

/**
 * Apply saved ship-scoped bots to a freshly loaded ship Z. Rows were already
 * remapped to this z by remapShipRows().
 */
/datum/controller/subsystem/persistence/proc/botsApplyZ(z, scope)
	if(!databaseCheckConnection("botsApplyZ"))
		return
	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, z, dir, name, is_on, locked, emagged, extra FROM ss13_persistent_bots WHERE map_path = :map_path AND z = :z",
		list("map_path" = scope, "z" = z)
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "botsApplyZ"))
		qdel(query)
		return
	var/list/rows = list()
	while(query.NextRow())
		rows += list(list(
			"type"    = query.item[1],
			"x"       = text2num(query.item[2]),
			"y"       = text2num(query.item[3]),
			"z"       = text2num(query.item[4]),
			"dir"     = text2num(query.item[5]),
			"name"    = query.item[6],
			"is_on"   = text2num(query.item[7]),
			"locked"  = text2num(query.item[8]),
			"emagged" = text2num(query.item[9]),
			"extra"   = query.item[10]
		))
	qdel(query)
	var/restored = 0
	for(var/list/data in rows)
		CHECK_TICK
		restored += _botsRestoreRow(data)
	log_subsystem_persistence_info("Bots: Applied [restored] ship bot(s) to z=[z] ([scope]).")

/**
 * Build the bulk-INSERT row string for one bot, keyed under its z's
 * persistence scope. Returns null if the bot should not be saved.
 */
/datum/controller/subsystem/persistence/proc/_botRow(mob/living/bot/B)
	PRIVATE_PROC(TRUE)
	if(!isturf(B.loc) || !B.z || persistence_z_excluded(B.z))
		return null
	var/scope_escaped = replacetext(persistence_scope_for_z(B.z), "'", "''")
	var/name_escaped = replacetext("[B.name]", "'", "''")
	var/extra_sql = "NULL"
	if(istype(B, /mob/living/bot/medbot))
		var/mob/living/bot/medbot/MB = B
		if(MB.firstaid_item)
			var/extra_json = replacetext(json_encode(list("firstaid" = "[MB.firstaid_item.type]")), "'", "''")
			extra_sql = "'[extra_json]'"
	return "('[scope_escaped]', '[B.type]', [B.x], [B.y], [B.z], [B.dir], '[name_escaped]', [B.on ? 1 : 0], [B.locked ? 1 : 0], [B.emagged || 0], [extra_sql])"

/// Chunked bulk INSERT of collected bot rows.
/datum/controller/subsystem/persistence/proc/_botsFlush(list/value_rows, log_context)
	PRIVATE_PROC(TRUE)
	var/saved = length(value_rows)
	if(saved)
		var/chunk_size = 100
		for(var/i = 1 to saved step chunk_size)
			var/end = min(i + chunk_size - 1, saved)
			var/list/chunk = value_rows.Copy(i, end + 1)
			var/datum/db_query/bulk = SSdbcore.NewQuery(
				"INSERT INTO ss13_persistent_bots (map_path, type, x, y, z, dir, name, is_on, locked, emagged, extra) VALUES [chunk.Join(",")]"
			)
			bulk.Execute()
			databaseCheckQueryResult(bulk, "[log_context] bulk insert")
			qdel(bulk)
			CHECK_TICK
	return saved

/**
 * Save all bots on persistent z-levels.
 * Called from SSpersistence.Shutdown() and forceSaveAll().
 */
/datum/controller/subsystem/persistence/proc/botsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("botsFinalize"))
		return

	// Wipe-and-reinsert per scope: current map plus every deployed ship's
	// scope (see persistence_ship_interiors.dm), mirroring floor items.
	var/datum/db_query/delete_old = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_bots WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	delete_old.Execute()
	databaseCheckQueryResult(delete_old, "botsFinalize delete old")
	qdel(delete_old)
	for(var/ship_z in GLOB.persistence_ship_z)
		var/datum/db_query/ship_delete = SSdbcore.NewQuery(
			"DELETE FROM ss13_persistent_bots WHERE map_path = :map_path",
			list("map_path" = GLOB.persistence_ship_z[ship_z])
		)
		ship_delete.Execute()
		databaseCheckQueryResult(ship_delete, "botsFinalize ship scope delete")
		qdel(ship_delete)

	var/list/value_rows = list()
	for(var/mob/living/bot/B in world)
		CHECK_TICK
		var/row = _botRow(B)
		if(row)
			value_rows += row

	var/saved = _botsFlush(value_rows, "botsFinalize")
	log_subsystem_persistence_info("Bots: Saved [saved] bot(s).")

/**
 * Per-Z bot save for a deployed ship Z -- wipe the ship scope's rows, then
 * re-collect bots on that z only.
 */
/datum/controller/subsystem/persistence/proc/botsFinalizeZ(z, scope)
	if(!databaseCheckConnection("botsFinalizeZ"))
		return
	var/datum/db_query/delete_old = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_bots WHERE map_path = :map_path",
		list("map_path" = scope)
	)
	delete_old.Execute()
	databaseCheckQueryResult(delete_old, "botsFinalizeZ delete")
	qdel(delete_old)

	var/list/value_rows = list()
	for(var/mob/living/bot/B in world)
		CHECK_TICK
		if(B.z != z)
			continue
		var/row = _botRow(B)
		if(row)
			value_rows += row

	var/saved = _botsFlush(value_rows, "botsFinalizeZ")
	log_subsystem_persistence_info("Bots: Saved [saved] ship bot(s) for z=[z] ([scope]).")
