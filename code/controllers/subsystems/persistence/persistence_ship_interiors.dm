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

/// The z currently being captured by shipInteriorSave(), or 0.
///
/// A ship's own interior save is AUTHORITATIVE for its z -- it must record what
/// is physically sitting there, unconditionally. The docked-turf exclusion above
/// exists purely to stop the general, z-scoped sweeps misattributing a docked
/// hull's turfs to the host station; applying it to the ship's own save is
/// nonsense, and it was actively destructive: floorItemsFinalizeZ() DELETEs the
/// whole ship scope up front and then rebuilds it, so a stale exclusion entry
/// suppressed every row and committed an EMPTY scope over good data, wiping the
/// ship's floor contents outright. Tracked machines fared no better -- their
/// add/update calls consult the same exclusion, freezing each machine at the
/// last state written (usually "empty, as built").
GLOBAL_VAR_INIT(persistence_interior_save_z, 0)

/// TRUE if this turf currently belongs to a ship that's physically docked
/// away from its own home Z right now -- see persistence_docked_turf_scope
/// above for why this must exclude, not redirect.
///
/// Never TRUE for the z a shipInteriorSave() is currently capturing: that save
/// IS the ship's own, so it must never skip the ship's own turfs.
/proc/persistence_turf_docked_elsewhere(turf/T)
	if(!T)
		return FALSE
	if(GLOB.persistence_interior_save_z && T.z == GLOB.persistence_interior_save_z)
		return FALSE
	return GLOB.persistence_docked_turf_scope[T]

/// TRUE if any deployed drydock ship is already using this template.
/// TRUE if any deployed (non-stashed) ship uses this template.
///
/// No longer a deployment gate: per-instance shuttle/landmark naming
/// (GLOB.drydock_loading_suffix, persistence_shuttles.dm) means multiple hulls
/// of one class can now be deployed simultaneously, so drydockRetrieve() no
/// longer refuses on this. Kept as a plain query for anything that wants to
/// know whether a class is currently in play.
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
	// This save is authoritative for this z -- suspend the docked-turf exclusion
	// for it, or a stale entry silently blanks the ship's entire interior. See
	// GLOB.persistence_interior_save_z's own doc comment.
	GLOB.persistence_interior_save_z = z
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
	GLOB.persistence_interior_save_z = 0
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
	// Every optional step below is individually guarded, because this proc is
	// the ONLY thing that sets DS.ready. It runs detached on a timer, so an
	// uncaught runtime anywhere in it used to leave ready FALSE forever: no
	// "ready to board" notification, boarding refused permanently, and the
	// ship recoverable only by stashing it again. A skipped atmos settle or
	// fuel-port refresh is recoverable; a permanently unboardable ship is not.
	try
		atmosApplyZ(z, scope)
	catch(var/exception/atmos_e)
		log_subsystem_persistence_error("Ship interiors: deferred atmos apply failed for [scope]: [atmos_e]")
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
	var/datum/shuttle/autodock/overmap/shuttle_datum = _drydock_shuttle_of(marker)
	if(istype(shuttle_datum))
		try
			shuttle_datum.refresh_fuel_ports_list()
		catch(var/exception/fuel_e)
			log_subsystem_persistence_error("Ship interiors: fuel port refresh failed for [scope]: [fuel_e]")
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
		try
			_drydock_reposition_ship_landmark(marker, shuttle_datum, "retrieve (shuttle_id=[shuttle_id])")
		catch(var/exception/anchor_e)
			log_subsystem_persistence_error("Ship interiors: landmark re-anchor failed for [scope]: [anchor_e]")

	// A sector created at RUNTIME never goes through initialize_sectors(), so
	// the waypoint tags populate_sector_objects() queued -- including this
	// ship's own "Open Space" home landmark -- are otherwise never turned into
	// real destinations. Without this the ship can dock somewhere and then has
	// no way to select home again. Safe here: the marker and its landmark are
	// fully settled by this point, and the call is idempotent.
	// See register_sector_waypoints() (controllers/subsystems/processing/shuttle.dm).
	try
		SSshuttle.register_sector_waypoints(marker)
	catch(var/exception/wp_e)
		log_subsystem_persistence_error("Ship interiors: sector waypoint registration failed for [scope]: [wp_e]")

	DS.ready = TRUE
	log_drydock("_shipInteriorApplyFinish: shuttle_id=[shuttle_id] finished background settle, ready to board.")
	if(DS.owner_ckey)
		var/client/C = GLOB.directory[DS.owner_ckey]
		if(C?.mob)
			to_chat(C.mob, SPAN_GOOD("Your ship '[DS.display_name()]' has finished initializing and is ready to board."))
			play_announcer_sound_priority(C.mob, 'sound/AI/announcements/ship_ready_to_board.ogg')
	else if(DS.faction_uid)
		// A faction-owned ship has NO owner_ckey -- it is null by construction
		// for a faction purchase, and drydockRepossess() explicitly nulls it
		// when seizing a hull for the Hub (persistence_shuttles.dm). So the
		// owner branch above matched nobody and these ships silently never
		// announced themselves ready, even though DS.ready had flipped and
		// their Enter/Stash buttons had already ungreyed. Tell the faction
		// instead. Member detection mirrors notify_faction_members()
		// (persistence_factions.dm); that helper is chat-only, and this needs
		// each mob to play the announcer line too, so the loop is inline.
		var/faction_uid = normalize_faction_uid(DS.faction_uid)
		for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
			if(!H.client)
				continue
			var/obj/item/card/id/ID = H.GetIdCard()
			if(!ID || !ID.employer_faction)
				continue
			if(normalize_faction_uid(ID.employer_faction) != faction_uid)
				continue
			to_chat(H, SPAN_GOOD("[get_faction_name(faction_uid)]'s ship '[DS.display_name()]' has finished initializing and is ready to board."))
			play_announcer_sound_priority(H, 'sound/AI/announcements/ship_ready_to_board.ogg')

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

	// 2/3. Movable + turf wipe.
	_wipeZContents(z, "shipZTeardown")

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

/// Z-levels a teardown has positively reported as emptied by its own hand.
///
/// Eligibility used to be inferred at acquire time from a chain of negative
/// guards -- "not pinned, not claimed, no players, looks empty" -- where any
/// link could veto in silence and the only visible symptom was the z count
/// climbing forever. This is the opposite: the code that actually wiped the z
/// states so, once, and the acquire path trusts that statement instead of
/// re-deriving it.
GLOBAL_LIST_EMPTY(persistence_reusable_z_verified)

/**
 * Marks a wiped, contentless Z as available for reuse by a future
 * load_into_z() call -- the shared release step for both ship teardown
 * (above) and away/mission site teardown (_despawn_away_site_z(),
 * persistence_factions.dm). Guards are structural invariants for the ship
 * path (only stash calls shipZTeardown()); for the away/mission path they
 * matter for real -- a pinned site's z, or one still claimed by a deployed
 * ship, must never be handed out to something else.
 */
/// Applies a display name to a z-level's own /datum/space_level label.
///
/// That label is set once when a template loads and nothing ever refreshed it,
/// so a renamed ship's level kept reading as its TEMPLATE name ("Player-Built
/// Shuttle") and a renamed away site's kept its own template default -- both
/// permanently, for the life of the level. Admin/VV-facing rather than
/// player-facing, which is why it went unnoticed, but it is still a stale
/// reference to something that has been renamed.
///
/// Bounds-checked because get_level() CRASHes on an unmanaged z rather than
/// returning null, and a cosmetic label refresh must never throw out of a
/// rename that has already committed to the database.
/proc/persistence_set_zlevel_label(z, new_name)
	if(!z || z < 1 || z > world.maxz || !new_name)
		return
	var/datum/space_level/level = SSmapping.get_level(z)
	if(istype(level))
		level.name = new_name

/// Z-levels that must never enter the reuse pool no matter what else says they
/// look free.
///
/// is_station_level() reads ZTRAIT_STATION and is the general answer, but it is
/// a cached macro keyed by z number and it is not the only thing worth being
/// careful about here. These decks hold the primary map and persistent player
/// content, and handing one to a ship or an away site would destroy a station
/// rather than recycle a scratch level -- so they get an explicit, unconditional
/// refusal that does not depend on a trait lookup being right.
///
/// DECK 4 is protected always.
///
/// DECKS 1-3 are protected unless persistence_disable_station is set. With that
/// config option on, the station map is never loaded and those levels are wiped
/// to open space at boot (persistence_world_ready.dm) while staying allocated --
/// genuinely free space, and reusing them is the whole point of running with the
/// station disabled. With it off (the normal case) they ARE the station.
#define PERSISTENCE_PROTECTED_DECK_ALWAYS 4
#define PERSISTENCE_PROTECTED_DECK_STATION_MAX 3

/proc/persistence_z_is_protected_deck(z)
	if(z == PERSISTENCE_PROTECTED_DECK_ALWAYS)
		return TRUE
	if(z >= 1 && z <= PERSISTENCE_PROTECTED_DECK_STATION_MAX && !GLOB.config.persistence_disable_station)
		return TRUE
	return FALSE

/// Every refusal below is logged. This used to return silently on the guard
/// chain, which meant a z that was never pooled left no trace anywhere -- the
/// pool simply stayed empty and every retrieve loaded a brand-new z, with
/// nothing to say why. "Reuse doesn't work" must never again be a question
/// static reading has to guess at.
/datum/controller/subsystem/persistence/proc/poolReusableZ(z)
	if(!z)
		return
	if(!GLOB.persistence_allow_z_reuse)
		log_subsystem_persistence_info("Persistence: z=[z] NOT pooled -- ship Z reuse is disabled server-wide.")
		return
	if(z in GLOB.persistence_pinned_site_z)
		log_subsystem_persistence_info("Persistence: z=[z] NOT pooled -- it is a pinned away site.")
		return
	if(GLOB.persistence_ship_z["[z]"])
		log_subsystem_persistence_warning("Persistence: z=[z] NOT pooled -- still claimed by ship scope '[GLOB.persistence_ship_z["[z]"]]'. The claim must be released BEFORE teardown (see _drydockMarkerTeardown()).")
		return
	if(is_station_level(z))
		log_subsystem_persistence_warning("Persistence: z=[z] NOT pooled -- flagged as a station level.")
		return
	if(persistence_z_is_protected_deck(z))
		log_subsystem_persistence_warning("Persistence: z=[z] NOT pooled -- it is a protected deck (see persistence_z_is_protected_deck()).")
		return
	// Someone's claimed territory. A faction beacon marks a z as a faction's
	// own station/site, and unlike a pinned site that claim is not recorded in
	// GLOB.persistence_pinned_site_z -- so without this an unpinned but actively
	// claimed station could be despawned into the pool and handed to another
	// ship, taking the players' base with it.
	if(GLOB.faction_beacon_by_z["[z]"])
		log_subsystem_persistence_warning("Persistence: z=[z] NOT pooled -- it is claimed by a faction beacon (someone's station).")
		return
	GLOB.reusable_z_pool |= z
	// Positive statement of fact from the code that actually emptied this z,
	// rather than acquireReusableZ() having to re-derive "probably safe" from a
	// chain of negative guards. See acquireReusableZ().
	GLOB.persistence_reusable_z_verified |= z
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
		var/was_verified = (z in GLOB.persistence_reusable_z_verified)
		GLOB.persistence_reusable_z_verified -= z
		// The remaining guards are about CURRENT ownership -- has anything
		// claimed this z since it was pooled -- not about whether the teardown
		// worked. That question is already answered by the verified set below.
		if(z < 1 || z > world.maxz)
			log_subsystem_persistence_warning("Persistence: pooled z=[z] discarded -- outside 1..[world.maxz].")
			continue
		if(z in GLOB.persistence_pinned_site_z)
			log_subsystem_persistence_warning("Persistence: pooled z=[z] discarded -- it became a pinned away site while pooled.")
			continue
		if(GLOB.persistence_ship_z["[z]"])
			log_subsystem_persistence_warning("Persistence: pooled z=[z] discarded -- claimed by ship scope '[GLOB.persistence_ship_z["[z]"]]' while pooled.")
			continue
		if(zlevel_has_players(z))
			log_subsystem_persistence_warning("Persistence: pooled z=[z] discarded -- players are present on it.")
			continue
		// Both re-checked here as well as in poolReusableZ(), deliberately. A z
		// can sit in the pool indefinitely, and a station level or a faction
		// claim appearing in the meantime must not be handed out just because it
		// was unclaimed at the moment it was pooled. Handing out someone's
		// station is not a mistake worth being one guard away from.
		if(is_station_level(z))
			log_subsystem_persistence_warning("Persistence: pooled z=[z] discarded -- it became a station level while pooled.")
			continue
		if(persistence_z_is_protected_deck(z))
			log_subsystem_persistence_error("Persistence: pooled z=[z] discarded -- it is a PROTECTED DECK and should never have been pooled. Investigate how it got in.")
			continue
		if(GLOB.faction_beacon_by_z["[z]"])
			log_subsystem_persistence_warning("Persistence: pooled z=[z] discarded -- a faction beacon claimed it while pooled (someone's station).")
			continue
		// The verified flag is a positive statement from the teardown that
		// actually emptied this z. A pooled z WITHOUT it was never confirmed
		// clean by anything -- it must not be trusted, so it goes through the
		// wipe-and-recheck path below rather than being handed straight out.
		// (This set was previously written and cleared but never read, so it
		// gated nothing at all.)
		var/teardown_vouched = was_verified
		if(!teardown_vouched)
			log_subsystem_persistence_warning("Persistence: pooled z=[z] has no teardown verification on record -- treating it as unclean and re-wiping before reuse.")

		// Retained as an ASSERTION, not as the primary test. A z in the pool
		// was put there by a teardown that reported having emptied it, so a
		// failure here means that report was wrong -- which is a teardown bug
		// worth naming loudly, not a routine "try the next one".
		var/list/leftovers = list()
		if(!teardown_vouched || !_z_is_verifiably_empty(z, leftovers))
			// Do NOT discard on the first failure. Discarding is what made the
			// z count climb forever: the z was pooled, rejected, dropped, and
			// every retrieve fell through to load_new_z(). This z has already
			// cleared every ownership guard above -- unclaimed, unpinned, no
			// players, not a station level -- so it belongs to nobody and
			// re-running the wipe on it is exactly what the teardown was
			// supposed to have achieved.
			log_subsystem_persistence_warning("Persistence: pooled z=[z] failed its emptiness assertion -- leftovers: [english_list(leftovers)]. Re-wiping and retrying rather than discarding it.")
			_wipeZContents(z, "acquireReusableZ retry")
			var/list/still_there = list()
			if(!_z_is_verifiably_empty(z, still_there))
				log_subsystem_persistence_error("Persistence: pooled z=[z] STILL not empty after a second wipe -- leftovers: [english_list(still_there)]. Discarded. This is a teardown defect; these types survive shipZTeardown().")
				continue
			log_subsystem_persistence_info("Persistence: z=[z] cleaned up on retry and is now reusable.")
		log_subsystem_persistence_info("Persistence: reusing pooled z=[z] ([length(GLOB.reusable_z_pool)] still pooled).")
		return z
	return 0

/// Strips every movable off z and converts every turf on it to space.
///
/// Shared by shipZTeardown() and acquireReusableZ()'s retry so both use one
/// implementation -- a pooled z that fails its emptiness assertion gets exactly
/// the same treatment the teardown was supposed to give it, rather than a
/// second, subtly different hand-written copy.
///
/// Pass 1 is a type-indexed world scan (the safe pattern): qdel'ing an object
/// can itself spawn/drop a new movable as a side effect (an APC ejecting its
/// cell is normal APC behavior), which a one-shot turf/contents snapshot taken
/// before that qdel would never catch. Passes 2+ mop up whatever pass 1's qdel
/// cascade freshly ejected -- those land directly on a turf (never nested), so
/// a Z-scoped turf/contents re-check is safe there and, critically, bounded to
/// this Z's own turf count instead of a second full for(TYPE in world) sweep.
/// Repeating the world-wide scan every pass was the actual hang: qdel() only
/// calls Destroy() immediately (SSgarbage defers the real del()), so a
/// just-qdel'd object with its .loc/.z untouched keeps matching on every
/// subsequent pass, guaranteeing all 5 passes ran as full-world scans.
/datum/controller/subsystem/persistence/proc/_wipeZContents(z, context = "wipeZ")
	if(!z || z < 1 || z > world.maxz)
		return
	// HARD GUARANTEE: never touch a z a deployed ship still claims. The
	// legitimate teardown path is unaffected -- _drydockMarkerTeardown() clears
	// GLOB.persistence_ship_z on the line before it calls shipZTeardown() -- but
	// this proc ends in an irreversible forced delete, and "whichever proc called
	// us was well-behaved" is an assumption, not a guarantee. Any accidental or
	// future call against a live ship's z stops here instead.
	if(GLOB.persistence_ship_z["[z]"])
		log_subsystem_persistence_error("Ship interiors: [context] REFUSED to wipe z=[z] -- it is still claimed by ship scope '[GLOB.persistence_ship_z["[z]"]]'. The claim must be released before a teardown. Nothing was deleted.")
		return
	// The same protected decks the reuse pool refuses. This proc ends in an
	// irreversible forced delete, so it gets its own copy of the check rather
	// than trusting every present and future caller to have made it first --
	// wiping the station because something called this with the wrong z is not
	// a recoverable mistake.
	if(persistence_z_is_protected_deck(z))
		log_subsystem_persistence_error("Ship interiors: [context] REFUSED to wipe z=[z] -- it is a protected deck (station/primary map). Nothing was deleted.")
		return
	if(GLOB.faction_beacon_by_z["[z]"])
		log_subsystem_persistence_error("Ship interiors: [context] REFUSED to wipe z=[z] -- it is claimed by a faction beacon (someone's station). Nothing was deleted.")
		return
	for(var/atom/movable/AM in world)
		CHECK_TICK
		if(AM.z != z)
			continue
		try
			qdel(AM)
		catch(var/exception/qdel_e)
			log_subsystem_persistence_error("Ship interiors: [context] qdel failed for [AM] on z=[z]: [qdel_e]")

	var/pass = 1
	var/removed_any = TRUE
	while(removed_any && pass < 5)
		removed_any = FALSE
		pass++
		for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			CHECK_TICK
			var/list/contents_snapshot = T.contents.Copy()
			for(var/atom/movable/AM in contents_snapshot)
				try
					qdel(AM)
				catch(var/exception/qdel_e)
					log_subsystem_persistence_error("Ship interiors: [context] mop-up qdel failed for [AM] on z=[z]: [qdel_e]")
				// Counts what was actually REMOVED, not what was merely seen.
				// Setting this per-sighting meant a single undeletable object
				// kept every pass "productive" and made the exhausted-passes
				// warning below fire on every teardown, healthy or not.
				if(QDELETED(AM) || AM.loc != T)
					removed_any = TRUE
	if(removed_any)
		log_subsystem_persistence_warning("Ship interiors: [context] used all its mop-up passes on z=[z] and was still removing movables -- the z may not be fully clean.")

	// Movables are gone, so converting every turf to space is safe.
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		T.ChangeTurf(/turf/space)
		CHECK_TICK

	// FINAL sweep, after the turf conversion. Does NOT use qdel().
	//
	// Two things survive everything above. ChangeTurf() can itself produce
	// movables -- a structure turf dropping debris, contents dumped onto the
	// tile as it converts -- so a pass has to run after it. And, the reason this
	// pass cannot be another qdel: qdel() (garbage.dm) short-circuits before
	// `force` is ever consulted --
	//
	//     if(!isnull(to_delete.gc_destroyed))  ... return   // already qdel'd
	//     if(SEND_SIGNAL(to_delete, COMSIG_PREQDELETED, force)) return // vetoed
	//
	// -- so the FIRST qdel is the only one that can accomplish anything, and
	// `force = TRUE` changes how Destroy() behaves only if Destroy() is reached
	// at all. A repeat attempt on something the earlier passes already failed on
	// is guaranteed to be a no-op. That is precisely what was happening: the
	// buildable shuttle control console outlived every pass, the pooled z failed
	// its emptiness assertion, was discarded, and every retrieve loaded a fresh
	// z while abandoned ones accumulated.
	//
	// So use the primitives instead. moveToNullspace() is the part that matters
	// for reuse -- it takes the object off the turf regardless of gc_destroyed,
	// component vetoes or deferred collection, and an empty z is all the caller
	// needs. del() then removes it outright; it cannot be vetoed and has no
	// early return (garbage.dm itself falls back to it). The cooperative passes
	// above are left untouched, so objects still get a normal Destroy() and
	// clean up their own references -- this only governs the stragglers, on a z
	// that is being recycled and where nothing has a future.
	//
	// Re-checked immediately before it runs, because everything above yields on
	// CHECK_TICK: a force-delete is irreversible, so it must never fire on a z
	// something has legitimately claimed while this proc was asleep. Drydock ops
	// are serialised by GLOB.drydock_op_active, but away/mission-site generation
	// also draws from the same pool without that lock, so "nothing else can be
	// here" is an assumption rather than a guarantee. Bail rather than assume.
	if(GLOB.persistence_ship_z["[z]"])
		log_subsystem_persistence_warning("Ship interiors: [context] skipped its forced sweep on z=[z] -- the z was claimed by '[GLOB.persistence_ship_z["[z]"]]' while the wipe was running. Nothing force-deleted.")
		return
	if(zlevel_has_players(z))
		log_subsystem_persistence_warning("Ship interiors: [context] skipped its forced sweep on z=[z] -- players are present. Nothing force-deleted.")
		return
	// An OCCUPIED neural lace is a person. It is an /obj/item/organ, not a mob,
	// so isliving() below does not cover it and a forced delete would destroy
	// someone with no body to fall back to. zlevel_has_players() is understood
	// to catch laces too, but this is the irreversible step -- check it here
	// directly rather than depending on another proc's definition holding.
	for(var/obj/item/organ/internal/neural_lace/L in world)
		CHECK_TICK
		var/turf/lace_turf = get_turf(L)
		if(lace_turf && lace_turf.z == z && L.lace_occupied)
			log_subsystem_persistence_error("Ship interiors: [context] skipped its forced sweep on z=[z] -- an OCCUPIED neural lace ([L]) is present at ([lace_turf.x],[lace_turf.y]). Nothing force-deleted; that z is not free to recycle.")
			return

	var/forced = 0
	var/list/forced_types = list()
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		CHECK_TICK
		for(var/atom/movable/AM in T.contents.Copy())
			if(isliving(AM))
				continue //never force-delete a living mob, whatever it is doing here
			if(istype(AM, /obj/item/organ/internal/neural_lace))
				continue //someone's mind may live in here -- never forced, occupied or not
			forced_types |= "[AM.type]"
			forced++
			// Deregistered by hand, because neither route below will do it.
			// /obj/Destroy() (objs.dm) normally deregisters tracked objects, but
			// anything reaching this sweep is here precisely BECAUSE its
			// Destroy() never ran -- qdel() short-circuited before it -- and
			// del() below is a hard delete that bypasses Destroy() as well. Left
			// alone, the object would vanish while GLOB.persistence_object_track_register
			// kept a dangling entry for it.
			if(isobj(AM))
				var/obj/tracked = AM
				if(tracked.persistent_objects_track_active)
					SSpersistence.objectsDeregisterTrack(tracked)
			try
				// Off the turf first. This is what actually frees the z, and it
				// works even when the object cannot be deleted at all.
				AM.moveToNullspace()
			catch(var/exception/move_e)
				log_subsystem_persistence_error("Ship interiors: [context] could not move [AM] ([AM.type]) to nullspace on z=[z]: [move_e]")
			try
				del(AM)
			catch(var/exception/del_e)
				log_subsystem_persistence_error("Ship interiors: [context] hard delete failed for [AM] ([AM.type]) on z=[z]: [del_e]")
	if(forced)
		log_subsystem_persistence_info("Ship interiors: [context] hard-removed [forced] movable(s) that survived the cooperative passes on z=[z]: [english_list(forced_types)].")

/// TRUE only if z genuinely holds nothing a correct teardown should have left
/// behind: no simulated turfs, no living mobs, no machinery. Bounded single-z
/// scan with CHECK_TICK -- trivial next to the map-template load the caller is
/// about to perform anyway, and the only thing standing between a half-torn-down
/// z and a ship being rebuilt on top of its leftovers.
///
/// found_out, when passed, is filled with human-readable descriptions of the
/// first few offenders. Returning a bare FALSE meant the rejection log could
/// only say "not empty", which is why a z silently failing this took a log dig
/// and a round of guessing to even locate. Name the leftovers instead.
/datum/controller/subsystem/persistence/proc/_z_is_verifiably_empty(z, list/found_out)
	if(z < 1 || z > world.maxz)
		return FALSE
	. = TRUE
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		CHECK_TICK
		// With found_out supplied, keep scanning long enough to characterise the
		// leftovers rather than bailing on the first one -- one stray machine and
		// a whole un-wiped room need different fixes, and the first hit alone
		// cannot tell them apart. Capped so a fully-populated z can't spam.
		if(!found_out && !.)
			return FALSE
		if(length(found_out) >= 8)
			return FALSE
		if(istype(T, /turf/simulated))
			. = FALSE
			LAZYADD(found_out, "[T.type] at ([T.x],[T.y],[T.z])")
			continue
		for(var/atom/movable/AM in T)
			if(isliving(AM))
				. = FALSE
				LAZYADD(found_out, "living mob [AM] at ([T.x],[T.y],[T.z])")
			else if(istype(AM, /obj/item/organ/internal/neural_lace))
				// Reported whether occupied or not: an occupied one is a person
				// and blocks reuse outright, and a loose one still belongs to
				// somebody and should be vaulted, not recycled away silently.
				var/obj/item/organ/internal/neural_lace/L = AM
				. = FALSE
				LAZYADD(found_out, "[L.lace_occupied ? "OCCUPIED " : ""]neural lace [L] at ([T.x],[T.y],[T.z])")
			else if(istype(AM, /obj/structure/machinery))
				. = FALSE
				LAZYADD(found_out, "machinery [AM] ([AM.type]) at ([T.x],[T.y],[T.z])")

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
