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
		var/turf/T = locate(data["x"], data["y"], data["z"])
		if(!T || !T.z)
			continue
		// Skip turfs with closed closets -- their contents are handled by closet content serialization,
		// and the closet LateInitialize would suck restored floor items in, causing duplication.
		var/has_closed_closet = FALSE
		for(var/obj/structure/closet/C in T)
			if(!C.opened) { has_closed_closet = TRUE; break }
		if(!has_closed_closet)
			for(var/obj/structure/machinery/suit_storage_unit/SSU in T)
				has_closed_closet = TRUE; break
		if(has_closed_closet)
			continue

		var/obj/item/I
		try
			var/extra_str = data["extra"]
			if(extra_str && istext(extra_str) && length(extra_str) > 2 && extra_str != "null")
				var/list/item_tree = json_decode(extra_str)
				I = deserializePersistentItem(item_tree, T)
			else
				var/path = text2path(data["type"])
				if(path && ispath(path, /obj/item))
					I = new path(T)
		catch(var/exception/floor_e)
			log_subsystem_persistence_error("Floor items: Failed to restore [data["type"]] at ([data["x"]],[data["y"]],[data["z"]]): [floor_e]")
			continue

		if(!I || QDELETED(I))
			continue

		if(!isnull(data["pixel_x"])) I.pixel_x = text2num(data["pixel_x"])
		if(!isnull(data["pixel_y"])) I.pixel_y = text2num(data["pixel_y"])
		if(!isnull(data["dir"]))     I.dir     = text2num(data["dir"])
		if(data["name"])    I.name    = data["name"]
		if(data["icon_state"]) I.icon_state = data["icon_state"]
		restored++

	log_subsystem_persistence_info("Floor items: Restored [restored] floor items for map [SSatlas.current_map.path].")

/**
 * Save the position and recursive contents of all untracked floor items to the database.
 * Called from SSpersistence.Shutdown() and forceSaveAll().
 */
/datum/controller/subsystem/persistence/proc/floorItemsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("floorItemsFinalize"))
		return

	var/datum/db_query/wipe_q = SSdbcore.NewQuery(
		"DELETE FROM ss13_floor_items WHERE map_path = :map_path",
		list("map_path" = "[SSatlas.current_map.path]")
	)
	wipe_q.Execute()
	databaseCheckQueryResult(wipe_q, "floorItemsFinalize delete")
	qdel(wipe_q)

	// Collect all floor item rows then bulk INSERT in chunks
	var/list/value_rows = list()
	var/map_escaped = replacetext("[SSatlas.current_map.path]", "'", "''")

	for(var/obj/item/I in world)
		CHECK_TICK
		if(!isturf(I.loc))
			continue
		if(!I.z)
			continue
		if(I.persistent_objects_track_id != 0)
			continue
		if(I in GLOB.persistence_object_track_register)
			continue
		if(istype(I, /obj/item/ammo_casing))
			continue  // Bullet casings are transient combat debris

		var/type_str  = replacetext("[I.type]", "'", "''")
		var/name_str  = (I.name != initial(I.name)) ? replacetext(copytext(I.name, 1, 129), "'", "''") : null
		var/icon_str  = (I.icon_state != initial(I.icon_state)) ? replacetext(copytext(I.icon_state, 1, 65), "'", "''") : null
		var/list/serialized = serializePersistentItem(I)
		var/extra_str = null
		if(length(serialized) > 1)
			var/raw_json = json_encode(serialized)
			// Escape backslashes first (MariaDB interprets \ in SQL strings), then single quotes
			raw_json = replacetext(raw_json, "\\", "\\\\")
			raw_json = replacetext(raw_json, "'", "''")
			extra_str = raw_json

		var/name_sql  = isnull(name_str)  ? "NULL" : "'[name_str]'"
		var/icon_sql  = isnull(icon_str)  ? "NULL" : "'[icon_str]'"
		var/extra_sql = isnull(extra_str) ? "NULL" : "'[extra_str]'"

		value_rows += "('[map_escaped]','[type_str]',[I.x],[I.y],[I.z],[I.pixel_x],[I.pixel_y],[I.dir],[name_sql],[icon_sql],[extra_sql])"

	var/saved = length(value_rows)
	if(saved)
		var/chunk_size = 200
		for(var/i = 1 to saved step chunk_size)
			var/end = min(i + chunk_size - 1, saved)
			var/list/chunk = value_rows.Copy(i, end + 1)
			var/datum/db_query/bulk = SSdbcore.NewQuery(
				"INSERT INTO ss13_floor_items (map_path,type,x,y,z,pixel_x,pixel_y,dir,name,icon_state,extra) VALUES [chunk.Join(",")]"
			)
			bulk.Execute()
			databaseCheckQueryResult(bulk, "floorItemsFinalize bulk insert")
			qdel(bulk)
			CHECK_TICK

	log_subsystem_persistence_info("Floor items: Saved [saved] floor items for map [SSatlas.current_map.path].")
