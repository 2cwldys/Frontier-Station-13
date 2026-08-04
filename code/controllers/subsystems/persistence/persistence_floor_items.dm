/*
 * Persistence - Floor Item Positions
 * Saves and restores the position and contents of obj/item instances sitting on station floor turfs.
 * Mirrors Persistent-Bay's turf contents approach but uses SQL rather than BYOND savefiles.
 *
 * On save: records (type, x, y, z, pixel offsets, dir, name, icon_state, recursive contents)
 *          for every floor item not already tracked by the persistent_objects subsystem.
 * On load: wipes all existing untracked floor items, then respawns them from the DB with full
 *          recursive container contents restored via deserializePersistentItem().
 *          If no rows exist (first run), map defaults are left as-is.
 *
 * Container contents (boxes, bags, toolboxes, etc.) are serialized recursively using
 * serializePersistentItem() / deserializePersistentItem() from persistence_mobs.dm.
 *
 * Hooked into SSpersistence Initialize() and Shutdown() / forceSaveAll().
 * Only runs on the SCCV Horizon map.
 */

/**
 * Restore saved floor item positions after the map has loaded.
 * Called from SSpersistence.Initialize(), after turfsInitialize().
 */
/datum/controller/subsystem/persistence/proc/floorItemsInitialize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("floorItemsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, z, pixel_x, pixel_y, dir, name, icon_state, extra FROM ss13_floor_items WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "floorItemsInitialize"))
		qdel(query)
		return

	var/list/saved_items = list()
	while(query.NextRow())
		CHECK_TICK
		saved_items += list(list(
			"type"       = query.item[1],
			"x"          = text2num(query.item[2]),
			"y"          = text2num(query.item[3]),
			"z"          = text2num(query.item[4]),
			"pixel_x"    = text2num(query.item[5]),
			"pixel_y"    = text2num(query.item[6]),
			"dir"        = text2num(query.item[7]),
			"name"       = query.item[8],
			"icon_state" = query.item[9],
			"extra"      = query.item[10]
		))
	qdel(query)

	if(!length(saved_items))
		log_subsystem_persistence_info("Floor items: No saved floor items found, leaving map defaults.")
		return

	// Wipe all existing untracked floor items so we start from a clean state.
	// Ammo casings are skipped -- guns may still hold refs to them and force-qdeling
	// them before their owning gun causes GC leak warnings.
	for(var/obj/item/I in world)
		CHECK_TICK
		if(!isturf(I.loc))
			continue
		if(!I.z)
			continue
		if(persistence_z_manual_blocked(I.z))
			continue // z-level not persisted -- leave its items alone, don't wipe
		if(I.persistent_objects_track_id != 0)
			continue
		if(I in GLOB.persistence_object_track_register)
			continue
		if(istype(I, /obj/item/ammo_casing))
			continue
		try
			qdel(I)
		catch(var/exception/wipe_e)
			log_subsystem_persistence_error("Floor items: Error deleting [I] during wipe: [wipe_e]")

	// Respawn items at their saved positions, restoring container contents recursively
	var/restored = 0
	for(var/list/data in saved_items)
		CHECK_TICK
		if(persistence_z_manual_blocked(data["z"]))
			continue
		restored += _floorItemsRestoreRow(data)

	log_subsystem_persistence_info("Floor items: Restored [restored] floor items for map [SSatlas.current_map.path].")

/**
 * Restore one saved floor-item row onto the world. Returns 1 on success,
 * 0 on any skip/failure. Shared by the boot restore (floorItemsInitialize())
 * and the per-ship-Z apply (floorItemsApplyZ()).
 */
/datum/controller/subsystem/persistence/proc/_floorItemsRestoreRow(list/data)
	PRIVATE_PROC(TRUE)
	var/turf/T = locate(data["x"], data["y"], data["z"])
	if(!T || !T.z)
		return 0
	// Skip turfs with closed closets -- their contents are handled by closet content serialization,
	// and the closet LateInitialize would suck restored floor items in, causing duplication.
	var/has_closed_closet = FALSE
	for(var/obj/structure/closet/C in T)
		if(!C.opened) { has_closed_closet = TRUE; break }
	if(!has_closed_closet)
		for(var/obj/structure/machinery/suit_storage_unit/SSU in T)
			has_closed_closet = TRUE; break
	if(has_closed_closet)
		return 0

	var/obj/item/I
	try
		var/extra_str = data["extra"]
		if(extra_str && istext(extra_str) && length(extra_str) > 2 && extra_str != "null")
			var/list/item_tree = json_decode(extra_str)
			I = deserializePersistentItem(item_tree, T)
#ifdef PERSISTENCE_FLOOR_ITEM_DEBUG
			if(istype(I, /obj/item/clothing))
				var/obj/item/clothing/dbg_c = I
				log_subsystem_persistence_info("FloorItemDebug: restored '[I]' ([data["type"]]) WITH state -- faction_tag_uid=[dbg_c.faction_tag_uid || "null"], color=[dbg_c.color || "null"]")
#endif
		else
			var/path = text2path(data["type"])
			if(path && ispath(path, /obj/item))
				I = new path(T)
#ifdef PERSISTENCE_FLOOR_ITEM_DEBUG
				if(ispath(path, /obj/item/clothing))
					log_subsystem_persistence_info("FloorItemDebug: restored '[data["type"]]' with NO extra blob -- spawned stateless, any faction tag/colour is gone. extra was: [isnull(data["extra"]) ? "NULL" : "'[data["extra"]]'"]")
#endif
	catch(var/exception/floor_e)
		log_subsystem_persistence_error("Floor items: Failed to restore [data["type"]] at ([data["x"]],[data["y"]],[data["z"]]): [floor_e] -- extra was: [isnull(data["extra"]) ? "NULL" : "'[data["extra"]]'"]")
		return 0

	if(!I || QDELETED(I))
		return 0

	if(!isnull(data["pixel_x"])) I.pixel_x = text2num(data["pixel_x"])
	if(!isnull(data["pixel_y"])) I.pixel_y = text2num(data["pixel_y"])
	if(!isnull(data["dir"]))     I.dir     = text2num(data["dir"])
	if(data["name"])    I.name    = data["name"]
	if(data["icon_state"]) I.icon_state = data["icon_state"]
	return 1

/**
 * Apply saved ship-scoped floor items to a freshly loaded ship Z. Rows were
 * already remapped to this z by remapShipRows(). A ship that has never been
 * saved has no rows here -- nothing to restore, so the template's own
 * authored debris is left untouched (pristine-load case). Once a saved
 * snapshot DOES exist, the template's freshly-spawned debris is wiped first
 * (mirrors floorItemsInitialize()'s boot-time wipe above) so the saved rows
 * are the sole source of truth -- without this, every retrieve from the
 * second one onward stacks the template's fresh copies on top of whatever
 * got saved last cycle, compounding duplication with every stash/retrieve.
 */
/datum/controller/subsystem/persistence/proc/floorItemsApplyZ(z, scope)
	if(!databaseCheckConnection("floorItemsApplyZ"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, z, pixel_x, pixel_y, dir, name, icon_state, extra FROM ss13_floor_items WHERE map_path = :map_path AND z = :z",
		list("map_path" = scope, "z" = z)
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "floorItemsApplyZ"))
		qdel(query)
		return
	var/list/saved_items = list()
	while(query.NextRow())
		CHECK_TICK
		saved_items += list(list(
			"type"       = query.item[1],
			"x"          = text2num(query.item[2]),
			"y"          = text2num(query.item[3]),
			"z"          = text2num(query.item[4]),
			"pixel_x"    = text2num(query.item[5]),
			"pixel_y"    = text2num(query.item[6]),
			"dir"        = text2num(query.item[7]),
			"name"       = query.item[8],
			"icon_state" = query.item[9],
			"extra"      = query.item[10]
		))
	qdel(query)

	if(!length(saved_items))
		// Pristine template, never saved before -- nothing to restore, and
		// wiping here would strip the template's own authored debris for no
		// reason. Leave it as-is; the next Stash captures it as the baseline.
		return

	for(var/obj/item/I in world)
		CHECK_TICK
		if(I.z != z)
			continue
		if(!isturf(I.loc))
			continue
		if(I.persistent_objects_track_id != 0)
			continue
		if(I in GLOB.persistence_object_track_register)
			continue
		if(istype(I, /obj/item/ammo_casing))
			continue
		try
			qdel(I)
		catch(var/exception/wipe_e)
			log_subsystem_persistence_error("Floor items: Error deleting [I] during ship Z wipe: [wipe_e]")

	var/restored = 0
	for(var/list/data in saved_items)
		CHECK_TICK
		restored += _floorItemsRestoreRow(data)
	log_subsystem_persistence_info("Floor items: Applied [restored] ship floor items to z=[z] ([scope]).")

/**
 * Build the bulk-INSERT row string for one floor item, keyed under its z's
 * persistence scope (ship scope for deployed ship Zs). Returns null if the
 * item should not be saved. Shared by floorItemsFinalize() and
 * floorItemsFinalizeZ().
 */
/datum/controller/subsystem/persistence/proc/_floorItemRow(obj/item/I)
	PRIVATE_PROC(TRUE)
#ifdef PERSISTENCE_FLOOR_ITEM_DEBUG
	// Only trace faction-tagged clothing -- the case being chased. Every early
	// return below is a silent drop, and from outside this proc they're all
	// indistinguishable from "saved fine but restored blank".
	var/fi_debug = FALSE
	if(istype(I, /obj/item/clothing))
		var/obj/item/clothing/dbg_c = I
		fi_debug = !isnull(dbg_c.faction_tag_uid)
	#define FI_TRACE(reason) if(fi_debug) { log_subsystem_persistence_info("FloorItemDebug: '[I]' ([I.type]) at ([I.x],[I.y],[I.z]) -- [reason]") }
#else
	#define FI_TRACE(reason)
#endif
	if(!isturf(I.loc))
		FI_TRACE("DROPPED: not directly on a turf (loc=[I.loc])")
		return null
	if(!I.z)
		FI_TRACE("DROPPED: no z")
		return null
	if(persistence_z_manual_blocked(I.z))
		FI_TRACE("DROPPED: z manually blocked")
		return null
	if(persistence_area_excluded(I))
		FI_TRACE("DROPPED: area excluded")
		return null
	if(I.persistent_objects_track_id != 0)
		FI_TRACE("DROPPED: already a tracked object (id=[I.persistent_objects_track_id])")
		return null
	if(I in GLOB.persistence_object_track_register)
		FI_TRACE("DROPPED: in the tracked-object register")
		return null
	if(istype(I, /obj/item/ammo_casing))
		return null  // Bullet casings are transient combat debris
	if(istype(I, /obj/item/trash/cigbutt))
		return null  // Cigarette/cigar butts are transient litter
	if(istype(I, /obj/item/material/shard))
		return null  // Glass/material shards are transient debris

	var/name_str  = (I.name != initial(I.name)) ? copytext(I.name, 1, 129) : null
	var/icon_str  = (I.icon_state != initial(I.icon_state)) ? copytext(I.icon_state, 1, 65) : null
	var/list/serialized = serializePersistentItem(I)
	var/extra_str = null
	if(length(serialized) > 1)
		// Handed to the query as a BOUND PARAMETER -- never string-escaped into
		// the SQL text. `extra` is a JSON column, so MariaDB validates it on
		// insert and rejects the whole statement if it doesn't parse. The old
		// hand-rolled escaping (doubling backslashes, then single quotes) had to
		// survive a round-trip through the SQL literal parser intact, and any
		// item whose blob contained nested JSON -- fingerprints and reagents are
		// both stored via a nested json_encode(), so effectively anything a
		// player has touched -- carried \" sequences that could come out
		// malformed. Because rows are inserted in chunks of 200, a single bad
		// blob failed the entire chunk, silently wiping the saved state of up to
		// 200 floor items at once. They then restored via the stateless
		// `new path(T)` fallback: the item returns, stripped of its faction tag
		// and colour.
		extra_str = json_encode(serialized)
	FI_TRACE("SAVED: serialized keys=[length(serialized)], obj_content=[serialized["obj_content"] ? "yes" : "NO"], extra len=[isnull(extra_str) ? "NULL (item will restore blank!)" : "[length(extra_str)]"]")

	return list(
		"map_path"   = persistence_scope_for_z(I.z),
		"type"       = "[I.type]",
		"x"          = I.x,
		"y"          = I.y,
		"z"          = I.z,
		"pixel_x"    = I.pixel_x,
		"pixel_y"    = I.pixel_y,
		"dir"        = I.dir,
		"name"       = name_str,
		"icon_state" = icon_str,
		"extra"      = extra_str
	)
#undef FI_TRACE

/// Chunked bulk INSERT of collected floor-item rows, every value passed as a
/// BOUND PARAMETER rather than interpolated into the SQL text -- see the note
/// in _floorItemRow() for why hand-escaping the JSON `extra` column was
/// silently destroying whole chunks of saved item state.
/datum/controller/subsystem/persistence/proc/_floorItemsFlush(list/value_rows, log_context)
	PRIVATE_PROC(TRUE)
	var/saved = length(value_rows)
	if(!saved)
		return 0
	var/chunk_size = 200
	for(var/i = 1 to saved step chunk_size)
		var/end = min(i + chunk_size - 1, saved)
		var/list/placeholders = list()
		var/list/params = list()
		var/n = 0
		for(var/j = i to end)
			var/list/row = value_rows[j]
			if(!islist(row))
				continue
			placeholders += "(:mp[n],:ty[n],:x[n],:y[n],:z[n],:px[n],:py[n],:dr[n],:nm[n],:ic[n],:ex[n])"
			params["mp[n]"] = row["map_path"]
			params["ty[n]"] = row["type"]
			params["x[n]"]  = row["x"]
			params["y[n]"]  = row["y"]
			params["z[n]"]  = row["z"]
			params["px[n]"] = row["pixel_x"]
			params["py[n]"] = row["pixel_y"]
			params["dr[n]"] = row["dir"]
			params["nm[n]"] = row["name"]
			params["ic[n]"] = row["icon_state"]
			params["ex[n]"] = row["extra"]
			n++
		if(!n)
			continue
		var/datum/db_query/bulk = SSdbcore.NewQuery(
			"INSERT INTO ss13_floor_items (map_path,type,x,y,z,pixel_x,pixel_y,dir,name,icon_state,extra) VALUES [placeholders.Join(",")]",
			params
		)
		bulk.Execute()
		databaseCheckQueryResult(bulk, "[log_context] bulk insert")
		qdel(bulk)
		CHECK_TICK
	return saved

/**
 * Save the position and recursive contents of all untracked floor items to the database.
 * Called from SSpersistence.Shutdown() and forceSaveAll().
 */
/datum/controller/subsystem/persistence/proc/floorItemsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("floorItemsFinalize"))
		return

	// Wipe-and-reinsert, per scope: the current map's rows, plus every
	// deployed ship's scope (the world sweep below re-collects ship-Z items
	// under their ship scope -- without this wipe they would duplicate, as
	// the table has no coordinate uniqueness).
	var/datum/db_query/wipe_q = SSdbcore.NewQuery(
		"DELETE FROM ss13_floor_items WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	wipe_q.Execute()
	databaseCheckQueryResult(wipe_q, "floorItemsFinalize delete")
	qdel(wipe_q)
	for(var/ship_z in GLOB.persistence_ship_z)
		var/datum/db_query/ship_wipe_q = SSdbcore.NewQuery(
			"DELETE FROM ss13_floor_items WHERE map_path = :map_path",
			list("map_path" = GLOB.persistence_ship_z[ship_z])
		)
		ship_wipe_q.Execute()
		databaseCheckQueryResult(ship_wipe_q, "floorItemsFinalize ship scope delete")
		qdel(ship_wipe_q)

	// Collect all floor item rows then bulk INSERT in chunks. Each item is
	// isolated in its own try/catch -- without this, one item throwing during
	// serialization (serializePersistentItem() has no internal guard) aborts
	// this whole loop, which skips _floorItemsFlush() entirely and silently
	// discards every OTHER floor item's saved state for the whole map, not
	// just the one bad item. Mirrors objectsGetTrackContent()'s existing
	// per-object guard for the tracked-object save path.
	var/list/value_rows = list()
	for(var/obj/item/I in world)
		CHECK_TICK
		try
			var/list/row = _floorItemRow(I)
			if(row)
				value_rows += list(row)
		catch(var/exception/e)
			log_subsystem_persistence_error("Floor items: Failed to serialize [I] ([I.type]) for save: [e]")

	var/saved = _floorItemsFlush(value_rows, "floorItemsFinalize")
	log_subsystem_persistence_info("Floor items: Saved [saved] floor items for map [SSatlas.current_map.path].")

/**
 * Per-Z floor item save for a deployed ship Z -- wipe the ship scope's rows,
 * then re-collect items on that z only. Caller must still have the z
 * registered in GLOB.persistence_ship_z so rows key under the ship scope.
 */
/datum/controller/subsystem/persistence/proc/floorItemsFinalizeZ(z, scope)
	if(!databaseCheckConnection("floorItemsFinalizeZ"))
		return
	var/datum/db_query/wipe_q = SSdbcore.NewQuery(
		"DELETE FROM ss13_floor_items WHERE map_path = :map_path",
		list("map_path" = scope)
	)
	wipe_q.Execute()
	databaseCheckQueryResult(wipe_q, "floorItemsFinalizeZ delete")
	qdel(wipe_q)

	var/list/value_rows = list()
	for(var/obj/item/I in world)
		CHECK_TICK
		if(I.z != z)
			continue
		try
			var/list/row = _floorItemRow(I)
			if(row)
				value_rows += list(row)
		catch(var/exception/e)
			log_subsystem_persistence_error("Floor items: Failed to serialize [I] ([I.type]) for ship-Z save: [e]")

	var/saved = _floorItemsFlush(value_rows, "floorItemsFinalizeZ")
	log_subsystem_persistence_info("Floor items: Saved [saved] ship floor items for z=[z] ([scope]).")
