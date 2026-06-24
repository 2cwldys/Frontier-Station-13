/*
 * Persistence - World Templates
 * Allows admins to capture and restore named snapshots of the station's physical state
 * (turf structure, machinery settings) independently of round-to-round player data.
 *
 * Use case: capture a "clean baseline" and restore it when the station becomes too
 * damaged or cluttered, without touching player money/records/health/inventory.
 *
 * Admin verbs:
 *   - Capture World Template  — save current world state under a name
 *   - Load World Template     — queue a template for apply at next Initialize()
 *   - Load World Template (Immediate) — apply template to live world mid-game
 *   - Delete World Template   — remove a saved template from the database
 *   - List World Templates    — print all templates to admin chat
 */

/**
 * Apply pending template (if any) at round/server startup before normal persistence loads.
 * Called from SSpersistence.Initialize(), before turfsInitialize() and worldstateInitialize().
 */
/datum/controller/subsystem/persistence/proc/templateCheckPending()
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("templateCheckPending"))
		return

	var/datum/db_query/check = SSdbcore.NewQuery(
		"SELECT template_id FROM ss13_template_pending WHERE id = 1 AND map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	check.Execute()
	if(!databaseCheckQueryResult(check, "templateCheckPending") || !check.NextRow())
		qdel(check)
		return
	var/template_id = text2num(check.item[1])
	qdel(check)

	// Clear pending flag first so a crash mid-apply doesn't loop forever
	var/datum/db_query/clear = SSdbcore.NewQuery(
		"DELETE FROM ss13_template_pending WHERE id = 1",
		list()
	)
	clear.Execute()
	qdel(clear)

	// template_id == 0 is the "reset to map default" sentinel — wipe tables, load nothing
	if(template_id == 0)
		log_subsystem_persistence_info("Templates: Default map reset pending. Wiping live worldstate tables.")
		templateWipeLiveTables()
		return

	log_subsystem_persistence_info("Templates: Found pending template ID [template_id]. Applying before init.")
	templateApplyToLiveTables(template_id)

/**
 * Wipe all live worldstate tables for the current map with no replacement data.
 * Used when reverting to map default: the next Initialize() finds empty tables and
 * applies nothing, leaving all turfs/machinery at .dmm-loaded defaults.
 * Also used by templateCheckPending() when template_id == 0 (default-reset sentinel).
 */
/datum/controller/subsystem/persistence/proc/templateWipeLiveTables()
	var/map = "[SSatlas.current_map.path]"
	for(var/table in list("ss13_worldstate_turfs", "ss13_worldstate_objects", "ss13_atmos_zones"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM [table] WHERE map_path = :map_path",
			list("map_path" = map)
		)
		q.Execute()
		databaseCheckQueryResult(q, "templateWipeLiveTables [table]")
		qdel(q)
	var/datum/db_query/del_decals = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_objects WHERE type LIKE '/obj/effect/decal/cleanable%'"
	)
	del_decals.Execute()
	qdel(del_decals)
	log_subsystem_persistence_info("Templates: Wiped all live worldstate tables (map default reset).")

/**
 * Copy template data into the live worldstate tables, replacing current state.
 * Wipes turf changes, worldstate objects, atmos zones, and decals for the current map,
 * then inserts the template snapshot in their place.
 * Does NOT touch player data (economy, records, health, inventory).
 */
/datum/controller/subsystem/persistence/proc/templateApplyToLiveTables(template_id)
	PRIVATE_PROC(TRUE)

	var/map = "[SSatlas.current_map.path]"

	// Wipe live physical state
	for(var/table in list("ss13_worldstate_turfs", "ss13_worldstate_objects", "ss13_atmos_zones"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM [table] WHERE map_path = :map_path",
			list("map_path" = map)
		)
		q.Execute()
		databaseCheckQueryResult(q, "templateApplyToLiveTables delete [table]")
		qdel(q)

	// Wipe cleanable decals from persistent objects (decals are cleanables)
	var/datum/db_query/del_decals = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_objects WHERE type LIKE '/obj/effect/decal/cleanable%'"
	)
	del_decals.Execute()
	qdel(del_decals)

	// Copy template turfs → live turf table
	var/datum/db_query/copy_turfs = SSdbcore.NewQuery(
		{"INSERT INTO ss13_worldstate_turfs (map_path, x, y, z, turf_type, base_type, content, saved_at)
		SELECT :map_path, x, y, z, turf_type, base_type, content, NOW()
		FROM ss13_template_turfs WHERE template_id = :template_id"},
		list("map_path" = map, "template_id" = template_id)
	)
	copy_turfs.Execute()
	databaseCheckQueryResult(copy_turfs, "templateApplyToLiveTables copy turfs")
	qdel(copy_turfs)

	// Copy template worldstate → live worldstate table
	var/datum/db_query/copy_ws = SSdbcore.NewQuery(
		{"INSERT INTO ss13_worldstate_objects (type, x, y, z, content, saved_at)
		SELECT type, x, y, z, content, NOW()
		FROM ss13_template_worldstate WHERE template_id = :template_id"},
		list("template_id" = template_id)
	)
	copy_ws.Execute()
	databaseCheckQueryResult(copy_ws, "templateApplyToLiveTables copy worldstate")
	qdel(copy_ws)

	log_subsystem_persistence_info("Templates: Applied template [template_id] to live tables.")

/**
 * Apply a template directly to the live world mid-game.
 * Changes turfs and machinery state without waiting for a server restart.
 * Expensive — iterates entire world. Call from an admin verb with user confirmation.
 */
/datum/controller/subsystem/persistence/proc/templateApplyNow(template_id)
	if(!databaseCheckConnection("templateApplyNow"))
		return

	// First update the DB tables so a server restart also starts from template
	templateApplyToLiveTables(template_id)

	// Reset all non-default station turfs to their map-original type before applying the template.
	// turfsInitialize() only applies entries that exist in the DB — without this pass, turfs
	// damaged AFTER the template was captured would not be restored (they have no template entry).
	// For next-restart loads this is unnecessary: the .dmm re-loads fresh turf types from the map.
	for(var/turf/T in world)
		if(!is_station_level(T.z))
			continue
		if(T.type != T.baseturf)
			T.ChangeTurf(T.baseturf)
		CHECK_TICK

	// Re-run the worldstate and turf inits against the freshly populated tables
	GLOB.persistence_worldstate_cache = list()
	GLOB.persistence_turfs_cache = list()

	try
		worldstateInitialize()
	catch(var/exception/ws_e)
		log_subsystem_persistence_error("templateApplyNow worldstate error: [ws_e]")

	try
		turfsInitialize()
	catch(var/exception/turfs_e)
		log_subsystem_persistence_error("templateApplyNow turfs error: [turfs_e]")

	log_subsystem_persistence_info("Templates: Live world updated from template [template_id].")

/**
 * Immediately revert the live world to its map-default state.
 * Wipes all worldstate/turf/atmos DB data, resets all station turfs to baseturf,
 * then re-runs worldstate and turf inits against the now-empty tables (so nothing is applied).
 * Result: machinery and turfs match the original .dmm map file.
 * Cannot rebuild physically deconstructed objects — use next-restart revert for a full reset.
 */
/datum/controller/subsystem/persistence/proc/templateRevertToDefault()
	if(!databaseCheckConnection("templateRevertToDefault"))
		return

	// Wipe DB tables — init procs will find nothing to apply
	templateWipeLiveTables()

	// Reset all non-default station turfs to their map-original type
	for(var/turf/T in world)
		if(!is_station_level(T.z))
			continue
		if(T.type != T.baseturf)
			T.ChangeTurf(T.baseturf)
		CHECK_TICK

	GLOB.persistence_worldstate_cache = list()
	GLOB.persistence_turfs_cache = list()

	try
		worldstateInitialize()
	catch(var/exception/ws_e)
		log_subsystem_persistence_error("templateRevertToDefault worldstate error: [ws_e]")

	try
		turfsInitialize()
	catch(var/exception/turfs_e)
		log_subsystem_persistence_error("templateRevertToDefault turfs error: [turfs_e]")

	log_subsystem_persistence_info("Templates: Live world reverted to map defaults.")

// ============================================================
// Admin verbs
// ============================================================

/datum/admins/proc/capture_world_template()
	set name = "Capture World Template"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(SSatlas.current_map.path != "sccv_horizon")
		to_chat(usr, SPAN_WARNING("World templates only supported on SCCV Horizon."))
		return

	var/tname = tgui_input_text(usr, "Enter a name for this template (e.g. 'clean_start'):", "Capture World Template", max_length = 64)
	if(!tname)
		return

	var/desc = tgui_input_text(usr, "Optional description:", "Capture World Template", max_length = 255)

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled."))
		return

	if(!SSpersistence.databaseCheckConnection("capture_world_template"))
		to_chat(usr, SPAN_WARNING("Database connection failed."))
		return

	to_chat(usr, SPAN_NOTICE("Capturing template '[tname]'... (this may take a moment)"))

	// Upsert the template record
	var/datum/db_query/upsert = SSdbcore.NewQuery(
		{"INSERT INTO ss13_world_templates (name, description, map_path, created_at)
		VALUES (:name, :desc, :map_path, NOW())
		ON DUPLICATE KEY UPDATE description = VALUES(description), created_at = NOW()"},
		list("name" = tname, "desc" = desc || "", "map_path" = "[SSatlas.current_map.path]")
	)
	upsert.Execute()
	SSpersistence.databaseCheckQueryResult(upsert, "capture_world_template upsert")
	qdel(upsert)

	// Get the template id
	var/datum/db_query/get_id = SSdbcore.NewQuery(
		"SELECT id FROM ss13_world_templates WHERE name = :name AND map_path = :map_path",
		list("name" = tname, "map_path" = "[SSatlas.current_map.path]")
	)
	get_id.Execute()
	if(!get_id.NextRow())
		qdel(get_id)
		to_chat(usr, SPAN_WARNING("Failed to retrieve template ID after insert."))
		return
	var/template_id = text2num(get_id.item[1])
	qdel(get_id)

	// Wipe old data for this template
	for(var/table in list("ss13_template_turfs", "ss13_template_worldstate"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM [table] WHERE template_id = :tid",
			list("tid" = template_id)
		)
		q.Execute()
		qdel(q)

	// Snapshot turfs — reuse turfsSerializeAndInsert equivalent inline for template table
	var/turf_count = 0
	for(var/turf/simulated/floor/F in world)
		if(!is_station_level(F.z))
			continue
		if(!F.broken && !F.burnt && !F.flooring && !F.color)
			if(F.type == F.baseturf)
				continue
		var/flooring_type = F.flooring ? "[F.flooring.type]" : null
		var/list/content = list("broken"=F.broken, "burnt"=F.burnt, "flooring"=flooring_type, "color"=F.color)
		var/datum/db_query/ins = SSdbcore.NewQuery(
			"INSERT INTO ss13_template_turfs (template_id, x, y, z, turf_type, base_type, content) VALUES (:tid, :x, :y, :z, :tt, :bt, :c)",
			list("tid"=template_id, "x"=F.x, "y"=F.y, "z"=F.z, "tt"="[F.type]", "bt"="[F.baseturf]", "c"=json_encode(content))
		)
		ins.Execute()
		qdel(ins)
		turf_count++
		CHECK_TICK

	for(var/turf/simulated/wall/W in world)
		if(!is_station_level(W.z))
			continue
		if(W.type == W.baseturf && W.health >= W.maxhealth)
			continue
		var/mat_name = W.material ? W.material.name : null
		var/reinf_name = W.reinf_material ? W.reinf_material.name : null
		var/list/content = list("material"=mat_name, "reinf_material"=reinf_name, "health"=W.health, "construction_stage"=W.construction_stage)
		var/datum/db_query/ins = SSdbcore.NewQuery(
			"INSERT INTO ss13_template_turfs (template_id, x, y, z, turf_type, base_type, content) VALUES (:tid, :x, :y, :z, :tt, :bt, :c)",
			list("tid"=template_id, "x"=W.x, "y"=W.y, "z"=W.z, "tt"="[W.type]", "bt"="[W.baseturf]", "c"=json_encode(content))
		)
		ins.Execute()
		qdel(ins)
		turf_count++
		CHECK_TICK

	// Snapshot worldstate machinery
	var/ws_count = 0
	for(var/obj/structure/machinery/M in world)
		if(!is_station_level(M.z))
			continue
		var/list/content = M.worldstate_get_content()
		if(!length(content))
			continue
		var/turf/T = get_turf(M)
		var/datum/db_query/ins = SSdbcore.NewQuery(
			"INSERT INTO ss13_template_worldstate (template_id, type, x, y, z, content) VALUES (:tid, :type, :x, :y, :z, :c)",
			list("tid"=template_id, "type"="[M.type]", "x"=T.x, "y"=T.y, "z"=T.z, "c"=json_encode(content))
		)
		ins.Execute()
		qdel(ins)
		ws_count++
		CHECK_TICK

	var/result = "Template '[tname]' captured: [turf_count] turfs, [ws_count] machinery objects."
	to_chat(usr, SPAN_GOOD(result))
	log_and_message_admins("captured world template '[tname]'. [result]", usr)
	feedback_add_details("admin_verb","CWT")

/datum/admins/proc/load_world_template_next_start()
	set name = "Load World Template (Next Restart)"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/list/templates = _get_template_list()
	if(!length(templates))
		to_chat(usr, SPAN_WARNING("No templates saved for this map."))
		return

	var/chosen = tgui_input_list(usr, "Select a template to load on next server restart:", "Load World Template", templates)
	if(!chosen)
		return

	var/template_id = templates[chosen]
	var/confirm = tgui_alert(usr, "Queue template '[chosen]' to load on next restart? Station physical state will be reset. Player data (money, records, health, inventory) is NOT affected.", "Confirm Load Template", list("Queue It", "Cancel"))
	if(confirm != "Queue It")
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_template_pending (id, template_id, map_path) VALUES (1, :tid, :map_path)
		ON DUPLICATE KEY UPDATE template_id = VALUES(template_id), map_path = VALUES(map_path)"},
		list("tid" = template_id, "map_path" = "[SSatlas.current_map.path]")
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "load_world_template_next_start")
	qdel(q)

	to_world(FONT_LARGE(EXAMINE_BLOCK_RED("World template '[chosen]' queued for next server restart. Station will be physically reset.")))
	log_and_message_admins("queued world template '[chosen]' (ID [template_id]) for next restart", usr)
	feedback_add_details("admin_verb","LWTNS")

/datum/admins/proc/load_world_template_immediate()
	set name = "Load World Template (Immediate)"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/list/templates = _get_template_list()
	if(!length(templates))
		to_chat(usr, SPAN_WARNING("No templates saved for this map."))
		return

	var/chosen = tgui_input_list(usr, "Select a template to apply RIGHT NOW:", "Load World Template (Immediate)", templates)
	if(!chosen)
		return

	var/template_id = templates[chosen]
	var/confirm = tgui_alert(usr, "Apply template '[chosen]' IMMEDIATELY? This will change turfs and machinery mid-game. Player data is NOT affected. This operation is slow.", "Confirm Immediate Load", list("Apply Now", "Cancel"))
	if(confirm != "Apply Now")
		return

	to_world(FONT_LARGE(EXAMINE_BLOCK_RED("World template '[chosen]' is being applied. Station physical state is resetting...")))
	log_and_message_admins("applied world template '[chosen]' (ID [template_id]) immediately", usr)

	SSpersistence.templateApplyNow(template_id)

	to_world(FONT_LARGE(EXAMINE_BLOCK_RED("World template '[chosen]' applied. Station physical state has been reset.")))
	feedback_add_details("admin_verb","LWTI")

/datum/admins/proc/delete_world_template()
	set name = "Delete World Template"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/list/templates = _get_template_list()
	if(!length(templates))
		to_chat(usr, SPAN_WARNING("No templates saved for this map."))
		return

	var/chosen = tgui_input_list(usr, "Select a template to DELETE:", "Delete World Template", templates)
	if(!chosen)
		return

	var/confirm = tgui_alert(usr, "Permanently delete template '[chosen]'? This cannot be undone.", "Confirm Delete", list("Delete", "Cancel"))
	if(confirm != "Delete")
		return

	var/template_id = templates[chosen]
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_world_templates WHERE id = :tid",
		list("tid" = template_id)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "delete_world_template")
	qdel(q)

	to_chat(usr, SPAN_GOOD("Template '[chosen]' deleted."))
	log_and_message_admins("deleted world template '[chosen]' (ID [template_id])", usr)
	feedback_add_details("admin_verb","DWT")

/datum/admins/proc/list_world_templates()
	set name = "List World Templates"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, name, description, created_at FROM ss13_world_templates WHERE map_path = :map_path ORDER BY created_at DESC",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	q.Execute()

	var/output = "World Templates for [SSatlas.current_map.path]:\n"
	var/count = 0
	while(q.NextRow())
		output += "  [q.item[2]] (ID [q.item[1]]) — [q.item[4]] — [q.item[3] || "(no description)"]\n"
		count++
	qdel(q)

	if(!count)
		output += "  (none)"
	to_chat(usr, output)

/datum/admins/proc/revert_to_map_default()
	set name = "Revert to Map Default"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(SSatlas.current_map.path != "sccv_horizon")
		to_chat(usr, SPAN_WARNING("Map default revert only supported on SCCV Horizon."))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled."))
		return

	if(!SSpersistence.databaseCheckConnection("revert_to_map_default"))
		to_chat(usr, SPAN_WARNING("Database connection failed."))
		return

	var/mode = tgui_alert(usr,
		"Reset the station to its original map state?\n\nThis wipes all worldstate, turf changes, atmos zones, and decals. Player data (credits, records, health, inventory) is NOT affected.\n\n• Next Restart — wipes DB now; map reloads fresh on next server boot (safest, rebuilds deconstructed structures).\n• Immediate — resets turfs and machinery mid-game (fast but cannot rebuild deconstructed structures/objects).",
		"Revert to Map Default",
		list("Next Restart", "Immediate", "Cancel")
	)

	if(mode == "Cancel" || !mode)
		return

	if(mode == "Next Restart")
		// Queue a default-reset sentinel (template_id=0) so templateCheckPending() wipes tables
		// at next startup before any init reads them, even if periodic saves run in between.
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT INTO ss13_template_pending (id, template_id, map_path) VALUES (1, 0, :map_path)
			ON DUPLICATE KEY UPDATE template_id = 0, map_path = VALUES(map_path)"},
			list("map_path" = "[SSatlas.current_map.path]")
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "revert_to_map_default queue")
		qdel(q)
		// Also wipe DB now so if someone reads the DB before restart it looks clean
		SSpersistence.templateWipeLiveTables()
		to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Station physical state queued to reset to map default on next server restart. Player data is NOT affected.")))
		log_and_message_admins("queued map default reset for next restart", usr)
		feedback_add_details("admin_verb","RTMD_NR")
		return

	// Immediate mode
	var/confirm = tgui_alert(usr,
		"Apply IMMEDIATELY? This resets all turfs and machinery but cannot rebuild deconstructed structures or remove scattered objects. Proceed?",
		"Confirm Immediate Reset",
		list("Reset Now", "Cancel")
	)
	if(confirm != "Reset Now")
		return

	to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Station physical state is being reset to map defaults...")))
	log_and_message_admins("applied immediate map default reset", usr)

	SSpersistence.templateRevertToDefault()

	to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Station physical state has been reset to map defaults. Player data is unchanged.")))
	feedback_add_details("admin_verb","RTMD_IMM")

/// Internal: returns an associative list of [template_name] = template_id for the current map.
/datum/admins/proc/_get_template_list()
	var/list/result = list()
	if(!GLOB.config.sql_enabled || !SSpersistence.databaseCheckConnection("_get_template_list"))
		return result
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, name FROM ss13_world_templates WHERE map_path = :map_path ORDER BY created_at DESC",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	q.Execute()
	while(q.NextRow())
		result[q.item[2]] = text2num(q.item[1])
	qdel(q)
	return result
