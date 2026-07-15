/*
 * Persistence -- Drydock Ship Ledger
 *
 * Drydock ships never persist in the live world or on the overmap -- only
 * the ownership/lifecycle row survives (ss13_drydock_ships). Buy is a pure
 * DB insert (see drydockBuy()); Retrieve/Stash toggle between "materialized
 * on a Z with an overmap marker" and "DB row only, nothing in the world"
 * (see drydockRetrieve()/drydockStash()). This mirrors corvetteRetrieve()/
 * corvetteStash() (persistence_corvettes.dm) almost exactly -- the one
 * difference is the anchor point: a docking beacon (any registered
 * navigation destination a ship flies to and lands at under its own power)
 * instead of a faction beacon (which claims a whole Z). Ownership can be
 * personal (owner_ckey) or faction (faction_uid), unlike corvettes which
 * are always faction-owned.
 *
 * Z's can never be freed by this engine (no decrementMaxZ()), so a stashed
 * ship's old Z is deliberately abandoned rather than reused -- every
 * Retrieve calls load_new_z() fresh, matching corvettes' own reasoning
 * (see persistence_corvettes.dm's file header).
 *
 * Tables: ss13_drydock_ships, ss13_drydock_ships_backup, ss13_persistent_shuttles
 */

/// shuttle_id -> /datum/drydock_ship, for every purchased drydock ship (owned, stashed or deployed).
GLOBAL_LIST_EMPTY(drydock_ships)

/datum/drydock_ship
	var/shuttle_id
	var/template_id
	var/owner_ckey
	var/faction_uid
	var/stashed = TRUE
	/// Only meaningful while stashed == FALSE -- null whenever stashed.
	var/z
	var/overmap_x
	var/overmap_y

/// Verbose debug logging for the drydock/shuttle system -- writes to the
/// dedicated persistence subsystem log file (gated behind the
/// log_subsystems_persistence config toggle), never shown to players. Every
/// call goes through one of these three so the log file is greppable by the
/// "Drydock:" prefix and severity is visually obvious.
/proc/log_drydock(text)
	log_subsystem_persistence_info("Drydock: [text]")

/proc/log_drydock_warning(text)
	log_subsystem_persistence_warning("Drydock: [text]")

/proc/log_drydock_error(text)
	log_subsystem_persistence_error("Drydock: [text]")

// ============================================================
// SAVE  called from SSpersistence.Shutdown()
// ============================================================

/datum/controller/subsystem/persistence/proc/shuttleStateFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("shuttleStateFinalize"))
		log_drydock_error("shuttleStateFinalize: database connection failed, no shuttle positions saved this cycle.")
		return

	if(!istype(SSshuttle) || !SSshuttle.shuttles)
		log_drydock_warning("shuttleStateFinalize: SSshuttle not ready, skipping.")
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
		log_drydock_warning("shuttleStateRestore: SQL disabled or connection failed, nothing restored.")
		return

	if(!istype(SSshuttle) || !SSshuttle.shuttles)
		log_drydock_warning("shuttleStateRestore: SSshuttle not ready, nothing restored.")
		return

	// Step 1: Recreate player docking beacon landmarks (must exist before
	// any ship's navigation console scans for them) -- also registers each
	// into its own Z's overmap sector waypoint list, same as a freshly
	// activated beacon does (docking_beacon/_register_landmark()), so a
	// beacon that existed before a restart is immediately flyable-to again.
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
		if(SSshuttle.registered_shuttle_landmarks[btag])
			log_drydock("shuttleStateRestore Step 1: beacon landmark '[btag]' already registered, skipping row.")
			continue
		// Z became persistence-excluded since this row was written (e.g. a
		// dynamic away site that wasn't pinned) -- away-site Z-numbers
		// reshuffle every boot, so trusting this row's z any further could
		// locate() into whatever unrelated content now occupies that
		// number. Prune it rather than leaving it to linger forever.
		if(persistence_z_excluded(bz))
			log_drydock_warning("shuttleStateRestore Step 1: beacon landmark '[btag]' -- z=[bz] is now persistence-excluded, pruning stale row.")
			var/datum/db_query/pruneq = SSdbcore.NewQuery("DELETE FROM ss13_player_docking_beacons WHERE landmark_tag = :tag", list("tag" = btag))
			pruneq.Execute()
			qdel(pruneq)
			continue
		var/turf/bt = locate(bx, by, bz)
		if(!bt)
			log_drydock_warning("shuttleStateRestore Step 1: beacon landmark '[btag]' -- turf ([bx],[by],[bz]) does not exist, skipping.")
			continue
		var/obj/effect/shuttle_landmark/player_dock/bl = new /obj/effect/shuttle_landmark/player_dock(bt)
		bl.landmark_tag = btag
		bl.name         = blabel ? blabel : "Docking Port ([bx],[by],[bz])"
		bl.base_turf    = /turf/simulated/floor/plating
		var/obj/effect/overmap/visitable/sector = GLOB.map_sectors["[bz]"]
		if(sector)
			sector.add_landmark(bl, null)
		beacons_restored++
		log_drydock("shuttleStateRestore Step 1: restored beacon landmark '[btag]' at ([bx],[by],[bz]).")
	qdel(bq)

	// Step 2: Restore saved positions for map-placed shuttles (e.g. the
	// Horizon's own autodock shuttles). Drydock ships and corvettes are
	// reconstructed on demand by their own Retrieve procs, never at boot --
	// see Step 3/Step 4 below for their ownership-ledger restore instead.
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
			log_drydock("shuttleStateRestore Step 2: shuttle '[sname]' has no live datum (not reconstructed), skipping position restore.")
			continue

		var/obj/effect/shuttle_landmark/dest = SSshuttle.registered_shuttle_landmarks[tag]
		if(!dest)
			skipped++
			log_world("shuttleStateRestore: landmark '[tag]' not found for shuttle '[sname]' -- leaving at default.")
			log_drydock_warning("shuttleStateRestore Step 2: shuttle '[sname]' -- landmark '[tag]' not registered, left at default position.")
			continue

		if(S.current_location && S.current_location.landmark_tag == tag)
			skipped++
			log_drydock("shuttleStateRestore Step 2: shuttle '[sname]' already at landmark '[tag]', no move needed.")
			continue

		S.short_jump(dest)
		restored++
		log_drydock("shuttleStateRestore Step 2: moved shuttle '[sname]' to landmark '[tag]'.")

	qdel(q)
	log_world("shuttleStateRestore: [beacons_restored] beacon(s) restored, [restored] position(s) restored, [skipped] skipped.")

	// Step 3: restore the faction corvette ownership ledger (persistence_corvettes.dm).
	corvetteLedgerRestore()

	// Step 4: restore the drydock ship ownership ledger (below).
	drydockShipLedgerRestore()

// ============================================================
// BOOT LOADER  called from shuttleStateRestore() above
// ============================================================

/// Restores the drydock ship ownership ledger. Under the backup-then-delete
/// lifecycle (see drydockRetrieve()/drydockStash()), a deployed ship has NO
/// row in the main table at all -- it was deleted the moment it went live,
/// and only gets re-inserted on a successful Stash. So every row this query
/// finds should always already be stashed=1; a ship lost mid-deployment
/// (crash before the shutdown sweep could force-stash it) simply has no row
/// here at all, and is only recoverable via its backup + Restore Ship
/// Backup. The stashed=0 branch below is defensive-only, mirroring
/// corvetteLedgerRestore() -- it should never fire in practice.
/proc/drydockShipLedgerRestore()
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		log_drydock_warning("drydockShipLedgerRestore: SQL disabled or connection failed, nothing restored.")
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT shuttle_id, template_id, owner_ckey, faction_uid, stashed, z, overmap_x, overmap_y FROM ss13_drydock_ships",
		list()
	)
	q.Execute()
	var/restored = 0
	var/reset_stale = 0
	while(q.NextRow())
		var/datum/drydock_ship/DS = new()
		DS.shuttle_id  = text2num(q.item[1])
		DS.template_id = q.item[2]
		DS.owner_ckey  = q.item[3]
		DS.faction_uid = q.item[4]
		DS.stashed     = !!text2num(q.item[5])
		DS.z           = text2num(q.item[6])
		DS.overmap_x   = text2num(q.item[7])
		DS.overmap_y   = text2num(q.item[8])

		if(!DS.stashed)
			log_drydock_error("drydockShipLedgerRestore: shuttle_id=[DS.shuttle_id] ('[DS.template_id]') was unexpectedly stashed=0 in the main table -- forcing back to stashed. This should not be possible under the backup-then-delete lifecycle; investigate how this row was written.")
			DS.stashed   = TRUE
			DS.z         = null
			DS.overmap_x = null
			DS.overmap_y = null
			reset_stale++

		GLOB.drydock_ships[DS.shuttle_id] = DS
		restored++
	qdel(q)

	log_drydock("drydockShipLedgerRestore: [restored] drydock ship(s) restored[reset_stale ? ", [reset_stale] unexpectedly reset from a stale deployed row" : ""].")

// ============================================================
// BUY  pure purchase transaction, no world footprint
// ============================================================

/datum/controller/subsystem/persistence/proc/drydockBuy(template_id, owner_ckey, faction_uid, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_drydock("drydockBuy: [acting] attempting to buy template '[template_id]' (owner=[owner_ckey || "none"], faction=[faction_uid || "none"]).")

	if(!template_id || (!owner_ckey && !faction_uid))
		log_drydock_warning("drydockBuy: refused -- missing template_id or both owner_ckey/faction_uid (acting=[acting]).")
		return FALSE

	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[template_id]
	if(!template)
		if(user)
			to_chat(user, SPAN_WARNING("No such ship template."))
		log_drydock_warning("drydockBuy: refused -- unknown template_id '[template_id]' (acting=[acting]).")
		return FALSE

	if(faction_uid)
		if(!can_configure_faction_shackle(user, faction_uid, 1))
			if(user)
				to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(faction_uid)] to buy a ship for the faction."))
			log_drydock_warning("drydockBuy: refused -- [acting] lacks officer access in [faction_uid].")
			return FALSE
		if(template.price > 0 && !faction_debit(faction_uid, template.price, "Drydock: bought '[template.name]'"))
			if(user)
				to_chat(user, SPAN_WARNING("Faction account has insufficient funds."))
			log_drydock_warning("drydockBuy: refused -- faction [faction_uid] has insufficient funds ([template.price] cr) (acting=[acting]).")
			return FALSE
	else if(template.price > 0)
		var/obj/item/card/id/ID = user?.GetIdCard()
		if(!ID || !ID.associated_account_number)
			if(user)
				to_chat(user, SPAN_WARNING("No linked bank account."))
			log_drydock_warning("drydockBuy: refused -- [acting] has no linked bank account.")
			return FALSE
		var/datum/money_account/acc = SSeconomy.get_account(ID.associated_account_number)
		if(!acc || acc.money < template.price)
			if(user)
				to_chat(user, SPAN_WARNING("Insufficient funds."))
			log_drydock_warning("drydockBuy: refused -- [acting] has insufficient personal funds ([template.price] cr).")
			return FALSE
		acc.adjust_money(-template.price)

	if(!databaseCheckConnection("drydockBuy"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed -- purchase not completed. Contact an admin if funds were deducted."))
		log_drydock_error("drydockBuy: database connection failed for '[template_id]' (acting=[acting]) -- funds may already be deducted, needs admin attention.")
		return FALSE

	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_drydock_ships (template_id, owner_ckey, faction_uid, stashed) VALUES (:tid, :ckey, :faction, 1)",
		list("tid" = template_id, "ckey" = owner_ckey, "faction" = faction_uid)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockBuy insert"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- purchase not completed. Contact an admin if funds were deducted."))
		log_drydock_error("drydockBuy: DB insert failed for '[template_id]' (acting=[acting]).")
		return FALSE
	var/new_id = text2num(q.last_insert_id)
	qdel(q)

	var/datum/drydock_ship/DS = new()
	DS.shuttle_id  = new_id
	DS.template_id = template_id
	DS.owner_ckey  = owner_ckey
	DS.faction_uid = faction_uid
	DS.stashed     = TRUE
	GLOB.drydock_ships[new_id] = DS

	if(user)
		to_chat(user, SPAN_GOOD("Purchased '[template.name]' -- retrieve it from the Drydock program."))
	log_drydock("drydockBuy: [acting] bought '[template_id]' (owner=[owner_ckey || "none"], faction=[faction_uid || "none"], shuttle_id=[new_id]).")
	return TRUE

// ============================================================
// RETRIEVE  materialize: fresh Z, marker placed near the docking beacon
// ============================================================

/datum/controller/subsystem/persistence/proc/drydockRetrieve(shuttle_id, obj/structure/machinery/docking_beacon/beacon, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_drydock("drydockRetrieve: [acting] attempting to retrieve shuttle_id=[shuttle_id].")

	var/datum/drydock_ship/DS = GLOB.drydock_ships[shuttle_id]
	if(!DS)
		if(user)
			to_chat(user, SPAN_WARNING("No such drydock ship."))
		log_drydock_warning("drydockRetrieve: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!DS.stashed)
		if(user)
			to_chat(user, SPAN_WARNING("That ship is already deployed."))
		log_drydock_warning("drydockRetrieve: refused -- shuttle_id=[shuttle_id] ('[DS.template_id]') already deployed (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || (DS.owner_ckey && user && DS.owner_ckey == user.ckey) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to retrieve this ship."))
		log_drydock_warning("drydockRetrieve: refused -- [acting] lacks permission for shuttle_id=[shuttle_id] (owner=[DS.owner_ckey || "none"], faction=[DS.faction_uid || "none"]).")
		return FALSE

	if(!istype(beacon))
		if(user)
			to_chat(user, SPAN_WARNING("No docking beacon in range."))
		log_drydock_warning("drydockRetrieve: refused -- no beacon provided (acting=[acting]).")
		return FALSE
	if(!beacon.beacon_active)
		if(user)
			to_chat(user, SPAN_WARNING("This beacon isn't active."))
		log_drydock_warning("drydockRetrieve: refused -- beacon '[beacon.landmark_tag]' not active (acting=[acting]).")
		return FALSE
	if(beacon.faction_restricted && beacon.faction_restricted != DS.faction_uid && !check_rights(R_ADMIN, 0, user))
		if(user)
			to_chat(user, SPAN_WARNING("This beacon is restricted to [get_faction_name(beacon.faction_restricted)]."))
		log_drydock_warning("drydockRetrieve: refused -- beacon '[beacon.landmark_tag]' restricted to [beacon.faction_restricted], shuttle_id=[shuttle_id] belongs to [DS.faction_uid || "no faction"] (acting=[acting]).")
		return FALSE

	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
	if(!template)
		if(user)
			to_chat(user, SPAN_WARNING("This ship's template is no longer available."))
		log_drydock_error("drydockRetrieve: template '[DS.template_id]' no longer registered for shuttle_id=[shuttle_id].")
		return FALSE

	// Back up the current (about-to-go-live) row before touching anything --
	// the main table row gets deleted once this ship is deployed (see
	// below), so this backup is the only recoverable trace of ownership
	// until the next successful Stash. Single row per shuttle_id, always
	// overwritten -- no explicit expiry needed.
	if(!databaseCheckConnection("drydockRetrieve backup"))
		log_drydock_error("drydockRetrieve: database connection failed backing up shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	var/datum/db_query/bq = SSdbcore.NewQuery(
		{"INSERT INTO ss13_drydock_ships_backup (shuttle_id, template_id, owner_ckey, faction_uid, purchased_at)
		SELECT shuttle_id, template_id, owner_ckey, faction_uid, purchased_at FROM ss13_drydock_ships WHERE shuttle_id = :id
		ON DUPLICATE KEY UPDATE template_id=VALUES(template_id), owner_ckey=VALUES(owner_ckey), faction_uid=VALUES(faction_uid), purchased_at=VALUES(purchased_at), backed_up_at=NOW()"},
		list("id" = shuttle_id)
	)
	bq.Execute()
	if(!databaseCheckQueryResult(bq, "drydockRetrieve backup"))
		log_drydock_error("drydockRetrieve: backup write failed for shuttle_id=[shuttle_id] -- proceeding anyway, but no recovery copy exists if this deployment is lost.")
	qdel(bq)

	// Suspend ZAS during the load or the freshly loaded hull gets vented
	// (same recipe as generate_away_site()/corvetteRetrieve()).
	var/z_before = world.maxz
	SSair.can_fire = FALSE
	var/bounds = template.load_new_z(FALSE)
	SSair.can_fire = TRUE
	if(!bounds)
		if(user)
			to_chat(user, SPAN_WARNING("Failed to materialize ship."))
		log_drydock_error("drydockRetrieve: load_new_z() failed for template '[DS.template_id]', shuttle_id=[shuttle_id].")
		return FALSE
	var/new_z = z_before + 1
	log_drydock("drydockRetrieve: shuttle_id=[shuttle_id] materialized fresh at z=[new_z] for template '[DS.template_id]'.")

	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[new_z]"]
	if(!istype(marker))
		log_drydock_error("drydockRetrieve: no overmap marker found at freshly-loaded z=[new_z] for shuttle_id=[shuttle_id].")
		return FALSE
	drydockPlaceOvermapMarker(marker, beacon)

	// Mirrors the old player_built pattern -- faction ownership lives on
	// the shuttle datum itself so player_dock/is_valid() can enforce a
	// beacon's faction restriction without needing to reverse-lookup the
	// ledger from inside the landmark check.
	var/datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum = SSshuttle.shuttles[marker.shuttle]
	if(istype(shuttle_datum))
		shuttle_datum.faction_uid = DS.faction_uid

	DS.stashed   = FALSE
	DS.z         = new_z
	DS.overmap_x = marker.x
	DS.overmap_y = marker.y

	// Backup-then-delete lifecycle: a deployed ship has no "current" row in
	// the main table at all -- the backup made above is what an admin
	// recovers from (Restore Ship Backup) if this deployment is somehow
	// lost before the next Stash.
	if(!databaseCheckConnection("drydockRetrieve"))
		log_drydock_error("drydockRetrieve: database connection failed deleting shuttle_id=[shuttle_id] -- ledger row now disagrees with live state until next save.")
	else
		var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_drydock_ships WHERE shuttle_id = :id", list("id" = shuttle_id))
		dq.Execute()
		if(!databaseCheckQueryResult(dq, "drydockRetrieve delete"))
			log_drydock_error("drydockRetrieve: DB delete failed for shuttle_id=[shuttle_id].")
		qdel(dq)

	if(user)
		to_chat(user, SPAN_GOOD("Ship retrieved near [beacon.dock_label || beacon.landmark_tag] -- fly it in using its own navigation console."))
	log_drydock("drydockRetrieve: shuttle_id=[shuttle_id] deployed at z=[DS.z], overmap ([DS.overmap_x],[DS.overmap_y]) (acting=[acting]).")
	return TRUE

/// Places a freshly-materialized ship's overmap marker within a fixed
/// radius of the retrieving beacon's own overmap sector -- mirrors
/// corvettePlaceOvermapMarker() exactly (same retry-then-exhaustive-scan-
/// then-share-a-tile shape), just anchored to a docking beacon's sector
/// instead of a faction beacon's, and using a fixed radius since
/// docking_beacon has no per-instance security_radius the way faction
/// beacons do.
#define DRYDOCK_SHIP_PLACEMENT_RADIUS 3
/datum/controller/subsystem/persistence/proc/drydockPlaceOvermapMarker(obj/effect/overmap/visitable/ship/landable/marker, obj/structure/machinery/docking_beacon/beacon, is_retry = FALSE)
	if(QDELETED(marker) || QDELETED(beacon))
		return
	var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(beacon)]"]
	if(!istype(beacon_sector))
		// Never leave the marker at its mapped .dmm turf (the ship's own
		// cockpit) -- sector view cameras onto the marker's loc, so an
		// unplaced marker shows ship interior instead of the overmap.
		// Random-place on the overmap now, and retry the intended
		// near-beacon placement once, for the init-order race where the
		// beacon's sector hasn't registered yet during post-save retrieval.
		log_drydock_warning("drydockPlaceOvermapMarker: beacon '[beacon.landmark_tag]' on z=[GET_Z(beacon)] has no overmap sector, [is_retry ? "keeping fallback placement" : "using fallback placement and scheduling one retry"].")
		marker.move_to_starting_location()
		if(!is_retry)
			addtimer(CALLBACK(src, PROC_REF(drydockPlaceOvermapMarker), marker, beacon, TRUE), 1 MINUTE)
		return

	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE

	var/turf/home
	var/tries = 10
	while(tries > 0)
		tries--
		var/turf/candidate = CircularRandomTurfAround(beacon_sector, DRYDOCK_SHIP_PLACEMENT_RADIUS, map_low, map_low, map_high, map_high)
		if(candidate && !(locate(/obj/effect/overmap/visitable) in candidate))
			home = candidate
			break
	if(!home)
		home = CircularRandomTurfAround(beacon_sector, DRYDOCK_SHIP_PLACEMENT_RADIUS, map_low, map_low, map_high, map_high)
		log_drydock_warning("drydockPlaceOvermapMarker: no free tile within radius [DRYDOCK_SHIP_PLACEMENT_RADIUS] of beacon sector after retries, sharing a tile.")

	if(home)
		marker.start_x = home.x
		marker.start_y = home.y
		marker.forceMove(home)
		log_drydock("drydockPlaceOvermapMarker: placed marker at ([home.x],[home.y]), radius=[DRYDOCK_SHIP_PLACEMENT_RADIUS] of beacon sector.")
#undef DRYDOCK_SHIP_PLACEMENT_RADIUS

// ============================================================
// STASH  wipe content, remove the marker, ledger row only
// ============================================================

/// force=TRUE (shutdown sweep / admin Force Stash) skips the "must be
/// genuinely docked at a registered beacon" check -- there's no way to fly
/// an abandoned ship home on demand the way the old turf-pad system could
/// relocate a hull, so an emergency stash just tears it down wherever it
/// is, same as corvetteStash()'s own force path.
/datum/controller/subsystem/persistence/proc/drydockStash(shuttle_id, mob/user, force = FALSE)
	var/acting = user ? key_name(user) : "SYSTEM[force ? "(force)" : ""]"
	log_drydock("drydockStash: [acting] attempting to stash shuttle_id=[shuttle_id].")

	var/datum/drydock_ship/DS = GLOB.drydock_ships[shuttle_id]
	if(!DS)
		log_drydock_warning("drydockStash: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(DS.stashed)
		if(user)
			to_chat(user, SPAN_WARNING("That ship is already stashed."))
		log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] already stashed (acting=[acting]).")
		return FALSE
	if(!force && !(check_rights(R_ADMIN, 0, user) || (DS.owner_ckey && user && DS.owner_ckey == user.ckey) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to stash this ship."))
		log_drydock_warning("drydockStash: refused -- [acting] lacks permission for shuttle_id=[shuttle_id] (owner=[DS.owner_ckey || "none"], faction=[DS.faction_uid || "none"]).")
		return FALSE
	if(!force)
		var/obj/effect/overmap/visitable/ship/landable/check_marker = GLOB.map_sectors["[DS.z]"]
		var/datum/shuttle/shuttle_datum = istype(check_marker) ? SSshuttle.shuttles[check_marker.shuttle] : null
		if(!shuttle_datum || !istype(shuttle_datum.current_location, /obj/effect/shuttle_landmark/player_dock))
			if(user)
				to_chat(user, SPAN_WARNING("This ship must be docked at a drydock beacon to be stashed."))
			log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] not docked at a drydock beacon (acting=[acting]).")
			return FALSE
	if(zlevel_has_players(DS.z))
		if(user)
			to_chat(user, SPAN_WARNING("Make sure everyone is off the ship first."))
		log_drydock_warning("drydockStash: refused -- players still present on z=[DS.z] for shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	resetZLevelContent(DS.z)

	// Remove the marker and, critically, clear every GLOB.map_sectors entry
	// pointing to it -- see corvetteStash()'s own comment on this being a
	// live landmine otherwise (~90 unchecked lookups across the codebase).
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[DS.z]"]
	if(istype(marker))
		for(var/zlevel in marker.map_z)
			GLOB.map_sectors["[zlevel]"] = null
		qdel(marker)
	else
		log_drydock_warning("drydockStash: no overmap marker found at z=[DS.z] for shuttle_id=[shuttle_id] -- already gone?")

	DS.stashed   = TRUE
	DS.z         = null
	DS.overmap_x = null
	DS.overmap_y = null

	// Backup-then-delete lifecycle: the main table row doesn't exist while
	// deployed (see drydockRetrieve()), so this is always a fresh INSERT,
	// not an UPDATE -- explicit shuttle_id (not auto-increment) so the row
	// always matches the key GLOB.drydock_ships already stores it under.
	// purchased_at is pulled back from the backup row (captured at the last
	// Retrieve) so the original purchase date survives the round trip
	// instead of resetting to "now" every stash cycle.
	if(!databaseCheckConnection("drydockStash"))
		log_drydock_error("drydockStash: database connection failed writing shuttle_id=[shuttle_id] -- ledger row now disagrees with live state until next save.")
	else
		var/purchased_at
		var/datum/db_query/pq = SSdbcore.NewQuery(
			"SELECT purchased_at FROM ss13_drydock_ships_backup WHERE shuttle_id = :id",
			list("id" = shuttle_id)
		)
		pq.Execute()
		if(databaseCheckQueryResult(pq, "drydockStash purchased_at lookup") && pq.NextRow())
			purchased_at = pq.item[1]
		qdel(pq)

		var/datum/db_query/iq = SSdbcore.NewQuery(
			{"INSERT INTO ss13_drydock_ships (shuttle_id, template_id, owner_ckey, faction_uid, stashed, stashed_at, purchased_at)
			VALUES (:id, :tid, :ckey, :faction, 1, NOW(), COALESCE(:purchased, NOW()))
			ON DUPLICATE KEY UPDATE stashed=1, stashed_at=NOW()"},
			list("id" = shuttle_id, "tid" = DS.template_id, "ckey" = DS.owner_ckey, "faction" = DS.faction_uid, "purchased" = purchased_at)
		)
		iq.Execute()
		if(!databaseCheckQueryResult(iq, "drydockStash insert"))
			log_drydock_error("drydockStash: DB write failed for shuttle_id=[shuttle_id].")
		qdel(iq)

	if(user)
		to_chat(user, SPAN_GOOD("Ship stashed."))
	log_drydock("drydockStash: shuttle_id=[shuttle_id] fully stashed and torn down (acting=[acting]).")
	return TRUE

// ============================================================
// SHUTDOWN SAFETY NET  called from SSpersistence.Shutdown()/forceSaveAll()
// ============================================================

/// Force-stashes every deployed drydock ship at shutdown, mirroring
/// corvetteAutoStashAll() exactly.
/datum/controller/subsystem/persistence/proc/drydockAutoStashAll()
	PRIVATE_PROC(TRUE)
	var/list/deployed = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(DS && !DS.stashed)
			deployed += sid
	log_drydock("drydockAutoStashAll: sweep starting -- [deployed.len] deployed drydock ship(s) found.")

	var/stashed_count = 0
	var/skipped_count = 0
	for(var/sid in deployed)
		if(drydockStash(sid, null, force = TRUE))
			stashed_count++
		else
			skipped_count++
			log_drydock_warning("drydockAutoStashAll: drydockStash() refused for shuttle_id=[sid] -- see preceding warning for reason.")

	log_drydock("drydockAutoStashAll: sweep complete -- [stashed_count] stashed, [skipped_count] skipped.")

// ============================================================
// ADMIN VERBS
// ============================================================

/// On-demand recall/stash tool for both drydock ships and faction
/// corvettes -- covers the gap the automatic shutdown sweeps
/// (drydockAutoStashAll()/corvetteAutoStashAll()) don't: forcing a specific
/// ship home right now, not just at server shutdown.
/datum/admins/proc/force_stash_ship()
	set name = "Force Stash Ship"
	set category = "Persistence"
	if(!check_rights(R_ADMIN))
		return

	var/list/options = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(DS && !DS.stashed)
			options["[DS.template_id] #[sid] (drydock ship, [DS.faction_uid ? "faction [DS.faction_uid]" : "owner [DS.owner_ckey]"])"] = list("type" = "shuttle", "id" = sid)
	for(var/cid in GLOB.faction_corvettes)
		var/datum/faction_corvette/C = GLOB.faction_corvettes[cid]
		if(C && !C.stashed)
			options["[C.template_id] #[cid] (corvette, faction [C.faction_uid])"] = list("type" = "corvette", "id" = cid)

	if(!length(options))
		to_chat(usr, SPAN_WARNING("No deployed drydock ships or corvettes found."))
		return

	var/pick = tgui_input_list(usr, "Force-stash which ship?", "Force Stash Ship", options)
	if(!pick)
		return
	var/list/target = options[pick]

	if(target["type"] == "shuttle")
		SSpersistence.drydockStash(target["id"], usr, force = TRUE)
	else
		SSpersistence.corvetteStash(target["id"], usr, force = TRUE)

/// Combined recovery tool for both drydock ships and faction corvettes --
/// restores a backup row (made by drydockRetrieve()/corvetteRetrieve()
/// right before a deployment) back into the main table as a stashed row,
/// for when a deployment is lost before the next successful Stash. One
/// picker across both systems, same shape as Force Stash Ship.
/datum/admins/proc/restore_ship_backup()
	set name = "Restore Ship Backup"
	set category = "Persistence"
	if(!check_rights(R_ADMIN))
		return

	if(!SSpersistence.databaseCheckConnection("restore_ship_backup"))
		to_chat(usr, SPAN_WARNING("Database connection failed."))
		return

	var/list/options = list()

	var/datum/db_query/sq = SSdbcore.NewQuery(
		"SELECT shuttle_id, template_id, owner_ckey, faction_uid, backed_up_at FROM ss13_drydock_ships_backup",
		list()
	)
	sq.Execute()
	if(SSpersistence.databaseCheckQueryResult(sq, "restore_ship_backup shuttle select"))
		while(sq.NextRow())
			options["[sq.item[2]] #[sq.item[1]] (drydock ship, [sq.item[4] ? "faction [sq.item[4]]" : "owner [sq.item[3]]"], backed up [sq.item[5]])"] = list("type" = "shuttle", "id" = text2num(sq.item[1]))
	qdel(sq)

	var/datum/db_query/cq = SSdbcore.NewQuery(
		"SELECT corvette_id, template_id, faction_uid, backed_up_at FROM ss13_faction_corvettes_backup",
		list()
	)
	cq.Execute()
	if(SSpersistence.databaseCheckQueryResult(cq, "restore_ship_backup corvette select"))
		while(cq.NextRow())
			options["[cq.item[2]] #[cq.item[1]] (corvette, faction [cq.item[3]], backed up [cq.item[4]])"] = list("type" = "corvette", "id" = text2num(cq.item[1]))
	qdel(cq)

	if(!length(options))
		to_chat(usr, SPAN_NOTICE("No ship backups found."))
		return

	var/pick = tgui_input_list(usr, "Restore which ship from backup?", "Restore Ship Backup", options)
	if(!pick)
		return
	var/list/target = options[pick]

	if(target["type"] == "shuttle")
		_restore_drydock_shuttle_from_backup(target["id"], usr)
	else
		_restore_corvette_from_backup(target["id"], usr)

/datum/admins/proc/_restore_drydock_shuttle_from_backup(shuttle_id, mob/user)
	var/datum/drydock_ship/existing = GLOB.drydock_ships[shuttle_id]
	if(existing && !existing.stashed)
		to_chat(user, SPAN_WARNING("Drydock ship #[shuttle_id] is already live -- nothing to restore."))
		return

	var/datum/db_query/bq = SSdbcore.NewQuery(
		"SELECT template_id, owner_ckey, faction_uid, purchased_at FROM ss13_drydock_ships_backup WHERE shuttle_id = :id",
		list("id" = shuttle_id)
	)
	bq.Execute()
	if(!SSpersistence.databaseCheckQueryResult(bq, "restore_ship_backup shuttle select") || !bq.NextRow())
		to_chat(user, SPAN_WARNING("No backup found for drydock ship #[shuttle_id]."))
		qdel(bq)
		return
	var/template_id = bq.item[1]
	var/owner_ckey = bq.item[2]
	var/faction_uid = bq.item[3]
	var/purchased_at = bq.item[4]
	qdel(bq)

	var/datum/db_query/iq = SSdbcore.NewQuery(
		"INSERT INTO ss13_drydock_ships (shuttle_id, template_id, owner_ckey, faction_uid, stashed, stashed_at, purchased_at) VALUES (:id, :tid, :ckey, :faction, 1, NOW(), :purchased) ON DUPLICATE KEY UPDATE stashed=1, stashed_at=NOW()",
		list("id" = shuttle_id, "tid" = template_id, "ckey" = owner_ckey, "faction" = faction_uid, "purchased" = purchased_at)
	)
	iq.Execute()
	if(!SSpersistence.databaseCheckQueryResult(iq, "restore_ship_backup shuttle insert"))
		to_chat(user, SPAN_WARNING("Restore failed -- see server log."))
		qdel(iq)
		return
	qdel(iq)

	if(existing)
		existing.stashed = TRUE
		existing.z = null
		existing.overmap_x = null
		existing.overmap_y = null
	else
		var/datum/drydock_ship/DS = new()
		DS.shuttle_id  = shuttle_id
		DS.template_id = template_id
		DS.owner_ckey  = owner_ckey
		DS.faction_uid = faction_uid
		DS.stashed     = TRUE
		GLOB.drydock_ships[shuttle_id] = DS

	to_chat(user, SPAN_GOOD("Drydock ship #[shuttle_id] ('[template_id]') restored from backup -- stashed, retrievable from the Drydock program."))
	log_admin("[key_name(user)] restored drydock ship #[shuttle_id] from backup.")
	log_drydock("restore_ship_backup: [key_name(user)] restored shuttle_id=[shuttle_id] from backup.")

/datum/admins/proc/_restore_corvette_from_backup(corvette_id, mob/user)
	var/datum/faction_corvette/existing = GLOB.faction_corvettes[corvette_id]
	if(existing && !existing.stashed)
		to_chat(user, SPAN_WARNING("Corvette #[corvette_id] is already live -- nothing to restore."))
		return

	var/datum/db_query/bq = SSdbcore.NewQuery(
		"SELECT template_id, faction_uid, purchased_at FROM ss13_faction_corvettes_backup WHERE corvette_id = :id",
		list("id" = corvette_id)
	)
	bq.Execute()
	if(!SSpersistence.databaseCheckQueryResult(bq, "restore_ship_backup corvette select") || !bq.NextRow())
		to_chat(user, SPAN_WARNING("No backup found for corvette #[corvette_id]."))
		qdel(bq)
		return
	var/template_id = bq.item[1]
	var/faction_uid = bq.item[2]
	var/purchased_at = bq.item[3]
	qdel(bq)

	var/datum/db_query/iq = SSdbcore.NewQuery(
		"INSERT INTO ss13_faction_corvettes (corvette_id, template_id, faction_uid, stashed, stashed_at, purchased_at) VALUES (:id, :tid, :faction, 1, NOW(), :purchased) ON DUPLICATE KEY UPDATE stashed=1, stashed_at=NOW()",
		list("id" = corvette_id, "tid" = template_id, "faction" = faction_uid, "purchased" = purchased_at)
	)
	iq.Execute()
	if(!SSpersistence.databaseCheckQueryResult(iq, "restore_ship_backup corvette insert"))
		to_chat(user, SPAN_WARNING("Restore failed -- see server log."))
		qdel(iq)
		return
	qdel(iq)

	if(existing)
		existing.stashed = TRUE
		existing.z = null
		existing.overmap_x = null
		existing.overmap_y = null
	else
		var/datum/faction_corvette/C = new()
		C.corvette_id = corvette_id
		C.template_id = template_id
		C.faction_uid = faction_uid
		C.stashed = TRUE
		GLOB.faction_corvettes[corvette_id] = C

	to_chat(user, SPAN_GOOD("Corvette #[corvette_id] ('[template_id]') restored from backup -- stashed, retrievable from the Faction Ship program."))
	log_admin("[key_name(user)] restored faction corvette #[corvette_id] from backup.")
	log_corvette("restore_ship_backup: [key_name(user)] restored corvette_id=[corvette_id] from backup.")
