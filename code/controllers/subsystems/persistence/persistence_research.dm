/*
 * Persistence - R&D Tech Trees
 * Saves and restores R&D server technology levels across rounds via SQL.
 * Tech levels are serialized as a JSON array keyed by tech ID.
 * Only runs on the SCCV Horizon map, mirroring the persistent objects guard.
 *
 * Hooked into SSpersistence Initialize() and Shutdown().
 * R&D servers read the cache in their setup() proc.
 */

/// Cached tech data for the current map, list of {id, level, next_level_progress} entries
GLOBAL_VAR(persistence_research_cache)

/**
 * Load saved R&D tech data from the database into the in-memory cache.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/researchInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_research_cache = null

	if(!databaseCheckConnection("researchInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT tech_data FROM ss13_research_state WHERE map_path = :map_path ORDER BY saved_at DESC LIMIT 1",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "researchInitialize"))
		qdel(query)
		return

	if(query.NextRow())
		var/json = query.item[1]
		if(json)
			GLOB.persistence_research_cache = json_decode(json)
			log_subsystem_persistence_info("Research: Loaded tech state for map [SSatlas.current_map.path] ([length(GLOB.persistence_research_cache)] techs).")
		else
			log_subsystem_persistence_info("Research: No saved tech data found for map [SSatlas.current_map.path].")
	else
		log_subsystem_persistence_info("Research: No saved research state found for map [SSatlas.current_map.path].")

	qdel(query)

/**
 * Save R&D tech levels from all active R&D servers to the database.
 * Aggregates across servers (takes highest level per tech in case of multiple servers).
 * Called from SSpersistence.Shutdown() at round end.
 */
/datum/controller/subsystem/persistence/proc/researchFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("researchFinalize"))
		return

	// Aggregate tech levels across all R&D servers  take the highest level per tech
	var/list/aggregated_tech = list()

	for(var/obj/structure/machinery/r_n_d/server/server in world)
		if(!server.files)
			continue
		for(var/tech_id in server.files.known_tech)
			var/datum/tech/tech = server.files.known_tech[tech_id]
			if(!aggregated_tech[tech_id] || tech.level > aggregated_tech[tech_id]["level"])
				aggregated_tech[tech_id] = list(
					"id"       = tech_id,
					"level"    = tech.level,
					"progress" = tech.next_level_progress
				)

	if(!length(aggregated_tech))
		log_subsystem_persistence_info("Research: No R&D servers found or no tech to save.")
		return

	var/list/tech_list = list()
	for(var/tech_id in aggregated_tech)
		tech_list += list(aggregated_tech[tech_id])

	var/tech_json = json_encode(tech_list)

	// Replace existing entry for this map (only keep latest round's data)
	var/datum/db_query/delete_old = SSdbcore.NewQuery(
		"DELETE FROM ss13_research_state WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	delete_old.Execute()
	databaseCheckQueryResult(delete_old, "researchFinalize delete old")
	qdel(delete_old)

	var/datum/db_query/insert = SSdbcore.NewQuery(
		"INSERT INTO ss13_research_state (map_path, tech_data, saved_at) VALUES (:map_path, :tech_data, NOW())",
		list(
			"map_path"  = "[SSatlas.current_map.path]",
			"tech_data" = tech_json
		)
	)
	insert.Execute()
	databaseCheckQueryResult(insert, "researchFinalize insert")
	qdel(insert)

	log_subsystem_persistence_info("Research: Saved [length(aggregated_tech)] tech entries for map [SSatlas.current_map.path].")

/**
 * Apply cached tech levels to a newly initialized R&D research datum.
 * Called from /obj/structure/machinery/r_n_d/server/setup().
 */
/datum/research/proc/applyPersistentTechLevels(faction_uid = null)
	if(!GLOB.config.sql_enabled)
		return

	// Use faction research cache if this server belongs to a faction
	var/list/tech_cache = null
	if(faction_uid && islist(GLOB.persistence_faction_research_cache) && (faction_uid in GLOB.persistence_faction_research_cache))
		tech_cache = GLOB.persistence_faction_research_cache[faction_uid]
	else if(!faction_uid && GLOB.persistence_research_cache)
		tech_cache = GLOB.persistence_research_cache
	if(!tech_cache)
		return

	var/restored = 0
	for(var/list/entry in tech_cache)
		var/tech_id = entry["id"]
		if(!known_tech[tech_id])
			continue
		var/datum/tech/tech = known_tech[tech_id]
		// Only advance tech, never regress it
		if(text2num(entry["level"]) > tech.level)
			tech.level = text2num(entry["level"])
			tech.next_level_progress = text2num(entry["progress"]) || 0
			restored++

	if(restored)
		RefreshResearch()
		log_subsystem_persistence_info("Research: Restored [restored] tech levels on R&D server.")
