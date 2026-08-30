/*
 * Persistence -- Drydock Ship Ledger
 *
 * The single unified system for player-owned ships, personal or faction --
 * the old faction-corvette engine was retired and merged in here. A ship
 * lives as a persistent ledger row (ss13_drydock_ships, stashed flag) plus,
 * while deployed, a materialized Z with an overmap marker. Buy is a pure DB
 * insert (see drydockBuy()); Retrieve/Stash toggle the stashed flag and
 * materialize/tear down the world footprint (see drydockRetrieve()/
 * drydockStash()). Ownership can be personal (owner_ckey) or faction
 * (faction_uid).
 *
 * Retrieve/Stash are sector-relative rather than anchored to any physical
 * navigation destination. A personal ship retrieves/stashes into whatever
 * sector its owner's current computer is in, provided any faction's
 * med-sec-or-better faction_beacon is nearby (not necessarily their own --
 * see _drydock_secured_beacon_nearby(), shared by both); a faction-owned
 * ship retrieves/stashes only near its OWN faction's faction_beacon (which
 * claims a whole Z) -- see shipPlaceOvermapMarker() and the
 * ownership-branching in drydockRetrieve()/drydockStash(). Both directions
 * also refuse during a recent-combat lockout
 * (in_recent_combat() on the user or the ship itself, see ship.dm) for stash,
 * and boarding itself now takes a 15-second interruptible spool-up
 * (_drydock_board_core(), telepad_drydock_boarding.dm) so a fight can't be
 * fled from instantly.
 *
 * Interiors PERSIST: everything aboard (turfs, machinery state, floor items,
 * tracked objects, bots, atmosphere) is captured on stash/shutdown under the
 * ship's own scope key ("ship:d:<shuttle_id>") and re-applied on retrieve --
 * see persistence_ship_interiors.dm. Stash releases the ship's Z into the
 * shared GLOB.reusable_z_pool for reuse by later retrieves (load_into_z()) --
 * away/mission sites draw from and return to the same pool -- so repeated
 * stash/retrieve cycles no longer permanently allocate new Z-levels.
 *
 * A ship can also be permanently Scuttled (drydockScuttle()) for a 25000cr
 * fee, from anywhere, deployed or stashed -- the self-service answer to a
 * ship that's stuck or unreachable, closing the gap that previously only an
 * admin's Force Stash Ship verb covered. Scuttle and an abnormally-destroyed
 * marker (see drydock_ship.dm's Destroy()) both route through the shared
 * _drydockMarkerTeardown() helper.
 *
 * Tables: ss13_drydock_ships, ss13_drydock_ships_backup, ss13_persistent_shuttles
 */

/// shuttle_id -> /datum/drydock_ship, for every purchased drydock ship (owned, stashed or deployed).
GLOBAL_LIST_EMPTY(drydock_ships)

// ============================================================
// CENTRAL SHIP SYNC (CENTRAL_SYNC_SHIPS)
// ============================================================
//
// Core ownership/existence fields only -- see V010__ship_sync.sql's own
// header for exactly what's covered vs. explicitly deferred (interiors,
// crew ACLs, schematic banking, deployment position). Write-through +
// (drydock-terminal-triggered) read-through-on-miss, same shape every
// other central sync this session uses, keyed by global_ship_id
// (V154__drydock_global_ship_id.sql) instead of the bare per-server
// shuttle_id, which has no cross-server meaning at all.
//
// No presence-lock-equivalent concern here the way faction treasury had:
// nothing on this table is a routinely-concurrently-mutated numeric
// balance -- ownership/name/repossession changes are each a deliberate,
// one-at-a-time action taken by whoever currently has the ship's
// schematic in hand or console access, not routine simultaneous
// multi-party activity. Plain last-write-wins upserts are the right fit,
// same reasoning as faction metadata.

/// Shared gate, same shape as every other _*CentralSyncActive() this
/// session.
/proc/_shipCentralSyncActive()
	if(!GLOB.config.central_sql_enabled || !GLOB.config.central_sync_ships)
		return FALSE
	return SSpersistence.centralDatabaseReachable()

/// Central write-through for core ss13_drydock_ships columns -- a plain
/// UPDATE (not upsert) for everything except the initial creation, which
/// goes through _shipCentralCreateWriteThrough() instead (an UPDATE has
/// nothing to apply against before the row exists). `columns`/`values` are
/// parallel lists.
/proc/_shipCentralPartialUpdate(global_ship_id, list/set_columns, list/set_values)
	if(!global_ship_id || !_shipCentralSyncActive())
		return
	var/list/set_clauses = list()
	var/list/params = list("gsid" = global_ship_id)
	for(var/i in 1 to length(set_columns))
		var/col = set_columns[i]
		set_clauses += "`[col]` = :[col]"
		params[col] = set_values[i]
	var/datum/db_query/q = SScentraldb.NewQuery(
		"UPDATE `ss13_drydock_ships` SET [jointext(set_clauses, ", ")] WHERE global_ship_id = :gsid",
		params
	)
	q.Execute()
	qdel(q)

/// Deletes a ship's central row -- called from drydockSell()/drydockScuttle(),
/// alongside their existing local DELETE, when a ship is permanently
/// destroyed/sold. Without this, a scuttled ship would stay
/// hydrate-able from another server that had never seen it yet.
/proc/_shipCentralDelete(global_ship_id)
	if(!global_ship_id || !_shipCentralSyncActive())
		return
	var/datum/db_query/q = SScentraldb.NewQuery(
		"DELETE FROM `ss13_drydock_ships` WHERE global_ship_id = :gsid",
		list("gsid" = global_ship_id)
	)
	q.Execute()
	qdel(q)

/// Writes a just-bought ship's full core row centrally -- called from
/// drydockBuy() once global_ship_id is known. Non-fatal on failure, same
/// reasoning as every other write-through this session.
/proc/_shipCentralCreateWriteThrough(datum/drydock_ship/DS)
	if(!DS.global_ship_id || !_shipCentralSyncActive())
		return
	var/datum/db_query/q = SScentraldb.NewQuery(
		{"INSERT INTO `ss13_drydock_ships`
		(global_ship_id, origin_server_id, template_id, owner_ckey, owner_char_name, owner_account_number, faction_uid,
		stashed, custom_name, custom_class, title_ckey, title_char_name, title_faction_uid, purchased_at)
		VALUES (:gsid, :origin, :tid, :ckey, :cname, :acct, :faction, :stashed, :custom_name, :custom_class, :t_ckey, :t_cname, :t_faction, :purchased)
		ON DUPLICATE KEY UPDATE template_id = VALUES(template_id)"},
		list(
			"gsid" = DS.global_ship_id, "origin" = GLOB.config.central_server_id, "tid" = DS.template_id,
			"ckey" = DS.owner_ckey, "cname" = DS.owner_char_name, "acct" = DS.owner_account_number, "faction" = DS.faction_uid,
			"stashed" = DS.stashed ? 1 : 0, "custom_name" = DS.custom_name, "custom_class" = DS.custom_class,
			"t_ckey" = DS.title_ckey, "t_cname" = DS.title_char_name, "t_faction" = DS.title_faction_uid,
			"purchased" = DS.purchased_at
		)
	)
	q.Execute()
	qdel(q)

/// Read-through-on-miss: SELECTs every ship centrally owned by
/// (ckey, char_name) that ISN'T already in GLOB.drydock_ships (this
/// server has never seen it), hydrating each into a live
/// /datum/drydock_ship AND self-healing it into this server's own local
/// ss13_drydock_ships table -- same pattern as every other central
/// read-through this session. Called from the drydock terminal's own
/// ship-listing (drydock.dm) right before it builds "your ships", so a
/// ship bought on another server just shows up here once its owner opens
/// a drydock terminal on this one.
/proc/_shipHydrateOwnedFromCentral(ckey, char_name)
	if(!ckey || !char_name || !_shipCentralSyncActive())
		return

	var/datum/db_query/q = SScentraldb.NewQuery(
		{"SELECT global_ship_id, template_id, owner_account_number, faction_uid, repossessed, prev_owner_ckey,
		prev_owner_char_name, prev_faction_uid, stashed, custom_name, custom_class, title_ckey, title_char_name,
		title_faction_uid, reported_stolen, purchased_at
		FROM `ss13_drydock_ships` WHERE owner_ckey = :ckey AND owner_char_name = :char_name"},
		list("ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()

	var/list/rows = list()
	while(q.NextRow())
		rows += list(q.item.Copy())
	qdel(q)

	for(var/list/row in rows)
		var/global_ship_id = row[1]
		var/already_known = FALSE
		for(var/sid in GLOB.drydock_ships)
			var/datum/drydock_ship/existing = GLOB.drydock_ships[sid]
			if(existing && existing.global_ship_id == global_ship_id)
				already_known = TRUE
				break
		if(already_known)
			continue

		if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
			return // can't allocate a local shuttle_id without a local DB

		var/datum/db_query/lins = SSdbcore.NewQuery(
			{"INSERT INTO ss13_drydock_ships
			(template_id, owner_ckey, owner_char_name, owner_account_number, faction_uid, repossessed, prev_owner_ckey,
			prev_owner_char_name, prev_faction_uid, stashed, custom_name, custom_class, title_ckey, title_char_name,
			title_faction_uid, reported_stolen, purchased_at, global_ship_id)
			VALUES (:tid, :ckey, :cname, :acct, :faction, :repo, :p_ckey, :p_cname, :p_faction, :stashed, :cust_name,
			:cust_class, :t_ckey, :t_cname, :t_faction, :stolen, :purchased, :gsid)"},
			list(
				"tid" = row[2], "ckey" = ckey, "cname" = char_name, "acct" = text2num(row[3]), "faction" = row[4],
				"repo" = text2num(row[5]), "p_ckey" = row[6], "p_cname" = row[7], "p_faction" = row[8],
				"stashed" = text2num(row[9]), "cust_name" = row[10], "cust_class" = row[11], "t_ckey" = row[12],
				"t_cname" = row[13], "t_faction" = row[14], "stolen" = text2num(row[15]), "purchased" = row[16],
				"gsid" = global_ship_id
			)
		)
		lins.Execute()
		var/new_local_id = text2num(lins.last_insert_id)
		qdel(lins)
		if(!new_local_id)
			continue

		var/datum/drydock_ship/DS = new()
		DS.shuttle_id = new_local_id
		DS.global_ship_id = global_ship_id
		DS.template_id = row[2]
		DS.owner_ckey = ckey
		DS.owner_char_name = char_name
		DS.owner_account_number = text2num(row[3])
		DS.faction_uid = row[4]
		DS.repossessed = !!text2num(row[5])
		DS.prev_owner_ckey = row[6]
		DS.prev_owner_char_name = row[7]
		DS.prev_faction_uid = row[8]
		DS.stashed = !!text2num(row[9])
		DS.custom_name = row[10]
		DS.custom_class = row[11]
		DS.title_ckey = row[12]
		DS.title_char_name = row[13]
		DS.title_faction_uid = row[14]
		DS.reported_stolen = !!text2num(row[15])
		DS.purchased_at = row[16]
		GLOB.drydock_ships["[new_local_id]"] = DS

/// TRUE once the periodic access re-sweep (below) has been armed -- lazily
/// started from the first drydock retrieve rather than wiring into
/// SSpersistence's own (30-minute-cadence, far too slow for this) Initialize().
GLOBAL_VAR_INIT(drydock_periodic_sweep_started, FALSE)

/// Arms a repeating sweep, on the same cadence as a faction beacon's own
/// periodic re-sweep (FACTION_BEACON_SWEEP_INTERVAL, faction_beacon.dm), that
/// re-runs the exact same unassigned-equipment sweep _drydockRetrieveRun()
/// already does once at retrieve time -- but for every currently-deployed
/// drydock ship, every cycle. This lets a ship that was deployed before a
/// template access fix (or one whose one-shot sweep otherwise missed
/// something) self-heal on its own, with no admin action or stash/retrieve
/// cycle needed. Safe to repeat: both sweep procs already skip anything
/// already assigned (`if(AL.req_access_faction || AL.crew_tagged) continue`),
/// so a manual re-tag via the faction tagger always still sticks afterward.
/proc/_drydock_start_periodic_sweep()
	if(GLOB.drydock_periodic_sweep_started)
		return
	GLOB.drydock_periodic_sweep_started = TRUE
	// Literal 30 SECONDS, not a shared define -- FACTION_BEACON_SWEEP_INTERVAL
	// (faction_beacon.dm) is compiled after this file in aurorastation.dme, so
	// it isn't visible here. Matches that interval by design; keep in sync if
	// it ever changes.
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_drydock_periodic_sweep)), 30 SECONDS, TIMER_LOOP)

/proc/_drydock_periodic_sweep()
	// Rebuilt from scratch every cycle (not incrementally added/removed) --
	// simplest correctness model, no stale-entry bookkeeping to get wrong.
	// See persistence_docked_turf_scope's doc comment
	// (persistence_ship_interiors.dm) for why this exists at all:
	// attempt_move()/shuttle_moved() (shuttle.dm) physically relocates a
	// docked ship's own turfs (and their area membership) onto wherever it's
	// actually docked, so the general per-z Finalize sweeps (persistence.dm)
	// can't tell those turfs apart from the surrounding station/host ship's
	// own content by z alone. This registry is what lets those sweeps
	// EXCLUDE a docked ship's turfs entirely (never write them under either
	// scope) rather than a docked ship ever having to move just because a
	// save is about to run -- its real, authoritative interior save always
	// happens via shipInteriorSave() once it's genuinely home again.
	GLOB.persistence_docked_turf_scope = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed || !DS.z)
			continue
		if(DS.faction_uid)
			_sweep_unassigned_objects_for_faction(list("[DS.z]"), DS.faction_uid)
		else
			_sweep_unassigned_crew(list("[DS.z]"))
		var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
		if(!istype(marker) || !marker.landmark)
			continue
		var/datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum = _drydock_shuttle_of(marker)
		// _drydock_ship_is_home(), NOT a comparison against marker.landmark. A
		// ship parked on its own z at a landmark that simply isn't the home one
		// (its own landmark_transition, most often) was being flagged as
		// "docked elsewhere" while sitting in its own open space -- which made
		// every save skip its turfs, and made its own shipInteriorSave() delete
		// its floor items and freeze its machines. Same definition of home the
		// stash gate, the schematic and the recall all use.
		if(istype(shuttle_datum) && !_drydock_ship_is_home(DS, shuttle_datum))
			var/turf_scope = "ship:d:[sid]"
			// Scoped to the hull's CURRENT z. shuttle_area for a player-built
			// hull is the shared singleton /area/drydock_ship/player_built_shuttle
			// (commission only renames it), so A.contents spans every deployed
			// player-built ship -- without this, one ship being away flags every
			// other player-built ship's turfs as excluded too.
			var/turf/hull_at = get_turf(shuttle_datum.current_location)
			var/hull_z = hull_at ? hull_at.z : 0
			if(hull_z)
				for(var/area/A in shuttle_datum.shuttle_area)
					for(var/turf/T in A.contents)
						if(T.z != hull_z)
							continue
						GLOB.persistence_docked_turf_scope[T] = turf_scope
		// Bound sub-craft (Xanu Fighter/Boarder, etc., sub_shuttle_tags) use
		// the exact same real attempt_move()/shuttle_moved() movement as any
		// other shuttle datum -- one can fly off its home slot and dock
		// somewhere entirely unrelated (another ship's hangar, a station
		// beacon) just like a full ship can, with the identical
		// foreign-Z misattribution exposure. logging_home_tag/current_location
		// comparison mirrors the exact check _drydockStashRun()'s own
		// sub-ship force-recall block already uses just below.
		var/datum/map_template/drydock_ship/sub_template = SSmapping.drydock_ship_templates[DS.template_id]
		if(sub_template && length(sub_template.sub_shuttle_tags))
			for(var/sub_tag in sub_template.sub_shuttle_tags)
				var/datum/shuttle/autodock/sub = SSshuttle.shuttles[_drydock_subship_key(DS.shuttle_id, sub_tag)]
				if(!istype(sub) || !istype(sub.current_location))
					continue
				if(sub.current_location.landmark_tag == sub.logging_home_tag)
					continue // already home
				var/sub_scope = "ship:d:[sid]:sub:[sub_tag]"
				for(var/area/A in sub.shuttle_area)
					for(var/turf/T in A.contents)
						GLOB.persistence_docked_turf_scope[T] = sub_scope

/// Admin-tunable, DB-persisted (ss13_drydock_config) cap on how many ships
/// can be deployed at once server-wide -- 0 = no limit. Loaded at boot by
/// _drydockLoadShipCap(), updated live by the "Set Drydock Ship Cap" admin
/// verb (set_drydock_ship_cap(), below).
GLOBAL_VAR_INIT(drydock_max_deployed_ships, 0)

/// TRUE while a retrieve or stash's heavy apply/teardown pipeline is
/// actively running -- see drydockRetrieve()/drydockStash()'s thin
/// queue-gate wrappers below. Serializes these server-wide so concurrent
/// heavy Z-loads from different players don't stack their tick cost on top
/// of each other.
GLOBAL_VAR_INIT(drydock_op_active, FALSE)

/// shuttle_id of whichever ship drydock_op_active is currently running for
/// (null while inactive). Lets _drydock_ship_busy() below tell the Drydock
/// program's ui_data() which specific row to grey Remove/Scuttle out for,
/// instead of disabling every ship's buttons just because some other ship
/// is mid-retrieve/stash somewhere else.
GLOBAL_VAR_INIT(drydock_op_active_shuttle_id, null)

/// Per-instance uniqueness suffix (e.g. "#42") applied to every shuttle datum
/// name and landable marker created during a drydock template load, so more
/// than one hull of the same class can be deployed at once.
///
/// Shuttle datum names and the home landmark tags derived from them
/// (/obj/effect/shuttle_landmark/ship/Initialize() builds "ship_[shuttle_name]")
/// are otherwise per-TEMPLATE: a second instance made /datum/shuttle/New()
/// hard-CRASH on the duplicate name, and made register_landmark() silently
/// skip the second ship's landmark so it believed it was parked where the
/// first one was. Naming has to be unique BEFORE the load builds any of that,
/// which is why this is a load-scoped global rather than the post-load rename
/// that drydockRetrieve() already does.
///
/// Set immediately before template.load_new_z()/load_into_z() and cleared
/// immediately after -- that whole call is synchronous through init_atoms()
/// and init_shuttles(), so the window never spans a yield.
GLOBAL_VAR_INIT(drydock_loading_suffix, null)

/// Area instances created for the drydock load currently in flight, keyed by
/// area type. Populated by the maploader (reader.dm) and consumed by
/// /datum/shuttle/New() (shuttle.dm); cleared with the suffix above.
///
/// BYOND areas are singletons keyed by type (GLOB.areas_by_type), so two hulls
/// of the same class would otherwise share one set of area objects -- and
/// everything area-scoped (ownership checks, APC/power, atmos alarms) would
/// treat both as a single ship. Giving each drydock load its own area
/// instances is what makes same-class deployment actually independent rather
/// than merely non-crashing. Safe to clone: /area/New() (areas.dm) only
/// records the FIRST instance of a type as canonical, so extra instances never
/// displace it.
GLOBAL_LIST_EMPTY(drydock_loading_areas)

/// Stable per-ship seed for pick_wall_icon_variant() (wall_icon.dm), read in
/// place of the literal z coordinate whenever it's non-null.
///
/// A reinforced wall's "weathered" look is a deterministic hash of x/y/z --
/// same wall, same z, forever the same variant, which is the whole point (it
/// stops walls flickering between look-alike sprites, and keeps two unrelated
/// rooms on two different Z-levels that happen to share x/y from always
/// looking identically weathered). That assumption breaks for a drydock ship:
/// its x/y are fixed but its z is NOT -- template.load_new_z()/
/// acquireReusableZ() hand it a different z on every commission and every
/// retrieve, by design (z-reuse pooling). Left alone, every reinforced wall on
/// the hull would re-roll a different-but-equally-valid variant each time,
/// which is exactly what a player would see as "the walls look different now"
/// with nothing actually damaged or lost.
///
/// Set to a stable hash of the ship's own shuttle_id (constant for the ship's
/// entire life, unlike its z) immediately before template.load_new_z() /
/// load_into_z() and kept set through the shipInteriorApply() call that
/// follows -- persistence_turfs.dm's own wall-restore re-pick
/// (turfsApplyContent()) needs the same stable seed, not just the template's
/// own Initialize() pass. Cleared back to null once both complete, same
/// window discipline as drydock_loading_suffix above (both calls are
/// synchronous, no yield in between). Null everywhere else, so every
/// non-ship wall (station, away sites) is completely unaffected.
GLOBAL_VAR_INIT(drydock_loading_wall_hash_seed, null)

/// Appends GLOB.drydock_loading_suffix to a name when a drydock load is in
/// flight, skipping names that already carry it (a retrieve of an already
/// suffixed hull, or the post-load rename running over the top).
/proc/drydock_apply_instance_suffix(base_name)
	if(!GLOB.drydock_loading_suffix || !base_name)
		return base_name
	if(findtext(base_name, GLOB.drydock_loading_suffix))
		return base_name
	return "[base_name] [GLOB.drydock_loading_suffix]"

/// Pending retrieve/stash requests that arrived while drydock_op_active was
/// TRUE, each an assoc list of the args needed to re-invoke the matching
/// public proc. Drained one at a time by _drydockProcessNextQueued().
GLOBAL_LIST_EMPTY(drydock_op_queue)

/// TRUE if shuttle_id is the ship drydock_op_active is currently running
/// for, or has a retrieve/stash queued behind it -- either way, its state is
/// about to change out from under a sell/scuttle, so both must refuse until
/// it settles. Checked both server-side (ui_act() "sell"/"scuttle") and
/// surfaced to the Drydock program's ui_data() so the TGUI can grey the
/// buttons out instead of just erroring after the fact.
/proc/_drydock_ship_busy(shuttle_id)
	if(GLOB.drydock_op_active && GLOB.drydock_op_active_shuttle_id == shuttle_id)
		return TRUE
	for(var/list/req in GLOB.drydock_op_queue)
		if(req["shuttle_id"] == shuttle_id)
			return TRUE
	return FALSE

/datum/drydock_ship
	var/shuttle_id
	/// Cross-server identity for CENTRAL_SYNC_SHIPS -- "[CENTRAL_SERVER_ID]:[shuttle_id]",
	/// set once at purchase (drydockBuy()) since shuttle_id alone is a bare
	/// per-server AUTO_INCREMENT with no cross-server meaning. Null for any
	/// ship bought before this existed (not backfilled) or on a server that's
	/// never had CENTRAL_SERVER_ID set.
	var/global_ship_id
	var/template_id
	var/owner_ckey
	/// Paired with owner_ckey -- ownership belongs to a CHARACTER (real_name),
	/// not the account, so a player's other characters under the same ckey
	/// don't inherit access to a ship one of their characters bought. Mirrors
	/// the existing (ckey, char_name) composite-identity convention
	/// ss13_mob_position already uses (persistence_mobs.dm). Null/unused for
	/// faction ownership -- faction_uid is never a character-identity concept.
	var/owner_char_name
	/// Captured once, at purchase (drydockBuy()), from the buyer's ID card --
	/// null for faction ships. Lets Crew-tagged equipment (persistence_faction_tagger.dm)
	/// bill the owner directly even when they're offline, since there's no
	/// reliable way to resolve an arbitrary (ckey, char_name)'s bank account
	/// otherwise. A stable account number, unlike a live mob/ID reference.
	var/owner_account_number
	var/faction_uid
	/// DB DATETIME string, set once at drydockBuy() time and never touched
	/// again -- used as a staleness guard by /obj/item/ship_schematic
	/// (ship_schematic.dm), since shuttle_id itself gets reused once a ship
	/// is scuttled/sold (V099__drydock_shuttle_id_reuse.sql). A schematic
	/// whose bound_purchased_at no longer matches this means its shuttle_id
	/// slot was freed and reassigned to an unrelated later ship.
	var/purchased_at
	/// TRUE once a valid /obj/item/ship_schematic for this ship has been
	/// deposited at a Drydock console/laptop (see ship_schematic.dm's
	/// resolve_attackby() and drydock.dm's "withdraw_schematic" ui_act) --
	/// the physical item is destroyed on deposit, and a fresh one can only
	/// be minted again by whoever satisfies the historical owner_ckey/
	/// owner_char_name/faction_uid check (repurposed as the recovery-path
	/// identity check now that day-to-day control is item-based).
	var/schematic_banked = FALSE
	/// DB DATETIME string, set each time drydockRename() successfully
	/// changes the main ship name/class -- get_drydock_rename_cooldown_remaining()
	/// reads the live DB column directly for the actual 30-day gate (real
	/// calendar time, survives reboots), this in-memory copy is just for
	/// display. Sub-ship renaming is untouched by this cooldown.
	var/renamed_at
	/// TRUE once the Hub has repossessed this ship (see drydockRepossess(),
	/// below) -- faction_uid is forced to "hub" and owner_ckey/owner_char_name
	/// are cleared while this is set, with the previous values snapshotted
	/// into the prev_* vars below so drydockReturnToOwner() can restore them.
	var/repossessed = FALSE
	var/prev_owner_ckey
	var/prev_owner_char_name
	var/prev_faction_uid
	var/stashed = TRUE
	/// FALSE from the moment drydockRetrieve() starts materializing a ship
	/// until its interior's deferred atmos settle finishes (~15s later,
	/// _shipInteriorApplyFinish(), persistence_ship_interiors.dm) -- boarding
	/// refuses while FALSE (_drydock_board_core(),
	/// telepad_drydock_boarding.dm) so nobody boards a ship that's still
	/// mid-load. Always TRUE while stashed.
	var/ready = TRUE
	/// Only meaningful while stashed == FALSE -- null whenever stashed.
	var/z
	var/overmap_x
	var/overmap_y
	/// Player-set display name/class, overriding the template's own defaults
	/// -- null means "use the template default". Applied to the overmap
	/// marker's name/class on every retrieve (drydockRetrieve()) and live if
	/// currently deployed (drydockRename()).
	var/custom_name
	var/custom_class
	/// Characters (not accounts) granted boarding access by the owner/an
	/// officer without being given ownership, faction membership, or any
	/// retrieve/stash/sell rights -- entries are "ckey|char_name" composite
	/// keys (same shape as GLOB.persistence_position_cache,
	/// persistence_mobs.dm) so being crew doesn't leak to a player's other
	/// characters. See drydockAddCrew()/drydockRemoveCrew() below and the
	/// crew-list OR clause in _drydock_board_core() (telepad_drydock_boarding.dm).
	var/list/crew_ckeys = list()
	/// Set ONCE at purchase (drydockBuy()) and never touched again by any
	/// other proc -- the permanent record of who legitimately bought this
	/// ship first. Distinct from owner_ckey/owner_char_name/faction_uid
	/// above, which are the CURRENT (mutable) owner: banking a schematic
	/// you're not titled to (drydockBankSchematic()) reassigns those to you,
	/// but never these. Only drydockGiveSchematic() (a deliberate,
	/// console-only "sign over the title" action) can move title_*.
	var/title_ckey
	var/title_char_name
	/// Null for a personally-titled ship -- never a character-identity
	/// concept, same as faction_uid above.
	var/title_faction_uid
	/// TRUE if this ship's schematic has been Stashed, Retrieved, or
	/// deposited by someone other than the title-holder (is_title_holder())
	/// since it last returned to their hands -- see _drydockFlagIfStolen()
	/// and drydockClearStolenFlag() below.
	var/reported_stolen = FALSE

/// Finds a live, valid /obj/item/ship_schematic (ship_schematic.dm) bound to
/// this ship anywhere in user's inventory -- held, worn, in a backpack, in a
/// pocket. Carrying it anywhere on your person is enough, same as an ID
/// card granting access from a wallet; only actually USING it (in an active
/// hand) additionally requires it be readily at hand. Returns the item if
/// found, null otherwise.
/datum/drydock_ship/proc/find_schematic_on(mob/user)
	if(!user)
		return null
	for(var/obj/item/ship_schematic/S in user.get_all_contents())
		if(S.resolve_ship() == src)
			return S
	return null

/// TRUE if user currently possesses a valid (non-repossessed, non-stale)
/// ship_schematic bound to this ship -- the sole ownership check for BOTH
/// personal and faction ships, day-to-day. owner_ckey/owner_char_name/
/// faction_uid (the CURRENT owner) are only consulted as the recovery-path
/// identity check for withdrawing a banked schematic back out of safekeeping
/// (drydock.dm's "withdraw_schematic") -- a lost/destroyed schematic has no
/// other way back short of an admin's intervention or is_title_holder()
/// below. See title_ckey/title_char_name/title_faction_uid's doc comment for
/// how title (permanent) differs from ownership (mutable, possession-driven).
/datum/drydock_ship/proc/owned_by(mob/user)
	return !!find_schematic_on(user)

/// TRUE if user is this ship's permanent title-holder -- the original buyer
/// (character identity) for a personally-titled ship, or ANY current member
/// of title_faction_uid (plain membership, no rank requirement) for a
/// faction-titled one. Purely a provenance/theft-detection concept, NOT a
/// standing recovery right: used to decide whether Stash/Retrieve/Deposit
/// should flag reported_stolen (_drydockFlagIfStolen()) and whether
/// examining/opening the schematic should clear an existing stolen flag.
/// Deliberately NOT consulted for withdrawing or giving away a banked
/// schematic -- those check the CURRENT owner identity instead (drydock.dm),
/// so a thief who successfully banks a stolen ship keeps full control of it.
/datum/drydock_ship/proc/is_title_holder(mob/user)
	if(!user)
		return FALSE
	if(title_faction_uid)
		var/obj/item/card/id/ID = user.GetIdCard()
		var/user_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
		return user_faction == title_faction_uid
	return title_ckey && user.ckey == title_ckey && user.real_name == title_char_name

/// Who may sign this ship's title over to someone else.
///
/// Deliberately stricter than is_title_holder() for FACTION-titled ships:
/// that check is plain membership, which is right for "is this your ship"
/// questions (stolen-flag clearing, examining) but would let any rank-0
/// civilian member give away faction property. Signing over a faction ship
/// requires officer (rank 1) or command (rank 2) --
/// can_configure_faction_shackle()'s standard "officer or better" idiom, which
/// also covers a faction master card holder.
///
/// Personally-titled ships are unchanged: only their own title holder.
/// Admins always.
/datum/drydock_ship/proc/can_transfer_title(mob/user)
	if(check_rights(R_ADMIN, 0, user))
		return TRUE
	if(!user)
		return FALSE
	if(title_faction_uid)
		return can_configure_faction_shackle(user, title_faction_uid, 1)
	return is_title_holder(user)

/// Shown everywhere a ship's own name appears (overmap marker, admin logs,
/// chat messages, the Drydock program's own list, the schematic item's own
/// name) -- custom_name if set, else the template's own default name, with
/// " (FactionName)" appended for a faction-owned ship (never for personal),
/// then " (Stolen)" appended last while reported_stolen is set. The stolen
/// tag is purely computed here, at display time -- it's never stored as part
/// of custom_name, so there is no rename input that can strip it; renaming
/// only ever changes what "base" is, not whether the tag gets appended on
/// top of it. See _drydockRefreshDisplayedName() for keeping cached copies
/// of this (the overmap marker, the schematic's own .name) in sync whenever
/// something -- a rename, or reported_stolen flipping -- changes what this
/// proc would now return.
/datum/drydock_ship/proc/display_name()
	var/base = custom_name
	if(!base)
		var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[template_id]
		base = template ? initial(template.name) : template_id
	if(faction_uid)
		base = "[base] ([get_faction_name(faction_uid)])"
	if(reported_stolen)
		base = "[base] (Stolen)"
	return base

/// Refreshes every live, cached copy of this ship's display_name() -- the
/// overmap marker (if currently deployed) and any live, valid schematic
/// bound to it anywhere in the world -- after something changes what
/// display_name() computes (a rename, or reported_stolen flipping).
/// Otherwise either would keep showing a stale name until an unrelated event
/// (the next rename, a mint/withdraw/repossess) happened to touch it.
/datum/controller/subsystem/persistence/proc/_drydockRefreshDisplayedName(datum/drydock_ship/DS)
	if(!DS.stashed)
		var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
		if(istype(marker))
			marker.name = DS.display_name()
			marker.class = DS.custom_class
		// The z-level's own label, too -- otherwise it keeps the TEMPLATE name
		// ("Player-Built Shuttle"), or for a rehomed ship the suffixed internal
		// name frozen at the moment it was rehomed.
		persistence_set_zlevel_label(DS.z, DS.display_name())
	for(var/obj/item/ship_schematic/S in world)
		if(S.shuttle_id == DS.shuttle_id && S.bound_purchased_at == DS.purchased_at && !S.repossessed)
			S.refresh_name()

/// TRUE if sector is within 1 tile of the CentCom/Frontier Beacon Depot
/// marker's own fixed position (code/modules/overmap/centcom_overmap.dm).
/// CentCom is a neutral administrative depot, not owned by any faction and
/// with no player-buildable faction beacon of its own -- proximity to it
/// alone counts as valid drydock range for both retrieve and stash, personal
/// or faction-owned, same as being within 1 tile of a real secured beacon.
/proc/_drydock_near_centcom_depot(obj/effect/overmap/visitable/sector)
	if(!istype(sector))
		return FALSE
	// Resolved via its own registered sector rather than the type path
	// directly -- centcom_overmap.dm compiles after this file in
	// aurorastation.dme, so /obj/.../sector/centcom isn't a known type here.
	if(!length(SSatlas.current_map.admin_levels))
		return FALSE
	var/obj/effect/overmap/visitable/depot = GLOB.map_sectors["[SSatlas.current_map.admin_levels[1]]"]
	if(!istype(depot))
		return FALSE
	return max(abs(sector.x - depot.x), abs(sector.y - depot.y)) <= 1

/// TRUE if a beacon satisfying the ownership rule sits at or adjacent to
/// (get_dist <= 1) sector: for a faction_uid, that faction's own beacon
/// specifically; for null (personal), any active med-sec-or-better beacon
/// regardless of whose it is. Shared by drydockRetrieve()'s personal-ship
/// path and drydockStash(), so "secured territory" means the same thing in
/// both places. Also always TRUE near the CentCom depot (see
/// _drydock_near_centcom_depot()), regardless of faction_uid.
/proc/_drydock_secured_beacon_nearby(obj/effect/overmap/visitable/sector, faction_uid)
	if(!istype(sector))
		return FALSE
	if(_drydock_near_centcom_depot(sector))
		return TRUE
	for(var/bz in GLOB.faction_beacon_by_z)
		var/obj/structure/machinery/faction_beacon/B = GLOB.faction_beacon_by_z[bz]
		if(!B)
			continue
		if(faction_uid ? (B.faction_uid != faction_uid) : (zone_security_get(GET_Z(B)) < ZONE_MEDSEC))
			continue
		var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
		if(istype(beacon_sector) && get_dist(sector, beacon_sector) <= 1)
			return TRUE
	return FALSE

/// The overmap sector marker representing where DS's content is GENUINELY,
/// physically located right now -- NOT necessarily DS's own marker object
/// directly. A ship's own marker (GLOB.map_sectors["[DS.z]"]) gets
/// forceMove()'d into the target sector's own marker's .contents (nested,
/// non-turf .loc) while SHIP_STATUS_LANDED (on_landing(), landable.dm --
/// pre-existing, unconditional for every landable ship docking anywhere,
/// see on_takeoff()'s own forceMove(get_turf(loc)) extraction right before
/// flight logic can resume) -- get_dist() against a nested marker does not
/// reliably reflect where the ship actually is. Any proximity check against
/// a specific ship (not a sector in general) should resolve position through
/// this proc instead of reading GLOB.map_sectors["[DS.z]"] directly.
///
/// When landed/docked, resolves via shuttle_datum.current_location instead
/// -- a real landmark anchored to a real turf, set unconditionally and
/// correctly by shuttle_moved() (shuttle.dm:251), the same "single source of
/// truth" _drydockStashRun()'s own away-from-home stash gate already trusts
/// -- and returns the sector that turf's own z actually belongs to. When not
/// docked (SHIP_STATUS_OVERMAP), the marker already sits on a normal
/// overmap turf, so it's returned directly, unchanged from today's behavior.
/proc/_drydock_ship_sector(datum/drydock_ship/DS)
	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
	if(!istype(marker))
		return null
	if(marker.status != SHIP_STATUS_LANDED)
		return marker
	var/datum/shuttle/shuttle_datum = _drydock_shuttle_of(marker)
	if(!istype(shuttle_datum) || !shuttle_datum.current_location)
		return marker
	var/turf/T = get_turf(shuttle_datum.current_location)
	if(!T)
		return marker
	return GLOB.map_sectors["[T.z]"]

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
	log_world("shuttleStateRestore: [restored] position(s) restored, [skipped] skipped.")

	// Step 3: restore the drydock ship ownership ledger (below).
	drydockShipLedgerRestore()

// ============================================================
// BOOT LOADER  called from shuttleStateRestore() above
// ============================================================

/// Restores the drydock ship ownership ledger. The row for a deployed ship
/// persists (stashed=0) rather than being deleted -- a graceful shutdown's
/// auto-stash sweep flips it to stashed=1 before this ever runs, so finding
/// a stashed=0 row here means that sweep didn't happen (a crash, or a hard
/// kill) -- the sanctioned recovery path: force it back to stashed now, on
/// the assumption its interior was captured by the last successful autosave
/// (see persistence_ship_interiors.dm, no longer excluded from the ordinary
/// per-Z Finalize sweeps while deployed).
/proc/drydockShipLedgerRestore()
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		log_drydock_warning("drydockShipLedgerRestore: SQL disabled or connection failed, nothing restored.")
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT shuttle_id, template_id, owner_ckey, owner_char_name, faction_uid, stashed, z, overmap_x, overmap_y, custom_name, custom_class, repossessed, prev_owner_ckey, prev_owner_char_name, prev_faction_uid, owner_account_number, purchased_at, schematic_banked, renamed_at, title_ckey, title_char_name, title_faction_uid, reported_stolen, global_ship_id FROM ss13_drydock_ships",
		list()
	)
	q.Execute()
	var/restored = 0
	var/reset_stale = 0
	var/list/stale_ids = list()
	while(q.NextRow())
		var/datum/drydock_ship/DS = new()
		DS.shuttle_id  = text2num(q.item[1])
		DS.template_id = q.item[2]
		DS.owner_ckey  = q.item[3]
		DS.owner_char_name = q.item[4]
		DS.faction_uid = q.item[5]
		DS.stashed     = !!text2num(q.item[6])
		DS.z           = text2num(q.item[7])
		DS.overmap_x   = text2num(q.item[8])
		DS.overmap_y   = text2num(q.item[9])
		DS.custom_name = q.item[10]
		DS.custom_class = q.item[11]
		DS.repossessed = !!text2num(q.item[12])
		DS.prev_owner_ckey = q.item[13]
		DS.prev_owner_char_name = q.item[14]
		DS.prev_faction_uid = q.item[15]
		DS.owner_account_number = text2num(q.item[16])
		DS.purchased_at = q.item[17]
		DS.schematic_banked = !!text2num(q.item[18])
		DS.renamed_at = q.item[19]
		DS.title_ckey = q.item[20]
		DS.title_char_name = q.item[21]
		DS.title_faction_uid = q.item[22]
		DS.reported_stolen = !!text2num(q.item[23])
		DS.global_ship_id = q.item[24]

		if(!DS.stashed)
			log_drydock("drydockShipLedgerRestore: shuttle_id=[DS.shuttle_id] ('[DS.template_id]') was still stashed=0 at boot -- graceful shutdown's auto-stash sweep didn't run (crash/hard kill). Forcing back to stashed; interior recovers from the last autosave.")
			DS.stashed   = TRUE
			DS.z         = null
			DS.overmap_x = null
			DS.overmap_y = null
			reset_stale++
			stale_ids += DS.shuttle_id

		GLOB.drydock_ships["[DS.shuttle_id]"] = DS
		restored++
	qdel(q)

	// Persist the stashed/z correction back to the DB -- without this, the
	// in-memory recovery above never reaches ss13_drydock_ships, so the
	// Drydock program's ui_data() (a separate, direct SELECT) keeps showing
	// "Deployed" forever, drydockStash() refuses with "already stashed"
	// (checking the now-corrected in-memory datum), and every future boot
	// re-logs the same "recovering from unclean shutdown" message for a
	// ship already recovered last time. One batched pass after the loop
	// (not nested inside q's own NextRow() iteration), mirroring the crew
	// pass below.
	if(length(stale_ids))
		var/datum/db_query/rq = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET stashed=1, z=NULL, overmap_x=NULL, overmap_y=NULL, stashed_at=NOW() WHERE shuttle_id IN ([stale_ids.Join(",")])",
			list()
		)
		rq.Execute()
		if(!SSpersistence.databaseCheckQueryResult(rq, "drydockShipLedgerRestore stale recovery"))
			log_drydock_error("drydockShipLedgerRestore: failed to persist stashed-recovery for shuttle_id(s) [stale_ids.Join(", ")] -- in-memory state corrected but DB still shows stashed=0.")
		qdel(rq)

	// Crew lists load in one pass after every ledger datum exists, rather
	// than per-row inside the loop above, so a crew row can never race
	// ahead of its owning ship's datum being created.
	var/crew_loaded = 0
	var/datum/db_query/cq = SSdbcore.NewQuery("SELECT shuttle_id, ckey, char_name FROM ss13_ship_crew", list())
	cq.Execute()
	if(SSpersistence.databaseCheckQueryResult(cq, "drydockShipLedgerRestore crew"))
		while(cq.NextRow())
			var/datum/drydock_ship/DS = GLOB.drydock_ships[cq.item[1]]
			if(istype(DS))
				DS.crew_ckeys |= "[cq.item[2]]|[cq.item[3]]"
				crew_loaded++
	qdel(cq)

	log_drydock("drydockShipLedgerRestore: [restored] drydock ship(s) restored[reset_stale ? ", [reset_stale] recovered from an unclean shutdown" : ""], [crew_loaded] crew entr[crew_loaded == 1 ? "y" : "ies"] loaded.")

	_drydockLoadShipCap()

/// Loads the admin-tunable deployed-ship cap from its singleton DB row into
/// GLOB.drydock_max_deployed_ships (0 = no limit). Called once at boot
/// alongside drydockShipLedgerRestore(); set_drydock_ship_cap() (admin verb,
/// below) updates both the GLOB and the DB row live afterward.
/proc/_drydockLoadShipCap()
	GLOB.drydock_max_deployed_ships = 0
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return
	var/datum/db_query/q = SSdbcore.NewQuery("SELECT max_deployed_ships FROM ss13_drydock_config WHERE id = 1", list())
	q.Execute()
	if(SSpersistence.databaseCheckQueryResult(q, "_drydockLoadShipCap") && q.NextRow())
		GLOB.drydock_max_deployed_ships = text2num(q.item[1])
	qdel(q)
	log_drydock("_drydockLoadShipCap: deployed-ship cap loaded as [GLOB.drydock_max_deployed_ships] (0 = no limit).")

// ============================================================
// CREW  boarding access without ownership/faction membership
// ============================================================

/// Grants target_ckey's target_char_name CHARACTER boarding access to
/// shuttle_id without ownership, faction membership, or any retrieve/stash/
/// sell rights -- scoped to one specific character, not the whole account,
/// same reasoning as owned_by() above. Same permission shape as
/// retrieve/stash: admin, the owner, or an officer of the owning faction.
/datum/controller/subsystem/persistence/proc/drydockAddCrew(shuttle_id, target_ckey, target_char_name, label, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS)
		log_drydock_warning("drydockAddCrew: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to manage this ship's crew."))
		log_drydock_warning("drydockAddCrew: refused -- [acting] lacks permission for shuttle_id=[shuttle_id].")
		return FALSE
	target_ckey = ckey(target_ckey)
	if(!target_ckey || !target_char_name)
		if(user)
			to_chat(user, SPAN_WARNING("A ckey and a character name are both required."))
		return FALSE

	if(!databaseCheckConnection("drydockAddCrew"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_ship_crew (shuttle_id, ckey, char_name, label, added_by, added_at)
		VALUES (:id, :ckey, :char_name, :label, :by, NOW())
		ON DUPLICATE KEY UPDATE label = VALUES(label)"},
		list("id" = shuttle_id, "ckey" = target_ckey, "char_name" = target_char_name, "label" = (label != "" ? label : null), "by" = acting)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockAddCrew insert"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- crew not added."))
		return FALSE
	qdel(q)

	DS.crew_ckeys |= "[target_ckey]|[target_char_name]"
	if(user)
		to_chat(user, SPAN_GOOD("Added '[target_char_name]' ([target_ckey]) to the crew list."))
	log_drydock("drydockAddCrew: [acting] added '[target_char_name]' ([target_ckey]) to shuttle_id=[shuttle_id]'s crew.")
	return TRUE

/datum/controller/subsystem/persistence/proc/drydockRemoveCrew(shuttle_id, target_ckey, target_char_name, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS)
		log_drydock_warning("drydockRemoveCrew: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to manage this ship's crew."))
		log_drydock_warning("drydockRemoveCrew: refused -- [acting] lacks permission for shuttle_id=[shuttle_id].")
		return FALSE
	target_ckey = ckey(target_ckey)

	if(!databaseCheckConnection("drydockRemoveCrew"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_ship_crew WHERE shuttle_id = :id AND ckey = :ckey AND char_name = :char_name",
		list("id" = shuttle_id, "ckey" = target_ckey, "char_name" = target_char_name)
	)
	q.Execute()
	databaseCheckQueryResult(q, "drydockRemoveCrew delete")
	qdel(q)

	DS.crew_ckeys -= "[target_ckey]|[target_char_name]"
	if(user)
		to_chat(user, SPAN_GOOD("Removed '[target_char_name]' ([target_ckey]) from the crew list."))
	log_drydock("drydockRemoveCrew: [acting] removed '[target_char_name]' ([target_ckey]) from shuttle_id=[shuttle_id]'s crew.")
	return TRUE

// ============================================================
// IDENTITY  per-instance display name/class, distinct from the template
// ============================================================

/// Sets a ship's custom display name/class (either may be left null to
/// clear back to the template default). Same permission shape as
/// crew management. If the ship is currently deployed, applies live to the
/// overmap marker immediately (same "always reflects the current value"
/// pattern set_faction_color() uses) -- otherwise takes effect at the next
/// retrieve.
/// Seconds remaining before a ship's main name/class can next be changed by
/// a non-admin (see drydockRename()'s own re-check), 0 if clear/never-set.
/// Live DB read (real calendar time, not world.time -- must survive
/// reboots), same TIMESTAMPDIFF/NOW() shape already shipped for the faction
/// cargo-category cooldown (get_faction_cargo_category_cooldown_remaining(),
/// persistence_factions.dm) and imprisonment expiry before that
/// (persistence_mobs.dm). Sub-ship renaming is untouched by this cooldown.
/proc/get_drydock_rename_cooldown_remaining(shuttle_id)
	if(!SSpersistence.databaseCheckConnection("get_drydock_rename_cooldown_remaining"))
		return 0
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT TIMESTAMPDIFF(SECOND, NOW(), DATE_ADD(renamed_at, INTERVAL 30 DAY)) FROM ss13_drydock_ships WHERE shuttle_id = :id AND renamed_at IS NOT NULL",
		list("id" = shuttle_id)
	)
	q.Execute()
	. = 0
	if(SSpersistence.databaseCheckQueryResult(q, "get_drydock_rename_cooldown_remaining") && q.NextRow())
		. = max(0, text2num(q.item[1]) || 0)
	qdel(q)

/datum/controller/subsystem/persistence/proc/drydockRename(shuttle_id, new_name, new_class, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS)
		log_drydock_warning("drydockRename: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to rename this ship."))
		log_drydock_warning("drydockRename: refused -- [acting] lacks permission for shuttle_id=[shuttle_id].")
		return FALSE
	if(!check_rights(R_ADMIN, 0, user))
		var/cooldown_remaining = get_drydock_rename_cooldown_remaining(shuttle_id)
		if(cooldown_remaining > 0)
			if(user)
				to_chat(user, SPAN_WARNING("This ship was renamed too recently -- try again in [round(cooldown_remaining / 86400)] day\s."))
			log_drydock_warning("drydockRename: refused -- [acting] hit the rename cooldown for shuttle_id=[shuttle_id] ([cooldown_remaining]s remaining).")
			return FALSE

	if(!databaseCheckConnection("drydockRename"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_drydock_ships SET custom_name = :name, custom_class = :class, renamed_at = NOW() WHERE shuttle_id = :id",
		list("name" = (new_name != "" ? new_name : null), "class" = (new_class != "" ? new_class : null), "id" = shuttle_id)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockRename update"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- rename not saved."))
		return FALSE
	qdel(q)

	DS.custom_name = (new_name != "" ? new_name : null)
	DS.custom_class = (new_class != "" ? new_class : null)
	_shipCentralPartialUpdate(DS.global_ship_id, list("custom_name", "custom_class"), list(DS.custom_name, DS.custom_class))

	var/datum/db_query/rq = SSdbcore.NewQuery("SELECT renamed_at FROM ss13_drydock_ships WHERE shuttle_id = :id", list("id" = shuttle_id))
	rq.Execute()
	if(databaseCheckQueryResult(rq, "drydockRename renamed_at read-back") && rq.NextRow())
		DS.renamed_at = rq.item[1]
	qdel(rq)

	_drydockRefreshDisplayedName(DS)

	if(user)
		to_chat(user, SPAN_GOOD("Ship identity updated."))
	log_drydock("drydockRename: [acting] renamed shuttle_id=[shuttle_id] to name='[DS.custom_name]', class='[DS.custom_class]'.")
	log_and_message_admins("renamed drydock ship #[shuttle_id] to '[DS.display_name()]'.", user)
	return TRUE

/// Seizes ownership of a ship for the Hub -- snapshots whatever ownership
/// existed (personal or faction) into the prev_* columns, then clears it and
/// sets faction_uid = "hub". No new retrieve/board code is needed for "the
/// Hub keeps it": the moment faction_uid reads "hub", every existing
/// faction-ownership check in the codebase (Drydock's own ship list query,
/// boarding, disembark) already treats it as belonging to any Hub security
/// member, same as any other faction-owned ship. Refuses if already
/// repossessed -- return the ship first via drydockReturnToOwner() to
/// re-repossess it.
/datum/controller/subsystem/persistence/proc/drydockRepossess(shuttle_id, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS || DS.repossessed)
		return FALSE

	if(!databaseCheckConnection("drydockRepossess"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE

	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_drydock_ships SET repossessed = 1, prev_owner_ckey = :prev_ckey, prev_owner_char_name = :prev_char, prev_faction_uid = :prev_faction, owner_ckey = NULL, owner_char_name = NULL, faction_uid = :hub, schematic_banked = 1 WHERE shuttle_id = :id",
		list("prev_ckey" = DS.owner_ckey, "prev_char" = DS.owner_char_name, "prev_faction" = DS.faction_uid, "hub" = "hub", "id" = shuttle_id)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockRepossess update"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- repossession not saved."))
		return FALSE
	qdel(q)

	DS.prev_owner_ckey = DS.owner_ckey
	DS.prev_owner_char_name = DS.owner_char_name
	DS.prev_faction_uid = DS.faction_uid
	DS.owner_ckey = null
	DS.owner_char_name = null
	DS.faction_uid = "hub"
	DS.repossessed = TRUE
	_shipCentralPartialUpdate(DS.global_ship_id,
		list("repossessed", "prev_owner_ckey", "prev_owner_char_name", "prev_faction_uid", "owner_ckey", "owner_char_name", "faction_uid"),
		list(1, DS.prev_owner_ckey, DS.prev_owner_char_name, DS.prev_faction_uid, null, null, "hub"))
	// Forced into the bank alongside the seizure -- whatever schematic is out
	// there (found below, wherever it physically is) gets killed permanently,
	// and there's deliberately no personal replacement minted for the seizing
	// officer (the ship becomes Hub property, not personally theirs). Banking
	// it is what lets drydockReturnToOwner() leave the restored owner with a
	// working "withdraw_schematic" recovery path afterward instead of a
	// ship with no schematic and no way to get one back short of an admin.
	DS.schematic_banked = TRUE

	var/invalidated = 0
	for(var/obj/item/ship_schematic/S in world)
		if(S.shuttle_id == shuttle_id && S.bound_purchased_at == DS.purchased_at && !S.repossessed)
			S.repossessed = TRUE
			S.refresh_name()
			invalidated++

	log_and_message_admins("repossessed drydock ship #[shuttle_id] ('[DS.display_name()]') for the Hub ([invalidated] live schematic(s) invalidated).", user)
	log_drydock("drydockRepossess: [acting] repossessed shuttle_id=[shuttle_id] for the Hub ([invalidated] live schematic(s) invalidated).")
	return TRUE

/// Reverses drydockRepossess() -- restores whatever ownership was snapshotted
/// at seizure time and clears the repossessed flag/prev_* columns. Refuses if
/// the ship isn't currently repossessed.
/datum/controller/subsystem/persistence/proc/drydockReturnToOwner(shuttle_id, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS || !DS.repossessed)
		return FALSE

	if(!databaseCheckConnection("drydockReturnToOwner"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE

	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_drydock_ships SET repossessed = 0, owner_ckey = :owner_ckey, owner_char_name = :owner_char, faction_uid = :faction, prev_owner_ckey = NULL, prev_owner_char_name = NULL, prev_faction_uid = NULL WHERE shuttle_id = :id",
		list("owner_ckey" = DS.prev_owner_ckey, "owner_char" = DS.prev_owner_char_name, "faction" = DS.prev_faction_uid, "id" = shuttle_id)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockReturnToOwner update"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- return not saved."))
		return FALSE
	qdel(q)

	DS.owner_ckey = DS.prev_owner_ckey
	DS.owner_char_name = DS.prev_owner_char_name
	DS.faction_uid = DS.prev_faction_uid
	DS.repossessed = FALSE
	DS.prev_owner_ckey = null
	DS.prev_owner_char_name = null
	DS.prev_faction_uid = null
	_shipCentralPartialUpdate(DS.global_ship_id,
		list("repossessed", "owner_ckey", "owner_char_name", "faction_uid", "prev_owner_ckey", "prev_owner_char_name", "prev_faction_uid"),
		list(0, DS.owner_ckey, DS.owner_char_name, DS.faction_uid, null, null, null))

	log_and_message_admins("returned drydock ship #[shuttle_id] ('[DS.display_name()]') to its original owner.", user)
	log_drydock("drydockReturnToOwner: [acting] returned shuttle_id=[shuttle_id] to its original owner.")
	return TRUE

/// Called by ship_schematic.dm's resolve_attackby() when a valid, live
/// schematic is deposited into a Drydock console/laptop -- caller is
/// responsible for destroying the physical item; this just records the ship
/// as banked so drydock.dm's "withdraw_schematic" knows to offer a reprint.
/// Refuses while deployed -- banking a schematic for a ship still out in the
/// field would leave it inaccessible to everyone until someone withdraws a
/// fresh one, so it must be stashed first (checked again here, not just in
/// the item's own afterattack(), same defense-in-depth every other proc in
/// this file already applies).
/datum/controller/subsystem/persistence/proc/drydockBankSchematic(shuttle_id, mob/user)
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS || DS.schematic_banked || !DS.stashed)
		return FALSE
	if(!databaseCheckConnection("drydockBankSchematic"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery("UPDATE ss13_drydock_ships SET schematic_banked = 1 WHERE shuttle_id = :id", list("id" = shuttle_id))
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockBankSchematic update"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- deposit not saved."))
		return FALSE
	qdel(q)
	DS.schematic_banked = TRUE

	// A non-title-holder banking someone else's ship is exactly what makes
	// it "theirs now" going forward (they become the recoverable-from-a-
	// console owner) -- but the permanent title never moves, and the
	// schematic gets flagged reported_stolen until it's back with the
	// title-holder or formally given away (drydockGiveSchematic()).
	if(user && !DS.is_title_holder(user))
		DS.owner_ckey = user.ckey
		DS.owner_char_name = user.real_name
		DS.faction_uid = null
		var/datum/db_query/oq = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET owner_ckey = :ck, owner_char_name = :cn, faction_uid = NULL WHERE shuttle_id = :id",
			list("ck" = user.ckey, "cn" = user.real_name, "id" = shuttle_id)
		)
		oq.Execute()
		databaseCheckQueryResult(oq, "drydockBankSchematic ownership transfer")
		qdel(oq)
		_shipCentralPartialUpdate(DS.global_ship_id, list("owner_ckey", "owner_char_name", "faction_uid"), list(user.ckey, user.real_name, null))
		log_drydock("drydockBankSchematic: [key_name(user)] (not the title-holder) banked shuttle_id=[shuttle_id] -- current ownership transferred to them.")

	_drydockFlagIfStolen(DS, user)
	log_drydock("drydockBankSchematic: [user ? key_name(user) : "SYSTEM"] deposited the schematic for shuttle_id=[shuttle_id].")
	return TRUE

/// Shared by drydockStash()/drydockRetrieve()/drydockBankSchematic() -- marks
/// a ship reported_stolen the first time someone who ISN'T its title-holder
/// (is_title_holder(), persistence_shuttles.dm) performs one of those three
/// actions on it. Admin actions and SYSTEM-triggered calls (user == null,
/// e.g. backup restores) never flag. Cleared by drydockClearStolenFlag(),
/// called from ship_schematic.dm's passive examine/ui_data detection.
/datum/controller/subsystem/persistence/proc/_drydockFlagIfStolen(datum/drydock_ship/DS, mob/user)
	if(!user || DS.reported_stolen || check_rights(R_ADMIN, 0, user) || DS.is_title_holder(user))
		return
	if(!databaseCheckConnection("_drydockFlagIfStolen"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery("UPDATE ss13_drydock_ships SET reported_stolen = 1 WHERE shuttle_id = :id", list("id" = DS.shuttle_id))
	q.Execute()
	if(!databaseCheckQueryResult(q, "_drydockFlagIfStolen update"))
		qdel(q)
		return
	qdel(q)
	DS.reported_stolen = TRUE
	_shipCentralPartialUpdate(DS.global_ship_id, list("reported_stolen"), list(1))
	_drydockRefreshDisplayedName(DS)
	log_drydock("_drydockFlagIfStolen: [key_name(user)] (not the title-holder) flagged shuttle_id=[DS.shuttle_id] as stolen.")

/// Reverses _drydockFlagIfStolen() -- called from ship_schematic.dm once the
/// title-holder is confirmed to actually be holding their own schematic
/// again (examining it or opening its TGUI while it's on their person).
/datum/controller/subsystem/persistence/proc/drydockClearStolenFlag(shuttle_id)
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS || !DS.reported_stolen)
		return
	if(!databaseCheckConnection("drydockClearStolenFlag"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery("UPDATE ss13_drydock_ships SET reported_stolen = 0 WHERE shuttle_id = :id", list("id" = shuttle_id))
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockClearStolenFlag update"))
		qdel(q)
		return
	qdel(q)
	DS.reported_stolen = FALSE
	_shipCentralPartialUpdate(DS.global_ship_id, list("reported_stolen"), list(0))
	_drydockRefreshDisplayedName(DS)
	log_drydock("drydockClearStolenFlag: shuttle_id=[shuttle_id] is back with its title-holder -- stolen flag cleared.")

/// Lets shuttle_id's CURRENT owner (not necessarily its permanent
/// title-holder -- see the gate below) formally sign the ship's title over
/// to someone else -- driven from the schematic's own UI, the deliberate
/// "sign over the title" counterpart to just physically handing someone the
/// schematic (which, per is_title_holder(), never moves title on its own).
/// The recipient may be a single character (target_ckey/target_char_name) or
/// a whole faction (target_faction_uid); ownership follows title either way.
/// Refuses outright while reported_stolen --
/// handing off a stolen ship is still handing off a stolen ship, so this can
/// never be used to launder one; it only ever succeeds on a ship that was
/// never stolen (or already recovered by its title-holder, clearing the
/// flag), never as a shortcut around that.
/datum/controller/subsystem/persistence/proc/drydockGiveSchematic(shuttle_id, target_ckey, target_char_name, mob/user, target_faction_uid = null)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	// schematic_banked is deliberately NOT required any more: this is now
	// driven from the physical schematic's own UI (ship_schematic.dm), so the
	// schematic is in the holder's hand rather than banked in a console.
	if(!DS || DS.repossessed)
		return FALSE
	// Gated on the PERMANENT title holder, not current ownership. The old
	// console action let whoever currently owned the hull sign the title over,
	// which meant a thief who banked a stolen ship could launder its
	// provenance. is_title_holder() covers both the personally-titled and
	// faction-titled cases.
	if(!DS.can_transfer_title(user))
		if(user)
			to_chat(user, DS.title_faction_uid \
				? SPAN_WARNING("Only an officer or command member of [get_faction_name(DS.title_faction_uid)] can sign this ship's title over.") \
				: SPAN_WARNING("Only this ship's title holder can sign its title over."))
		log_drydock_warning("drydockGiveSchematic: refused -- [acting] may not transfer the title of shuttle_id=[shuttle_id].")
		return FALSE
	if(DS.reported_stolen && !check_rights(R_ADMIN, 0, user))
		if(user)
			to_chat(user, SPAN_WARNING("This ship is reported stolen -- its title can't be legitimately transferred until it's back with its rightful owner."))
		log_drydock_warning("drydockGiveSchematic: refused -- shuttle_id=[shuttle_id] is reported_stolen (acting=[acting]).")
		return FALSE
	// Two mutually exclusive targets. target_faction_uid signs the ship over to
	// a faction as a whole (title AND current ownership both become the
	// faction's, and the personal identity columns are cleared); otherwise the
	// ckey/char_name pair names one character. Ownership follows title in both
	// cases -- a transfer hands over the ship, not just its provenance.
	var/datum/db_query/q
	if(target_faction_uid)
		target_faction_uid = normalize_faction_uid(target_faction_uid)
		if(!target_faction_uid || !(target_faction_uid in GLOB.persistence_faction_cache))
			if(user)
				to_chat(user, SPAN_WARNING("That faction doesn't exist."))
			return FALSE
		if(!databaseCheckConnection("drydockGiveSchematic"))
			if(user)
				to_chat(user, SPAN_WARNING("Database connection failed."))
			return FALSE
		q = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET title_ckey = NULL, title_char_name = NULL, title_faction_uid = :fid, owner_ckey = NULL, owner_char_name = NULL, faction_uid = :fid, reported_stolen = 0 WHERE shuttle_id = :id",
			list("fid" = target_faction_uid, "id" = shuttle_id)
		)
	else
		target_ckey = ckey(target_ckey)
		if(!target_ckey || !target_char_name)
			return FALSE
		if(!databaseCheckConnection("drydockGiveSchematic"))
			if(user)
				to_chat(user, SPAN_WARNING("Database connection failed."))
			return FALSE
		q = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET title_ckey = :ck, title_char_name = :cn, title_faction_uid = NULL, owner_ckey = :ck, owner_char_name = :cn, faction_uid = NULL, reported_stolen = 0 WHERE shuttle_id = :id",
			list("ck" = target_ckey, "cn" = target_char_name, "id" = shuttle_id)
		)

	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockGiveSchematic update"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- transfer not saved."))
		return FALSE
	qdel(q)

	if(target_faction_uid)
		DS.title_ckey = null
		DS.title_char_name = null
		DS.title_faction_uid = target_faction_uid
		DS.owner_ckey = null
		DS.owner_char_name = null
		DS.faction_uid = target_faction_uid
	else
		DS.title_ckey = target_ckey
		DS.title_char_name = target_char_name
		DS.title_faction_uid = null
		DS.owner_ckey = target_ckey
		DS.owner_char_name = target_char_name
		DS.faction_uid = null
	DS.reported_stolen = FALSE
	_shipCentralPartialUpdate(DS.global_ship_id,
		list("title_ckey", "title_char_name", "title_faction_uid", "owner_ckey", "owner_char_name", "faction_uid", "reported_stolen"),
		list(DS.title_ckey, DS.title_char_name, DS.title_faction_uid, DS.owner_ckey, DS.owner_char_name, DS.faction_uid, 0))

	// Wipe the crew roster along with the title. Boarding rights resolve as
	// owned_by() OR faction match OR membership of crew_ckeys
	// (_drydock_full_access_check(), telepad_drydock_boarding.dm) -- so
	// reassigning ownership alone left the PREVIOUS owner and everyone they
	// had added still able to board, and still hearing that ship's boarding
	// audio. The new title holder starts with a clean roster and re-adds whom
	// they want via the schematic's own Add Crew.
	var/datum/db_query/crew_wipe = SSdbcore.NewQuery(
		"DELETE FROM ss13_ship_crew WHERE shuttle_id = :id",
		list("id" = shuttle_id)
	)
	crew_wipe.Execute()
	databaseCheckQueryResult(crew_wipe, "drydockGiveSchematic crew wipe")
	qdel(crew_wipe)
	DS.crew_ckeys = list()

	var/recipient_desc = target_faction_uid ? "[get_faction_name(target_faction_uid)] (faction)" : "'[target_char_name]' ([target_ckey])"
	if(user)
		to_chat(user, SPAN_GOOD("Title for [DS.display_name()] transferred to [recipient_desc]. Its crew roster has been cleared."))
	log_drydock("drydockGiveSchematic: [acting] transferred title for shuttle_id=[shuttle_id] to [recipient_desc].")
	return TRUE

/// Reverses drydockBankSchematic() -- mints a fresh /obj/item/ship_schematic
/// for shuttle_id and hands it to user, clearing schematic_banked. Caller
/// (drydock.dm's "withdraw_schematic") is responsible for the historical
/// owner_ckey/owner_char_name/faction_uid identity check beforehand, the
/// same division of labor drydockRepossess() already has with its own
/// caller (First Responder). Refuses while still repossessed for a normal
/// call -- return the ship to its owner first -- unless hub_authority is
/// set (First Responder's own "withdraw_schematic", mirroring
/// drydockScuttle()'s identical hub_authority bypass in this same file),
/// which lets a Hub officer withdraw a still-repossessed ship's schematic
/// directly, e.g. to hand it back to the owner in person.
/datum/controller/subsystem/persistence/proc/drydockWithdrawSchematic(shuttle_id, mob/user, hub_authority = FALSE)
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS || !DS.schematic_banked || (DS.repossessed && !hub_authority) || !user)
		return FALSE
	if(!databaseCheckConnection("drydockWithdrawSchematic"))
		to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery("UPDATE ss13_drydock_ships SET schematic_banked = 0 WHERE shuttle_id = :id", list("id" = shuttle_id))
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockWithdrawSchematic update"))
		qdel(q)
		to_chat(user, SPAN_WARNING("Database error -- withdrawal not saved."))
		return FALSE
	qdel(q)
	DS.schematic_banked = FALSE

	var/obj/item/ship_schematic/schematic = new(get_turf(user))
	schematic.shuttle_id = shuttle_id
	schematic.bound_purchased_at = DS.purchased_at
	schematic.refresh_name()
	user.put_in_hands(schematic)
	to_chat(user, SPAN_GOOD("Withdrew the schematic for [DS.display_name()]."))
	log_drydock("drydockWithdrawSchematic: [key_name(user)] withdrew the schematic for shuttle_id=[shuttle_id].")
	return TRUE

/// Registers each sub-ship's own home landmark as a RESTRICTED waypoint on
/// its parent drydock ship's overmap marker, so a launched sub-ship can
/// actually select "return to my hangar".
///
/// Without this it never can. /datum/shuttle/autodock/overmap builds its
/// destination list purely from sector waypoints (get_waypoints(),
/// sectors.dm), and NO drydock template declares
/// initial_generic_waypoints/initial_restricted_waypoints -- the away-site
/// originals do, but the drydock markers don't subtype them, so they inherit
/// nothing. A deployed drydock sector therefore only ever exposes its own
/// Open-Space landmark plus the generated visiting_shuttle slots.
///
/// Forced recall always worked because it resolves logging_home_tag directly
/// through SSshuttle.get_landmark() and skips waypoints entirely. The same tag
/// is reused here so both paths agree on what "home" means.
///
/// A bound sub-ship (Xanu Fighter/Boarder, etc. -- /datum/shuttle/autodock/overmap/xanu_fighter
/// and siblings, NOT /datum/shuttle/autodock/overmap/drydock_ship) never carries
/// its own faction_uid -- it's never independently ledgered in
/// GLOB.drydock_ships, see subshipSnapshotSave()'s own doc comment. Ownership
/// only ever exists via whichever deployed mothership's own template lists
/// this shuttle's CURRENT name in sub_shuttle_tags (same key
/// _drydock_register_subship_waypoints() below already resolves through
/// SSshuttle.shuttles[sub_tag]). Used by player_dock/is_valid()'s raiding
/// check (docking_beacon.dm) so a sub-ship correctly inherits its parent's
/// faction instead of always resolving to "no faction" (which would block it
/// from docking anywhere claimed, including its own faction's territory,
/// the moment raiding is disabled).
/proc/_drydock_sub_shuttle_owner_faction(shuttle_name)
	if(!shuttle_name)
		return null
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed)
			continue
		var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
		if(!template)
			continue
		// Compared against the per-instance registry key, not the bare tag.
		// sub_shuttle_tags holds "Xanu Fighter" while the live shuttle is
		// named "Xanu Fighter #18" (drydock_apply_instance_suffix()), so the
		// old `shuttle_name in template.sub_shuttle_tags` never matched and
		// every sub-ship resolved as factionless -- which then got it refused
		// from docking in its own faction's claimed territory.
		for(var/sub_tag in template.sub_shuttle_tags)
			if(shuttle_name == _drydock_subship_key(DS.shuttle_id, sub_tag))
				return DS.faction_uid
	return null

/// SSshuttle.shuttles[] looked up by a marker's own .shuttle, guarded against
/// that var being unset. Indexing a list with null is a "bad index" runtime in
/// BYOND, and a landable overmap marker with no shuttle datum assigned is an
/// ordinary thing to encounter -- especially while walking another ship's
/// nested contents during a stash, which is where this kept killing the whole
/// operation. "No shuttle" is the correct answer, not a crash.
/proc/_drydock_shuttle_of(obj/effect/overmap/visitable/ship/landable/marker)
	if(!istype(marker) || isnull(marker.shuttle))
		return null
	return SSshuttle.shuttles[marker.shuttle]

/// A deployed sub-ship's real SSshuttle.shuttles key. sub_shuttle_tags holds
/// the bare template tag ("Solarian Frigate Shuttle"), but a sub-ship's
/// shuttle datum registers under a per-instance suffixed name
/// (drydock_apply_instance_suffix(), applied in /datum/shuttle/New() BEFORE
/// SSshuttle.shuttles[src.name] = src) -- so the bare tag is never the key,
/// and every lookup through it silently returned null.
/proc/_drydock_subship_key(shuttle_id, shuttle_tag)
	return "[shuttle_tag] #[shuttle_id]"

/// The overmap marker for a deployed sub-ship, or null. Markers carry the
/// registry key in .shuttle, so this matches on the real key above.
/proc/_drydock_subship_marker(shuttle_id, shuttle_tag)
	var/key = _drydock_subship_key(shuttle_id, shuttle_tag)
	for(var/obj/effect/overmap/visitable/ship/landable/sub_marker in SSshuttle.ships)
		if(sub_marker.shuttle == key)
			return sub_marker
	return null

/// TRUE if this nested marker's home hangar is aboard `marker` itself -- i.e.
/// it is one of my own sub-ships parked at home, not a foreign guest.
///
/// on_landing() (landable.dm) forceMove()s a landing ship's marker into the
/// marker of whatever z it touched down on, so a sub-ship sitting in its own
/// hangar is ALWAYS nested in its parent's contents -- that's its normal
/// parked state, not a docked visitor.
///
/// Keyed on logging_home_tag rather than name: a sub-ship's identity is
/// matched elsewhere in this file by its CURRENT name against the template's
/// fixed sub_shuttle_tags (see _drydock_sub_shuttle_owner_faction() above),
/// but drydockRenameSubship() changes that name while sub_shuttle_tags keeps
/// the original tag -- so a renamed sub-ship stopped matching and started
/// reading as a foreign ship docked aboard its own carrier, which blocked the
/// carrier from ever stashing. logging_home_tag is assigned at shuttle
/// creation and no rename path touches it.
/proc/_drydock_guest_is_own_subship(obj/effect/overmap/visitable/ship/landable/guest, obj/effect/overmap/visitable/ship/landable/marker)
	if(!istype(guest) || !istype(marker))
		return FALSE
	// guest.shuttle must be checked BEFORE it is used as a list index.
	// Indexing a list with null is a "bad index" runtime in BYOND, and a
	// landable overmap marker with no shuttle datum assigned is a perfectly
	// ordinary thing to find nested in another ship's contents -- which made
	// stashing any hull with such a marker aboard die with
	// "drydockStash: uncaught exception ... bad index".
	if(!guest.shuttle)
		return FALSE
	var/datum/shuttle/guest_shuttle = SSshuttle.shuttles[guest.shuttle]
	if(!istype(guest_shuttle) || !guest_shuttle.logging_home_tag)
		return FALSE
	var/obj/effect/shuttle_landmark/guest_home = SSshuttle.get_landmark(guest_shuttle.logging_home_tag)
	if(!guest_home)
		return FALSE
	return (guest_home.z in marker.map_z)

/// Restricted rather than generic: only this sub-ship may dock in its own
/// parent's hangar. Keyed by the shuttle's CURRENT name, because that's what
/// get_waypoints(name) matches on -- see drydockRenameSubship(), which has to
/// re-key when that name changes.
/proc/_drydock_register_subship_waypoints(obj/effect/overmap/visitable/marker, datum/map_template/drydock_ship/template, shuttle_id)
	if(!istype(marker) || !template || !length(template.sub_shuttle_tags))
		return
	for(var/sub_tag in template.sub_shuttle_tags)
		// One tag's work is its own proc so the whole thing can sit inside a
		// try/catch cleanly (a `continue` inside a try block is exactly the
		// kind of control flow to avoid here). This body never actually
		// executed while the lookup resolved null, so any latent runtime in
		// it must degrade to a logged error rather than aborting the caller's
		// entire retrieve -- see reverted commit bd131aaa.
		try
			_drydock_register_one_subship_waypoint(marker, shuttle_id, sub_tag)
		catch(var/exception/wp_e)
			log_drydock_error("_drydock_register_subship_waypoints: failed for sub-ship '[sub_tag]' (shuttle_id=[shuttle_id]): [wp_e]")

/// One sub-ship's hangar registration -- see the caller above for why this is
/// split out.
/proc/_drydock_register_one_subship_waypoint(obj/effect/overmap/visitable/marker, shuttle_id, sub_tag)
	var/datum/shuttle/sub = SSshuttle.shuttles[_drydock_subship_key(shuttle_id, sub_tag)]
	if(!istype(sub) || !sub.logging_home_tag)
		return
	var/obj/effect/shuttle_landmark/home = SSshuttle.get_landmark(sub.logging_home_tag)
	if(!home)
		// Expected for hulls whose map simply has no hangar landmark (the
		// Idris Cruiser only maps port/starboard berths), and for a tag
		// dropped by SSshuttle's duplicate guard when the matching away
		// site spawned the same round and claimed it first.
		log_drydock_warning("_drydock_register_subship_waypoints: no home landmark '[sub.logging_home_tag]' for sub-ship '[sub_tag]' -- it will not be able to return to its hangar.")
		return
	if(home in LAZYACCESS(marker.restricted_waypoints, sub.name))
		return // already registered (re-deploy)
	marker.add_landmark(home, sub.name)

	// Also expose this same hangar slot publicly -- a
	// size-gated proxy at the same turf, discoverable by any
	// appropriately sized outside ship's own navigation console, valid
	// only while sub isn't physically parked here right now
	// (hangar_slot/is_valid(), docking_beacon.dm). The real home
	// landmark above is untouched -- still restricted to sub's own name
	// for its "return to hangar" waypoint.
	var/public_tag = "[home.landmark_tag]_public"
	if(!SSshuttle.registered_shuttle_landmarks[public_tag])
		var/obj/effect/shuttle_landmark/player_dock/hangar_slot/slot = new(get_turf(home))
		slot.landmark_tag = public_tag
		slot.name = "[sub.name] Hangar Slot"
		slot.base_area = home.base_area
		slot.base_turf = home.base_turf
		slot.max_footprint_x = SUBSHIP_FOOTPRINT_X
		slot.max_footprint_y = SUBSHIP_FOOTPRINT_Y
		slot.bound_sub_shuttle = sub
		slot.real_home = home
		// Registered explicitly, because /obj/effect/shuttle_landmark/Initialize()
		// (landmarks.dm) already ran its own register_landmark() during the
		// new() above -- while landmark_tag was still null, since it's only
		// assigned on the line after. Without this the tag never enters
		// registered_shuttle_landmarks at all, so the dedup guard just above
		// passes on every single retrieve (leaking another duplicate slot each
		// time) and _drydock_unregister_subship_waypoints() below can never
		// find this slot to clean it up.
		SSshuttle.register_landmark(public_tag, slot)
		marker.add_landmark(slot, null)

/// Drops those registrations again, so a stashed ship's hangar stops being
/// offered as a destination to anything still flying.
/proc/_drydock_unregister_subship_waypoints(obj/effect/overmap/visitable/marker, datum/map_template/drydock_ship/template, shuttle_id)
	if(!istype(marker) || !template || !length(template.sub_shuttle_tags))
		return
	for(var/sub_tag in template.sub_shuttle_tags)
		var/datum/shuttle/sub = SSshuttle.shuttles[_drydock_subship_key(shuttle_id, sub_tag)]
		if(!istype(sub) || !sub.logging_home_tag)
			continue
		var/obj/effect/shuttle_landmark/home = SSshuttle.get_landmark(sub.logging_home_tag)
		if(home)
			marker.remove_landmark(home, sub.name)
			var/obj/effect/shuttle_landmark/player_dock/hangar_slot/slot = SSshuttle.registered_shuttle_landmarks["[home.landmark_tag]_public"]
			if(slot)
				marker.remove_landmark(slot, null)
				qdel(slot)

/// Renames a sub-ship mapped into this hull's own hangar (see
/// /datum/map_template/drydock_ship/sub_shuttle_tags, drydock_ship.dm) --
/// bound entirely to the parent ship, so this just updates the persisted
/// display name (ss13_drydock_subship_names) and the live shuttle datum's
/// own .name, not a separate ledger entry. shuttle_tag identifies which
/// sub-ship for hulls carrying more than one (Xanu Frigate, Taj Smuggler).
/datum/controller/subsystem/persistence/proc/drydockRenameSubship(shuttle_id, shuttle_tag, new_name, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS)
		log_drydock_warning("drydockRenameSubship: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to rename this ship's sub-ship."))
		log_drydock_warning("drydockRenameSubship: refused -- [acting] lacks permission for shuttle_id=[shuttle_id].")
		return FALSE
	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
	if(!template || !(shuttle_tag in template.sub_shuttle_tags))
		log_drydock_warning("drydockRenameSubship: refused -- shuttle_tag='[shuttle_tag]' not a valid sub-ship for shuttle_id=[shuttle_id].")
		return FALSE

	if(!databaseCheckConnection("drydockRenameSubship"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_drydock_subship_names (shuttle_id, shuttle_tag, custom_name) VALUES (:id, :tag, :name) ON DUPLICATE KEY UPDATE custom_name = VALUES(custom_name)",
		list("id" = shuttle_id, "tag" = shuttle_tag, "name" = new_name)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "drydockRenameSubship update"))
		qdel(q)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- rename not saved."))
		return FALSE
	qdel(q)

	// Renames the player-facing overmap MARKER, deliberately not the shuttle
	// datum's own name. That's the same split the parent ship already uses --
	// _drydockRetrieveRun() keeps the datum as "<template> #id" (its
	// SSshuttle.shuttles key) and sets marker.name = DS.display_name() for
	// players. Leaving the datum name alone means no re-keying of
	// SSshuttle.shuttles, and no orphaning of restricted_waypoints, which is
	// keyed by that datum name.
	var/obj/effect/overmap/visitable/ship/landable/sub_marker = _drydock_subship_marker(shuttle_id, shuttle_tag)
	if(istype(sub_marker))
		sub_marker.name = new_name

	if(user)
		to_chat(user, SPAN_GOOD("Sub-ship renamed."))
	log_drydock("drydockRenameSubship: [acting] renamed shuttle_id=[shuttle_id]'s sub-ship '[shuttle_tag]' to '[new_name]'.")
	log_and_message_admins("renamed drydock ship #[shuttle_id]'s sub-ship '[shuttle_tag]' to '[new_name]'.", user)
	return TRUE

/// Applies each persisted sub-ship custom name (ss13_drydock_subship_names)
/// to its live shuttle datum -- called once per retrieve, alongside the
/// missing-sub-ship detection (see _drydockRetrieveRun()) since both need
/// the same per-tag SSshuttle.shuttles lookup.
/datum/controller/subsystem/persistence/proc/_drydockApplySubshipNames(shuttle_id, datum/map_template/drydock_ship/template)
	if(!template || !length(template.sub_shuttle_tags))
		return
	if(!databaseCheckConnection("_drydockApplySubshipNames"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT shuttle_tag, custom_name FROM ss13_drydock_subship_names WHERE shuttle_id = :id",
		list("id" = shuttle_id)
	)
	q.Execute()
	if(databaseCheckQueryResult(q, "_drydockApplySubshipNames select"))
		while(q.NextRow())
			// Marker, not the shuttle datum -- see drydockRenameSubship().
			var/obj/effect/overmap/visitable/ship/landable/sub_marker = _drydock_subship_marker(shuttle_id, q.item[1])
			if(istype(sub_marker))
				sub_marker.name = q.item[2]
	qdel(q)

/**
 * Self-contained "turf saving" for a sub-ship mapped into a drydock hull's
 * own hangar bay -- separate from, and independent of, the whole-Z
 * ship-scale persistence (turfsFinalizeZ()/objectsFinalizeZ() etc, scoped
 * to "ship:d:<shuttle_id>"). Narrower in scope too: turf type + any loose
 * items sitting on it, not full structure/machinery tracking -- covers
 * "is the compartment intact, is my stuff still in it," not a second copy
 * of the generic object-persistence system.
 *
 * subshipSnapshotSave() captures every turf in the sub-ship's own
 * shuttle_area (absolute x/y, turf type, loose /obj/items via the same
 * serializePersistentItem() used for closet contents elsewhere) into one
 * JSON row per (shuttle_id, shuttle_tag). subshipSnapshotApply() re-applies
 * that snapshot on the next retrieve -- unconditionally, the same
 * philosophy as the parent ship's own persistence always re-applying its
 * last save -- which is what makes this double as "replenish if missing":
 * if the compartment was damaged or its contents scattered in a previous
 * session, re-applying the last good snapshot restores it. A sub-ship
 * that's never been saved before (first-ever retrieve) simply has no row
 * yet, so apply() no-ops and the freshly map-loaded template copy stands
 * as-is, exactly like a pristine ship interior today.
 */
/datum/controller/subsystem/persistence/proc/subshipSnapshotSave(shuttle_id, shuttle_tag)
	var/datum/shuttle/sub = SSshuttle.shuttles[_drydock_subship_key(shuttle_id, shuttle_tag)]
	if(!istype(sub))
		return
	// Everything below is best-effort bookkeeping: losing one turf or one item
	// from a snapshot is far better than an uncaught runtime aborting the
	// whole stash, which is exactly what "drydockStash: uncaught exception ...
	// bad index" was. This body never executed at all until the sub-ship
	// lookup above was fixed, so it is newly exposed code. The logs name the
	// sub tag, turf and item type so a real failure is pinpointable instead of
	// being a bare "bad index".
	var/list/turf_rows = list()
	for(var/area/A in sub.shuttle_area)
		for(var/turf/T in get_area_turfs(A))
			CHECK_TICK
			try
				var/list/items = list()
				for(var/obj/item/I in T)
					try
						var/list/item_data = serializePersistentItem(I)
						if(item_data)
							items += list(item_data)
					catch(var/exception/item_e)
						log_drydock_error("subshipSnapshotSave: failed to serialize [I?.type] at ([T.x],[T.y],[T.z]) for shuttle_id=[shuttle_id] tag='[shuttle_tag]': [item_e]")
				turf_rows += list(list("x" = T.x, "y" = T.y, "type" = "[T.type]", "items" = items))
			catch(var/exception/turf_e)
				log_drydock_error("subshipSnapshotSave: failed on turf ([T.x],[T.y],[T.z]) for shuttle_id=[shuttle_id] tag='[shuttle_tag]': [turf_e]")
	if(!databaseCheckConnection("subshipSnapshotSave"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_drydock_subship_snapshot (shuttle_id, shuttle_tag, turf_data) VALUES (:id, :tag, :data) ON DUPLICATE KEY UPDATE turf_data = VALUES(turf_data)",
		list("id" = shuttle_id, "tag" = shuttle_tag, "data" = json_encode(turf_rows))
	)
	q.Execute()
	databaseCheckQueryResult(q, "subshipSnapshotSave update")
	qdel(q)

/// Periodic safety net for sub-ship snapshots, mirroring why
/// shipLedgerPositionSync() exists for the parent ship's own ledger --
/// without this, subshipSnapshotSave() only ever runs at explicit stash,
/// so an ungraceful crash (no drydockAutoStashAll() sweep) would replenish
/// a sub-ship from wherever it was at the LAST real stash, not where it
/// actually was -- stale in exactly the way the parent ship's own interior
/// isn't, since forceSaveAll() already covers that via the ordinary
/// world-wide turfs/objects/etc. sweeps. Called from forceSaveAll()
/// (persistence.dm, the periodic autosave) and from the "Force Persistence
/// Save" admin verb (persistence.dm's force_persistence_save() -- a
/// separate, hand-duplicated call sequence that doesn't route through
/// forceSaveAll() itself), so every save trigger keeps every deployed
/// ship's sub-ship(s) no more than one save cycle stale.
/datum/controller/subsystem/persistence/proc/subshipSnapshotSaveAllDeployed()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed)
			continue
		var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
		if(!template || !length(template.sub_shuttle_tags))
			continue
		for(var/sub_tag in template.sub_shuttle_tags)
			subshipSnapshotSave(DS.shuttle_id, sub_tag)

/// Re-applies a sub-ship's last snapshot (if any) onto its freshly-loaded
/// area, on the given (current) z -- turf coordinates are stored relative
/// to nothing but the hull's own fixed layout (x/y only, no z), since the
/// same hull can reuse a different pooled z on every deployment.
/datum/controller/subsystem/persistence/proc/subshipSnapshotApply(shuttle_id, shuttle_tag, z)
	if(!databaseCheckConnection("subshipSnapshotApply"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT turf_data FROM ss13_drydock_subship_snapshot WHERE shuttle_id = :id AND shuttle_tag = :tag",
		list("id" = shuttle_id, "tag" = shuttle_tag)
	)
	q.Execute()
	var/turf_data
	if(databaseCheckQueryResult(q, "subshipSnapshotApply select") && q.NextRow())
		turf_data = q.item[1]
	qdel(q)
	if(!turf_data)
		return
	var/list/turf_rows = json_decode(turf_data)
	if(!islist(turf_rows))
		return
	// Per-row validation + try/catch, because until subshipSnapshotSave() was
	// fixed nothing ever wrote to ss13_drydock_subship_snapshot, so this body
	// has effectively never executed in production. One malformed or
	// truncated row must degrade to a logged warning, not abort the caller --
	// an uncaught runtime here surfaces as drydockRetrieve()'s "uncaught
	// exception" and takes the whole retrieve down with it.
	for(var/list/row in turf_rows)
		if(!islist(row) || !isnum(row["x"]) || !isnum(row["y"]))
			log_drydock_warning("subshipSnapshotApply: skipped malformed row for shuttle_id=[shuttle_id] tag='[shuttle_tag]'.")
			continue
		var/turf/T = locate(row["x"], row["y"], z)
		if(!T)
			continue
		try
			var/turf_type = text2path(row["type"])
			if(turf_type && ispath(turf_type, /turf))
				T = T.ChangeTurf(turf_type)
			for(var/obj/item/existing in T)
				qdel(existing)
			if(islist(row["items"]))
				for(var/list/item_data in row["items"])
					if(!islist(item_data))
						continue
					deserializePersistentItem(item_data, T)
		catch(var/exception/row_e)
			log_drydock_error("subshipSnapshotApply: row ([row["x"]],[row["y"]]) failed for shuttle_id=[shuttle_id] tag='[shuttle_tag]': [row_e]")

// ============================================================
// BUY  pure purchase transaction, no world footprint
// ============================================================

/datum/controller/subsystem/persistence/proc/drydockBuy(template_id, owner_ckey, faction_uid, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_drydock("drydockBuy: [acting] attempting to buy template '[template_id]' (owner=[owner_ckey || "none"], faction=[faction_uid || "none"]).")

	if(!template_id || (!owner_ckey && !faction_uid))
		log_drydock_warning("drydockBuy: refused -- missing template_id or both owner_ckey/faction_uid (acting=[acting]).")
		return FALSE

	// A personal purchase belongs to the buying CHARACTER, not just their
	// account -- see owned_by() -- so a player's other characters don't
	// inherit access to a ship this one just bought.
	var/owner_char_name = (owner_ckey && user) ? user.real_name : null

	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[template_id]
	if(!template)
		if(user)
			to_chat(user, SPAN_WARNING("No such ship template."))
		log_drydock_warning("drydockBuy: refused -- unknown template_id '[template_id]' (acting=[acting]).")
		return FALSE
	// Server-side enforcement, not just a UI listing omission -- the shared
	// player-commissioned shell (hidden_from_catalog, drydock_ship.dm) must
	// never be reachable through the normal free/priced buy flow, only
	// through drydockCommission()'s own payment/rank gating.
	if(template.hidden_from_catalog)
		if(user)
			to_chat(user, SPAN_WARNING("No such ship template."))
		log_drydock_warning("drydockBuy: refused -- template '[template_id]' is hidden_from_catalog (acting=[acting]).")
		return FALSE

	var/owner_account_number
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
	else
		// Captured regardless of price (even a free ship) -- Crew-tagged
		// equipment (persistence_faction_tagger.dm) bills this account
		// directly later, even when the owner is offline, so it needs to be
		// on file from the moment the ship exists, not just when a fee was
		// actually charged.
		var/obj/item/card/id/ID = user?.GetIdCard()
		if(!ID || !ID.associated_account_number)
			if(user)
				to_chat(user, SPAN_WARNING("No linked bank account."))
			log_drydock_warning("drydockBuy: refused -- [acting] has no linked bank account.")
			return FALSE
		owner_account_number = ID.associated_account_number
		if(template.price > 0)
			var/datum/money_account/acc = SSeconomy.get_account(owner_account_number)
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
		"INSERT INTO ss13_drydock_ships (template_id, owner_ckey, owner_char_name, owner_account_number, faction_uid, stashed, purchased_at, title_ckey, title_char_name, title_faction_uid) VALUES (:tid, :ckey, :char_name, :account, :faction, 1, NOW(), :t_ckey, :t_char, :t_faction)",
		list("tid" = template_id, "ckey" = owner_ckey, "char_name" = owner_char_name, "account" = owner_account_number, "faction" = faction_uid, "t_ckey" = owner_ckey, "t_char" = owner_char_name, "t_faction" = faction_uid)
	)
	q.Execute()
	var/succeeded = databaseCheckQueryResult(q, "drydockBuy insert")
	var/new_id = text2num(q.last_insert_id)
	qdel(q)
	if(!succeeded)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- purchase not completed. Contact an admin if funds were deducted."))
		log_drydock_error("drydockBuy: DB insert failed for '[template_id]' (acting=[acting]).")
		return FALSE

	// Read the DB-assigned purchased_at back rather than stamping our own
	// timestamp string -- this exact value is what gets snapshotted onto the
	// buyer's schematic below, and must match byte-for-byte what a later
	// resolve_ship() staleness comparison reads back out of the same column.
	var/purchased_at
	var/datum/db_query/pq = SSdbcore.NewQuery("SELECT purchased_at FROM ss13_drydock_ships WHERE shuttle_id = :id", list("id" = new_id))
	pq.Execute()
	if(databaseCheckQueryResult(pq, "drydockBuy purchased_at read-back") && pq.NextRow())
		purchased_at = pq.item[1]
	qdel(pq)

	var/datum/drydock_ship/DS = new()
	DS.shuttle_id  = new_id
	DS.template_id = template_id
	DS.owner_ckey  = owner_ckey
	DS.owner_char_name = owner_char_name
	DS.owner_account_number = owner_account_number
	DS.faction_uid = faction_uid
	DS.stashed     = TRUE
	DS.purchased_at = purchased_at
	DS.title_ckey = owner_ckey
	DS.title_char_name = owner_char_name
	DS.title_faction_uid = faction_uid
	GLOB.drydock_ships["[new_id]"] = DS

	// CENTRAL_SYNC_SHIPS -- both gated inside their own procs (no-op
	// entirely when central_sql_enabled/central_sync_ships are off), see
	// this file's "CENTRAL SHIP SYNC" section.
	if(GLOB.config.central_sql_enabled && GLOB.config.central_server_id)
		DS.global_ship_id = "[GLOB.config.central_server_id]:[new_id]"
		var/datum/db_query/gq = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET global_ship_id = :gsid WHERE shuttle_id = :id",
			list("gsid" = DS.global_ship_id, "id" = new_id)
		)
		gq.Execute()
		qdel(gq)
		_shipCentralCreateWriteThrough(DS)

	if(user)
		var/obj/item/ship_schematic/schematic = new(get_turf(user))
		schematic.shuttle_id = new_id
		schematic.bound_purchased_at = purchased_at
		schematic.refresh_name()
		user.put_in_hands(schematic)
		to_chat(user, SPAN_GOOD("Purchased '[template.name]' -- schematic in hand."))
	log_and_message_admins("bought drydock ship '[template.name]' (#[new_id])[faction_uid ? " for faction [get_faction_name(faction_uid)]" : ""].", user)
	log_drydock("drydockBuy: [acting] bought '[template_id]' (owner=[owner_ckey ? "[owner_ckey] (\"[owner_char_name]\")" : "none"], faction=[faction_uid || "none"], shuttle_id=[new_id]).")
	return TRUE

// ============================================================
// COMMISSION  turn a player-built hull into a real drydock shuttle
// ============================================================

/// TRUE if any currently-known ship (deployed or stashed) already has this
/// exact name -- trimmed, case-insensitive. Compares against each ship's
/// own effective base name (custom_name if renamed, else its template's
/// default), the same value display_name() itself starts from, before any
/// faction-name/stolen suffix gets appended. Scoped to drydockCommission()
/// only -- drydockRename()/drydockBuy() have never enforced this and
/// aren't being changed to start now.
/proc/_drydock_name_taken(new_name)
	var/normalized = trim(lowertext(new_name))
	if(!normalized)
		return FALSE
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/other = GLOB.drydock_ships[sid]
		if(!other)
			continue
		var/other_base = other.custom_name
		if(!other_base)
			var/datum/map_template/drydock_ship/t = SSmapping.drydock_ship_templates[other.template_id]
			other_base = t ? initial(t.name) : other.template_id
		if(trim(lowertext(other_base)) == normalized)
			return TRUE
	return FALSE

/// Public entry point -- a thin queue-gate in front of _drydockCommissionRun()
/// (below), identical in shape to drydockRetrieve()/drydockStash()'s own
/// wrappers just above/below this file. Without this, two rapid Commission
/// clicks (or two players at two different consoles) could both pass
/// validation and both capture the same build before either one's heavy
/// body finishes -- at minimum a double-charge, at worst two ships minted
/// from one hull. Serializes with retrieve/stash too, not just other
/// commissions, since they share the same GLOB.drydock_op_active gate.
/datum/controller/subsystem/persistence/proc/drydockCommission(obj/structure/machinery/computer/ship_commissioning/console, mob/user, faction_uid, new_name, dock_at_beacon = FALSE)
	if(GLOB.drydock_op_active || save_in_progress)
		GLOB.drydock_op_queue += list(list("op" = "commission", "console" = console, "faction_uid" = faction_uid, "new_name" = new_name, "dock_at_beacon" = dock_at_beacon, "user" = user))
		if(user)
			to_chat(user, SPAN_WARNING("[save_in_progress ? "A world save is in progress" : "Too much drydock activity right now"] -- queued (position [length(GLOB.drydock_op_queue)]). You'll be notified when it starts."))
		log_drydock("drydockCommission: [user ? key_name(user) : "SYSTEM"] queued commission (position [length(GLOB.drydock_op_queue)], [save_in_progress ? "world save" : "drydock op"] active).")
		return FALSE
	GLOB.drydock_op_active = TRUE
	GLOB.drydock_op_active_shuttle_id = null
	try
		. = _drydockCommissionRun(console, user, faction_uid, new_name, dock_at_beacon)
	catch(var/exception/e)
		log_drydock_error("drydockCommission: uncaught exception (acting=[user ? key_name(user) : "SYSTEM"]): [e]")
		if(user)
			to_chat(user, SPAN_WARNING("Something went wrong commissioning that ship -- an admin has been notified."))
		log_and_message_admins("drydockCommission: uncaught exception: [e]", user)
	GLOB.drydock_op_active = FALSE
	GLOB.drydock_op_active_shuttle_id = null
	_drydockProcessNextQueued()
	return .

/**
 * Turns a player-built hull into a real, independently-owned drydock
 * shuttle -- the ship_commissioning console's own "Commission" action
 * (ship_commissioning_console.dm) delegates everything here (via
 * drydockCommission()'s thin queue-gate just above). Validates the build
 * (sealed, within the standard footprint centered on a linked active
 * docking_beacon), charges SHIP_COMMISSION_PRICE (the commissioning
 * player's own account, or a faction's with command-rank/CEO/leader
 * approval), captures the built envelope onto a freshly materialized
 * player_built_shuttle Z, and mints a fresh ship_schematic. Unlike
 * drydockBuy(), the ship exists deployed immediately -- it's already
 * physically sitting there the moment it's captured, no separate retrieve
 * step makes sense. The docking beacon and the commissioning console itself
 * are never captured, moved, or wiped -- only the surrounding hull is,
 * explicitly excluded turf-by-turf on both the move and the wipe passes.
 * The captured APC/cabling/atmos machinery are explicitly re-initialized
 * post-capture (area/powernet/pipe-network rebuild) since forceMove() alone
 * doesn't trigger any of that the way a template's own initial map load does.
 *
 * dock_at_beacon: player's choice, not forced either way. FALSE (default)
 * places the ship out in nearby open space via shipPlaceOvermapMarker(),
 * same as any template retrieve. TRUE instead genuinely docks it at the
 * beacon via a real shuttle_datum.attempt_move() call (shuttle.dm) once the
 * hull is captured and the first interior save has run -- attempt_move()'s
 * own shuttle_moved() physically relocates the ship's real turfs (and their
 * area membership) onto the beacon's actual location, exactly like any ship
 * flying itself there under its own power; current_location/status and the
 * marker's overmap nesting all follow as ordinary side effects of that real
 * move, not manual bookkeeping. Either way it's a completely ordinary
 * drydock ship from that point on -- stash still requires being near a
 * secured faction beacon exactly like any other ship
 * (_drydock_secured_beacon_nearby()/faction beacon proximity,
 * _drydockStashRun() below), regardless of which placement was chosen here,
 * and stashing while genuinely docked (dock_at_beacon or otherwise) is
 * refused/force-recalled by _drydockStashRun() -- see its own doc comment.
 */
/datum/controller/subsystem/persistence/proc/_drydockCommissionRun(obj/structure/machinery/computer/ship_commissioning/console, mob/user, faction_uid, new_name, dock_at_beacon = FALSE)
	var/acting = user ? key_name(user) : "SYSTEM"
	if(!istype(console) || !console.anchored)
		return FALSE
	if(!new_name)
		if(user)
			to_chat(user, SPAN_WARNING("Name this shuttle before commissioning it."))
		return FALSE
	if(_drydock_name_taken(new_name))
		if(user)
			to_chat(user, SPAN_WARNING("A ship named '[new_name]' already exists -- pick a different name."))
		log_drydock_warning("drydockCommission: refused -- name '[new_name]' already taken (acting=[acting]).")
		return FALSE

	var/obj/structure/machinery/docking_beacon/beacon = console._valid_linked_beacon()
	if(!beacon)
		if(user)
			to_chat(user, console.linked_beacon \
				? SPAN_WARNING("Linked beacon isn't valid right now -- deactivated, unanchored, or out of range.") \
				: SPAN_WARNING("No beacon linked -- multitool a docking beacon, choose Buffer, then multitool this console to link it."))
		return FALSE
	// Shared with the console's own preview (_get_envelope_corner(),
	// ship_commissioning_console.dm) so they can never disagree about which
	// tiles are covered -- the box sits flush against whichever side of the
	// beacon it's currently facing, not centered on it.
	var/turf/source_corner = console._get_envelope_corner(beacon)
	if(!source_corner)
		if(user)
			to_chat(user, SPAN_WARNING("The build envelope runs off the edge of the map."))
		return FALSE
	var/list/turf/envelope = block(source_corner, locate(source_corner.x + console.build_envelope_x - 1, source_corner.y + console.build_envelope_y - 1, source_corner.z))

	for(var/turf/T in envelope)
		if(isspaceturf(T) || isopenspace(T))
			if(user)
				to_chat(user, SPAN_WARNING("The build envelope isn't fully sealed -- check for gaps to space."))
			log_drydock_warning("drydockCommission: refused -- unsealed envelope near [console] (acting=[acting]).")
			return FALSE

	if(_drydock_envelope_has_occupants(envelope))
		if(user)
			to_chat(user, SPAN_WARNING("Someone (or something's remains) is still inside the build envelope -- clear it before commissioning."))
		log_drydock_warning("drydockCommission: refused -- occupant present in envelope near [console] (acting=[acting]).")
		return FALSE

	// A docking_transponder, facing the exact opposite of this beacon, is
	// required to commission at all -- not just an opt-in nicety for OTHER
	// beacons later (player_dock/is_valid(), docking_beacon.dm). This is
	// what ties all three devices together into one coherent flow: the
	// beacon marks the dock, the console builds/commissions, and the
	// transponder proves the hull's own airlock is actually oriented to
	// meet this specific beacon before it's allowed to become a real ship.
	var/obj/structure/machinery/docking_transponder/transponder = console._valid_linked_transponder(envelope)
	if(!istype(transponder))
		if(user)
			to_chat(user, console.linked_transponder \
				? SPAN_WARNING("Linked docking transponder isn't inside the build envelope -- move it, or link a different one.") \
				: SPAN_WARNING("No docking transponder linked -- multitool one at your airlock, choose Buffer, then multitool this console to link it. It needs to face [beacon]."))
		log_drydock_warning("drydockCommission: refused -- no docking transponder in envelope near [console] (acting=[acting]).")
		return FALSE
	if(turn(transponder.dir, 180) != beacon.dir)
		if(user)
			to_chat(user, SPAN_WARNING("The docking transponder isn't facing [beacon] -- rotate it (multitool) to face the opposite direction."))
		log_drydock_warning("drydockCommission: refused -- transponder facing mismatch near [console] (acting=[acting]).")
		return FALSE

	// A shuttle_control console is the actual minimum drydockAutoFurnish()
	// itself already treats as "the ship can be flown" (persistence_shuttles.dm,
	// see that proc's own doc comment) -- required here too, for the same
	// reason the transponder is: without this check a player could pay
	// SHIP_COMMISSION_PRICE and end up with a ship that has no way to ever
	// be piloted, with no way to find that out until it's too late to fix
	// (the build site is already wiped by the time anyone would notice).
	if(!console._valid_linked_console(envelope))
		if(user)
			to_chat(user, console.linked_shuttle_console \
				? SPAN_WARNING("Linked shuttle control console isn't inside the build envelope -- move it, or link a different one.") \
				: SPAN_WARNING("No shuttle control console linked -- multitool one, choose Buffer, then multitool this console to link it. Without one, this hull could never be flown."))
		log_drydock_warning("drydockCommission: refused -- no shuttle control console in envelope near [console] (acting=[acting]).")
		return FALSE

	// Same reasoning as the console check just above -- the ship's own area
	// (mapped in as part of player_built_shuttle's shell, and preserved as-is
	// by ChangeTurf() during capture below, which only ever swaps turf type,
	// never area membership) has no power distribution at all without an
	// APC. No APC means the engine, life support, lights, and every console
	// aboard -- including the one just confirmed present -- would deploy
	// dark.
	if(!_drydock_envelope_find_apc(envelope))
		if(user)
			to_chat(user, SPAN_WARNING("No APC found in the build envelope -- without one, nothing aboard would have power."))
		log_drydock_warning("drydockCommission: refused -- no APC in envelope near [console] (acting=[acting]).")
		return FALSE

	// Counted, not just presence-only like the checks above -- a real hull
	// needs real thrust, and one engine anywhere in the envelope was never
	// meant to be enough. No particular placement required, just physically
	// present somewhere inside the built hull.
	var/propulsion_count = _drydock_envelope_count_propulsion(envelope)
	if(propulsion_count < SHIP_COMMISSION_MIN_PROPULSION)
		if(user)
			to_chat(user, SPAN_WARNING("Not enough propulsion engines in the build envelope -- need at least [SHIP_COMMISSION_MIN_PROPULSION], found [propulsion_count]."))
		log_drydock_warning("drydockCommission: refused -- only [propulsion_count]/[SHIP_COMMISSION_MIN_PROPULSION] propulsion engines in envelope near [console] (acting=[acting]).")
		return FALSE

	// Presence-only, like the console/APC checks above -- shuttle_control
	// alone only ever offers point-to-point docking, not real overmap
	// flight.
	if(!_drydock_envelope_find_helm(envelope))
		if(user)
			to_chat(user, SPAN_WARNING("No helm console found in the build envelope -- without one, this hull could never actually be piloted on the overmap."))
		log_drydock_warning("drydockCommission: refused -- no helm console in envelope near [console] (acting=[acting]).")
		return FALSE

	// Navigation is buildable/orderable but deliberately NOT required here --
	// only helm and shuttle_control gate commissioning.

	// The decorative propulsion count above is structural only -- a real
	// engine (one that actually populates datum/ship_engine) is a separate,
	// additional requirement. Either a piped nozzle engine or a
	// self-contained ion engine satisfies this -- not both. Checked before
	// the fuel port requirement below, since whether a fuel port is even
	// relevant depends on which engine type was actually found.
	var/obj/structure/machinery/atmospherics/unary/engine/nozzle_engine = _drydock_envelope_find_ship_engine(envelope)
	var/obj/structure/machinery/ion_engine/ion_engine_found = _drydock_envelope_find_ion_engine(envelope)
	if(!nozzle_engine && !ion_engine_found)
		if(user)
			to_chat(user, SPAN_WARNING("No engine found in the build envelope -- without a nozzle engine (piped to a fuel-gas network) or an ion engine (self-contained, needs only power), this hull has nothing to actually burn for thrust."))
		log_drydock_warning("drydockCommission: refused -- no engine of either type in envelope near [console] (acting=[acting]).")
		return FALSE

	// A fuel port is NOT required to commission -- it's a backup/emergency
	// fuel source only (_draw_backup_fuel(), gas_thruster.dm: tops up a
	// nozzle engine's own gas reservoir from a loaded tank once its piped
	// network alone isn't enough to burn). A nozzle engine's real fuel
	// comes from that piped network, and an ion engine needs no fuel at
	// all -- neither ever needed a fuel port just to commission.

	// Fuel/helm/propulsion alone still can't move a hull -- engines_state
	// can only ever be set TRUE via this specific console (engine_control.dm).
	if(!_drydock_envelope_find_engine_control(envelope))
		if(user)
			to_chat(user, SPAN_WARNING("No engine control terminal found in the build envelope -- without one, this hull's engines could never actually be turned on."))
		log_drydock_warning("drydockCommission: refused -- no engine control terminal in envelope near [console] (acting=[acting]).")
		return FALSE

	// Without a sensors terminal + array, crew have no way to see anything
	// outside the hull at all.
	if(!_drydock_envelope_find_sensors_terminal(envelope))
		if(user)
			to_chat(user, SPAN_WARNING("No sensors terminal found in the build envelope -- without one, crew have no way to see anything outside the hull."))
		log_drydock_warning("drydockCommission: refused -- no sensors terminal in envelope near [console] (acting=[acting]).")
		return FALSE
	if(!_drydock_envelope_find_sensor_array(envelope))
		if(user)
			to_chat(user, SPAN_WARNING("No sensor array found in the build envelope -- the sensors terminal has nothing to actually read from."))
		log_drydock_warning("drydockCommission: refused -- no sensor array in envelope near [console] (acting=[acting]).")
		return FALSE

	// Payment -- mirrors drydockBuy()'s own personal/faction split exactly,
	// just at a flat SHIP_COMMISSION_PRICE instead of a template's price.
	// Command rank (2), not the officer-only (1) bar most faction shackle
	// actions use -- this permanently spends a much larger sum.
	var/owner_ckey
	var/owner_char_name
	var/owner_account_number
	if(faction_uid)
		var/op_rank = get_effective_faction_rank(user, faction_uid)
		if(op_rank < 2 && is_faction_ceo(faction_uid, user.ckey, user.real_name))
			op_rank = 2
		if(op_rank < 2 && is_faction_designated_leader(faction_uid, user.ckey, user.real_name))
			op_rank = 2
		if(op_rank < 2)
			if(user)
				to_chat(user, SPAN_WARNING("You need command rank in [get_faction_name(faction_uid)] to commission a ship for the faction."))
			log_drydock_warning("drydockCommission: refused -- [acting] lacks command rank in [faction_uid].")
			return FALSE
		if(!faction_debit(faction_uid, SHIP_COMMISSION_PRICE, "Drydock: commissioned a player-built shuttle"))
			if(user)
				to_chat(user, SPAN_WARNING("Faction account has insufficient funds."))
			return FALSE
	else
		var/obj/item/card/id/ID = user?.GetIdCard()
		if(!ID || !ID.associated_account_number)
			if(user)
				to_chat(user, SPAN_WARNING("No linked bank account."))
			return FALSE
		owner_ckey = user.ckey
		owner_char_name = user.real_name
		owner_account_number = ID.associated_account_number
		var/datum/money_account/acc = SSeconomy.get_account(owner_account_number)
		if(!acc || acc.money < SHIP_COMMISSION_PRICE)
			if(user)
				to_chat(user, SPAN_WARNING("Insufficient funds."))
			return FALSE
		// One deployed personal ship at a time, same constraint retrieve
		// enforces (_drydock_owner_other_deployed_ship()) -- checked here too
		// since commissioning materializes deployed immediately, with no
		// separate retrieve step to catch it later.
		for(var/sid in GLOB.drydock_ships)
			var/datum/drydock_ship/other = GLOB.drydock_ships[sid]
			if(other && !other.stashed && other.owner_ckey == owner_ckey && other.owner_char_name == owner_char_name)
				to_chat(user, SPAN_WARNING("You already have [other.display_name()] deployed -- stash or scuttle it before commissioning another."))
				return FALSE
		acc.adjust_money(-SHIP_COMMISSION_PRICE)

	if(!databaseCheckConnection("drydockCommission"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed -- commission not completed. Contact an admin if funds were deducted."))
		log_drydock_error("drydockCommission: database connection failed (acting=[acting]) -- funds may already be deducted, needs admin attention.")
		return FALSE

	var/template_id = "player_built_shuttle"
	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[template_id]
	if(!template)
		log_drydock_error("drydockCommission: '[template_id]' template missing entirely.")
		return FALSE

	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_drydock_ships (template_id, owner_ckey, owner_char_name, owner_account_number, faction_uid, stashed, purchased_at, title_ckey, title_char_name, title_faction_uid, custom_name) VALUES (:tid, :ckey, :char_name, :account, :faction, 1, NOW(), :t_ckey, :t_char, :t_faction, :custom_name)",
		list("tid" = template_id, "ckey" = owner_ckey, "char_name" = owner_char_name, "account" = owner_account_number, "faction" = faction_uid, "t_ckey" = owner_ckey, "t_char" = owner_char_name, "t_faction" = faction_uid, "custom_name" = new_name)
	)
	q.Execute()
	var/succeeded = databaseCheckQueryResult(q, "drydockCommission insert")
	var/new_id = text2num(q.last_insert_id)
	qdel(q)
	if(!succeeded)
		if(user)
			to_chat(user, SPAN_WARNING("Database error -- commission not completed. Contact an admin if funds were deducted."))
		log_drydock_error("drydockCommission: DB insert failed (acting=[acting]).")
		return FALSE

	var/purchased_at
	var/datum/db_query/pq = SSdbcore.NewQuery("SELECT purchased_at FROM ss13_drydock_ships WHERE shuttle_id = :id", list("id" = new_id))
	pq.Execute()
	if(databaseCheckQueryResult(pq, "drydockCommission purchased_at read-back") && pq.NextRow())
		purchased_at = pq.item[1]
	qdel(pq)

	var/datum/drydock_ship/DS = new()
	DS.shuttle_id  = new_id
	DS.template_id = template_id
	DS.owner_ckey  = owner_ckey
	DS.owner_char_name = owner_char_name
	DS.owner_account_number = owner_account_number
	DS.faction_uid = faction_uid
	DS.stashed     = FALSE // materializes immediately below -- already physically exists, no separate retrieve step makes sense
	DS.purchased_at = purchased_at
	DS.title_ckey = owner_ckey
	DS.title_char_name = owner_char_name
	DS.title_faction_uid = faction_uid
	DS.custom_name = new_name
	GLOB.drydock_ships["[new_id]"] = DS

	// CENTRAL_SYNC_SHIPS -- see drydockBuy()'s matching block and this
	// file's "CENTRAL SHIP SYNC" section; both gated inside their own procs.
	if(GLOB.config.central_sql_enabled && GLOB.config.central_server_id)
		DS.global_ship_id = "[GLOB.config.central_server_id]:[new_id]"
		var/datum/db_query/gq = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET global_ship_id = :gsid WHERE shuttle_id = :id",
			list("gsid" = DS.global_ship_id, "id" = new_id)
		)
		gq.Execute()
		qdel(gq)
		_shipCentralCreateWriteThrough(DS)

	// Materialize -- mirrors _drydockRetrieveRun()'s own Z-provisioning
	// exactly, just sourced from the live capture below instead of a saved
	// interior.
	var/scope = "ship:d:[new_id]"
	var/pool_z = SSpersistence.acquireReusableZ()
	var/new_z
	var/bounds
	SSair.can_fire = FALSE
	// Same per-instance naming the retrieve path uses -- a commissioned hull
	// is built from the same shared shell template as every other one, so
	// without this the second commission collides exactly as a second
	// retrieve would. See GLOB.drydock_loading_suffix.
	GLOB.drydock_loading_suffix = "#[new_id]"
	GLOB.drydock_loading_areas = list()
	// See GLOB.drydock_loading_wall_hash_seed's own doc comment -- keyed on
	// new_id (stable for the ship's whole life) rather than the z this load
	// is about to assign, so reinforced walls look the same on every future
	// retrieve as they do right now at commission.
	GLOB.drydock_loading_wall_hash_seed = "[new_id]"
	if(pool_z)
		bounds = template.load_into_z(pool_z, TRUE)
		new_z = pool_z
	else
		var/z_before = world.maxz
		bounds = template.load_new_z(FALSE, TRUE)
		new_z = z_before + 1
	GLOB.drydock_loading_suffix = null
	GLOB.drydock_loading_wall_hash_seed = null
	// Cleared only AFTER the load returns -- init_shuttles() runs inside it,
	// and /datum/shuttle/New() reads this list to bind its own areas.
	GLOB.drydock_loading_areas = list()
	SSair.can_fire = TRUE
	if(!bounds)
		GLOB.drydock_ships -= "[new_id]"
		if(pool_z)
			SSpersistence.poolReusableZ(pool_z)
		if(user)
			to_chat(user, SPAN_WARNING("Failed to materialize shuttle."))
		log_drydock_error("drydockCommission: template load failed for '[template_id]', shuttle_id=[new_id][pool_z ? " (pooled z=[pool_z])" : ""].")
		return FALSE
	// Parity with retrieve's own line -- says outright whether z reuse actually
	// happened, so "the z count keeps climbing" is answerable from the log
	// instead of by inspection.
	log_drydock("drydockCommission: shuttle_id=[new_id] materialized at z=[new_z] ([pool_z ? "pooled" : "fresh"]) for template '[template_id]'.")

	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[new_z]"]
	if(!istype(marker))
		GLOB.drydock_ships -= "[new_id]"
		log_drydock_error("drydockCommission: no overmap marker found at loaded z=[new_z] for shuttle_id=[new_id].")
		return FALSE

	// _drydockRetrieveRun() sets this immediately after materializing too
	// (its own DS.z = new_z) -- commission was missing it entirely. Every
	// z-keyed lookup downstream that reads DS.z directly instead of the
	// local new_z var (_drydock_ship_at(), used by
	// _drydock_full_access_check() -- the sole ownership gate for personal
	// boarding/stashing -- and _drydock_ship_sector() itself) was silently
	// operating on a null DS.z for any ship that had only ever been
	// commissioned, never stashed and retrieved even once. That's exactly
	// why a freshly-commissioned ship behaved as if it "didn't exist" for
	// boarding/stashing regardless of actual distance -- not a distance bug
	// at all. overmap_x/overmap_y are set later, once the marker's real
	// final position (post dock_at_beacon or its fallback) is known.
	DS.z = new_z

	var/obj/effect/overmap/visitable/target_sector = GLOB.map_sectors["[GET_Z(console)]"]
	if(!dock_at_beacon)
		shipPlaceOvermapMarker(marker, target_sector, DRYDOCK_SHIP_PLACEMENT_RADIUS)
	// dock_at_beacon's actual docking happens much further below, after the
	// build envelope is captured onto this Z and the first interior save has
	// run -- attempt_move() (shuttle.dm) needs shuttle_area to hold the ship's
	// real, just-captured hull before it has anything meaningful to relocate,
	// and the first save should capture the ship whole on its own home Z
	// before it physically leaves that Z. See the dock_at_beacon block near
	// the end of this proc, right after shipInteriorSave().

	var/datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum = _drydock_shuttle_of(marker)
	if(istype(shuttle_datum))
		// Commission always materializes a player-built ship, by definition --
		// read by player_dock/is_valid() (docking_beacon.dm) to decide whether
		// a beacon's own player-built-specific max footprint applies here.
		shuttle_datum.player_built = TRUE
		// Every player-built shuttle shares this one template/shuttle name --
		// same per-instance uniqueness rename _drydockRetrieveRun() does, or
		// a second commission/retrieve collides hard (/datum/shuttle/New()).
		var/old_shuttle_name = shuttle_datum.name
		var/new_shuttle_name = "[old_shuttle_name] #[new_id]"
		if(old_shuttle_name != new_shuttle_name && SSshuttle.shuttles[old_shuttle_name] == shuttle_datum)
			SSshuttle.shuttles -= old_shuttle_name
			shuttle_datum.name = new_shuttle_name
			SSshuttle.shuttles[new_shuttle_name] = shuttle_datum
			marker.shuttle = new_shuttle_name
			// Without this the ship's own home landmark stays filed under the
			// pre-rename key and can never be offered as a destination again --
			// see _drydock_rekey_ship_waypoints().
			_drydock_rekey_ship_waypoints(marker, old_shuttle_name, new_shuttle_name)

	marker.name = DS.display_name()

	GLOB.persistence_ship_z["[new_z]"] = scope
	GLOB.zone_security_by_z["[new_z]"] = DS.faction_uid ? ZONE_MEDSEC : ZONE_NULLSEC
	zone_security_update_overmap()
	// Every cached copy of this ship's name in one place -- marker, z-level
	// label and any live schematic. Setting marker.name inline above is not
	// enough on its own: the z-level would otherwise keep the TEMPLATE's name
	// ("Player-Built Shuttle") for the ship's entire life.
	_drydockRefreshDisplayedName(DS)

	// The actual capture -- move the player's built envelope onto the fresh
	// Z, then wipe the build site clean. The beacon and this console are
	// never touched, by specific object reference (not type), on either pass.
	var/turf/dest_corner = locate(bounds[MAP_MINX], bounds[MAP_MINY], new_z)
	// The blank shell template's own mapped room is a fixed 9x9 -- a
	// player-configured envelope bigger than that (console.build_envelope_x/y)
	// extends past the template's own painted area into the rest of
	// that dedicated Z, which is fine (ChangeTurf() below freely overwrites
	// whatever base turf is there regardless) as long as those turfs actually
	// exist on the Z at all. Confirm that explicitly rather than trusting it --
	// losing part of a built hull silently because a turf resolved null would
	// be exactly the kind of data loss this session already had to fix once.
	if(dest_corner.x + console.build_envelope_x - 1 > world.maxx || dest_corner.y + console.build_envelope_y - 1 > world.maxy)
		DS.stashed = TRUE
		if(user)
			to_chat(user, SPAN_WARNING("Commission failed -- this build envelope size doesn't fit on a fresh ship z. Contact an admin."))
		log_drydock_error("drydockCommission: build envelope [console.build_envelope_x]x[console.build_envelope_y] doesn't fit on new_z=[new_z] (dest_corner=[dest_corner.x],[dest_corner.y], world max=[world.maxx],[world.maxy]).")
		return FALSE
	var/list/translation = get_turf_translation(source_corner, dest_corner, envelope)
	var/obj/structure/machinery/computer/shuttle_control/captured_console
	var/obj/structure/machinery/power/apc/captured_apc
	var/list/obj/structure/cable/captured_cables = list()
	var/list/obj/structure/machinery/atmospherics/captured_atmos_machines = list()
	// Helm/navigation consoles -- built on the STATION side first,
	// so their own Initialize() only ever sees the station's sector (not a
	// /obj/effect/overmap/visitable/ship, per ship/attempt_hook_up()'s own
	// type check), landing them in SSshuttle.lonely_ship_computers rather
	// than actually linking. sync_linked() (ship.dm) DOES self-heal this
	// lazily the first time a player opens the console's own UI -- but
	// every other captured object here gets rebound proactively instead of
	// waiting on something else to trigger it, so do the same for these.
	var/list/obj/structure/machinery/computer/ship/captured_ship_computers = list()
	// Self-contained ion engines (ion_thruster.dm) -- same "built station-side
	// before the ship existed, silently never links" gap the nozzle engine
	// (Part 38) and ship computers above already needed fixing for.
	var/list/obj/structure/machinery/ion_engine/captured_ion_engines = list()
	for(var/turf/source_turf in translation)
		var/turf/dest_turf = translation[source_turf]
		if(!dest_turf)
			continue
		if((beacon in source_turf) || (console in source_turf))
			continue
		dest_turf.ChangeTurf(source_turf.type)
		for(var/atom/movable/M in source_turf)
			if(ismob(M) || istype(M, /obj/effect) || M == beacon || M == console)
				continue
			M.forceMove(dest_turf)
			if(istype(M, /obj/structure/machinery/computer/shuttle_control) && !captured_console)
				captured_console = M
			else if(istype(M, /obj/structure/machinery/power/apc) && !captured_apc)
				captured_apc = M
			else if(istype(M, /obj/structure/cable))
				captured_cables += M
			else if(istype(M, /obj/structure/machinery/atmospherics))
				captured_atmos_machines += M
			else if(istype(M, /obj/structure/machinery/computer/ship))
				captured_ship_computers += M
			else if(istype(M, /obj/structure/machinery/ion_engine))
				captured_ion_engines += M

	// A player may have claimed the build site into a custom area via the
	// station blueprints tool before building here (blueprints.dm,
	// is_blueprint_area = TRUE) -- ChangeTurf() below only ever swaps turf
	// TYPE, never area membership, so that claim would otherwise survive
	// the wipe indefinitely, straggling behind with the exact same
	// footprint the (now-departed) hull just vacated -- a real risk of
	// overlap if another ship is later built at the same physical spot.
	// Mirrors remove_area()/modify_area()'s own revert-to-background
	// pattern (blueprints.dm) exactly, just invoked from here too.
	var/list/area/wiped_blueprint_areas = list()
	for(var/turf/source_turf in envelope)
		if((beacon in source_turf) || (console in source_turf))
			continue
		var/area/current_area = source_turf.loc
		if(istype(current_area) && current_area.is_blueprint_area)
			wiped_blueprint_areas |= current_area
			source_turf.change_area(source_turf.loc, source_turf.blueprint_prior_area || locate(world.area))
			source_turf.blueprint_prior_area = null
		source_turf.ChangeTurf(get_base_turf_by_area(source_turf))
	for(var/area/A in wiped_blueprint_areas)
		if(!(locate(/turf) in A))
			qdel(A)

	// The wipe above reverts these turfs to their area's base turf, which on a
	// hub/away-site build site is unsimulated space -- and BOTH turf save
	// sweeps only ever iterate /turf/simulated, so none of these will ever be
	// visited again to emit the "reverted to default, delete the row" signal
	// _turfsCollectOne() normally produces. Without this, any row saved while
	// the hull still stood survives forever and turfsInitialize() rebuilds the
	// whole floor/wall layout at the abandoned build site on the next boot.
	SSpersistence.turfsForget(envelope)

	// Anchor the ship's own home landmark to its transponder rather than
	// leaving it wherever the shell template mapped it (dead centre of the
	// room, for player_built_shuttle) -- see
	// _drydock_reposition_ship_landmark()'s own doc comment for why a
	// centre-anchored landmark misaligns every future dock by half a hull.
	_drydock_reposition_ship_landmark(marker, shuttle_datum, "drydockCommission (shuttle_id=[new_id])")

	// This sector was created at runtime, so initialize_sectors() never ran for
	// it and the waypoint tags populate_sector_objects() queued -- the ship's
	// own "Open Space" home landmark among them -- would otherwise never become
	// real destinations, leaving the ship able to dock but never undock. See
	// register_sector_waypoints() (controllers/subsystems/processing/shuttle.dm).
	SSshuttle.register_sector_waypoints(marker)

	// Hook up whichever shuttle_control console the player actually built,
	// same as drydockAutoFurnish() does for its own auto-spawned one.
	if(istype(captured_console) && istype(shuttle_datum))
		SSshuttle.lonely_shuttle_computers -= captured_console
		captured_console.shuttle_tag = marker.shuttle
		shuttle_datum.shuttle_computers += captured_console

	// Same idea for any helm/navigation console the player built --
	// re-resolve its link now that it's sitting on the ship's own z, rather
	// than leaving it to self-heal lazily the first time someone opens its
	// UI (sync_linked(), ship.dm). SSshuttle.lonely_ship_computers is the
	// separate (singular "ship") retry list these consoles' own Initialize()
	// queued themselves onto when first built station-side, before ever
	// being captured onto a real ship z.
	for(var/obj/structure/machinery/computer/ship/captured_ship_computer in captured_ship_computers)
		SSshuttle.lonely_ship_computers -= captured_ship_computer
		captured_ship_computer.sync_linked()
		// Re-derive NOPOWER against its new surroundings -- same reason as
		// the captured airpump's own power_change() call below: nothing else
		// recomputes this after a forceMove(), so a console built in an
		// unpowered area station-side would otherwise stay stuck reporting
		// no power indefinitely once captured here.
		captured_ship_computer.power_change()

	// Re-bind the captured APC to its new surroundings -- APC/Initialize()
	// (apc.dm) only ever sets area/area.apc/its own "[area] APC" name ONCE,
	// at creation, and forceMove() above never re-runs that. Left alone, a
	// captured APC would keep silently pointing at whatever station-side
	// area it was originally built in. Name the ship's own area after it
	// while we're here, so the APC's own name (derived from its area's
	// display name) reads as the ship, not a leftover station room name.
	var/area/ship_area = get_area(dest_corner)
	if(istype(ship_area))
		ship_area.name = new_name
	if(istype(captured_apc) && istype(ship_area))
		captured_apc.area = ship_area
		ship_area.apc = captured_apc
		captured_apc.name = "[get_area_display_name(ship_area)] APC"
		captured_apc.update_icon()
		captured_apc.connect_to_network()

	// Same reasoning as the APC above, for whatever cabling the player laid
	// down -- init_atoms() (map_template.dm) runs this for a template's own
	// initial load, but capture here never went through that pass at all.
	if(length(captured_cables))
		SSmachinery.setup_powernets_for_cables(captured_cables)

	// Same again for atmos machinery (vents, scrubbers, pipes) -- atmos_init()
	// + build_network() is what actually forms pipe networks
	// (setup_atmos_machinery(), machinery.dm), also normally only run once
	// by a template's own initial map load. Quiet -- this isn't a real
	// admin-notice-worthy "initializing atmos machinery" event, just a
	// routine part of every commission.
	if(length(captured_atmos_machines))
		// Engine nozzles specifically: atmos_init() (gas_thruster.dm) bails
		// immediately if node is already set (`if(node) return`), so a
		// nozzle captured with a stale node from its old station-side
		// position would never re-scan for the ship's own actual pipe
		// layout -- same reasoning as _link_to_airpump()'s node=null reset
		// just above, ported to this type specifically. Also re-attempt ship
		// registration here -- a nozzle built before the ship existed never
		// found one to register into at its own Initialize().
		for(var/obj/structure/machinery/atmospherics/unary/engine/captured_engine in captured_atmos_machines)
			captured_engine.node = null
#ifdef DRYDOCK_ENGINE_DIAGNOSTICS
			// check_ownership() (landable.dm) matches on the object's AREA, and
			// the capture loop above only ever ChangeTurf()s turf TYPE -- never
			// area membership. Any hull captured outside the shell template's
			// own mapped room therefore sits in the wrong area and can never
			// register. Log the area each engine actually landed in.
			log_debug("ENGINE DIAG: commission captured nozzle [captured_engine] -> area [get_area(captured_engine)] at ([captured_engine.x],[captured_engine.y],[captured_engine.z]).")
#endif
			captured_engine.sync_ship_registration()
		SSmachinery.setup_atmos_machinery(captured_atmos_machines, TRUE)

	// Same registration gap as the nozzle engines above, for any self-contained
	// ion engine the player built -- plus a power_change() re-derive, same
	// reasoning as the captured ship computers' own call above (a machine
	// built in a station-side area never recomputes NOPOWER after being
	// forceMove()'d into the ship's own area here).
	for(var/obj/structure/machinery/ion_engine/captured_ion_engine in captured_ion_engines)
#ifdef DRYDOCK_ENGINE_DIAGNOSTICS
		log_debug("ENGINE DIAG: commission captured ion engine [captured_ion_engine] -> area [get_area(captured_ion_engine)] at ([captured_ion_engine.x],[captured_ion_engine.y],[captured_ion_engine.z]).")
#endif
		captured_ion_engine.sync_ship_registration()
		captured_ion_engine.power_change()

	// refresh_fuel_ports_list() (overmap_shuttle.dm) only ever runs once, at
	// the shuttle datum's own New() -- which for a commissioned ship fires
	// at blank-shell template load time, before the player's own built fuel
	// port has been captured onto this z at all. Without this, fuel_ports
	// stays permanently empty and the engine's own backup-fuel draw
	// (check_fuel(), gas_thruster.dm) has nothing to ever find. Re-run now
	// that the fuel port has actually landed here.
	if(istype(shuttle_datum))
		shuttle_datum.refresh_fuel_ports_list()

	DS.ready = TRUE

	if(DS.faction_uid)
		_sweep_unassigned_objects_for_faction(list("[new_z]"), DS.faction_uid)
	else
		_sweep_unassigned_crew(list("[new_z]"))
	_drydock_start_periodic_sweep()

	// First save -- captures the just-built interior in place immediately,
	// same shape as any other ship's periodic/stash save, so a crash right
	// after commissioning still has something to recover from. Deliberately
	// before the dock_at_beacon move just below -- this baseline should
	// reflect the ship whole on its own home Z, not mid-relocation.
	shipInteriorSave(new_z, scope)

	// dock_at_beacon -- a REAL move, not the marker-only shortcut this used
	// to be. attempt_move() (shuttle.dm) -> shuttle_moved() physically
	// translates the ship's just-captured hull (shuttle_area, now real)
	// onto the beacon's actual turfs and reassigns their area to match --
	// the ship is genuinely, physically docked there afterward, not just
	// flagged as such. current_location/status and the marker's own overmap
	// nesting are all set as normal side effects of that real move
	// (shuttle_moved() itself, then the reactive on_shuttle_jump() ->
	// on_landing() chain, landable.dm) -- no manual bookkeeping needed here.
	if(dock_at_beacon)
		var/obj/effect/shuttle_landmark/beacon_landmark = SSshuttle.registered_shuttle_landmarks[beacon.landmark_tag]
		// reason_out -- see is_valid()'s own doc comment (landmarks.dm) --
		// turns a failed dock attempt into a concrete, actionable reason
		// instead of the generic fallback message.
		var/list/dock_refusal_reason = list()
		var/docked_ok = istype(beacon_landmark) && istype(shuttle_datum) && beacon_landmark.is_valid(shuttle_datum, dock_refusal_reason) && shuttle_datum.attempt_move(beacon_landmark)
		if(docked_ok)
			log_drydock("drydockCommission: shuttle_id=[new_id] docked directly at beacon '[beacon.landmark_tag]' via attempt_move().")
		else
			// Either the beacon's own landmark vanished out from under us
			// mid-commission (deactivated/deconstructed), or is_valid()
			// refused for a specific, now-captured reason (collision,
			// footprint, facing mismatch, raid-block, faction-restriction) --
			// attempt_move() never half-applies on refusal, so falling back
			// is always safe.
			// Split the single "deactivated/deconstructed" catch-all into the
			// three genuinely distinct states it could actually be -- turns
			// the next occurrence into a concrete fact instead of a guess.
			var/reason_text
			if(istype(beacon_landmark))
				reason_text = length(dock_refusal_reason) ? jointext(dock_refusal_reason, "; ") : "attempt_move() refused for an unlogged reason"
			else if(QDELETED(beacon))
				reason_text = "the beacon machine itself was deconstructed/destroyed mid-commission"
			else if(!beacon.beacon_active)
				reason_text = "the beacon was deactivated (screwdriver) mid-commission"
			else
				reason_text = "the beacon is still active but its landmark_tag '[beacon.landmark_tag]' has no matching registered landmark -- registration bug, needs admin attention"
			log_drydock_warning("drydockCommission: dock_at_beacon requested but real docking failed for shuttle_id=[new_id] -- [reason_text] -- falling back to nearby placement.")
			shipPlaceOvermapMarker(marker, target_sector, DRYDOCK_SHIP_PLACEMENT_RADIUS)
			if(user)
				to_chat(user, SPAN_WARNING("Commissioned, but the ship couldn't actually dock at the beacon -- it's nearby in open space instead. Fly it in manually."))
				to_chat(user, SPAN_WARNING("Reason: [reason_text]"))

	// The initial INSERT above always writes stashed=1 (matching drydockBuy()'s
	// shape, correct for a freshly-bought-but-not-yet-retrieved template ship)
	// -- but a commissioned ship materializes immediately, so the row needs
	// correcting to its real, final state now that dock_at_beacon (if any) has
	// resolved one way or the other. Mirrors _drydockRetrieveRun()'s own
	// equivalent UPDATE exactly (persistence_shuttles.dm, its DS.z/overmap_x/
	// overmap_y assignment right after placement) -- without this, the DB row
	// stayed permanently wrong (stashed=1, z/overmap_x/overmap_y all NULL)
	// until the ship's first real stash, so a restart before that ever
	// happened reloaded it as if it had never been retrieved: Retrieve AND
	// Stash both greyed out, name reverted to the generic template fallback.
	DS.overmap_x = marker.x
	DS.overmap_y = marker.y
	if(databaseCheckConnection("drydockCommission position update"))
		var/datum/db_query/uq = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET stashed=0, z=:z, overmap_x=:x, overmap_y=:y WHERE shuttle_id = :id",
			list("z" = DS.z, "x" = marker.x, "y" = marker.y, "id" = new_id)
		)
		uq.Execute()
		if(!databaseCheckQueryResult(uq, "drydockCommission position update"))
			log_drydock_error("drydockCommission: DB position update failed for shuttle_id=[new_id] -- ledger row now disagrees with live state until next save.")
		qdel(uq)

	if(user)
		var/obj/item/ship_schematic/schematic = new(get_turf(user))
		schematic.shuttle_id = new_id
		schematic.bound_purchased_at = purchased_at
		schematic.refresh_name()
		user.put_in_hands(schematic)
		to_chat(user, SPAN_GOOD("[DS.display_name()] commissioned -- schematic in hand."))
	log_and_message_admins("commissioned a player-built shuttle '[new_name]' (#[new_id])[faction_uid ? " for faction [get_faction_name(faction_uid)]" : ""].", user)
	log_drydock("drydockCommission: [acting] commissioned shuttle_id=[new_id] ('[new_name]').")
	return TRUE

// ============================================================
// QUEUE  shared serialization for drydockRetrieve()/drydockStash()
// ============================================================

/// Pops the next queued retrieve/stash request (if any) and re-invokes the
/// matching public proc for it -- which re-runs every permission/proximity/
/// ownership check fresh, so a stale request (the player moved away,
/// disconnected, or no longer owns the ship) just fails its own normal
/// checks naturally. Deferred via addtimer(0) rather than called directly
/// so a long queue drains as a chain of separate, shallow calls instead of
/// growing one deep recursive stack.
/datum/controller/subsystem/persistence/proc/_drydockProcessNextQueued()
	if(!length(GLOB.drydock_op_queue))
		return
	var/list/req = GLOB.drydock_op_queue[1]
	GLOB.drydock_op_queue.Cut(1, 2)
	addtimer(CALLBACK(src, PROC_REF(_drydockRunQueuedRequest), req), 0)

/datum/controller/subsystem/persistence/proc/_drydockRunQueuedRequest(list/req)
	var/mob/user = req["user"]
	if(user)
		to_chat(user, SPAN_GOOD("Your [req["op"]] is now processing..."))
	if(req["op"] == "retrieve")
		drydockRetrieve(req["shuttle_id"], req["anchor"], req["from_turf"], user)
	else if(req["op"] == "commission")
		drydockCommission(req["console"], user, req["faction_uid"], req["new_name"], req["dock_at_beacon"])
	else
		drydockStash(req["shuttle_id"], user)

// ============================================================
// RETRIEVE  materialize: fresh Z, marker placed near the docking beacon
// ============================================================

/// A faction-owned ship retrieves only near its OWN faction's faction_beacon
/// (anchor, required, faction_uid must match). A personally-owned ship
/// ignores anchor entirely and retrieves directly into whatever sector
/// from_turf (the retrieving computer's own position) is currently in --
/// still requires SOME active med-sec-or-better faction beacon nearby
/// (any faction's, not necessarily the retriever's own), matching the same
/// rule drydockStash() already enforced for personal ships
/// (_drydock_secured_beacon_nearby()) -- can't retrieve in raw unclaimed
/// space just because a modular computer is present. See the file header
/// for the full rationale.
///
/// Public entry point -- a thin queue-gate in front of _drydockRetrieveRun()
/// (below), which does the actual work. Serializes with drydockStash()
/// server-wide via GLOB.drydock_op_active/drydock_op_queue so concurrent
/// heavy Z-loads from different players don't stack lag on top of each
/// other; a request arriving while another is active gets queued and
/// processed once its turn comes, rather than running immediately.
/datum/controller/subsystem/persistence/proc/drydockRetrieve(shuttle_id, obj/structure/machinery/faction_beacon/anchor, turf/from_turf, mob/user)
	// save_in_progress: never start a Z-level load while a world save is
	// mid-walk -- same corruption class as saving mid-stash, opposite order.
	// The save's own completion (fire()/force_persistence_save()) drains
	// this queue, so requests parked here don't wait on another drydock op.
	if(GLOB.drydock_op_active || save_in_progress)
		GLOB.drydock_op_queue += list(list("op" = "retrieve", "shuttle_id" = shuttle_id, "anchor" = anchor, "from_turf" = from_turf, "user" = user))
		if(user)
			to_chat(user, SPAN_WARNING("[save_in_progress ? "A world save is in progress" : "Too much drydock activity right now"] -- queued (position [length(GLOB.drydock_op_queue)]). You'll be notified when it starts."))
		log_drydock("drydockRetrieve: [user ? key_name(user) : "SYSTEM"] queued retrieve of shuttle_id=[shuttle_id] (position [length(GLOB.drydock_op_queue)], [save_in_progress ? "world save" : "drydock op"] active).")
		return FALSE
	GLOB.drydock_op_active = TRUE
	GLOB.drydock_op_active_shuttle_id = shuttle_id
	try
		. = _drydockRetrieveRun(shuttle_id, anchor, from_turf, user)
	catch(var/exception/e)
		log_drydock_error("drydockRetrieve: uncaught exception retrieving shuttle_id=[shuttle_id] (acting=[user ? key_name(user) : "SYSTEM"]): [e] at [e.file]:[e.line]")
		if(user)
			to_chat(user, SPAN_WARNING("Something went wrong retrieving that ship -- an admin has been notified."))
		log_and_message_admins("drydockRetrieve: uncaught exception retrieving shuttle_id=[shuttle_id]: [e] at [e.file]:[e.line]", user)
	GLOB.drydock_op_active = FALSE
	GLOB.drydock_op_active_shuttle_id = null
	_drydockProcessNextQueued()
	return .

/// Returns the OTHER currently-deployed drydock ship personally owned by the
/// same (ckey, char_name) pair as candidate, or null if there isn't one (or
/// candidate isn't personally owned at all -- faction ships are exempt from
/// this check). Excludes candidate itself. Enforces "one deployed personal
/// vessel at a time" in _drydockRetrieveRun() below -- without this, a player
/// owning more than one vessel could deploy all of them simultaneously.
/datum/controller/subsystem/persistence/proc/_drydock_owner_other_deployed_ship(datum/drydock_ship/candidate)
	if(!candidate.owner_ckey)
		return null
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/other = GLOB.drydock_ships[sid]
		if(other && other != candidate && !other.stashed && other.owner_ckey == candidate.owner_ckey && other.owner_char_name == candidate.owner_char_name)
			return other
	return null

/datum/controller/subsystem/persistence/proc/_drydockRetrieveRun(shuttle_id, obj/structure/machinery/faction_beacon/anchor, turf/from_turf, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_drydock("drydockRetrieve: [acting] attempting to retrieve shuttle_id=[shuttle_id].")

	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
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
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to retrieve this ship."))
		log_drydock_warning("drydockRetrieve: refused -- [acting] lacks permission for shuttle_id=[shuttle_id] (owner=[DS.owner_ckey || "none"], faction=[DS.faction_uid || "none"]).")
		return FALSE
	if(!DS.custom_name && !check_rights(R_ADMIN, 0, user))
		if(user)
			to_chat(user, SPAN_WARNING("Rename this ship before retrieving it -- use the schematic's Rename Ship option."))
		log_drydock_warning("drydockRetrieve: refused -- shuttle_id=[shuttle_id] hasn't been renamed from its default yet (acting=[acting]).")
		return FALSE
	// The old "a ship of this class is already deployed" refusal lived here.
	// It existed only because shuttle datum names and their derived landmark
	// tags were per-TEMPLATE; GLOB.drydock_loading_suffix now makes both
	// per-instance at load time, so any number of hulls of one class can be
	// deployed at once. The per-OWNER limit immediately below is unrelated and
	// still applies.
	var/datum/drydock_ship/other_deployed = _drydock_owner_other_deployed_ship(DS)
	if(other_deployed)
		if(user)
			to_chat(user, SPAN_WARNING("You already have [other_deployed.display_name()] deployed -- stash or scuttle it before retrieving another."))
		log_drydock_warning("drydockRetrieve: refused -- owner [DS.owner_ckey]|[DS.owner_char_name] already has shuttle_id=[other_deployed.shuttle_id] deployed (acting=[acting]).")
		return FALSE
	if(GLOB.drydock_max_deployed_ships > 0)
		var/currently_deployed = 0
		for(var/sid in GLOB.drydock_ships)
			var/datum/drydock_ship/other = GLOB.drydock_ships[sid]
			if(other && !other.stashed)
				currently_deployed++
		if(currently_deployed >= GLOB.drydock_max_deployed_ships)
			if(user)
				to_chat(user, SPAN_WARNING("Too many ships are currently in play -- try again later. Consider using the Personal Travel program instead."))
			log_drydock_warning("drydockRetrieve: refused -- deployed ship cap ([GLOB.drydock_max_deployed_ships]) reached (acting=[acting]).")
			return FALSE

	var/obj/effect/overmap/visitable/target_sector
	var/placement_radius
	if(DS.faction_uid)
		if(istype(anchor) && (anchor.faction_uid == DS.faction_uid || check_rights(R_ADMIN, 0, user)))
			target_sector = GLOB.map_sectors["[GET_Z(anchor)]"]
			// Capped, not passed through raw -- security_radius is a multi-purpose
			// value (zone-security coverage, Personal Travel leap eligibility) that
			// can legitimately exceed the boarding proximity threshold; only the
			// PLACEMENT distance used here needs to stay within it.
			placement_radius = min(anchor.security_radius, DRYDOCK_SHIP_PLACEMENT_RADIUS)
		else if(istype(anchor) && anchor.faction_uid != DS.faction_uid)
			if(user)
				to_chat(user, SPAN_WARNING("This beacon belongs to [get_faction_name(anchor.faction_uid)], not [get_faction_name(DS.faction_uid)]."))
			log_drydock_warning("drydockRetrieve: refused -- faction beacon belongs to [anchor.faction_uid], not [DS.faction_uid] (acting=[acting]).")
			return FALSE
		else if(_drydock_near_centcom_depot(GLOB.map_sectors["[from_turf.z]"]))
			// CentCom/the Frontier Beacon Depot has no player-buildable
			// faction beacon of its own -- proximity to its fixed marker
			// position counts as valid drydock range regardless, same as
			// _drydock_secured_beacon_nearby() already grants personal ships.
			target_sector = GLOB.map_sectors["[from_turf.z]"]
			placement_radius = DRYDOCK_SHIP_PLACEMENT_RADIUS
		else
			if(user)
				to_chat(user, SPAN_WARNING("No faction beacon in range."))
			log_drydock_warning("drydockRetrieve: refused -- no faction beacon anchor provided for faction-owned shuttle_id=[shuttle_id] (acting=[acting]).")
			return FALSE
	else
		if(!from_turf)
			if(user)
				to_chat(user, SPAN_WARNING("No location to retrieve from."))
			log_drydock_warning("drydockRetrieve: refused -- no from_turf provided for personal shuttle_id=[shuttle_id] (acting=[acting]).")
			return FALSE
		target_sector = GLOB.map_sectors["[from_turf.z]"]
		if(!istype(target_sector))
			if(user)
				to_chat(user, SPAN_WARNING("You must be within a mapped sector to retrieve a ship."))
			log_drydock_warning("drydockRetrieve: refused -- from_turf z=[from_turf.z] has no overmap sector for personal shuttle_id=[shuttle_id] (acting=[acting]).")
			return FALSE
		if(!_drydock_secured_beacon_nearby(target_sector, null))
			if(user)
				to_chat(user, SPAN_WARNING("You must be near a secured (med-sec or better) faction beacon to retrieve a ship."))
			log_drydock_warning("drydockRetrieve: refused -- shuttle_id=[shuttle_id] not near a secured beacon (acting=[acting]).")
			return FALSE
		placement_radius = DRYDOCK_SHIP_PLACEMENT_RADIUS
	if(!istype(target_sector))
		if(user)
			to_chat(user, SPAN_WARNING("No valid sector to retrieve into."))
		log_drydock_warning("drydockRetrieve: refused -- could not resolve a target sector for shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
	if(!template)
		if(user)
			to_chat(user, SPAN_WARNING("This ship's template is no longer available."))
		log_drydock_error("drydockRetrieve: template '[DS.template_id]' no longer registered for shuttle_id=[shuttle_id].")
		return FALSE

	// Belt-and-braces recovery copy in case the DB write below fails
	// mid-operation -- see the admin "Restore Ship Backup" verb.
	if(!databaseCheckConnection("drydockRetrieve backup"))
		log_drydock_error("drydockRetrieve: database connection failed backing up shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	// Every refusal above has already returned -- this retrieval is
	// actually going to happen from here on.
	if(user)
		play_announcer_sound_priority(user, 'sound/AI/announcements/retrieving_ship_please_wait.ogg')
	var/datum/db_query/bq = SSdbcore.NewQuery(
		{"INSERT INTO ss13_drydock_ships_backup (shuttle_id, template_id, owner_ckey, owner_char_name, faction_uid, purchased_at)
		SELECT shuttle_id, template_id, owner_ckey, owner_char_name, faction_uid, purchased_at FROM ss13_drydock_ships WHERE shuttle_id = :id
		ON DUPLICATE KEY UPDATE template_id=VALUES(template_id), owner_ckey=VALUES(owner_ckey), owner_char_name=VALUES(owner_char_name), faction_uid=VALUES(faction_uid), purchased_at=VALUES(purchased_at), backed_up_at=NOW()"},
		list("id" = shuttle_id)
	)
	bq.Execute()
	if(!databaseCheckQueryResult(bq, "drydockRetrieve backup"))
		log_drydock_error("drydockRetrieve: backup write failed for shuttle_id=[shuttle_id] -- proceeding anyway.")
	qdel(bq)

	// Flip stashed FALSE now, before the (internally-yielding) apply
	// pipeline below runs, so a second retrieve for this same shuttle_id
	// arriving mid-load is refused by the "already deployed" check at the
	// top instead of racing a duplicate Z-load. Mirrors drydockStash()'s
	// stashed=TRUE-before-teardown ordering (see there) for the same
	// reason -- reverted below on the two failure paths that can still
	// occur before the load actually succeeds.
	DS.stashed = FALSE

	// Feedback up front, not just at the end -- shipInteriorApply() below
	// can take several real seconds on a heavy hull (its sub-procs yield
	// via CHECK_TICK), so without this the player sees nothing at all until
	// the "still initializing" notice appears once that wait is already over.
	if(user)
		to_chat(user, SPAN_NOTICE("Retrieving ship -- this may take a moment, please be patient."))

	// Reuse a torn-down Z from the shared pool if one's available; otherwise
	// allocate fresh. Either way, suspend ZAS during the load or the newly
	// loaded hull gets vented (same recipe as generate_away_site()).
	var/scope = "ship:d:[shuttle_id]"
	var/pool_z = SSpersistence.acquireReusableZ()
	var/new_z
	var/bounds
	SSair.can_fire = FALSE
	// Per-instance naming for everything this load creates -- the shuttle
	// datum(s) and the landable marker, which in turn names the home landmark.
	// Without it a second hull of the same class CRASHes on the duplicate
	// shuttle name and loses its landmark to the first one's tag. Cleared
	// immediately after the load, before any of the failure returns below.
	GLOB.drydock_loading_suffix = "#[shuttle_id]"
	GLOB.drydock_loading_areas = list()
	// See GLOB.drydock_loading_wall_hash_seed's own doc comment -- keyed on
	// shuttle_id (stable across every retrieve) rather than the z this load
	// is about to assign. NOT cleared alongside drydock_loading_suffix below --
	// stays set through shipInteriorApply() further down, since that's where
	// persistence_turfs.dm re-picks a saved wall's icon and needs the same
	// stable seed the template's own Initialize() pass just used.
	GLOB.drydock_loading_wall_hash_seed = "[shuttle_id]"
	if(pool_z)
		bounds = template.load_into_z(pool_z, TRUE)
		new_z = pool_z
	else
		var/z_before = world.maxz
		bounds = template.load_new_z(FALSE, TRUE)
		new_z = z_before + 1
	GLOB.drydock_loading_suffix = null
	// Cleared only AFTER the load returns -- init_shuttles() runs inside it,
	// and /datum/shuttle/New() reads this list to bind its own areas.
	GLOB.drydock_loading_areas = list()
	SSair.can_fire = TRUE
	if(!bounds)
		DS.stashed = TRUE // revert -- retrieve never actually happened
		if(pool_z)
			SSpersistence.poolReusableZ(pool_z) // hand it back, this attempt never claimed it
		if(user)
			to_chat(user, SPAN_WARNING("Failed to materialize ship."))
		log_drydock_error("drydockRetrieve: template load failed for '[DS.template_id]', shuttle_id=[shuttle_id][pool_z ? " (pooled z=[pool_z])" : ""].")
		GLOB.drydock_loading_wall_hash_seed = null
		return FALSE
	log_drydock("drydockRetrieve: shuttle_id=[shuttle_id] materialized at z=[new_z] ([pool_z ? "pooled" : "fresh"]) for template '[DS.template_id]'.")

	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[new_z]"]
	if(!istype(marker))
		DS.stashed = TRUE // revert -- retrieve never actually happened
		log_drydock_error("drydockRetrieve: no overmap marker found at loaded z=[new_z] for shuttle_id=[shuttle_id].")
		GLOB.drydock_loading_wall_hash_seed = null
		return FALSE
	shipPlaceOvermapMarker(marker, target_sector, placement_radius)

	var/datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum = _drydock_shuttle_of(marker)
	if(istype(shuttle_datum))
		// A retrieved ship's shuttle datum is freshly recreated every time
		// (template.load_new_z()/load_into_z() above), so player_built has
		// to be re-derived here too, not just set once at commission --
		// otherwise a commissioned ship would lose the flag the moment it's
		// stashed and retrieved again. hidden_from_catalog is exactly what
		// already marks the shared player-built shell template elsewhere.
		shuttle_datum.player_built = !!template.hidden_from_catalog
		// Per-instance identity: give this deployment's shuttle registry
		// entry and marker a unique name (suffixed with the ledger id) so
		// multiple instances of the same template can be deployed at once --
		// /datum/shuttle/New() hard-CRASHes on a duplicate name otherwise
		// (shuttle.dm), which is exactly what the same-template-deployed
		// guard above exists to prevent until this runs. Already-linked
		// shuttle_computers/consoles hold direct object references, not name
		// lookups, so renaming afterward doesn't disturb THEM -- but
		// shuttle_control/explore's OWN destination-picker UI (shuttle.dm)
		// does its own SEPARATE name-based lookup via its shuttle_tag var
		// (SSshuttle.shuttles[shuttle_tag]), independent of the shuttle
		// datum's shuttle_computers list. drydockAutoFurnish() sets that
		// correctly for a console it spawns fresh, but a MAPPED-IN console
		// (any Bucket-A hull, or one restored from a prior stash) never gets
		// touched -- so its shuttle_tag still points at the pre-rename name
		// once this runs, and its destination/fuel display silently comes up
		// empty. Keep every already-linked shuttle_control console's tag in
		// lockstep with the rename, not just newly-furnished ones.
		var/old_shuttle_name = shuttle_datum.name
		var/new_shuttle_name = "[old_shuttle_name] #[shuttle_id]"
		if(old_shuttle_name != new_shuttle_name && SSshuttle.shuttles[old_shuttle_name] == shuttle_datum)
			SSshuttle.shuttles -= old_shuttle_name
			shuttle_datum.name = new_shuttle_name
			SSshuttle.shuttles[new_shuttle_name] = shuttle_datum
			marker.shuttle = new_shuttle_name
			// Same stale-key problem the sub-ship waypoint registration below
			// already guards against -- see _drydock_rekey_ship_waypoints().
			_drydock_rekey_ship_waypoints(marker, old_shuttle_name, new_shuttle_name)
			for(var/obj/structure/machinery/computer/shuttle_control/console in shuttle_datum.shuttle_computers)
				console.shuttle_tag = new_shuttle_name

	// Player-facing identity (separate from the internal registry name
	// above): custom_name/custom_class override the template's own
	// defaults, kept clean of the "#shuttle_id" uniqueness suffix.
	marker.name = DS.display_name()
	if(DS.custom_class)
		marker.class = DS.custom_class

	GLOB.persistence_ship_z["[new_z]"] = scope

	// Default zone security tier for the fresh z: faction law aboard a
	// faction-owned vessel wherever it flies (medsec, matching a faction
	// beacon's own default guaranteed_security_tier), nullsec otherwise. Set
	// explicitly rather than left unset -- this z number may be a pooled
	// reuse (persistence_ship_interiors.dm) still carrying a stale tier from
	// a previous occupant if shipZTeardown() somehow didn't clear it, and an
	// admin can always override via "Set Z-Level Security Zone" afterward.
	GLOB.zone_security_by_z["[new_z]"] = DS.faction_uid ? ZONE_MEDSEC : ZONE_NULLSEC
	zone_security_update_overmap()

	// Not ready until shipInteriorApply()'s deferred atmos settle finishes
	// (~15s later) -- see _drydockInteriorSettled() (persistence_ship_interiors.dm),
	// which flips this back on and notifies the owner.
	DS.ready = FALSE
	SSpersistence.shipInteriorApply(new_z, scope)
	// Turf/object restore inside shipInteriorApply() is synchronous (only its
	// final atmos settle is deferred, via its own addtimer) -- every
	// pick_wall_icon_variant() call this retrieve will make has already
	// happened by the time this returns, so it's safe to clear the seed now.
	GLOB.drydock_loading_wall_hash_seed = null
	SSpersistence.drydockAutoFurnish(new_z, template, marker)

	// Auto-claim any still-unassigned equipment on this ship's Z, same as a
	// station beacon claiming its Zs (faction_beacon.dm) -- a faction-owned
	// ship gets its equipment networked to its faction; a personally-owned
	// ship gets its equipment tagged to its own crew instead, so an owner
	// doesn't have to manually tag every console by hand. This one-shot pass
	// covers the ship immediately; _drydock_start_periodic_sweep() (arming
	// itself below) then keeps re-running the same sweep for every deployed
	// ship going forward, so anything it misses self-heals within one cycle.
	if(DS.faction_uid)
		_sweep_unassigned_objects_for_faction(list("[new_z]"), DS.faction_uid)
	else
		_sweep_unassigned_crew(list("[new_z]"))
	_drydock_start_periodic_sweep()

	// Replenish each sub-ship from its own last snapshot (subshipSnapshotSave(),
	// called from stash) -- unconditional, same philosophy as the parent
	// ship's own persistence always re-applying its last save. This is what
	// makes "missing/damaged sub-ship" self-healing: if its compartment was
	// destroyed or emptied in a previous session, re-applying the last good
	// snapshot restores it. A never-before-saved sub-ship (first retrieve
	// ever) has no row yet, so this no-ops and the template's own copy
	// stands as-is.
	if(length(template.sub_shuttle_tags))
		for(var/sub_tag in template.sub_shuttle_tags)
			SSpersistence.subshipSnapshotApply(shuttle_id, sub_tag, new_z)
	SSpersistence._drydockApplySubshipNames(shuttle_id, template)
	// After the rename pass -- restricted_waypoints is keyed by the shuttle's
	// exact CURRENT name, so registering before renaming would file the hangar
	// under a name get_waypoints() will never ask for.
	_drydock_register_subship_waypoints(marker, template, shuttle_id)

	// Missing-sub-ship detection -- checked LAST, after the replenish pass
	// above -- log and alert rather than attempt anything further. Should
	// only ever fire for a genuinely first-ever-broken template (no prior
	// snapshot to replenish from, and the registered shuttle datum itself
	// still isn't valid), not a normal case.
	if(length(template.sub_shuttle_tags))
		for(var/sub_tag in template.sub_shuttle_tags)
			var/datum/shuttle/sub = SSshuttle.shuttles[_drydock_subship_key(shuttle_id, sub_tag)]
			if(!istype(sub) || !length(sub.shuttle_area))
				log_drydock_warning("drydockRetrieve: sub-ship '[sub_tag]' missing or invalid for shuttle_id=[shuttle_id] template='[DS.template_id]' -- may need manual recovery.")
				log_and_message_admins("[SPAN_WARNING("Drydock sub-ship missing:")] '[sub_tag]' not found aboard [DS.display_name()] (#[shuttle_id]) after retrieve.", user, marker)

	// DS.stashed already flipped FALSE above, before the apply pipeline ran.
	DS.z         = new_z
	DS.overmap_x = marker.x
	DS.overmap_y = marker.y
	// Only meaningful once DS.z points at the new level -- everything this
	// refreshes is looked up BY DS.z. It sets the marker (already correct
	// above, harmlessly re-set) and, the part that was missing, the z-level's
	// own label, which otherwise stays whatever the template was called
	// ("Player-Built Shuttle") rather than the player's ship name.
	_drydockRefreshDisplayedName(DS)

	if(!databaseCheckConnection("drydockRetrieve"))
		log_drydock_error("drydockRetrieve: database connection failed updating shuttle_id=[shuttle_id] -- ledger row now disagrees with live state until next save.")
	else
		var/datum/db_query/uq = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET stashed=0, z=:z, overmap_x=:x, overmap_y=:y WHERE shuttle_id = :id",
			list("z" = new_z, "x" = marker.x, "y" = marker.y, "id" = shuttle_id)
		)
		uq.Execute()
		if(!databaseCheckQueryResult(uq, "drydockRetrieve update"))
			log_drydock_error("drydockRetrieve: DB update failed for shuttle_id=[shuttle_id].")
		qdel(uq)
		_shipCentralPartialUpdate(DS.global_ship_id, list("stashed"), list(0))

	if(user)
		to_chat(user, SPAN_GOOD("Ship retrieved -- fly it in via its nav console. You'll be notified when it's ready to board."))
		log_and_message_admins("retrieved drydock ship '[DS.display_name()]' (#[shuttle_id]) at ([marker.x],[marker.y],[new_z]).", user, marker)
	_drydockFlagIfStolen(DS, user)
	log_drydock("drydockRetrieve: shuttle_id=[shuttle_id] deployed at z=[DS.z], overmap ([DS.overmap_x],[DS.overmap_y]) (acting=[acting]).")
	return TRUE

/**
 * Runtime furnishing for hulls converted from a static away-site mothership
 * that never had its own bridge console mapped in (template.bridge_area_type,
 * drydock_ship.dm) -- lets ~49 away-site hulls become flyable without any
 * blind DMM tile surgery. No-ops for hulls that already have a console,
 * either mapped in from the start (the placeholder, and any hull converted
 * from an already-landable away-site craft) or restored from a previous
 * stash via the ordinary ship-scoped object persistence (objectsApplyZ(),
 * already run by shipInteriorApply() before this is called every retrieve).
 * Only ever actually furnishes once per ship, on its very first-ever
 * retrieve: the console and blueprints item spawned here are registered via
 * objectsRegisterTrack(), folding them into the same per-ship persistence
 * every player-placed object already uses, so every later stash/retrieve
 * just restores them normally -- no re-furnish logic needed after the first.
 *
 * shuttle_computers/shuttle_tag are wired up directly here rather than via
 * the console's own Initialize() lookup, because by the time this runs the
 * shuttle datum is already registered under its post-rename per-instance
 * name (the rename block earlier in drydockRetrieve()) -- a console spawned
 * with a compile-time-constant shuttle_tag would resolve against the
 * pre-rename name, which no longer exists in SSshuttle.shuttles by now.
 */
/datum/controller/subsystem/persistence/proc/drydockAutoFurnish(z, datum/map_template/drydock_ship/template, obj/effect/overmap/visitable/ship/landable/drydock_ship/marker)
	if(!template.bridge_area_type)
		return
	var/datum/shuttle/shuttle_datum = _drydock_shuttle_of(marker)
	if(!istype(shuttle_datum))
		return
	if(length(shuttle_datum.shuttle_computers))
		return // already has a console, mapped-in or restored from a prior save

	var/area/bridge = locate(template.bridge_area_type)
	if(!istype(bridge))
		log_drydock_error("drydockAutoFurnish: couldn't locate bridge area [template.bridge_area_type] for [marker.shuttle] at z=[z].")
		return

	var/turf/spot
	for(var/turf/T in get_area_turfs(bridge))
		if(T.z != z || T.density)
			continue
		if(locate(/obj/structure) in T)
			continue
		spot = T
		break
	if(!spot)
		log_drydock_error("drydockAutoFurnish: no safe furnishing turf found in [template.bridge_area_type] for [marker.shuttle] at z=[z].")
		return

	var/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/console = new(spot)
	SSshuttle.lonely_shuttle_computers -= console
	console.shuttle_tag = marker.shuttle
	shuttle_datum.shuttle_computers += console
	SSpersistence.objectsRegisterTrack(console)

	var/obj/item/blueprints/shuttle/furnished_blueprints = new(spot)
	SSpersistence.objectsRegisterTrack(furnished_blueprints)

	log_drydock("drydockAutoFurnish: furnished [marker.shuttle] with a bridge console + blueprints at ([spot.x],[spot.y],[z]).")

/// Places a freshly-materialized ship's overmap marker within radius tiles of
/// anchor_sector -- the caller has already resolved whichever sector is
/// relevant (a faction beacon's sector for a faction ship, or the retrieving
/// computer's own current sector for a personal ship).
/datum/controller/subsystem/persistence/proc/shipPlaceOvermapMarker(obj/effect/overmap/visitable/ship/landable/marker, obj/effect/overmap/visitable/anchor_sector, radius, is_retry = FALSE)
	if(QDELETED(marker) || QDELETED(anchor_sector))
		return
	if(!istype(anchor_sector))
		// Never leave the marker at its mapped .dmm turf (the ship's own
		// cockpit) -- sector view cameras onto the marker's loc, so an
		// unplaced marker shows ship interior instead of the overmap.
		// Random-place on the overmap now, and retry the intended
		// near-anchor placement once, for the init-order race where the
		// anchor's sector hasn't registered yet during post-save retrieval.
		log_drydock_warning("shipPlaceOvermapMarker: anchor sector unavailable, [is_retry ? "keeping fallback placement" : "using fallback placement and scheduling one retry"].")
		marker.move_to_starting_location()
		if(!is_retry)
			addtimer(CALLBACK(src, PROC_REF(shipPlaceOvermapMarker), marker, anchor_sector, radius, TRUE), 1 MINUTE)
		return

	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
	if(anchor_sector.x < map_low || anchor_sector.x > map_high || anchor_sector.y < map_low || anchor_sector.y > map_high)
		// Anchor itself sits outside the normal placement band (eg CentCom,
		// deliberately pinned near the map's corner, centcom_overmap.dm) --
		// use the map's true bounds instead so the ship can land genuinely
		// adjacent to the anchor's own real position, rather than having its
		// center dragged into the normal band by BoundedCircularRandomCoordinate()'s
		// own clamp and landing tiles away from where the player actually is.
		map_low = 1
		map_high = SSatlas.current_map.overmap_size

	// Tier 1: within the normal radius, avoiding both other ship markers and
	// active overmap hazards (meteor/dust/carp/electric/gravity_anomaly/ion,
	// event.dm) -- forceMove() below fires Entered() unconditionally, and
	// landing directly on a live hazard tile starts its wave event targeting
	// this ship's own freshly-loaded Z (real explosions shortly after
	// retrieve). Tier 2: if hazards happen to blanket every tile at the
	// normal radius, widen to DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX -- boarding's
	// own sector-proximity checks tolerate up to that same distance
	// (telepad_drydock_boarding.dm), so the ship stays reachable from
	// wherever it was retrieved. Only if both tiers fail does this fall back
	// to today's absolute last resort (share a tile, no exclusions at all).
	var/turf/home = _shipPlacementFindClearTurf(anchor_sector, radius, map_low, map_high)
	if(!home && radius < DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX)
		log_drydock_warning("shipPlaceOvermapMarker: no hazard-free tile within radius [radius] of anchor sector, widening to [DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX].")
		home = _shipPlacementFindClearTurf(anchor_sector, DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX, map_low, map_high)
	if(!home)
		home = CircularRandomTurfAround(anchor_sector, radius, map_low, map_low, map_high, map_high)
		log_drydock_warning("shipPlaceOvermapMarker: no clear tile found even at widened radius, accepting a shared/hazard tile as last resort.")

	if(home)
		marker.start_x = home.x
		marker.start_y = home.y
		marker.forceMove(home)
		log_drydock("shipPlaceOvermapMarker: placed marker at ([home.x],[home.y]), radius=[radius] of anchor sector.")
		// Beacon hazard eviction (_evict_hazards_in_range()/_evict_ship_hazards_in_range(),
		// faction_beacon.dm) only runs periodically (process(), ~every 30s) or
		// on a network claim -- neither is guaranteed to have already run at
		// the exact instant this ship shows up. A ship materializing inside a
		// beacon's supposedly hazard-free radius must actually BE hazard-free
		// right now, not "probably clear as of up to 30 seconds ago" -- force
		// the check synchronously instead of trusting the timer.
		_drydockEvictHazardsForShip(marker)

/// Forces every currently active, powered, hazard-eviction-active faction
/// beacon whose security_radius reaches marker's new position to immediately
/// re-run its own hazard eviction (both the tile-level and ship-event-level
/// sweeps) -- see shipPlaceOvermapMarker()'s call site above for why this
/// can't just wait for the next periodic sweep.
/datum/controller/subsystem/persistence/proc/_drydockEvictHazardsForShip(obj/effect/overmap/visitable/ship/landable/marker)
	for(var/obj/structure/machinery/faction_beacon/B in world)
		if(!B._hazard_eviction_active())
			continue
		var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
		if(!istype(beacon_sector) || get_dist(marker, beacon_sector) > B.security_radius)
			continue
		B._evict_hazards_in_range()
		B._evict_ship_hazards_in_range()

/// Up to 10 random tries within radius of anchor_sector for a turf holding
/// neither another ship marker nor an active overmap hazard. Returns null if
/// none found -- see shipPlaceOvermapMarker()'s two-tier caller above.
/datum/controller/subsystem/persistence/proc/_shipPlacementFindClearTurf(obj/effect/overmap/visitable/anchor_sector, radius, map_low, map_high)
	var/tries = 10
	while(tries > 0)
		tries--
		var/turf/candidate = CircularRandomTurfAround(anchor_sector, radius, map_low, map_low, map_high, map_high)
		if(candidate && !(locate(/obj/effect/overmap/visitable) in candidate) && !(locate(/obj/effect/overmap/event) in candidate))
			return candidate
	return null

// ============================================================
// STASH  wipe content, remove the marker, ledger row only
// ============================================================

/// force=TRUE (shutdown sweep / admin Force Stash) skips the "must be
/// genuinely docked at a registered beacon" check -- there's no way to fly
/// an abandoned ship home on demand the way the old turf-pad system could
/// relocate a hull, so an emergency stash just tears it down wherever it
/// is, same as corvetteStash()'s own force path.
///
/// Public entry point -- a thin queue-gate in front of _drydockStashRun()
/// (below), which does the actual work. Serializes with drydockRetrieve()
/// server-wide via GLOB.drydock_op_active/drydock_op_queue (see there for
/// why). force=TRUE (the shutdown sweep, drydockAutoStashAll(), and the
/// admin Force Stash verb) bypasses the queue entirely and runs immediately
/// -- those callers need a real synchronous result now, not "queued for
/// whenever the current op finishes."
/datum/controller/subsystem/persistence/proc/drydockStash(shuttle_id, mob/user, force = FALSE)
	if(force)
		return _drydockStashRun(shuttle_id, user, force)
	// save_in_progress: never start a Z-level teardown while a world save is
	// mid-walk -- the exact "save it mid-stash" corruption case. The save's
	// own completion (fire()/force_persistence_save()) drains this queue.
	if(GLOB.drydock_op_active || save_in_progress)
		GLOB.drydock_op_queue += list(list("op" = "stash", "shuttle_id" = shuttle_id, "user" = user))
		if(user)
			to_chat(user, SPAN_WARNING("[save_in_progress ? "A world save is in progress" : "Too much drydock activity right now"] -- queued (position [length(GLOB.drydock_op_queue)]). You'll be notified when it starts."))
		log_drydock("drydockStash: [user ? key_name(user) : "SYSTEM"] queued stash of shuttle_id=[shuttle_id] (position [length(GLOB.drydock_op_queue)], [save_in_progress ? "world save" : "drydock op"] active).")
		return FALSE
	GLOB.drydock_op_active = TRUE
	GLOB.drydock_op_active_shuttle_id = shuttle_id
	try
		. = _drydockStashRun(shuttle_id, user, force)
	catch(var/exception/e)
		log_drydock_error("drydockStash: uncaught exception stashing shuttle_id=[shuttle_id] (acting=[user ? key_name(user) : "SYSTEM"]): [e] at [e.file]:[e.line]")
		if(user)
			to_chat(user, SPAN_WARNING("Something went wrong stashing that ship -- an admin has been notified."))
		log_and_message_admins("drydockStash: uncaught exception stashing shuttle_id=[shuttle_id]: [e] at [e.file]:[e.line]", user)
	GLOB.drydock_op_active = FALSE
	GLOB.drydock_op_active_shuttle_id = null
	_drydockProcessNextQueued()
	return .

/// TRUE if a living mob (stat != DEAD, client or lingering ckey) or an
/// occupied neural lace is anywhere aboard this ship -- the parent hull's Z
/// (which, after the sub-ship recall in _drydockStashRun() above it runs,
/// includes any sub-ship docked home), plus a direct sweep of each sub-ship's
/// shuttle_area turfs as a backstop (checked by area membership, not
/// z-coordinate, so it's still found even if recall somehow left it
/// elsewhere). Narrower than zlevel_has_players() (persistence_zlevel_reset.dm)
/// on purpose -- that one also blocks on a dead body with a lingering ckey or
/// any neural lace regardless of occupancy, which don't matter here.
/proc/_drydock_ship_has_living_occupants(datum/drydock_ship/DS)
	if(DS.z)
		for(var/mob/M in GLOB.mob_list)
			CHECK_TICK
			if(M.z == DS.z && M.stat != DEAD && (M.client || M.ckey))
				return TRUE
		for(var/obj/item/organ/internal/neural_lace/L in world)
			CHECK_TICK
			if(L.lace_occupied)
				var/turf/T = get_turf(L)
				if(T && T.z == DS.z)
					return TRUE
	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
	if(template && length(template.sub_shuttle_tags))
		var/list/sub_areas = list()
		for(var/sub_tag in template.sub_shuttle_tags)
			var/datum/shuttle/autodock/sub = SSshuttle.shuttles[_drydock_subship_key(DS.shuttle_id, sub_tag)]
			if(!istype(sub))
				continue
			sub_areas |= sub.shuttle_area
		if(length(sub_areas))
			// Resolved by AREA rather than by scanning each turf's own
			// contents: get_area() sees through nesting, so someone inside a
			// closet, cryo pod or mech -- or a lace inside a body, locker or
			// autodoc -- still counts. Iterating `for(var/mob/M in T)` only
			// sees what lies directly on the turf and missed every one of
			// those, while the DS.z sweep above already resolves at any depth
			// via get_turf(). One pass over each list for all sub-ships, not
			// one per tag.
			for(var/mob/M in GLOB.mob_list)
				CHECK_TICK
				if(M.stat == DEAD || !(M.client || M.ckey))
					continue
				if(get_area(M) in sub_areas)
					return TRUE
			for(var/obj/item/organ/internal/neural_lace/L in world)
				CHECK_TICK
				if(!L.lace_occupied)
					continue
				if(get_area(L) in sub_areas)
					return TRUE
	return FALSE

/// TRUE if any mob (dead OR alive) or occupied neural lace is anywhere
/// within envelope -- gates the ship_commissioning console's Commission
/// action, both the TGUI's own greyed-out button (ui_data(), Ship
/// Commissioning) and drydockCommission()'s server-side enforcement below.
/// Deliberately broader than _drydock_ship_has_living_occupants() above
/// (which only cares about LIVING occupants of an already-owned ship's own
/// Z, since a dead body left aboard a stashed ship is harmless) --
/// commissioning wipes the build site's turfs out from under whoever's
/// standing there, dead or alive, so anyone at all has to step clear first.
/proc/_drydock_envelope_has_occupants(list/turf/envelope)
	for(var/turf/T in envelope)
		if(locate(/mob/living) in T)
			return TRUE
		for(var/obj/item/organ/internal/neural_lace/L in T)
			if(L.lace_occupied)
				return TRUE
	return FALSE

/// The first APC found anywhere in envelope, or null -- used by both
/// drydockCommission()'s own required-APC check and the ship_commissioning
/// console's ui_data() (greyed-out button/hint). Kept a hard requirement,
/// not auto-furnished, same as the console and transponder -- players build
/// their own.
/proc/_drydock_envelope_find_apc(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/power/apc/apc = locate() in T
		if(apc)
			return apc
	return null

/// The first helm console found anywhere in envelope, or null -- required
/// at commission time since shuttle_control alone only ever offers
/// point-to-point docking, not real overmap flight -- without a helm
/// console a commissioned hull would have no way to actually pilot itself.
/proc/_drydock_envelope_find_helm(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/computer/ship/helm/helm = locate() in T
		if(helm)
			return helm
	return null

/// The first navigation console found anywhere in envelope, or null --
/// required at commission time since it's the only thing that lets crew see
/// anything outside the hull (live position/speed/heading, nearby
/// contacts), not merely a display nicety.
/proc/_drydock_envelope_find_navigation(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/computer/ship/navigation/nav = locate() in T
		if(nav)
			return nav
	return null

/// The first engine control terminal found anywhere in envelope, or null --
/// required at commission time since engines_state (engine_control.dm) can
/// only ever be set TRUE via this specific console -- fuel, a helm, and
/// propulsion engine structures alone still can't move a hull without one.
/proc/_drydock_envelope_find_engine_control(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/computer/ship/engines/terminal = locate() in T
		if(terminal)
			return terminal
	return null

/// The first real engine nozzle found anywhere in envelope, or null --
/// required at commission time alongside (not instead of) the decorative
/// propulsion count above -- the nozzle is what actually burns fuel gas for
/// thrust and populates datum/ship_engine (gas_thruster.dm), which the
/// decorative propulsion structure never does.
/proc/_drydock_envelope_find_ship_engine(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/atmospherics/unary/engine/nozzle = locate() in T
		if(nozzle)
			return nozzle
	return null

/// The first self-contained ion engine found anywhere in envelope, or null --
/// an alternate way to satisfy the same commission requirement
/// _drydock_envelope_find_ship_engine() checks, since either engine type
/// populates datum/ship_engine the same way (ion_thruster.dm).
/proc/_drydock_envelope_find_ion_engine(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/ion_engine/engine = locate() in T
		if(engine)
			return engine
	return null

/// The first sensors terminal found anywhere in envelope, or null --
/// required at commission time since it's the only way to see anything
/// outside the hull.
/proc/_drydock_envelope_find_sensors_terminal(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/computer/ship/sensors/terminal = locate() in T
		if(terminal)
			return terminal
	return null

/// The first sensor array found anywhere in envelope, or null -- required
/// alongside the sensors terminal, which has nothing to read from without
/// one.
/proc/_drydock_envelope_find_sensor_array(list/turf/envelope)
	for(var/turf/T in envelope)
		var/obj/structure/machinery/shipsensors/array = locate() in T
		if(array)
			return array
	return null

/// Every /obj/structure/shuttle/engine/propulsion (including the buildable
/// crate-orderable subtype) anywhere in envelope -- used by both
/// drydockCommission()'s own minimum-propulsion check and the ship_commissioning
/// console's ui_data() (greyed-out button/hint). No particular placement
/// required, just a count.
/proc/_drydock_envelope_count_propulsion(list/turf/envelope)
	var/count = 0
	for(var/turf/T in envelope)
		for(var/obj/structure/shuttle/engine/propulsion/P in T)
			count++
	return count

/datum/controller/subsystem/persistence/proc/_drydockStashRun(shuttle_id, mob/user, force = FALSE)
	var/acting = user ? key_name(user) : "SYSTEM[force ? "(force)" : ""]"
	log_drydock("drydockStash: [acting] attempting to stash shuttle_id=[shuttle_id].")

	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS)
		log_drydock_warning("drydockStash: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(DS.stashed)
		if(user)
			to_chat(user, SPAN_WARNING("That ship is already stashed."))
		log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] already stashed (acting=[acting]).")
		return FALSE
	// A retrieve releases the op lock as soon as the marker is placed, but the
	// interior is still being applied asynchronously after that -- so between
	// "Ship retrieved, you'll be notified when it's ready to board" and the
	// apply actually finishing, this ship reads as neither busy nor stashed.
	// Stashing in that window saves a half-restored interior back over the good
	// rows and tears the marker down mid-load, wedging the ship. DS.ready is
	// exactly that window's flag (set at _shipInteriorApplyFinish(),
	// persistence_ship_interiors.dm), so gate on it.
	if(!DS.ready)
		if(!force)
			if(user)
				to_chat(user, SPAN_WARNING("This ship is still being retrieved -- wait until you're notified it's ready to board."))
			log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] is not ready yet (retrieve still applying its interior), acting=[acting].")
			return FALSE
		// Forced stashes (shutdown sweep, admin Force Stash) still proceed --
		// refusing one at shutdown would leave the ledger claiming a deployed
		// ship whose z is about to disappear. Logged loudly because the saved
		// interior may be incomplete.
		log_drydock_warning("drydockStash: shuttle_id=[shuttle_id] force-stashed while NOT ready -- its interior may still have been mid-apply. Verify it after retrieve (acting=[acting]).")
	if(!force && !(check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to stash this ship."))
		log_drydock_warning("drydockStash: refused -- [acting] lacks permission for shuttle_id=[shuttle_id] (owner=[DS.owner_ckey || "none"], faction=[DS.faction_uid || "none"]).")
		return FALSE
	var/obj/effect/overmap/visitable/ship/landable/check_marker = GLOB.map_sectors["[DS.z]"]
	var/datum/shuttle/autodock/overmap/drydock_ship/stashing_shuttle_datum = istype(check_marker) ? _drydock_shuttle_of(check_marker) : null
	if(!force)
		// A personal ship may stash near ANY faction's beacon (not
		// necessarily one it owns), provided that beacon's own sector is
		// currently med-sec or better -- a faction ship still requires its
		// OWN faction's beacon specifically, same as retrieve. _drydock_ship_sector(),
		// not check_marker directly -- check_marker is DS's own marker, which
		// may currently be nested (docked) and would give get_dist() a
		// meaningless result; check_marker itself is still used correctly
		// below for the guest-ship/nested-in-host checks, which specifically
		// care about its own nesting state.
		if(!_drydock_secured_beacon_nearby(_drydock_ship_sector(DS), DS.faction_uid))
			if(user)
				to_chat(user, SPAN_WARNING(DS.faction_uid ? "This ship must be within 1 tile of your faction's own beacon to be stashed." : "You must be near a secured (med-sec or better) faction beacon to stash."))
			log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] not near a valid beacon (acting=[acting]).")
			return FALSE
		// _drydock_secured_beacon_nearby() above only checks that the SHIP is
		// near SOME qualifying beacon -- for a personal ship that's any
		// faction's beacon, not necessarily one anywhere near the player --
		// so without this, a player could stash a ship sitting at a
		// completely different away site just because it happened to be
		// parked near a good-enough beacon there. Faction ships aren't
		// affected -- they already require their own faction's specific
		// beacon, a much tighter constraint than "any secured beacon."
		if(!DS.faction_uid && istype(user))
			var/obj/effect/overmap/visitable/player_sector = _drydock_boarder_sector(user)
			var/obj/effect/overmap/visitable/ship_sector_now = _drydock_ship_sector(DS)
			var/stash_dist = (istype(player_sector) && istype(ship_sector_now)) ? get_dist(player_sector, ship_sector_now) : INFINITY
			if(stash_dist > DRYDOCK_SHIP_PLACEMENT_RADIUS_MAX)
				if(user)
					to_chat(user, SPAN_WARNING("You need to be at the ship's own location to stash it -- you're at [player_sector || "an unresolvable location"], it's at [ship_sector_now || "an unresolvable location"]."))
				log_drydock_warning("drydockStash: refused -- [acting] not near shuttle_id=[shuttle_id] (player=[player_sector], ship=[ship_sector_now], dist=[stash_dist]).")
				return FALSE
		var/mob/living/living_user = istype(user, /mob/living) ? user : null
		if((living_user && living_user.in_recent_combat()) || (istype(check_marker) && check_marker.in_recent_combat()))
			if(user)
				to_chat(user, SPAN_WARNING("You (or your ship) were recently in combat -- wait before stashing."))
			log_drydock_warning("drydockStash: refused -- combat lockout active for shuttle_id=[shuttle_id] (acting=[acting]).")
			return FALSE
		// "Docked with another independently-owned ship" from the OTHER
		// direction -- someone else's marker is nested inside MY contents.
		// on_landing() (landable.dm) forceMove()s a docking ship's marker
		// directly into its target's own contents (visiting_shuttle slots,
		// and public hangar_slot landmarks, docking_beacon.dm), so
		// I may not stash while that's the case. This doesn't move any of MY
		// own turfs anywhere (unlike the away-from-home check just below,
		// which is about my OWN real position) -- _drydockMarkerTeardown()
		// still evacuates rather than destroys a nested guest as a last-resort
		// fallback for forced/admin teardowns, but a normal stash should never
		// need that fallback in the first place -- refuse and explain instead.
		if(istype(check_marker))
			for(var/obj/effect/overmap/visitable/ship/landable/guest in check_marker.contents)
				if(_drydock_guest_is_own_subship(guest, check_marker))
					continue // my own sub-ship parked at home, not a foreign guest
				if(user)
					to_chat(user, SPAN_WARNING("[guest.shuttle] is currently docked with you -- it must undock before you can stash."))
				log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] has guest ship '[guest.shuttle]' docked with it (acting=[acting]).")
				return FALSE
	// Absolute -- currently away from my OWN home landmark (docked at a
	// beacon, an open hangar slot, or nested inside another ship's own
	// visiting slot -- current_location is the single source of truth for
	// all three, set by real flight (shuttle_moved(), shuttle.dm) or by
	// drydockCommission()'s own dock_at_beacon placement) means my real hull
	// is genuinely NOT sitting on DS.z right now. shipInteriorSave() below
	// captures DS.z verbatim, and _drydockMarkerTeardown() tears it down --
	// stashing from anywhere but home would silently save nothing and leave
	// a live, fully-functional ship stranded at the dock while the ledger
	// falsely claims it's stashed. A normal stash refuses and asks the
	// player to undock manually; a forced stash (shutdown sweep, admin Force
	// Stash) can't wait on that, so it recalls the ship home itself first --
	// mirroring the sub-ship recall-or-abort pattern just below.
	if(!force && istype(stashing_shuttle_datum) && !_drydock_ship_is_home(DS, stashing_shuttle_datum))
		if(user)
			to_chat(user, SPAN_WARNING("This ship is currently docked -- undock before stashing."))
		log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] is away from home (at '[stashing_shuttle_datum.current_location]') (acting=[acting]).")
		return FALSE
	// Recalls the ship itself (if away from home -- a no-op otherwise) and
	// any bound sub-ship (unconditionally, not just for a forced stash --
	// see _drydock_recall_ship_home()'s own doc comment for why). Shared
	// with the periodic-autosave sweep (drydockRecallAllDeployed()) so both
	// go through the exact same recall logic.
	if(!_drydock_recall_ship_home(DS))
		log_drydock_error("drydockStash: recall-home failed for shuttle_id=[shuttle_id] -- aborting stash cleanly, needs admin attention.")
		return FALSE

	// A real stash (shutdown, Force Stash Ship/All -- never a normal
	// player-initiated one, which still just refuses via the occupancy
	// check below) evacuates any living occupant first instead of simply
	// giving up on that ship -- see _drydock_evacuate_occupants_before_stash()'s
	// own doc comment for exactly what it can and can't safely handle.
	if(force)
		if(!_drydock_evacuate_occupants_before_stash(DS))
			log_drydock_error("drydockStash: could not safely evacuate all living occupants for shuttle_id=[shuttle_id] -- aborting stash cleanly, needs admin attention.")
			return FALSE

	if(_drydock_ship_has_living_occupants(DS))
		if(user)
			to_chat(user, SPAN_WARNING("Everyone must be off the ship (and no one still in a neural lace) before it can be stashed."))
		log_drydock_warning("drydockStash: refused -- living occupant or occupied neural lace present for shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	if(user)
		to_chat(user, SPAN_NOTICE("Stashing ship -- this may take a moment, please be patient."))
		play_announcer_sound_priority(user, 'sound/AI/announcements/stashing_ship_please_wait.ogg')

	// Before the interior is captured, so the SAVED state records everything
	// as off -- otherwise a retrieved ship arrives already burning fuel,
	// projecting shields, or cloaked with nobody having switched it on.
	_drydock_power_down_ship_systems(DS)

	var/scope = "ship:d:[shuttle_id]"
	var/stash_z = DS.z
	// LAST LINE OF DEFENCE. Everything past this point saves stash_z and then
	// destroys it, so if the hull is not physically on stash_z we would capture
	// an empty z, tear it down, and leave the real ship orphaned wherever it
	// actually is -- irrecoverably, since the saved interior is what a retrieve
	// rebuilds from. That is exactly how a ship was lost: an undock whose
	// translation came out empty reported success, so the bookkeeping said home
	// while the hull never left the away site.
	//
	// Verified from the turfs themselves rather than from current_location,
	// because current_location is precisely the var that lies in this scenario.
	if(istype(stashing_shuttle_datum))
		var/hull_present = FALSE
		for(var/turf/T as anything in stashing_shuttle_datum.get_hull_turfs())
			if(T.z == stash_z)
				hull_present = TRUE
				break
		if(!hull_present)
			if(user)
				to_chat(user, SPAN_WARNING("Stash aborted -- this ship's hull isn't actually on its own z-level. An admin has been notified; nothing has been saved or torn down."))
			log_drydock_error("drydockStash: ABORTED for shuttle_id=[shuttle_id] -- no hull turfs found on stash_z=[stash_z] (current_location='[stashing_shuttle_datum.current_location]'). Refusing to save an empty z and tear it down; the real hull is elsewhere and must be recovered first.")
			log_and_message_admins("Drydock: stash of '[DS.display_name()]' (#[shuttle_id]) aborted -- its hull is not on z=[stash_z]. The ship is intact but mislocated; do not retry until it is recovered.", user)
			return FALSE
	var/datum/map_template/drydock_ship/save_template = SSmapping.drydock_ship_templates[DS.template_id]
	// Drop the hangar waypoint registrations before the z goes away, so a
	// stashed ship's hangar stops being offered as a destination to anything
	// still flying. Mirrors _drydock_register_subship_waypoints() at retrieve.
	_drydock_unregister_subship_waypoints(GLOB.map_sectors["[stash_z]"], save_template, shuttle_id)
	SSpersistence.shipInteriorSave(stash_z, scope)

	if(save_template && length(save_template.sub_shuttle_tags))
		for(var/sub_tag in save_template.sub_shuttle_tags)
			SSpersistence.subshipSnapshotSave(shuttle_id, sub_tag)

	// Destroy each sub-ship's own shuttle datum, AFTER its snapshot is saved
	// above. shipZTeardown() (persistence_ship_interiors.dm) only ever qdels
	// the single datum it is handed -- the parent hull's -- so a sub-ship's
	// datum outlived every stash and stayed in SSshuttle.shuttles under its
	// per-instance name. The next retrieve then rebuilt the same sub-ship
	// from the template and /datum/shuttle/New() hard-CRASHed on the
	// duplicate name ("A shuttle with the name '... #22' is already
	// defined."). Areas are pulled from SSshuttle.shuttle_areas first,
	// exactly as shipZTeardown() does for the parent.
	if(save_template && length(save_template.sub_shuttle_tags))
		for(var/sub_tag in save_template.sub_shuttle_tags)
			var/datum/shuttle/sub = SSshuttle.shuttles[_drydock_subship_key(shuttle_id, sub_tag)]
			if(!istype(sub))
				continue
			for(var/area/A in sub.shuttle_area)
				SSshuttle.shuttle_areas -= A
			qdel(sub) // Destroy() clears SSshuttle.shuttles/process_shuttles itself

	// Ledger flips to stashed BEFORE the marker is torn down -- the qdel
	// below fires drydock_ship/Destroy()'s defensive orphan-recovery check
	// (drydock_ship.dm), which only acts when it finds a ledger row still
	// disagreeing with the marker's destruction. Flipping first means that
	// check correctly sees this as already-sanctioned and no-ops.
	DS.stashed   = TRUE
	DS.z         = null
	DS.overmap_x = null
	DS.overmap_y = null

	if(!databaseCheckConnection("drydockStash"))
		log_drydock_error("drydockStash: database connection failed writing shuttle_id=[shuttle_id] -- ledger row now disagrees with live state until next save.")
	else
		var/datum/db_query/uq = SSdbcore.NewQuery(
			"UPDATE ss13_drydock_ships SET stashed=1, stashed_at=NOW() WHERE shuttle_id = :id",
			list("id" = shuttle_id)
		)
		uq.Execute()
		if(!databaseCheckQueryResult(uq, "drydockStash update"))
			log_drydock_error("drydockStash: DB write failed for shuttle_id=[shuttle_id].")
		qdel(uq)
		_shipCentralPartialUpdate(DS.global_ship_id, list("stashed"), list(1))

	// Grabbed before teardown -- there's no marker left to JMP to afterward.
	var/turf/stash_location = istype(check_marker) ? get_turf(check_marker) : null

	SSpersistence._drydockMarkerTeardown(stash_z)

	if(user)
		to_chat(user, SPAN_GOOD("Ship stashed."))
		play_announcer_sound_priority(user, 'sound/AI/announcements/ship_successfully_stashed.ogg')
		log_and_message_admins("stashed drydock ship '[DS.display_name()]' (#[shuttle_id]).", user, stash_location)
	// force=TRUE is a system/officer-authority override (shutdown sweep,
	// admin Force Stash, First Responder seizure) -- never the acting user
	// exercising their own claim, so it should never itself flag theft.
	if(!force)
		_drydockFlagIfStolen(DS, user)
	log_drydock("drydockStash: shuttle_id=[shuttle_id] fully stashed and torn down (acting=[acting]).")
	return TRUE

/// Recalls DS (and any bound sub-ship) back to its own home landmark if
/// currently away -- shared by _drydockStashRun()'s own force path and the
/// periodic-autosave sweep (drydockRecallAllDeployed() below), so both go
/// through the exact same logic instead of two hand-written copies. The
/// primary ship only actually moves if away from home (a no-op returning
/// TRUE otherwise); a bound sub-ship is always recalled unconditionally,
/// same as before this was factored out -- it has no independent stash of
/// its own, so leaving it wherever it happened to be would either orphan it
/// or leave it exposed to whatever it's docked with. Returns FALSE only on
/// a genuine recall failure (attempt_move() refused -- blocked, grappled,
/// missing home landmark) that needs admin attention.
/// Absolute fallback for a ship whose own open space is unreachable: give it a
/// brand-new, guaranteed-empty z, put its home landmark there, and move it in.
///
/// Only ever called after a normal recall has already been refused. A ship that
/// cannot reach its own home is otherwise stranded permanently -- every retry
/// hits the identical refusal -- so a fresh z is strictly better than leaving
/// it stuck, even though it costs a z-level.
///
/// Ordering is deliberate and matters: the new z and landmark are fully built
/// and the MOVE IS ATTEMPTED FIRST. Only once the ship is physically on the new
/// z does any ledger/registry state change. If the move fails, everything
/// provisioned here is discarded and the ship is left exactly as it was --
/// never half-migrated with DS.z pointing somewhere the hull isn't, which is
/// the failure mode that loses ships.
/datum/controller/subsystem/persistence/proc/_drydock_rehome_to_fresh_z(datum/drydock_ship/DS, obj/effect/overmap/visitable/ship/landable/marker, datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum)
	if(!istype(marker) || !istype(shuttle_datum))
		return FALSE

	// Never recycle here -- a pooled z can carry leftovers, and this path exists
	// precisely because the ship's existing ground is already untrustworthy.
	var/datum/space_level/fresh = SSmapping.add_new_zlevel("Rehomed Open Space for [shuttle_datum.name]", list(ZTRAIT_RESERVED = TRUE), contain_turfs = FALSE)
	if(!fresh)
		return FALSE
	var/new_z = fresh.z_value
	var/turf/centre = locate(round(world.maxx / 2), round(world.maxy / 2), new_z)
	if(!centre)
		return FALSE

	// Unique tag -- reusing the template's fixed tag would collide with the old
	// landmark still sitting in the registry (register_landmark() rejects
	// duplicates outright).
	var/obj/effect/shuttle_landmark/ship/rehomed = new(centre, shuttle_datum.name)
	rehomed.landmark_tag = "nav_rehomed_[DS.shuttle_id]_[new_z]"
	rehomed.shuttle_name = shuttle_datum.name
	rehomed.name = "Open Space"
	// Space, explicitly -- the exact defect that duplicated hulls in the first
	// place was a home landmark whose base_area resolved to the ship's OWN area
	// (see player_built_shuttle.dm).
	rehomed.landmark_flags = SLANDMARK_FLAG_ZERO_G
	rehomed.base_turf = /turf/space
	rehomed.base_area = locate(/area/space) || world.area
	SSshuttle.register_landmark(rehomed.landmark_tag, rehomed)

	// Move BEFORE committing any state. A refusal here must leave the ship
	// untouched.
	if(!shuttle_datum.attempt_move(rehomed))
		SSshuttle.registered_shuttle_landmarks -= rehomed.landmark_tag
		qdel(rehomed)
		log_drydock_error("_drydock_rehome_to_fresh_z: the fresh z at [new_z] ALSO refused shuttle_id=[DS.shuttle_id] -- discarded it and left the ship where it was.")
		return FALSE

	// Committed: the hull is physically on new_z, so the ledger and registries
	// follow it.
	var/old_z = DS.z
	var/scope = "ship:d:[DS.shuttle_id]"
	marker.landmark = rehomed
	for(var/zlevel in marker.map_z)
		GLOB.map_sectors["[zlevel]"] = null
	GLOB.persistence_ship_z -= "[old_z]"
	marker.map_z = list(new_z)
	GLOB.map_sectors["[new_z]"] = marker
	GLOB.persistence_ship_z["[new_z]"] = scope
	GLOB.zone_security_by_z["[new_z]"] = DS.faction_uid ? ZONE_MEDSEC : ZONE_NULLSEC
	DS.z = new_z
	// Point the ship's saved content rows at the z it actually lives on now,
	// or the next retrieve would restore its interior onto the abandoned one.
	remapShipRows(scope, new_z)
	log_and_message_admins("Drydock: '[DS.display_name()]' (#[DS.shuttle_id]) could not reach its own open space (z=[old_z]) and was rehomed onto a fresh z=[new_z].", null, get_turf(marker))
	return TRUE

/// allow_rehome -- whether a ship that genuinely cannot reach its own open
/// space may be given a brand-new z to live on instead. TRUE for a real stash,
/// where the alternative is a stash that can never complete. FALSE for the
/// periodic autosave sweep: provisioning a z-level and physically relocating a
/// ship a player deliberately parked somewhere is far too heavy-handed for
/// background housekeeping, and it reads to the player as their ship being
/// dumped into empty space for no reason they can see.
/datum/controller/subsystem/persistence/proc/_drydock_recall_ship_home(datum/drydock_ship/DS, allow_rehome = TRUE)
	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
	if(!istype(marker))
		return FALSE
	var/datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum = _drydock_shuttle_of(marker)
	var/obj/effect/shuttle_landmark/home_landmark = _drydock_resolve_home_landmark(marker, shuttle_datum)
	// FAIL CLOSED. This used to read marker.landmark directly and, when that
	// was null, skip the whole move and still return TRUE -- reporting a
	// successful recall for a ship that never budged. _drydockStashRun() then
	// went on to shipInteriorSave() the ship's EMPTY home z and tear the marker
	// down while the real hull sat somewhere else entirely. A stash that cannot
	// bring the ship home must never proceed.
	if(!istype(shuttle_datum) || !istype(home_landmark))
		log_drydock_error("_drydock_recall_ship_home: could not resolve a home landmark for shuttle_id=[DS.shuttle_id] (marker.landmark=[marker.landmark ? "set" : "NULL"], logging_home_tag='[istype(shuttle_datum) ? shuttle_datum.logging_home_tag : "n/a"]') -- refusing to report a recall that never happened. Needs admin attention.")
		return FALSE
	// Already on our own z counts as home -- see _drydock_ship_is_home(). Moving
	// from (say) the transit landmark to the home landmark on that same z
	// overlaps the hull with itself, which attempt_move() now refuses outright,
	// so attempting it could only fail and abort an otherwise-fine stash. There
	// is nothing to recall: the hull is already on the z that is about to be
	// saved and torn down.
	if(!_drydock_ship_is_home(DS, shuttle_datum) && shuttle_datum.current_location != home_landmark)
		log_drydock("_drydock_recall_ship_home: shuttle_id=[DS.shuttle_id] is away from home -- force-recalling.")
		if(!shuttle_datum.attempt_move(home_landmark))
			// Last resort: the ship's own open space is genuinely unreachable
			// (its home z is occupied, corrupted, or gone). Rather than leave
			// it stranded forever, give it a brand-new empty z to call home and
			// move it there -- the caller then proceeds with the normal stash,
			// which saves the interior and tears that z down again.
			if(!allow_rehome)
				log_drydock_warning("_drydock_recall_ship_home: home move refused for shuttle_id=[DS.shuttle_id] -- leaving it where it is (rehoming is reserved for a real stash).")
				return FALSE
			log_drydock_warning("_drydock_recall_ship_home: home move refused for shuttle_id=[DS.shuttle_id] -- provisioning a fresh open-space z as a fallback.")
			if(!_drydock_rehome_to_fresh_z(DS, marker, shuttle_datum))
				log_drydock_error("_drydock_recall_ship_home: fallback rehome ALSO failed for shuttle_id=[DS.shuttle_id] -- needs admin attention.")
				return FALSE
			log_drydock("_drydock_recall_ship_home: shuttle_id=[DS.shuttle_id] rehomed onto a fresh z successfully.")
		else
			log_drydock("_drydock_recall_ship_home: shuttle_id=[DS.shuttle_id] force-recalled home successfully.")

	var/datum/map_template/drydock_ship/sub_template = SSmapping.drydock_ship_templates[DS.template_id]
	if(sub_template && length(sub_template.sub_shuttle_tags))
		for(var/sub_tag in sub_template.sub_shuttle_tags)
			var/datum/shuttle/autodock/sub = SSshuttle.shuttles[_drydock_subship_key(DS.shuttle_id, sub_tag)]
			if(!istype(sub) || !istype(sub.current_location))
				continue
			if(sub.current_location.landmark_tag == sub.logging_home_tag)
				continue // already home
			var/obj/effect/shuttle_landmark/home = SSshuttle.get_landmark(sub.logging_home_tag)
			if(!home)
				log_drydock_error("_drydock_recall_ship_home: force-recall failed -- no home landmark '[sub.logging_home_tag]' for sub-ship '[sub_tag]', shuttle_id=[DS.shuttle_id].")
				return FALSE
			// Cancel any pending long_jump cleanly first -- the long_jump()
			// checkpoint is what catches this if it's currently asleep
			// mid-loop. Harmless no-op if it's just docked elsewhere/idle,
			// or actively flying (flight never touches these vars).
			sub.moving_status = SHUTTLE_IDLE
			sub.next_location = null
			sub.in_use = null
			sub.set_process_state(IDLE_STATE)
			if(sub.attempt_move(home))
				sub.next_location = home
				sub.process_arrived()
				log_drydock("_drydock_recall_ship_home: force-recalled sub-ship '[sub_tag]' home for shuttle_id=[DS.shuttle_id].")
			else
				log_drydock_error("_drydock_recall_ship_home: force-recall of sub-ship '[sub_tag]' failed (attempt_move refused -- possibly grappled/blocked), shuttle_id=[DS.shuttle_id].")
				return FALSE // don't let the caller proceed and orphan it
	return TRUE

/// Periodic-autosave companion to drydockAutoStashAll() -- recalls every
/// currently away-from-home deployed ship (and its sub-ships) back to its
/// own open-space Z, WITHOUT stashing it, so the general Finalize sweeps
/// that follow in forceSaveAll() always see every deployed ship sitting at
/// its own persisted position (closing the "duplicated at an away-site Z
/// across a restart" risk) while leaving every ship fully playable
/// afterward -- exit, redock, or a manual stash are all still available to
/// anyone aboard once they're off it. Called from forceSaveAll()
/// (persistence.dm), before any Finalize sweep runs.
/datum/controller/subsystem/persistence/proc/drydockRecallAllDeployed()
	var/recalled_count = 0
	var/failed_count = 0
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed || !DS.z)
			continue
		var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
		if(!istype(marker) || !istype(marker.landmark))
			continue
		var/datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum = _drydock_shuttle_of(marker)
		if(!istype(shuttle_datum) || shuttle_datum.current_location == marker.landmark)
			continue // already home, nothing to recall
		if(_drydock_recall_ship_home(DS, allow_rehome = FALSE))
			recalled_count++
		else
			failed_count++
	if(recalled_count || failed_count)
		log_drydock("drydockRecallAllDeployed: periodic sweep complete -- [recalled_count] recalled, [failed_count] failed (needs admin attention).")

/// Powers down everything a stashing ship shouldn't come back still running:
/// its engines, its shield generator, and its cloaking device.
///
/// Without this the saved interior records them mid-operation, so a retrieved
/// ship arrives already burning fuel/projecting shields/cloaked with nobody
/// having switched anything on this session -- and, for the cloak especially,
/// an invisible ship nobody knows is theirs. Not a refusal: stashing simply
/// does the shutdown on the player's behalf.
///
/// Drives the exact same controls a player would use by hand -- engines_state
/// plus each datum/ship_engine's own toggle() (the pair engine_control.dm's
/// "global_toggle"/"engine_toggle" actions drive), and each device's own
/// _set_active(FALSE) -- so every UI reading them live simply reflects the
/// change on its next poll, with no TGUI work needed anywhere.
/proc/_drydock_power_down_ship_systems(datum/drydock_ship/DS)
	if(!DS || !DS.z)
		return
	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
	if(!istype(marker))
		return

	if(marker.engines_state)
		marker.engines_state = FALSE
		log_drydock("_drydock_power_down_ship_systems: cleared engines_state for shuttle_id=[DS.shuttle_id] before stash.")
	for(var/datum/ship_engine/E as anything in marker.engines)
		if(E.is_on())
			E.toggle()

	// The registry loop above is only as good as sync_ship_registration(),
	// which the still-open "no engines detected" problem shows is not reliably
	// populating marker.engines -- so clearing engines_state appeared to work
	// while every individual engine kept running. Sweep the ship's own z for
	// the real machines instead of trusting the registry. Sensors get switched
	// off here too (use_power IS their on/off state, see shipsensors/toggle()).
	for(var/zlevel in marker.map_z)
		for(var/obj/structure/machinery/atmospherics/unary/engine/nozzle in SSmachinery.machinery)
			if(GET_Z(nozzle) == zlevel && nozzle.use_power)
				nozzle.update_use_power(POWER_USE_OFF)
		for(var/obj/structure/machinery/ion_engine/ion in SSmachinery.machinery)
			if(GET_Z(ion) == zlevel && ion.on)
				ion.on = FALSE
		for(var/obj/structure/machinery/shipsensors/sensors in SSmachinery.machinery)
			if(GET_Z(sensors) == zlevel && sensors.use_power)
				sensors.toggle()

	if(istype(marker.shield_generator) && marker.shield_generator.active)
		marker.shield_generator._set_active(FALSE)
		log_drydock("_drydock_power_down_ship_systems: powered down the shield generator for shuttle_id=[DS.shuttle_id] before stash.")

	// No back-reference from the ship to its own cloak (unlike shield_generator,
	// ship.dm) -- same SSmachinery scan _ship_gun.dm's own fire() already uses
	// to force-uncloak a firing ship.
	for(var/obj/structure/machinery/ship_cloaking_device/CD in SSmachinery.machinery)
		if(CD.linked != marker || !CD.active)
			continue
		CD._set_active(FALSE)
		log_drydock("_drydock_power_down_ship_systems: powered down the cloaking device for shuttle_id=[DS.shuttle_id] before stash.")

/// Anchors a ship's own home landmark to its docking transponder: one tile
/// outside the hull, on the exact side the transponder faces.
///
/// attempt_move() (shuttle.dm) translates a docking ship by
/// `destination - current_location`, using the home landmark as the ship's
/// whole reference point. A landmark left at a template's mapped default --
/// dead centre of the room, for player_built_shuttle -- therefore lands the
/// hull's CENTRE on the target beacon, shoving roughly half the hull
/// (4 tiles of a 9x9) into whatever sits behind it. Since is_valid() gates
/// the destination LIST as well as the move itself, that doesn't merely fail
/// to dock: it makes every beacon near any structure silently vanish from
/// the shuttle console's destination picker.
///
/// Anchoring to the transponder instead makes the ship's own airlock land
/// directly adjacent to the target beacon -- two airlocks genuinely meeting,
/// which is what the transponder/beacon pairing was always meant to express.
///
/// Called from BOTH commission and retrieve deliberately. Retrieve rebuilds
/// the ship's Z from its template, which restores the template's own centred
/// landmark and would otherwise silently undo this on a ship's very first
/// stash/retrieve cycle -- so a ship must be repositioned identically on both
/// paths or it docks differently before and after being stashed.
///
/// No-ops (logging, leaving the template default alone) rather than guessing
/// if the ship carries no transponder -- a mapper-authored template ship's
/// landmark is placed deliberately and must never be moved.
/proc/_drydock_reposition_ship_landmark(obj/effect/overmap/visitable/ship/landable/marker, datum/shuttle/shuttle_datum, context)
	if(!istype(marker) || !istype(marker.landmark) || !istype(shuttle_datum))
		log_drydock_error("_drydock_reposition_ship_landmark: no marker/landmark/shuttle for [context] -- landmark left at template default, docking may be misaligned.")
		return FALSE
	var/obj/structure/machinery/docking_transponder/transponder = shuttle_datum.find_docking_transponder()
	if(!istype(transponder))
		log_drydock("_drydock_reposition_ship_landmark: no docking transponder aboard for [context] -- landmark left as mapped (expected for a template ship).")
		return FALSE
	var/turf/transponder_turf = get_turf(transponder)
	if(!transponder_turf)
		return FALSE
	var/turf/anchor = get_step(transponder_turf, transponder.dir)
	if(!anchor)
		log_drydock_error("_drydock_reposition_ship_landmark: transponder at ([transponder_turf.x],[transponder_turf.y],[transponder_turf.z]) faces off the map edge for [context] -- landmark left at template default.")
		return FALSE
	marker.landmark.forceMove(anchor)
	log_drydock("_drydock_reposition_ship_landmark: anchored landmark to the transponder at ([anchor.x],[anchor.y],[anchor.z]) for [context].")
	return TRUE

/// Re-files a ship's own restricted waypoints under its NEW shuttle name
/// after the per-instance uniqueness rename.
///
/// find_z_levels() (landable.dm) registers the ship's own "Open Space" home
/// landmark with `add_landmark(landmark, shuttle)` -- a RESTRICTED waypoint
/// keyed by the shuttle's name string at template-load time, deliberately so
/// that landmark belongs to this ship alone and no other vessel can target it.
/// Commission/retrieve then rename the shuttle datum to "[name] #[id]" for
/// registry uniqueness. get_waypoints() (sectors.dm) only ever looks
/// restricted_waypoints up under the CURRENT name, so without this the home
/// landmark stays filed under a key nothing will ever ask for again: it
/// silently vanishes from every destination list and the ship can never
/// undock. (The FORE/PORT/AFT/STARBOARD visiting slots keep working because
/// those are registered as GENERIC waypoints.)
///
/// A re-key, never a downgrade to generic -- the exclusivity is the point.
/proc/_drydock_rekey_ship_waypoints(obj/effect/overmap/visitable/ship/landable/marker, old_name, new_name)
	if(!istype(marker) || !old_name || !new_name || old_name == new_name)
		return
	var/list/moved = LAZYACCESS(marker.restricted_waypoints, old_name)
	if(length(moved))
		for(var/obj/effect/shuttle_landmark/L in moved)
			// Keep the landmark's own idea of its owner in step, so a later
			// cross-z forceMove() (landmarks.dm) re-registers it under the new
			// key instead of resurrecting the stale one.
			L.shuttle_restricted = new_name
		LAZYSET(marker.restricted_waypoints, new_name, moved)
	LAZYREMOVE(marker.restricted_waypoints, old_name)
	// visiting_shuttle/is_valid() (landable.dm) resolves its governing shuttle
	// via SSshuttle.shuttles[core_landmark.shuttle_name] and dereferences the
	// result -- a stale name there returns null and runtimes every check.
	if(istype(marker.landmark))
		marker.landmark.shuttle_name = new_name

/// This ship's own "Open Space" home landmark, resolved defensively, with
/// `marker.landmark` repaired in place whenever a fallback had to be used.
///
/// `marker.landmark` is assigned in exactly one place --
/// populate_sector_objects() (landable.dm) -- which early-returns and retries
/// on a 2-second timer whenever the shuttle datum isn't registered yet. A
/// runtime retrieve can lose that race, leaving the var null with nothing to
/// ever set it again. Everything that needs to send a ship home reads it, so
/// one lost race silently breaks undocking, force-recall, Force Stash, and
/// Clear Docking Beacons all at once.
///
/// Falls back to the shuttle datum's own logging_home_tag -- the same
/// resolution _drydock_evict_docked_shuttle() already uses for non-drydock
/// shuttles, and for a player-built hull that tag is exactly
/// "nav_drydock_ship_player_built_shuttle_space" -- then to current_location
/// when it already IS a ship landmark. Returns null only when a ship genuinely
/// has no home to return to, which callers must treat as a hard failure rather
/// than "nothing to do".
/// TRUE when this ship is physically sitting in its own open space.
///
/// Deliberately NOT an object-identity comparison against marker.landmark.
/// That reference goes stale -- a landmark re-created by a rehome, or replaced
/// across a stash/retrieve cycle while the marker kept pointing at the old one
/// -- and comparing against a stale value reports a ship parked at home as
/// "docked", greying out Stash with no way for the player to ever clear it.
///
/// A ship's own dedicated z IS its open space -- GLOB.persistence_ship_z holds
/// that claim for as long as it is deployed, and no other ship can be given it.
/// So being anywhere on that z is being home.
///
/// Deliberately NOT narrowed to "parked at the /ship home landmark". A hull can
/// legitimately sit on its own z at a landmark that is not the home one -- most
/// commonly its own landmark_transition, which player_built_shuttle.dm maps on
/// that same z. To the player that is plainly open space (the transit
/// landmark's base_turf is /turf/space), and requiring the exact home landmark
/// reported them as "docked" with no way to clear it, since the hop from
/// transit to home overlaps the hull with itself and is refused outright.
///
/// Stashing from anywhere on the z is safe: shipInteriorSave() captures the
/// whole z regardless of which landmark the hull is parked at, and a retrieve
/// re-seats current_location from the template anyway.
///
/// Used by both _drydockStashRun()'s refusal and the schematic's own
/// away_from_home field, so the greyed-out button and the server can never
/// disagree about whether a stash is allowed.
/proc/_drydock_ship_is_home(datum/drydock_ship/DS, datum/shuttle/shuttle_datum)
	if(!DS || !DS.z || !istype(shuttle_datum) || !istype(shuttle_datum.current_location))
		return FALSE
	var/turf/here = get_turf(shuttle_datum.current_location)
	if(!here || here.z != DS.z)
		return FALSE
	// The LANDMARK being home is not proof the HULL is. A move whose translation
	// came out empty still updates current_location and reports success, so the
	// bookkeeping can say "home" with the hull physically still at the away site
	// it never left. Believing that is what let a stash save an empty z and tear
	// it down while the real ship sat elsewhere. Require the hull to actually be
	// present on this z -- get_hull_turfs() is already scoped to
	// current_location's own z, so a non-empty result means it is genuinely here.
	return length(shuttle_datum.get_hull_turfs()) > 0

/proc/_drydock_resolve_home_landmark(obj/effect/overmap/visitable/ship/landable/marker, datum/shuttle/shuttle_datum)
	if(!istype(marker))
		return null
	// Validated, not merely type-checked. A landmark that is no longer on one
	// of the marker's own z-levels is a stale reference (a rehome built a new
	// one elsewhere, or a stash/retrieve cycle replaced it while the marker
	// kept the old pointer). Trusting it is what made recall no-op and the UI
	// report a docked ship that was already home -- fall through to the
	// recovery chain below instead of returning it.
	if(istype(marker.landmark) && (marker.landmark.z in marker.map_z))
		return marker.landmark

	var/obj/effect/shuttle_landmark/recovered
	if(istype(shuttle_datum) && shuttle_datum.logging_home_tag)
		recovered = SSshuttle.get_landmark(shuttle_datum.logging_home_tag)
	if(!istype(recovered) && istype(shuttle_datum) && istype(shuttle_datum.current_location, /obj/effect/shuttle_landmark/ship))
		recovered = shuttle_datum.current_location

	if(istype(recovered))
		// Self-heal: put it back where every other caller expects to find it,
		// so this only ever has to be recovered once.
		marker.landmark = recovered
		log_drydock_warning("_drydock_resolve_home_landmark: marker.landmark was missing for '[marker.shuttle]' -- recovered '[recovered.landmark_tag]' and repaired it in place.")
	return recovered

/// The first turf in `envelope` that a shuttle's own area covers, or null.
///
/// The authoritative "is a ship physically sitting here" test, derived from
/// the turfs themselves rather than from any bookkeeping var. Docking is real
/// turf relocation (translate_turfs(), shuttle.dm) and carries AREA membership
/// with it, so a shuttle area covering these tiles means a hull is genuinely
/// on them -- no matter what current_location claims.
///
/// Exists because trusting current_location got a live ship deleted: the
/// "Clear Docking Beacons" verb matched docked ships by
/// `current_location == pad`, found none (that var goes stale after the
/// uniqueness rename), and wiped the envelope with the hull still on it.
/// Any destructive envelope operation must consult this FIRST and refuse.
/proc/_drydock_envelope_shuttle_turf(list/turf/envelope)
	for(var/turf/T in envelope)
		var/area/A = get_area(T)
		if(A && (A in SSshuttle.shuttle_areas))
			return T
	return null

/// TRUE if any ship commissioning console currently claims this beacon --
/// either resolved live, or still only as a restored-but-not-yet-resolved
/// saved tag (linked_beacon_tag, ship_commissioning_console.dm), so a link
/// that simply hasn't been touched since a reboot still counts.
/proc/_drydock_beacon_is_commission_linked(obj/structure/machinery/docking_beacon/beacon)
	for(var/obj/structure/machinery/computer/ship_commissioning/console in SSmachinery.machinery)
		if(console.linked_beacon == beacon)
			return TRUE
		if(beacon.landmark_tag && console.linked_beacon_tag == beacon.landmark_tag)
			return TRUE
	return FALSE

/// Forgets the saved turf/object rows inside every ACTIVE docking beacon's
/// own landing envelope, every save.
///
/// A beacon's envelope is a landing pad, not persistent ground: an arriving
/// hull physically overwrites those tiles (shuttle_moved(), shuttle.dm) and
/// departure reverts them, so nothing there is meant to survive a reboot on
/// its own. Meanwhile a ship that happens to be docked when a save fires can
/// leak its hull rows into the HOST z's own scope -- Part 8c's
/// persistence_turf_docked_elsewhere() exclusion is supposed to stop that,
/// but it's rebuilt on a 30-second sweep and its own doc comment concedes a
/// staleness window. Rather than keep chasing that window, this simply makes
/// the pad unable to reconstruct anything at all, whatever wrote the row.
///
/// Deliberate, accepted tradeoff: turf/equipment changes inside a live
/// beacon's landing envelope do not persist across a reboot.
///
/// Two exemptions:
///  * An INACTIVE beacon is skipped entirely -- it isn't a landing
///    destination, carries no duplication risk, and its surroundings stay
///    ordinary persistent space.
///  * A beacon linked to a ship commissioning console is skipped entirely --
///    a player may have a hull under construction in that envelope, which
///    absolutely must persist.
/datum/controller/subsystem/persistence/proc/drydockForgetBeaconEnvelopes()
	var/swept = 0
	for(var/obj/structure/machinery/docking_beacon/beacon in SSmachinery.machinery)
		if(!beacon.beacon_active)
			continue
		if(_drydock_beacon_is_commission_linked(beacon))
			continue
		var/list/envelope = beacon.get_envelope_turfs()
		if(!length(envelope))
			continue
		// Never forget rows while a hull is physically on these tiles. Two
		// distinct hazards, one check:
		//  * A beacon built ABOARD a ship puts its envelope on that ship's own
		//    z, so persistence_scope_for_z() resolves to "ship:d:<id>" and this
		//    sweep would delete that ship's OWN saved turf/object rows -- every
		//    single save.
		//  * A ship docked here at save time is genuinely sitting on those
		//    coordinates, and its content is not the pad's to discard.
		// Same physical-presence rule clear_docking_beacons() uses, and for the
		// same reason: bookkeeping can drift, turf area membership cannot.
		var/turf/occupied = _drydock_envelope_shuttle_turf(envelope)
		if(occupied)
			log_drydock("drydockForgetBeaconEnvelopes: skipped beacon '[beacon.landmark_tag]' -- a ship's hull ([get_area(occupied)]) is physically on its envelope.")
			continue
		turfsForget(envelope)
		objectsForget(envelope)
		swept++
		CHECK_TICK
	if(swept)
		log_drydock("drydockForgetBeaconEnvelopes: cleared saved turf/object rows for [swept] active beacon envelope(s).")

/// Called from _drydockStashRun()'s force path right before the interior
/// actually gets torn down -- force-persists every living human occupant
/// off DS's own Z (and any bound sub-ship's own area) via whatever cryopod
/// is reachable there, and vaults every loose (non-occupied) neural lace on
/// the same scope, so a real stash (shutdown, Force Stash Ship/All) never
/// has to just give up on a ship the way a normal, player-initiated stash
/// still does via _drydock_ship_has_living_occupants() right after this.
/// cryopod/persistence_force_store() (cryopod.dm) already does everything
/// needed -- it accepts an arbitrary human mob (not just its own current
/// occupant) and moves/persists them itself, so this never needs to
/// physically walk anyone into a pod first. Deliberately does NOT attempt
/// to handle a neural-lace consciousness (lace_occupied/lace_mob,
/// _drydock_ship_has_living_occupants()'s other check) -- a lace_mob has no
/// body for a cryopod to freeze, so persistence_force_store() correctly
/// refuses it (istype() gate on mob/living/carbon/human) and that case
/// still falls through to a clean abort below, same as today.
/// Returns FALSE if any living occupant couldn't be safely evacuated this
/// way -- the caller aborts the stash cleanly rather than risk stranding
/// someone.
/datum/controller/subsystem/persistence/proc/_drydock_evacuate_occupants_before_stash(datum/drydock_ship/DS)
	if(!DS.z)
		return TRUE
	var/list/zs = list(DS.z)
	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
	if(template && length(template.sub_shuttle_tags))
		for(var/sub_tag in template.sub_shuttle_tags)
			var/datum/shuttle/autodock/sub = SSshuttle.shuttles[_drydock_subship_key(DS.shuttle_id, sub_tag)]
			if(istype(sub) && istype(sub.current_location))
				zs |= sub.current_location.z

	for(var/mob/M in GLOB.mob_list)
		if(!(M.z in zs) || M.stat == DEAD || !(M.client || M.ckey))
			continue
		// Prefer a pod on the ship's own z, but persistence_force_store()
		// (cryopod.dm) never actually requires the mob be anywhere near the
		// pod first -- it forceMove()s them to just outside itself before
		// persisting, so any pod anywhere in the game works as a fallback
		// when this specific z has none of its own (a bare-bones player-built
		// hull with no cryopod built in, most commonly). Among fallback pods
		// elsewhere, rank the evacuee's own faction above public/unassigned,
		// and never fall back to a pod belonging to a DIFFERENT, non-allied
		// faction at all -- waking up in a rival faction's own vault is worse
		// than aborting the stash outright. Only actually fails if no pod on
		// the ship's own z, no same-faction/allied pod, and no public pod
		// exists anywhere on the server.
		var/obj/item/card/id/evac_id = M.GetIdCard()
		var/evac_faction = (evac_id && evac_id.employer_faction) ? normalize_faction_uid(evac_id.employer_faction) : null
		var/obj/structure/machinery/cryopod/pod
		var/obj/structure/machinery/cryopod/same_faction_pod
		var/obj/structure/machinery/cryopod/public_pod
		for(var/obj/structure/machinery/cryopod/candidate in SSmachinery.machinery)
			if(istype(candidate, /obj/structure/machinery/cryopod/prison))
				continue // a prison cell is detention, not evacuation -- never an implicit destination
			if(GET_Z(candidate) == M.z)
				pod = candidate
				break
			var/pod_faction = candidate.persistent_network
			if(!pod_faction || pod_faction == "public")
				if(!public_pod)
					public_pod = candidate
				continue
			pod_faction = normalize_faction_uid(pod_faction)
			if(evac_faction && pod_faction == evac_faction)
				if(!same_faction_pod)
					same_faction_pod = candidate
				continue
#ifdef FACTION_ALLIANCES
			if(evac_faction && factions_are_allied(evac_faction, pod_faction))
				if(!same_faction_pod)
					same_faction_pod = candidate
				continue
#endif
			// Belongs to a different, non-allied faction -- never used as a
			// fallback, opposing or not; only this evacuee's own faction and
			// public/unassigned pods are acceptable stand-ins.
		if(!pod)
			pod = same_faction_pod || public_pod
		if(!pod || !pod.persistence_force_store(M))
			log_drydock_error("_drydock_evacuate_occupants_before_stash: could not safely evacuate living occupant '[key_name(M)]' from shuttle_id=[DS.shuttle_id] (no cryopod on this z, and no same-faction/public cryopod exists elsewhere, or not an ordinary human) -- aborting stash.")
			return FALSE
		log_drydock("_drydock_evacuate_occupants_before_stash: force-stored '[key_name(M)]' off shuttle_id=[DS.shuttle_id] before stash[GET_Z(pod) == M.z ? "" : " (via a pod elsewhere -- none on this ship's own z)"].")

	var/list/lace_result = SSpersistence.vaultAllLaces(zs)
	if(lace_result && lace_result["vaulted"])
		log_drydock("_drydock_evacuate_occupants_before_stash: vaulted [lace_result["vaulted"]] loose neural lace(s) from shuttle_id=[DS.shuttle_id] before stash.")
	return TRUE

/// Shared non-destructive world-footprint teardown for a currently-deployed
/// ship at z: qdels the marker (nulling every GLOB.map_sectors entry it
/// claimed FIRST -- a dangling entry is a live landmine, looked up unchecked
/// in ~90 places across the codebase), tears down/pools the Z, and clears
/// GLOB.persistence_ship_z. Used by drydockStash() (above) and
/// drydockScuttle() (below) alike -- neither the ledger row nor the scoped
/// content tables are touched here, only the live world state, so this is
/// also exactly what drydock_ship/Destroy()'s defensive orphan-recovery check
/// (drydock_ship.dm) calls when a marker is destroyed some other way.
/datum/controller/subsystem/persistence/proc/_drydockMarkerTeardown(z)
	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[z]"]
	var/datum/shuttle/shuttle_datum = istype(marker) ? _drydock_shuttle_of(marker) : null
	var/shuttle_name = shuttle_datum?.name
	if(istype(marker))
		// Evacuate anything currently docked WITH this ship before it's
		// qdeleted -- on_landing() (landable.dm) forceMove()s a docking
		// ship's marker directly into the TARGET marker's own contents (the
		// same mechanism the built-in FORE/PORT/AFT/STARBOARD visiting_shuttle
		// slots use, and now also public hangar_slot landmarks,
		// docking_beacon.dm). qdel() below does not relocate contents first,
		// so anything still nested here -- independently owned or not --
		// would otherwise be destroyed or orphaned alongside this marker.
		// Kicked back to open space exactly like a normal undock
		// (on_takeoff()'s own forceMove(get_turf(loc))+unhalt()), not
		// destroyed -- this ship isn't the guest's to lose just because its
		// host stashed out from under it.
		for(var/obj/effect/overmap/visitable/ship/landable/guest in marker.contents)
			// My own sub-ship goes down WITH me -- it's part of this hull, and
			// it comes back from the template on the next retrieve. Kicking it
			// to open space like a foreign guest would leave it drifting,
			// orphaned, the moment its carrier stashed.
			if(_drydock_guest_is_own_subship(guest, marker))
				continue
			var/turf/safe_turf = get_turf(marker)
			if(safe_turf)
				guest.forceMove(safe_turf)
				guest.unhalt()
				guest.status = SHIP_STATUS_OVERMAP
				log_drydock_warning("_drydockMarkerTeardown: evacuated docked guest ship '[guest.shuttle]' from '[marker.shuttle]' before teardown.")
			else
				log_drydock_error("_drydockMarkerTeardown: could not find a safe turf to evacuate guest ship '[guest.shuttle]' from '[marker.shuttle]' -- left in place, needs admin attention.")
		for(var/zlevel in marker.map_z)
			GLOB.map_sectors["[zlevel]"] = null
		qdel(marker)
	else
		log_drydock_warning("_drydockMarkerTeardown: no overmap marker found at z=[z] -- already gone?")
	GLOB.persistence_ship_z -= "[z]"
	shipZTeardown(z, shuttle_name)

// ============================================================
// SCUTTLE  permanent, player-facing, fee-gated removal from anywhere
// ============================================================

#define DRYDOCK_SCUTTLE_FEE 25000

/// Self-service permanent removal -- the player-facing answer to a ship
/// that's stuck, damaged, or unreachable, closing the gap that previously
/// only an admin's Force Stash Ship verb covered (and that one still doesn't
/// delete anything). Works regardless of location/docked state, deployed or
/// already stashed alike -- unlike stash, there's no proximity requirement,
/// since the whole point is rescuing a ship you can't get back to. Always
/// logged to admins with a JMP link, and always costs a real fee so it isn't
/// a free escape hatch.
///
/// hub_authority = TRUE is the First Responder ship-seizure tap's "Scuttle"
/// mode (handle_ship_seizure_tap(), first_responder.dm) -- an officer-rank+
/// Hub security member destroying someone ELSE's ship as an enforcement
/// action, not the owner's own self-service escape hatch. That path already
/// verified Hub officer rank before calling in, so it bypasses both the
/// ownership permission check and the fee -- an officer doing their job
/// shouldn't have to personally pay 25000cr to destroy seized contraband.
/// Permanently deletes a stashed ship from storage with no fee (unlike
/// drydockScuttle() below, which charges DRYDOCK_SCUTTLE_FEE and works
/// whether deployed or stashed) -- extracted from drydock.dm's old inline
/// "sell" ui_act branch so ship_schematic.dm's own sell action can call it
/// without duplicating the DB cleanup. Self-contained gating, same shape as
/// drydockScuttle(): looks up the ship and checks permission/busy-state
/// itself rather than trusting the caller already did. Confirmation dialogs
/// stay in whichever UI calls this, same as drydockScuttle()'s own.
/datum/controller/subsystem/persistence/proc/drydockSell(shuttle_id, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	if(!databaseCheckConnection("drydockSell"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE

	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS)
		log_drydock_warning("drydockSell: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	var/ship_display_name = DS.display_name()
	if(!DS.stashed)
		if(user)
			to_chat(user, SPAN_WARNING("Stash the ship before removing it."))
		log_drydock_warning("drydockSell: refused -- shuttle_id=[shuttle_id] still deployed (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to remove this ship."))
		log_drydock_warning("drydockSell: refused -- [acting] lacks permission for shuttle_id=[shuttle_id].")
		return FALSE
	if(_drydock_ship_busy(shuttle_id))
		if(user)
			to_chat(user, SPAN_WARNING("That ship is still being retrieved/stashed -- wait for it to finish."))
		log_drydock_warning("drydockSell: refused -- shuttle_id=[shuttle_id] busy (acting=[acting]).")
		return FALSE

	_shipCentralDelete(DS.global_ship_id)
	var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_drydock_ships WHERE shuttle_id = :id", list("id" = shuttle_id))
	dq.Execute()
	if(!databaseCheckQueryResult(dq, "drydockSell delete"))
		log_drydock_error("drydockSell: DB delete failed for shuttle_id=[shuttle_id].")
		qdel(dq)
		return FALSE
	qdel(dq)

	// Purge the ship's saved interior too -- a sold ship's scope must never
	// resurrect onto some future hull that happens to reuse the same
	// shuttle_id.
	purgeShipScopeRows("ship:d:[shuttle_id]")
	var/datum/db_query/bdq = SSdbcore.NewQuery("DELETE FROM ss13_drydock_ships_backup WHERE shuttle_id = :id", list("id" = shuttle_id))
	bdq.Execute()
	databaseCheckQueryResult(bdq, "drydockSell backup delete")
	qdel(bdq)
	var/datum/db_query/crdq = SSdbcore.NewQuery("DELETE FROM ss13_ship_crew WHERE shuttle_id = :id", list("id" = shuttle_id))
	crdq.Execute()
	databaseCheckQueryResult(crdq, "drydockSell crew delete")
	qdel(crdq)
	// A stashed ship's ledger datum still lives in GLOB.drydock_ships (keyed
	// by string, see drydockScuttle's identical fix) -- without this it
	// would linger there after the DB row is gone.
	GLOB.drydock_ships -= "[shuttle_id]"

	if(user)
		to_chat(user, SPAN_GOOD("Ship removed."))
	log_and_message_admins("permanently removed drydock ship '[ship_display_name]' (#[shuttle_id]) from storage (no fee).", user)
	log_drydock("drydockSell: [acting] permanently deleted shuttle_id=[shuttle_id] from the drydock DB.")
	return TRUE

/datum/controller/subsystem/persistence/proc/drydockScuttle(shuttle_id, mob/user, hub_authority = FALSE)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_drydock("drydockScuttle: [acting] attempting to scuttle shuttle_id=[shuttle_id][hub_authority ? " (Hub authority)" : ""].")

	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS)
		log_drydock_warning("drydockScuttle: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(hub_authority || check_rights(R_ADMIN, 0, user) || DS.owned_by(user)))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to scuttle this ship."))
		log_drydock_warning("drydockScuttle: refused -- [acting] lacks permission for shuttle_id=[shuttle_id].")
		return FALSE

	var/was_deployed = !DS.stashed
	if(was_deployed && zlevel_has_players(DS.z))
		if(user)
			to_chat(user, SPAN_WARNING("Make sure everyone is off the ship first."))
		log_drydock_warning("drydockScuttle: refused -- players still present on z=[DS.z] for shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	if(!databaseCheckConnection("drydockScuttle"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed -- scuttle not completed."))
		log_drydock_error("drydockScuttle: database connection failed for shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	var/fee_paid = 0
	if(!hub_authority)
		if(!user)
			log_drydock_error("drydockScuttle: refused -- no user to charge the fee to for shuttle_id=[shuttle_id].")
			return FALSE
		var/obj/item/card/id/ID = user.GetIdCard()
		if(!ID || !ID.associated_account_number)
			to_chat(user, SPAN_WARNING("No linked bank account."))
			log_drydock_warning("drydockScuttle: refused -- [acting] has no linked bank account.")
			return FALSE
		var/datum/money_account/acc = SSeconomy.get_account(ID.associated_account_number)
		if(!acc || acc.money < DRYDOCK_SCUTTLE_FEE)
			to_chat(user, SPAN_WARNING("Insufficient funds -- scuttling costs [DRYDOCK_SCUTTLE_FEE]cr."))
			log_drydock_warning("drydockScuttle: refused -- [acting] has insufficient funds to scuttle shuttle_id=[shuttle_id].")
			return FALSE
		acc.adjust_money(-DRYDOCK_SCUTTLE_FEE)
		fee_paid = DRYDOCK_SCUTTLE_FEE

	return _drydockScuttleFinish(shuttle_id, DS, was_deployed, user, acting, fee_paid)

/// Shared deletion body for drydockScuttle() above -- ledger/backup/crew row
/// removal, marker teardown, and admin/chat/log reporting. fee_paid is 0 for
/// a Hub-authority seizure (no charge), else DRYDOCK_SCUTTLE_FEE.
/datum/controller/subsystem/persistence/proc/_drydockScuttleFinish(shuttle_id, datum/drydock_ship/DS, was_deployed, mob/user, acting, fee_paid)
	PRIVATE_PROC(TRUE)
	var/obj/effect/overmap/visitable/marker = was_deployed ? GLOB.map_sectors["[DS.z]"] : null
	var/atom/jmp_target = (was_deployed && marker) ? marker : user
	var/ship_display_name = DS.display_name()
	var/deployed_z = DS.z

	// Ledger row (and its GLOB.drydock_ships entry) is fully gone BEFORE the
	// marker is torn down below -- the qdel fires drydock_ship/Destroy()'s
	// defensive orphan-recovery check (drydock_ship.dm), which only acts on
	// a shuttle_id it can still find in GLOB.drydock_ships. Deleting first
	// means that check correctly finds nothing to "recover" here.
	SSpersistence.purgeShipScopeRows("ship:d:[shuttle_id]")

	_shipCentralDelete(DS.global_ship_id)
	var/datum/db_query/dq = SSdbcore.NewQuery("DELETE FROM ss13_drydock_ships WHERE shuttle_id = :id", list("id" = shuttle_id))
	dq.Execute()
	databaseCheckQueryResult(dq, "drydockScuttle delete")
	qdel(dq)
	var/datum/db_query/bdq = SSdbcore.NewQuery("DELETE FROM ss13_drydock_ships_backup WHERE shuttle_id = :id", list("id" = shuttle_id))
	bdq.Execute()
	databaseCheckQueryResult(bdq, "drydockScuttle backup delete")
	qdel(bdq)
	var/datum/db_query/crdq = SSdbcore.NewQuery("DELETE FROM ss13_ship_crew WHERE shuttle_id = :id", list("id" = shuttle_id))
	crdq.Execute()
	databaseCheckQueryResult(crdq, "drydockScuttle crew delete")
	qdel(crdq)

	// GLOB.drydock_ships is keyed by string everywhere else (see the lookup
	// two lines up in the caller, and every assignment into this list) --
	// removing by the raw number here never matched the string-keyed entry,
	// so the ledger datum was never actually removed despite the comment
	// above, leaking a stale entry that drydock_ship/Destroy()'s orphan-
	// recovery check later found and misreported as "destroyed outside
	// sanctioned flow."
	GLOB.drydock_ships -= "[shuttle_id]"

	if(was_deployed)
		SSpersistence._drydockMarkerTeardown(deployed_z)

	if(fee_paid)
		log_and_message_admins("SCUTTLED their ship '[ship_display_name]' (#[shuttle_id]) for [fee_paid]cr.", user, get_turf(jmp_target))
		if(user)
			to_chat(user, SPAN_GOOD("Ship scuttled -- gone for good."))
		log_drydock("drydockScuttle: [acting] permanently scuttled shuttle_id=[shuttle_id] ('[DS.template_id]') for [fee_paid]cr, was_deployed=[was_deployed].")
	else
		log_and_message_admins("SCUTTLED '[ship_display_name]' (#[shuttle_id]) under Hub officer authority (no fee).", user, get_turf(jmp_target))
		log_drydock("drydockScuttle: [acting] permanently scuttled shuttle_id=[shuttle_id] ('[DS.template_id]') under Hub authority, was_deployed=[was_deployed].")
	return TRUE

#undef DRYDOCK_SCUTTLE_FEE

// ============================================================
// SHUTDOWN SAFETY NET  called from SSpersistence.Shutdown()/forceSaveAll()
// ============================================================

/// Force-stashes every deployed drydock ship at shutdown -- called only
/// from SSpersistence.Shutdown(), NOT the periodic autosave (a deployed
/// ship's interior now saves in place via the ordinary per-Z Finalize
/// sweeps, see persistence_ship_interiors.dm -- the periodic path no longer
/// needs to tear ships down to persist them).
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

/// On-demand recall/stash tool -- covers the gap the automatic shutdown
/// sweep (drydockAutoStashAll()) doesn't: forcing a specific ship home
/// right now, not just at server shutdown.
/datum/admins/proc/force_stash_ship()
	set name = "Force Stash Ship"
	set category = "Persistence.Ships & Drydock"
	if(!check_rights(R_ADMIN))
		return

	var/list/options = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(DS && !DS.stashed)
			options["[DS.template_id] #[sid] ([DS.faction_uid ? "faction [DS.faction_uid]" : "owner [DS.owner_ckey]"])"] = sid

	if(!length(options))
		to_chat(usr, SPAN_WARNING("No deployed drydock ships found."))
		return

	var/pick = tgui_input_list(usr, "Force-stash which ship?", "Force Stash Ship", options)
	if(!pick)
		return

	SSpersistence.drydockStash(options[pick], usr, force = TRUE)

/// A name stays blocked in _drydock_name_taken() for as long as its
/// GLOB.drydock_ships row exists, with no self-service way to free it once
/// the schematic proving ownership is genuinely gone -- drydockScuttle()'s
/// own doc comment already concedes "a lost/destroyed schematic has no
/// other way back short of an admin's intervention." Lists EVERY ship
/// (stashed and deployed both, unlike force_stash_ship() above), tagging
/// each with whether it's actually reachable -- a live schematic somewhere
/// in the world, or banked -- so an orphaned one is immediately obvious.
/// Not restricted to only orphaned ships, same as force_stash_ship() isn't
/// restricted to only broken ones.
/datum/admins/proc/free_drydock_ship_name()
	set name = "Free Drydock Ship Name"
	set category = "Persistence.Ships & Drydock"
	if(!check_rights(R_ADMIN))
		return

	var/list/options = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS)
			continue

		var/reachable = DS.schematic_banked
		if(!reachable)
			for(var/obj/item/ship_schematic/S in world)
				if(S.shuttle_id == DS.shuttle_id && S.bound_purchased_at == DS.purchased_at && !S.repossessed)
					reachable = TRUE
					break

		options["[DS.display_name()] #[sid] ([DS.stashed ? "stashed" : "deployed"], [DS.faction_uid ? "faction [DS.faction_uid]" : "owner [DS.owner_ckey]"])[reachable ? "" : " -- ORPHANED, no schematic"]"] = sid

	if(!length(options))
		to_chat(usr, SPAN_WARNING("No drydock ships found."))
		return

	var/pick = tgui_input_list(usr, "Free the name of which ship? (this scuttles it)", "Free Drydock Ship Name", options)
	if(!pick)
		return
	var/shuttle_id = options[pick]

	if(tgui_alert(usr, "Scuttle [pick]? This permanently deletes the ship and frees its name. This cannot be undone.", "Free Drydock Ship Name", list("Scuttle", "Cancel")) != "Scuttle")
		return

	SSpersistence.drydockScuttle(shuttle_id, usr, hub_authority = TRUE)

/// Server-wide version of force_stash_ship() above -- stashes every
/// currently-deployed ship at once via the same sweep drydockAutoStashAll()
/// already runs at shutdown.
/datum/admins/proc/force_stash_all_ships()
	set name = "Force Stash All Ships"
	set category = "Persistence.Ships & Drydock"

	if(!check_rights(R_ADMIN))
		return
	if(tgui_alert(usr, "Force-stash every deployed ship on the map? This cannot be undone per-ship.", "Force Stash All Ships", list("Stash All", "Cancel")) != "Stash All")
		return
	SSpersistence.drydockAutoStashAll()
	log_and_message_admins("force-stashed all deployed ships", usr)
	to_chat(usr, SPAN_GOOD("All deployed ships have been stashed."))

/// Flips whether torn-down ship Z-levels get recycled at all
/// (GLOB.persistence_allow_z_reuse, persistence_ship_interiors.dm). Turning
/// it OFF makes every retrieve load a brand-new z, trading z-level count for
/// a guarantee that no ship can inherit ground another ship left behind --
/// useful when ships are sitting away from the home Z that handles their
/// stashing. In-memory only: resets to the default on reboot.
///
/// Independent of the emptiness verification, which vets every candidate z
/// regardless of this setting.
/datum/admins/proc/toggle_ship_z_reuse()
	set name = "Toggle Ship Z Reuse"
	set category = "Persistence.Ships & Drydock"

	if(!check_rights(R_ADMIN))
		return

	GLOB.persistence_allow_z_reuse = !GLOB.persistence_allow_z_reuse
	if(!GLOB.persistence_allow_z_reuse)
		// Drop whatever's already queued -- leaving it would let the pool be
		// drained the moment someone toggles reuse back on, from Zs torn down
		// while it was meant to be disabled.
		var/dropped = length(GLOB.reusable_z_pool)
		GLOB.reusable_z_pool.Cut()
		to_chat(usr, SPAN_GOOD("Ship Z reuse DISABLED -- every retrieve now loads a brand-new z. Dropped [dropped] pooled z-level\s."))
	else
		to_chat(usr, SPAN_GOOD("Ship Z reuse ENABLED -- torn-down ship z-levels are pooled and recycled again (pool currently empty until the next stash)."))
	log_and_message_admins("set ship Z reuse to [GLOB.persistence_allow_z_reuse ? "ENABLED" : "DISABLED"].", usr)

/// On-demand pad cleanup -- walks every ACTIVE docking beacon, sends whatever
/// is docked there back where it actually belongs (its own home landmark Z,
/// or its own hangar berth for a bound sub-ship), wipes the pad's envelope
/// back to open space, and forgets its saved rows so nothing reconstructs
/// there on the next boot. The manual counterpart to
/// drydockForgetBeaconEnvelopes()'s automatic save-time cleanup, for clearing
/// leftover/duplicated hulls sitting anywhere other than where they belong.
/// Beacons currently linked to a commissioning console are skipped -- a hull
/// may be under construction in that envelope.
/datum/admins/proc/clear_docking_beacons()
	set name = "Clear Docking Beacons"
	set category = "Persistence.Ships & Drydock"

	if(!check_rights(R_ADMIN))
		return

	// Group every active beacon by the overmap sector it actually sits in, so
	// an admin can clear one site's pads without touching anyone else's.
	var/list/beacons_by_sector = list()
	var/total_beacons = 0
	for(var/obj/structure/machinery/docking_beacon/candidate in SSmachinery.machinery)
		if(!candidate.beacon_active)
			continue
		var/obj/effect/overmap/visitable/sector = GLOB.map_sectors["[GET_Z(candidate)]"]
		var/label = sector ? "[sector.name]" : "Unmapped (z=[GET_Z(candidate)])"
		if(!beacons_by_sector[label])
			beacons_by_sector[label] = list()
		beacons_by_sector[label] += candidate
		total_beacons++

	if(!total_beacons)
		to_chat(usr, SPAN_WARNING("No active docking beacons found anywhere."))
		return

	var/list/options = list()
	options["Every sector ([total_beacons] beacon\s)"] = "__all__"
	for(var/label in beacons_by_sector)
		options["[label] ([length(beacons_by_sector[label])] beacon\s)"] = label

	var/pick = tgui_input_list(usr, "Clear docking beacons in which sector?", "Clear Docking Beacons", options)
	if(!pick)
		return
	var/chosen = options[pick]

	var/list/targets = list()
	if(chosen == "__all__")
		for(var/label in beacons_by_sector)
			targets += beacons_by_sector[label]
	else
		targets = beacons_by_sector[chosen]
	if(!length(targets))
		return

	if(tgui_alert(usr, "Evict everything docked at [length(targets)] active docking beacon\s in [chosen == "__all__" ? "EVERY sector" : chosen] and wipe their landing pads back to open space? Ships are returned to their own home Z (sub-ships to their hangar) first. This cannot be undone.", "Clear Docking Beacons", list("Clear", "Cancel")) != "Clear")
		return

	var/cleared = 0
	var/evicted = 0
	var/skipped = 0
	for(var/obj/structure/machinery/docking_beacon/beacon in targets)
		if(QDELETED(beacon) || !beacon.beacon_active)
			continue
		if(_drydock_beacon_is_commission_linked(beacon))
			skipped++
			log_drydock("clear_docking_beacons: skipped beacon '[beacon.landmark_tag]' -- linked to a commissioning console (possible build in progress).")
			continue
		var/list/envelope = beacon.get_envelope_turfs()
		if(!length(envelope))
			continue

		// Evict first -- never wipe turfs out from under a hull still on them.
		var/obj/effect/shuttle_landmark/pad = SSshuttle.registered_shuttle_landmarks[beacon.landmark_tag]
		// Fail CLOSED. This used to be `if(istype(pad))` wrapping only the
		// eviction loop, so an unresolvable pad skipped straight past eviction
		// and wiped anyway -- "couldn't look" was treated as "nothing there",
		// and it deleted a live ship.
		if(!istype(pad))
			skipped++
			log_drydock_error("clear_docking_beacons: beacon '[beacon.landmark_tag]' SKIPPED -- its landmark could not be resolved, so whether anything is docked here is unknown. Refusing to wipe.")
			continue
		var/eviction_failed = FALSE
		for(var/shuttle_name in SSshuttle.shuttles)
			var/datum/shuttle/docked = SSshuttle.shuttles[shuttle_name]
			if(!istype(docked) || docked.current_location != pad)
				continue
			if(!_drydock_evict_docked_shuttle(docked, usr))
				eviction_failed = TRUE
				continue
			evicted++
		if(eviction_failed)
			skipped++
			log_drydock_error("clear_docking_beacons: beacon '[beacon.landmark_tag]' left untouched -- a docked shuttle could not be evicted (see preceding error). Needs admin attention.")
			continue

		// Physical fallback, independent of every var above: if a shuttle area
		// still covers any of these tiles, a hull is genuinely there regardless
		// of what current_location said. Rather than only refusing, resolve
		// that area back to its owning shuttle and evict THAT -- matching by
		// tag/current_location misses a ship whose bookkeeping has drifted,
		// which is how this verb reported "0 shuttles" while a hull sat on the
		// pad. Only if a hull is STILL there afterwards do we refuse.
		var/turf/still_occupied = _drydock_envelope_shuttle_turf(envelope)
		if(still_occupied)
			var/area/occupying_area = get_area(still_occupied)
			for(var/shuttle_name in SSshuttle.shuttles)
				var/datum/shuttle/physical = SSshuttle.shuttles[shuttle_name]
				if(!istype(physical) || !(occupying_area in physical.shuttle_area))
					continue
				log_drydock("clear_docking_beacons: beacon '[beacon.landmark_tag]' -- found '[physical.name]' physically on the envelope via its area, evicting it (nothing reported as docked here).")
				if(_drydock_evict_docked_shuttle(physical, usr))
					evicted++
				break
			still_occupied = _drydock_envelope_shuttle_turf(envelope)
		if(still_occupied)
			skipped++
			log_and_message_admins("clear_docking_beacons: beacon '[beacon.landmark_tag]' REFUSED -- a ship's hull is still physically on its envelope ([get_area(still_occupied)] at ([still_occupied.x],[still_occupied.y],[still_occupied.z])) and could not be evicted. Nothing was wiped.", usr, still_occupied)
			continue

		// Never wipe a pad someone is still standing on -- refuse this one
		// outright rather than leaving them floating in open space. Same gate
		// commissioning itself uses (_drydock_envelope_has_occupants()), so it
		// also covers an occupied neural lace lying there, not just a body.
		if(_drydock_envelope_has_occupants(envelope))
			skipped++
			log_and_message_admins("clear_docking_beacons: refused beacon '[beacon.landmark_tag]' -- someone (or an occupied neural lace) is still inside its envelope.", usr, get_turf(beacon))
			continue

		for(var/turf/T in envelope)
			T.ChangeTurf(get_base_turf_by_area(T))
		SSpersistence.turfsForget(envelope)
		SSpersistence.objectsForget(envelope)
		cleared++
		CHECK_TICK

	log_and_message_admins("cleared [cleared] docking beacon envelope(s) in [chosen == "__all__" ? "every sector" : chosen], evicting [evicted] docked shuttle(s)[skipped ? ", skipping [skipped]" : ""].", usr)
	to_chat(usr, SPAN_GOOD("Cleared [cleared] beacon envelope(s), evicted [evicted] shuttle(s)[skipped ? ", skipped [skipped] (see logs)" : ""]."))

/// Sends one shuttle currently sitting at a docking beacon back to wherever it
/// actually belongs. A deployed drydock ship routes through
/// _drydock_recall_ship_home() (which also recalls its own bound sub-ships);
/// anything else (a lone sub-ship, a mapped shuttle) goes to its own
/// logging_home_tag landmark, which for a bound sub-ship IS its hangar berth.
/// If a drydock ship's home Z no longer exists at all, its saved interior is
/// regenerated via the normal retrieve path first, then recalled into.
/// Returns FALSE only when there's genuinely nowhere legitimate to send it --
/// the caller then leaves that pad alone rather than wiping a live hull.
/proc/_drydock_evict_docked_shuttle(datum/shuttle/docked, mob/user)
	var/obj/effect/overmap/visitable/ship/landable/marker
	for(var/z_key in GLOB.persistence_ship_z)
		var/obj/effect/overmap/visitable/ship/landable/candidate = GLOB.map_sectors[z_key]
		if(istype(candidate) && candidate.shuttle == docked.name)
			marker = candidate
			break

	var/datum/drydock_ship/DS = istype(marker) ? _drydock_ship_at(GET_Z(marker)) : null
	if(DS)
		if(SSpersistence._drydock_recall_ship_home(DS))
			return TRUE
		log_drydock_error("_drydock_evict_docked_shuttle: recall home failed for drydock ship shuttle_id=[DS.shuttle_id] ('[docked.name]').")
		return FALSE

	// Not a live drydock ship -- try its own mapped home landmark.
	var/obj/effect/shuttle_landmark/home = docked.logging_home_tag ? SSshuttle.get_landmark(docked.logging_home_tag) : null
	if(istype(home))
		if(docked.current_location == home)
			return TRUE
		var/datum/shuttle/autodock/auto = docked
		if(istype(auto))
			auto.moving_status = SHUTTLE_IDLE
			auto.next_location = null
			auto.in_use = null
			auto.set_process_state(IDLE_STATE)
		if(docked.attempt_move(home))
			return TRUE
		log_drydock_error("_drydock_evict_docked_shuttle: attempt_move home refused for '[docked.name]' (home '[docked.logging_home_tag]' -- blocked or grappled).")
		return FALSE

	// No live ship and no resolvable home landmark. If this shuttle belongs to
	// a ledgered drydock ship whose Z is simply gone (stashed/torn down),
	// regenerating it via the normal retrieve path is the legitimate way back;
	// there is nothing safe to fabricate for anything else.
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/candidate_DS = GLOB.drydock_ships[sid]
		if(!candidate_DS)
			continue
		var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[candidate_DS.template_id]
		if(!template || !length(template.shuttles_to_initialise))
			continue
		if(!candidate_DS.stashed || candidate_DS.z)
			continue
		log_drydock("_drydock_evict_docked_shuttle: '[docked.name]' has no home Z -- regenerating shuttle_id=[sid] via retrieve before eviction.")
		if(SSpersistence.drydockRetrieve(sid, null, get_turf(docked.current_location), user))
			var/obj/effect/shuttle_landmark/regenerated = docked.logging_home_tag ? SSshuttle.get_landmark(docked.logging_home_tag) : null
			if(istype(regenerated) && docked.attempt_move(regenerated))
				return TRUE
		break

	log_drydock_error("_drydock_evict_docked_shuttle: '[docked.name]' has no resolvable home landmark and no recoverable ledger entry -- left in place, needs admin attention.")
	return FALSE

/// Recovery tool -- restores a backup row (made by drydockRetrieve() right
/// before a deployment) back into the main table as a stashed row, for when
/// a deployment is lost before the next successful Stash.
/datum/admins/proc/restore_ship_backup()
	set name = "Restore Ship Backup"
	set category = "Persistence.Ships & Drydock"
	if(!check_rights(R_ADMIN))
		return

	if(!SSpersistence.databaseCheckConnection("restore_ship_backup"))
		to_chat(usr, SPAN_WARNING("Database connection failed."))
		return

	var/list/options = list()

	var/datum/db_query/sq = SSdbcore.NewQuery(
		"SELECT shuttle_id, template_id, owner_ckey, owner_char_name, faction_uid, backed_up_at FROM ss13_drydock_ships_backup",
		list()
	)
	sq.Execute()
	if(SSpersistence.databaseCheckQueryResult(sq, "restore_ship_backup shuttle select"))
		while(sq.NextRow())
			options["[sq.item[2]] #[sq.item[1]] ([sq.item[5] ? "faction [sq.item[5]]" : "owner [sq.item[3]] (\"[sq.item[4]]\")"], backed up [sq.item[6]])"] = text2num(sq.item[1])
	qdel(sq)

	if(!length(options))
		to_chat(usr, SPAN_NOTICE("No ship backups found."))
		return

	var/pick = tgui_input_list(usr, "Restore which ship from backup?", "Restore Ship Backup", options)
	if(!pick)
		return

	_restore_drydock_shuttle_from_backup(options[pick], usr)

/datum/admins/proc/_restore_drydock_shuttle_from_backup(shuttle_id, mob/user)
	var/datum/drydock_ship/existing = GLOB.drydock_ships["[shuttle_id]"]
	if(existing && !existing.stashed)
		to_chat(user, SPAN_WARNING("Drydock ship #[shuttle_id] is already live -- nothing to restore."))
		return

	var/datum/db_query/bq = SSdbcore.NewQuery(
		"SELECT template_id, owner_ckey, owner_char_name, faction_uid, purchased_at FROM ss13_drydock_ships_backup WHERE shuttle_id = :id",
		list("id" = shuttle_id)
	)
	bq.Execute()
	if(!SSpersistence.databaseCheckQueryResult(bq, "restore_ship_backup shuttle select") || !bq.NextRow())
		to_chat(user, SPAN_WARNING("No backup found for drydock ship #[shuttle_id]."))
		qdel(bq)
		return
	var/template_id = bq.item[1]
	var/owner_ckey = bq.item[2]
	var/owner_char_name = bq.item[3]
	var/faction_uid = bq.item[4]
	var/purchased_at = bq.item[5]
	qdel(bq)

	var/datum/db_query/iq = SSdbcore.NewQuery(
		"INSERT INTO ss13_drydock_ships (shuttle_id, template_id, owner_ckey, owner_char_name, faction_uid, stashed, stashed_at, purchased_at) VALUES (:id, :tid, :ckey, :char_name, :faction, 1, NOW(), :purchased) ON DUPLICATE KEY UPDATE stashed=1, stashed_at=NOW()",
		list("id" = shuttle_id, "tid" = template_id, "ckey" = owner_ckey, "char_name" = owner_char_name, "faction" = faction_uid, "purchased" = purchased_at)
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
		DS.owner_char_name = owner_char_name
		DS.faction_uid = faction_uid
		DS.stashed     = TRUE
		GLOB.drydock_ships["[shuttle_id]"] = DS

	to_chat(user, SPAN_GOOD("Drydock ship #[shuttle_id] ('[template_id]') restored from backup -- stashed, retrievable from the Drydock program."))
	log_admin("[key_name(user)] restored drydock ship #[shuttle_id] from backup.")
	log_drydock("restore_ship_backup: [key_name(user)] restored shuttle_id=[shuttle_id] from backup.")

/// Live-edits the server-wide deployed-ship cap (GLOB.drydock_max_deployed_ships,
/// see _drydockLoadShipCap()) and persists it to its singleton DB row --
/// takes effect immediately, survives a restart. 0 = no limit.
/datum/admins/proc/set_drydock_ship_cap()
	set name = "Set Drydock Ship Cap"
	set category = "Persistence.Ships & Drydock"
	if(!check_rights(R_ADMIN))
		return

	var/new_cap = tgui_input_number(usr, "Max ships deployed at once (0 = no limit):", "Set Drydock Ship Cap", GLOB.drydock_max_deployed_ships, 9999, 0)
	if(isnull(new_cap))
		return

	if(!SSpersistence.databaseCheckConnection("set_drydock_ship_cap"))
		to_chat(usr, SPAN_WARNING("Database connection failed -- cap not saved."))
		return

	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_drydock_config (id, max_deployed_ships) VALUES (1, :cap) ON DUPLICATE KEY UPDATE max_deployed_ships = :cap",
		list("cap" = new_cap)
	)
	q.Execute()
	if(!SSpersistence.databaseCheckQueryResult(q, "set_drydock_ship_cap update"))
		to_chat(usr, SPAN_WARNING("Database error -- cap not saved."))
		qdel(q)
		return
	qdel(q)

	GLOB.drydock_max_deployed_ships = new_cap
	to_chat(usr, SPAN_GOOD("Deployed-ship cap set to [new_cap ? new_cap : "no limit"]."))
	log_admin("[key_name(usr)] set the drydock deployed-ship cap to [new_cap].")
	message_admins("[key_name(usr)] set the drydock deployed-ship cap to [new_cap ? new_cap : "no limit"].")
	log_drydock("set_drydock_ship_cap: [key_name(usr)] set cap to [new_cap].")

/// One-time migration helper for the ship_schematic.dm ownership revision --
/// mints a schematic (ship_schematic.dm) for every existing personally- or
/// faction-owned ship that doesn't already have one (a live one somewhere in
/// the world, or one already banked). Skips repossessed ships entirely (the
/// Hub already holds those, nothing to backfill). Delivers directly to the
/// owning character if they're currently online with a living body; for a
/// faction ship, falls back to any of that faction's networked consoles;
/// failing both, banks the ship instead of leaving it in limbo, so the
/// eventual owner can just use "Withdraw Schematic" (drydock.dm) themselves
/// once reachable -- no further admin action needed. Safe to re-run --
/// already-handled ships are skipped every time.
/datum/admins/proc/backfill_ship_schematics()
	set name = "Backfill Ship Schematics"
	set category = "Persistence.Ships & Drydock"
	if(!check_rights(R_ADMIN))
		return

	var/minted = 0
	var/skipped = 0
	var/list/banked_instead = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.repossessed || DS.schematic_banked || !DS.purchased_at)
			continue

		var/already_exists = FALSE
		for(var/obj/item/ship_schematic/S in world)
			if(S.shuttle_id == DS.shuttle_id && S.bound_purchased_at == DS.purchased_at && !S.repossessed)
				already_exists = TRUE
				break
		if(already_exists)
			skipped++
			continue

		var/turf/spawn_turf
		var/mob/deliver_to
		if(DS.owner_ckey)
			for(var/mob/M in GLOB.mob_list)
				if(M.ckey == DS.owner_ckey && M.real_name == DS.owner_char_name && isturf(M.loc))
					deliver_to = M
					spawn_turf = get_turf(M)
					break
		else if(DS.faction_uid)
			for(var/obj/item/modular_computer/MC in world)
				if(normalize_faction_uid(MC.persistent_network) == DS.faction_uid)
					spawn_turf = get_turf(MC)
					break

		if(!spawn_turf)
			SSpersistence.drydockBankSchematic(DS.shuttle_id, null)
			banked_instead += "[DS.display_name()] (#[DS.shuttle_id])"
			continue

		var/obj/item/ship_schematic/schematic = new(spawn_turf)
		schematic.shuttle_id = DS.shuttle_id
		schematic.bound_purchased_at = DS.purchased_at
		schematic.refresh_name()
		if(deliver_to)
			deliver_to.put_in_hands(schematic)
		minted++

	var/summary = "Backfill complete: [minted] schematic(s) minted, [skipped] already had one."
	if(length(banked_instead))
		summary += " [length(banked_instead)] had no reachable owner/faction console -- banked instead, recoverable via Withdraw Schematic once reachable: [banked_instead.Join("; ")]."
	to_chat(usr, SPAN_GOOD(summary))
	log_and_message_admins("ran Backfill Ship Schematics -- [summary]", usr)
