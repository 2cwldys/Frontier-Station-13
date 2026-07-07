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
		"SELECT type, x, y, z, dir, name, is_on, locked, emagged FROM ss13_persistent_bots WHERE map_path = :map_path",
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
			"emagged" = text2num(query.item[9])
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
		var/bz = data["z"]
		if(bz < 1 || bz > world.maxz)
			skipped++
			continue
		var/path = text2path(data["type"])
		if(!path || !ispath(path, /mob/living/bot))
			skipped++
			continue
		var/turf/T = locate(data["x"], data["y"], bz)
		if(!T)
			skipped++
			continue
		var/mob/living/bot/B = new path(T)
		if(data["dir"])
			B.set_dir(data["dir"])
		if(data["name"])
			B.name = data["name"]
		B.locked  = data["locked"] ? TRUE : FALSE
		B.emagged = data["emagged"] || 0
		if(data["is_on"])
			B.turn_on()
		else
			B.turn_off()
		restored++

	log_subsystem_persistence_info("Bots: Restored [restored] bot(s)[skipped ? ", skipped [skipped]" : ""][wiped ? ", wiped [wiped] stale" : ""].")

/**
 * Save all bots on persistent z-levels.
 * Called from SSpersistence.Shutdown() and forceSaveAll().
 */
/datum/controller/subsystem/persistence/proc/botsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("botsFinalize"))
		return

	var/datum/db_query/delete_old = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_bots WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	delete_old.Execute()
	databaseCheckQueryResult(delete_old, "botsFinalize delete old")
	qdel(delete_old)

	var/map_path_escaped = replacetext("[SSatlas.current_map.path]", "'", "''")
	var/list/value_rows = list()
	for(var/mob/living/bot/B in world)
		CHECK_TICK
		if(!isturf(B.loc) || !B.z || persistence_z_excluded(B.z))
			continue
		var/name_escaped = replacetext("[B.name]", "'", "''")
		value_rows += "('[map_path_escaped]', '[B.type]', [B.x], [B.y], [B.z], [B.dir], '[name_escaped]', [B.on ? 1 : 0], [B.locked ? 1 : 0], [B.emagged || 0])"

	var/saved = length(value_rows)
	if(saved)
		var/chunk_size = 100
		for(var/i = 1 to saved step chunk_size)
			var/end = min(i + chunk_size - 1, saved)
			var/list/chunk = value_rows.Copy(i, end + 1)
			var/datum/db_query/bulk = SSdbcore.NewQuery(
				"INSERT INTO ss13_persistent_bots (map_path, type, x, y, z, dir, name, is_on, locked, emagged) VALUES [chunk.Join(",")]"
			)
			bulk.Execute()
			databaseCheckQueryResult(bulk, "botsFinalize bulk insert")
			qdel(bulk)
			CHECK_TICK

	log_subsystem_persistence_info("Bots: Saved [saved] bot(s).")
