/*
 * Persistence subsystem
 * Subsytem for managing any form of persistent content across rounds.
 *
 * This subsystem consists of multiple partial files, following the structure:
 * - persistence.dm						- Subsystem definition and generic code.
 * - persistence_objects.dm				- Persistent objects related code.
 * - persistence_objects_sql.dm			- Persistent objects database code.
 * - persistence_objects_public.dm		- Persistent objects public procs.
 */

/// Set to TRUE once SSpersistence.Initialize() fully completes  gates PersistentAutoSpawn().
GLOBAL_VAR_INIT(persistence_ready, FALSE)

/// Whether players can self-service found new factions via faction_manage.dm's
/// "start_founding" action. Admin-toggled (toggle_faction_creation(),
/// persistence_factions.dm), persists across restarts via ss13_faction_creation_toggle.
GLOBAL_VAR_INIT(faction_creation_enabled, TRUE)

/// Z levels whose numbers appear in this list are SKIPPED by turf/object/worldstate persistence.
/// Populated from ss13_zlevel_persistence WHERE enabled = 0 at startup.
/// Empty by default = all Z levels persist.
GLOBAL_LIST_EMPTY(persistence_zlevel_skip)

/// Z levels explicitly ENABLED via the Toggle Z-Level Persistence verb.
/// Populated from ss13_zlevel_persistence WHERE enabled = 1 at startup.
/// Only consulted when MANUAL_AREA_SAVE is on -- persistence then becomes
/// opt-in and ONLY these z-levels save/load.
GLOBAL_LIST_EMPTY(persistence_zlevel_allow)

/// Z levels that received a map template at runtime (away sites via load_new_z,
/// ruins/landmark loads via template.load on non-station levels). Never persisted.
GLOBAL_LIST_EMPTY(persistence_template_loaded_z)

/// Z levels of admin-pinned persistent away sites (ss13_persistent_away_sites),
/// populated by build_pinned_away_sites() during SSmapping init. These BYPASS
/// every persistence exclusion (away trait, template-loaded, manual gate) --
/// a pinned site saves/loads like a station deck.
GLOBAL_LIST_EMPTY(persistence_pinned_site_z)

/// TRUE when MANUAL_AREA_SAVE is on and this z was not explicitly enabled via
/// the Toggle Z-Level Persistence verb -- flips persistence from opt-out to
/// opt-in per z-level, using the same DB-backed list the verb manages.
/// Pinned away-site z's are never blocked (their z is derived, not listed).
/proc/persistence_z_manual_blocked(z)
	// Deployed player-ship Zs save like pinned sites do, regardless of the
	// manual allow list -- their content rows are ship-scoped, not map-scoped
	// (see persistence_ship_interiors.dm).
	if(GLOB.persistence_ship_z["[z]"])
		return FALSE
	if(z in GLOB.persistence_pinned_site_z)
		return FALSE
	return GLOB.config.manual_area_save && !(z in GLOB.persistence_zlevel_allow)

/// TRUE if this z-level must not be saved/loaded by turf/object/worldstate persistence:
/// not in the MANUAL_AREA_SAVE allow list (when that mode is on), manually disabled via
/// ss13_zlevel_persistence, a procedurally loaded away-site z (tagged ZTRAIT_AWAY), an
/// asteroid/mining level (regenerated each round), or any z a map template was loaded
/// onto at runtime. Admin-pinned persistent away sites bypass ALL of these -- the
/// pinned check must stay FIRST: pinned sites spawn via load_new_z(), which stamps
/// them with both the away trait and the template-loaded mark below.
/// TRUE if this atom is inside a drydock pad -- turf/object persistence must
/// skip it entirely so a landed (not stashed) shuttle's hull damage, dropped
/// items, and decals never get autosaved. See docs/shuttlesystem-architecture.md Part 2.
/proc/persistence_area_excluded(atom/A)
	var/area/ar = get_area(A)
	return ar && (ar.area_flags & AREA_FLAG_DRYDOCK_PAD)

/proc/persistence_z_excluded(z)
	// Deployed player-ship Zs bypass every exclusion below (they carry the
	// away trait AND the template-loaded mark) -- must stay FIRST, like the
	// pinned check. See persistence_ship_interiors.dm.
	if(GLOB.persistence_ship_z["[z]"])
		return FALSE
	if(z in GLOB.persistence_pinned_site_z)
		return FALSE
	if(persistence_z_manual_blocked(z))
		return TRUE
	if(z in GLOB.persistence_zlevel_skip)
		return TRUE
	if(is_away_level(z))
		return TRUE
	if(is_mining_level(z))
		return TRUE
	if(z in GLOB.persistence_template_loaded_z)
		return TRUE
	return FALSE

SUBSYSTEM_DEF(persistence)
	name = "Persistence"
	init_order = INIT_ORDER_PERSISTENCE // The order is tied with the init and maploading subsystem.
	wait = 30 MINUTES // Fires every 30 minutes; saves all persistence data including turfs and atmos.
	var/prevent_saving = FALSE // Toggle to prevent saving at round end, changed by toggle_persistence proc, used for admin purposes.
	var/save_in_progress = FALSE // Set TRUE while a save is running to prevent concurrent saves.
	var/autosave_paused = FALSE
	var/autosave_pause_remaining = 0

/**
 * Subsystem info stub message generation.
 */
/datum/controller/subsystem/persistence/stat_entry(msg)
	msg = ("Register: [length(GLOB.persistence_object_track_register)] | Prevent saving: [SSpersistence.prevent_saving ? "TRUE" : "FALSE"] | Saving: [SSpersistence.save_in_progress ? "YES" : "NO"] | Autosave: [SSpersistence.autosave_paused ? "PAUSED" : "active"]")
	return msg

/**
 * Periodic save  fires every 30 minutes and saves all persistence data.
 * Since the world runs continuously with no round end, this is the primary save mechanism.
 * Shutdown() also runs all saves for graceful server restarts.
 */
/datum/controller/subsystem/persistence/fire()
	if(prevent_saving || !GLOB.config.sql_enabled)
		return
	if(save_in_progress)
		log_subsystem_persistence_warning("Persistence: Periodic save skipped -- save already in progress.")
		return

	save_in_progress = TRUE
	log_subsystem_persistence_info("Persistence: Running periodic save.")
	to_world(SPAN_NOTICE(SPAN_BOLD("Automatic world save in progress. This may take 1-2 minutes.")))

	try
		forceSaveAll()
	catch(var/exception/e)
		log_subsystem_persistence_error("Periodic save failed: [e]")

	save_in_progress = FALSE
	log_subsystem_persistence_info("Persistence: Periodic save complete.")
	to_world(SPAN_GOOD(SPAN_BOLD("World save complete.")))

/**
 * Helper method to check and log database connection.
 * RETURN: True if connection is scuccessful, false if not.
 * PARAMS:
 * 	action = Custom string of the action being performed written to log.
 */
/datum/controller/subsystem/persistence/proc/databaseCheckConnection(action = "unlabeled action")
	PRIVATE_PROC(TRUE)
	if(!SSdbcore.Connect())
		log_subsystem_persistence_error("SQL error during [action], connection failed.")
		return FALSE
	return TRUE

/**
 * Helper method to check the SQL query result and log possible errors.
 * RETURN: True if no error occured, false if an error was found.
 */
/datum/controller/subsystem/persistence/proc/databaseCheckQueryResult(datum/db_query/query, action = "unlabeled action")
	PRIVATE_PROC(TRUE)
	if (!query)
		log_subsystem_persistence_error("SQL error during [action], in addition query object provided to check was null.")
		return FALSE
	if (query.ErrorMsg())
		log_subsystem_persistence_error("SQL error during [action]. " + query.ErrorMsg())
		return FALSE
	return TRUE

/datum/admins/proc/toggle_server_joining()
	set name = "Toggle Server Joining"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(GLOB.config.enter_allowed)
		var/confirm = tgui_alert(usr, "Prevent new players from joining the server? Admins can still join.", "Toggle Server Joining", list("Lock", "Cancel"))
		if(confirm != "Lock")
			return
		GLOB.config.enter_allowed = FALSE
		to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Joining has been [SPAN_BOLD(SPAN_WARNING("disabled"))] by an administrator. The server is now locked.")))
		log_and_message_admins("has locked the server  joining is disabled", usr)
	else
		var/confirm = tgui_alert(usr, "Allow players to join the server again?", "Toggle Server Joining", list("Unlock", "Cancel"))
		if(confirm != "Unlock")
			return
		GLOB.config.enter_allowed = TRUE
		to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Joining has been [SPAN_BOLD(SPAN_GOOD("re-enabled"))] by an administrator. The server is now open.")))
		log_and_message_admins("has unlocked the server  joining is enabled", usr)

	feedback_add_details("admin_verb", "TSJ")

/datum/admins/proc/toggle_persistence()
	set name = "Toggle Persistence"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/message = ""
	var/options = list()
	if(SSpersistence.prevent_saving)
		message = "The persistence subsystem will NOT save at the end of the round. Do you want to re-enable it?"
		options = list("Re-enable saving", "Cancel")
	else
		message = "The persistence subsystem will save at the end of the round. Do you want to prevent this? This can be un-done before the round ends."
		options = list("Prevent saving", "Cancel")

	var/confirm = tgui_alert(usr, message, "Toggle Persistence Saving", options)
	if(confirm == "Prevent saving")
		SSpersistence.prevent_saving = TRUE
		to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Persistence saving at the end of the round has been [SPAN_BOLD(SPAN_WARNING("disabled"))] by an administrator.")))
		log_and_message_admins("has toggled persistence saving at round end, it is now disabled", usr)
	else if (confirm == "Re-enable saving")
		SSpersistence.prevent_saving = FALSE
		to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Persistence saving at the end of the round has been [SPAN_BOLD(SPAN_GOOD("re-enabled"))] by an administrator.")))
		log_and_message_admins("has toggled persistence saving at round end, it is now re-enabled", usr)
	else
		return

	feedback_add_details("admin_verb","TP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/admins/proc/toggle_autosave_pause()
	set name = "Toggle Autosave Pause"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	if(SSpersistence.autosave_paused)
		SSpersistence.next_fire = world.time + max(0, SSpersistence.autosave_pause_remaining)
		SSpersistence.autosave_paused = FALSE
		to_world(FONT_LARGE(SPAN_GOOD("Autosave RESUMED. Next save in approximately [round(max(0, SSpersistence.autosave_pause_remaining) / (1 MINUTE))] minute(s).")))
		log_and_message_admins("resumed the autosave timer", usr)
	else
		SSpersistence.autosave_pause_remaining = max(0, SSpersistence.next_fire - world.time)
		SSpersistence.next_fire = world.time + (999 MINUTES)
		SSpersistence.autosave_paused = TRUE
		to_world(FONT_LARGE(SPAN_WARNING("Autosave PAUSED by an administrator. Manual saves still work.")))
		log_and_message_admins("paused the autosave timer", usr)

	feedback_add_details("admin_verb","TAP")

/datum/admins/proc/force_persistence_save()
	set name = "Force Persistence Save"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return

	var/confirm = tgui_alert(usr, "Immediately save all persistence data to the database? This saves economy, records, research, worldstate, turfs, atmos, objects, mob health, and inventory.", "Force Persistence Save", list("Save Now", "Cancel"))
	if(confirm != "Save Now")
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled. Cannot save."))
		return

	if(!SSpersistence.databaseCheckConnection("admin force save"))
		to_chat(usr, SPAN_WARNING("Database connection failed. Cannot save."))
		return

	if(SSpersistence.save_in_progress)
		to_chat(usr, SPAN_WARNING("A save is already in progress. Please wait for it to complete before forcing another."))
		return

	SSpersistence.save_in_progress = TRUE
	to_world(SPAN_NOTICE(SPAN_BOLD("World state save in progress.")))
	log_and_message_admins("initiated a world persistence save", usr)

	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("1/8")] Saving economy..."))
	SSpersistence.economyFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("2/8")] Saving records + research..."))
	SSpersistence.recordsFinalize()
	SSpersistence.researchFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("3/8")] Saving machinery states..."))
	SSpersistence.areasFinalize()
	SSpersistence.worldstateFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("4/8")] Saving mob health, inventory, identity, position..."))
	SSpersistence.mobsHealthFinalize()
	SSpersistence.mobsInventoryFinalize()
	SSpersistence.charIdentityFinalize()
	SSpersistence.mobsPositionFinalizeAll()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("5/8")] Saving turfs..."))
	SSpersistence.turfsFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("6/8")] Saving atmos zones..."))
	SSpersistence.atmosFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("7/8")] Saving persistent objects..."))
	SSpersistence.objectsFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("8/8")] Saving floor items..."))
	SSpersistence.floorItemsFinalize()
	SSpersistence.botsFinalize()
	SSpersistence.subshipSnapshotSaveAllDeployed()

	SSpersistence.save_in_progress = FALSE
	log_and_message_admins("forced a mid-round persistence save", usr)
	to_chat(usr, SPAN_GOOD("Persistence save complete."))

	feedback_add_details("admin_verb","FPS")

/**
 * Sweeps the whole world and vaults every dead/unclaimed neural lace, plus
 * any sitting loose. Never touches a lace still installed in a living
 * owner -- that check must run before _auto_transfer_to_storage() is ever
 * called, not after, so a living person's lace is never even momentarily
 * touched. Shared by the admin verb (manual, mid-round) and Shutdown()
 * (automatic, on every real reboot -- not the periodic autosave, which
 * never touches this).
 */
/datum/controller/subsystem/persistence/proc/vaultAllLaces()
	var/vaulted = 0
	var/skipped_alive = 0
	for(var/obj/item/organ/internal/neural_lace/L in world)
		if(istype(L.loc, /obj/structure/machinery/lace_storage))
			continue // already vaulted, nothing to do

		if(L.owner && L.owner.stat != DEAD)
			skipped_alive++
			continue

		L._auto_transfer_to_storage()
		vaulted++

	log_subsystem_persistence_info("Lace vault sweep: [vaulted] vaulted, [skipped_alive] skipped (alive owner).")
	return list("vaulted" = vaulted, "skipped_alive" = skipped_alive)

/datum/admins/proc/force_vault_all_laces()
	set name = "Force Vault All Laces"
	set category = "Persistence"
	set desc = "Immediately vaults every neural lace belonging to a dead/unclaimed body, plus any sitting loose in the world. Never touches a living person's installed lace. Use before a server reboot."

	if(!check_rights(R_ADMIN))
		return

	var/list/result = SSpersistence.vaultAllLaces()
	to_chat(usr, SPAN_NOTICE("Force-vaulted [result["vaulted"]] neural lace\s ([result["skipped_alive"]] skipped -- still alive)."))
	log_admin("[key_name(usr)] used Force Vault All Laces -- [result["vaulted"]] processed, [result["skipped_alive"]] skipped (alive owner).")

	feedback_add_details("admin_verb","FVAL")

/**
 * Public proc: save all persistence data immediately (economy, records, research, worldstate, turfs, atmos, objects, mob health, inventory).
 * Called by the force-save admin verb and by fire() for periodic saves.
 */
/datum/controller/subsystem/persistence/proc/forceSaveAll()
	if(!databaseCheckConnection("forceSaveAll"))
		return

	log_subsystem_persistence_info("forceSaveAll: Starting full persistence save.")

	try
		economyFinalize()
	catch(var/exception/economy_e)
		log_subsystem_persistence_panic("Unhandled exception during economy persistence finalization: [economy_e]")

	try
		recordsFinalize()
	catch(var/exception/records_e)
		log_subsystem_persistence_panic("Unhandled exception during records persistence finalization: [records_e]")

	try
		researchFinalize()
	catch(var/exception/research_e)
		log_subsystem_persistence_panic("Unhandled exception during research persistence finalization: [research_e]")

	try
		factionFinalize()
	catch(var/exception/faction_e)
		log_subsystem_persistence_panic("Unhandled exception during faction persistence finalization: [faction_e]")

	try
		factionFoundingSweep()
	catch(var/exception/faction_founding_sweep_e)
		log_subsystem_persistence_panic("Unhandled exception during faction founding sweep: [faction_founding_sweep_e]")

	try
		factionResearchFinalize()
	catch(var/exception/faction_research_e)
		log_subsystem_persistence_panic("Unhandled exception during faction research persistence finalization: [faction_research_e]")

	try
		areasFinalize()
	catch(var/exception/areas_e)
		log_subsystem_persistence_panic("Unhandled exception during area persistence finalization: [areas_e]")

	try
		worldstateFinalize()
	catch(var/exception/ws_e)
		log_subsystem_persistence_panic("Unhandled exception during worldstate persistence finalization: [ws_e]")

	try
		mobsHealthFinalize()
	catch(var/exception/health_e)
		log_subsystem_persistence_panic("Unhandled exception during mob health persistence finalization: [health_e]")

	try
		mobsInventoryFinalize()
	catch(var/exception/inv_e)
		log_subsystem_persistence_panic("Unhandled exception during mob inventory persistence finalization: [inv_e]")

	try
		charIdentityFinalize()
	catch(var/exception/id_e)
		log_subsystem_persistence_panic("Unhandled exception during character identity persistence finalization: [id_e]")

	try
		mobsPositionFinalizeAll()
	catch(var/exception/pos_e)
		log_subsystem_persistence_panic("Unhandled exception during mob position persistence finalization: [pos_e]")

	try
		turfsFinalize()
	catch(var/exception/turfs_e)
		log_subsystem_persistence_panic("Unhandled exception during turf persistence finalization: [turfs_e]")

	try
		atmosFinalize()
	catch(var/exception/atmos_e)
		log_subsystem_persistence_panic("Unhandled exception during atmos persistence finalization: [atmos_e]")

	try
		objectsFinalize()
	catch(var/exception/objs_e)
		log_subsystem_persistence_panic("Unhandled exception during persistent objects finalization: [objs_e]")

	try
		floorItemsFinalize()
	catch(var/exception/floor_e)
		log_subsystem_persistence_panic("Unhandled exception during floor item persistence finalization: [floor_e]")

	try
		botsFinalize()
	catch(var/exception/bots_e)
		log_subsystem_persistence_panic("Unhandled exception during bot persistence finalization: [bots_e]")

	// Deployed ships are NOT auto-stashed on the periodic save -- their
	// interiors are already covered by the Finalize sweeps above (ship Zs
	// are no longer excluded, see persistence_ship_interiors.dm) and their
	// ledger row persists while deployed, so nothing is lost by leaving them
	// flying. Just keep the ledger's overmap position current.
	try
		shipLedgerPositionSync()
	catch(var/exception/pos_sync_e)
		log_subsystem_persistence_panic("Unhandled exception during ship position sync: [pos_sync_e]")

	// Sub-ship snapshots (persistence_shuttles.dm) are a separate, smaller
	// persistence tier from the Finalize sweeps above -- they don't ride
	// along for free, so they need their own periodic save here too, or an
	// ungraceful crash would replenish a sub-ship from whenever it was last
	// explicitly stashed instead of where it actually was.
	try
		subshipSnapshotSaveAllDeployed()
	catch(var/exception/subship_snapshot_e)
		log_subsystem_persistence_panic("Unhandled exception during sub-ship snapshot save: [subship_snapshot_e]")

	try
		shuttleStateFinalize()
	catch(var/exception/shuttle_e)
		log_subsystem_persistence_panic("Unhandled exception during shuttle state persistence finalization: [shuttle_e]")

	log_subsystem_persistence_info("forceSaveAll: Full persistence save complete.")

/**
 * Initialization of the persistence subsystem.
 * Includes generic startup checks and init of the different persistent data types.
 */
/datum/controller/subsystem/persistence/Initialize()
	. = ..()
	if(!GLOB.config.sql_enabled)
		log_subsystem_persistence_warning("SQL configuration not enabled. Persistence subsystem requires SQL. Skipping init.")
		return SS_INIT_SUCCESS

	if(!databaseCheckConnection("subsystem init"))
		return SS_INIT_FAILURE

	// Load Z-level persistence toggles FIRST — before any save/load so checks are in effect
	var/datum/db_query/zlq = SSdbcore.NewQuery(
		"SELECT z, enabled FROM ss13_zlevel_persistence WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]"))
	zlq.Execute()
	if(databaseCheckQueryResult(zlq, "Initialize zlevel toggles"))
		while(zlq.NextRow())
			var/toggle_z = text2num(zlq.item[1])
			if(text2num(zlq.item[2]))
				GLOB.persistence_zlevel_allow += toggle_z
			else
				GLOB.persistence_zlevel_skip += toggle_z
	qdel(zlq)
	if(length(GLOB.persistence_zlevel_skip))
		log_subsystem_persistence_info("Z-Level skip list loaded: [GLOB.persistence_zlevel_skip.Join(", ")]")
	if(GLOB.config.manual_area_save)
		log_subsystem_persistence_info("MANUAL_AREA_SAVE active: only z-levels \[[GLOB.persistence_zlevel_allow.Join(", ")]\] will save/load.")

	var/init_start_time = world.time

	log_subsystem_persistence_info("Starting zone security initialization...")
	try
		zoneSecurityInitialize()
	catch(var/exception/zs_e)
		log_subsystem_persistence_error("Zone security init failed: [zs_e] on [zs_e.file]:[zs_e.line]")

	log_subsystem_persistence_info("Starting join whitelist initialization...")
	try
		// Loaded first so the join gate is armed before anyone can hit Play.
		whitelistInitialize()
	catch(var/exception/wl_e)
		log_subsystem_persistence_panic("Unhandled exception during join whitelist initialization: [wl_e]")

	log_subsystem_persistence_info("Starting cargo exports initialization...")
	try
		cargoExportsInitialize()
	catch(var/exception/ce_e)
		log_subsystem_persistence_error("Cargo exports init failed: [ce_e] on [ce_e.file]:[ce_e.line]")

	log_subsystem_persistence_info("Starting bounties initialization...")
	try
		bountiesInitialize()
	catch(var/exception/bt_e)
		log_subsystem_persistence_error("Bounties init failed: [bt_e] on [bt_e.file]:[bt_e.line]")

	log_subsystem_persistence_info("Starting missions initialization...")
	try
		missionsInitialize()
	catch(var/exception/ms_e)
		log_subsystem_persistence_error("Missions init failed: [ms_e] on [ms_e.file]:[ms_e.line]")

	log_subsystem_persistence_info("Starting area initialization...")
	try
		// Before objectsInitialize()/worldstateInitialize() -- a restored
		// player-built APC's get_area(src)/loc.loc must already resolve to the
		// correct custom blueprint area by the time it's recreated, or it bakes
		// in the wrong name/.area binding permanently (no refresh hook exists
		// to fix this after the fact -- see faction_beacon/APC persistence
		// investigation).
		areasInitialize()
	catch(var/exception/areas_e)
		log_subsystem_persistence_panic("Unhandled exception during area persistence initialization: [areas_e]")

	log_subsystem_persistence_info("Starting persistent objects initialization...")
	try
		objectsInitialize()
	catch(var/exception/objs_e)
		log_subsystem_persistence_panic("Unhandled exception during persistent objects initialization: [objs_e]")

	// Floor items runs immediately after objects so machines/structures are recreated
	// before worldstateInitialize applies their saved state vars.
	log_subsystem_persistence_info("Starting floor item initialization...")
	try
		floorItemsInitialize()
	catch(var/exception/floor_e)
		log_subsystem_persistence_panic("Unhandled exception during floor item persistence initialization: [floor_e]")

	log_subsystem_persistence_info("Starting bot initialization...")
	try
		botsInitialize()
	catch(var/exception/bots_e)
		log_subsystem_persistence_panic("Unhandled exception during bot persistence initialization: [bots_e]")

	log_subsystem_persistence_info("Starting removed structures initialization...")
	try
		removedStructuresInitialize()
	catch(var/exception/rs_e)
		log_subsystem_persistence_panic("Unhandled exception during removed structures initialization: [rs_e]")

	log_subsystem_persistence_info("Starting economy initialization...")
	try
		economyInitialize()
	catch(var/exception/economy_e)
		log_subsystem_persistence_panic("Unhandled exception during economy persistence initialization: [economy_e]")

	log_subsystem_persistence_info("Starting records initialization...")
	try
		recordsInitialize()
	catch(var/exception/records_e)
		log_subsystem_persistence_panic("Unhandled exception during records persistence initialization: [records_e]")

	log_subsystem_persistence_info("Starting research initialization...")
	try
		researchInitialize()
	catch(var/exception/research_e)
		log_subsystem_persistence_panic("Unhandled exception during research persistence initialization: [research_e]")

	log_subsystem_persistence_info("Starting faction initialization...")
	try
		factionInitialize()
	catch(var/exception/faction_e)
		log_subsystem_persistence_panic("Unhandled exception during faction persistence initialization: [faction_e]")

	log_subsystem_persistence_info("Starting faction founding petition initialization...")
	try
		factionFoundingInitialize()
	catch(var/exception/faction_founding_e)
		log_subsystem_persistence_panic("Unhandled exception during faction founding petition initialization: [faction_founding_e]")

	log_subsystem_persistence_info("Starting faction creation toggle initialization...")
	try
		factionCreationToggleInitialize()
	catch(var/exception/faction_toggle_e)
		log_subsystem_persistence_panic("Unhandled exception during faction creation toggle initialization: [faction_toggle_e]")

	log_subsystem_persistence_info("Starting faction research initialization...")
	try
		factionResearchInitialize()
	catch(var/exception/faction_res_e)
		log_subsystem_persistence_panic("Unhandled exception during faction research initialization: [faction_res_e]")

	log_subsystem_persistence_info("Starting template pending check...")
	try
		templateCheckPending()
	catch(var/exception/templates_e)
		log_subsystem_persistence_panic("Unhandled exception during template pending check: [templates_e]")

	log_subsystem_persistence_info("Starting worldstate initialization...")
	try
		worldstateInitialize()
	catch(var/exception/ws_e)
		log_subsystem_persistence_panic("Unhandled exception during worldstate persistence initialization: [ws_e]")

	log_subsystem_persistence_info("Starting lace vault initialization...")
	try
		// After worldstate so vaults exist and have their networks applied.
		laceVaultInitialize()
	catch(var/exception/vault_e)
		log_subsystem_persistence_panic("Unhandled exception during lace vault initialization: [vault_e]")

	log_subsystem_persistence_info("Starting turf initialization...")
	try
		turfsInitialize()
	catch(var/exception/turfs_e)
		log_subsystem_persistence_panic("Unhandled exception during turf persistence initialization: [turfs_e]")

	log_subsystem_persistence_info("Starting powernet rebuild...")
	try
		// Restored cables/turfs above may have left segments on isolated powernets
		// (SSmachinery built the grid long before persistence ran). Rebuild from
		// GLOB.cable_list -- same proc the admin "Make Powernets" debug verb uses.
		SSmachinery.makepowernets()
		log_subsystem_persistence_info("Powernets rebuilt after persistence restore.")
	catch(var/exception/pn_e)
		log_subsystem_persistence_panic("Unhandled exception during powernet rebuild: [pn_e]")

	log_subsystem_persistence_info("Starting atmos initialization...")
	try
		atmosInitialize()
		// The turf restore above queued ZAS updates -- settle them so zone geometry
		// is final, then re-apply the saved zone gases. This must happen here:
		// SSair initializes BEFORE SSpersistence, so any air vented while restored
		// turfs rebuilt zones is replenished from the saved state, and alarms clear.
		SSair.fire(FALSE, TRUE)
		atmosApply()
	catch(var/exception/atmos_e)
		log_subsystem_persistence_panic("Unhandled exception during atmos persistence initialization: [atmos_e]")

	log_subsystem_persistence_info("Starting power state finalization...")
	try
		// Must run after makepowernets(): re-derives APC channels from restored
		// cell charge, writes area power flags, and rebroadcasts power state so
		// no machine is left with stale NOPOWER sampled mid-restore.
		powerstateFinalize()
	catch(var/exception/ps_e)
		log_subsystem_persistence_panic("Unhandled exception during power state finalization: [ps_e]")

	log_subsystem_persistence_info("Starting atmos alarm reset...")
	try
		// After atmosApply(): clear alarm/shutter state latched on transient
		// boot air -- alarms re-sample the restored air next tick.
		atmosAlarmsReset()
	catch(var/exception/aar_e)
		log_subsystem_persistence_panic("Unhandled exception during atmos alarm reset: [aar_e]")

	log_subsystem_persistence_info("Starting mob health initialization...")
	try
		mobsHealthInitialize()
	catch(var/exception/health_e)
		log_subsystem_persistence_panic("Unhandled exception during mob health persistence initialization: [health_e]")

	log_subsystem_persistence_info("Starting mob inventory initialization...")
	try
		mobsInventoryInitialize()
	catch(var/exception/inv_e)
		log_subsystem_persistence_panic("Unhandled exception during mob inventory persistence initialization: [inv_e]")

	log_subsystem_persistence_info("Starting character identity initialization...")
	try
		charIdentityInitialize()
	catch(var/exception/id_e)
		log_subsystem_persistence_panic("Unhandled exception during character identity persistence initialization: [id_e]")

	log_subsystem_persistence_info("Starting mob position initialization...")
	try
		mobPositionInitialize()
	catch(var/exception/pos_e)
		log_subsystem_persistence_panic("Unhandled exception during mob position persistence initialization: [pos_e]")

	// GLOB.persistence_ready is set by SSpersistence_world_ready.Initialize()
	// which runs at init_order = 1 (last of all subsystems)  after atoms, mapping, etc.

	// One delayed power resync: the mid-init rebroadcast can't reach machines
	// restored after it (objectsInitialize) nor powernets that hadn't ticked
	// yet -- the rare "dark station, full APCs" boot state that a manual APC
	// on->auto cycle used to fix.
	addtimer(CALLBACK(src, PROC_REF(powerstateFinalize)), 30 SECONDS)

	// Prevent an immediate fire() right after init  first autosave should be 30 min after startup
	next_fire = world.time + wait

	log_subsystem_persistence_info("Persistence initialization: all steps completed in [(world.time - init_start_time) / 10] seconds. Check the lines above for any PANIC/ERROR entries from individual steps.")
	return SS_INIT_SUCCESS

/**
 * Shutdown of the persistence subsystem.
 * The shutdown consists of finalization steps for each persistent data type.
 */
/datum/controller/subsystem/persistence/Shutdown()
	if(prevent_saving)
		log_subsystem_persistence_warning("Persistence subsystem was toggled to not save. Skipping subsystem finalization.")
		return

	if(!databaseCheckConnection("subsystem shutdown"))
		log_subsystem_persistence_panic("SQL error during persistence subsystem shutdown. Cannot finalise persistence of the round.")
		return

	//  PRIORITY 0: Vault laces before anything else touches mob/organ state
	// Runs automatically on every real reboot (admin verb, vote, round-end
	// auto-restart, remote command) -- Shutdown() is the one proc every
	// world.Reboot() path funnels through via Master.Shutdown(). Does NOT
	// run on the periodic 30-minute autosave (fire()), which never restarts
	// the server.
	try
		vaultAllLaces()
	catch(var/exception/lace_e)
		log_subsystem_persistence_panic("Unhandled exception during pre-reboot lace vault sweep: [lace_e]")

	//  PRIORITY 1: Player data  must survive even if server is killed mid-shutdown
	try
		mobsHealthFinalize()
	catch(var/exception/health_e)
		log_subsystem_persistence_panic("Unhandled exception during mob health persistence finalization: [health_e]")

	try
		mobsInventoryFinalize()
	catch(var/exception/inv_e)
		log_subsystem_persistence_panic("Unhandled exception during mob inventory persistence finalization: [inv_e]")

	try
		charIdentityFinalize()
	catch(var/exception/id_e)
		log_subsystem_persistence_panic("Unhandled exception during character identity persistence finalization: [id_e]")

	try
		mobsPositionFinalizeAll()
	catch(var/exception/pos_e)
		log_subsystem_persistence_panic("Unhandled exception during mob position persistence finalization: [pos_e]")

	//  PRIORITY 2: World items  floor items first (fast), then persistent objects (can be slow)
	try
		floorItemsFinalize()
	catch(var/exception/floor_e)
		log_subsystem_persistence_panic("Unhandled exception during floor item persistence finalization: [floor_e]")

	try
		botsFinalize()
	catch(var/exception/bots_e)
		log_subsystem_persistence_panic("Unhandled exception during bot persistence finalization: [bots_e]")

	try
		objectsFinalize()
	catch(var/exception/objs_e)
		log_subsystem_persistence_panic("Unhandled exception during persistent objects finalization: [objs_e]")

	//  PRIORITY 3: World state  machinery, turfs, atmos
	try
		areasFinalize()
	catch(var/exception/areas_e)
		log_subsystem_persistence_panic("Unhandled exception during area persistence finalization: [areas_e]")

	try
		worldstateFinalize()
	catch(var/exception/ws_e)
		log_subsystem_persistence_panic("Unhandled exception during worldstate persistence finalization: [ws_e]")

	try
		turfsFinalize()
	catch(var/exception/turfs_e)
		log_subsystem_persistence_panic("Unhandled exception during turf persistence finalization: [turfs_e]")

	try
		atmosFinalize()
	catch(var/exception/atmos_e)
		log_subsystem_persistence_panic("Unhandled exception during atmos persistence finalization: [atmos_e]")

	//  PRIORITY 4: Administrative data 
	try
		economyFinalize()
	catch(var/exception/economy_e)
		log_subsystem_persistence_panic("Unhandled exception during economy persistence finalization: [economy_e]")

	try
		recordsFinalize()
	catch(var/exception/records_e)
		log_subsystem_persistence_panic("Unhandled exception during records persistence finalization: [records_e]")

	try
		researchFinalize()
	catch(var/exception/research_e)
		log_subsystem_persistence_panic("Unhandled exception during research persistence finalization: [research_e]")

	try
		factionFinalize()
	catch(var/exception/faction_e)
		log_subsystem_persistence_panic("Unhandled exception during faction persistence finalization: [faction_e]")

	try
		factionResearchFinalize()
	catch(var/exception/faction_research_e)
		log_subsystem_persistence_panic("Unhandled exception during faction research persistence finalization: [faction_research_e]")

	try
		factionChatPrune()
	catch(var/exception/faction_chat_e)
		log_subsystem_persistence_panic("Unhandled exception during faction chat pruning: [faction_chat_e]")

	try
		drydockAutoStashAll()
	catch(var/exception/drydock_e)
		log_subsystem_persistence_panic("Unhandled exception during drydock auto-stash: [drydock_e]")

	try
		shuttleStateFinalize()
	catch(var/exception/shuttle_e)
		log_subsystem_persistence_panic("Unhandled exception during shuttle state persistence finalization: [shuttle_e]")
