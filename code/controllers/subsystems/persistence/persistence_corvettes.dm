/*
 * Persistence -- Faction Corvette Ledger
 *
 * Faction corvettes never persist in the live world or on the overmap --
 * only the ownership/lifecycle row survives (ss13_faction_corvettes). Buy
 * is a pure DB insert (see corvetteBuy()); Retrieve/Stash toggle between
 * "materialized on a Z with an overmap marker" and "DB row only, nothing in
 * the world" (see corvetteRetrieve()/corvetteStash()). This mirrors
 * drydockStash()/drydockRetrieve() (persistence_shuttles.dm) exactly, just
 * Z-based instead of turf-grid-based.
 *
 * Z's can never be freed by this engine (no decrementMaxZ()), so a stashed
 * corvette's old Z is deliberately abandoned rather than reused -- every
 * Retrieve calls load_new_z() fresh. The abandoned Z is genuinely empty
 * after resetZLevelContent() (turfs reverted, all content cleared), which
 * costs ~nothing per tick; reloading a template's map content back onto an
 * already-allocated Z is not a mechanism this codebase has, so trying to
 * reuse the old Z would mean inventing one. Not reusing is simpler and
 * matches how the engine already treats abandoned Z's everywhere else
 * (e.g. GLOB.cached_space).
 *
 * Table: ss13_faction_corvettes
 */

/// corvette_id -> /datum/faction_corvette, for every purchased corvette (owned, stashed or deployed).
GLOBAL_LIST_EMPTY(faction_corvettes)

/datum/faction_corvette
	var/corvette_id
	var/template_id
	var/faction_uid
	var/stashed = TRUE
	/// Only meaningful while stashed == FALSE -- null whenever stashed.
	var/z
	var/overmap_x
	var/overmap_y

/// Verbose debug logging for the faction corvette system -- writes to the
/// same dedicated persistence subsystem log file the drydock system uses
/// (log_drydock*, persistence_shuttles.dm), gated the same way, never shown
/// to players. Greppable by the "Corvette:" prefix.
/proc/log_corvette(text)
	log_subsystem_persistence_info("Corvette: [text]")

/proc/log_corvette_warning(text)
	log_subsystem_persistence_warning("Corvette: [text]")

/proc/log_corvette_error(text)
	log_subsystem_persistence_error("Corvette: [text]")

// ============================================================
// BOOT LOADER  called from shuttleStateRestore() (persistence_shuttles.dm)
// ============================================================

/// Restores the corvette ownership ledger. Under the backup-then-delete
/// lifecycle (see corvetteRetrieve()/corvetteStash()), a deployed corvette
/// has NO row in the main table at all -- it was deleted the moment it went
/// live, and only gets re-inserted on a successful Stash. So every row this
/// query finds should always already be stashed=1; a corvette lost mid-
/// deployment (crash before the shutdown sweep could force-stash it) simply
/// has no row here at all, and is only recoverable via its backup + Restore
/// Ship Backup. The stashed=0 branch below is defensive-only, kept in case
/// some future code path ever leaves a live row behind unexpectedly -- it
/// should never fire in practice.
/proc/corvetteLedgerRestore()
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		log_corvette_warning("corvetteLedgerRestore: SQL disabled or connection failed, nothing restored.")
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT corvette_id, template_id, faction_uid, stashed, z, overmap_x, overmap_y FROM ss13_faction_corvettes",
		list()
	)
	q.Execute()
	var/restored = 0
	var/reset_stale = 0
	while(q.NextRow())
		var/datum/faction_corvette/C = new()
		C.corvette_id = text2num(q.item[1])
		C.template_id = q.item[2]
		C.faction_uid = q.item[3]
		C.stashed     = !!text2num(q.item[4])
		C.z           = text2num(q.item[5])
		C.overmap_x   = text2num(q.item[6])
		C.overmap_y   = text2num(q.item[7])

		if(!C.stashed)
			log_corvette_error("corvetteLedgerRestore: corvette_id=[C.corvette_id] ('[C.template_id]', faction=[C.faction_uid]) was unexpectedly stashed=0 in the main table -- forcing back to stashed. This should not be possible under the backup-then-delete lifecycle; investigate how this row was written.")
			C.stashed   = TRUE
			C.z         = null
			C.overmap_x = null
			C.overmap_y = null
			reset_stale++

		GLOB.faction_corvettes[C.corvette_id] = C
		restored++
	qdel(q)

	log_corvette("corvetteLedgerRestore: [restored] corvette(s) restored[reset_stale ? ", [reset_stale] unexpectedly reset from a stale deployed row" : ""].")

// ============================================================
// BUY  pure purchase transaction, no world footprint
// ============================================================

/datum/controller/subsystem/persistence/proc/corvetteBuy(template_id, faction_uid, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_corvette("corvetteBuy: [acting] attempting to buy template '[template_id]' for faction [faction_uid].")

	if(!template_id || !faction_uid)
		log_corvette_warning("corvetteBuy: refused -- missing template_id or faction_uid (acting=[acting]).")
		return FALSE
	if(!can_configure_faction_shackle(user, faction_uid, 1))
		if(user)
			to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(faction_uid)] to buy a corvette."))
		log_corvette_warning("corvetteBuy: refused -- [acting] lacks officer access in [faction_uid].")
		return FALSE

	var/datum/map_template/faction_corvette/template = SSmapping.faction_corvette_templates[template_id]
	if(!template)
		if(user)
			to_chat(user, SPAN_WARNING("No such corvette template."))
		log_corvette_warning("corvetteBuy: refused -- unknown template_id '[template_id]' (acting=[acting]).")
		return FALSE

	if(template.price > 0 && !faction_debit(faction_uid, template.price, "Corvette: bought '[template.name]'"))
		if(user)
			to_chat(user, SPAN_WARNING("Faction account has insufficient funds."))
		log_corvette_warning("corvetteBuy: refused -- faction [faction_uid] has insufficient funds ([template.price] cr) (acting=[acting]).")
		return FALSE

	if(!databaseCheckConnection("corvetteBuy"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed -- purchase not completed. Contact an admin if funds were deducted."))
		log_corvette_error("corvetteBuy: database connection failed for '[template_id]' (acting=[acting]) -- faction was already debited, this needs admin attention.")
		return FALSE

	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_corvettes (template_id, faction_uid, stashed) VALUES (:tid, :faction, 1)",
		list("tid" = template_id, "faction" = faction_uid)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "corvetteBuy insert"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- purchase not completed. Contact an admin if funds were deducted."))
		log_corvette_error("corvetteBuy: DB insert failed for '[template_id]' (acting=[acting]).")
		return FALSE
	var/new_id = text2num(q.last_insert_id)
	qdel(q)

	var/datum/faction_corvette/C = new()
	C.corvette_id = new_id
	C.template_id = template_id
	C.faction_uid = faction_uid
	C.stashed = TRUE
	GLOB.faction_corvettes[new_id] = C

	if(user)
		to_chat(user, SPAN_GOOD("Purchased '[template.name]' -- retrieve it from the Faction Ship program."))
	log_corvette("corvetteBuy: [acting] bought '[template_id]' for faction [faction_uid] (corvette_id=[new_id]).")
	return TRUE

// ============================================================
// RETRIEVE  materialize: fresh Z, marker placed near the faction's beacon
// ============================================================

/datum/controller/subsystem/persistence/proc/corvetteRetrieve(corvette_id, obj/item/modular_computer/computer, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_corvette("corvetteRetrieve: [acting] attempting to retrieve corvette_id=[corvette_id].")

	var/datum/faction_corvette/C = GLOB.faction_corvettes[corvette_id]
	if(!C)
		if(user)
			to_chat(user, SPAN_WARNING("No such corvette."))
		log_corvette_warning("corvetteRetrieve: refused -- unknown corvette_id=[corvette_id] (acting=[acting]).")
		return FALSE
	if(!C.stashed)
		if(user)
			to_chat(user, SPAN_WARNING("That corvette is already deployed."))
		log_corvette_warning("corvetteRetrieve: refused -- corvette_id=[corvette_id] ('[C.template_id]') already deployed (acting=[acting]).")
		return FALSE
	if(!can_configure_faction_shackle(user, C.faction_uid, 1))
		if(user)
			to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(C.faction_uid)] to retrieve this corvette."))
		log_corvette_warning("corvetteRetrieve: refused -- [acting] lacks officer access in [C.faction_uid] for corvette_id=[corvette_id].")
		return FALSE

	var/turf/computer_turf = get_turf(computer)
	if(!computer_turf)
		if(user)
			to_chat(user, SPAN_WARNING("Cannot determine your current location."))
		log_corvette_warning("corvetteRetrieve: refused -- could not resolve computer's turf (acting=[acting]).")
		return FALSE

	var/obj/structure/machinery/faction_beacon/beacon = GLOB.faction_beacon_by_z["[computer_turf.z]"]
	if(!beacon)
		if(user)
			to_chat(user, SPAN_WARNING("This location isn't claimed by a faction beacon."))
		log_corvette_warning("corvetteRetrieve: refused -- no faction beacon claims z=[computer_turf.z] (acting=[acting]).")
		return FALSE
	if(beacon.faction_uid != C.faction_uid)
		if(user)
			to_chat(user, SPAN_WARNING("This beacon belongs to [get_faction_name(beacon.faction_uid)], not [get_faction_name(C.faction_uid)]."))
		log_corvette_warning("corvetteRetrieve: refused -- beacon on z=[computer_turf.z] belongs to [beacon.faction_uid], not [C.faction_uid] (acting=[acting]).")
		return FALSE

	var/datum/map_template/faction_corvette/template = SSmapping.faction_corvette_templates[C.template_id]
	if(!template)
		if(user)
			to_chat(user, SPAN_WARNING("This corvette's template is no longer available."))
		log_corvette_error("corvetteRetrieve: template '[C.template_id]' no longer registered for corvette_id=[corvette_id].")
		return FALSE

	// Back up the current (about-to-go-live) row before touching anything --
	// the main table row gets deleted once this corvette is deployed (see
	// below), so this backup is the only recoverable trace of ownership
	// until the next successful Stash. Single row per corvette_id, always
	// overwritten -- no explicit expiry needed.
	if(!databaseCheckConnection("corvetteRetrieve backup"))
		log_corvette_error("corvetteRetrieve: database connection failed backing up corvette_id=[corvette_id] (acting=[acting]).")
		return FALSE
	var/datum/db_query/bq = SSdbcore.NewQuery(
		{"INSERT INTO ss13_faction_corvettes_backup (corvette_id, template_id, faction_uid, purchased_at)
		SELECT corvette_id, template_id, faction_uid, purchased_at FROM ss13_faction_corvettes WHERE corvette_id = :id
		ON DUPLICATE KEY UPDATE template_id=VALUES(template_id), faction_uid=VALUES(faction_uid), purchased_at=VALUES(purchased_at), backed_up_at=NOW()"},
		list("id" = corvette_id)
	)
	bq.Execute()
	if(!databaseCheckQueryResult(bq, "corvetteRetrieve backup"))
		log_corvette_error("corvetteRetrieve: backup write failed for corvette_id=[corvette_id] -- proceeding anyway, but no recovery copy exists if this deployment is lost.")
	qdel(bq)

	// Suspend ZAS during the load or the freshly loaded hull gets vented
	// (same recipe as generate_away_site(), persistence_factions.dm:947-952).
	var/z_before = world.maxz
	SSair.can_fire = FALSE
	var/bounds = template.load_new_z(FALSE)
	SSair.can_fire = TRUE
	if(!bounds)
		if(user)
			to_chat(user, SPAN_WARNING("Failed to materialize corvette."))
		log_corvette_error("corvetteRetrieve: load_new_z() failed for template '[C.template_id]', corvette_id=[corvette_id].")
		return FALSE
	var/new_z = z_before + 1
	log_corvette("corvetteRetrieve: corvette_id=[corvette_id] materialized fresh at z=[new_z] for template '[C.template_id]'.")

	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[new_z]"]
	if(!istype(marker))
		log_corvette_error("corvetteRetrieve: no overmap marker found at freshly-loaded z=[new_z] for corvette_id=[corvette_id].")
		return FALSE
	corvettePlaceOvermapMarker(marker, beacon)

	C.stashed    = FALSE
	C.z          = new_z
	C.overmap_x  = marker.x
	C.overmap_y  = marker.y

	// Backup-then-delete lifecycle: a deployed corvette has no "current" row
	// in the main table at all -- the backup made above is what an admin
	// recovers from (Restore Ship Backup) if this deployment is somehow
	// lost before the next Stash.
	if(!databaseCheckConnection("corvetteRetrieve"))
		log_corvette_error("corvetteRetrieve: database connection failed deleting corvette_id=[corvette_id] -- ledger row now disagrees with live state until next save.")
	else
		var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_faction_corvettes WHERE corvette_id = :id", list("id" = corvette_id))
		dq.Execute()
		if(!databaseCheckQueryResult(dq, "corvetteRetrieve delete"))
			log_corvette_error("corvetteRetrieve: DB delete failed for corvette_id=[corvette_id].")
		qdel(dq)

	if(user)
		to_chat(user, SPAN_GOOD("Corvette retrieved near [beacon.name]."))
	log_corvette("corvetteRetrieve: corvette_id=[corvette_id] deployed at z=[C.z], overmap ([C.overmap_x],[C.overmap_y]) (acting=[acting]).")
	return TRUE

/// Places a freshly-materialized corvette's overmap marker within the
/// claiming beacon's own security_radius of that beacon's overmap sector --
/// reuses the beacon's existing, already-admin-configurable radius number
/// rather than inventing a new one. Mirrors move_to_starting_location()'s
/// own retry-then-exhaustive-scan-then-share-a-tile fallback shape
/// (sectors.dm:127-182).
/datum/controller/subsystem/persistence/proc/corvettePlaceOvermapMarker(obj/effect/overmap/visitable/ship/landable/marker, obj/structure/machinery/faction_beacon/beacon)
	var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(beacon)]"]
	if(!istype(beacon_sector))
		log_corvette_warning("corvettePlaceOvermapMarker: beacon on z=[GET_Z(beacon)] has no overmap sector, leaving marker at its default placement.")
		return

	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
	var/radius = max(1, beacon.security_radius)

	var/turf/home
	var/tries = 10
	while(tries > 0)
		tries--
		var/turf/candidate = CircularRandomTurfAround(beacon_sector, radius, map_low, map_low, map_high, map_high)
		if(candidate && !(locate(/obj/effect/overmap/visitable) in candidate))
			home = candidate
			break
	if(!home)
		home = CircularRandomTurfAround(beacon_sector, radius, map_low, map_low, map_high, map_high)
		log_corvette_warning("corvettePlaceOvermapMarker: no free tile within radius [radius] of beacon sector after retries, sharing a tile.")

	if(home)
		marker.start_x = home.x
		marker.start_y = home.y
		marker.forceMove(home)
		log_corvette("corvettePlaceOvermapMarker: placed marker at ([home.x],[home.y]), radius=[radius] of beacon sector.")

// ============================================================
// STASH  wipe content, remove the marker, ledger row only
// ============================================================

/datum/controller/subsystem/persistence/proc/corvetteStash(corvette_id, mob/user, force = FALSE)
	var/acting = user ? key_name(user) : "SYSTEM[force ? "(force)" : ""]"
	log_corvette("corvetteStash: [acting] attempting to stash corvette_id=[corvette_id].")

	var/datum/faction_corvette/C = GLOB.faction_corvettes[corvette_id]
	if(!C)
		log_corvette_warning("corvetteStash: refused -- unknown corvette_id=[corvette_id] (acting=[acting]).")
		return FALSE
	if(C.stashed)
		if(user)
			to_chat(user, SPAN_WARNING("That corvette is already stashed."))
		log_corvette_warning("corvetteStash: refused -- corvette_id=[corvette_id] already stashed (acting=[acting]).")
		return FALSE
	if(!force && !can_configure_faction_shackle(user, C.faction_uid, 1))
		if(user)
			to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(C.faction_uid)] to stash this corvette."))
		log_corvette_warning("corvetteStash: refused -- [acting] lacks officer access in [C.faction_uid] for corvette_id=[corvette_id].")
		return FALSE
	if(!force)
		var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[C.z]"]
		var/at_beacon = FALSE
		if(istype(marker))
			for(var/bz in GLOB.faction_beacon_by_z)
				var/obj/structure/machinery/faction_beacon/B = GLOB.faction_beacon_by_z[bz]
				if(!B || B.faction_uid != C.faction_uid)
					continue
				var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
				if(istype(beacon_sector) && get_dist(marker, beacon_sector) <= 1)
					at_beacon = TRUE
					break
		if(!at_beacon)
			if(user)
				to_chat(user, SPAN_WARNING("You must be within 1 tile of a friendly faction beacon to stash this corvette."))
			log_corvette_warning("corvetteStash: refused -- corvette_id=[corvette_id] not within 1 tile of a faction [C.faction_uid] beacon on the overmap (acting=[acting]).")
			return FALSE
	if(zlevel_has_players(C.z))
		if(user)
			to_chat(user, SPAN_WARNING("Make sure everyone is off the corvette first."))
		log_corvette_warning("corvetteStash: refused -- players still present on z=[C.z] for corvette_id=[corvette_id] (acting=[acting]).")
		return FALSE

	resetZLevelContent(C.z)

	// Remove the marker and, critically, clear every GLOB.map_sectors entry
	// pointing to it -- unlike drydock pads, nothing in this codebase ever
	// deletes a live overmap ship marker today, and GLOB.map_sectors is
	// looked up unchecked in ~90 places across the codebase. Leaving a
	// dangling entry after qdel() would be a live landmine (e.g.
	// zone_security_update_overmap()'s full-list sweep, persistence_zone_security.dm:89).
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[C.z]"]
	if(istype(marker))
		for(var/zlevel in marker.map_z)
			GLOB.map_sectors["[zlevel]"] = null
		qdel(marker)
	else
		log_corvette_warning("corvetteStash: no overmap marker found at z=[C.z] for corvette_id=[corvette_id] -- already gone?")

	C.stashed   = TRUE
	C.z         = null
	C.overmap_x = null
	C.overmap_y = null

	// Backup-then-delete lifecycle: the main table row doesn't exist while
	// deployed (see corvetteRetrieve()), so this is always a fresh INSERT,
	// not an UPDATE -- explicit corvette_id (not auto-increment) so the row
	// always matches the key GLOB.faction_corvettes already stores it under.
	// purchased_at is pulled back from the backup row (captured at the last
	// Retrieve) so the original purchase date survives the round trip
	// instead of resetting to "now" every stash cycle.
	if(!databaseCheckConnection("corvetteStash"))
		log_corvette_error("corvetteStash: database connection failed writing corvette_id=[corvette_id] -- ledger row now disagrees with live state until next save.")
	else
		var/purchased_at
		var/datum/db_query/pq = SSdbcore.NewQuery(
			"SELECT purchased_at FROM ss13_faction_corvettes_backup WHERE corvette_id = :id",
			list("id" = corvette_id)
		)
		pq.Execute()
		if(databaseCheckQueryResult(pq, "corvetteStash purchased_at lookup") && pq.NextRow())
			purchased_at = pq.item[1]
		qdel(pq)

		var/datum/db_query/iq = SSdbcore.NewQuery(
			{"INSERT INTO ss13_faction_corvettes (corvette_id, template_id, faction_uid, stashed, stashed_at, purchased_at)
			VALUES (:id, :tid, :faction, 1, NOW(), COALESCE(:purchased, NOW()))
			ON DUPLICATE KEY UPDATE stashed=1, stashed_at=NOW()"},
			list("id" = corvette_id, "tid" = C.template_id, "faction" = C.faction_uid, "purchased" = purchased_at)
		)
		iq.Execute()
		if(!databaseCheckQueryResult(iq, "corvetteStash insert"))
			log_corvette_error("corvetteStash: DB write failed for corvette_id=[corvette_id].")
		qdel(iq)

	if(user)
		to_chat(user, SPAN_GOOD("Corvette stashed."))
	log_corvette("corvetteStash: corvette_id=[corvette_id] fully stashed and torn down (acting=[acting]).")
	return TRUE

// ============================================================
// SHUTDOWN SAFETY NET  called from SSpersistence.Shutdown()/forceSaveAll()
// ============================================================

/// Force-stashes every deployed corvette at shutdown, mirroring
/// drydockAutoStashAll() exactly -- so a faction never loses a corvette
/// they simply forgot to stash before a graceful restart.
/datum/controller/subsystem/persistence/proc/corvetteAutoStashAll()
	PRIVATE_PROC(TRUE)
	var/list/deployed = list()
	for(var/cid in GLOB.faction_corvettes)
		var/datum/faction_corvette/C = GLOB.faction_corvettes[cid]
		if(C && !C.stashed)
			deployed += cid
	log_corvette("corvetteAutoStashAll: sweep starting -- [deployed.len] deployed corvette(s) found.")

	var/stashed_count = 0
	var/skipped_count = 0
	for(var/cid in deployed)
		if(corvetteStash(cid, null, force = TRUE))
			stashed_count++
		else
			skipped_count++
			log_corvette_warning("corvetteAutoStashAll: corvetteStash() refused for corvette_id=[cid] -- see preceding warning for reason.")

	log_corvette("corvetteAutoStashAll: sweep complete -- [stashed_count] stashed, [skipped_count] skipped.")
