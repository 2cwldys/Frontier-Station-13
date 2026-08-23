/*
 * Persistence - World State
 * Saves and restores station machinery state across rounds via SQL.
 * Each machine is identified by its (type, x, y, z) position.
 *
 * Pattern (Persistent-Bay inspired):
 *   - Types declare /atom/movable/var/list/worldstate_vars = list("var1", "var2", ...)
 *   - Base procs read/write those vars using BYOND's runtime vars[] accessor automatically
 *   - Types with complex serialization (vending stock, closet contents, etc.) override the procs directly
 *   - worldstateInitialize / worldstateFinalize use blanket loops  no per-type loop needed
 *
 * Adding a new type: just set worldstate_vars on the type. No loop edits required.
 */

/// Cache of worldstate data keyed by "[typepath]|[x]|[y]|[z]", or
/// "[typepath]|site:[template_id]|[x]|[y]" for machines on a pinned away
/// site -- see worldstate_pinned_site_key() below.
GLOBAL_LIST_EMPTY(persistence_worldstate_cache)

/// For a pinned away-site's Z, returns that site's own template id -- a
/// stable identifier across boots, unlike the Z number itself (pinned
/// sites are Z-allocated by sequential append in build_pinned_away_sites(),
/// so the same site can land on a different Z every boot -- confirmed by
/// the rename-site code's own last_z staleness handling in
/// persistence_factions.dm). Returns null for anything else (ordinary
/// station Z's, or a template-loaded-but-unpinned Z like a drydock ship/
/// corvette -- those are already fully excluded from worldstate by
/// persistence_z_excluded() before this ever runs, and unlike a pinned
/// site, more than one live instance of the same template can exist at
/// once for those, so template id alone wouldn't be a safe key there).
/proc/worldstate_pinned_site_key(z)
	if(!(z in GLOB.persistence_pinned_site_z))
		return null
	var/datum/map_template/T = GLOB.map_templates["[z]"]
	return T ? T.id : null

// =====================================================================
// BASE PROCS  declarative var list drives automatic save/restore
// =====================================================================

/// Set this list on any type to have worldstate save/restore those vars automatically.
/// Leave null (default) to opt out of worldstate entirely.
/atom/movable/var/list/worldstate_vars = null

/// Cache-key type for worldstate save/restore matching. Defaults to the
/// object's own type -- override only when a type is allowed to change at
/// runtime (e.g. glass conversion) and should still key/match consistently
/// across that change.
/atom/movable/proc/worldstate_key_type()
	return type

/// Generic get  reads each var in worldstate_vars via BYOND runtime src.vars[] accessor.
/// Types with complex state (nested objects, list-encoded fields) override this proc directly.
/atom/movable/proc/worldstate_get_content()
	if(!worldstate_vars) return null
	var/list/content = list()
	for(var/v in worldstate_vars)
		content[v] = src.vars[v]
	return content

/// Generic apply  writes each var from the saved content dict back to the object.
/// Calls update_icon() afterward; types needing different post-apply hooks override this proc.
/atom/movable/proc/worldstate_apply_content(list/content)
	if(!worldstate_vars) return
	for(var/v in worldstate_vars)
		if((v in content) && !isnull(content[v]))
			// Faction uids saved before normalization may be raw display names
			if(v == "persistent_network")
				src.vars[v] = normalize_faction_uid(content[v])
			else
				src.vars[v] = content[v]
	update_icon()

// =====================================================================
// SUBSYSTEM PROCS
// =====================================================================

/**
 * Load saved machinery state from the database into the in-memory cache,
 * then apply it to all matching map objects.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/worldstateInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_worldstate_cache = list()

	if(!databaseCheckConnection("worldstateInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, z, content FROM ss13_worldstate_objects WHERE map_path = :map_path",
		list("map_path" = SSatlas.current_map.path)
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "worldstateInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		CHECK_TICK
		var/db_type = query.item[1]
		var/db_x = query.item[2]
		var/db_y = query.item[3]
		var/db_z = query.item[4]
		var/db_content = query.item[5]
		var/cache_key = "[db_type]|[db_x]|[db_y]|[db_z]"
		// A row saved while its site was pinned carries its own stable
		// site key in the content -- prefer that over the raw z it was
		// saved under, since a pinned site's z isn't stable across boots
		// (see worldstate_pinned_site_key() above).
		var/list/parsed = json_decode(db_content)
		if(islist(parsed) && parsed["__worldstate_site"])
			cache_key = "[db_type]|site:[parsed["__worldstate_site"]]|[db_x]|[db_y]"
		GLOB.persistence_worldstate_cache[cache_key] = db_content
		loaded++

	qdel(query)
	log_subsystem_persistence_info("Worldstate: Loaded [loaded] machine state entries from database.")

	if(!loaded)
		return

	var/applied = 0

	// Single blanket loop  covers all /obj/structure subtypes (machinery, closets, tables, grilles, etc.)
	// Only types with worldstate_vars set or explicit proc overrides will actually save/load.
	for(var/obj/structure/S in world)
		if(persistence_z_excluded(S.z)) continue
		applied += worldstateApplyToMachine(S)

	// Items that need worldstate but aren't structures
	for(var/obj/item/radio/intercom/IC in world)
		if(persistence_z_excluded(IC.z)) continue
		applied += worldstateApplyToMachine(IC)

	for(var/obj/item/modular_computer/MC in world)
		if(persistence_z_excluded(MC.z)) continue
		applied += worldstateApplyToMachine(MC)

	log_subsystem_persistence_info("Worldstate: Applied saved state to [applied] machines.")

/**
 * Deterministic power-state resync, called as the final step of
 * SSpersistence.Initialize() AFTER makepowernets(). The worldstate restore
 * above overwrites APC channels/autoflag/cell charge (and SMES charge) but
 * only calls update_icon() -- area.power_light/equip/environ are ONLY written
 * by apc/update(), so without this sweep the area flags and every machine's
 * cached NOPOWER stat are left to converge via racy timers (batteryless
 * modular computers refuse to turn on, ATMs render lit but reject use, etc).
 */
/datum/controller/subsystem/persistence/proc/powerstateFinalize()
	var/apc_count = 0
	var/list/apc_areas = list()
	for(var/obj/structure/machinery/power/apc/A in world)
		if(!A.z) continue
		if(A.cell)
			A.update_channels()  // re-derive channel bits from the RESTORED cell charge
		A.update()               // write area power flags (broadcasts on change)
		A.update_icon()          // refresh the visible charge/equipment/lighting overlays to match
		if(A.area)
			apc_areas |= A.area
			// Flags the exact bug class where an APC got recreated before its
			// real area was restored, permanently binding it to the background
			// area instead -- self-reporting if this ever regresses.
			if(A.area.area_flags & AREA_FLAG_IS_BACKGROUND)
				log_subsystem_persistence_error("Worldstate: APC '[A.name]' at ([A.x],[A.y],[A.z]) resolved to background area '[A.area.name]' -- likely restored before its real area, or was never claimed by one.")
		apc_count++

	var/solar_count = 0
	for(var/obj/structure/machinery/power/solar_control/SC in world)
		if(!SC.z) continue
		// search_for_connected() only scans an already-established powernet --
		// if the control's own Initialize()-time connect_to_network() ran before
		// player-modified cabling was restored, powernet is still null here and
		// the scan would silently no-op forever. Re-attempt the connection now
		// that makepowernets() has finalized the real topology.
		if(!SC.powernet)
			SC.connect_to_network()
		SC.search_for_connected()
		SC.update() // sync cdir/panel angle to the current sun position immediately, instead of waiting up to SSsun's 1-minute tick
		solar_count++

	// Force every machine to re-read its area's power flags: machines cache
	// stat & NOPOWER and only refresh on this signal, so ones that sampled
	// power mid-restore would otherwise keep stale state until something
	// happens to flip their area again.
	for(var/area/AR in apc_areas)
		SEND_SIGNAL(AR, COMSIG_AREA_POWER_CHANGE)

	log_subsystem_persistence_info("Worldstate: Power state finalized -- [apc_count] APC(s), [solar_count] solar controller(s), [length(apc_areas)] area(s) rebroadcast.")

/**
 * On-demand repair for a PLAYER-BUILT wall device left centered/off-wall.
 *
 * There is deliberately no automatic world-wide version of this, and there
 * must never be one again. apply_wall_mount_offset() (_machinery.dm) derives
 * pixel_x/pixel_y purely from `dir`, which is only ever correct for the case
 * its own doc comment describes: a wall frame being built, which can only
 * place its machine on the adjacent floor tile with `dir` pointing at the
 * wall. Mapped devices do not follow that convention at all -- a mapper
 * positions them on BOTH axes (x to sit beside a doorframe, y to sit high on
 * the wall) while `dir` independently sets which way the sprite faces, e.g.
 * `access_button{ pixel_x = -12; pixel_y = 28; dir = 8 }` in frontier.dmm.
 * A dir-derived formula can only ever produce a single-axis offset, so
 * applying it to a mapped device relocates it -- previously 342 of them per
 * boot, many onto the opposite wall.
 *
 * So this is scoped to machines that are genuinely persistence-tracked:
 * persistent_objects_track_id is only ever assigned by objectsRegisterTrack()
 * under `!mapload` (_machinery.dm), making "was this player-built" a fact we
 * can read rather than guess. A mapped device is structurally unreachable
 * from here.
 */
/datum/admins/proc/fix_wall_mounted_machinery()
	set name = "Fix Wall-Mounted Machinery"
	set category = "Persistence.Backups & Saves"
	set desc = "Re-derives wall-mount pixel offsets for PLAYER-BUILT wall devices only. Never touches mapped machinery."

	if(!check_rights(R_SERVER))
		return

	var/fixed = 0
	for(var/obj/structure/machinery/M in SSmachinery.machinery)
		if(!M.persistent_objects_track_id)
			continue // mapped/untracked -- its offset is authored, not derived
		var/before_px = M.pixel_x
		var/before_py = M.pixel_y
		M.persistence_reapply_wall_offset()
		if(before_px != M.pixel_x || before_py != M.pixel_y)
			fixed++
			log_subsystem_persistence_info("WallMachineFix: [M.type] at ([M.x],[M.y],[M.z]) pixel_x [before_px]->[M.pixel_x] pixel_y [before_py]->[M.pixel_y]")
	to_chat(usr, SPAN_GOOD("Re-derived wall-mount offsets for [fixed] player-built device(s). Mapped machinery was not touched."))
	log_and_message_admins("ran a live wall-mounted machinery fix ([fixed] player-built device(s) adjusted).")

/**
 * Clear atmos alarm state latched during boot, called AFTER atmosApply()
 * has put the real saved air back. While turfs/zones rebuild, live air
 * alarms sample transient vacuum/cold and latch danger levels that close
 * the area firedoors; the reset path can't recover from a frozen
 * danger_level, so we zero every alarm and re-derive each area once the
 * air is correct. Genuinely bad zones re-trigger within one process tick.
 */
/datum/controller/subsystem/persistence/proc/atmosAlarmsReset()
	var/alarms_reset = 0
	var/list/alarmed_areas = list()
	for(var/obj/structure/machinery/alarm/AA in SSmachinery.machinery)
		if(!AA.z)
			continue
		AA.danger_level = 0
		// Clear the environment memo so the next process() re-samples the
		// restored air instead of short-circuiting on "unchanged".
		AA.previous_environment_gas = list()
		AA.previous_environment_temperature = null
		AA.previous_environment_total_moles = null
		AA.previous_environment_volume = null
		AA.previous_environment_group_multiplier = null
		// Re-apply the restored mode so vents/scrubbers actually match it --
		// worldstate only writes the var.
		AA.apply_mode()
		if(AA.alarm_area && AA.alarm_area.atmosalm)
			alarmed_areas |= AA.alarm_area
		alarms_reset++
	// With every alarm zeroed the recompute clears the area alarm and
	// air_doors_open() lifts the shutters (welded doors stay put).
	for(var/area/AR in alarmed_areas)
		AR.atmosalert(0, null)
	log_subsystem_persistence_info("Worldstate: Atmos alarms reset -- [alarms_reset] alarm(s), [length(alarmed_areas)] latched area(s) cleared.")

/**
 * Looks up the cache entry for this machine and applies its saved content.
 * Returns 1 if state was applied, 0 otherwise.
 */
/datum/controller/subsystem/persistence/proc/worldstateApplyToMachine(atom/movable/S)
	PRIVATE_PROC(TRUE)
	try
		var/turf/T = get_turf(S)
		if(!T || !T.z)
			return 0
		var/site_key = worldstate_pinned_site_key(T.z)
		var/key_type = S.worldstate_key_type()
		var/cache_key = site_key ? "[key_type]|site:[site_key]|[T.x]|[T.y]" : "[key_type]|[T.x]|[T.y]|[T.z]"
		var/json = GLOB.persistence_worldstate_cache[cache_key]
		if(!json)
			return 0
		var/list/content = json_decode(json)
		if(!islist(content))
			return 0
		content -= "__worldstate_site"
		S.worldstate_apply_content(content)
#ifdef WALL_MACHINE_DIAGNOSTICS
		if(S.pixel_x || S.pixel_y)
			log_subsystem_persistence_info("WallMachineDiag RESTORE: [S.type] at ([T.x],[T.y],[T.z]) dir=[S.dir] pixel_x=[S.pixel_x] pixel_y=[S.pixel_y]")
#endif
		return 1
	catch(var/exception/e)
		log_subsystem_persistence_error("Worldstate: Failed to apply content to [S] at [get_turf(S)]: [e]")
		return 0

/**
 * Save current state of all tracked machinery types to the database.
 * Clears all previous worldstate data first so destroyed objects don't persist.
 * Called from SSpersistence.Shutdown().
 */
/datum/controller/subsystem/persistence/proc/worldstateFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("worldstateFinalize"))
		return

	// DB-side clock (not DM's) to avoid clock skew. Every row written below
	// gets a fresh saved_at and so survives the cutoff; only rows nothing
	// touched this cycle (destroyed objects, and the previous generation of
	// every row this one replaces) get removed, and only after the write
	// completes. If the collection or flush is interrupted (crash,
	// disconnect), nothing is deleted at all -- the previous save stays
	// intact instead of being wiped up front.
	var/datum/db_query/clock = SSdbcore.NewQuery("SELECT NOW(6)")
	clock.Execute()
	var/cutoff
	if(databaseCheckQueryResult(clock, "worldstateFinalize clock") && clock.NextRow())
		cutoff = clock.item[1]
	qdel(clock)
	if(!cutoff)
		return

	// Collect every row first, then write them in chunks -- see
	// _worldstateFlush() for why this is no longer one query per machine.
	// The cutoff above was taken BEFORE any of this, and the stale DELETE
	// below runs after it, so an interrupted save still deletes nothing.
	var/list/value_rows = list()

	for(var/obj/structure/S in world)
		CHECK_TICK
		if(persistence_z_excluded(S.z)) continue
		if(persistence_area_excluded(S)) continue
		var/list/row = _worldstateRowFor(S)
		if(row)
			value_rows += list(row)

	for(var/obj/item/radio/intercom/IC in world)
		CHECK_TICK
		if(persistence_z_excluded(IC.z)) continue
		if(persistence_area_excluded(IC)) continue
		var/list/row = _worldstateRowFor(IC)
		if(row)
			value_rows += list(row)

	for(var/obj/item/modular_computer/MC in world)
		CHECK_TICK
		if(persistence_z_excluded(MC.z)) continue
		if(persistence_area_excluded(MC)) continue
		var/list/row = _worldstateRowFor(MC)
		if(row)
			value_rows += list(row)

	var/list/flush_result = _worldstateFlush(value_rows, "worldstateFinalize")
	var/saved = flush_result["saved"]

	// Only prune the previous generation once THIS one is known to be fully
	// written -- see _worldstateFlush()'s doc comment. A partial write plus a
	// delete would lose the machines whose chunk failed.
	if(flush_result["failed"])
		log_subsystem_persistence_error("Worldstate: skipping stale-row cleanup -- [saved] row\s were collected but at least one chunk failed to write. Last cycle's rows are left intact.")
	else
		var/datum/db_query/delete_stale = SSdbcore.NewQuery(
			"DELETE FROM ss13_worldstate_objects WHERE saved_at < :cutoff AND map_path = :map_path",
			list("cutoff" = cutoff, "map_path" = SSatlas.current_map.path)
		)
		delete_stale.Execute()
		databaseCheckQueryResult(delete_stale, "worldstateFinalize delete stale")
		qdel(delete_stale)

		// The sweep above also re-saved every deployed ship Z's machines under
		// their ship scopes (persistence_ship_interiors.dm) -- run the same
		// destroyed-object cutoff per scope so ship rows don't accumulate.
		for(var/ship_z in GLOB.persistence_ship_z)
			var/datum/db_query/ship_stale = SSdbcore.NewQuery(
				"DELETE FROM ss13_worldstate_objects WHERE saved_at < :cutoff AND map_path = :map_path",
				list("cutoff" = cutoff, "map_path" = GLOB.persistence_ship_z[ship_z])
			)
			ship_stale.Execute()
			databaseCheckQueryResult(ship_stale, "worldstateFinalize ship scope delete stale")
			qdel(ship_stale)

	log_subsystem_persistence_info("Worldstate: Saved state for [saved] machines.")

/**
 * Per-Z machinery save for a deployed ship Z -- same save/cutoff contract as
 * worldstateFinalize(), restricted to one z. Caller must still have the z
 * registered in GLOB.persistence_ship_z so rows key under the ship scope.
 */
/datum/controller/subsystem/persistence/proc/worldstateFinalizeZ(z, scope)
	if(!databaseCheckConnection("worldstateFinalizeZ"))
		return

	var/datum/db_query/clock = SSdbcore.NewQuery("SELECT NOW(6)")
	clock.Execute()
	var/cutoff
	if(databaseCheckQueryResult(clock, "worldstateFinalizeZ clock") && clock.NextRow())
		cutoff = clock.item[1]
	qdel(clock)
	if(!cutoff)
		return

	// Same collect-then-chunk shape as worldstateFinalize() above.
	var/list/value_rows = list()
	for(var/obj/structure/S in world)
		if(S.z != z) continue
		if(persistence_area_excluded(S)) continue
		var/list/row = _worldstateRowFor(S)
		if(row)
			value_rows += list(row)
	for(var/obj/item/radio/intercom/IC in world)
		if(IC.z != z) continue
		if(persistence_area_excluded(IC)) continue
		var/list/row = _worldstateRowFor(IC)
		if(row)
			value_rows += list(row)
	for(var/obj/item/modular_computer/MC in world)
		if(MC.z != z) continue
		if(persistence_area_excluded(MC)) continue
		var/list/row = _worldstateRowFor(MC)
		if(row)
			value_rows += list(row)

	var/list/flush_result = _worldstateFlush(value_rows, "worldstateFinalizeZ")
	var/saved = flush_result["saved"]

	// Same rule as worldstateFinalize(): never prune the previous generation
	// on the back of a partial write.
	if(flush_result["failed"])
		log_subsystem_persistence_error("Worldstate: skipping stale-row cleanup for z=[z] ([scope]) -- at least one chunk failed to write. Last cycle's rows are left intact.")
	else
		var/datum/db_query/delete_stale = SSdbcore.NewQuery(
			"DELETE FROM ss13_worldstate_objects WHERE saved_at < :cutoff AND map_path = :map_path",
			list("cutoff" = cutoff, "map_path" = scope)
		)
		delete_stale.Execute()
		databaseCheckQueryResult(delete_stale, "worldstateFinalizeZ delete stale")
		qdel(delete_stale)
	log_subsystem_persistence_info("Worldstate: Saved [saved] ship machines for z=[z] ([scope]).")

/**
 * Apply saved ship-scoped machinery rows to a freshly loaded ship Z. Queries
 * fresh (rows were just remapped to this z by remapShipRows()) rather than
 * touching the boot cache, and matches machines by (type, x, y) on the z.
 */
/datum/controller/subsystem/persistence/proc/worldstateApplyZ(z, scope)
	if(!databaseCheckConnection("worldstateApplyZ"))
		return
	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, content FROM ss13_worldstate_objects WHERE map_path = :map_path AND z = :z",
		list("map_path" = scope, "z" = z)
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "worldstateApplyZ"))
		qdel(query)
		return
	var/list/rows_by_key = list()
	while(query.NextRow())
		CHECK_TICK
		rows_by_key["[query.item[1]]|[query.item[2]]|[query.item[3]]"] = query.item[4]
	qdel(query)
	if(!length(rows_by_key))
		return

	var/applied = 0
	for(var/obj/structure/S in world)
		CHECK_TICK
		if(S.z != z) continue
		applied += _worldstateApplyRowTo(S, rows_by_key)
	for(var/obj/item/radio/intercom/IC in world)
		CHECK_TICK
		if(IC.z != z) continue
		applied += _worldstateApplyRowTo(IC, rows_by_key)
	for(var/obj/item/modular_computer/MC in world)
		CHECK_TICK
		if(MC.z != z) continue
		applied += _worldstateApplyRowTo(MC, rows_by_key)
	log_subsystem_persistence_info("Worldstate: Applied [applied] ship machine states to z=[z] ([scope]).")

/// Match one machine against a (type|x|y)-keyed row set and apply its saved
/// content. Returns 1 if applied, 0 otherwise.
/datum/controller/subsystem/persistence/proc/_worldstateApplyRowTo(atom/movable/S, list/rows_by_key)
	PRIVATE_PROC(TRUE)
	try
		var/turf/T = get_turf(S)
		if(!T)
			return 0
		var/json = rows_by_key["[S.type]|[T.x]|[T.y]"]
		if(!json)
			return 0
		var/list/content = json_decode(json)
		if(!islist(content))
			return 0
		content -= "__worldstate_site"
		S.worldstate_apply_content(content)
#ifdef WALL_MACHINE_DIAGNOSTICS
		if(S.pixel_x || S.pixel_y)
			log_subsystem_persistence_info("WallMachineDiag RESTORE: [S.type] at ([T.x],[T.y],[T.z]) dir=[S.dir] pixel_x=[S.pixel_x] pixel_y=[S.pixel_y]")
#endif
		return 1
	catch(var/exception/e)
		log_subsystem_persistence_error("Worldstate: Failed to apply ship content to [S] at [get_turf(S)]: [e]")
		return 0

/**
 * Serialize one machine and INSERT/UPDATE its row in the database.
 * Returns 1 on success, 0 if skipped or failed.
 */
/datum/controller/subsystem/persistence/proc/_worldstateRowFor(atom/movable/S)
	PRIVATE_PROC(TRUE)
	CHECK_TICK
	try
		var/turf/T = get_turf(S)
		if(!T || !T.z)
			return null
#ifdef WALL_MACHINE_DIAGNOSTICS
		if(S.pixel_x || S.pixel_y)
			log_subsystem_persistence_info("WallMachineDiag SAVE: [S.type] at ([T.x],[T.y],[T.z]) dir=[S.dir] pixel_x=[S.pixel_x] pixel_y=[S.pixel_y]")
#endif
		var/list/content = S.worldstate_get_content()
		if(!islist(content) || !length(content))
			return null
		// A pinned site's z isn't stable across boots -- embed the site's
		// own stable template id in the saved content so worldstateInitialize()
		// can match this row back up regardless of which z the site lands
		// on next boot (see worldstate_pinned_site_key() above).
		var/site_key = worldstate_pinned_site_key(T.z)
		if(site_key)
			content["__worldstate_site"] = site_key
		return list(
			// Deployed ship Zs key under their ship scope instead of the
			// map path -- see persistence_ship_interiors.dm.
			"map_path" = persistence_scope_for_z(T.z),
			"type"    = "[S.worldstate_key_type()]",
			"x"       = T.x,
			"y"       = T.y,
			"z"       = T.z,
			"content" = json_encode(content)
		)
	catch(var/exception/e)
		// Per-object, so one bad machine costs only itself. Without this a
		// single throw would unwind the whole collection loop and silently
		// discard every OTHER machine's state for the entire map -- the same
		// failure the floor-item writer already had to guard against.
		log_subsystem_persistence_error("Worldstate: Failed to serialize [S] at [get_turf(S)]: [e]")
		return null

/**
 * Chunked bulk INSERT of collected worldstate rows, every value passed as a
 * BOUND PARAMETER rather than interpolated into the SQL text -- the same shape
 * _floorItemsFlush() (persistence_floor_items.dm) and the turf writer already
 * use. Returns the number of rows written.
 *
 * This replaced a one-INSERT-per-machine loop that was measured at ~135
 * seconds for 3125 machines -- 85% of an entire ~159s save -- purely in
 * sequential query round-trips, each blocking in datum/db_query/sync(). The
 * comparable batched writers move a similar row count in single-digit seconds.
 *
 * No ON DUPLICATE KEY UPDATE: ss13_worldstate_objects has only
 * PRIMARY KEY (id) and no unique key on (map_path, type, x, y, z), so the
 * upsert clause the old per-row insert carried could never actually fire.
 * Every save has always written fresh rows, with the trailing stale-cutoff
 * DELETE in the callers removing the previous generation -- a plain multi-row
 * INSERT is exactly equivalent to the previous behaviour.
 *
 * Returns list("saved" = rows written, "failed" = TRUE if any chunk errored).
 * Callers MUST skip their stale-cutoff DELETE when "failed" is set: batching
 * means one failed query now costs a whole chunk of machines instead of one,
 * and deleting the previous generation after a partial write would turn a
 * retryable hiccup into real data loss. Skipping the delete leaves last
 * cycle's rows in place, which is always recoverable.
 */
/datum/controller/subsystem/persistence/proc/_worldstateFlush(list/value_rows, log_context)
	PRIVATE_PROC(TRUE)
	var/saved = length(value_rows)
	if(!saved)
		return list("saved" = 0, "failed" = FALSE)
	var/any_failed = FALSE
	var/written = 0
	// Two independent limits, whichever is reached first:
	//   rows  -- 200, matching the other bulk writers.
	//   bytes -- a 4MB budget well under MariaDB's 16MB max_allowed_packet.
	//
	// The byte budget is what makes an oversized statement impossible rather
	// than merely survivable. Content averages ~550 bytes, so chunks are
	// normally row-limited at 200 (~110KB) -- but blobs are unbounded in
	// principle (the largest observed is ~98KB, a closet full of items), and
	// 200 outliers in one chunk would blow past the packet limit and fail the
	// whole statement. Splitting on size instead just makes that chunk
	// smaller.
	var/chunk_rows = 200
	var/chunk_byte_budget = 4000000

	var/list/placeholders = list()
	var/list/params = list()
	var/n = 0
	var/batch_bytes = 0

	for(var/j = 1 to saved)
		var/list/row = value_rows[j]
		if(!islist(row))
			continue
		var/content_bytes = length(row["content"])
		// Flush the batch in progress before it would exceed either limit.
		if(n && ((n >= chunk_rows) || ((batch_bytes + content_bytes) > chunk_byte_budget)))
			// Only count rows that actually landed -- the reported machine
			// count is what tells an operator a save was complete, so it must
			// never include a chunk that failed to write.
			if(_worldstateWriteChunk(placeholders, params, log_context))
				written += n
			else
				any_failed = TRUE
			placeholders = list()
			params = list()
			n = 0
			batch_bytes = 0
			CHECK_TICK
		placeholders += "(:mp[n],:ty[n],:x[n],:y[n],:z[n],:ct[n],NOW())"
		params["mp[n]"] = row["map_path"]
		params["ty[n]"] = row["type"]
		params["x[n]"]  = row["x"]
		params["y[n]"]  = row["y"]
		params["z[n]"]  = row["z"]
		params["ct[n]"] = row["content"]
		n++
		batch_bytes += content_bytes

	// Trailing partial batch.
	if(n)
		if(_worldstateWriteChunk(placeholders, params, log_context))
			written += n
		else
			any_failed = TRUE

	return list("saved" = written, "failed" = any_failed)

/// Issues one bulk-INSERT batch. Split out so _worldstateFlush() can flush
/// mid-iteration (on either the row or byte limit) without duplicating the
/// query. Returns FALSE if the write failed.
/datum/controller/subsystem/persistence/proc/_worldstateWriteChunk(list/placeholders, list/params, log_context)
	PRIVATE_PROC(TRUE)
	if(!length(placeholders))
		return TRUE
	var/datum/db_query/bulk = SSdbcore.NewQuery(
		"INSERT INTO ss13_worldstate_objects (map_path,type,x,y,z,content,saved_at) VALUES [placeholders.Join(",")]",
		params
	)
	bulk.Execute()
	. = databaseCheckQueryResult(bulk, "[log_context] bulk insert")
	if(!.)
		log_subsystem_persistence_error("Worldstate: [log_context] failed to write a [length(placeholders)]-row chunk -- the stale-row cleanup will be skipped so the previous save is kept.")
	qdel(bulk)

// =====================================================================
// DECLARATIVE VAR LISTS
// Types listed here get full save/restore automatically via the base procs.
// To add a new type: just set worldstate_vars. No loop edits required.
// =====================================================================

// ------- Non-machinery structures -------

/obj/structure/grille
	worldstate_vars = list("density")  // density = FALSE when cut with wirecutters

// ------- Machinery -------

/obj/structure/machinery/telepad_cargo
	worldstate_vars = list("persistent_network", "persistent_spawn", "faction_shackled", "personal_ckey", "personal_char_name", "crew_tagged")

// Full override instead of worldstate_vars -- also saves/restores downloaded
// software via the shared helpers in modular_computer/faction.dm, so a
// stationary shackled computer keeps its installed programs across restarts
// the same way a dynamically-tracked one does via persistent_objects_*_content().
/obj/item/modular_computer/worldstate_get_content()
	var/list/content = list("persistent_network" = persistent_network, "faction_shackled" = faction_shackled, "personal_ckey" = personal_ckey, "personal_char_name" = personal_char_name, "crew_tagged" = crew_tagged, "computer_emagged" = computer_emagged)
	var/list/programs = modcomp_save_programs()
	if(length(programs))
		content["programs"] = json_encode(programs)
	return content

/obj/item/modular_computer/worldstate_apply_content(list/content)
	if(!isnull(content["persistent_network"]))
		persistent_network = normalize_faction_uid(content["persistent_network"]) || ""
	if(!isnull(content["faction_shackled"]))
		faction_shackled = content["faction_shackled"]
	if(!isnull(content["personal_ckey"]))
		personal_ckey = content["personal_ckey"]
	if(!isnull(content["personal_char_name"]))
		personal_char_name = content["personal_char_name"]
	if(!isnull(content["crew_tagged"]))
		crew_tagged = content["crew_tagged"]
	if(!isnull(content["computer_emagged"]))
		computer_emagged = content["computer_emagged"]
	if(content["programs"])
		modcomp_restore_programs(json_decode(content["programs"]))

/obj/structure/machinery/door/airlock
	// "door_button_tag" -- so a link made via the buildable door button
	// (blast_door_button.dm) survives a restart, same as "id_tag" already
	// does for the cycler/legacy button systems.
	worldstate_vars = list("name", "welded", "locked", "ai_disabled_id_scanner", "req_access_faction", "req_access", "req_one_access", "id_tag", "frequency", "crew_tagged", "emagged", "persistent_network", "door_button_tag")

// Converting an airlock to/from glass (door_assembly.dm's construction-finish
// step) changes its actual DM type -- new glass_type(...), not a var toggle.
// On restart the map reloads the original (pre-conversion) type at this
// position, so keying by exact type would silently orphan the whole saved
// row, not just glass -- collapse every airlock subtype onto one stable key
// per position instead. Position alone already guarantees uniqueness.
/obj/structure/machinery/door/airlock/worldstate_key_type()
	return /obj/structure/machinery/door/airlock

/obj/structure/machinery/door/airlock/worldstate_get_content()
	var/list/content = ..()
	if(!content) content = list()
	// The exact type at save time -- glass subtypes aren't uniformly defined
	// (e.g. glass_service doesn't restate maxhealth/explosion_resistance the
	// way the base /glass type does), so restoring "glass-ness" means
	// re-deriving THIS type's actual compiled defaults, not guessing a fixed
	// var set -- see worldstate_apply_content() below.
	content["saved_type"] = "[type]"
	if(wires && length(wires.cut_wires))
		content["cut_wires"] = json_encode(wires.cut_wires)
	return content

/obj/structure/machinery/door/airlock/worldstate_apply_content(list/content)
	..()
	if(content && content["saved_type"])
		var/saved_type_path = text2path(content["saved_type"])
		if(ispath(saved_type_path, /obj/structure/machinery/door/airlock) && saved_type_path != type)
			// Off-map dummy purely to read that type's compiled defaults --
			// qdel()'d before anything else runs, never observable elsewhere.
			var/obj/structure/machinery/door/airlock/dummy = new saved_type_path(null)
			glass = dummy.glass
			maxhealth = dummy.maxhealth
			health = maxhealth
			explosion_resistance = dummy.explosion_resistance
			hitsound = dummy.hitsound
			open_sound_powered = dummy.open_sound_powered
			close_sound_powered = dummy.close_sound_powered
			panel_visible_while_open = dummy.panel_visible_while_open
			door_color = dummy.door_color
			door_frame_color = dummy.door_frame_color
			qdel(dummy)
			_apply_glass_state()
	if(content && content["cut_wires"] && wires)
		var/list/cut = json_decode(content["cut_wires"])
		if(islist(cut))
			wires.cut_wires = cut
	// The generic apply above only sets the raw frequency var -- it takes an
	// actual set_frequency() call to re-register with SSradio, or a restored
	// door with a restored id_tag would sit on the right frequency var but
	// never actually receive anything.
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/door/blast
	// "id" -- so a button link made via multitool (door_control.dm's
	// _link_door()) survives a restart; every other blast door still
	// defaults to the class's own initial(id), unaffected.
	worldstate_vars = list("density", "persistent_network", "id")

/obj/structure/machinery/button/remote/blast_door
	// "id" -- multitool-linking (door_control.dm's _link_door()/_link_airlock())
	// now applies to every mapped button, not just the buildable subtype
	// below, and it OVERWRITES the button's own id with a freshly generated
	// one on first link. Without this, that generated id reverts to the
	// map's original hardcoded value on the next restart while the door side
	// (already persisted, above) keeps the generated one -- silently
	// breaking every multitool-made link one restart after it was made.
	worldstate_vars = list("id")

/obj/structure/machinery/button/remote/blast_door/buildable
	worldstate_vars = list("id")

/obj/structure/machinery/power/smes
	worldstate_vars = list("charge", "input_attempt", "input_level", "output_attempt", "output_level")

// ------- SMES buildable (nested coil composition, not a flat var) -------
// capacity/input_level_max/output_level_max are derived from component_parts
// each boot (recalc_coils()), and Initialize() unconditionally rebuilds
// component_parts from cur_coils copies of the base-tier coil -- neither the
// coil count nor the upgraded coil types survive a restart without this.

/obj/structure/machinery/power/smes/buildable/worldstate_get_content()
	var/list/content = ..() // base smes worldstate_vars: charge, input_attempt, input_level, output_attempt, output_level
	if(!content) content = list()
	var/list/coil_types = list()
	for(var/obj/item/smes_coil/C in component_parts)
		coil_types += "[C.type]"
	content["coil_types"] = coil_types
	return content

/obj/structure/machinery/power/smes/buildable/worldstate_apply_content(list/content)
	..() // restores charge/input_attempt/etc via the inherited worldstate_vars list
	if(content && islist(content["coil_types"]) && length(content["coil_types"]))
		for(var/obj/item/smes_coil/C in component_parts)
			qdel(C)
		component_parts = list()
		for(var/type_str in content["coil_types"])
			var/coil_type = text2path(type_str)
			if(ispath(coil_type, /obj/item/smes_coil))
				component_parts += new coil_type(src)
		cur_coils = length(component_parts)
		recalc_coils()

/obj/structure/machinery/atmospherics/binary/pump
	worldstate_vars = list("use_power", "target_pressure")

/obj/structure/machinery/atmospherics/unary/vent_scrubber
	worldstate_vars = list("use_power", "scrubbing", "welded")

/obj/structure/machinery/atmospherics/unary/vent_pump
	// id_tag is load-bearing here, not cosmetic: _ensure_id_tag() mints the
	// pump's tag when a cycler controller links it, and the controller
	// separately persists that tag as tag_airpump. Without saving id_tag the
	// pump comes back with a null/regenerated tag after a reboot, so the
	// controller's saved tag_airpump points at nothing and every cycler pump
	// silently unlinks itself on restart.
	// "name" is load-bearing alongside id_tag: broadcast_status() auto-names an
	// unnamed vent from a per-area counter, so without persisting the name a
	// restored pump gets renamed to the next free number every boot.
	worldstate_vars = list("use_power", "pump_direction", "external_pressure_bound", "internal_pressure_bound", "pressure_checks", "welded", "frequency", "id_tag", "name")

/obj/structure/machinery/atmospherics/unary/vent_pump/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

// ------- Reagent containers (fluids in machinery/structures) -------
// serializePersistentItem() (persistence_mobs.dm) already round-trips reagents
// for ITEMS, but worldstate had no reagent handling at all, so anything that
// holds fluid as a structure or machine -- water/fuel tanks, chem masters,
// grinders -- came back empty every reboot.
//
// Written as two shared helpers rather than repeating the encode/decode in
// each type's override, since the types involved don't share a useful common
// ancestor (/obj/structure/reagent_dispensers vs /obj/structure/machinery/*)
// and blanket-overriding /obj/structure would touch every structure in the
// game for no reason.

/// Adds this atom's reagent contents to a worldstate content blob, if any.
/// Returns the blob so callers can `return _worldstate_save_reagents(...)`.
/proc/_worldstate_save_reagents(atom/A, list/content)
	if(!islist(content))
		content = list()
	if(A.reagents && A.reagents.total_volume && length(A.reagents.reagent_volumes))
		content["reagents"] = json_encode(A.reagents.reagent_volumes)
	return content

/// Restores reagents saved by _worldstate_save_reagents(). Clears first, so a
/// container emptied before the save doesn't come back holding its Initialize()
/// fill -- same reasoning as the storage-contents restore in persistence_mobs.dm.
/proc/_worldstate_apply_reagents(atom/A, list/content)
	if(!A.reagents || !islist(content) || !content["reagents"])
		return
	var/list/saved_reagents = json_decode(content["reagents"])
	if(!islist(saved_reagents))
		return
	A.reagents.clear_reagents()
	for(var/rtype_str in saved_reagents)
		var/rtype = text2path(rtype_str)
		if(rtype)
			A.reagents.add_reagent(rtype, text2num(saved_reagents[rtype_str]))

/obj/structure/reagent_dispensers/worldstate_get_content()
	return _worldstate_save_reagents(src, ..())

/obj/structure/reagent_dispensers/worldstate_apply_content(list/content)
	..()
	_worldstate_apply_reagents(src, content)

/obj/structure/machinery/chem_master/worldstate_get_content()
	return _worldstate_save_reagents(src, ..())

/obj/structure/machinery/chem_master/worldstate_apply_content(list/content)
	..()
	_worldstate_apply_reagents(src, content)

/obj/structure/machinery/reagentgrinder/worldstate_get_content()
	return _worldstate_save_reagents(src, ..())

/obj/structure/machinery/reagentgrinder/worldstate_apply_content(list/content)
	..()
	_worldstate_apply_reagents(src, content)

// ------- Tank control console + its injector (multitool-linked by tag) -------
// input_tag/output_tag are the console's only handle on its devices, and the
// injector's own `id` is what it answers to -- all three were mapper-authored
// only until multitool linking existed, so none of them were ever persisted.
// The set_frequency() calls matter for the same reason the vent pump and
// airlock cycler already override apply: the generic apply writes the raw
// frequency var, but it takes a real set_frequency() call to re-register with
// SSradio, or a restored pair holds correct-looking tags and hears nothing.

// `sensors` is an assoc id_tag -> display name built by multitool linking
// (_link_air_sensor(), atmo_control.dm) -- it round-trips fine as part of the
// JSON content blob, and without it every readout link is lost on reboot.
/obj/structure/machinery/computer/general_air_control
	worldstate_vars = list("sensors", "frequency")

/obj/structure/machinery/computer/general_air_control/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/computer/general_air_control/large_tank_control
	worldstate_vars = list("sensors", "input_tag", "output_tag", "frequency")

// Same shape as large_tank_control just above -- input_tag/output_tag are
// now on the shared base type (atmo_control.dm), but each subtype still
// needs its OWN worldstate_vars override to actually persist them; a
// subtype with none just inherits the base's own narrower list ("sensors",
// "frequency" only). Without this, a device linked to a supermatter core
// console -- now possible at all for the first time -- would survive the
// rest of the round but silently unlink on every restart.
/obj/structure/machinery/computer/general_air_control/supermatter_core
	worldstate_vars = list("sensors", "input_tag", "output_tag", "frequency")

/obj/structure/machinery/atmospherics/unary/outlet_injector
	worldstate_vars = list("id", "frequency", "volume_rate", "use_power")

/obj/structure/machinery/atmospherics/unary/outlet_injector/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

// ------------------- Omni mixers/filters (port config) -----------------------
// Port configuration is serialized off the LIVE ports list, not the tag_north/
// tag_south/tag_east/tag_west vars.
//
// Those tag vars look like the config but are write-once SEEDS: Initialize()
// reads them exactly once to build the /datum/omni_port instances
// (omni_base.dm), and nothing ever writes back to them. Player configuration
// goes to P.mode and P.concentration on the port datums themselves
// (mixer.dm ui_act). Saving the tags therefore recorded the mapper/compile
// default forever -- every row in the live DB read
// {"tag_north":0,...,"tag_north_con":null} while set_flow_rate, an ordinary
// live var, saved correctly -- and restore rebuilt every port unconfigured.
//
// Ports are keyed by P.dir (a stable cardinal), not list position, so a
// reordered ports list can't silently shuffle a mixer's inputs and output.
// Subtypes restate worldstate_vars because it is a plain var override, not
// additive; they inherit the get/apply overrides from the base.

/obj/structure/machinery/atmospherics/omni
	worldstate_vars = list("use_power")

/obj/structure/machinery/atmospherics/omni/worldstate_get_content()
	var/list/content = ..()
	if(!islist(content))
		content = list()
	var/list/port_data = list()
	for(var/datum/omni_port/P in ports)
		port_data["[P.dir]"] = list("mode" = P.mode, "concentration" = P.concentration)
	if(length(port_data))
		content["ports"] = port_data
	return content

/obj/structure/machinery/atmospherics/omni/worldstate_apply_content(list/content)
	..()
	var/list/port_data = content["ports"]
	if(islist(port_data))
		for(var/datum/omni_port/P in ports)
			var/list/saved = port_data["[P.dir]"]
			if(!islist(saved))
				continue
			P.mode = saved["mode"]
			P.concentration = saved["concentration"]
	// Rebuilds the derived state from the port modes just written --
	// sort_ports() + update_port_icons() (omni_base.dm). Without it the modes
	// are set but nothing acts on them and the icons stay stale.
	update_ports()

/obj/structure/machinery/atmospherics/omni/mixer
	worldstate_vars = list("use_power", "set_flow_rate")

/obj/structure/machinery/atmospherics/omni/filter
	worldstate_vars = list("use_power", "set_flow_rate")

/obj/structure/machinery/atmospherics/omni/filter/worldstate_apply_content(list/content)
	..()
	// update_ports() does NOT rebuild filtering_outputs -- that is a separate
	// proc (filter.dm), and P.mode is what encodes which gas each port filters.
	// Skipping this leaves a filter whose ports look correctly configured while
	// it routes no gas at all.
	rebuild_filtering_list()

/obj/structure/machinery/portable_atmospherics/canister
	worldstate_vars = list("valve_open", "release_pressure", "release_flow_rate", "can_label")

/obj/structure/machinery/portable_atmospherics/canister/worldstate_get_content()
	var/list/content = ..()
	if(air_contents)
		content["air_gas"] = json_encode(air_contents.gas)
		content["air_temperature"] = air_contents.temperature
	return content

/obj/structure/machinery/portable_atmospherics/canister/worldstate_apply_content(list/content)
	..()
	if(!air_contents || !content["air_gas"])
		return
	var/list/gases = json_decode(content["air_gas"])
	if(islist(gases))
		air_contents.gas = gases
	if(!isnull(content["air_temperature"]))
		air_contents.temperature = text2num(content["air_temperature"])
	air_contents.update_values()

// Airlock cycler parts (section 8): buildstage/panel_open + dir so a still-
// under-construction frame/circuit survives a restart mid-build, plus every
// tag/frequency link a multitool sets up, so a player-built cycler doesn't
// need to be rewired after a restart.
//
// pixel_x/pixel_y travel WITH dir here, deliberately. These offsets cannot be
// re-derived from dir: a mapper positions these devices on both axes (x to sit
// beside a doorframe, y to sit high on the wall) while dir independently sets
// which way the sprite faces -- see apply_wall_mount_offset()'s formula, which
// can only ever produce a single-axis offset and is correct solely for a frame
// being freshly BUILT. Persisting the real value means whatever the device
// actually had -- mapper-authored or player-built -- round-trips exactly,
// instead of being recomputed into the wrong position on every boot.
/obj/structure/machinery/airlock_sensor
	worldstate_vars = list("buildstage", "panel_open", "dir", "pixel_x", "pixel_y", "id_tag", "master_tag", "frequency", "on")

/obj/structure/machinery/airlock_sensor/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/access_button
	worldstate_vars = list("buildstage", "panel_open", "dir", "pixel_x", "pixel_y", "master_tag", "frequency", "on")

/obj/structure/machinery/access_button/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller
	worldstate_vars = list("buildstage", "panel_open", "dir", "pixel_x", "pixel_y", "id_tag", "frequency", "tag_exterior_door", "tag_interior_door", "tag_exterior_doors", "tag_interior_doors", "tag_airpump", "tag_airpumps", "tag_chamber_sensor", "tag_exterior_sensor", "tag_interior_sensor", "persistent_network")

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

// ------- Telecomms machinery (section 9) -------
// Full override instead of worldstate_vars: freq_listening is list-valued
// (json-encoded, same as camera's network list above) and links/
// links_by_telecomms_type are object references, not JSON-safe -- saved as
// [x,y,z] coordinates and restored via add_new_link(), which already
// rebuilds links_by_telecomms_type as a side effect (it's a derived index,
// not independently saved). Message logs (pda_msgs/rc_msgs -- themselves
// unfinished, see the TODO already in message_server.dm) and the server's
// NTSL2 script (rawcode is dead/unreferenced outside its own declaration;
// the actual compiled Program datum isn't a simple var dump) are both
// deliberately NOT persisted here -- out of scope for this pass, flagged
// rather than silently skipped.
/obj/structure/machinery/telecomms/worldstate_get_content()
	var/list/link_coords = list()
	for(var/obj/structure/machinery/telecomms/L in links)
		link_coords += list(list(L.x, L.y, L.z))
	return list(
		"id" = id,
		"network" = network,
		"use_power" = use_power,
		"integrity" = integrity,
		"persistent_network" = persistent_network,
		"freq_listening" = json_encode(freq_listening),
		"links" = json_encode(link_coords),
	)

/obj/structure/machinery/telecomms/worldstate_apply_content(list/content)
	if(content["id"])
		id = content["id"]
	if(content["network"])
		network = content["network"]
	if(!isnull(content["use_power"]))
		use_power = text2num(content["use_power"])
	if(!isnull(content["integrity"]))
		integrity = text2num(content["integrity"])
	if(!isnull(content["persistent_network"]))
		persistent_network = normalize_faction_uid(content["persistent_network"]) || ""
	if(content["freq_listening"])
		var/list/freqs = json_decode(content["freq_listening"])
		if(islist(freqs))
			freq_listening = freqs
	if(content["links"])
		var/list/coords = json_decode(content["links"])
		if(islist(coords))
			for(var/list/pair in coords)
				if(!islist(pair) || length(pair) < 3)
					continue
				var/turf/T = locate(pair[1], pair[2], pair[3])
				if(!T)
					continue
				for(var/obj/structure/machinery/telecomms/other in T)
					add_new_link(other)
	update_icon()

/obj/structure/machinery/telecomms/bus
	worldstate_vars = list("change_frequency")

/obj/structure/machinery/telecomms/message_server
	worldstate_vars = list("decryptkey", "spamfilter_limit")

/obj/structure/machinery/light
	worldstate_vars = list("status")

/obj/structure/machinery/firealarm
	worldstate_vars = list("detecting", "working")

/obj/structure/machinery/suit_cycler
	worldstate_vars = list("locked", "safeties", "radiation_level", "target_department", "target_species", "emagged")

/obj/structure/machinery/porta_turret
	worldstate_vars = list("enabled", "lethal", "locked", "check_arrest", "check_records", "check_weapons", "check_access", "check_wildlife", "check_synth", "target_borgs", "auto_repair", "persistent_network", "turret_faction_target_mode", "emagged")

/obj/structure/machinery/disposal
	worldstate_vars = list("is_on", "can_flush")

/obj/structure/machinery/turret_control
	worldstate_vars = list("enabled", "lethal", "locked", "check_arrest", "check_records", "check_weapons", "check_access", "check_wildlife", "check_synth", "target_borgs", "emagged", "ailock")

/obj/structure/machinery/atmospherics/unary/cryo_cell
	worldstate_vars = list("on", "temperature_warning_threshold", "temperature_danger_threshold")

/obj/structure/machinery/spaceheater
	worldstate_vars = list("on", "set_temperature", "high_power_cell")

/obj/structure/machinery/sleeper
	worldstate_vars = list("filtering", "pump", "stasis")

/obj/structure/machinery/chem_heater
	worldstate_vars = list("target_temperature", "should_heat", "slow_mode")

/obj/structure/machinery/biogenerator
	worldstate_vars = list("points", "build_eff", "eat_eff", "processing_time_divisor", "emagged")

/obj/structure/machinery/bioprinter
	worldstate_vars = list("stored_matter", "loaded_species_id", "loaded_blood_type", "loaded_blood_dna")

/obj/structure/machinery/bioprinter/worldstate_apply_content(list/content)
	. = ..()
	if(loaded_species_id)
		loaded_species = GLOB.all_species[loaded_species_id]
	products = get_possible_products()

/obj/structure/machinery/stasis_bed
	worldstate_vars = list("stasis_enabled", "stasis_can_toggle")

/obj/structure/machinery/stasis_cage
	worldstate_vars = list("safety")

/obj/structure/machinery/newscaster
	worldstate_vars = list("c_locked", "securityCaster")

/obj/structure/machinery/flasher
	worldstate_vars = list("disable")

/obj/structure/machinery/optable
	worldstate_vars = list("suppressing")

/obj/structure/machinery/floodlight
	worldstate_vars = list("on", "unlocked", "open")

/obj/structure/machinery/floodlight/worldstate_apply_content(list/content)
	. = ..()
	// The restore writes "on" as a raw var -- the dynamic light listens to
	// set_light_on()'s signal, which a raw write never fires.
	set_light_on(on)

/obj/structure/machinery/hologram/holopad
	worldstate_vars = list("long_range", "hacked")

/obj/structure/machinery/mass_driver
	worldstate_vars = list("power")

/obj/structure/machinery/teleporter
	worldstate_vars = list("calibration", "ignore_distance")

/obj/structure/machinery/gumballmachine
	worldstate_vars = list("amountleft", "broken", "on")

// TLV is the whole point of configuring an air alarm (the per-gas warning/
// danger threshold table, set via ui_act("set_threshold")) and was missing
// from this list entirely, so every threshold a player set reverted on
// restart. It round-trips fine as a nested list through json_encode/decode --
// the airlock persists req_access the same way. `name` matters because the
// blueprints area-rename walks alarms and renames them to match the area.
/obj/structure/machinery/alarm
	worldstate_vars = list("mode", "target_temperature", "breach_detection", "locked", "aidisabled", "highpower", "frequency", "TLV", "rcon_setting", "report_danger_level", "shorted", "name")

/obj/structure/machinery/alarm/worldstate_apply_content(list/content)
	..()
	// first_run() rewrites TLV to hard defaults on every Initialize() (and
	// again on rebuild), so a restored table has to be re-asserted here --
	// worldstate apply runs after Initialize, but re-applying explicitly makes
	// that ordering dependency safe rather than incidental.
	if(islist(content) && islist(content["TLV"]))
		TLV = content["TLV"]
	// The generic path only assigns the var; the radio still has to actually
	// be moved onto the restored frequency. Same override vent_pump uses.
	if(frequency)
		set_frequency(frequency)
	// LateInitialize() (alarm.dm) already called apply_mode() once, using
	// whatever `mode` was BEFORE this restore ever touched it -- SSatoms
	// (init_order 30) finishes every LateInitialize() well before
	// SSpersistence (init_order -10) runs at all, so that first call always
	// propagated the class default, not the saved mode, to the room's own
	// vents/scrubbers. The generic apply above just fixed `mode` itself, but
	// never re-sends the signal -- without this, the alarm reads as
	// correctly restored (its own mode var is right) while the room it
	// controls keeps acting on the stale default indefinitely.
	apply_mode()

/obj/structure/machinery/power/portgen/basic
	worldstate_vars = list("active", "open", "power_output", "sheets", "sheet_left", "anchored", "emagged")

/obj/structure/machinery/power/portgen/basic/worldstate_apply_content(list/content)
	. = ..()
	// The generic restore above only sets vars directly -- it doesn't re-run
	// the side effect that normally accompanies anchored becoming true.
	// Initialize() already tries this, but runs BEFORE this restore applies
	// the saved value, so it sees the class default (unanchored) and skips
	// it. Without this, a restored generator reports anchored/active/fueled
	// correctly but never actually rejoins its powernet -- it silently
	// contributes zero power, and anything drawing from that grid falls back
	// to draining its own cell until it reads as unpowered.
	if(anchored)
		connect_to_network()
	// Same issue, same cause, for the looping hum: Initialize() constructs
	// soundloop with start_immediately = active, but sees the class default
	// (FALSE) since this restore hasn't run yet -- so a generator saved
	// while running comes back reporting active but silently mute until
	// manually toggled off and back on. soundloop is always non-null by this
	// point (Initialize() constructs it unconditionally).
	if(active)
		soundloop.start(src)

/obj/structure/machinery/power/solar_control
	worldstate_vars = list("track", "trackrate")

/obj/structure/machinery/power/generator
	worldstate_vars = list("anchored")

// =====================================================================
// EXPLICIT PROCS  complex serialization that needs custom logic
// =====================================================================

// ------- APC (nested cell.charge) -------

/obj/structure/machinery/power/apc/worldstate_get_content()
	var/list/content = list()
	content["name"]       = name
	content["lighting"]   = lighting
	content["equipment"]  = equipment
	content["environ"]    = environ
	content["chargemode"] = chargemode
	content["autoflag"]   = autoflag
	content["aidisabled"] = aidisabled
	content["locked"]     = locked
	// hacker (var/mob/living/silicon/ai) deliberately NOT persisted -- a live
	// mob reference can't survive a JSON round-trip through worldstate the
	// way a plain boolean/number can (the AI it names may not even exist in
	// a future session). infected is what actually matters for behavior
	// (which IPC gets hacked next); losing the "who did it" attribution on
	// restart is an acceptable tradeoff for not storing a dangling reference.
	content["emagged"]    = emagged
	content["infected"]   = infected
	if(cell)
		content["cell_type"]      = "[cell.type]"
		content["cell_charge"]    = cell.charge
		content["cell_maxcharge"] = cell.maxcharge
	return content

/obj/structure/machinery/power/apc/worldstate_apply_content(list/content)
	// Only overrides the formula-derived "[area] APC" name when it was
	// actually customized (e.g. via an area bulk-rename) -- the areasInitialize()
	// reorder above already makes the formula-derived name correct on its own,
	// this just preserves a manual override on top of that.
	if(!isnull(content["name"]) && length(content["name"]))
		name = content["name"]
	if(!isnull(content["lighting"]))   lighting   = content["lighting"]
	if(!isnull(content["equipment"]))  equipment  = content["equipment"]
	if(!isnull(content["environ"]))    environ    = content["environ"]
	if(!isnull(content["chargemode"])) chargemode = content["chargemode"]
	if(!isnull(content["autoflag"]))   autoflag   = content["autoflag"]
	if(!isnull(content["aidisabled"])) aidisabled = content["aidisabled"]
	if(!isnull(content["locked"]))     locked     = content["locked"]
	if(!isnull(content["emagged"]))    emagged    = content["emagged"]
	if(!isnull(content["infected"]))   infected   = content["infected"]
	if(content["cell_type"])
		var/celltype = text2path(content["cell_type"])
		if(celltype && (!cell || cell.type != celltype))
			if(cell)
				qdel(cell)
			cell = new celltype(src)
	if(cell && !isnull(content["cell_charge"]))
		cell.charge = text2num(content["cell_charge"])
	if(cell && !isnull(content["cell_maxcharge"]))
		cell.maxcharge = text2num(content["cell_maxcharge"])
	update_icon()

// ------- Camera (network is a list) -------

/obj/structure/machinery/camera/worldstate_get_content()
	return list("network" = json_encode(network), "status" = status)

/obj/structure/machinery/camera/worldstate_apply_content(list/content)
	if(content["network"])
		network = json_decode(content["network"])
	if(!isnull(content["status"]))
		status = text2num(content["status"])

// ------- Vending machine (stock loop) -------

/obj/structure/machinery/vending/worldstate_get_content()
	var/list/stock = list()
	for(var/datum/data/vending_product/P in product_records)
		stock["[P.product_path]"] = P.amount
	return list("active" = active, "emagged" = emagged, "stock" = json_encode(stock))

/obj/structure/machinery/vending/worldstate_apply_content(list/content)
	if(!isnull(content["active"]))  active  = content["active"]
	if(!isnull(content["emagged"])) emagged = content["emagged"]
	if(content["stock"])
		var/list/stock = json_decode(content["stock"])
		for(var/datum/data/vending_product/P in product_records)
			var/key = "[P.product_path]"
			if(key in stock)
				P.amount = text2num(stock[key])

// ------- Cryopod (null guard for unconfigured pods) -------

/obj/structure/machinery/cryopod/worldstate_get_content()
	if(!persistent_network && !personal_ckey && !crew_tagged && !tagger_disabled)
		return null
	return list("persistent_network" = persistent_network, "persistent_spawn" = persistent_spawn, "personal_ckey" = personal_ckey, "personal_char_name" = personal_char_name, "crew_tagged" = crew_tagged, "tagger_disabled" = tagger_disabled)

/obj/structure/machinery/cryopod/worldstate_apply_content(list/content)
	// Only apply non-empty network strings  don't let a stale empty DB value wipe the "public" default
	if(!isnull(content["persistent_network"]) && length(content["persistent_network"]))
		persistent_network = normalize_faction_uid(content["persistent_network"])
	if(!isnull(content["persistent_spawn"]))
		persistent_spawn = content["persistent_spawn"]
	if(!isnull(content["personal_ckey"]))
		personal_ckey = content["personal_ckey"]
	if(!isnull(content["crew_tagged"]))
		crew_tagged = content["crew_tagged"]
	if(!isnull(content["personal_char_name"]))
		personal_char_name = content["personal_char_name"]
	if(!isnull(content["tagger_disabled"]))
		tagger_disabled = content["tagger_disabled"]

// ------- Conveyor switch (needs update() not update_icon()) -------

/obj/structure/machinery/conveyor_switch/worldstate_get_content()
	return list("position" = position)

/obj/structure/machinery/conveyor_switch/worldstate_apply_content(list/content)
	position = text2num(content["position"])
	update()

// ------- Navigation beacon (needs set_codes() after apply) -------

/obj/structure/machinery/navbeacon/worldstate_get_content()
	return list(
		"location"  = location,
		"locked"    = locked,
		"freq"      = freq,
		"codes_txt" = codes_txt,
		"open"      = open
	)

/obj/structure/machinery/navbeacon/worldstate_apply_content(list/content)
	location = content["location"]
	locked   = content["locked"]
	open     = content["open"]
	if(!isnull(content["freq"]))
		freq = text2num(content["freq"]) || freq
	if(content["codes_txt"])
		codes_txt = content["codes_txt"]
		set_codes()
	update_icon()

// ------- Intercom (needs set_frequency() after apply) -------

/obj/item/radio/intercom/worldstate_get_content()
	return list(
		"default_frequency"      = default_frequency,
		"should_be_broadcasting" = should_be_broadcasting,
		"should_be_listening"    = should_be_listening
	)

/obj/item/radio/intercom/worldstate_apply_content(list/content)
	default_frequency      = text2num(content["default_frequency"]) || default_frequency
	should_be_broadcasting = content["should_be_broadcasting"]
	should_be_listening    = content["should_be_listening"]
	set_frequency(default_frequency)

// ------- Suit storage unit (saves SUIT/HELMET/MASK item state) -------

/obj/structure/machinery/suit_storage_unit/worldstate_get_content()
	var/list/content = list()
	if(SUIT)
		var/list/s = serializePersistentItem(SUIT)
		if(s) content["suit"] = json_encode(s)
	if(HELMET)
		var/list/h = serializePersistentItem(HELMET)
		if(h) content["helmet"] = json_encode(h)
	if(MASK)
		var/list/m = serializePersistentItem(MASK)
		if(m) content["mask"] = json_encode(m)
	if(!length(content)) return list()
	return content

/obj/structure/machinery/suit_storage_unit/worldstate_apply_content(list/content)
	if(SUIT)   { qdel(SUIT);   SUIT   = null }
	if(HELMET) { qdel(HELMET); HELMET = null }
	if(MASK)   { qdel(MASK);   MASK   = null }
	if(content["suit"])
		SUIT   = deserializePersistentItem(json_decode(content["suit"]),   src)
	if(content["helmet"])
		HELMET = deserializePersistentItem(json_decode(content["helmet"]), src)
	if(content["mask"])
		MASK   = deserializePersistentItem(json_decode(content["mask"]),   src)
	update_icon()

// ------- Solar control (trigger panel scan after apply) -------

/obj/structure/machinery/power/solar_control/worldstate_apply_content(list/content)
	..()
	if(track > 0)
		search_for_connected()

// ------- Ladder (save/restore target_up and target_down by position) -------

/obj/structure/ladder/worldstate_get_content()
	var/list/content = list("allowed_directions" = allowed_directions)
	if(target_down)
		var/turf/TL = get_turf(target_down)
		if(TL) { content["td_x"] = TL.x; content["td_y"] = TL.y; content["td_z"] = TL.z }
	if(target_up)
		var/turf/TU = get_turf(target_up)
		if(TU) { content["tu_x"] = TU.x; content["tu_y"] = TU.y; content["tu_z"] = TU.z }
	if(length(content) <= 1 && !target_up && !target_down) return list()
	return content

/obj/structure/ladder/worldstate_apply_content(list/content)
	if(content["allowed_directions"])
		allowed_directions = text2num(content["allowed_directions"])
	if(content["td_x"])
		var/turf/T = locate(text2num(content["td_x"]), text2num(content["td_y"]), text2num(content["td_z"]))
		if(T) for(var/obj/structure/ladder/BL in T)
			if(BL.allowed_directions & UP) { target_down = BL; BL.target_up = src; break }
	if(content["tu_x"])
		var/turf/T = locate(text2num(content["tu_x"]), text2num(content["tu_y"]), text2num(content["tu_z"]))
		if(T) for(var/obj/structure/ladder/BL in T)
			if(BL.allowed_directions & DOWN) { target_up = BL; BL.target_down = src; break }

// ------- Table (material/reinforced aren't flat vars -- round-trip by name) -------

/obj/structure/table
	worldstate_vars = list("flipped", "carpeted")

/obj/structure/table/worldstate_get_content()
	var/list/content = ..()
	if(!content) content = list()
	if(material)
		content["material_name"] = material.name
	if(reinforced)
		content["reinforced_name"] = reinforced.name
	return content

/obj/structure/table/worldstate_apply_content(list/content)
	..()
	if(content && content["material_name"])
		material = SSmaterials.get_material_by_name(content["material_name"])
	if(content && content["reinforced_name"])
		reinforced = SSmaterials.get_material_by_name(content["reinforced_name"])
	if(material)
		update_connections(1)
		update_desc()
		update_material()
		if(reinforced)
			AddComponent(/datum/component/armor, list(MELEE = ARMOR_MELEE_KNIVES, BULLET = ARMOR_BALLISTIC_MINOR))
	queue_icon_update()
	update_icon()
