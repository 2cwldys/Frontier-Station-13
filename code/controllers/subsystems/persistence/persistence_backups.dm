/*
 * Persistence - Database Backups
 * Lets an R_SERVER admin trigger scripts/db_backup (a parameter-free mysqldump +
 * 7-backup rotation, see scripts/db_backup.ps1) from in-game instead of needing
 * shell access to the host.
 *
 * Deliberately does NOT expose restore. scripts/db_restore.ps1 overwrites the live
 * database entirely, is built around interactive Read-Host prompts (pick a backup,
 * then type RESTORE) with no CLI parameters, and its own header says the change
 * doesn't take effect until the server is restarted anyway -- it was never going to
 * be a live in-round action. world.shelleo() (code/__HELPERS/shell.dm) also has no
 * way to pipe further input into a still-running process, so there is no way to
 * "steer" that script from a TGUI window short of building a persistent shell
 * bridge, which is a fundamentally different and far riskier thing than a backup
 * button.
 */

/**
 * Shared backup runner -- shells out to scripts/db_backup (mysqldump + 7-backup
 * rotation) and hands back the raw result, EXCEPT inside a local game-server
 * shard (GLOB.config.shard_id set), where it transparently runs
 * scripts/central/shard_backup_self.sh instead -- same idea, but mysqldump
 * straight over the network to the shard's own sibling DB container, since a
 * shard's container has no Docker CLI to run scripts/db_backup with at all.
 * Both callers below stay oblivious to which one actually ran. No chat/log
 * reporting in here; the two callers (the admin verb and fire()'s automatic
 * post-autosave hook, persistence.dm) each report success/failure in
 * whatever way fits their own context (one to the calling admin, the other
 * to the subsystem log/admins).
 *
 * Retries once after a short delay on failure. This whole call chain
 * (world.shelleo() -> wscript -> cmd -> PowerShell -> docker exec ->
 * mysqldump) is several nested OS process launches deep, and any one of them
 * can transiently fail for reasons that have nothing to do with this code --
 * most concretely, aurora-db reporting "running" in `docker ps` before
 * MariaDB inside it has actually finished starting, which is normal after
 * any host reboot and especially likely after an unclean one (e.g. a power
 * outage). scripts/db_backup.ps1 and .sh both now wait for a real DB
 * readiness ping before attempting the dump, which is the primary fix for
 * that specific case; this retry is a second, cheap layer of defense against
 * anything else transient in the chain (a fresh boot only happens once, but
 * the process-spawn chain runs on every single attempt, automatic or
 * manual). One short backoff and one retry turns a one-off blip into a
 * non-event instead of an admin-alerting failure.
 */
/datum/controller/subsystem/persistence/proc/run_database_backup()
	// scripts/db_backup targets the main server's aurora-db container by
	// fixed name -- unreachable from inside a shard's own container (a
	// different local DB entirely, aurora-shard-<id>-db), which also has no
	// Docker CLI installed to run it with regardless. Transparently run the
	// shard's own in-container backup script instead (mysqldump straight
	// over the network to its sibling DB container -- no docker CLI needed),
	// so the verb/auto-toggle both just work the same either way.
	var/command = GLOB.config.shard_id ? "scripts/central/shard_backup_self.sh" : ((world.system_type == UNIX) ? "scripts/db_backup.sh" : "scripts\\db_backup.bat")
	// Relative -- the shelled-out process's cwd comes from DreamDaemon's own OS
	// process cwd, which isn't guaranteed to be the repo root (see
	// GLOB.config.server_root_path's doc comment, configuration.dm). Prefix an
	// explicit cd when configured so this doesn't depend on how DD was launched.
	command = prefix_server_root_cd(command)

	var/list/result = _run_database_backup_attempt(command)
	if(!result["success"])
		log_subsystem_persistence_warning("Persistence: Database backup attempt 1 failed (exit [result["errorcode"]])[(result["stdout"] || result["stderr"]) ? ": [result["stdout"]][result["stderr"]]" : " -- no output captured"]. Retrying once after a short delay...")
		sleep(30)
		result = _run_database_backup_attempt(command)
		if(result["success"])
			log_subsystem_persistence_info("Persistence: Database backup succeeded on retry.")

	if(!result["success"] && !result["stdout"] && !result["stderr"])
		// Both attempts produced nothing to go on -- the failure is happening
		// before db_backup.ps1's own error handling ever runs (i.e. somewhere
		// in the shell/wscript/cmd launch chain itself, not inside the script),
		// which is exactly what a transient OS/AV/process-spawn hiccup looks
		// like rather than a real script bug. Say so instead of a bare exit code.
		result["stderr"] = "(no output captured on either attempt -- failed before the backup script itself ran; likely a transient OS/security-software interruption rather than a script error. Check Docker/antivirus logs for this timestamp if it recurs.)"
	return result

/datum/controller/subsystem/persistence/proc/_run_database_backup_attempt(command)
	var/list/result = world.shelleo(command)
	var/errorcode = result[1]
	var/stdout = result[2]
	var/stderr = result[3]

	// db_backup.ps1 Write-Error's "Backup failed..." on a non-zero mysqldump exit
	// but the wrapping .bat/.sh can still exit 0 -- check the text too, not just
	// the process exit code.
	var/success = !errorcode && !findtext(stdout, "Backup failed")
	return list("success" = success, "errorcode" = errorcode, "stdout" = stdout, "stderr" = stderr)

/datum/admins/proc/trigger_database_backup()
	set name = "Trigger Database Backup"
	set category = "Persistence.Backups & Saves"
	set desc = "Runs scripts/db_backup now and reports the result."

	if(!check_rights(R_SERVER))
		return

	// world.shelleo() (run_database_backup(), below) is a raw OS shell-out --
	// BYOND refuses that outright under Safe/Ultrasafe security, so this
	// would otherwise just silently fail every time under either of those.
	// Same TgsSecurityLevel() check toggle_auto_backup_on_autosave() uses --
	// null (TGS absent, e.g. a bare local test server) treated as Trusted.
	var/current_security = world.TgsSecurityLevel()
	if(!isnull(current_security) && current_security != TGS_SECURITY_TRUSTED)
		to_chat(usr, SPAN_WARNING("Database backup can't run while this server's security level is Safe/Ultrasafe -- it shells out to run the backup script, which BYOND blocks under anything but Trusted. Set the server's security level to Trusted first."))
		return

	to_chat(usr, SPAN_NOTICE("Running database backup..."))

	var/list/result = SSpersistence.run_database_backup()
	if(!result["success"])
		to_chat(usr, SPAN_WARNING("Backup failed (exit code [result["errorcode"]]):"))
		to_chat(usr, SPAN_WARNING(result["stderr"] || result["stdout"] || "No output captured."))
		log_and_message_admins("ran a database backup -- FAILED (exit [result["errorcode"]])", usr)
		return

	to_chat(usr, SPAN_GOOD("Backup complete:"))
	// A script can legitimately report progress on stderr while still
	// succeeding, so show both rather than only stdout -- printing an empty
	// line was what made a completed backup look like it said nothing at all.
	var/report = trim(result["stdout"])
	if(trim(result["stderr"]))
		report = report ? "[report]\n[trim(result["stderr"])]" : trim(result["stderr"])
	to_chat(usr, report || "No output captured.")
	log_and_message_admins("ran a manual database backup", usr)

/// Loads the auto-backup-on-autosave toggle from ss13_auto_backup_toggle at
/// boot. Mirrors factionRaidingToggleInitialize() (persistence_factions.dm).
/datum/controller/subsystem/persistence/proc/autoBackupToggleInitialize()
	if(!databaseCheckConnection("autoBackupToggleInitialize"))
		return
	try
		var/datum/db_query/q = SSdbcore.NewQuery("SELECT enabled FROM ss13_auto_backup_toggle WHERE id = 1", list())
		q.Execute()
		if(databaseCheckQueryResult(q, "autoBackupToggleInitialize") && q.NextRow())
			GLOB.auto_backup_on_autosave = text2num(q.item[1])
		qdel(q)
	catch(var/exception/toggle_e)
		log_subsystem_persistence_error("Backups: failed to load auto-backup-on-autosave toggle: [toggle_e]")

	// Toggle was left on from a prior session that was Trusted -- this boot
	// might not be. Catch it here instead of leaving it on to fail silently
	// on every future autosave.
	if(GLOB.auto_backup_on_autosave && !_autoBackupSecurityOK())
		_autoBackupDisableForSecurity()

/// Shared security gate -- TRUE if this instance can actually run
/// world.shelleo() right now (null = TGS absent, treated as Trusted, same
/// as toggle_auto_backup_on_autosave()'s own reasoning).
/datum/controller/subsystem/persistence/proc/_autoBackupSecurityOK()
	var/current_security = world.TgsSecurityLevel()
	return isnull(current_security) || current_security == TGS_SECURITY_TRUSTED

/datum/controller/subsystem/persistence/proc/_autoBackupDisableForSecurity()
	setAutoBackupOnAutosave(FALSE)
	log_and_message_admins("Auto-backup-on-autosave was automatically disabled -- server security level is no longer Trusted.")

/datum/controller/subsystem/persistence/proc/setAutoBackupOnAutosave(enabled)
	GLOB.auto_backup_on_autosave = enabled
	if(!databaseCheckConnection("setAutoBackupOnAutosave"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_auto_backup_toggle (id, enabled) VALUES (1, :enabled) ON DUPLICATE KEY UPDATE enabled = VALUES(enabled)",
		list("enabled" = enabled ? 1 : 0)
	)
	q.Execute()
	databaseCheckQueryResult(q, "setAutoBackupOnAutosave")
	qdel(q)

/// Admin toggle: whether the periodic autosave (fire(), persistence.dm) also
/// runs this same backup automatically after each successful save. Persists
/// across restarts via ss13_auto_backup_toggle (setAutoBackupOnAutosave()).
/datum/admins/proc/toggle_auto_backup_on_autosave()
	set name = "Toggle Auto Backup On Autosave"
	set category = "Persistence.Backups & Saves"
	set desc = "Toggles whether every periodic autosave also runs a database backup."

	if(!check_rights(R_SERVER))
		return

	var/new_state = !GLOB.auto_backup_on_autosave

	// world.shelleo() (run_database_backup(), above) is a raw OS shell-out --
	// BYOND refuses that outright under Safe/Ultrasafe security, so an
	// autosave-triggered backup would just silently fail every single time
	// under either of those. Refuse turning it ON here rather than letting
	// an admin enable something that can never actually run -- see
	// _autoBackupSecurityOK()'s own doc comment for the null/Trusted handling.
	if(new_state && !SSpersistence._autoBackupSecurityOK())
		to_chat(usr, SPAN_WARNING("Auto-backup-on-autosave can't be enabled while this server's security level is Safe/Ultrasafe -- it shells out to run the backup script, which BYOND blocks under anything but Trusted. Set the server's security level to Trusted first."))
		return

	var/script_name = GLOB.config.shard_id ? "scripts/central/shard_backup_self.sh" : ((world.system_type == UNIX) ? "scripts/db_backup.sh" : "scripts\\db_backup.bat")
	if(tgui_alert(usr, "Auto-backup-on-autosave is currently [GLOB.auto_backup_on_autosave ? "ON" : "OFF"]. [new_state ? "Enable" : "Disable"] it? When on, every periodic autosave (every 30 minutes) also runs a full database backup ([script_name]).", "Toggle Auto Backup On Autosave", list("Yes", "No")) != "Yes")
		return

	SSpersistence.setAutoBackupOnAutosave(new_state)
	log_and_message_admins("[new_state ? "enabled" : "disabled"] automatic database backups on autosave.", usr)
