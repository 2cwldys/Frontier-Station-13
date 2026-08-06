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

/datum/admins/proc/trigger_database_backup()
	set name = "Trigger Database Backup"
	set category = "Persistence"
	set desc = "Runs scripts/db_backup now and reports the result."

	if(!check_rights(R_SERVER))
		return

	to_chat(usr, SPAN_NOTICE("Running database backup..."))

	// Fixed literal chosen only by world.system_type -- never built from admin- or
	// player-supplied text, so there is no injection surface here.
	var/command = (world.system_type == UNIX) ? "scripts/db_backup.sh" : "scripts/db_backup.bat"
	var/list/result = world.shelleo(command)
	var/errorcode = result[1]
	var/stdout = result[2]
	var/stderr = result[3]

	// db_backup.ps1 Write-Error's "Backup failed..." on a non-zero mysqldump exit
	// but the wrapping .bat/.sh can still exit 0 -- check the text too, not just
	// the process exit code.
	if(errorcode || findtext(stdout, "Backup failed"))
		to_chat(usr, SPAN_WARNING("Backup failed (exit code [errorcode]):"))
		to_chat(usr, SPAN_WARNING(stderr || stdout || "No output captured."))
		log_and_message_admins("ran a database backup -- FAILED (exit [errorcode])", usr)
		return

	to_chat(usr, SPAN_GOOD("Backup complete:"))
	to_chat(usr, stdout)
	log_and_message_admins("ran a manual database backup", usr)
