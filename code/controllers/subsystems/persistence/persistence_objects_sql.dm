/**
 * Run cleanup on the persistence entries in the database.
 * Cleanup includes all entries that have expired and have passed the clean up grace period (PERSISTENT_EXPIRATION_CLEANUP_DELAY_DAYS).
 */
/datum/controller/subsystem/persistence/proc/objectsDatabaseCleanEntries()
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("objectsDatabaseCleanEntries"))
		return

	var/datum/db_query/cleanup_query = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_objects WHERE DATE_ADD(expires_at, INTERVAL :grace_period_days DAY) <= NOW()",
		list("grace_period_days" = PERSISTENT_EXPIRATION_CLEANUP_DELAY_DAYS)
	)

	cleanup_query.SetFailCallback(CALLBACK(PROC_REF(objectsDatabaseCleanEntries_CallbackFailure)))
	cleanup_query.SetSuccessCallback(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(qdel)))
	cleanup_query.ExecuteNoSleep(TRUE)

/datum/controller/subsystem/persistence/proc/objectsDatabaseCleanEntries_CallbackFailure(datum/db_query/cleanup_query)
	databaseCheckQueryResult(cleanup_query, "objectsDatabaseCleanEntries")
	qdel(cleanup_query)

/**
 * Retrieve persistent data entries that haven't expired.
 * scope defaults to the current map's path; pass a ship scope key
 * ("ship:c:<id>" / "ship:d:<id>", persistence_ship_interiors.dm) to fetch a
 * deployed/stashed ship's rows instead.
 * RETURN: List of JSON, with ID, author_ckey, type, content, x, y, z
 */
/datum/controller/subsystem/persistence/proc/objectsDatabaseGetActiveEntries(scope)
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("objectsDatabaseGetActiveEntries"))
		return

	var/datum/db_query/get_query = SSdbcore.NewQuery(
		"SELECT id, author_ckey, type, content, x, y, z FROM ss13_persistent_objects WHERE NOW() < expires_at AND map_path = :map_path",
		list("map_path" = scope ? scope : "[SSatlas.current_map.path]")
	)
	get_query.Execute()

	var/list/results = list()
	if (!databaseCheckQueryResult(get_query, "objectsDatabaseGetActiveEntries"))
		qdel(get_query)
		return
	else
		while (get_query.NextRow())
			CHECK_TICK
			var/list/entry = list(
				"id" = get_query.item[1],
				"author_ckey" = get_query.item[2],
				"type" = get_query.item[3],
				"content" = get_query.item[4],
				"x" = get_query.item[5],
				"y" = get_query.item[6],
				"z" = get_query.item[7]
			)
			results += list(entry)
	qdel(get_query)
	return results

/**
 * Permanently forgets any tracked-object rows at the given turfs, right now.
 *
 * Object counterpart to turfsForget() (persistence_turfs.dm) and used
 * alongside it wherever a block of space is being deliberately cleared and
 * must not reconstruct itself on the next boot -- the commission build-site
 * wipe, and the docking-beacon landing-envelope sweeps
 * (drydockForgetBeaconEnvelopes()/clear_docking_beacons(),
 * persistence_shuttles.dm).
 *
 * Buckets by persistence_scope_for_z() exactly as the add/update entry procs
 * below do, so a deployed ship Z's rows are deleted under that ship's own
 * scope rather than the map's.
 */
/datum/controller/subsystem/persistence/proc/objectsForget(list/turfs)
	if(!length(turfs))
		return
	if(!databaseCheckConnection("objectsForget"))
		return

	var/list/delete_by_scope = list()
	for(var/turf/T in turfs)
		var/scope_escaped = replacetext(persistence_scope_for_z(T.z), "'", "''")
		if(!(scope_escaped in delete_by_scope))
			delete_by_scope[scope_escaped] = list()
		delete_by_scope[scope_escaped] += "([T.x],[T.y],[T.z])"
		CHECK_TICK

	var/forgotten = 0
	for(var/scope_escaped in delete_by_scope)
		var/list/coords = delete_by_scope[scope_escaped]
		if(!length(coords))
			continue
		var/datum/db_query/wipe = SSdbcore.NewQuery(
			"DELETE FROM ss13_persistent_objects WHERE map_path = '[scope_escaped]' AND (x,y,z) IN ([coords.Join(",")])"
		)
		wipe.Execute()
		databaseCheckQueryResult(wipe, "objectsForget delete")
		qdel(wipe)
		forgotten += length(coords)
		CHECK_TICK

	log_subsystem_persistence_info("Objects: Forgot rows across [forgotten] coordinate(s) in [length(delete_by_scope)] scope(s).")

/**
 * Adds a persistent data record to the database.
 */
/datum/controller/subsystem/persistence/proc/objectsDatabaseAddEntry(obj/track)
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("objectsDatabaseAddEntry"))
		return

	var/turf/T = get_turf(track)
	if(!T)
		return
	// A ship's own tracked objects, while it's genuinely docked away from its
	// own home z, are excluded rather than written under either scope here --
	// see persistence_docked_turf_scope's doc comment (persistence_ship_interiors.dm)
	// for why redirecting to the ship's own scope instead would silently
	// accumulate stale, wrongly-positioned rows.
	if(persistence_turf_docked_elsewhere(T))
		return

	var/datum/db_query/insert_query = SSdbcore.NewQuery(
		"INSERT INTO ss13_persistent_objects (author_ckey, type, created_at, expires_at, content, x, y, z, map_path) \
		VALUES (:author_ckey, :type, NOW(), DATE_ADD(NOW(), INTERVAL :expire_in_days DAY), :content, :x, :y, :z, :map_path)",
		list(
			"author_ckey" = track.persistent_objects_author_ckey,
			"type" = "[track.type]",
			"expire_in_days" = track.persistant_objects_expiration_time_days,
			"content" = objectsGetTrackContent(track),
			"x" = T.x,
			"y" = T.y,
			"z" = T.z,
			// Deployed ship Zs key under their ship scope instead of the map
			// path -- see persistence_ship_interiors.dm.
			"map_path" = persistence_scope_for_z(T.z)
		)
	)
	insert_query.Execute()

	databaseCheckQueryResult(insert_query, "objectsDatabaseAddEntry")
	qdel(insert_query)

/**
 * Updates a persistent data record in the database.
 */
/datum/controller/subsystem/persistence/proc/objectsDatabaseUpdateEntry(obj/track)
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("objectsDatabaseUpdateEntry"))
		return

	var/turf/T = get_turf(track)
	if(!T)
		return
	// See objectsDatabaseAddEntry()'s matching check just above -- same
	// reasoning, excluded rather than redirected while genuinely docked away
	// from home.
	if(persistence_turf_docked_elsewhere(T))
		return

	var/datum/db_query/update_query = SSdbcore.NewQuery(
		// map_path follows the object's current turf so a tracked object
		// carried onto or off a deployed ship migrates between the map scope
		// and the ship scope on its next save (persistence_ship_interiors.dm).
		"UPDATE ss13_persistent_objects SET author_ckey=:author_ckey, expires_at=DATE_ADD(NOW(), INTERVAL :expire_in_days DAY), content=:content, x=:x, y=:y, z=:z, map_path=:map_path WHERE id = :id",
		list(
			"author_ckey" = track.persistent_objects_author_ckey,
			"expire_in_days" = track.persistant_objects_expiration_time_days,
			"content" = objectsGetTrackContent(track),
			"x" = T.x,
			"y" = T.y,
			"z" = T.z,
			"map_path" = persistence_scope_for_z(T.z),
			"id" = track.persistent_objects_track_id
		)
	)
	update_query.Execute()

	databaseCheckQueryResult(update_query, "objectsDatabaseUpdateEntry")
	qdel(update_query)

/**
 * Expire a persistent data record in the database by setting it's expiration date to now.
 */
/datum/controller/subsystem/persistence/proc/objectsDatabaseExpireEntry(track_id)
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("objectsDatabaseExpireEntry"))
		return

	var/datum/db_query/expire_query = SSdbcore.NewQuery(
		"UPDATE ss13_persistent_objects SET expires_at=NOW() WHERE id = :id",
		list("id" = track_id)
	)
	expire_query.Execute()

	databaseCheckQueryResult(expire_query, "objectsDatabaseExpireEntry")
	qdel(expire_query)
