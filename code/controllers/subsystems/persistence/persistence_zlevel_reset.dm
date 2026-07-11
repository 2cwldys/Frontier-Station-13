/*
 * Persistence - Per-Z-Level Info & Reset
 * Two admin tools: one reports a z-level's identity (so an admin knows what
 * number to type into the other), the other immediately wipes and reverts
 * everything persisted for a single z-level back to a map-default-like
 * state, live, without a server restart.
 *
 * This is NOT a byte-exact reload from the original .dmm file -- that would
 * require a full z-level teardown/re-parse subsystem that doesn't exist in
 * this codebase. Turf reversion uses the same `baseturf` fallback mechanism
 * already established by persistence_templates.dm's "Revert to Map Default"
 * (Immediate mode), which has the same known limitation (reverts to a
 * generic underlying type, e.g. plating/space, not the tile's true authored
 * type). Everything else this tool does (respawning destroyed structures,
 * resetting existing structures to fresh compiled defaults, clearing
 * dynamic/player-placed content, clearing floor items) is more thorough than
 * the existing template system, which touches none of those.
 */

/**
 * Deletes every persistence DB row keyed to the given z (turfs, atmos, floor
 * items, tracked objects, machinery worldstate, removed-structure tombstones).
 * DB rows ONLY -- no live-world changes. Used when a pinned away site's
 * deterministic z drifts (stale rows must not misapply to the new occupant of
 * that z) and by the Persistent Overmap Sites unpin flow.
 */
/datum/controller/subsystem/persistence/proc/purgeZRows(z, quiet = FALSE)
	if(!databaseCheckConnection("purgeZRows"))
		return FALSE
	var/map_path = "[SSatlas.current_map.path]"
	var/list/deletes = list(
		"ss13_worldstate_turfs"    = "DELETE FROM ss13_worldstate_turfs WHERE z = :z AND map_path = :mp",
		"ss13_persistent_objects"  = "DELETE FROM ss13_persistent_objects WHERE z = :z AND map_path = :mp",
		"ss13_floor_items"         = "DELETE FROM ss13_floor_items WHERE z = :z AND map_path = :mp",
		"ss13_removed_structures"  = "DELETE FROM ss13_removed_structures WHERE z = :z AND map_path = :mp",
		"ss13_persistent_bots"     = "DELETE FROM ss13_persistent_bots WHERE z = :z AND map_path = :mp",
		"ss13_atmos_zones"         = "DELETE FROM ss13_atmos_zones WHERE rep_z = :z AND map_path = :mp",
		"ss13_worldstate_objects"  = "DELETE FROM ss13_worldstate_objects WHERE z = :z AND map_path = :mp"
	)
	for(var/table in deletes)
		var/datum/db_query/dq = SSdbcore.NewQuery(deletes[table], list("z" = z, "mp" = map_path))
		dq.Execute()
		databaseCheckQueryResult(dq, "purgeZRows [table]")
		qdel(dq)
	if(!quiet)
		log_subsystem_persistence_info("Purged persistence DB rows for z=[z] ([map_path]).")
	return TRUE

/**
 * Moves every persistence DB row from old_z to new_z (same map). Used when a
 * pinned away site's deterministic z drifts between boots: templates always
 * load centered at the same (x, y), so remapping just the z column preserves
 * everything saved at the old number losslessly. Stale rows already sitting
 * at new_z are purged first so the moved rows can't collide.
 */
/datum/controller/subsystem/persistence/proc/remapZRows(old_z, new_z, quiet = FALSE)
	if(old_z == new_z)
		return TRUE
	if(!databaseCheckConnection("remapZRows"))
		return FALSE
	purgeZRows(new_z, quiet = TRUE)
	var/map_path = "[SSatlas.current_map.path]"
	var/list/updates = list(
		"ss13_worldstate_turfs"    = "UPDATE ss13_worldstate_turfs SET z = :nz WHERE z = :oz AND map_path = :mp",
		"ss13_persistent_objects"  = "UPDATE ss13_persistent_objects SET z = :nz WHERE z = :oz AND map_path = :mp",
		"ss13_floor_items"         = "UPDATE ss13_floor_items SET z = :nz WHERE z = :oz AND map_path = :mp",
		"ss13_removed_structures"  = "UPDATE ss13_removed_structures SET z = :nz WHERE z = :oz AND map_path = :mp",
		"ss13_persistent_bots"     = "UPDATE ss13_persistent_bots SET z = :nz WHERE z = :oz AND map_path = :mp",
		"ss13_atmos_zones"         = "UPDATE ss13_atmos_zones SET rep_z = :nz WHERE rep_z = :oz AND map_path = :mp",
		"ss13_worldstate_objects"  = "UPDATE ss13_worldstate_objects SET z = :nz WHERE z = :oz AND map_path = :mp"
	)
	for(var/table in updates)
		var/datum/db_query/uq = SSdbcore.NewQuery(updates[table], list("oz" = old_z, "nz" = new_z, "mp" = map_path))
		uq.Execute()
		databaseCheckQueryResult(uq, "remapZRows [table]")
		qdel(uq)
	if(!quiet)
		log_subsystem_persistence_info("Remapped persistence DB rows z=[old_z] -> z=[new_z] ([map_path]).")
	return TRUE

/datum/admins/proc/check_zlevel_info()
	set name = "Check Z-Level Info"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	// Auto-detects wherever the admin's own current mob is (living body or
	// ghost, whichever they're currently controlling) -- no manual entry.
	// Use "Reset Z-Level" for a deliberately-targeted z instead.
	var/z_pick = usr.z
	if(!z_pick || z_pick < 1 || z_pick > world.maxz)
		to_chat(usr, SPAN_WARNING("Could not determine your current z-level."))
		return

	var/level_name = (SSmapping.z_list && z_pick <= SSmapping.z_list.len) ? SSmapping.z_list[z_pick].name : "(unmanaged)"

	var/list/trait_names = list()
	if(is_station_level(z_pick))    trait_names += "Station"
	if(is_centcom_level(z_pick))    trait_names += "CentCom"
	if(is_away_level(z_pick))       trait_names += "Away"
	if(is_mining_level(z_pick))     trait_names += "Mining"
	if(is_reserved_level(z_pick))   trait_names += "Reserved"
	if(is_portofcall_level(z_pick)) trait_names += "Port of Call"

	var/persisted = !persistence_z_excluded(z_pick)

	var/list/present = list()
	for(var/mob/M in GLOB.mob_list)
		if(M.z == z_pick && M.client)
			present += "[M.name] ([M.client.ckey])"

	var/msg = "--- Z-Level [z_pick] ---\n"
	msg += "Name: [level_name]\n"
	msg += "Traits: [trait_names.len ? trait_names.Join(", ") : "(none)"]\n"
	msg += "Persistence: [persisted ? "enabled (saves/loads)" : "disabled (regenerates each restart)"]\n"
	msg += "Security zone: [uppertext(zone_security_name(zone_security_get(z_pick)))]\n"
	msg += "Players currently present: [present.len]"
	if(present.len)
		msg += "\n  [present.Join("\n  ")]"

	to_chat(usr, SPAN_NOTICE(msg))

/// TRUE if any player -- actively connected, SSD-lingering, or a disembodied
/// neural-lace consciousness (including one in vault storage with no mob at
/// all) -- is currently on z. Hard-blocks destructive Z-level admin actions.
/proc/zlevel_has_players(z)
	for(var/mob/M in GLOB.mob_list)
		if(M.z == z && (M.client || M.ckey))
			return TRUE
	for(var/obj/item/organ/internal/neural_lace/L in world)
		if(!length(L.registered_ckey))
			continue
		var/turf/T = get_turf(L)
		if(T && T.z == z)
			return TRUE
	return FALSE

/datum/admins/proc/reset_zlevel()
	set name = "Reset Z-Level"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/z_pick = tgui_input_number(usr, "Which z-level to reset? This immediately wipes and reverts everything persisted for it.", "Reset Z-Level", usr.z, world.maxz, 1)
	if(isnull(z_pick) || z_pick < 1 || z_pick > world.maxz)
		return

	var/list/present = list()
	for(var/mob/M in GLOB.mob_list)
		if(M.z == z_pick && M.client)
			present += "[M.name] ([M.client.ckey])"

	if(present.len)
		to_chat(usr, SPAN_DANGER("Make sure all players are removed from the Z level first."))
		to_chat(usr, SPAN_WARNING("Still present on Z=[z_pick]: [present.Join(", ")]"))
		return

	var/level_name = (SSmapping.z_list && z_pick <= SSmapping.z_list.len) ? SSmapping.z_list[z_pick].name : "z=[z_pick]"
	var/confirm = tgui_alert(usr, "Reset z-level [z_pick] ([level_name])? This cannot be undone.", "Reset Z-Level", list("Reset", "Cancel"))
	if(confirm != "Reset")
		return

	if(!SSpersistence.databaseCheckConnection("reset_zlevel"))
		to_chat(usr, SPAN_WARNING("Database connection failed."))
		return

	var/map_path = "[SSatlas.current_map.path]"
	var/respawned = 0
	var/machinery_reset = 0
	var/dynamic_removed = 0
	var/floor_items_removed = 0
	var/turfs_reverted = 0

	// 1. Respawn structures destroyed in a previous session (removed-structures tombstones)
	var/datum/db_query/rq = SSdbcore.NewQuery(
		"SELECT type, x, y FROM ss13_removed_structures WHERE z = :z AND map_path = :mp",
		list("z" = z_pick, "mp" = map_path)
	)
	rq.Execute()
	if(SSpersistence.databaseCheckQueryResult(rq, "reset_zlevel removed_structures select"))
		while(rq.NextRow())
			var/typepath = text2path(rq.item[1])
			if(!typepath)
				continue
			var/turf/T = locate(text2num(rq.item[2]), text2num(rq.item[3]), z_pick)
			if(!T)
				continue
			var/obj/structure/new_instance = new typepath(T)
			SSpersistence.clearStructureRemoval(new_instance)
			respawned++
	qdel(rq)

	// 2. Reset currently-existing map-placed structures to fresh compiled defaults.
	// Snapshot (type, turf) pairs first -- can't qdel while iterating turf contents.
	var/list/existing_structures = list()
	for(var/turf/T in block(locate(1, 1, z_pick), locate(world.maxx, world.maxy, z_pick)))
		for(var/obj/structure/S in T)
			if(S.persistence_was_mapload)
				existing_structures += list(list("type" = S.type, "turf" = T))
		CHECK_TICK
	for(var/list/entry in existing_structures)
		var/turf/T = entry["turf"]
		var/old_type = entry["type"]
		for(var/obj/structure/S in T)
			if(S.type == old_type && S.persistence_was_mapload)
				qdel(S)
				break
		var/obj/structure/new_instance = new old_type(T)
		SSpersistence.clearStructureRemoval(new_instance)
		machinery_reset++

	// 3. Remove dynamic/player-placed persistent-tracked content on this z
	var/list/tracked_to_remove = list()
	for(var/obj/track as anything in GLOB.persistence_object_track_register)
		var/turf/T = get_turf(track)
		if(T && T.z == z_pick)
			tracked_to_remove += track
		CHECK_TICK
	for(var/obj/track in tracked_to_remove)
		qdel(track)
		dynamic_removed++
	var/datum/db_query/dpq = SSdbcore.NewQuery(
		"DELETE FROM ss13_persistent_objects WHERE z = :z AND map_path = :mp",
		list("z" = z_pick, "mp" = map_path)
	)
	dpq.Execute()
	SSpersistence.databaseCheckQueryResult(dpq, "reset_zlevel persistent_objects delete")
	qdel(dpq)

	// 4. Clear loose floor items on this z (mirrors floorItemsInitialize's wipe criteria).
	// Snapshot first -- can't qdel while iterating turf contents.
	var/list/floor_items_to_remove = list()
	for(var/turf/T in block(locate(1, 1, z_pick), locate(world.maxx, world.maxy, z_pick)))
		for(var/obj/item/I in T)
			if(I.persistent_objects_track_id != 0)
				continue
			if(I in GLOB.persistence_object_track_register)
				continue
			if(istype(I, /obj/item/ammo_casing))
				continue
			floor_items_to_remove += I
		CHECK_TICK
	for(var/obj/item/I in floor_items_to_remove)
		qdel(I)
		floor_items_removed++
	var/datum/db_query/dfq = SSdbcore.NewQuery(
		"DELETE FROM ss13_floor_items WHERE z = :z AND map_path = :mp",
		list("z" = z_pick, "mp" = map_path)
	)
	dfq.Execute()
	SSpersistence.databaseCheckQueryResult(dfq, "reset_zlevel floor_items delete")
	qdel(dfq)

	// 5. Revert turfs to their baseturf (same mechanism as persistence_templates.dm)
	for(var/turf/T in block(locate(1, 1, z_pick), locate(world.maxx, world.maxy, z_pick)))
		if(T.type != T.baseturf)
			T.ChangeTurf(T.baseturf)
			turfs_reverted++
		CHECK_TICK
	var/datum/db_query/dtq = SSdbcore.NewQuery(
		"DELETE FROM ss13_worldstate_turfs WHERE z = :z AND map_path = :mp",
		list("z" = z_pick, "mp" = map_path)
	)
	dtq.Execute()
	SSpersistence.databaseCheckQueryResult(dtq, "reset_zlevel worldstate_turfs delete")
	qdel(dtq)

	// 6. Clear remaining worldstate/atmos DB rows for this z
	var/datum/db_query/dwq = SSdbcore.NewQuery(
		"DELETE FROM ss13_worldstate_objects WHERE z = :z AND map_path = :mp",
		list("z" = z_pick, "mp" = map_path)
	)
	dwq.Execute()
	SSpersistence.databaseCheckQueryResult(dwq, "reset_zlevel worldstate_objects delete")
	qdel(dwq)

	var/datum/db_query/daq = SSdbcore.NewQuery(
		"DELETE FROM ss13_atmos_zones WHERE rep_z = :z AND map_path = :mp",
		list("z" = z_pick, "mp" = map_path)
	)
	daq.Execute()
	SSpersistence.databaseCheckQueryResult(daq, "reset_zlevel atmos_zones delete")
	qdel(daq)

	var/summary = "Reset Z=[z_pick] ([level_name]): [respawned] structure(s) respawned, [machinery_reset] machine(s) reset to defaults, [dynamic_removed] dynamic object(s) removed, [floor_items_removed] floor item(s) cleared, [turfs_reverted] turf(s) reverted. Atmos DB rows cleared (live gas state untouched)."
	to_chat(usr, SPAN_GOOD(summary))
	log_admin("[key_name(usr)] reset z-level [z_pick] ([level_name]) via reset_zlevel(). [summary]")
