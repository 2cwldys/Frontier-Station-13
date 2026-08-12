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
		var/rep_z = text2num(query.item[3])
		if(persistence_z_manual_blocked(rep_z))
			continue
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
		CHECK_TICK
		if(!length(GLOB.persistence_atmos_cache))
			break
		if(!length(Z.contents))
			continue

		// The save keys each zone on its first turf, but ZAS rebuilds zone
		// membership/ordering every boot (and restored walls split/merge
		// zones), so the saved representative is not reliably contents[1]
		// anymore. Scan the zone for ANY turf matching a saved key, and
		// consume the entry so each saved zone applies exactly once.
		var/list/entry = null
		var/turf/simulated/rep = null
		for(var/turf/simulated/T in Z.contents)
			if((!is_station_level(T.z) && !(T.z in GLOB.persistence_pinned_site_z)) || persistence_z_manual_blocked(T.z))
				continue
			var/key = "[T.x]|[T.y]|[T.z]"
			var/list/candidate = GLOB.persistence_atmos_cache[key]
			if(candidate)
				entry = candidate
				rep = T
				GLOB.persistence_atmos_cache -= key
				break
		if(!entry)
			continue

		try
			var/list/gas_data = json_decode(entry["gas_json"])
			if(!gas_data || !islist(gas_data))
				continue
			Z.air.gas = gas_data
			Z.air.temperature = entry["temperature"]
			Z.air.update_values()
		catch(var/exception/e)
			log_subsystem_persistence_error("Atmos: Failed to apply zone at ([rep.x],[rep.y],[rep.z]): [e]")
			continue

		applied++

	var/unmatched = length(GLOB.persistence_atmos_cache)
	log_subsystem_persistence_info("Atmos: Applied gas state to [applied] zones[unmatched ? ", [unmatched] saved zone(s) unmatched" : ""].")

/**
 * Save all active atmospheric zone states to the database at round end.
 * Called from SSpersistence.Shutdown().
 */
/datum/controller/subsystem/persistence/proc/atmosFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("atmosFinalize"))
		return

	// Wipe-and-reinsert per scope: current map plus every deployed ship's
	// scope (see persistence_ship_interiors.dm).
	var/datum/db_query/delete_old = SSdbcore.NewQuery(
		"DELETE FROM ss13_atmos_zones WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	delete_old.Execute()
	databaseCheckQueryResult(delete_old, "atmosFinalize delete old")
	qdel(delete_old)
	for(var/ship_z in GLOB.persistence_ship_z)
		var/datum/db_query/ship_delete = SSdbcore.NewQuery(
			"DELETE FROM ss13_atmos_zones WHERE map_path = :map_path",
			list("map_path" = GLOB.persistence_ship_z[ship_z])
		)
		ship_delete.Execute()
		databaseCheckQueryResult(ship_delete, "atmosFinalize ship scope delete")
		qdel(ship_delete)

	// Collect all zone rows then bulk INSERT in chunks  avoids 487 round-trips
	var/list/value_rows = list()

	for(var/zone/Z in SSair.zones)
		CHECK_TICK
		var/row = _atmosZoneRow(Z)
		if(row)
			value_rows += row

	var/saved = _atmosFlush(value_rows, "atmosFinalize")
	log_subsystem_persistence_info("Atmos: Saved [saved] zone gas states for map [SSatlas.current_map.path].")

/**
 * Build the bulk-INSERT row string for one ZAS zone, keyed under its
 * representative turf's persistence scope (ship scope for deployed ship Zs).
 * Returns null if the zone should not be saved.
 */
/datum/controller/subsystem/persistence/proc/_atmosZoneRow(zone/Z)
	PRIVATE_PROC(TRUE)
	if(Z.invalid || !length(Z.contents))
		return null
	var/turf/simulated/rep = Z.contents[1]
	if(!rep)
		return null
	if(!is_station_level(rep.z) && !(rep.z in GLOB.persistence_pinned_site_z) && !GLOB.persistence_ship_z["[rep.z]"])
		return null
	if(persistence_z_manual_blocked(rep.z))
		return null
	if(!Z.air || !length(Z.air.gas))
		return null
	if(persistence_turf_docked_elsewhere(rep))
		return null
	var/scope_escaped = replacetext(persistence_scope_for_z(rep.z), "'", "''")
	var/gas_json = replacetext(json_encode(Z.air.gas), "'", "''")
	return "('[scope_escaped]', [rep.x], [rep.y], [rep.z], '[gas_json]', [Z.air.temperature], NOW())"

/// Chunked bulk INSERT of collected atmos zone rows.
/datum/controller/subsystem/persistence/proc/_atmosFlush(list/value_rows, log_context)
	PRIVATE_PROC(TRUE)
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
			databaseCheckQueryResult(bulk, "[log_context] bulk insert")
			qdel(bulk)
			CHECK_TICK
	return saved

/**
 * Per-Z atmos save for a deployed ship Z -- wipe the ship scope's rows, then
 * re-collect zones whose representative turf sits on that z.
 */
/datum/controller/subsystem/persistence/proc/atmosFinalizeZ(z, scope)
	if(!databaseCheckConnection("atmosFinalizeZ"))
		return
	var/datum/db_query/delete_old = SSdbcore.NewQuery(
		"DELETE FROM ss13_atmos_zones WHERE map_path = :map_path",
		list("map_path" = scope)
	)
	delete_old.Execute()
	databaseCheckQueryResult(delete_old, "atmosFinalizeZ delete")
	qdel(delete_old)

	var/list/value_rows = list()
	for(var/zone/Z in SSair.zones)
		CHECK_TICK
		if(Z.invalid || !length(Z.contents))
			continue
		var/turf/simulated/first_turf = Z.contents[1]
		if(!first_turf || first_turf.z != z)
			continue
		var/row = _atmosZoneRow(Z)
		if(row)
			value_rows += row

	var/saved = _atmosFlush(value_rows, "atmosFinalizeZ")
	log_subsystem_persistence_info("Atmos: Saved [saved] ship zone gas states for z=[z] ([scope]).")

/**
 * Apply saved ship-scoped zone gas states to a freshly loaded ship Z. Called
 * on a delay after retrieve (ZAS needs a few ticks to rebuild zones on the
 * new Z once SSair resumes). Same consume-on-match shape as atmosApply();
 * zones with no saved match keep the template's authored atmosphere.
 */
/datum/controller/subsystem/persistence/proc/atmosApplyZ(z, scope)
	if(!databaseCheckConnection("atmosApplyZ"))
		return
	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT rep_x, rep_y, gas_json, temperature FROM ss13_atmos_zones WHERE map_path = :map_path AND rep_z = :z",
		list("map_path" = scope, "z" = z)
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "atmosApplyZ"))
		qdel(query)
		return
	var/list/saved_zones = list()
	while(query.NextRow())
		saved_zones["[query.item[1]]|[query.item[2]]"] = list(
			"gas_json"    = query.item[3],
			"temperature" = text2num(query.item[4])
		)
	qdel(query)
	if(!length(saved_zones))
		return

	var/applied = 0
	for(var/zone/Z in SSair.zones)
		CHECK_TICK
		if(!length(saved_zones))
			break
		if(Z.invalid || !length(Z.contents))
			continue
		var/list/entry = null
		var/turf/simulated/rep = null
		for(var/turf/simulated/T in Z.contents)
			if(T.z != z)
				break // zones never span Zs; skip whole zone fast
			var/list/candidate = saved_zones["[T.x]|[T.y]"]
			if(candidate)
				entry = candidate
				rep = T
				saved_zones -= "[T.x]|[T.y]"
				break
		if(!entry)
			continue
		try
			var/list/gas_data = json_decode(entry["gas_json"])
			if(!gas_data || !islist(gas_data))
				continue
			Z.air.gas = gas_data
			Z.air.temperature = entry["temperature"]
			Z.air.update_values()
		catch(var/exception/e)
			log_subsystem_persistence_error("Atmos: Failed to apply ship zone at ([rep.x],[rep.y],[z]): [e]")
			continue
		applied++
	log_subsystem_persistence_info("Atmos: Applied [applied] ship zone gas states to z=[z] ([scope])[length(saved_zones) ? ", [length(saved_zones)] unmatched" : ""].")
