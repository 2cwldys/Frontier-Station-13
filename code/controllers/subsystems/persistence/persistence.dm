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

/// Whether non-members may enter a claimed faction's own Z-level(s) at all
/// (the Hub's own highsec beacon is always exempt). Default ON. Admin-toggled
/// (toggle_faction_raiding(), persistence_factions.dm), persists across
/// restarts via ss13_faction_raiding_toggle. Enforced in
/// _drydock_pick_access_mode()/_drydock_pick_turf_valid()
/// (telepad_drydock_boarding.dm), the shared gate behind Personal Travel's
/// leap and drydock boarding/disembark.
GLOBAL_VAR_INIT(faction_raiding_enabled, TRUE)

/// Current text shown by every printed hub law book (/obj/item/book/hub_laws)
/// -- always the LIVE value, not frozen at print time. Admin-edited
/// (modify_hub_laws(), persistence_factions.dm), persists across restarts
/// via ss13_hub_law_text. Empty string until an admin sets it.
GLOBAL_VAR_INIT(hub_law_text, "")

/// Whether the periodic autosave (fire(), below) also runs a full database
/// backup (the same scripts/db_backup that Trigger Database Backup runs on
/// demand) after each successful save. Default OFF -- opt-in. Admin-toggled
/// (toggle_auto_backup_on_autosave(), persistence_backups.dm), persists
/// across restarts via ss13_auto_backup_toggle.
GLOBAL_VAR_INIT(auto_backup_on_autosave, FALSE)

/// Runtime override for config.txt's MIN_CLIENT_BUILD -- the minimum BYOND
/// build (the 1687 of 516.1687) a client may connect with. 0 means "no
/// override", in which case the config value applies. Exists because config
/// is only read once at startup (configuration.dm load()), so without this a
/// change to the minimum would need a server restart. Admin-set
/// (set_min_client_build(), persistence_client_build.dm), persists across
/// restarts via ss13_min_client_build, enforced in client_procs.dm.
GLOBAL_VAR_INIT(min_client_build_override, 0)

/// TRUE when the CALLER of /world/Reboot() (world.dm) asked for a genuine,
/// process-ending shutdown, FALSE when it's a soft round reboot the world
/// comes straight back from. Set immediately before Master.Shutdown(),
/// because a subsystem's Shutdown() runs identically for both and cannot
/// tell them apart otherwise. Defaults TRUE so a shutdown path that never
/// went through Reboot() still cleans up rather than silently leaking a
/// child process.
///
/// Deliberately the CALLER's original request, not whether BYOND actually
/// went on to perform an OS-level restart -- Reboot() also forces its own
/// local hard_reset FALSE whenever TGS isn't available (a real OS restart
/// is unsafe with nothing present to relaunch the process), which is a
/// different question with a different answer: on any non-TGS deployment,
/// using that post-override value here made this permanently FALSE on
/// every single shutdown, soft or genuinely final, silently skipping the
/// Discord bot stop below every time.
GLOBAL_VAR_INIT(world_shutdown_is_hard, TRUE)

/// TRUE while faction raiding is suspended because no staff are online
/// (AUTO_SUSPEND_RAIDING_WHEN_UNSTAFFED, _compile_options.dm). Separate from
/// GLOB.faction_raiding_enabled so the two states stay distinguishable:
/// "off because staff turned it off" and "off because nobody is watching" get
/// restored very differently.
GLOBAL_VAR_INIT(faction_raiding_suspended, FALSE)
/// The value GLOB.faction_raiding_enabled held when suspension began, restored
/// when staff return. Meaningless unless faction_raiding_suspended is TRUE.
GLOBAL_VAR_INIT(faction_raiding_presuspend, TRUE)

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
	// Without this, the MC schedules the next fire from when THIS one was
	// due, not when it actually finished -- forceSaveAll() can take 1-2 real
	// minutes, which would otherwise be silently absorbed into the next
	// interval instead of the full 30 minutes always separating one
	// completed save from the next.
	flags = SS_POST_FIRE_TIMING
	var/prevent_saving = FALSE // Toggle to prevent saving at round end, changed by toggle_persistence proc, used for admin purposes.
	var/save_in_progress = FALSE // Set TRUE while a save is running to prevent concurrent saves.
	/// world.realtime the last save finished, or 0 if none has this round.
	///
	/// Exists because save_in_progress alone is unobservable from outside: a
	/// full save runs ~18s and external status pollers sample far less often
	/// than that, so the flag is almost always already back to FALSE by the
	/// time anyone looks. get_serverstatus (server_query.dm) reports the age of
	/// this instead, which a poller can use to notice a save it never actually
	/// caught in progress.
	var/last_save_completed = 0
	var/autosave_paused = FALSE
	var/autosave_pause_remaining = 0
	/// TRUE only when _autosave_empty_reconcile() (below) is what caused the
	/// current pause, never the admin's own "Toggle Autosave Pause" verb --
	/// so auto-resume can never override a pause the admin explicitly chose.
	var/autosave_auto_paused = FALSE
	/// Set by fire()'s drydock-defer branch so update_nextfire() (below) can
	/// honor a short retry instead of SS_POST_FIRE_TIMING's normal 30-minute
	/// recompute, which otherwise unconditionally overwrites whatever fire()
	/// itself assigns to next_fire the instant it returns (master/subsystem.dm)
	/// -- a plain `next_fire =` assignment inside fire() can never survive on
	/// its own for a SS_POST_FIRE_TIMING subsystem.
	var/deferred_retry_at = 0

/**
 * Subsystem info stub message generation.
 */
/datum/controller/subsystem/persistence/stat_entry(msg)
	msg = ("Register: [length(GLOB.persistence_object_track_register)] | Prevent saving: [SSpersistence.prevent_saving ? "TRUE" : "FALSE"] | Saving: [SSpersistence.save_in_progress ? "YES" : "NO"] | Autosave: [SSpersistence.autosave_paused ? "PAUSED" : "active"]")
	return msg

/// Honors a short drydock-deferral retry (deferred_retry_at) when fire() set
/// one; otherwise defers to the normal SS_POST_FIRE_TIMING recompute.
/datum/controller/subsystem/persistence/update_nextfire(reset_time = FALSE)
	if(!reset_time && deferred_retry_at)
		next_fire = deferred_retry_at
		deferred_retry_at = 0
		return
	..()

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
	// Never save mid-stash/retrieve -- a save walking turfs/objects while a
	// Z-level is being torn down or loaded is how half-state saves happen.
	// Retry every minute until drydock is fully idle (queue included: a
	// queued op starts the moment the active one ends). next_fire drives the
	// HUD "NEXT SAVE" countdown, so the deferral is visible to everyone.
	if(GLOB.drydock_op_active || length(GLOB.drydock_op_queue))
		deferred_retry_at = world.time + (1 MINUTE)
		next_fire = deferred_retry_at // keeps the HUD "NEXT SAVE" countdown honest in the interim
		log_subsystem_persistence_info("Persistence: Periodic save deferred -- ship stash/retrieve in progress.")
		return

	save_in_progress = TRUE
	SSstatistics.update_status()
	log_subsystem_persistence_info("Persistence: Running periodic save.")
	to_world(SPAN_NOTICE(SPAN_BOLD("Automatic world save in progress.")))
	play_announcer_voice_to_all('sound/AI/announcements/autosave_in_progress.ogg')

	try
		forceSaveAll()
	catch(var/exception/e)
		log_subsystem_persistence_error("Periodic save failed: [e]")
		log_and_message_admins("EVENT periodic persistence autosave FAILED: [e]", null)

	save_in_progress = FALSE
	last_save_completed = world.realtime
	SSstatistics.update_status()
	log_subsystem_persistence_info("Persistence: Periodic save complete.")
	to_world(SPAN_GOOD(SPAN_BOLD("World save complete.")))
	// Discord-only (log_admin(), not log_and_message_admins()) -- to_world()
	// above already covers live visibility, this just closes the gap where
	// routine automatic saves never reached the admin log webhook at all.
	log_admin("EVENT periodic persistence autosave completed.")

	// Admin-toggled (toggle_auto_backup_on_autosave(), persistence_backups.dm).
	// Reported via subsystem log on success and an admin ping on failure --
	// not to_world, so this stays silent to players every 30 minutes like the
	// rest of the automatic persistence machinery (_autosave_empty_reconcile()
	// above behaves the same way).
	if(GLOB.auto_backup_on_autosave)
		if(!_autoBackupSecurityOK())
			_autoBackupDisableForSecurity()
		else
			log_subsystem_persistence_info("Persistence: Running automatic post-autosave database backup...")
			var/list/backup_result = run_database_backup()
			if(backup_result["success"])
				log_subsystem_persistence_info("Persistence: Automatic post-autosave database backup complete.")
				log_admin("EVENT automatic post-autosave database backup complete.")
			else
				log_subsystem_persistence_error("Persistence: Automatic post-autosave database backup FAILED (exit [backup_result["errorcode"]]): [backup_result["stderr"] || backup_result["stdout"]]")
				log_and_message_admins("automatic post-autosave database backup FAILED (exit [backup_result["errorcode"]])", null)
	// ignite() (subsystem.dm) is waitfor=FALSE, and forceSaveAll() really
	// does sleep across real time (CHECK_TICK) for a save this size -- so
	// Master's RunQueue() gets control back (and calls update_nextfire())
	// at the FIRST yield, i.e. essentially when the save STARTED, not when
	// it finished ~1-2 minutes later. SS_POST_FIRE_TIMING can't fix this on
	// its own since it's computed at that same premature moment. Setting
	// next_fire explicitly here, now that the save is actually done, is
	// what makes the HUD countdown (screen_objects.dm) show a real 30
	// minutes instead of 30 minutes minus however long the save took.
	next_fire = world.time + wait
	// Kick anything that queued behind save_in_progress (the drydock gates
	// now queue stash/retrieve requests arriving mid-save) -- the normal
	// drain only runs after another drydock op, never after a save.
	_drydockProcessNextQueued()

/**
 * Ad hoc full save triggered when the last active player leaves the round
 * via cryo (see the hook in persistStoreCharacter(), persistence_cryo.dm) --
 * distinct from fire()'s scheduled 30-minute save, and from the admin's own
 * Force Persistence Save (force_persistence_save(), persistence_backups.dm),
 * but reuses the exact same forceSaveAll()/save_in_progress/drydock-idle
 * guard fire() uses. Must be dispatched via INVOKE_ASYNC by the caller, never
 * called inline -- forceSaveAll() yields across ticks for a real 1-2 minutes,
 * and persistStoreCharacter()'s own caller needs to hand its client off to a
 * new lobby mob immediately afterward with no sleep in between.
 *
 * Silent (subsystem log only, no to_world/announcer voice line) -- there is
 * nobody left in a body to see it, matching how _autosave_empty_reconcile()'s
 * own automatic pause/resume of this same subsystem stays silent for its own
 * automatic actions.
 */
/datum/controller/subsystem/persistence/proc/runLobbyEmptyAutosave()
	if(prevent_saving || !GLOB.config.sql_enabled || save_in_progress)
		return
	if(GLOB.drydock_op_active || length(GLOB.drydock_op_queue))
		return
	save_in_progress = TRUE
	log_subsystem_persistence_info("Persistence: Running lobby-empty autosave (last player left via cryo).")
	try
		forceSaveAll()
	catch(var/exception/e)
		log_subsystem_persistence_error("Lobby-empty autosave failed: [e]")
		log_and_message_admins("EVENT lobby-empty persistence autosave FAILED: [e]", null)
	save_in_progress = FALSE
	last_save_completed = world.realtime
	log_subsystem_persistence_info("Persistence: Lobby-empty autosave complete.")
	// Discord-only (log_admin(), not log_and_message_admins()) -- this proc
	// is deliberately silent to players/live chat (nobody's left in a body
	// to see it), but that shouldn't also mean invisible to the admin log.
	log_admin("EVENT lobby-empty persistence autosave completed (last player left via cryo).")
	_drydockProcessNextQueued()

	if(GLOB.auto_backup_on_autosave)
		if(!_autoBackupSecurityOK())
			_autoBackupDisableForSecurity()
		else
			var/list/backup_result = run_database_backup()
			if(backup_result["success"])
				log_subsystem_persistence_info("Persistence: Automatic post-lobby-autosave database backup complete.")
				log_admin("EVENT automatic post-lobby-autosave database backup complete.")
			else
				log_subsystem_persistence_error("Persistence: Automatic post-lobby-autosave database backup FAILED (exit [backup_result["errorcode"]]): [backup_result["stderr"] || backup_result["stdout"]]")
				log_and_message_admins("automatic post-lobby-autosave database backup FAILED (exit [backup_result["errorcode"]])", null)

/// TRUE if any mob in the round is alive, has a connected client, and is
/// actively possessing it right now -- i.e. someone is really playing, not
/// just an admin ghost/ dead body with a lingering ckey/ lobby client.
/// exclude: skip this mob when checking -- needed by callers checking "is
/// anyone ELSE still playing" while the mob in question is mid-departure and
/// may still have its client attached (see runLobbyEmptyAutosave()'s hook in
/// persistStoreCharacter(), persistence_cryo.dm).
/proc/_any_active_player_character(mob/living/exclude)
	for(var/mob/M in GLOB.mob_list)
		if(M == exclude)
			continue
		if(M.stat != DEAD && M.client)
			return TRUE
	return FALSE

/// How often _autosave_empty_reconcile() below re-checks round population.
#define AUTOSAVE_EMPTY_CHECK_INTERVAL 1 MINUTE

/// Starts the recurring "is anyone actually playing" reconciliation --
/// called once from SSpersistence's own Initialize().
/proc/_autosave_empty_reconcile_start()
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_autosave_empty_reconcile)), AUTOSAVE_EMPTY_CHECK_INTERVAL, TIMER_LOOP)

/// Auto-pauses the periodic autosave (same visible PAUSED status/mechanism
/// as the admin's manual "Toggle Autosave Pause" verb) the moment nobody's
/// actively playing, and auto-resumes it the moment someone is again --
/// without ever touching or overriding a pause the admin verb itself set
/// (see autosave_auto_paused's doc comment).
/proc/_autosave_empty_reconcile()
	if(SSpersistence.prevent_saving || !GLOB.config.sql_enabled)
		return
	var/playing = _any_active_player_character()
	if(!playing && !SSpersistence.autosave_paused)
		SSpersistence.autosave_pause_remaining = max(0, SSpersistence.next_fire - world.time)
		SSpersistence.next_fire = world.time + (999 MINUTES)
		SSpersistence.autosave_paused = TRUE
		SSpersistence.autosave_auto_paused = TRUE
		log_subsystem_persistence_info("Persistence: Autosave auto-paused -- no active player characters.")
		log_admin("EVENT periodic autosave auto-paused -- no active player characters.")
	else if(playing && SSpersistence.autosave_auto_paused)
		SSpersistence.next_fire = world.time + max(0, SSpersistence.autosave_pause_remaining)
		SSpersistence.autosave_paused = FALSE
		SSpersistence.autosave_auto_paused = FALSE
		log_subsystem_persistence_info("Persistence: Autosave auto-resumed -- a player character is active again.")
		log_admin("EVENT periodic autosave auto-resumed -- a player character is active again.")

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
	set category = "Persistence.Misc"

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

	SSstatistics.update_status()
	feedback_add_details("admin_verb", "TSJ")

/// Heads-up broadcast only -- does not itself trigger any save or reboot.
/// Run this first, then separately trigger the actual forced save (Force
/// Persistence Save) and/or reboot.
/datum/admins/proc/warn_pending_save()
	set name = "Warn Pending Save"
	set category = "Persistence.Backups & Saves"

	if(!check_rights(R_ADMIN))
		return

	to_world(FONT_LARGE(EXAMINE_BLOCK_RED("[SPAN_BOLD("ATTENTION")]: A forced save and reboot is coming shortly to refresh the game world and overmap. Get to a safe location.")))
	play_announcer_voice_to_all('sound/AI/announcements/romble.ogg')
	log_and_message_admins("issued a pending-save warning to the server", usr)

/datum/admins/proc/toggle_persistence()
	set name = "Toggle Persistence"
	set category = "Persistence.Backups & Saves"

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
	set category = "Persistence.Backups & Saves"

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
	set category = "Persistence.Backups & Saves"

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

	// Mirror fire()'s deferral (persistence.dm) -- a retrieve/stash mid-flight
	// is a multi-second window where objectsApplyZ()/floorItemsApplyZ() are
	// still populating a ship's scope; finalizing that same scope here
	// concurrently would interleave two independent save passes over it and
	// can produce duplicate rows.
	if(GLOB.drydock_op_active || length(GLOB.drydock_op_queue))
		to_chat(usr, SPAN_WARNING("A ship stash/retrieve is in progress. Please wait for it to complete before forcing a save."))
		return

	SSpersistence.save_in_progress = TRUE
	to_world(SPAN_NOTICE(SPAN_BOLD("World state save in progress.")))
	play_announcer_voice_to_all('sound/AI/announcements/autosave_in_progress.ogg')
	log_and_message_admins("initiated a world persistence save", usr)

	// try/catch is NOT optional around this whole sequence: save_in_progress
	// gates the Stash, Retrieve and Scuttle buttons on every ship schematic
	// AND the Ship Drydock program (plus joining, plus another save). An
	// exception escaping ANY of these -- not just the last one -- between
	// setting save_in_progress TRUE and clearing it below leaves everything
	// gated on it stuck, with no way to recover short of a server restart
	// (or the Emergency Stop Save admin verb).
	try
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
		// Same trailing cleanup the periodic save and Shutdown() both run --
		// see drydockForgetBeaconEnvelopes() (persistence_shuttles.dm).
		SSpersistence.drydockForgetBeaconEnvelopes()
	catch(var/exception/force_save_e)
		log_subsystem_persistence_panic("Unhandled exception during forced persistence save: [force_save_e]")
		to_chat(usr, SPAN_WARNING("Persistence save failed partway through -- see the persistence log. save_in_progress has still been cleared."))

	SSpersistence.save_in_progress = FALSE
	SSpersistence.last_save_completed = world.realtime
	// Same post-save queue kick as the periodic fire() -- stash/retrieve
	// requests that arrived during this save are waiting on it.
	SSpersistence._drydockProcessNextQueued()
	log_and_message_admins("forced a mid-round persistence save", usr)
	to_chat(usr, SPAN_GOOD("Persistence save complete."))

	feedback_add_details("admin_verb","FPS")

/**
 * Actually unsticks a hung save, not just the flag. A stuck save is the
 * original proc sleeping forever in datum/db_query/sync() (dbcore.dm:550-552,
 * `while(status < DB_QUERY_FINISHED): stoplag()`), waiting on
 * SSdbcore's connection POOL (SSdbcore.connection -- a rust-g pool handle,
 * not a single connection, see dbcore.dm's Connect()) to ever report that
 * query finished. If the underlying MySQL query is genuinely wedged (e.g.
 * a lock wait that never resolves), that pool slot -- and the suspended
 * proc waiting on it -- is orphaned forever; merely clearing
 * save_in_progress unblocks everything ELSE gated on it (joining, drydock
 * ops, a new save) but leaves that original proc as a permanent zombie and
 * does nothing to recover the pool capacity it's still holding.
 *
 * SSdbcore.Disconnect() + Connect() tears down and rebuilds the whole
 * connection pool, forcibly severing whatever query is stuck. This is safe:
 * individual SQL statements are atomic, so MySQL rolls back the interrupted
 * one cleanly -- nothing is left half-written. The real cost is that any
 * OTHER query genuinely in flight at that exact moment also gets aborted
 * and has to be retried by its own caller, same as any ordinary "DB
 * connection dropped" hiccup this codebase already tolerates everywhere
 * (databaseCheckConnection() failing is a normal, handled case). Severing
 * the connection lets the ORIGINAL stuck proc's query fail for real, which
 * lets it actually resume and hit its own try/catch (both
 * force_persistence_save() and forceSaveAll() have one) and finish
 * properly instead of staying orphaned.
 */
/datum/admins/proc/emergency_stop_save()
	set name = "Emergency Stop Save"
	set category = "Persistence.Backups & Saves"
	set desc = "Resets the database connection pool to actually unstick a hung save (not just clear the flag), then clears save_in_progress. Only use once you're sure a save is genuinely stuck, not just slow."

	if(!check_rights(R_ADMIN))
		return

	if(!SSpersistence.save_in_progress)
		to_chat(usr, SPAN_NOTICE("No save is currently marked in progress."))
		return

	var/confirm = tgui_alert(usr, "This resets the database connection pool -- killing whatever query is genuinely stuck -- then clears save_in_progress. SQL statements are atomic, so the interrupted one rolls back cleanly with nothing half-written, but any OTHER query in flight right now also gets aborted and will need to retry. Only do this if a save has stalled far longer than one ever should, not just running slow.", "Emergency Stop Save", list("Reset & Clear", "Cancel"))
	if(confirm != "Reset & Clear")
		return

	SSdbcore.Disconnect()
	SSdbcore.Connect()

	SSpersistence.save_in_progress = FALSE
	SSpersistence._drydockProcessNextQueued()
	log_and_message_admins("reset the database connection pool and force-cleared a stuck save_in_progress flag (Emergency Stop Save)", usr)
	to_chat(usr, SPAN_GOOD("Database connection pool reset, save_in_progress cleared. Saves, joins, and drydock ops can resume."))

	feedback_add_details("admin_verb","ESS")

/**
 * Sweeps the whole world and vaults every dead/unclaimed neural lace, plus
 * any sitting loose. Never touches a lace still installed in a living
 * owner -- that check must run before _auto_transfer_to_storage() is ever
 * called, not after, so a living person's lace is never even momentarily
 * touched. Shared by the admin verb (manual, mid-round) and Shutdown()
 * (automatic, on every real reboot -- not the periodic autosave, which
 * never touches this).
 */
/datum/controller/subsystem/persistence/proc/vaultAllLaces(list/z_filter = null)
	var/vaulted = 0
	var/skipped_alive = 0
	for(var/obj/item/organ/internal/neural_lace/L in world)
		if(z_filter && !(GET_Z(L) in z_filter))
			continue
		if(istype(L.loc, /obj/structure/machinery/lace_storage))
			continue // already vaulted, nothing to do

		if(L.owner && L.owner.stat != DEAD)
			skipped_alive++
			continue

		L._auto_transfer_to_storage()
		// A lace still installed on a dead body only gets as far as surgical
		// extraction on the call above -- _auto_transfer_to_storage() ejects
		// it via removed() and returns, scheduling a fresh 4-hour timer
		// rather than continuing on to the vault itself (see that proc's own
		// "removed() will call this again indirectly" comment: that's the
		// NEW timer, not an immediate re-invocation). Finish the job now
		// instead of leaving a freshly-extracted, still-unvaulted lace_mob
		// exactly as exposed to the imminent restart as before this sweep
		// existed.
		if(L.lace_occupied && !istype(L.loc, /obj/structure/machinery/lace_storage))
			L._auto_transfer_to_storage()
		vaulted++

	log_subsystem_persistence_info("Lace vault sweep: [vaulted] vaulted, [skipped_alive] skipped (alive owner).")
	return list("vaulted" = vaulted, "skipped_alive" = skipped_alive)

/datum/admins/proc/force_vault_all_laces()
	set name = "Force Vault All Laces"
	set category = "Persistence.Backups & Saves"
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

	// Recall every away-from-home deployed ship (and its sub-ships) before
	// anything else runs -- see drydockRecallAllDeployed()'s own doc comment
	// (persistence_shuttles.dm) for why this closes the "duplicated at an
	// away-site z across a restart" risk without actually stashing anyone's
	// ship. Deliberately first, before any Finalize sweep below.
	try
		drydockRecallAllDeployed()
	catch(var/exception/recall_e)
		log_subsystem_persistence_panic("Unhandled exception during drydock recall sweep: [recall_e]")

	try
		economyFinalize()
	catch(var/exception/economy_e)
		log_subsystem_persistence_panic("Unhandled exception during economy persistence finalization: [economy_e]")

	try
		stockMarketSaveCompanies()
	catch(var/exception/stock_market_e)
		log_subsystem_persistence_panic("Unhandled exception during stock market persistence finalization: [stock_market_e]")

	try
		supplyBeaconsSaveAll()
	catch(var/exception/supply_beacon_e)
		log_subsystem_persistence_panic("Unhandled exception during supply beacon persistence finalization: [supply_beacon_e]")

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

	// Last, so it cleans up whatever the sweeps above just wrote -- see
	// drydockForgetBeaconEnvelopes()'s own doc comment (persistence_shuttles.dm)
	// for why a docking pad's tiles are never meant to persist.
	try
		drydockForgetBeaconEnvelopes()
	catch(var/exception/beacon_forget_e)
		log_subsystem_persistence_panic("Unhandled exception during docking beacon envelope cleanup: [beacon_forget_e]")

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

	// CentCom is a bare, template-less Z built directly by atlas.dm at boot --
	// it has no DB row of its own and no ruin/away_site template to pin, so
	// unlike every other Z it can never earn its way onto the allow list
	// before this. Without this, CentCom only gets allow-listed reactively
	// (persistence_pin_site_at_z(), via a faction beacon's _apply_network())
	// -- which runs AFTER the restore passes below already skipped it for
	// this boot.
	for(var/z = 1 to world.maxz)
		if(is_centcom_level(z))
			GLOB.persistence_pinned_site_z |= z
			GLOB.persistence_zlevel_allow |= z

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

	log_subsystem_persistence_info("Starting cargo imports initialization...")
	try
		cargoImportsInitialize()
	catch(var/exception/ci_e)
		log_subsystem_persistence_error("Cargo imports init failed: [ci_e] on [ci_e.file]:[ci_e.line]")

	log_subsystem_persistence_info("Starting drydock ship price initialization...")
	try
		drydockShipPricesInitialize()
	catch(var/exception/dsp_e)
		log_subsystem_persistence_error("Drydock ship price init failed: [dsp_e] on [dsp_e.file]:[dsp_e.line]")

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

	log_subsystem_persistence_info("Starting outfit template initialization...")
	try
		outfitTemplatesInitialize()
	catch(var/exception/ot_e)
		log_subsystem_persistence_error("Outfit templates init failed: [ot_e] on [ot_e.file]:[ot_e.line]")

	log_subsystem_persistence_info("Starting hostile NPC preset initialization...")
	try
		hostileNpcPresetsInitialize()
	catch(var/exception/hnp_e)
		log_subsystem_persistence_error("Hostile NPC presets init failed: [hnp_e] on [hnp_e.file]:[hnp_e.line]")

	log_subsystem_persistence_info("Starting away site mob preset initialization...")
	try
		awaySiteMobPresetsInitialize()
	catch(var/exception/asmp_e)
		log_subsystem_persistence_error("Away site mob presets init failed: [asmp_e] on [asmp_e.file]:[asmp_e.line]")

	// Arms the "is anyone actually playing" autosave auto-pause sweep.
	_autosave_empty_reconcile_start()

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

	// Floor items must run after objects (machines/structures are recreated
	// before worldstateInitialize applies their saved state vars) AND after
	// faction (GLOB.persistence_faction_cache, populated by factionInitialize()
	// above, has to be ready before a restored floor item can look itself up
	// through get_faction_color() -- restoring floor items any earlier had a
	// faction-tagged item's tint silently resolve to null every boot, while
	// mobsInventoryInitialize() below -- which runs the same lookup for worn
	// items -- was unaffected since it already runs after faction).
	log_subsystem_persistence_info("Starting floor item initialization...")
	try
		floorItemsInitialize()
	catch(var/exception/floor_e)
		log_subsystem_persistence_panic("Unhandled exception during floor item persistence initialization: [floor_e]")

	log_subsystem_persistence_info("Starting faction founding petition initialization...")
	try
		factionFoundingInitialize()
	catch(var/exception/faction_founding_e)
		log_subsystem_persistence_panic("Unhandled exception during faction founding petition initialization: [faction_founding_e]")

#ifdef FACTION_ALLIANCES
	log_subsystem_persistence_info("Starting faction alliance initialization...")
	try
		factionAlliancesInitialize()
	catch(var/exception/faction_alliances_e)
		log_subsystem_persistence_panic("Unhandled exception during faction alliance initialization: [faction_alliances_e]")
#endif //FACTION_ALLIANCES

	log_subsystem_persistence_info("Starting faction creation toggle initialization...")
	try
		factionCreationToggleInitialize()
	catch(var/exception/faction_toggle_e)
		log_subsystem_persistence_panic("Unhandled exception during faction creation toggle initialization: [faction_toggle_e]")

	log_subsystem_persistence_info("Starting faction raiding toggle initialization...")
	try
		factionRaidingToggleInitialize()
	catch(var/exception/faction_raiding_toggle_e)
		log_subsystem_persistence_panic("Unhandled exception during faction raiding toggle initialization: [faction_raiding_toggle_e]")

#ifdef AUTO_SUSPEND_RAIDING_WHEN_UNSTAFFED
	// Immediately after the stored value is loaded, so a server that boots
	// unattended starts suspended rather than waiting for the first staff
	// transition to notice. Any staff already connected keeps it as loaded.
	try
		// announce = FALSE -- this runs inside Initialize() with nobody
		// connected to read a message_admins(); the subsystem log line is the
		// useful record at boot.
		raidingUpdateForStaffPresence(FALSE)
	catch(var/exception/raiding_presence_e)
		log_subsystem_persistence_error("Unhandled exception during raiding staff-presence evaluation: [raiding_presence_e]")
#endif

	log_subsystem_persistence_info("Starting hub law text initialization...")
	try
		hubLawTextInitialize()
	catch(var/exception/hub_law_text_e)
		log_subsystem_persistence_panic("Unhandled exception during hub law text initialization: [hub_law_text_e]")

	log_subsystem_persistence_info("Starting auto-backup-on-autosave toggle initialization...")
	try
		autoBackupToggleInitialize()
	catch(var/exception/auto_backup_toggle_e)
		log_subsystem_persistence_panic("Unhandled exception during auto-backup-on-autosave toggle initialization: [auto_backup_toggle_e]")

	log_subsystem_persistence_info("Starting minimum client build initialization...")
	try
		minClientBuildInitialize()
	catch(var/exception/min_client_build_e)
		log_subsystem_persistence_panic("Unhandled exception during minimum client build initialization: [min_client_build_e]")

	log_subsystem_persistence_info("Starting stock market initialization...")
	try
		stockMarketInitialize()
	catch(var/exception/stock_market_e)
		log_subsystem_persistence_panic("Unhandled exception during stock market initialization: [stock_market_e]")

	log_subsystem_persistence_info("Starting supply beacon initialization...")
	try
		supplyBeaconsInitialize()
	catch(var/exception/supply_beacon_e)
		log_subsystem_persistence_panic("Unhandled exception during supply beacon initialization: [supply_beacon_e]")

	log_subsystem_persistence_info("Starting faction shareholders initialization...")
	try
		factionShareholdersInitialize()
	catch(var/exception/faction_shareholders_e)
		log_subsystem_persistence_panic("Unhandled exception during faction shareholders initialization: [faction_shareholders_e]")

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
#ifdef DISCORD_STATUS_BOT_AUTOSTART
	// Before the early returns below -- stopping the bot has nothing to do
	// with whether this round's state is being saved, and leaking the process
	// on a prevent_saving or DB-failure shutdown would be a silent orphan.
	try
		discordStatusBotStop()
	catch(var/exception/discord_bot_e)
		log_subsystem_persistence_error("Unhandled exception stopping the Discord status bot: [discord_bot_e]")
#endif

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
		stockMarketSaveCompanies()
	catch(var/exception/stock_market_e)
		log_subsystem_persistence_panic("Unhandled exception during stock market persistence finalization: [stock_market_e]")

	try
		supplyBeaconsSaveAll()
	catch(var/exception/supply_beacon_e)
		log_subsystem_persistence_panic("Unhandled exception during supply beacon persistence finalization: [supply_beacon_e]")

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

	// After the stash sweep above -- see drydockForgetBeaconEnvelopes()'s own
	// doc comment (persistence_shuttles.dm). A pad's tiles are never meant to
	// survive a reboot, so nothing left at one can reconstruct itself.
	try
		drydockForgetBeaconEnvelopes()
	catch(var/exception/beacon_forget_e)
		log_subsystem_persistence_panic("Unhandled exception during docking beacon envelope cleanup: [beacon_forget_e]")

	try
		shuttleStateFinalize()
	catch(var/exception/shuttle_e)
		log_subsystem_persistence_panic("Unhandled exception during shuttle state persistence finalization: [shuttle_e]")
