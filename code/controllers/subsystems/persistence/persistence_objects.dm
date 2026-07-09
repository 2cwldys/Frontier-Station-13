/**
 * Initializes persistent objects.
 * This includes cleaning up expired objects from the database and instanciating all active tracks.
 */
/datum/controller/subsystem/persistence/proc/objectsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_object_track_register = list()

	// Delete all persistent objects in the database that have expired and have passed the cleanup grace period (PERSISTENT_EXPIRATION_CLEANUP_DELAY_DAYS)
	try
		objectsDatabaseCleanEntries()
	catch(var/exception/clean_e)
		log_subsystem_persistence_error("Persistent objects: cleanup pass failed: [clean_e]")

	// Retrieve all persistent data that is not expired
	var/list/persistent_data = list()
	try
		persistent_data = objectsDatabaseGetActiveEntries()
	catch(var/exception/fetch_e)
		log_subsystem_persistence_error("Persistent objects: failed to fetch active entries: [fetch_e]")
	log_subsystem_persistence_info("Persistent objects: Retrieved [length(persistent_data)] entries for instancing this round.")

	// Instantiate all remaining entries based of their type
	// Assign persistence related vars found in /obj, apply content and add to live tracking list.
	for (var/data in persistent_data)
		CHECK_TICK
		try
			var/typepath = text2path(data["type"])
			if (!ispath(typepath)) // Type checking
				continue
			// Create at saved location so Initialize() has a valid turf (avoids null.is_hole on cables etc.)
			var/nx = text2num(data["x"])
			var/ny = text2num(data["y"])
			var/nz = text2num(data["z"])
			if(persistence_z_excluded(nz)) continue
			var/turf/spawn_turf = (nx && ny && nz) ? locate(nx, ny, nz) : null
			if(!spawn_turf)
				log_subsystem_persistence_error("Persistent objects: Cannot locate saved position for [data["type"]] (id=[data["id"]]) at ([data["x"]],[data["y"]],[data["z"]]) -- skipping.")
				continue
			var/obj/instance
			if(ispath(typepath, /obj/structure/lattice))
				// Create in null space to bypass check_for_duplicates, then move to position.
				instance = new typepath()
				if(!instance || QDELETED(instance))
					objectsDatabaseExpireEntry(data["id"])
					continue
				var/obj/structure/lattice/existing_lattice = null
				for(var/obj/structure/lattice/L in spawn_turf)
					if(L.type == typepath) { existing_lattice = L; break }
				if(existing_lattice)
					qdel(instance)
					instance = existing_lattice
				else
					instance.forceMove(spawn_turf)
			else
				instance = new typepath(spawn_turf)
				if(!instance || QDELETED(instance))
					var/obj/existing = null
					for(var/obj/O in spawn_turf)
						if(O.type == typepath) { existing = O; break }
					if(existing)
						existing.persistent_objects_track_id = text2num(data["id"])
						objectsRegisterTrack(existing, data["author_ckey"])
					else
						objectsDatabaseExpireEntry(data["id"])
					continue
			instance.persistent_objects_track_id = data["id"]
			objectsApplyTrackContent(instance, data["content"], data["x"], data["y"], data["z"])
			objectsRegisterTrack(instance, data["author_ckey"])
		catch(var/exception/e)
			log_subsystem_persistence_error("Persistent objects: Failed to instantiate [data["type"]] (id=[data["id"]]): [e]")

	try
		for(var/obj/structure/ladder/L in world)
			if(!(L.allowed_directions & DOWN)) continue
			if(L.target_down) continue
			var/turf/LT = get_turf(L)
			if(!LT) continue
			var/turf/below = GET_TURF_BELOW(LT)
			if(!below) continue
			for(var/obj/structure/ladder/BL in below)
				if(BL.allowed_directions & UP)
					L.target_down = BL
					BL.target_up = L
					break
	catch(var/exception/ladder_e)
		log_subsystem_persistence_error("Persistent objects: ladder relink pass failed: [ladder_e]")

/**
 * Finalize persistent object tracking.
 * Adds new persistent objects, removes no longer existing persistent objects and updates changed persistent objects in the database.
 */
/datum/controller/subsystem/persistence/proc/objectsFinalize()
	PRIVATE_PROC(TRUE)

	// Subsystem shutdown:
	// Create new persistent records for objects that have been created in the round
	// Update tracked objects that have an ID (already existing from previous rounds)
	// Delete persistent records that no longer exist in the registry (removed during the round)

	// Run checks on each track that might prevent further persistence
	for (var/obj/track as anything in GLOB.persistence_object_track_register)
		CHECK_TICK
		var/turf/T = get_turf(track)
		if(!T || !T.z || persistence_z_excluded(T.z)) // Skip invalid or non-persistent Z levels
			objectsDeregisterTrack(track)
			continue
		if(isitem(track) && !isturf(track.loc)) // Items inside a mob/container are the inventory system's job, not a floor-object track
			objectsDeregisterTrack(track)

	var/created = 0
	var/updated = 0
	var/expired = 0

	// Get already stored data before saving new tracks so we can compare what has been updated or removed during the round.
	var/list/existing_data = objectsDatabaseGetActiveEntries()

	for (var/obj/track as anything in GLOB.persistence_object_track_register)
		CHECK_TICK
		if (track.persistent_objects_track_id == 0)
			// Tracked object has no ID meaning it is new, create a new persistent record for it
			objectsDatabaseAddEntry(track)
			created++

	// Find tracks that have been removed during the round by trying to find the track by database ID
	// If we find the track, we need to check if it requires an update instead
	for (var/record in existing_data)
		var/found = FALSE
		for (var/obj/track as anything in GLOB.persistence_object_track_register)
			CHECK_TICK
			if (record["id"] == track.persistent_objects_track_id)
				// A track with the same ID has been found in the register, it still exists, check if we need to update it instead
				found = TRUE // Prevent expiration of track
				var/changed = FALSE
				var/turf/T = get_turf(track)
				if (T && T.x != record["x"])
					changed = TRUE
				else if (T && T.y != record["y"])
					changed = TRUE
				else if (T && T.z != record["z"])
					changed = TRUE
				else if (objectsGetTrackContent(track) != record["content"])
					changed = TRUE
				if (changed)
					objectsDatabaseUpdateEntry(track)
					updated++
				break // Track found (and perhaps updated), break off loop search as it won't need to be deleted anyways
		if (!found)
			// No track with the same ID has been found in the register, remove it from the database (expire)
			objectsDatabaseExpireEntry(record["id"])
			expired++

	log_subsystem_persistence_info("Persistent objects: Created [created], updated [updated] and expired [expired] tracks.")

/**
 * Safely get JSON persistent content of track.
 * RETURN: JSON formatted content of track or null if an exception occured.
 */
/datum/controller/subsystem/persistence/proc/objectsGetTrackContent(obj/track)
	PRIVATE_PROC(TRUE)
	var/result = json_encode(list("__dir" = track.dir, "__anchored" = track.anchored))
	try
		var/list/content = track.persistent_objects_get_content()
		if(!islist(content))
			content = list()
		content["__dir"]      = track.dir
		content["__anchored"] = track.anchored
		result = json_encode(content)
	catch(var/exception/e)
		log_subsystem_persistence_error("Error during json serialization for persistent object. Failed to get/encode track content: [e]")
	return result

/**
 * Safely apply persistent content to track.
 * PARAMS:
 * 	track = Object to apply content to.
 *  json = Custom persistent content JSON to be applied.
 *	x,y,z = x-y-z coordinates of object, can be null.
 */
/datum/controller/subsystem/persistence/proc/objectsApplyTrackContent(obj/track, json, x, y, z)
	PRIVATE_PROC(TRUE)
	try
		var/list/content = json_decode(json)
		track.persistent_objects_apply_content(content, x, y, z)
		if(islist(content) && ("__dir" in content))
			track.dir = text2num(content["__dir"])
		if(islist(content) && ("__anchored" in content))
			track.anchored = content["__anchored"]
	catch(var/exception/e)
		log_subsystem_persistence_error("Error during json deserialization for persistent object. Failed to apply/decode track content: [e]")

// ============================================================
// CABLE -- save and restore d1/d2/icon_state so wire direction is preserved
// ============================================================

/obj/structure/cable/persistent_objects_get_content()
	return list("d1" = d1, "d2" = d2, "icon_state" = icon_state, "color" = color)

/obj/structure/cable/persistent_objects_apply_content(list/content, x, y, z)
	..()  // base: forceMove to saved position
	if(!content)
		return
	if("d1" in content)         d1         = text2num(content["d1"])
	if("d2" in content)         d2         = text2num(content["d2"])
	if("icon_state" in content) icon_state = content["icon_state"]
	if("color" in content)      color      = content["color"]
	update_icon()
	// Reconnect with correct d1/d2 -- Initialize built connections with wrong default d1=0,d2=1
	if(powernet)
		cut_cable_from_powernet()
	mergeConnectedNetworksOnTurf()
	mergeConnectedNetworks(d1)
	mergeConnectedNetworks(d2)

// ============================================================
// CLOSET -- save and restore contents so fill() items are not duplicated
// ============================================================

/obj/structure/closet/persistent_objects_get_content()
	var/list/content = list("opened" = opened)
	var/list/items = list()
	for(var/obj/item/I in src.contents)
		items += list(serializePersistentItem(I))
	content["items"] = items
	return content

/obj/structure/closet/persistent_objects_apply_content(list/content, x, y, z)
	..()  // base: forceMove to saved position
	if(!content)
		return
	// Remove items that fill() placed on creation -- we restore from saved state instead
	while(length(contents))
		qdel(contents[1])
	// Restore saved contents
	if(islist(content["items"]))
		for(var/list/item_data in content["items"])
			if(islist(item_data))
				deserializePersistentItem(item_data, src)
	// Restore open/closed state
	if(!isnull(content["opened"]))
		if(content["opened"] && !opened)
			open(TRUE)
		else if(!content["opened"] && opened)
			close(TRUE)
