/datum/controller/subsystem/persistence/proc/saveStructureRemoval(obj/structure/S)
	var/turf/T = get_turf(S)
	if(!T)
		return
	saveStructureRemovalAt(S.type, T)

/**
 * Tombstones a (type, turf) pair directly, for callers where the structure
 * itself is no longer AT the position being tombstoned (e.g. a relocated
 * map-placed object promoted to dynamic tracking -- the original map slot
 * must still stop respawning it, even though `S` has since moved away).
 */
/datum/controller/subsystem/persistence/proc/saveStructureRemovalAt(type, turf/T)
	if(!databaseCheckConnection("saveStructureRemovalAt"))
		return FALSE
	if(!T || !T.z || persistence_z_manual_blocked(T.z))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT IGNORE INTO ss13_removed_structures (map_path, type, x, y, z)
		VALUES (:mp, :type, :x, :y, :z)"},
		// Deployed ship Zs tombstone under their ship scope instead of the
		// map path -- see persistence_ship_interiors.dm.
		list("mp" = persistence_scope_for_z(T.z), "type" = "[type]", "x" = T.x, "y" = T.y, "z" = T.z)
	)
	q.Execute()
	. = databaseCheckQueryResult(q, "saveStructureRemovalAt")
	qdel(q)

/datum/controller/subsystem/persistence/proc/clearStructureRemoval(obj/structure/S)
	if(!databaseCheckConnection("clearStructureRemoval"))
		return
	var/turf/T = get_turf(S)
	if(!T || !T.z || persistence_z_manual_blocked(T.z))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_removed_structures WHERE map_path = :mp AND type = :type AND x = :x AND y = :y AND z = :z",
		list("mp" = persistence_scope_for_z(T.z), "type" = "[S.type]", "x" = T.x, "y" = T.y, "z" = T.z)
	)
	q.Execute()
	qdel(q)

/**
 * Apply saved ship-scoped removal tombstones to a freshly loaded ship Z --
 * qdels each map-placed structure the ship's crew removed in a previous
 * deployment, so it doesn't respawn with the template.
 */
/datum/controller/subsystem/persistence/proc/removedStructuresApplyZ(z, scope)
	if(!databaseCheckConnection("removedStructuresApplyZ"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT type, x, y FROM ss13_removed_structures WHERE map_path = :mp AND z = :z",
		list("mp" = scope, "z" = z)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "removedStructuresApplyZ"))
		qdel(q)
		return
	var/removed = 0
	while(q.NextRow())
		var/typepath = text2path(q.item[1])
		if(!typepath)
			continue
		if(ispath(typepath, /obj/structure))
			var/obj/structure/probe = typepath
			if(initial(probe.persistence_never_tombstone))
				continue
		var/turf/T = locate(text2num(q.item[2]), text2num(q.item[3]), z)
		if(!T)
			continue
		for(var/obj/structure/S in T)
			if(S.type == typepath && S.persistence_was_mapload)
				qdel(S)
				removed++
				break
		CHECK_TICK
	qdel(q)
	log_subsystem_persistence_info("Removed structures: Applied [removed] ship tombstones to z=[z] ([scope]).")

/datum/controller/subsystem/persistence/proc/removedStructuresInitialize()
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("removedStructuresInitialize"))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT type, x, y, z FROM ss13_removed_structures WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "removedStructuresInitialize"))
		qdel(q)
		return

	var/removed = 0
	while(q.NextRow())
		var/typepath = text2path(q.item[1])
		if(!typepath)
			continue
		// Types flagged persistence_never_tombstone must ALWAYS load with the
		// map, every session -- never delete them from stale removal rows
		// (written before the flag existed). Also erase those rows so this
		// permanently self-heals on the first boot after the flag is added.
		if(ispath(typepath, /obj/structure))
			var/obj/structure/probe = typepath
			if(initial(probe.persistence_never_tombstone))
				var/datum/db_query/cleanup_q = SSdbcore.NewQuery(
					"DELETE FROM ss13_removed_structures WHERE map_path = :mp AND type = :type",
					list("mp" = "[SSatlas.current_map.path]", "type" = q.item[1])
				)
				cleanup_q.Execute()
				qdel(cleanup_q)
				log_subsystem_persistence_info("Removed structures: purged stale removal row(s) for [typepath] -- this type always loads with the map.")
				continue
		var/tx = text2num(q.item[2])
		var/ty = text2num(q.item[3])
		var/tz = text2num(q.item[4])
		if(persistence_z_manual_blocked(tz))
			continue
		var/turf/T = locate(tx, ty, tz)
		if(!T)
			continue
		for(var/obj/structure/S in T)
			if(S.type == typepath && S.persistence_was_mapload)
				log_subsystem_persistence_info("Removed structures: removing [typepath] at ([tx],[ty],[tz]) (tombstoned in a previous session).")
				qdel(S)
				removed++
				break

	qdel(q)
	log_subsystem_persistence_info("Removed structures: Removed [removed] map-placed structures from previous session.")

/// Admin tool: lists every tombstoned map-placed structure for the current
/// map and lets an admin permanently un-tombstone one (it will reappear on
/// the next boot -- the object itself was already qdel'd this round, this
/// only clears the DB row that keeps it from being recreated).
/client/proc/view_removed_structures()
	set category = "Admin"
	set name = "View Removed Structures"
	if(!check_rights(R_ADMIN))
		return
	if(!SSpersistence.databaseCheckConnection("view_removed_structures"))
		to_chat(usr, SPAN_WARNING("Database connection failed."))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id, type, x, y, z FROM ss13_removed_structures WHERE map_path = :mp ORDER BY id",
		list("mp" = "[SSatlas.current_map.path]")
	)
	q.Execute()
	if(!SSpersistence.databaseCheckQueryResult(q, "view_removed_structures"))
		qdel(q)
		return

	var/list/rows = list()
	while(q.NextRow())
		rows += list(list(
			"id"   = text2num(q.item[1]),
			"type" = q.item[2],
			"x"    = text2num(q.item[3]),
			"y"    = text2num(q.item[4]),
			"z"    = text2num(q.item[5])
		))
	qdel(q)

	if(!length(rows))
		to_chat(usr, SPAN_NOTICE("No removed structures recorded for this map."))
		return

	var/list/choices = list()
	for(var/list/row in rows)
		choices["#[row["id"]] [row["type"]] at ([row["x"]],[row["y"]],[row["z"]])"] = row

	var/picked = tgui_input_list(usr, "Select a removed structure to restore (it will reappear next boot):", "View Removed Structures", choices)
	if(!picked || !(picked in choices))
		return
	var/list/chosen = choices[picked]

	var/datum/db_query/dq = SSdbcore.NewQuery(
		"DELETE FROM ss13_removed_structures WHERE id = :id",
		list("id" = chosen["id"])
	)
	dq.Execute()
	SSpersistence.databaseCheckQueryResult(dq, "view_removed_structures delete")
	qdel(dq)

	to_chat(usr, SPAN_GOOD("Cleared removal record for [chosen["type"]] at ([chosen["x"]],[chosen["y"]],[chosen["z"]]) -- it will be recreated on the next server restart."))
	log_admin("[key_name(usr)] restored a removed structure record: [chosen["type"]] at ([chosen["x"]],[chosen["y"]],[chosen["z"]]).")
