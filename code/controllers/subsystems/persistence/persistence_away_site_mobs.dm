/*
 * Persistence - Away Site Mob Presets
 * Admin-authored, DB-backed (ss13_away_site_mob_presets) pool of hostile NPC
 * presets (persistence_hostile_npcs.dm) eligible to auto-populate a freshly
 * generated away site as long as it isn't already spoken for -- pinned,
 * beacon-claimed, or an active mission's target sector. Mirrors the exact
 * cache/Initialize()/admin-verb shape the other persistence_*.dm preset
 * files use.
 *
 * Consumed by: maps/_common/mapsystem/map.dm's build_away_sites() (the
 * boot-time RNG pool) and persistence_factions.dm's
 * _spawn_away_site_for_template() (runtime on-demand generation) -- both call
 * maybe_populate_away_site_with_pirates() right after a new site's Z is known.
 */

/// Cached away-site mob presets: list of list(id, preset_id).
GLOBAL_LIST_EMPTY(away_site_mob_presets)

/**
 * Load away-site mob presets into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/awaySiteMobPresetsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.away_site_mob_presets = list()

	if(!databaseCheckConnection("awaySiteMobPresetsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT id, preset_id FROM ss13_away_site_mob_presets WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "awaySiteMobPresetsInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.away_site_mob_presets += list(list(
			"id"        = text2num(query.item[1]),
			"preset_id" = text2num(query.item[2])
		))
	qdel(query)
	log_subsystem_persistence_info("Away site mob presets: loaded [length(GLOB.away_site_mob_presets)] preset(s).")

/**
 * Populates a freshly-generated away site Z with 1-3 hostile NPCs drawn from
 * the admin-authored pool, unless it's pinned, an active mission's target
 * sector, already claimed by a powered faction beacon, or a template that
 * already ships its own hand-placed fauna_spawner. Safe to call for any Z --
 * silently does nothing if none of the above apply or the pool is empty.
 */
/proc/maybe_populate_away_site_with_pirates(z)
	if(!z || (z in GLOB.persistence_pinned_site_z))
		return
	if(is_active_mission_sector(z))
		return
	if(get_owning_faction_beacon(z))
		return
	if(!length(GLOB.away_site_mob_presets))
		return
	if(islist(GLOB.fauna_spawners))
		for(var/obj/effect/fauna_spawner/existing in GLOB.fauna_spawners)
			if(existing.z == z)
				return // template already ships its own hand-placed fauna
	var/spawn_count = rand(1, 3)
	for(var/i in 1 to spawn_count)
		var/list/entry = pick(GLOB.away_site_mob_presets)
		var/turf/T = find_mission_spawn_turf(z)
		if(T)
			spawn_hostile_npc_from_preset(entry["preset_id"], T)

/datum/admins/proc/manage_away_site_mob_presets()
	set name = "Modify Away Site Mobs"
	set category = "Persistence"
	set desc = "Add or remove hostile NPC presets from the pool that auto-populates freshly generated, unclaimed away sites."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- away site mob presets are inactive."))
		return

	while(usr && usr.client)
		var/msg = "Away site mob presets ([length(GLOB.away_site_mob_presets)]):\n"
		for(var/list/entry in GLOB.away_site_mob_presets)
			var/list/preset = get_hostile_npc_preset(entry["preset_id"])
			msg += "  #[entry["id"]] -- [preset ? preset["name"] : "(missing preset #[entry["preset_id"]])"]\n"
		to_chat(usr, SPAN_NOTICE(msg))

		var/choice = tgui_input_list(usr, "Select action:", "Modify Away Site Mobs", list("Add Preset to Pool", "Remove Preset from Pool", "Close"))
		if(!choice || choice == "Close")
			return

		if(choice == "Add Preset to Pool")
			if(!length(GLOB.hostile_npc_presets))
				to_chat(usr, SPAN_WARNING("No hostile NPC presets exist yet -- create one via 'Manage Hostile NPC Presets' first."))
				continue
			var/list/preset_options = list()
			for(var/list/preset in GLOB.hostile_npc_presets)
				preset_options["#[preset["id"]] [preset["name"]]"] = preset
			var/pick = tgui_input_list(usr, "Add which preset to the away-site pool?", "Modify Away Site Mobs", preset_options)
			if(!pick)
				continue
			var/list/picked_preset = preset_options[pick]

			var/datum/db_query/q = SSdbcore.NewQuery(
				"INSERT INTO ss13_away_site_mob_presets (map_path, preset_id) VALUES (:mp, :preset)",
				list("mp" = "[SSatlas.current_map.path]", "preset" = picked_preset["id"])
			)
			q.Execute()
			SSpersistence.databaseCheckQueryResult(q, "manage_away_site_mob_presets add")
			var/new_id = text2num(q.last_insert_id)
			qdel(q)

			GLOB.away_site_mob_presets += list(list("id" = new_id, "preset_id" = picked_preset["id"]))
			log_and_message_admins("added '[picked_preset["name"]]' to the away-site mob pool", usr)
			to_chat(usr, SPAN_GOOD("Added '[picked_preset["name"]]' to the pool."))

		if(choice == "Remove Preset from Pool")
			if(!length(GLOB.away_site_mob_presets))
				to_chat(usr, SPAN_NOTICE("Pool is empty."))
				continue
			var/list/remove_choices = list()
			for(var/list/entry in GLOB.away_site_mob_presets)
				var/list/preset = get_hostile_npc_preset(entry["preset_id"])
				remove_choices["#[entry["id"]] -- [preset ? preset["name"] : "(missing preset #[entry["preset_id"]])"]"] = entry
			var/remove_pick = tgui_input_list(usr, "Remove which entry from the pool?", "Modify Away Site Mobs", remove_choices)
			if(!remove_pick)
				continue
			var/list/remove_entry = remove_choices[remove_pick]
			var/datum/db_query/rq = SSdbcore.NewQuery(
				"DELETE FROM ss13_away_site_mob_presets WHERE id = :id",
				list("id" = remove_entry["id"])
			)
			rq.Execute()
			SSpersistence.databaseCheckQueryResult(rq, "manage_away_site_mob_presets remove")
			qdel(rq)
			GLOB.away_site_mob_presets -= list(remove_entry)
			log_and_message_admins("removed entry #[remove_entry["id"]] from the away-site mob pool", usr)
			to_chat(usr, SPAN_GOOD("Removed from the pool."))
