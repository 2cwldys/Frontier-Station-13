/datum/controller/subsystem/persistence/proc/saveStructureRemoval(obj/structure/S)
	if(!databaseCheckConnection("saveStructureRemoval"))
		return
	var/turf/T = get_turf(S)
	if(!T || !T.z)
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT IGNORE INTO ss13_removed_structures (map_path, type, x, y, z)
		VALUES (:mp, :type, :x, :y, :z)"},
		list("mp" = "[SSatlas.current_map.path]", "type" = "[S.type]", "x" = T.x, "y" = T.y, "z" = T.z)
	)
	q.Execute()
	qdel(q)

/datum/controller/subsystem/persistence/proc/clearStructureRemoval(obj/structure/S)
	if(!databaseCheckConnection("clearStructureRemoval"))
		return
	var/turf/T = get_turf(S)
	if(!T || !T.z)
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_removed_structures WHERE map_path = :mp AND type = :type AND x = :x AND y = :y AND z = :z",
		list("mp" = "[SSatlas.current_map.path]", "type" = "[S.type]", "x" = T.x, "y" = T.y, "z" = T.z)
	)
	q.Execute()
	qdel(q)

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
		var/tx = text2num(q.item[2])
		var/ty = text2num(q.item[3])
		var/tz = text2num(q.item[4])
		var/turf/T = locate(tx, ty, tz)
		if(!T)
			continue
		for(var/obj/structure/S in T)
			if(S.type == typepath && S.persistence_was_mapload)
				qdel(S)
				removed++
				break

	qdel(q)
	log_subsystem_persistence_info("Removed structures: Removed [removed] map-placed structures from previous session.")
