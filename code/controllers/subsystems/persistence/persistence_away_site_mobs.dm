/*
 * Persistence - Away Site Mob Presets
 * Admin-authored, DB-backed (ss13_away_site_mob_presets) pool of hostile NPC
 * presets (persistence_hostile_npcs.dm) eligible to auto-populate a freshly
 * generated away site as long as it isn't already spoken for -- an active
 * mission's target sector, already claimed by a powered faction beacon, or a
 * template that already ships its own hand-placed fauna_spawner. Mirrors the
 * exact cache/Initialize()/admin-verb shape the other persistence_*.dm
 * preset files use.
 *
 * Each pool entry can optionally be scoped to one specific away-site
 * template id (template_id) -- null means "any template," matching every
 * pre-existing row. This is what actually lets an admin pick WHICH away
 * sites get pirates rather than sharing one flat pool across every template
 * on the map: a template with no matching entry (scoped or wildcard) simply
 * gets nothing.
 *
 * Consumed by: maps/_common/mapsystem/map.dm's build_away_sites() (the
 * boot-time RNG pool) and build_pinned_away_sites() (every reboot's reload of
 * a pinned site -- e.g. the colony radio's "station" template, which is
 * always pinned and would otherwise only ever get pirates once, at
 * creation), and persistence_factions.dm's _spawn_away_site_for_template()
 * (runtime on-demand generation) -- all three call
 * maybe_populate_away_site_with_pirates() right after a site's Z and
 * template id are both known.
 */

/// Cached away-site mob presets: list of list(id, preset_id, template_id).
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
		"SELECT id, preset_id, template_id FROM ss13_away_site_mob_presets WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "awaySiteMobPresetsInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.away_site_mob_presets += list(list(
			"id"          = text2num(query.item[1]),
			"preset_id"   = text2num(query.item[2]),
			"template_id" = query.item[3] || null
		))
	qdel(query)
	log_subsystem_persistence_info("Away site mob presets: loaded [length(GLOB.away_site_mob_presets)] preset(s).")

/**
 * Populates a freshly-generated (or freshly-reloaded pinned) away site Z
 * with 1-3 hostile NPCs drawn from the admin-authored pool, unless it's an
 * active mission's target sector, already claimed by a powered faction
 * beacon, a template that already ships its own hand-placed fauna_spawner,
 * or -- once template_id is applied -- simply has no matching pool entry at
 * all. Safe to call for any Z -- silently does nothing if none of the above
 * apply or no pool entry matches this template.
 */
/proc/maybe_populate_away_site_with_pirates(z, template_id)
	if(!z)
		return
	if(is_active_mission_sector(z))
		return
	if(get_owning_faction_beacon(z))
		return
	if(islist(GLOB.fauna_spawners))
		for(var/obj/effect/fauna_spawner/existing in GLOB.fauna_spawners)
			if(existing.z == z)
				return // template already ships its own hand-placed fauna
	var/list/eligible = list()
	for(var/list/entry in GLOB.away_site_mob_presets)
		if(!entry["template_id"] || entry["template_id"] == template_id)
			eligible += list(entry)
	if(!length(eligible))
		return
	var/spawn_count = rand(1, 3)
	for(var/i in 1 to spawn_count)
		var/list/entry = pick(eligible)
		var/turf/T = find_mission_spawn_turf(z)
		if(T)
			spawn_hostile_npc_from_preset(entry["preset_id"], T)

/datum/admins/proc/manage_away_site_mob_presets()
	set name = "Modify Away Site Mobs"
	set category = "Persistence.Away Sites & Missions"
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
			var/scope_text = entry["template_id"] ? "[entry["template_id"]] only" : "any template"
			msg += "  #[entry["id"]] -- [preset ? preset["name"] : "(missing preset #[entry["preset_id"]])"] ([scope_text])\n"
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

			var/list/template_options = list("(Any Template)" = "")
			for(var/site_id in SSmapping.away_sites_templates)
				var/datum/map_template/ruin/away_site/site = SSmapping.away_sites_templates[site_id]
				template_options["[site_id] -- [site.name]"] = site_id
			var/template_pick = tgui_input_list(usr, "Restrict '[picked_preset["name"]]' to which away-site template? Pick '(Any Template)' for the current shared-pool behavior.", "Modify Away Site Mobs", template_options)
			if(isnull(template_pick))
				continue
			var/chosen_template_id = template_options[template_pick]

			var/datum/db_query/q = SSdbcore.NewQuery(
				"INSERT INTO ss13_away_site_mob_presets (map_path, preset_id, template_id) VALUES (:mp, :preset, :template)",
				list("mp" = "[SSatlas.current_map.path]", "preset" = picked_preset["id"], "template" = chosen_template_id || null)
			)
			q.Execute()
			SSpersistence.databaseCheckQueryResult(q, "manage_away_site_mob_presets add")
			var/new_id = text2num(q.last_insert_id)
			qdel(q)

			GLOB.away_site_mob_presets += list(list("id" = new_id, "preset_id" = picked_preset["id"], "template_id" = chosen_template_id || null))
			log_and_message_admins("added '[picked_preset["name"]]' to the away-site mob pool ([chosen_template_id || "any template"])", usr)
			to_chat(usr, SPAN_GOOD("Added '[picked_preset["name"]]' to the pool ([chosen_template_id ? "[chosen_template_id] only" : "any template"])."))

		if(choice == "Remove Preset from Pool")
			if(!length(GLOB.away_site_mob_presets))
				to_chat(usr, SPAN_NOTICE("Pool is empty."))
				continue
			var/list/remove_choices = list()
			for(var/list/entry in GLOB.away_site_mob_presets)
				var/list/preset = get_hostile_npc_preset(entry["preset_id"])
				var/scope_text = entry["template_id"] ? "[entry["template_id"]] only" : "any template"
				remove_choices["#[entry["id"]] -- [preset ? preset["name"] : "(missing preset #[entry["preset_id"]])"] ([scope_text])"] = entry
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
