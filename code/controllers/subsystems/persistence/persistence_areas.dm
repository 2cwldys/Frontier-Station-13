/*
 * Persistence - Blueprint-created areas
 * Saves and restores areas created via the blueprints tool (finalize_area()),
 * so a player-made area's name, turf footprint, and faction ownership
 * (persistent_network, see faction_beacon.dm) survive a restart. Mapped-in
 * station areas (is_blueprint_area FALSE) are never touched -- those already
 * load from the map itself.
 *
 * Low cardinality compared to turf persistence (dozens of areas, not
 * thousands of tiles), so a full wipe-and-reinsert per save is used instead
 * of turfsFinalize()'s delta upsert -- areas have no stable identity across
 * saves to upsert against (a renamed area is, from the DB's perspective, a
 * different row) and re-deriving one isn't worth the complexity here.
 *
 * Hooked into SSpersistence Initialize() BEFORE worldstateInitialize(), so a
 * restored area already exists by the time a restored APC's get_area(src)
 * resolves -- and into Shutdown()/forceSaveAll() alongside worldstateFinalize().
 */

/**
 * Load saved blueprint areas from the database and apply them to the world.
 * Called from SSpersistence.Initialize(), before worldstateInitialize().
 */
/datum/controller/subsystem/persistence/proc/areasInitialize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("areasInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT name, area_type, turfs, persistent_network FROM ss13_persistent_areas WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "areasInitialize"))
		qdel(query)
		return

	var/restored = 0
	while(query.NextRow())
		try
			var/area_name = query.item[1]
			var/area_type = text2path(query.item[2])
			var/list/coords = json_decode(query.item[3])
			var/network = query.item[4]

			if(!area_type || !ispath(area_type, /area))
				area_type = /area
			if(!islist(coords) || !length(coords))
				continue

			var/area/A = new area_type()
			A.name = area_name
			A.is_blueprint_area = TRUE
			A.power_equip = FALSE
			A.power_light = FALSE
			A.power_environ = FALSE
			A.always_unpowered = FALSE
			if(network)
				A.persistent_network = network

			var/moved = 0
			var/skipped_unsafe = 0
			for(var/list/triple in coords)
				if(!islist(triple) || length(triple) < 3)
					continue
				var/tx = triple[1]
				var/ty = triple[2]
				var/tz = triple[3]
				if(tz < 1 || tz > world.maxz)
					continue
				if(!(tz in GLOB.persistence_pinned_site_z) && ((tz in GLOB.persistence_zlevel_skip) || is_mining_level(tz) || persistence_z_manual_blocked(tz)))
					continue
				var/turf/T = locate(tx, ty, tz)
				if(!istype(T))
					continue
				var/area/current = T.loc
				if(!current)
					continue
				// Never steal a turf that's now part of a real, mapped-in area --
				// only reclaim background turf or a turf that's already
				// blueprint-owned (same rule the interactive tool enforces, see
				// check_turf_validity_for_area() in blueprints.dm).
				if(!current.is_blueprint_area && !(current.area_flags & AREA_FLAG_IS_BACKGROUND))
					skipped_unsafe++
					log_subsystem_persistence_info("Areas: SKIPPED ([tx],[ty],[tz]) for '[area_name]' -- currently owned by real area '[current.name]' ([current.type]).")
					continue
				T.change_area(T.loc, A)
				moved++
				log_subsystem_persistence_info("Areas: moved ([tx],[ty],[tz]) from '[current.name]' ([current.type]) into restored blueprint area '[area_name]'.")

			if(skipped_unsafe)
				log_subsystem_persistence_info("Areas: '[area_name]' had [skipped_unsafe] unsafe turf(s) skipped (now owned by a real area).")

			if(!moved)
				qdel(A)
				continue

			restored++
			CHECK_TICK
		catch(var/exception/e)
			log_subsystem_persistence_error("Areas: Failed to restore a saved area: [e]")

	qdel(query)
	log_subsystem_persistence_info("Areas: Restored [restored] blueprint-created areas for map [SSatlas.current_map.path].")

/**
 * Save all blueprint-created areas to the database.
 * Full wipe-and-reinsert of this map's rows every call.
 * Called from SSpersistence.Shutdown() and forceSaveAll(), alongside worldstateFinalize().
 */
/datum/controller/subsystem/persistence/proc/areasFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("areasFinalize"))
		return

	var/map_path = "[SSatlas.current_map.path]"
	var/map_escaped = replacetext(map_path, "'", "''")

	var/datum/db_query/wipe = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_areas WHERE map_path = :map_path",
		list("map_path" = map_path)
	)
	wipe.Execute()
	databaseCheckQueryResult(wipe, "areasFinalize wipe")
	qdel(wipe)

	var/list/upsert_rows = list()
	var/saved = 0
	for(var/area/A in GLOB.areas)
		CHECK_TICK
		if(!A.is_blueprint_area)
			continue

		var/list/coords = list()
		var/first_z = 0
		for(var/turf/T in A.contents)
			// Deployed ship Zs are saved separately, keyed to their own ship
			// scope (areasFinalizeZ()/areasApplyZ() below, called from
			// shipInteriorSave()/shipInteriorApply()) -- skip them here so a
			// ship's blueprint areas never get written twice under the wrong
			// (plain map) scope, which would misapply after Z-pool reuse.
			if(GLOB.persistence_ship_z["[T.z]"])
				continue
			if(!(T.z in GLOB.persistence_pinned_site_z) && ((T.z in GLOB.persistence_zlevel_skip) || is_mining_level(T.z) || persistence_z_manual_blocked(T.z)))
				continue
			if(!first_z)
				first_z = T.z
			coords += list(list(T.x, T.y, T.z))

		if(!length(coords))
			continue

		var/name_str = replacetext(A.name, "'", "''")
		var/type_str = replacetext("[A.type]", "'", "''")
		var/turfs_json = replacetext(json_encode(coords), "'", "''")
		var/network_str = A.persistent_network ? replacetext(A.persistent_network, "'", "''") : ""
		upsert_rows += "('[map_escaped]',[first_z],'[name_str]','[type_str]','[turfs_json]','[network_str]',NOW())"
		saved++

	if(length(upsert_rows))
		var/chunk_size = 200
		for(var/i = 1 to saved step chunk_size)
			var/end = min(i + chunk_size - 1, saved)
			var/list/chunk = upsert_rows.Copy(i, end + 1)
			var/datum/db_query/bulk = SSdbcore.NewQuery(
				"INSERT INTO ss13_persistent_areas (map_path,z,name,area_type,turfs,persistent_network,saved_at) VALUES [chunk.Join(",")]"
			)
			bulk.Execute()
			databaseCheckQueryResult(bulk, "areasFinalize bulk insert")
			qdel(bulk)
			CHECK_TICK

	log_subsystem_persistence_info("Areas: Saved [saved] blueprint-created areas for map [SSatlas.current_map.path].")

/**
 * Per-ship sibling of areasFinalize() above -- captures blueprint-created
 * areas whose turfs live on this one ship z, wiping and reinserting only
 * this ship's own scope-keyed rows. Called by shipInteriorSave()
 * (persistence_ship_interiors.dm) instead of the whole-map sweep, which
 * deliberately skips ship Zs (see the skip check added to the loop above) now
 * that they're handled here under their own "ship:d:<id>" scope key.
 */
/datum/controller/subsystem/persistence/proc/areasFinalizeZ(z, scope)
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("areasFinalizeZ"))
		return FALSE

	var/scope_escaped = replacetext(scope, "'", "''")

	var/datum/db_query/wipe = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_areas WHERE map_path = :mp",
		list("mp" = scope)
	)
	wipe.Execute()
	databaseCheckQueryResult(wipe, "areasFinalizeZ wipe")
	qdel(wipe)

	var/list/upsert_rows = list()
	var/saved = 0
	for(var/area/A in GLOB.areas)
		CHECK_TICK
		if(!A.is_blueprint_area)
			continue

		var/list/coords = list()
		for(var/turf/T in A.contents)
			if(T.z != z)
				continue
			coords += list(list(T.x, T.y, T.z))

		if(!length(coords))
			continue

		var/name_str = replacetext(A.name, "'", "''")
		var/type_str = replacetext("[A.type]", "'", "''")
		var/turfs_json = replacetext(json_encode(coords), "'", "''")
		var/network_str = A.persistent_network ? replacetext(A.persistent_network, "'", "''") : ""
		upsert_rows += "('[scope_escaped]',[z],'[name_str]','[type_str]','[turfs_json]','[network_str]',NOW())"
		saved++

	if(length(upsert_rows))
		var/datum/db_query/bulk = SSdbcore.NewQuery(
			"INSERT INTO ss13_persistent_areas (map_path,z,name,area_type,turfs,persistent_network,saved_at) VALUES [upsert_rows.Join(",")]"
		)
		bulk.Execute()
		databaseCheckQueryResult(bulk, "areasFinalizeZ bulk insert")
		qdel(bulk)

	log_subsystem_persistence_info("Ship interiors: saved [saved] blueprint-created area(s) for scope [scope].")
	return TRUE

/**
 * Per-ship sibling of areasInitialize() above -- restores blueprint-created
 * areas onto a freshly template-loaded ship z. Unlike every other ship-scoped
 * table, z here is embedded per-coordinate inside each row's turfs JSON
 * rather than a plain column, so there's no separate remapShipRows() entry
 * for this table (persistence_ship_interiors.dm) -- the remap happens inline
 * below by locating each saved (x,y) on the ship's CURRENT live z instead of
 * whatever z the row was saved under. Called by shipInteriorApply().
 */
/datum/controller/subsystem/persistence/proc/areasApplyZ(z, scope)
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("areasApplyZ"))
		return FALSE

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT name, area_type, turfs, persistent_network FROM ss13_persistent_areas WHERE map_path = :mp",
		list("mp" = scope)
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "areasApplyZ"))
		qdel(query)
		return FALSE

	var/restored = 0
	while(query.NextRow())
		try
			var/area_name = query.item[1]
			var/area_type = text2path(query.item[2])
			var/list/coords = json_decode(query.item[3])
			var/network = query.item[4]

			if(!area_type || !ispath(area_type, /area))
				area_type = /area
			if(!islist(coords) || !length(coords))
				continue

			var/area/A = new area_type()
			A.name = area_name
			A.is_blueprint_area = TRUE
			A.power_equip = FALSE
			A.power_light = FALSE
			A.power_environ = FALSE
			A.always_unpowered = FALSE
			if(network)
				A.persistent_network = network

			var/moved = 0
			for(var/list/triple in coords)
				if(!islist(triple) || length(triple) < 3)
					continue
				var/tx = triple[1]
				var/ty = triple[2]
				// Saved tz (triple[3]) reflects whatever z this ship last lived
				// on -- ignored on purpose, always remap onto the new live z
				// (same reasoning as remapShipRows()'s plain-column UPDATE).
				var/turf/T = locate(tx, ty, z)
				if(!istype(T))
					continue
				var/area/current = T.loc
				if(!current)
					continue
				if(!current.is_blueprint_area && !(current.area_flags & AREA_FLAG_IS_BACKGROUND))
					continue
				T.change_area(T.loc, A)
				moved++

			if(!moved)
				qdel(A)
				continue

			restored++
			CHECK_TICK
		catch(var/exception/e)
			log_subsystem_persistence_error("Ship interiors: failed to restore a saved blueprint area for scope [scope]: [e]")

	qdel(query)
	log_subsystem_persistence_info("Ship interiors: restored [restored] blueprint-created area(s) for scope [scope] at z=[z].")
	return TRUE
