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

/// Set to TRUE once SSpersistence.Initialize() fully completes — gates PersistentAutoSpawn().
GLOBAL_VAR_INIT(persistence_ready, FALSE)

SUBSYSTEM_DEF(persistence)
	name = "Persistence"
	init_order = INIT_ORDER_PERSISTENCE // The order is tied with the init and maploading subsystem.
	wait = 30 MINUTES // Fires every 30 minutes; saves all persistence data including turfs and atmos.
	var/prevent_saving = FALSE // Toggle to prevent saving at round end, changed by toggle_persistence proc, used for admin purposes.

/**
 * Subsystem info stub message generation.
 */
/datum/controller/subsystem/persistence/stat_entry(msg)
	msg = ("Register: [length(GLOB.persistence_object_track_register)] | Prevent saving: [SSpersistence.prevent_saving ? "TRUE" : "FALSE"]")
	return msg

/**
 * Periodic save — fires every 30 minutes and saves all persistence data.
 * Since the world runs continuously with no round end, this is the primary save mechanism.
 * Shutdown() also runs all saves for graceful server restarts.
 */
/datum/controller/subsystem/persistence/fire()
	if(prevent_saving || !GLOB.config.sql_enabled)
		return

	log_subsystem_persistence_info("Persistence: Running periodic save.")
	to_world(SPAN_NOTICE(SPAN_BOLD("Automatic world save in progress. This may take 1-2 minutes.")))

	try
		forceSaveAll()
	catch(var/exception/e)
		log_subsystem_persistence_error("Periodic save failed: [e]")

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
		log_and_message_admins("has locked the server — joining is disabled", usr)
	else
		var/confirm = tgui_alert(usr, "Allow players to join the server again?", "Toggle Server Joining", list("Unlock", "Cancel"))
		if(confirm != "Unlock")
			return
		GLOB.config.enter_allowed = TRUE
		to_world(FONT_LARGE(EXAMINE_BLOCK_RED("Joining has been [SPAN_BOLD(SPAN_GOOD("re-enabled"))] by an administrator. The server is now open.")))
		log_and_message_admins("has unlocked the server — joining is enabled", usr)

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

	to_world(SPAN_NOTICE(SPAN_BOLD("World state save in progress.")))
	log_and_message_admins("initiated a world persistence save", usr)

	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("1/8")] Saving economy..."))
	SSpersistence.economyFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("2/8")] Saving records + research..."))
	SSpersistence.recordsFinalize()
	SSpersistence.researchFinalize()
	to_chat(usr, SPAN_NOTICE("[SPAN_BOLD("3/8")] Saving machinery states..."))
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

	log_and_message_admins("forced a mid-round persistence save", usr)
	to_chat(usr, SPAN_GOOD("Persistence save complete."))

	feedback_add_details("admin_verb","FPS")

/**
 * Public proc: save all persistence data immediately (economy, records, research, worldstate, turfs, atmos, objects, mob health, inventory).
 * Called by the force-save admin verb and by fire() for periodic saves.
 */
/datum/controller/subsystem/persistence/proc/forceSaveAll()
	if(!databaseCheckConnection("forceSaveAll"))
		return
	economyFinalize()
	recordsFinalize()
	researchFinalize()
	factionFinalize()
	factionResearchFinalize()
	worldstateFinalize()
	mobsHealthFinalize()
	mobsInventoryFinalize()
	charIdentityFinalize()
	mobsPositionFinalizeAll()
	turfsFinalize()
	atmosFinalize()
	objectsFinalize()
	floorItemsFinalize()

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

	try
		objectsInitialize()
	catch(var/exception/objs_e)
		log_subsystem_persistence_panic("Unhandled exception during persistent objects initialization: [objs_e]")
		return SS_INIT_FAILURE

	try
		economyInitialize()
	catch(var/exception/economy_e)
		log_subsystem_persistence_panic("Unhandled exception during economy persistence initialization: [economy_e]")

	try
		recordsInitialize()
	catch(var/exception/records_e)
		log_subsystem_persistence_panic("Unhandled exception during records persistence initialization: [records_e]")

	try
		researchInitialize()
	catch(var/exception/research_e)
		log_subsystem_persistence_panic("Unhandled exception during research persistence initialization: [research_e]")

	try
		factionInitialize()
	catch(var/exception/faction_e)
		log_subsystem_persistence_panic("Unhandled exception during faction persistence initialization: [faction_e]")

	try
		factionResearchInitialize()
	catch(var/exception/faction_res_e)
		log_subsystem_persistence_panic("Unhandled exception during faction research initialization: [faction_res_e]")

	try
		templateCheckPending()
	catch(var/exception/templates_e)
		log_subsystem_persistence_panic("Unhandled exception during template pending check: [templates_e]")

	try
		worldstateInitialize()
	catch(var/exception/ws_e)
		log_subsystem_persistence_panic("Unhandled exception during worldstate persistence initialization: [ws_e]")

	try
		turfsInitialize()
	catch(var/exception/turfs_e)
		log_subsystem_persistence_panic("Unhandled exception during turf persistence initialization: [turfs_e]")

	try
		atmosInitialize()
	catch(var/exception/atmos_e)
		log_subsystem_persistence_panic("Unhandled exception during atmos persistence initialization: [atmos_e]")

	try
		mobsHealthInitialize()
	catch(var/exception/health_e)
		log_subsystem_persistence_panic("Unhandled exception during mob health persistence initialization: [health_e]")

	try
		mobsInventoryInitialize()
	catch(var/exception/inv_e)
		log_subsystem_persistence_panic("Unhandled exception during mob inventory persistence initialization: [inv_e]")

	try
		charIdentityInitialize()
	catch(var/exception/id_e)
		log_subsystem_persistence_panic("Unhandled exception during character identity persistence initialization: [id_e]")

	try
		floorItemsInitialize()
	catch(var/exception/floor_e)
		log_subsystem_persistence_panic("Unhandled exception during floor item persistence initialization: [floor_e]")

	try
		mobPositionInitialize()
	catch(var/exception/pos_e)
		log_subsystem_persistence_panic("Unhandled exception during mob position persistence initialization: [pos_e]")

	// GLOB.persistence_ready is set by SSpersistence_world_ready.Initialize()
	// which runs at init_order = 1 (last of all subsystems) — after atoms, mapping, etc.

	// Prevent an immediate fire() right after init — first autosave should be 30 min after startup
	next_fire = world.time + wait
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

	// ── PRIORITY 1: Player data — must survive even if server is killed mid-shutdown ──
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

	// ── PRIORITY 2: World items — floor items first (fast), then persistent objects (can be slow) ──
	try
		floorItemsFinalize()
	catch(var/exception/floor_e)
		log_subsystem_persistence_panic("Unhandled exception during floor item persistence finalization: [floor_e]")

	try
		objectsFinalize()
	catch(var/exception/objs_e)
		log_subsystem_persistence_panic("Unhandled exception during persistent objects finalization: [objs_e]")

	// ── PRIORITY 3: World state — machinery, turfs, atmos ──
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

	// ── PRIORITY 4: Administrative data ──
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
