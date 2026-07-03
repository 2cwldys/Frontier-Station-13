/*
 * Persistence - Atmospheric Zone State
 * Saves and restores per-zone gas composition and temperature across rounds.
 * Uses the first turf in each zone as the representative coordinate key.
 *
 * Timing: SSair (INIT_ORDER_AIR = -1) initializes BEFORE SSpersistence
 * (INIT_ORDER_PERSISTENCE = -10). SSpersistence.Initialize() restores turfs,
 * loads the atmos cache (atmosInitialize), settles the ZAS updates the turf
 * restore queued (SSair.fire), then calls atmosApply() to re-pressurize zones
 * from the saved state.
 *
 * Only runs on the SCCV Horizon map.
 */

/// Cached atmos data keyed by "[x]|[y]|[z]" of the representative turf
GLOBAL_LIST_EMPTY(persistence_atmos_cache)

/**
 * Load saved atmospheric zone data into the in-memory cache.
 * Called from SSpersistence.Initialize(), right before atmosApply().
 */
/datum/controller/subsystem/persistence/proc/atmosInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_atmos_cache = list()

	if(!databaseCheckConnection("atmosInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT rep_x, rep_y, rep_z, gas_json, temperature FROM ss13_atmos_zones WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "atmosInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/key = "[query.item[1]]|[query.item[2]]|[query.item[3]]"
		GLOB.persistence_atmos_cache[key] = list(
			"gas_json"    = query.item[4],
			"temperature" = text2num(query.item[5])
		)
		loaded++

	qdel(query)
	log_subsystem_persistence_info("Atmos: Loaded [loaded] zone entries for map [SSatlas.current_map.path].")

/**
 * Apply cached atmos data to live zones after SSair has built them.
 * Called from SSpersistence.Initialize() after the turf restore and air settle.
 */
/datum/controller/subsystem/persistence/proc/atmosApply()
	if(!GLOB.config.sql_enabled || !length(GLOB.persistence_atmos_cache))
		return

	var/applied = 0
	for(var/zone/Z in SSair.zones)
		if(!length(Z.contents))
			continue

		// Use the first turf in the zone as the representative coordinate
		var/turf/simulated/rep = Z.contents[1]
		if(!rep || !is_station_level(rep.z))
			continue

		var/key = "[rep.x]|[rep.y]|[rep.z]"
		var/list/entry = GLOB.persistence_atmos_cache[key]
		if(!entry)
			continue

		var/list/gas_data = json_decode(entry["gas_json"])
		if(!gas_data || !islist(gas_data))
			continue

		try
			Z.air.gas = gas_data
			Z.air.temperature = entry["temperature"]
			Z.air.update_values()
		catch(var/exception/e)
			log_subsystem_persistence_error("Atmos: Failed to apply zone at ([rep.x],[rep.y],[rep.z]): [e]")
			continue

		applied++

	log_subsystem_persistence_info("Atmos: Applied gas state to [applied] zones.")

/**
 * Save all active atmospheric zone states to the database at round end.
 * Called from SSpersistence.Shutdown().
 */
/datum/controller/subsystem/persistence/proc/atmosFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("atmosFinalize"))
		return

	var/datum/db_query/delete_old = SSdbcore.NewQuery(
		"DELETE FROM ss13_atmos_zones WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	delete_old.Execute()
	databaseCheckQueryResult(delete_old, "atmosFinalize delete old")
	qdel(delete_old)

	// Collect all zone rows then bulk INSERT in chunks  avoids 487 round-trips
	var/list/value_rows = list()
	var/map_path_escaped = replacetext("[SSatlas.current_map.path]", "'", "''")

	for(var/zone/Z in SSair.zones)
		CHECK_TICK
		if(Z.invalid || !length(Z.contents))
			continue
		var/turf/simulated/rep = Z.contents[1]
		if(!rep || !is_station_level(rep.z))
			continue
		if(!Z.air || !length(Z.air.gas))
			continue
		var/gas_json = replacetext(json_encode(Z.air.gas), "'", "''")
		value_rows += "('[map_path_escaped]', [rep.x], [rep.y], [rep.z], '[gas_json]', [Z.air.temperature], NOW())"

	var/saved = length(value_rows)
	if(saved)
		var/chunk_size = 200
		for(var/i = 1 to saved step chunk_size)
			var/end = min(i + chunk_size - 1, saved)
			var/list/chunk = value_rows.Copy(i, end + 1)
			var/datum/db_query/bulk = SSdbcore.NewQuery(
				"INSERT INTO ss13_atmos_zones (map_path, rep_x, rep_y, rep_z, gas_json, temperature, saved_at) VALUES [chunk.Join(",")]"
			)
			bulk.Execute()
			databaseCheckQueryResult(bulk, "atmosFinalize bulk insert")
			qdel(bulk)
			CHECK_TICK

	log_subsystem_persistence_info("Atmos: Saved [saved] zone gas states for map [SSatlas.current_map.path].")
