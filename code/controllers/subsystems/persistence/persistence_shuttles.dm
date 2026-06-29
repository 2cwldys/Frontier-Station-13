/*
 * Persistence -- Shuttle State
 *
 * Saves and restores shuttle docked locations across server restarts.
 *
 * Ordering guarantee (critical for no duplication):
 *   SSshuttle (INIT_ORDER_MISC = -2.2) initializes BEFORE SSpersistence (INIT_ORDER_PERSISTENCE = -10).
 *   shuttleStateRestore() is called at the end of SSshuttle.Initialize() so that all shuttle
 *   areas are at their correct (saved) positions BEFORE SSpersistence.objectsInitialize() loads
 *   persistent objects. This prevents objects from being loaded at the map-default position
 *   while the shuttle is actually somewhere else.
 *
 * Tables: ss13_persistent_shuttles
 */

// ============================================================
// SAVE  called from SSpersistence.Shutdown()
// ============================================================

/datum/controller/subsystem/persistence/proc/shuttleStateFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("shuttleStateFinalize"))
		return

	if(!istype(SSshuttle) || !SSshuttle.shuttles)
		return

	var/saved = 0
	for(var/sname in SSshuttle.shuttles)
		var/datum/shuttle/S = SSshuttle.shuttles[sname]
		if(!S || !S.current_location)
			continue
		var/tag = S.current_location.landmark_tag
		if(!tag)
			continue
		var/datum/db_query/q = SSdbcore.NewQuery(
			{"INSERT INTO ss13_persistent_shuttles (shuttle_name, location_tag)
			VALUES (:name, :tag)
			ON DUPLICATE KEY UPDATE location_tag = VALUES(location_tag), saved_at = NOW()"},
			list("name" = sname, "tag" = tag)
		)
		q.Execute()
		databaseCheckQueryResult(q, "shuttleStateFinalize [sname]")
		qdel(q)
		saved++

	log_subsystem_persistence_info("Shuttles: Saved [saved] shuttle location(s).")

// ============================================================
// RESTORE  called from SSshuttle.Initialize() after shuttles are set up
// ============================================================

/proc/shuttleStateRestore()
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return

	if(!istype(SSshuttle) || !SSshuttle.shuttles)
		return

	// Step 1: Recreate player docking beacons (their landmarks must exist before shuttles try to find them)
	var/datum/db_query/bq = SSdbcore.NewQuery(
		"SELECT landmark_tag, x, y, z, label FROM ss13_player_docking_beacons",
		list()
	)
	bq.Execute()
	var/beacons_restored = 0
	while(bq.NextRow())
		var/btag   = bq.item[1]
		var/bx     = text2num(bq.item[2])
		var/by     = text2num(bq.item[3])
		var/bz     = text2num(bq.item[4])
		var/blabel = bq.item[5]
		// Skip if already registered (e.g. beacon object already created its landmark)
		if(SSshuttle.registered_shuttle_landmarks[btag]) continue
		var/turf/bt = locate(bx, by, bz)
		if(!bt) continue
		var/obj/effect/shuttle_landmark/bl = new /obj/effect/shuttle_landmark(bt)
		bl.landmark_tag = btag
		bl.name         = blabel ? blabel : "Docking Port ([bx],[by],[bz])"
		bl.base_turf    = /turf/simulated/floor/plating
		beacons_restored++
	qdel(bq)

	// Step 2: Reconstruct player-built shuttle datums
	var/datum/db_query/pq = SSdbcore.NewQuery(
		"SELECT shuttle_name, owner_ckey, faction_uid, home_x, home_y, home_z, hull_json FROM ss13_player_shuttles",
		list()
	)
	pq.Execute()
	var/player_shuttles_restored = 0
	while(pq.NextRow())
		var/psname   = pq.item[1]
		var/pckey    = pq.item[2]
		var/pfaction = pq.item[3]
		var/phx      = text2num(pq.item[4])
		var/phy      = text2num(pq.item[5])
		var/phz      = text2num(pq.item[6])
		var/pjson    = pq.item[7]

		// Skip if shuttle datum already exists (map-placed?)
		if(psname in SSshuttle.shuttles) continue

		// Reconstruct hull turfs from saved positions
		var/list/pos_list = json_decode(pjson)
		var/list/hull_turfs = list()
		if(islist(pos_list))
			for(var/pos in pos_list)
				var/list/coords = splittext(pos, ",")
				if(length(coords) < 3) continue
				var/turf/T = locate(text2num(coords[1]), text2num(coords[2]), text2num(coords[3]))
				if(T) hull_turfs += T

		if(!length(hull_turfs)) continue

		var/turf/home_turf = locate(phx, phy, phz)
		if(!home_turf) continue

		var/datum/shuttle/player_built/S = create_player_shuttle(psname, hull_turfs, home_turf, pckey, pfaction)
		if(S) player_shuttles_restored++
	qdel(pq)

	// Step 3: Restore saved positions for ALL shuttles (map-placed and player-built)
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT shuttle_name, location_tag FROM ss13_persistent_shuttles",
		list()
	)
	q.Execute()

	var/restored = 0
	var/skipped  = 0
	while(q.NextRow())
		var/sname = q.item[1]
		var/tag   = q.item[2]

		var/datum/shuttle/S = SSshuttle.shuttles[sname]
		if(!S)
			skipped++
			continue

		var/obj/effect/shuttle_landmark/dest = SSshuttle.registered_shuttle_landmarks[tag]
		if(!dest)
			skipped++
			log_world("shuttleStateRestore: landmark '[tag]' not found for shuttle '[sname]' -- leaving at default.")
			continue

		if(S.current_location && S.current_location.landmark_tag == tag)
			skipped++
			continue

		S.short_jump(dest)
		restored++

	qdel(q)
	log_world("shuttleStateRestore: [player_shuttles_restored] player shuttle(s) reconstructed, [beacons_restored] beacon(s) restored, [restored] position(s) restored, [skipped] skipped.")
