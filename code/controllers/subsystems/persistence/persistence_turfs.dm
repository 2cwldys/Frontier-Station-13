/*
 * Persistence - Turf Structural Changes
 * Saves and restores turf types and state for turfs that differ from their map default.
 * Covers floor damage/flooring changes and wall construction/material changes.
 *
 * Hooked into SSpersistence Initialize() and Shutdown().
 * Only runs on the SCCV Horizon map.
 */

/// Cached turf data keyed by "[x]|[y]|[z]"
GLOBAL_LIST_EMPTY(persistence_turfs_cache)

/// Set of turfs that have changed since last save — only these need to be written
GLOBAL_LIST_EMPTY(persistence_dirty_turfs)

/turf/simulated
	var/persistence_dirty = FALSE

/turf/simulated/proc/mark_persistence_dirty()
	if(persistence_dirty || !z || !SSatlas.current_map)
		return
	persistence_dirty = TRUE
	GLOB.persistence_dirty_turfs |= src

/**
 * Load saved turf state from the database and apply it to the world.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/turfsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_turfs_cache = list()

	if(!SSatlas.current_map)
		log_subsystem_persistence_info("Turfs: Map is not SCCV Horizon, skipping turf persistence init.")
		return

	if(!databaseCheckConnection("turfsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT x, y, z, turf_type, base_type, content FROM ss13_worldstate_turfs WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "turfsInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/tx = text2num(query.item[1])
		var/ty = text2num(query.item[2])
		var/tz = text2num(query.item[3])
		var/turf_type = text2path(query.item[4])
		var/content_json = query.item[6]

		if(!turf_type)
			continue

		var/turf/T = locate(tx, ty, tz)
		if(!istype(T))
			continue

		var/list/content = json_decode(content_json)
		if(!content)
			continue

		try
			T.ChangeTurf(turf_type)
			turfsApplyContent(T, content)
		catch(var/exception/e)
			log_subsystem_persistence_error("Turfs: Failed to restore turf at ([tx],[ty],[tz]): [e]")
			continue

		loaded++
		CHECK_TICK

	qdel(query)
	log_subsystem_persistence_info("Turfs: Restored [loaded] changed turfs for map [SSatlas.current_map.path].")

/**
 * Apply saved content vars to a turf after type change.
 */
/datum/controller/subsystem/persistence/proc/turfsApplyContent(turf/T, list/content)
	PRIVATE_PROC(TRUE)
	if(istype(T, /turf/simulated/floor))
		var/turf/simulated/floor/F = T
		F.broken = content["broken"]
		F.burnt = content["burnt"]
		if(!isnull(content["color"]))
			F.color = content["color"]
		F.update_icon()

	else if(istype(T, /turf/simulated/wall))
		var/turf/simulated/wall/W = T
		if(content["material"])
			W.material = SSmaterials.get_material_by_name(content["material"])
		if(!isnull(content["reinf_material"]))
			W.reinf_material = SSmaterials.get_material_by_name(content["reinf_material"])
		if(!isnull(content["health"]))
			W.health = text2num(content["health"])
		if(!isnull(content["construction_stage"]))
			W.construction_stage = text2num(content["construction_stage"])
		W.update_icon()

/**
 * Save all structurally changed turfs to the database at round end.
 * Called from SSpersistence.Shutdown().
 */
/datum/controller/subsystem/persistence/proc/turfsFinalize()
	PRIVATE_PROC(TRUE)

	if(!SSatlas.current_map)
		log_subsystem_persistence_info("Turfs: Map is not SCCV Horizon, skipping turf persistence save.")
		return

	if(!databaseCheckConnection("turfsFinalize"))
		return

	// NO bulk DELETE — dirty tracking only saves what changed this session.
	// Previous sessions' turf data stays in the DB untouched.
	// Turfs restored to default are individually deleted; changed ones are upserted.
	var/list/upsert_rows  = list()  // turfs to insert/update
	var/list/delete_coords = list() // turfs restored to default — remove from DB
	var/map_path = "[SSatlas.current_map.path]"
	var/map_escaped = replacetext(map_path, "'", "''")

	for(var/turf/simulated/T in GLOB.persistence_dirty_turfs)
		CHECK_TICK
		T.persistence_dirty = FALSE

		if(istype(T, /turf/simulated/floor))
			var/turf/simulated/floor/F = T
			if(!F.broken && !F.burnt && !F.color && F.type == F.baseturf)
				// Restored to default — remove from DB so it doesn't load unnecessarily
				delete_coords += "([F.x],[F.y],[F.z])"
				continue
			var/content_json = replacetext(json_encode(list("broken"=F.broken,"burnt"=F.burnt,"color"=F.color)), "'", "''")
			var/type_str = replacetext("[F.type]", "'", "''")
			var/base_str = replacetext("[F.baseturf]", "'", "''")
			upsert_rows += "('[map_escaped]',[F.x],[F.y],[F.z],'[type_str]','[base_str]','[content_json]',NOW())"

		else if(istype(T, /turf/simulated/wall))
			var/turf/simulated/wall/W = T
			if(W.type == W.baseturf && W.health >= W.maxhealth)
				delete_coords += "([W.x],[W.y],[W.z])"
				continue
			var/mat_name   = W.material ? replacetext(W.material.name, "'", "''") : null
			var/reinf_name = W.reinf_material ? replacetext(W.reinf_material.name, "'", "''") : null
			var/content_json = "'[replacetext(json_encode(list("material"=mat_name,"reinf_material"=reinf_name,"health"=W.health,"construction_stage"=W.construction_stage)), "'", "''")]'"
			var/type_str = replacetext("[T.type]", "'", "''")
			var/base_str = replacetext("[T.baseturf]", "'", "''")
			upsert_rows += "('[map_escaped]',[T.x],[T.y],[T.z],'[type_str]','[base_str]',[content_json],NOW())"

	GLOB.persistence_dirty_turfs = list()

	// Delete restored-to-default turfs individually
	if(length(delete_coords))
		var/datum/db_query/wipe_defaults = SSdbcore.NewQuery(
			"DELETE FROM ss13_worldstate_turfs WHERE map_path = '[map_escaped]' AND (x,y,z) IN ([delete_coords.Join(",")])"
		)
		wipe_defaults.Execute()
		qdel(wipe_defaults)

	var/saved = length(upsert_rows)
	if(saved)
		var/chunk_size = 200
		for(var/i = 1 to saved step chunk_size)
			var/end = min(i + chunk_size - 1, saved)
			var/list/chunk = upsert_rows.Copy(i, end + 1)
			var/datum/db_query/bulk = SSdbcore.NewQuery(
				"INSERT INTO ss13_worldstate_turfs (map_path,x,y,z,turf_type,base_type,content,saved_at) VALUES [chunk.Join(",")] ON DUPLICATE KEY UPDATE turf_type=VALUES(turf_type),base_type=VALUES(base_type),content=VALUES(content),saved_at=NOW()"
			)
			bulk.Execute()
			databaseCheckQueryResult(bulk, "turfsFinalize bulk insert")
			qdel(bulk)
			CHECK_TICK

	log_subsystem_persistence_info("Turfs: Saved [saved] changed turfs for map [SSatlas.current_map.path].")
