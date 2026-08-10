/*
 * Persistence - Ship Interiors
 * Interior persistence, Z-level reuse pool, and lifecycle plumbing for
 * player-owned drydock ships (persistence_shuttles.dm) -- the single unified
 * system for both personal and faction ship ownership.
 *
 * Identity model: every ship's interior content rows live in the existing 8
 * persistence content tables (worldstate_turfs, persistent_objects,
 * floor_items, removed_structures, persistent_bots, atmos_zones,
 * worldstate_objects, persistent_areas) under a ship-scoped map_path key
 * instead of the current map's path: "ship:d:<shuttle_id>"
 * Rows keyed this way are invisible to every boot loader (which all filter
 * WHERE map_path = current map), collision-free across Z reuse (two ships can
 * occupy the same Z number at different times without row ambiguity), and
 * crash-safe (rows stay valid no matter what Z the ship lands on next). The
 * z column on ship-scope rows is just "last live z" -- retrieve remaps it
 * with one UPDATE per table (remapShipRows()), the same trick pinned away
 * sites use (remapZRows(), persistence_zlevel_reset.dm), keyed on map_path
 * instead of (map_path, z). Lossless because templates always load centered
 * at the same (x, y). persistent_areas is the one exception to the "plain z
 * column" shape (its z lives per-coordinate inside a JSON blob), so it remaps
 * inline in areasApplyZ() (persistence_areas.dm) instead of going through
 * remapShipRows().
 *
 * Known accepted limitation (same as pinned sites): if a hull's .dmm is
 * edited between sessions, saved rows referencing coordinates that no longer
 * align simply skip on apply -- the authored template stands where rows
 * don't match.
 */

/// Assoc list "z" -> ship scope key ("ship:d:<shuttle_id>").
/// Registered on retrieve, cleared on stash. A Z present here saves/loads
/// through the ordinary persistence sweeps (persistence_z_excluded() and
/// persistence_z_manual_blocked() both bypass for it) with every row keyed
/// to the ship scope via persistence_scope_for_z().
GLOBAL_LIST_EMPTY(persistence_ship_z)

/// General-purpose pool of wiped, contentless Z-levels available for reuse
/// by a future load_into_z() call -- ships (persistence_shuttles.dm) AND
/// away/mission sites (_spawn_away_site_for_template()/_despawn_away_site_z(),
/// persistence_factions.dm) both draw from and return to this same pool, so
/// repeated retrieve/stash and spawn/despawn cycles stop permanently
/// allocating new Z-levels. BYOND has no way to shrink world.maxz -- this is
/// the only mitigation available. In-memory only by design: everything that
/// could be pooled is also fully torn down at boot (ships boot stashed,
/// away/mission sites aren't restored at all), so the pool is definitionally
/// empty at startup and an SQL mirror could only ever hold stale numbers.
GLOBAL_LIST_EMPTY(reusable_z_pool)

/// Master on/off for recycling torn-down ship Z-levels at all. TRUE keeps
/// today's behaviour (pool a wiped z, hand it to the next retrieve); FALSE
/// makes every retrieve load a brand-new z instead, trading z-level count for
/// a guarantee that no ship can ever inherit another's ground. Flipped at
/// runtime by the "Toggle Ship Z Reuse" admin verb (persistence_shuttles.dm).
///
/// In-memory only -- resets to the default on reboot, same as the other
/// in-memory admin-tunable globals. Independent of _z_is_verifiably_empty()
/// (below), which vets a candidate z regardless of this setting.
GLOBAL_VAR_INIT(persistence_allow_z_reuse, TRUE)

/// The persistence scope key content rows on this z should be written under:
/// the ship scope if a ship owns the z, else the current map's path.
/proc/persistence_scope_for_z(z)
	var/ship_scope = GLOB.persistence_ship_z["[z]"]
	if(ship_scope)
		return ship_scope
	return "[SSatlas.current_map.path]"

/// Set of turfs currently belonging to a deployed ship's real hull while it's
/// physically docked somewhere other than its own home Z
/// (docking_beacon.dm/shuttle.dm's attempt_move()/shuttle_moved() genuinely
/// relocates a docked ship's turfs and area membership onto the destination's
/// real location).
/// persistence_scope_for_z(z) alone can't tell those specific turfs apart
/// from the rest of whatever Z they're currently sitting on (a single z can't
/// map to two scopes at once).
///
/// Deliberately an EXCLUSION set, not a scope redirect: a docked ship's rows
/// would otherwise get written at its current (docked) x/y/z, keyed under its
/// own ship scope via an ON DUPLICATE KEY UPDATE upsert (_turfsFlush() etc.,
/// persistence_turfs.dm) -- but remapShipRows() (below) only ever rewrites
/// the z column for a whole scope at retrieve time, never x/y, so those
/// docked-position rows would never get cleaned up by a later save taken at
/// the ship's actual home coordinates (a completely different key). They'd
/// sit under the ship's own scope forever and get blindly reapplied at the
/// wrong spot on every future retrieve -- not a duplicated ship, but
/// corrupted leftover content mixed into the real interior. Excluding these
/// turfs from the general sweep entirely avoids that: while docked, interior
/// changes simply aren't captured by the periodic autosave (only by the next
/// real shipInteriorSave(), which only ever runs once the ship is genuinely
/// back home -- see _drydockStashRun()) -- a real but safe limitation, not a
/// silent corruption path.
///
/// Kept live by _drydock_periodic_sweep() (persistence_shuttles.dm), which
/// rebuilds it from scratch every cycle for every deployed ship currently
/// away from its own home landmark.
GLOBAL_LIST_EMPTY(persistence_docked_turf_scope)

/// TRUE if this turf currently belongs to a ship that's physically docked
/// away from its own home Z right now -- see persistence_docked_turf_scope
/// above for why this must exclude, not redirect.
/proc/persistence_turf_docked_elsewhere(turf/T)
	return T && GLOB.persistence_docked_turf_scope[T]

/// TRUE if any deployed drydock ship is already using this template.
/// Shuttle datum names are per-template, and /datum/shuttle/New() hard-
/// CRASHes on a duplicate name (shuttle.dm) -- so only one instance of a
/// given hull class can be deployed at a time until per-instance shuttle
/// naming lands (Phase 4).
/proc/ship_template_already_deployed(template_id)
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/D = GLOB.drydock_ships[sid]
		if(D && !D.stashed && D.template_id == template_id)
			return TRUE
	return FALSE

/**
 * Deletes every persistence DB row keyed to the given ship scope, across all
 * 8 content tables. The map_path-keyed sibling of purgeZRows()
 * (persistence_zlevel_reset.dm) -- used when a ship is sold/deleted so its
 * interior can never resurrect onto a future hull.
 */
/datum/controller/subsystem/persistence/proc/purgeShipScopeRows(scope, quiet = FALSE)
	if(!databaseCheckConnection("purgeShipScopeRows"))
		return FALSE
	var/list/deletes = list(
		"ss13_worldstate_turfs"    = "DELETE FROM ss13_worldstate_turfs WHERE map_path = :mp",
		"ss13_persistent_objects"  = "DELETE FROM ss13_persistent_objects WHERE map_path = :mp",
		"ss13_floor_items"         = "DELETE FROM ss13_floor_items WHERE map_path = :mp",
		"ss13_removed_structures"  = "DELETE FROM ss13_removed_structures WHERE map_path = :mp",
		"ss13_persistent_bots"     = "DELETE FROM ss13_persistent_bots WHERE map_path = :mp",
		"ss13_atmos_zones"         = "DELETE FROM ss13_atmos_zones WHERE map_path = :mp",
		"ss13_worldstate_objects"  = "DELETE FROM ss13_worldstate_objects WHERE map_path = :mp",
		"ss13_persistent_areas"    = "DELETE FROM ss13_persistent_areas WHERE map_path = :mp"
	)
	for(var/table in deletes)
		var/datum/db_query/dq = SSdbcore.NewQuery(deletes[table], list("mp" = scope))
		dq.Execute()
		databaseCheckQueryResult(dq, "purgeShipScopeRows [table]")
		qdel(dq)
	if(!quiet)
		log_subsystem_persistence_info("Purged persistence DB rows for ship scope [scope].")
	return TRUE

/**
 * Capture a deployed ship's full interior state under its scope: turfs,
 * machinery worldstate, floor items, tracked objects, bots, atmos. Called by
 * stash (before teardown) and by the shutdown auto-stash sweeps. Each step
 * is the per-Z sibling of the corresponding world Finalize proc, so the
 * serialization logic is shared, not duplicated. The z must still be
 * registered in GLOB.persistence_ship_z when this runs, so every row keys
 * under the ship scope.
 */
/datum/controller/subsystem/persistence/proc/shipInteriorSave(z, scope)
	if(!databaseCheckConnection("shipInteriorSave"))
		return FALSE
	log_subsystem_persistence_info("Ship interiors: saving z=[z] under [scope]...")
	try
		turfsFinalizeZ(z)
	catch(var/exception/turfs_e)
		log_subsystem_persistence_error("Ship interiors: turf save failed for [scope]: [turfs_e]")
	try
		areasFinalizeZ(z, scope)
	catch(var/exception/areas_e)
		log_subsystem_persistence_error("Ship interiors: blueprint area save failed for [scope]: [areas_e]")
	try
		worldstateFinalizeZ(z, scope)
	catch(var/exception/ws_e)
		log_subsystem_persistence_error("Ship interiors: worldstate save failed for [scope]: [ws_e]")
	try
		floorItemsFinalizeZ(z, scope)
	catch(var/exception/fi_e)
		log_subsystem_persistence_error("Ship interiors: floor item save failed for [scope]: [fi_e]")
	try
		objectsFinalizeZ(z, scope)
	catch(var/exception/obj_e)
		log_subsystem_persistence_error("Ship interiors: tracked object save failed for [scope]: [obj_e]")
	try
		botsFinalizeZ(z, scope)
	catch(var/exception/bots_e)
		log_subsystem_persistence_error("Ship interiors: bot save failed for [scope]: [bots_e]")
	try
		atmosFinalizeZ(z, scope)
	catch(var/exception/atmos_e)
		log_subsystem_persistence_error("Ship interiors: atmos save failed for [scope]: [atmos_e]")
	_shipLedgerTouchSavedAt(scope)
	return TRUE

/**
 * Re-apply a ship's saved interior onto its freshly template-loaded Z:
 * remap rows to the new z, then tombstones, turfs, tracked objects, floor
 * items, machinery worldstate, bots, powernet rebuild, and a delayed atmos
 * apply (ZAS needs a few ticks to rebuild zones once SSair resumes). A ship
 * that has never been saved (pristine template) has no rows under its scope
 * and every step no-ops.
 */
/datum/controller/subsystem/persistence/proc/shipInteriorApply(z, scope)
	if(!databaseCheckConnection("shipInteriorApply"))
		return FALSE
	log_subsystem_persistence_info("Ship interiors: applying [scope] to z=[z]...")
	remapShipRows(scope, z, quiet = TRUE)
	try
		removedStructuresApplyZ(z, scope)
	catch(var/exception/rs_e)
		log_subsystem_persistence_error("Ship interiors: tombstone apply failed for [scope]: [rs_e]")
	try
		turfsApplyZ(z, scope)
	catch(var/exception/turfs_e)
		log_subsystem_persistence_error("Ship interiors: turf apply failed for [scope]: [turfs_e]")
	try
		areasApplyZ(z, scope)
	catch(var/exception/areas_e)
		log_subsystem_persistence_error("Ship interiors: blueprint area apply failed for [scope]: [areas_e]")
	try
		objectsApplyZ(z, scope)
	catch(var/exception/obj_e)
		log_subsystem_persistence_error("Ship interiors: tracked object apply failed for [scope]: [obj_e]")
	try
		floorItemsApplyZ(z, scope)
	catch(var/exception/fi_e)
		log_subsystem_persistence_error("Ship interiors: floor item apply failed for [scope]: [fi_e]")
	try
		worldstateApplyZ(z, scope)
	catch(var/exception/ws_e)
		log_subsystem_persistence_error("Ship interiors: worldstate apply failed for [scope]: [ws_e]")
	try
		botsApplyZ(z, scope)
	catch(var/exception/bots_e)
		log_subsystem_persistence_error("Ship interiors: bot apply failed for [scope]: [bots_e]")
	try
		// Restored cables sit on isolated powernets until rebuilt -- same
		// proc the boot restore runs after its own turf/object apply
		// (persistence.dm:614).
		SSmachinery.makepowernets()
	catch(var/exception/pn_e)
		log_subsystem_persistence_error("Ship interiors: powernet rebuild failed for [scope]: [pn_e]")
	addtimer(CALLBACK(src, PROC_REF(_shipInteriorApplyFinish), z, scope), 15 SECONDS)
	return TRUE

/// Runs the deferred atmos apply, then -- for a ship scope only -- flips
/// DS.ready back on and notifies the owner if they're connected. Boarding
/// (_drydock_board_core(), telepad_drydock_boarding.dm) refuses while a
/// ship's ready flag is FALSE, so nobody boards mid-load; this is what
/// clears that gate once the background settle genuinely finishes.
/datum/controller/subsystem/persistence/proc/_shipInteriorApplyFinish(z, scope)
	atmosApplyZ(z, scope)
	if(copytext(scope, 1, 8) != "ship:d:")
		return
	var/shuttle_id = text2num(copytext(scope, 8))
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS || DS.stashed || DS.z != z)
		return
	// refresh_fuel_ports_list() (overmap_shuttle.dm) only ever runs once, at
	// the shuttle datum's own New() -- which fires at template-load time,
	// before objectsApplyZ() (above) has restored this ship's own saved fuel
	// ports onto the z. Without this, any drydock ship's fuel_ports stays
	// permanently empty on every single retrieve, not just the first
	// commission -- same gap, same fix, run here for every ship type.
	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[z]"]
	var/datum/shuttle/autodock/overmap/shuttle_datum = istype(marker) ? SSshuttle.shuttles[marker.shuttle] : null
	if(istype(shuttle_datum))
		shuttle_datum.refresh_fuel_ports_list()
#ifdef DRYDOCK_ENGINE_DIAGNOSTICS
		log_debug("ENGINE DIAG: retrieve refresh_fuel_ports_list() for '[shuttle_datum.name]' found [length(shuttle_datum.fuel_ports)] fuel port(s) across areas [english_list(shuttle_datum.shuttle_area)].")
#endif

	// Retrieve rebuilds this ship's z from its template, which restores the
	// template's own mapped landmark position -- dead centre of the room, for
	// player_built_shuttle. That silently undoes the commission-time anchoring
	// on a ship's very first stash/retrieve cycle, after which every dock is
	// misaligned by half a hull and beacons stop appearing in the destination
	// list at all. Re-anchor here, now that objectsApplyZ() above has actually
	// restored the transponder onto this z. Scoped to player-built hulls --
	// a mapper-authored template ship's landmark is placed deliberately.
	var/datum/map_template/drydock_ship/finish_template = SSmapping.drydock_ship_templates[DS.template_id]
	if(istype(shuttle_datum) && finish_template && finish_template.hidden_from_catalog)
		_drydock_reposition_ship_landmark(marker, shuttle_datum, "retrieve (shuttle_id=[shuttle_id])")

	DS.ready = TRUE
	log_drydock("_shipInteriorApplyFinish: shuttle_id=[shuttle_id] finished background settle, ready to board.")
	if(DS.owner_ckey)
		var/client/C = GLOB.directory[DS.owner_ckey]
		if(C?.mob)
			to_chat(C.mob, SPAN_GOOD("Your ship '[DS.display_name()]' has finished initializing and is ready to board."))
			play_announcer_sound_priority(C.mob, 'sound/AI/announcements/ship_ready_to_board.ogg')

/**
 * Keeps each deployed ship's ledger overmap_x/y current with its live
 * marker position. Called from the periodic forceSaveAll() in place of
 * auto-stashing deployed ships (persistence.dm) -- interiors already save
 * in place via the ordinary Finalize sweeps, so the ledger just needs its
 * position kept fresh in case of a crash before the next graceful Stash.
 */
/datum/controller/subsystem/persistence/proc/shipLedgerPositionSync()
	if(!databaseCheckConnection("shipLedgerPositionSync"))
		return
	var/synced = 0
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed)
			continue
		var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[DS.z]"]
		if(!istype(marker))
			continue
		DS.overmap_x = marker.x
		DS.overmap_y = marker.y
		var/datum/db_query/q = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET overmap_x = :x, overmap_y = :y WHERE shuttle_id = :id",
			list("x" = marker.x, "y" = marker.y, "id" = sid)
		)
		q.Execute()
		databaseCheckQueryResult(q, "shipLedgerPositionSync")
		qdel(q)
		synced++
	log_subsystem_persistence_info("Ship interiors: synced overmap position for [synced] deployed ship(s).")

/**
 * Full teardown of a stashed ship's Z, releasing it into the reuse pool.
 * Modeled on _despawn_away_site_z() (persistence_factions.dm) plus the
 * shuttle-registry cleanup that proc never needed: without qdel'ing the
 * /datum/shuttle, re-retrieving the same template CRASHes on the duplicate
 * shuttle name check in /datum/shuttle/New() (shuttle.dm), and its stale
 * landmark tags block the new copy's registration.
 *
 * Caller contract (see corvetteStash()/drydockStash()): the interior was
 * already saved (shipInteriorSave()), the overmap marker already qdel'd and
 * its GLOB.map_sectors entries nulled, and the z already removed from
 * GLOB.persistence_ship_z. shuttle_name is the marker's shuttle datum name,
 * captured before the marker was destroyed.
 */
/datum/controller/subsystem/persistence/proc/shipZTeardown(z, shuttle_name)
	if(!z)
		return

	// 1. Shuttle datum + landmark registry cleanup.
	if(shuttle_name)
		var/datum/shuttle/S = SSshuttle.shuttles[shuttle_name]
		if(S)
			for(var/area/A in S.shuttle_area)
				SSshuttle.shuttle_areas -= A
			qdel(S) // Destroy() cleans SSshuttle.shuttles/process_shuttles itself
	for(var/tag in SSshuttle.registered_shuttle_landmarks.Copy())
		var/obj/effect/shuttle_landmark/L = SSshuttle.registered_shuttle_landmarks[tag]
		if(QDELETED(L) || L.z == z)
			SSshuttle.registered_shuttle_landmarks -= tag

	// 2. Movable wipe. Pass 1 is a type-indexed world scan (the safe pattern):
	// qdel'ing an object can itself spawn/drop a new movable as a side effect
	// (an APC ejecting its cell is normal APC behavior), which a one-shot
	// turf/contents snapshot taken before that qdel would never catch.
	// Passes 2+ mop up whatever pass 1's qdel cascade freshly ejected -- those
	// land directly on a turf (never nested), so a Z-scoped turf/contents
	// re-check is safe there and, critically, bounded to this Z's own turf
	// count instead of a second full for(TYPE in world) sweep. Repeating the
	// world-wide scan every pass was the actual hang: qdel() only calls
	// Destroy() immediately (SSgarbage defers the real del()), so a just-qdel'd
	// object with its .loc/.z untouched keeps matching on every subsequent
	// pass, guaranteeing all 5 passes ran as full-world scans every time.
	for(var/atom/movable/AM in world)
		CHECK_TICK
		if(AM.z != z)
			continue
		try
			qdel(AM)
		catch(var/exception/qdel_e)
			log_subsystem_persistence_error("Ship interiors: shipZTeardown qdel failed for [AM] on z=[z]: [qdel_e]")

	var/pass = 1
	var/found_any = TRUE
	while(found_any && pass < 5)
		found_any = FALSE
		pass++
		for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			CHECK_TICK
			var/list/contents_snapshot = T.contents.Copy()
			for(var/atom/movable/AM in contents_snapshot)
				try
					qdel(AM)
				catch(var/exception/qdel_e)
					log_subsystem_persistence_error("Ship interiors: shipZTeardown mop-up qdel failed for [AM] on z=[z]: [qdel_e]")
				found_any = TRUE

	// 3. Turf wipe -- movables are actually gone now, safe to convert every
	// turf to space unconditionally.
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		T.ChangeTurf(/turf/space)
		CHECK_TICK

	// 4. Area reassignment back to the world default -- a smaller future
	// template must not inherit a ring of turfs still claimed by the old
	// hull's area instances. Same primitive blueprints/areasInitialize use.
	var/area/default_area = locate(world.area)
	if(default_area)
		for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/area/current = T.loc
			if(current != default_area)
				T.change_area(current, default_area)
			CHECK_TICK

	// 5. Bookkeeping: template registry, zone security, stray current-map
	// persistence rows at this z (legacy pre-migration deployments must not
	// leak onto the next occupant -- ship-scope rows are untouched, they
	// live under a different map_path).
	GLOB.map_templates -= "[z]"
	GLOB.zone_security_by_z -= "[z]"
	purgeZRows(z, quiet = TRUE)

	// 6. Release into the shared reuse pool.
	poolReusableZ(z)

/**
 * Marks a wiped, contentless Z as available for reuse by a future
 * load_into_z() call -- the shared release step for both ship teardown
 * (above) and away/mission site teardown (_despawn_away_site_z(),
 * persistence_factions.dm). Guards are structural invariants for the ship
 * path (only stash calls shipZTeardown()); for the away/mission path they
 * matter for real -- a pinned site's z, or one still claimed by a deployed
 * ship, must never be handed out to something else.
 */
/datum/controller/subsystem/persistence/proc/poolReusableZ(z)
	if(!z)
		return
	if(!GLOB.persistence_allow_z_reuse)
		return // reuse disabled server-wide -- don't pool it in the first place
	if((z in GLOB.persistence_pinned_site_z) || GLOB.persistence_ship_z["[z]"] || is_station_level(z))
		return
	GLOB.reusable_z_pool |= z
	log_subsystem_persistence_info("Persistence: z=[z] released into the reusable Z pool ([length(GLOB.reusable_z_pool)] pooled).")

/**
 * Pops a reusable Z for a fresh spawn (ship retrieve or away/mission site
 * generation), revalidating it before handing it out. Returns 0 if none is
 * available (caller falls back to load_new_z()).
 */
/datum/controller/subsystem/persistence/proc/acquireReusableZ()
	if(!GLOB.persistence_allow_z_reuse)
		return 0 // caller falls back to load_new_z() for a brand-new z
	while(length(GLOB.reusable_z_pool))
		var/z = GLOB.reusable_z_pool[1]
		GLOB.reusable_z_pool.Cut(1, 2)
		if(z < 1 || z > world.maxz)
			continue
		if(z in GLOB.persistence_pinned_site_z)
			continue
		if(GLOB.persistence_ship_z["[z]"])
			continue
		if(zlevel_has_players(z))
			continue
		// Runs regardless of the reuse toggle above -- the cheap guards to
		// this point only prove nobody has CLAIMED this z, not that it's
		// actually empty. Anything still here means a teardown didn't
		// complete, and handing it to a ship would materialize that hull on
		// top of the leftovers.
		if(!_z_is_verifiably_empty(z))
			log_subsystem_persistence_warning("Persistence: z=[z] rejected from the reusable pool -- not verifiably empty (leftover content from an incomplete teardown). Dropped rather than reused.")
			continue
		return z
	return 0

/// TRUE only if z genuinely holds nothing a correct teardown should have
/// left behind: no simulated turfs, no living mobs, no machinery. Bounded
/// single-z scan with CHECK_TICK -- trivial next to the map-template load the
/// caller is about to perform anyway, and the only thing standing between a
/// half-torn-down z and a ship being rebuilt on top of its leftovers.
/datum/controller/subsystem/persistence/proc/_z_is_verifiably_empty(z)
	if(z < 1 || z > world.maxz)
		return FALSE
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		CHECK_TICK
		if(istype(T, /turf/simulated))
			return FALSE
		for(var/atom/movable/AM in T)
			if(isliving(AM))
				return FALSE
			if(istype(AM, /obj/structure/machinery))
				return FALSE
	return TRUE

/// Stamps interior_saved_at = NOW() on the ledger row the scope key encodes
/// ("ship:d:<shuttle_id>").
/datum/controller/subsystem/persistence/proc/_shipLedgerTouchSavedAt(scope)
	PRIVATE_PROC(TRUE)
	if(findtext(scope, "ship:d:") != 1)
		return
	var/ledger_id = text2num(copytext(scope, 8))
	if(!ledger_id)
		return
	var/datum/db_query/tq = SSdbcore.NewQuery(
		"UPDATE ss13_drydock_ships SET interior_saved_at = NOW() WHERE shuttle_id = :id",
		list("id" = ledger_id)
	)
	tq.Execute()
	databaseCheckQueryResult(tq, "_shipLedgerTouchSavedAt")
	qdel(tq)

/**
 * Points every persistence DB row under the given ship scope at a new live
 * z. One UPDATE per table -- x/y never change because ship templates always
 * load centered at the same coordinates (see remapZRows() for the identical
 * reasoning on pinned away sites). Called by retrieve after the template is
 * loaded onto its (possibly pooled, possibly fresh) Z.
 */
/datum/controller/subsystem/persistence/proc/remapShipRows(scope, new_z, quiet = FALSE)
	if(!databaseCheckConnection("remapShipRows"))
		return FALSE
	var/list/updates = list(
		"ss13_worldstate_turfs"    = "UPDATE ss13_worldstate_turfs SET z = :nz WHERE map_path = :mp",
		"ss13_persistent_objects"  = "UPDATE ss13_persistent_objects SET z = :nz WHERE map_path = :mp",
		"ss13_floor_items"         = "UPDATE ss13_floor_items SET z = :nz WHERE map_path = :mp",
		"ss13_removed_structures"  = "UPDATE ss13_removed_structures SET z = :nz WHERE map_path = :mp",
		"ss13_persistent_bots"     = "UPDATE ss13_persistent_bots SET z = :nz WHERE map_path = :mp",
		"ss13_atmos_zones"         = "UPDATE ss13_atmos_zones SET rep_z = :nz WHERE map_path = :mp",
		"ss13_worldstate_objects"  = "UPDATE ss13_worldstate_objects SET z = :nz WHERE map_path = :mp"
	)
	for(var/table in updates)
		var/datum/db_query/uq = SSdbcore.NewQuery(updates[table], list("nz" = new_z, "mp" = scope))
		uq.Execute()
		databaseCheckQueryResult(uq, "remapShipRows [table]")
		qdel(uq)
	if(!quiet)
		log_subsystem_persistence_info("Remapped ship scope [scope] persistence rows to z=[new_z].")
	return TRUE
