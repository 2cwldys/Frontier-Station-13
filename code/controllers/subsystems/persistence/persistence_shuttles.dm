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
 * navigation destination. A personal ship retrieves directly into whatever
 * sector its owner's current computer is in, and stashes near any faction's
 * med-sec-or-better faction_beacon (not necessarily their own -- see
 * drydockStash()); a faction-owned ship retrieves/stashes only near its OWN
 * faction's faction_beacon (which claims a whole Z) -- see
 * shipPlaceOvermapMarker() and the ownership-branching in drydockRetrieve()/
 * drydockStash(). Both directions also refuse during a recent-combat lockout
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

/datum/drydock_ship
	var/shuttle_id
	var/template_id
	var/owner_ckey
	/// Paired with owner_ckey -- ownership belongs to a CHARACTER (real_name),
	/// not the account, so a player's other characters under the same ckey
	/// don't inherit access to a ship one of their characters bought. Mirrors
	/// the existing (ckey, char_name) composite-identity convention
	/// ss13_mob_position already uses (persistence_mobs.dm). Null/unused for
	/// faction ownership -- faction_uid is never a character-identity concept.
	var/owner_char_name
	var/faction_uid
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

/// TRUE if user is personally the owning CHARACTER (not just the owning
/// account) -- both owner_ckey AND owner_char_name must match. Used
/// throughout instead of a bare ckey check so a player's other characters
/// under the same ckey don't inherit access to a ship one character bought.
/datum/drydock_ship/proc/owned_by(mob/user)
	return owner_ckey && user && owner_ckey == user.ckey && owner_char_name == user.real_name

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
		"SELECT shuttle_id, template_id, owner_ckey, owner_char_name, faction_uid, stashed, z, overmap_x, overmap_y, custom_name, custom_class FROM ss13_drydock_ships",
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
		DS.owner_char_name = q.item[4]
		DS.faction_uid = q.item[5]
		DS.stashed     = !!text2num(q.item[6])
		DS.z           = text2num(q.item[7])
		DS.overmap_x   = text2num(q.item[8])
		DS.overmap_y   = text2num(q.item[9])
		DS.custom_name = q.item[10]
		DS.custom_class = q.item[11]

		if(!DS.stashed)
			log_drydock("drydockShipLedgerRestore: shuttle_id=[DS.shuttle_id] ('[DS.template_id]') was still stashed=0 at boot -- graceful shutdown's auto-stash sweep didn't run (crash/hard kill). Forcing back to stashed; interior recovers from the last autosave.")
			DS.stashed   = TRUE
			DS.z         = null
			DS.overmap_x = null
			DS.overmap_y = null
			reset_stale++

		GLOB.drydock_ships[DS.shuttle_id] = DS
		restored++
	qdel(q)

	// Crew lists load in one pass after every ledger datum exists, rather
	// than per-row inside the loop above, so a crew row can never race
	// ahead of its owning ship's datum being created.
	var/crew_loaded = 0
	var/datum/db_query/cq = SSdbcore.NewQuery("SELECT shuttle_id, ckey, char_name FROM ss13_ship_crew", list())
	cq.Execute()
	if(SSpersistence.databaseCheckQueryResult(cq, "drydockShipLedgerRestore crew"))
		while(cq.NextRow())
			var/datum/drydock_ship/DS = GLOB.drydock_ships[text2num(cq.item[1])]
			if(DS)
				DS.crew_ckeys |= "[cq.item[2]]|[cq.item[3]]"
				crew_loaded++
	qdel(cq)

	log_drydock("drydockShipLedgerRestore: [restored] drydock ship(s) restored[reset_stale ? ", [reset_stale] recovered from an unclean shutdown" : ""], [crew_loaded] crew entr[crew_loaded == 1 ? "y" : "ies"] loaded.")

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
	var/datum/drydock_ship/DS = GLOB.drydock_ships[shuttle_id]
	if(!DS)
		log_drydock_warning("drydockAddCrew: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
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
	var/datum/drydock_ship/DS = GLOB.drydock_ships[shuttle_id]
	if(!DS)
		log_drydock_warning("drydockRemoveCrew: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
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
/datum/controller/subsystem/persistence/proc/drydockRename(shuttle_id, new_name, new_class, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	var/datum/drydock_ship/DS = GLOB.drydock_ships[shuttle_id]
	if(!DS)
		log_drydock_warning("drydockRename: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to rename this ship."))
		log_drydock_warning("drydockRename: refused -- [acting] lacks permission for shuttle_id=[shuttle_id].")
		return FALSE

	if(!databaseCheckConnection("drydockRename"))
		if(user)
			to_chat(user, SPAN_WARNING("Database connection failed."))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_drydock_ships SET custom_name = :name, custom_class = :class WHERE shuttle_id = :id",
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

	if(!DS.stashed)
		var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[DS.z]"]
		if(istype(marker))
			var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
			marker.name = DS.custom_name || (template ? initial(template.name) : marker.name)
			marker.class = DS.custom_class

	if(user)
		to_chat(user, SPAN_GOOD("Ship identity updated."))
	log_drydock("drydockRename: [acting] renamed shuttle_id=[shuttle_id] to name='[DS.custom_name]', class='[DS.custom_class]'.")
	return TRUE

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
		"INSERT INTO ss13_drydock_ships (template_id, owner_ckey, owner_char_name, faction_uid, stashed) VALUES (:tid, :ckey, :char_name, :faction, 1)",
		list("tid" = template_id, "ckey" = owner_ckey, "char_name" = owner_char_name, "faction" = faction_uid)
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
	DS.owner_char_name = owner_char_name
	DS.faction_uid = faction_uid
	DS.stashed     = TRUE
	GLOB.drydock_ships[new_id] = DS

	if(user)
		to_chat(user, SPAN_GOOD("Purchased '[template.name]' -- retrieve it from the Drydock program."))
	log_drydock("drydockBuy: [acting] bought '[template_id]' (owner=[owner_ckey ? "[owner_ckey] (\"[owner_char_name]\")" : "none"], faction=[faction_uid || "none"], shuttle_id=[new_id]).")
	return TRUE

// ============================================================
// RETRIEVE  materialize: fresh Z, marker placed near the docking beacon
// ============================================================

#define DRYDOCK_SHIP_PLACEMENT_RADIUS 3

/// A faction-owned ship retrieves only near its OWN faction's faction_beacon
/// (anchor, required, faction_uid must match). A personally-owned ship
/// ignores anchor entirely and retrieves directly into whatever sector
/// from_turf (the retrieving computer's own position) is currently in -- no
/// beacon of any kind required. See the file header for the full rationale.
/datum/controller/subsystem/persistence/proc/drydockRetrieve(shuttle_id, obj/structure/machinery/faction_beacon/anchor, turf/from_turf, mob/user)
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
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to retrieve this ship."))
		log_drydock_warning("drydockRetrieve: refused -- [acting] lacks permission for shuttle_id=[shuttle_id] (owner=[DS.owner_ckey || "none"], faction=[DS.faction_uid || "none"]).")
		return FALSE
	if(ship_template_already_deployed(DS.template_id))
		if(user)
			to_chat(user, SPAN_WARNING("A ship of this class is already deployed somewhere -- stash it first."))
		log_drydock_warning("drydockRetrieve: refused -- template '[DS.template_id]' already has a deployed instance (acting=[acting]).")
		return FALSE

	var/obj/effect/overmap/visitable/target_sector
	var/placement_radius
	if(DS.faction_uid)
		if(!istype(anchor))
			if(user)
				to_chat(user, SPAN_WARNING("No faction beacon in range."))
			log_drydock_warning("drydockRetrieve: refused -- no faction beacon anchor provided for faction-owned shuttle_id=[shuttle_id] (acting=[acting]).")
			return FALSE
		if(anchor.faction_uid != DS.faction_uid && !check_rights(R_ADMIN, 0, user))
			if(user)
				to_chat(user, SPAN_WARNING("This beacon belongs to [get_faction_name(anchor.faction_uid)], not [get_faction_name(DS.faction_uid)]."))
			log_drydock_warning("drydockRetrieve: refused -- faction beacon belongs to [anchor.faction_uid], not [DS.faction_uid] (acting=[acting]).")
			return FALSE
		target_sector = GLOB.map_sectors["[GET_Z(anchor)]"]
		placement_radius = anchor.security_radius
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

	// Reuse a torn-down Z from the shared pool if one's available; otherwise
	// allocate fresh. Either way, suspend ZAS during the load or the newly
	// loaded hull gets vented (same recipe as generate_away_site()).
	var/scope = "ship:d:[shuttle_id]"
	var/pool_z = SSpersistence.acquireReusableZ()
	var/new_z
	var/bounds
	SSair.can_fire = FALSE
	if(pool_z)
		bounds = template.load_into_z(pool_z)
		new_z = pool_z
	else
		var/z_before = world.maxz
		bounds = template.load_new_z(FALSE)
		new_z = z_before + 1
	SSair.can_fire = TRUE
	if(!bounds)
		if(pool_z)
			SSpersistence.poolReusableZ(pool_z) // hand it back, this attempt never claimed it
		if(user)
			to_chat(user, SPAN_WARNING("Failed to materialize ship."))
		log_drydock_error("drydockRetrieve: template load failed for '[DS.template_id]', shuttle_id=[shuttle_id][pool_z ? " (pooled z=[pool_z])" : ""].")
		return FALSE
	log_drydock("drydockRetrieve: shuttle_id=[shuttle_id] materialized at z=[new_z] ([pool_z ? "pooled" : "fresh"]) for template '[DS.template_id]'.")

	var/obj/effect/overmap/visitable/ship/landable/marker = GLOB.map_sectors["[new_z]"]
	if(!istype(marker))
		log_drydock_error("drydockRetrieve: no overmap marker found at loaded z=[new_z] for shuttle_id=[shuttle_id].")
		return FALSE
	shipPlaceOvermapMarker(marker, target_sector, placement_radius)

	var/datum/shuttle/autodock/overmap/drydock_ship/shuttle_datum = SSshuttle.shuttles[marker.shuttle]
	if(istype(shuttle_datum))
		// Per-instance identity: give this deployment's shuttle registry
		// entry and marker a unique name (suffixed with the ledger id) so
		// multiple instances of the same template can be deployed at once --
		// /datum/shuttle/New() hard-CRASHes on a duplicate name otherwise
		// (shuttle.dm), which is exactly what the same-template-deployed
		// guard above exists to prevent until this runs. Already-linked
		// shuttle_computers/consoles hold direct object references, not name
		// lookups, so renaming afterward doesn't disturb them -- only the
		// SSshuttle.shuttles registry key and marker.shuttle (both looked up
		// by name on every subsequent access) need to move together.
		var/old_shuttle_name = shuttle_datum.name
		var/new_shuttle_name = "[old_shuttle_name] #[shuttle_id]"
		if(old_shuttle_name != new_shuttle_name && SSshuttle.shuttles[old_shuttle_name] == shuttle_datum)
			SSshuttle.shuttles -= old_shuttle_name
			shuttle_datum.name = new_shuttle_name
			SSshuttle.shuttles[new_shuttle_name] = shuttle_datum
			marker.shuttle = new_shuttle_name

	// Player-facing identity (separate from the internal registry name
	// above): custom_name/custom_class override the template's own
	// defaults, kept clean of the "#shuttle_id" uniqueness suffix.
	marker.name = DS.custom_name || initial(template.name)
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
	SSpersistence.drydockAutoFurnish(new_z, template, marker)

	DS.stashed   = FALSE
	DS.z         = new_z
	DS.overmap_x = marker.x
	DS.overmap_y = marker.y

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

	if(user)
		to_chat(user, SPAN_GOOD("Ship retrieved -- fly it in using its own navigation console. It's still initializing; you'll be notified once it's ready to board."))
		message_admins("[key_name(user)] retrieved drydock ship '[DS.custom_name || template.name]' (#[shuttle_id]) at ([marker.x],[marker.y],[new_z]). [ADMIN_JMP(marker)]")
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
	var/datum/shuttle/shuttle_datum = SSshuttle.shuttles[marker.shuttle]
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

	var/turf/home
	var/tries = 10
	while(tries > 0)
		tries--
		var/turf/candidate = CircularRandomTurfAround(anchor_sector, radius, map_low, map_low, map_high, map_high)
		if(candidate && !(locate(/obj/effect/overmap/visitable) in candidate))
			home = candidate
			break
	if(!home)
		home = CircularRandomTurfAround(anchor_sector, radius, map_low, map_low, map_high, map_high)
		log_drydock_warning("shipPlaceOvermapMarker: no free tile within radius [radius] of anchor sector after retries, sharing a tile.")

	if(home)
		marker.start_x = home.x
		marker.start_y = home.y
		marker.forceMove(home)
		log_drydock("shipPlaceOvermapMarker: placed marker at ([home.x],[home.y]), radius=[radius] of anchor sector.")
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
	if(!force && !(check_rights(R_ADMIN, 0, user) || DS.owned_by(user) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
		if(user)
			to_chat(user, SPAN_WARNING("You don't have permission to stash this ship."))
		log_drydock_warning("drydockStash: refused -- [acting] lacks permission for shuttle_id=[shuttle_id] (owner=[DS.owner_ckey || "none"], faction=[DS.faction_uid || "none"]).")
		return FALSE
	var/obj/effect/overmap/visitable/ship/landable/check_marker = GLOB.map_sectors["[DS.z]"]
	if(!force)
		// A personal ship may stash near ANY faction's beacon (not
		// necessarily one it owns), provided that beacon's own sector is
		// currently med-sec or better -- a faction ship still requires its
		// OWN faction's beacon specifically, same as retrieve.
		var/near_valid_beacon = FALSE
		if(istype(check_marker))
			for(var/bz in GLOB.faction_beacon_by_z)
				var/obj/structure/machinery/faction_beacon/B = GLOB.faction_beacon_by_z[bz]
				if(!B)
					continue
				if(DS.faction_uid ? (B.faction_uid != DS.faction_uid) : (zone_security_get(GET_Z(B)) < ZONE_MEDSEC))
					continue
				var/obj/effect/overmap/visitable/beacon_sector = GLOB.map_sectors["[GET_Z(B)]"]
				if(istype(beacon_sector) && get_dist(check_marker, beacon_sector) <= 1)
					near_valid_beacon = TRUE
					break
		if(!near_valid_beacon)
			if(user)
				to_chat(user, SPAN_WARNING(DS.faction_uid ? "This ship must be within 1 tile of your faction's own beacon to be stashed." : "You must be near a secured (med-sec or better) faction beacon to stash."))
			log_drydock_warning("drydockStash: refused -- shuttle_id=[shuttle_id] not near a valid beacon (acting=[acting]).")
			return FALSE
		var/mob/living/living_user = istype(user, /mob/living) ? user : null
		if((living_user && living_user.in_recent_combat()) || (istype(check_marker) && check_marker.in_recent_combat()))
			if(user)
				to_chat(user, SPAN_WARNING("You (or your ship) were recently in combat -- wait before stashing."))
			log_drydock_warning("drydockStash: refused -- combat lockout active for shuttle_id=[shuttle_id] (acting=[acting]).")
			return FALSE
	if(zlevel_has_players(DS.z))
		if(user)
			to_chat(user, SPAN_WARNING("Make sure everyone is off the ship first."))
		log_drydock_warning("drydockStash: refused -- players still present on z=[DS.z] for shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	var/scope = "ship:d:[shuttle_id]"
	var/stash_z = DS.z
	SSpersistence.shipInteriorSave(stash_z, scope)

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

	// Grabbed before teardown -- there's no marker left to JMP to afterward.
	var/stash_jmp = istype(check_marker) ? ADMIN_JMP(check_marker) : ""

	SSpersistence._drydockMarkerTeardown(stash_z)

	if(user)
		to_chat(user, SPAN_GOOD("Ship stashed."))
		message_admins("[key_name(user)] stashed drydock ship '[DS.custom_name || DS.template_id]' (#[shuttle_id]). [stash_jmp]")
	log_drydock("drydockStash: shuttle_id=[shuttle_id] fully stashed and torn down (acting=[acting]).")
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
	var/datum/shuttle/shuttle_datum = istype(marker) ? SSshuttle.shuttles[marker.shuttle] : null
	var/shuttle_name = shuttle_datum?.name
	if(istype(marker))
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
/datum/controller/subsystem/persistence/proc/drydockScuttle(shuttle_id, mob/user)
	var/acting = user ? key_name(user) : "SYSTEM"
	log_drydock("drydockScuttle: [acting] attempting to scuttle shuttle_id=[shuttle_id].")

	var/datum/drydock_ship/DS = GLOB.drydock_ships[shuttle_id]
	if(!DS)
		log_drydock_warning("drydockScuttle: refused -- unknown shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE
	if(!(check_rights(R_ADMIN, 0, user) || DS.owned_by(user) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
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

	if(!databaseCheckConnection("drydockScuttle"))
		to_chat(user, SPAN_WARNING("Database connection failed -- scuttle not completed."))
		log_drydock_error("drydockScuttle: database connection failed for shuttle_id=[shuttle_id] (acting=[acting]).")
		return FALSE

	acc.adjust_money(-DRYDOCK_SCUTTLE_FEE)

	var/obj/effect/overmap/visitable/marker = was_deployed ? GLOB.map_sectors["[DS.z]"] : null
	var/atom/jmp_target = (was_deployed && marker) ? marker : user
	var/display_name = DS.custom_name || DS.template_id
	var/deployed_z = DS.z

	// Ledger row (and its GLOB.drydock_ships entry) is fully gone BEFORE the
	// marker is torn down below -- the qdel fires drydock_ship/Destroy()'s
	// defensive orphan-recovery check (drydock_ship.dm), which only acts on
	// a shuttle_id it can still find in GLOB.drydock_ships. Deleting first
	// means that check correctly finds nothing to "recover" here.
	SSpersistence.purgeShipScopeRows("ship:d:[shuttle_id]")

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

	GLOB.drydock_ships -= shuttle_id

	if(was_deployed)
		SSpersistence._drydockMarkerTeardown(deployed_z)

	message_admins("[key_name(user)] SCUTTLED their ship '[display_name]' (#[shuttle_id]) for [DRYDOCK_SCUTTLE_FEE]cr. [ADMIN_JMP(jmp_target)]")
	to_chat(user, SPAN_GOOD("Ship scuttled -- gone for good."))
	log_drydock("drydockScuttle: [acting] permanently scuttled shuttle_id=[shuttle_id] ('[DS.template_id]') for [DRYDOCK_SCUTTLE_FEE]cr, was_deployed=[was_deployed].")
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
	set category = "Persistence"
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

/// Recovery tool -- restores a backup row (made by drydockRetrieve() right
/// before a deployment) back into the main table as a stashed row, for when
/// a deployment is lost before the next successful Stash.
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
	var/datum/drydock_ship/existing = GLOB.drydock_ships[shuttle_id]
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
		GLOB.drydock_ships[shuttle_id] = DS

	to_chat(user, SPAN_GOOD("Drydock ship #[shuttle_id] ('[template_id]') restored from backup -- stashed, retrievable from the Drydock program."))
	log_admin("[key_name(user)] restored drydock ship #[shuttle_id] from backup.")
	log_drydock("restore_ship_backup: [key_name(user)] restored shuttle_id=[shuttle_id] from backup.")
