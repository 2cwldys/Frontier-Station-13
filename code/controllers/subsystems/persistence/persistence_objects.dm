/// TRUE for the duration of objectsInstantiateRows()'s restore loop --
/// suppresses /obj/structure/Initialize()'s auto-register/clear-tombstone
/// side effect (structures.dm), which otherwise has no way to tell "this is
/// persistence recreating a tracked object" apart from "this is a genuine
/// new placement that should un-tombstone its tile." Boot-time restore is
/// already covered by !GLOB.persistence_ready, but objectsApplyZ() (ship
/// retrieve) runs long after that flips TRUE, with no equivalent protection
/// until now -- without this, recreating a tracked object on a tile that
/// coincidentally matches a different, already-tombstoned map structure
/// silently erases that unrelated tombstone, letting the ship template's
/// own original copy respawn unopposed on the next retrieve.
GLOBAL_VAR_INIT(persistence_restoring_tracked_objects, FALSE)

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
	objectsInstantiateRows(persistent_data)

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
 * Instantiate a list of fetched persistent-object rows into the world and
 * register them for tracking. Shared by the boot restore (objectsInitialize())
 * and the per-ship-Z apply (objectsApplyZ()). Returns the count instantiated.
 */
/datum/controller/subsystem/persistence/proc/objectsInstantiateRows(list/persistent_data, quiet = FALSE)
	PRIVATE_PROC(TRUE)
	GLOB.persistence_restoring_tracked_objects = TRUE
	var/instantiated = 0
	// Recreated here via a plain new() (below) rather than a template mapload,
	// so mapload=FALSE and Initialize() never returns INITIALIZE_HINT_LATELOAD
	// for these specific instances -- atmos_init()/build_network() would
	// otherwise never run for any persisted atmos machine (a fuel tank, pipe
	// segment, engine part) at all, leaving it permanently isolated from any
	// pipe network. Collected below and batch-initialized after the loop,
	// same shape as the existing SSmachinery.makepowernets() fix already
	// applied for the equivalent cable/powernet problem (shipInteriorApply(),
	// persistence_ship_interiors.dm).
	var/list/atmos_batch = list()
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
				// Reuse an already-existing, untracked (persistent_objects_track_id
				// == 0) instance of this exact type at the saved position instead
				// of always minting a new one -- a freshly-loaded ship template
				// re-spawns its own authored decor (e.g. an ashtray) on every
				// retrieve BEFORE this runs, and without this check the saved row
				// mints a second, independent instance alongside it. At the next
				// stash, the untracked original gets its own fresh DB row
				// (objectsFinalizeZ()'s create-branch) while the restored one
				// updates in place -- one extra instance AND one extra row every
				// single stash/retrieve cycle, compounding indefinitely. Mirrors
				// the /obj/structure/lattice special case above, generalized to
				// every type. The track_id == 0 check specifically prevents this
				// row from "stealing" an instance a PRIOR row in this same batch
				// already claimed.
				var/obj/existing = null
				for(var/obj/O in spawn_turf)
					if(O.type == typepath && O.persistent_objects_track_id == 0)
						existing = O
						break
				if(existing)
					instance = existing
				else
					instance = new typepath(spawn_turf)
					if(!instance || QDELETED(instance))
						var/obj/existing_after_fail = null
						for(var/obj/O in spawn_turf)
							if(O.type == typepath) { existing_after_fail = O; break }
						if(existing_after_fail)
							existing_after_fail.persistent_objects_track_id = text2num(data["id"])
							objectsRegisterTrack(existing_after_fail, data["author_ckey"])
						else
							objectsDatabaseExpireEntry(data["id"])
						continue
			instance.persistent_objects_track_id = data["id"]
			objectsApplyTrackContent(instance, data["content"], data["x"], data["y"], data["z"])
			objectsRegisterTrack(instance, data["author_ckey"])
			if(istype(instance, /obj/structure/machinery/atmospherics))
				atmos_batch += instance
			instantiated++
		catch(var/exception/e)
			log_subsystem_persistence_error("Persistent objects: Failed to instantiate [data["type"]] (id=[data["id"]]): [e]")
	if(length(atmos_batch))
		SSmachinery.setup_atmos_machinery(atmos_batch, quiet)
	GLOB.persistence_restoring_tracked_objects = FALSE
	return instantiated

/**
 * Apply saved ship-scoped tracked objects to a freshly loaded ship Z. Rows
 * were already remapped to this z by remapShipRows(); recreated tracks rejoin
 * GLOB.persistence_object_track_register so future saves keep tracking them.
 */
/datum/controller/subsystem/persistence/proc/objectsApplyZ(z, scope)
	var/list/scope_rows = objectsDatabaseGetActiveEntries(scope)
	if(!islist(scope_rows) || !length(scope_rows))
		return
	var/instantiated = objectsInstantiateRows(scope_rows, TRUE)
	log_subsystem_persistence_info("Persistent objects: Applied [instantiated] ship tracked objects to z=[z] ([scope]).")

/**
 * Per-Z tracked-object save for a deployed ship Z. Mirrors objectsFinalize()'s
 * add/update/expire contract, restricted to this ship's scope:
 * - tracked objects currently on z are created/updated (their rows key under
 *   the ship scope via the object's own turf)
 * - scope rows whose object no longer exists anywhere are expired
 * - scope rows whose object still exists but has moved OFF the ship are
 *   updated in place, which migrates the row back to the object's current
 *   scope (so carrying an item off a ship doesn't strand or expire its row)
 */
/datum/controller/subsystem/persistence/proc/objectsFinalizeZ(z, scope)
	// Fetch BEFORE the add pass, mirroring objectsFinalize() -- rows created
	// below must not be visible to this cycle's expire diff.
	var/list/scope_rows = objectsDatabaseGetActiveEntries(scope)

	var/created = 0
	var/updated = 0
	var/expired = 0

	for (var/obj/track as anything in GLOB.persistence_object_track_register)
		CHECK_TICK
		var/turf/T = get_turf(track)
		if(!T || T.z != z)
			continue
		if(isitem(track) && !isturf(track.loc))
			objectsDeregisterTrack(track)
			continue
		if (track.persistent_objects_track_id == 0)
			objectsDatabaseAddEntry(track)
			created++
		else
			objectsDatabaseUpdateEntry(track)
			updated++

	for (var/record in scope_rows)
		CHECK_TICK
		var/obj/found_track = null
		for (var/obj/candidate as anything in GLOB.persistence_object_track_register)
			if (record["id"] == candidate.persistent_objects_track_id)
				found_track = candidate
				break
		if(!found_track)
			objectsDatabaseExpireEntry(record["id"])
			expired++
		else
			var/turf/T = get_turf(found_track)
			if(!T || T.z != z)
				objectsDatabaseUpdateEntry(found_track)

	log_subsystem_persistence_info("Persistent objects: Ship z=[z] ([scope]): created [created], updated [updated], expired [expired] tracks.")

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
	// Deployed ship scopes are included so ship-borne tracks update/expire in
	// the same diff (a stashed ship's scope is NOT registered, so its saved
	// interior rows stay untouched by this pass -- that's load-bearing).
	var/list/existing_data = objectsDatabaseGetActiveEntries()
	if(!islist(existing_data))
		existing_data = list()
	for(var/ship_z in GLOB.persistence_ship_z)
		var/list/ship_rows = objectsDatabaseGetActiveEntries(GLOB.persistence_ship_z[ship_z])
		if(islist(ship_rows))
			existing_data += ship_rows

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
	var/list/content = list("opened" = opened, "broken" = broken, "locked" = locked)
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
	// Restore open/closed state -- set vars directly, NOT via open()/close()
	// which call dump_contents() and eject the items we just restored inside.
	if(!isnull(content["opened"]))
		opened = content["opened"] ? TRUE : FALSE
		if(!opened)
			density = TRUE
		else if(!dense_when_open)
			density = FALSE
	if(!isnull(content["broken"]))
		broken = content["broken"] ? TRUE : FALSE
	if(!isnull(content["locked"]))
		locked = content["locked"] ? TRUE : FALSE
	update_icon()

// ============================================================
// STORAGE ITEMS (bags, boxes, satchels) -- save and restore contents on the
// TRACKED-OBJECT path.
//
// Contents were only ever recorded by serializePersistentItem(), which the
// floor-item sweep uses. But _floorItemRow() deliberately skips anything
// already registered as a tracked object, and the tracked path's own
// objectsGetTrackContent() resolves to the /obj/item override -- which records
// wear state and nothing else. So a storage item that became tracked fell
// through BOTH paths and lost everything inside it. Same shape as the closet
// handler above, which has always done this correctly.
// ============================================================

/obj/item/storage/persistent_objects_get_content()
	. = ..()
	var/list/items = list()
	for(var/obj/item/I in contents)
		items += list(serializePersistentItem(I))
	.["items"] = items

/obj/item/storage/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content) || !islist(content["items"]))
		return
	// Drop whatever fill() placed during Initialize before restoring -- without
	// this the saved contents stack on top of a fresh default load-out.
	while(length(contents))
		qdel(contents[1])
	for(var/list/item_data in content["items"])
		if(islist(item_data))
			deserializePersistentItem(item_data, src)

// ============================================================
// CARTS -- engineering/janitorial/parcel carts had NO persistence hook at all,
// so nothing they carried survived a save. They also aren't /obj/item/storage:
// they hold loose items directly in contents, and additionally track a few
// specific slots in their own typed vars (toolboxes, light replacer, and
// stacked sheet lists), which are what the cart's UI actually reads. Restoring
// contents alone would leave those vars null and the cart looking empty, so
// both halves are rebuilt -- the typed vars are re-pointed at the restored
// contents by type rather than being serialized twice.
// ============================================================

/obj/structure/cart/storage/persistent_objects_get_content()
	. = ..()
	var/list/items = list()
	for(var/obj/item/I in contents)
		items += list(serializePersistentItem(I))
	.["items"] = items

/obj/structure/cart/storage/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content) || !islist(content["items"]))
		return
	while(length(contents))
		qdel(contents[1])
	for(var/list/item_data in content["items"])
		if(islist(item_data))
			deserializePersistentItem(item_data, src)
	_rebuild_cart_slots()
	update_icon()

/// Re-points a cart's typed convenience vars at whatever is actually in its
/// contents after a restore. Subtypes with their own slot vars override this.
/obj/structure/cart/storage/proc/_rebuild_cart_slots()
	return

/obj/structure/cart/storage/engineeringcart/_rebuild_cart_slots()
	my_glass = list()
	my_metal = list()
	my_plasteel = list()
	my_cable_coil = list()
	my_lightreplacer = null
	my_blue_toolbox = null
	my_yellow_toolbox = null
	my_red_toolbox = null
	// Order matters: plasteel is a subtype-adjacent sibling of steel here, so
	// match the most specific stack types first.
	for(var/obj/item/I in contents)
		if(istype(I, /obj/item/stack/material/plasteel))
			my_plasteel += I
		else if(istype(I, /obj/item/stack/material/glass))
			my_glass += I
		else if(istype(I, /obj/item/stack/material/steel))
			my_metal += I
		else if(istype(I, /obj/item/stack/cable_coil))
			my_cable_coil += I
		else if(istype(I, /obj/item/storage/toolbox/mechanical))
			my_blue_toolbox = I
		else if(istype(I, /obj/item/storage/toolbox/electrical))
			my_yellow_toolbox = I
		else if(istype(I, /obj/item/storage/toolbox/emergency))
			my_red_toolbox = I
		else if(istype(I, /obj/item/lightreplacer))
			my_lightreplacer = I

// ============================================================
// COSMETIC COLOR -- these item types roll a random `color` in Initialize()
// with no persistence hook, so a saved instance gets a fresh random reroll
// every restore. Save/restore the roll the same way CABLE does above; their
// own decorative overlays (where they have one) are added with RESET_COLOR
// and don't depend on `color`, so restoring the var alone is sufficient --
// no update_icon()/overlay rebuild needed.
// ============================================================

/obj/item/screwdriver/persistent_objects_get_content()
	. = ..()
	if(color)
		.["color"] = color

/obj/item/screwdriver/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && content["color"])
		color = content["color"]

/obj/item/wirecutters/persistent_objects_get_content()
	. = ..()
	if(color)
		.["color"] = color

/obj/item/wirecutters/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && content["color"])
		color = content["color"]

/obj/item/sleeping_bag/persistent_objects_get_content()
	. = ..()
	if(color)
		.["color"] = color

/obj/item/sleeping_bag/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && content["color"])
		color = content["color"]

/obj/item/clothing/mask/smokable/ecig/util/persistent_objects_get_content()
	. = ..()
	if(color)
		.["color"] = color

/obj/item/clothing/mask/smokable/ecig/util/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && content["color"])
		color = content["color"]

/obj/item/handcuffs/cable/persistent_objects_get_content()
	. = ..()
	if(color)
		.["color"] = color

/obj/item/handcuffs/cable/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && content["color"])
		color = content["color"]

/obj/item/toy/balloon/color/persistent_objects_get_content()
	. = ..()
	if(color)
		.["color"] = color

/obj/item/toy/balloon/color/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && content["color"])
		color = content["color"]

// ============================================================
// MACHETE -- the random handle color tints a separate overlay image, not
// the item's own `color` var, so it needs its own captured var and an
// overlay rebuild on restore (ClearOverlays() first, since Initialize()
// already added one with a different random pick before restore runs).
// ============================================================

/obj/item/material/hatchet/machete/persistent_objects_get_content()
	. = ..()
	if(handle_color)
		.["handle_color"] = handle_color

/obj/item/material/hatchet/machete/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && content["handle_color"])
		handle_color = content["handle_color"]
		ClearOverlays()
		var/image/I = image(icon, icon_state = "machete_handle")
		I.color = handle_color
		AddOverlays(I)
