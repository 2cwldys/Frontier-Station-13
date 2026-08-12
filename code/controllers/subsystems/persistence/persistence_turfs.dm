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
		if(!(tz in GLOB.persistence_pinned_site_z) && ((tz in GLOB.persistence_zlevel_skip) || is_mining_level(tz) || persistence_z_manual_blocked(tz))) continue
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
 * Apply saved ship-scoped turf rows to a freshly loaded ship Z. Same
 * restore mechanics as turfsInitialize(), but querying by ship scope
 * (rows were just remapped to this z by remapShipRows()) and skipping the
 * z-exclusion gates -- the caller owns the z and wants it applied. Rows
 * whose coordinates no longer match the hull (template edited between
 * sessions) skip harmlessly.
 */
/datum/controller/subsystem/persistence/proc/turfsApplyZ(z, scope)
	if(!databaseCheckConnection("turfsApplyZ"))
		return
	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT x, y, turf_type, base_type, content FROM ss13_worldstate_turfs WHERE map_path = :map_path AND z = :z",
		list("map_path" = scope, "z" = z)
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "turfsApplyZ"))
		qdel(query)
		return
	var/loaded = 0
	while(query.NextRow())
		var/tx = text2num(query.item[1])
		var/ty = text2num(query.item[2])
		var/turf_type = text2path(query.item[3])
		var/base_type = text2path(query.item[4])
		var/content_json = query.item[5]
		if(!turf_type)
			continue
		var/turf/T = locate(tx, ty, z)
		if(!istype(T))
			continue
		try
			var/list/content = json_decode(content_json)
			if(!content)
				continue
			T.ChangeTurf(turf_type)
			if(base_type)
				T.baseturf = base_type
			turfsApplyContent(T, content)
		catch(var/exception/e)
			log_subsystem_persistence_error("Turfs: Failed to apply ship turf at ([tx],[ty],[z]) for [scope]: [e]")
			continue
		loaded++
		CHECK_TICK
	qdel(query)
	log_subsystem_persistence_info("Turfs: Applied [loaded] ship turfs to z=[z] ([scope]).")

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
		// Rebuild through set_material() rather than assigning the material
		// refs raw. update_material() is what derives name/desc/opacity/
		// explosion_resistance/icon from the material, and maxhealth has to be
		// recomputed from the RESTORED materials -- Initialize() only ever
		// derived it from the wall TYPE's default material, so a restored wall
		// kept a maxhealth that didn't match what it's actually made of. Once
		// that desyncs from the restored health, wall_attacks.dm's damage check
		// traps the welder in the REPAIR branch, which returns before it can
		// ever reach the dismantle code -- a wall that simply can't be taken
		// apart. Mirrors /turf/simulated/wall/Initialize()'s own ordering.
#ifdef WALL_RESTORE_DIAGNOSTICS
		log_subsystem_persistence_info("Turfs: wall restore at ([W.x],[W.y],[W.z]) -- saved_material=[content["material"] || "MISSING"] W.material(pre)=[W.material ? W.material.name : "NULL"] W.icon(pre)=[W.icon || "NULL"]")
#endif
		if(content["material"])
			var/material/restored_mat = SSmaterials.get_material_by_name(content["material"])
			var/material/restored_reinf = !isnull(content["reinf_material"]) ? SSmaterials.get_material_by_name(content["reinf_material"]) : null
			if(restored_mat)
				W.set_material(restored_mat, restored_reinf)
				W.hitsound = W.material.hitsound
				W.set_maxhealth(W.material.integrity + (W.reinf_material ? W.reinf_material.integrity : 0), TRUE)
		// Guarantee a real material and a freshly (re-)picked icon variant
		// regardless of whether a saved material was found above.
		// ChangeTurf() (called just before this proc) SHOULD already have run
		// Initialize() -> update_material() and set a default steel material +
		// icon on this turf -- but a restored wall has been observed showing
		// icon=null via VV despite that, meaning that chain isn't reliable
		// here. This re-derives both explicitly rather than trusting it: safe
		// and a no-op when set_material() above already ran correctly (same
		// x/y/z + same material always picks the same deterministic variant),
		// and the only thing that actually fixes the case where it didn't.
		if(!W.material)
			W.material = SSmaterials.get_material_by_name(DEFAULT_WALL_MATERIAL)
		if(W.material)
			var/picked_variant = pick_wall_icon_variant(W.x, W.y, W.z, W.material.wall_icon_variants)
			if(picked_variant)
				W.icon = picked_variant
			else if(W.material.wall_icon)
				W.icon = W.material.wall_icon
#ifdef WALL_RESTORE_DIAGNOSTICS
		log_subsystem_persistence_info("Turfs: wall restore at ([W.x],[W.y],[W.z]) -- W.icon(post)=[W.icon || "STILL NULL"]")
#endif
		// under_turf is what a wall reverts to when dismantled, and is neither
		// carried by ChangeTurf() nor derived from anything -- without it a
		// restored player/RFD-built wall comes apart into plating instead of
		// whatever floor it was actually built on.
		if(!isnull(content["under_turf"]))
			var/under_path = text2path(content["under_turf"])
			if(under_path)
				W.under_turf = under_path
		// After set_material(): update_material() forces construction_stage to
		// 6 (or null) from reinf_material, which would otherwise wipe a
		// part-deconstructed wall's saved progress.
		if(!isnull(content["construction_stage"]))
			W.construction_stage = text2num(content["construction_stage"])
		// After set_maxhealth(): that rewrites health when update_current_health
		// is set (atom_health.dm), so the saved value has to land last.
		if(!isnull(content["health"]))
			W.health = text2num(content["health"])
		W.update_icon()

/**
 * Examine one simulated turf and append its save outcome to the shared
 * collections: an upsert row string (keyed under persistence_scope_for_z(),
 * so deployed ship Zs write under their ship scope -- see
 * persistence_ship_interiors.dm), or a delete coordinate bucketed by scope
 * for turfs that have reverted to default. Shared by the full-world sweep
 * (turfsFinalize()) and the per-ship-Z save (turfsFinalizeZ()).
 */
/datum/controller/subsystem/persistence/proc/_turfsCollectOne(turf/simulated/T, list/upsert_rows, list/delete_by_scope)
	PRIVATE_PROC(TRUE)
	if(!(T.z in GLOB.persistence_pinned_site_z) && ((T.z in GLOB.persistence_zlevel_skip) || is_mining_level(T.z) || persistence_z_manual_blocked(T.z)))
		return
	if(persistence_area_excluded(T))
		return
	if(persistence_turf_docked_elsewhere(T))
		return
	var/scope_escaped = replacetext(persistence_scope_for_z(T.z), "'", "''")

	if(istype(T, /turf/simulated/floor))
		var/turf/simulated/floor/F = T
		if(!F.broken && !F.burnt && !F.color && F.type == F.baseturf)
			if(!(scope_escaped in delete_by_scope))
				delete_by_scope[scope_escaped] = list()
			delete_by_scope[scope_escaped] += "([F.x],[F.y],[F.z])"
			return
		var/content_json = replacetext(json_encode(list("broken"=F.broken,"burnt"=F.burnt,"color"=F.color)), "'", "''")
		var/type_str = replacetext("[F.type]", "'", "''")
		var/base_str = replacetext("[F.baseturf]", "'", "''")
		upsert_rows += "('[scope_escaped]',[F.x],[F.y],[F.z],'[type_str]','[base_str]','[content_json]',NOW())"
		return

	if(istype(T, /turf/simulated/wall))
		var/turf/simulated/wall/W = T
		if(W.type == W.baseturf && W.health >= W.maxhealth)
			if(!(scope_escaped in delete_by_scope))
				delete_by_scope[scope_escaped] = list()
			delete_by_scope[scope_escaped] += "([W.x],[W.y],[W.z])"
			return
		var/mat_name   = W.material ? replacetext(W.material.name, "'", "''") : null
		var/reinf_name = W.reinf_material ? replacetext(W.reinf_material.name, "'", "''") : null
		var/wall_json = replacetext(json_encode(list("material"=mat_name,"reinf_material"=reinf_name,"health"=W.health,"construction_stage"=W.construction_stage,"under_turf"="[W.under_turf]")), "'", "''")
		var/wtype_str = replacetext("[W.type]", "'", "''")
		var/wbase_str = replacetext("[W.baseturf]", "'", "''")
		upsert_rows += "('[scope_escaped]',[W.x],[W.y],[W.z],'[wtype_str]','[wbase_str]','[wall_json]',NOW())"
		return

	// Other simulated turfs (catwalks etc.) -- saved type-only when changed.
	if(T.type == T.baseturf)
		return
	var/has_lattice = FALSE
	for(var/obj/structure/lattice/L in T)
		has_lattice = TRUE
		break
	if(has_lattice)
		return
	var/otype_str = replacetext("[T.type]", "'", "''")
	var/obase_str = replacetext("[T.baseturf]", "'", "''")
	upsert_rows += "('[scope_escaped]',[T.x],[T.y],[T.z],'[otype_str]','[obase_str]','{}',NOW())"

/**
 * Flush collected turf rows: one default-reversion DELETE per scope, then
 * chunked bulk upserts. Shared by turfsFinalize() and turfsFinalizeZ().
 */
/datum/controller/subsystem/persistence/proc/_turfsFlush(list/upsert_rows, list/delete_by_scope)
	PRIVATE_PROC(TRUE)
	for(var/scope_escaped in delete_by_scope)
		var/list/coords = delete_by_scope[scope_escaped]
		if(!length(coords))
			continue
		var/datum/db_query/wipe_defaults = SSdbcore.NewQuery(
			"DELETE FROM ss13_worldstate_turfs WHERE map_path = '[scope_escaped]' AND (x,y,z) IN ([coords.Join(",")])"
		)
		wipe_defaults.Execute()
		qdel(wipe_defaults)
		CHECK_TICK

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
	return saved

/**
 * Permanently forgets any saved rows for the given turfs, right now.
 *
 * Exists because both save sweeps below iterate `/turf/simulated` ONLY -- a
 * turf that reverts from simulated to UNSIMULATED (space, most commonly) is
 * never visited by the collector at all, so it can never emit the
 * "reverted to default, delete its row" coordinate that _turfsCollectOne()
 * produces for an ordinary reversion. Its stale row would otherwise survive
 * every future save and get faithfully restored by turfsInitialize() on the
 * next boot -- resurrecting floors and walls at a site that was deliberately
 * cleared (the commission build-site wipe, _drydockCommissionRun(),
 * persistence_shuttles.dm, being the case that does this at scale).
 *
 * Takes live turfs and buckets by persistence_scope_for_z() exactly as
 * _turfsCollectOne() does, so a deployed ship Z's rows are deleted under the
 * ship's own scope rather than the map's.
 */
/datum/controller/subsystem/persistence/proc/turfsForget(list/turfs)
	if(!length(turfs))
		return
	if(!databaseCheckConnection("turfsForget"))
		return

	var/list/delete_by_scope = list()
	for(var/turf/T in turfs)
		var/scope_escaped = replacetext(persistence_scope_for_z(T.z), "'", "''")
		if(!(scope_escaped in delete_by_scope))
			delete_by_scope[scope_escaped] = list()
		delete_by_scope[scope_escaped] += "([T.x],[T.y],[T.z])"
		// Drop the in-memory copy too, so nothing in this same session can
		// re-derive the row from cache before the next real save.
		GLOB.persistence_turfs_cache -= "[T.x]|[T.y]|[T.z]"
		CHECK_TICK

	var/forgotten = 0
	for(var/scope_escaped in delete_by_scope)
		var/list/coords = delete_by_scope[scope_escaped]
		if(!length(coords))
			continue
		var/datum/db_query/wipe = SSdbcore.NewQuery(
			"DELETE FROM ss13_worldstate_turfs WHERE map_path = '[scope_escaped]' AND (x,y,z) IN ([coords.Join(",")])"
		)
		wipe.Execute()
		databaseCheckQueryResult(wipe, "turfsForget delete")
		qdel(wipe)
		forgotten += length(coords)
		CHECK_TICK

	log_subsystem_persistence_info("Turfs: Forgot [forgotten] turf row(s) across [length(delete_by_scope)] scope(s).")

/**
 * Save all structurally changed turfs to the database at round end.
 * Full world scan  compares every simulated floor and wall against its base state.
 * Called from SSpersistence.Shutdown() and forceSaveAll().
 */
/datum/controller/subsystem/persistence/proc/turfsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("turfsFinalize"))
		return

	var/list/upsert_rows     = list()
	var/list/delete_by_scope = list()

	for(var/turf/simulated/T in world)
		CHECK_TICK
		_turfsCollectOne(T, upsert_rows, delete_by_scope)

	var/saved = _turfsFlush(upsert_rows, delete_by_scope)
	log_subsystem_persistence_info("Turfs: Saved [saved] changed turfs for map [SSatlas.current_map.path].")

/**
 * Per-Z turf save for a deployed ship Z -- same collector/flush as the world
 * sweep, restricted to one z. Caller must still have the z registered in
 * GLOB.persistence_ship_z so rows key under the ship scope.
 */
/datum/controller/subsystem/persistence/proc/turfsFinalizeZ(z)
	if(!databaseCheckConnection("turfsFinalizeZ"))
		return
	var/list/upsert_rows     = list()
	var/list/delete_by_scope = list()
	for(var/turf/simulated/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		CHECK_TICK
		_turfsCollectOne(T, upsert_rows, delete_by_scope)
	var/saved = _turfsFlush(upsert_rows, delete_by_scope)
	log_subsystem_persistence_info("Turfs: Saved [saved] changed turfs for z=[z] ([persistence_scope_for_z(z)]).")
