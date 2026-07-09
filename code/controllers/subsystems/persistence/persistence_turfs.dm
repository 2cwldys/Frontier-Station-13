/*
 * Persistence - Turf Structural Changes
 * Saves and restores turf types and state for turfs that differ from their map default.
 * Covers floor damage/flooring changes and wall construction/material changes.
 *
 * Hooked into SSpersistence Initialize() and Shutdown().
 * Save uses a full world scan  no dirty tracking needed.
 */

/// Cached turf data keyed by "[x]|[y]|[z]"
GLOBAL_LIST_EMPTY(persistence_turfs_cache)

/**
 * Load saved turf state from the database and apply it to the world.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/turfsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_turfs_cache = list()

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
		// Rows can reference dynamic z-levels not loaded (yet) this session --
		// the z-trait helpers THROW on unmanaged z, and one bad row used to
		// abort the entire restore. Skip them; the rows stay in the DB.
		if(tz < 1 || tz > world.maxz) continue
		// Turf sweeps use the manual skip list plus mining levels only. Mining
		// z-levels deliberately never save or load turf changes (ore/terrain
		// regenerates from the map each session); away/template-loaded/player
		// levels are player space on this server and must persist.
		if((tz in GLOB.persistence_zlevel_skip) || is_mining_level(tz) || persistence_z_manual_blocked(tz)) continue
		var/turf_type = text2path(query.item[4])
		var/base_type = text2path(query.item[5])  // restored base so next save doesn't see type==baseturf
		var/content_json = query.item[6]

		if(!turf_type)
			continue

		var/turf/T = locate(tx, ty, tz)
		if(!istype(T))
			continue

		try
			var/list/content = json_decode(content_json)
			if(!content)
				continue
			T.ChangeTurf(turf_type)
			// Restore original baseturf so the next turfsFinalize() doesn't treat this
			// as "back to default" (type==baseturf) and delete it from the DB.
			if(base_type)
				T.baseturf = base_type
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
 * Full world scan  compares every simulated floor and wall against its base state.
 * Called from SSpersistence.Shutdown() and forceSaveAll().
 */
/datum/controller/subsystem/persistence/proc/turfsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("turfsFinalize"))
		return

	var/list/upsert_rows   = list()
	var/list/delete_coords = list()
	var/map_path    = "[SSatlas.current_map.path]"
	var/map_escaped = replacetext(map_path, "'", "''")

	for(var/turf/simulated/floor/F in world)
		CHECK_TICK
		if((F.z in GLOB.persistence_zlevel_skip) || is_mining_level(F.z) || persistence_z_manual_blocked(F.z)) continue
		if(!F.broken && !F.burnt && !F.color && F.type == F.baseturf)
			delete_coords += "([F.x],[F.y],[F.z])"
			continue
		var/content_json = replacetext(json_encode(list("broken"=F.broken,"burnt"=F.burnt,"color"=F.color)), "'", "''")
		var/type_str = replacetext("[F.type]", "'", "''")
		var/base_str = replacetext("[F.baseturf]", "'", "''")
		upsert_rows += "('[map_escaped]',[F.x],[F.y],[F.z],'[type_str]','[base_str]','[content_json]',NOW())"

	for(var/turf/simulated/wall/W in world)
		CHECK_TICK
		if((W.z in GLOB.persistence_zlevel_skip) || is_mining_level(W.z) || persistence_z_manual_blocked(W.z)) continue
		if(W.type == W.baseturf && W.health >= W.maxhealth)
			delete_coords += "([W.x],[W.y],[W.z])"
			continue
		var/mat_name   = W.material ? replacetext(W.material.name, "'", "''") : null
		var/reinf_name = W.reinf_material ? replacetext(W.reinf_material.name, "'", "''") : null
		var/content_json = "'[replacetext(json_encode(list("material"=mat_name,"reinf_material"=reinf_name,"health"=W.health,"construction_stage"=W.construction_stage)), "'", "''")]'"
		var/type_str = replacetext("[W.type]", "'", "''")
		var/base_str = replacetext("[W.baseturf]", "'", "''")
		upsert_rows += "('[map_escaped]',[W.x],[W.y],[W.z],'[type_str]','[base_str]',[content_json],NOW())"

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

	upsert_rows = list()
	for(var/turf/simulated/T in world)
		CHECK_TICK
		if((T.z in GLOB.persistence_zlevel_skip) || is_mining_level(T.z) || persistence_z_manual_blocked(T.z)) continue
		if(istype(T, /turf/simulated/floor) || istype(T, /turf/simulated/wall))
			continue
		if(T.type == T.baseturf)
			continue
		var/has_lattice = FALSE
		for(var/obj/structure/lattice/L in T)
			has_lattice = TRUE; break
		if(has_lattice)
			continue
		var/type_str = replacetext("[T.type]", "'", "''")
		var/base_str = replacetext("[T.baseturf]", "'", "''")
		upsert_rows += "('[map_escaped]',[T.x],[T.y],[T.z],'[type_str]','[base_str]','{}',NOW())"

	saved = length(upsert_rows)
	if(saved)
		var/chunk_size3 = 200
		for(var/i3 = 1 to saved step chunk_size3)
			var/end3 = min(i3 + chunk_size3 - 1, saved)
			var/list/chunk3 = upsert_rows.Copy(i3, end3 + 1)
			var/datum/db_query/bulk3 = SSdbcore.NewQuery(
				"INSERT INTO ss13_worldstate_turfs (map_path,x,y,z,turf_type,base_type,content,saved_at) VALUES [chunk3.Join(",")] ON DUPLICATE KEY UPDATE turf_type=VALUES(turf_type),base_type=VALUES(base_type),content=VALUES(content),saved_at=NOW()"
			)
			bulk3.Execute()
			databaseCheckQueryResult(bulk3, "turfsFinalize third-pass")
			qdel(bulk3)
			CHECK_TICK

	log_subsystem_persistence_info("Turfs: Saved [saved] changed turfs for map [SSatlas.current_map.path].")
