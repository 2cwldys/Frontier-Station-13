#define DEPLOY_WATCH_TIMEOUT (10 MINUTES)
#define DEPLOY_WATCH_INTERVAL (5 SECONDS)

/**
 * Pulls and compiles the deployment branch in the background (scripts/deploy.sh
 * on Linux, scripts/deploy.ps1 on Windows), so a fresh build is ready by the
 * next server restart. Does not restart DreamDaemon itself -- see docs/deployment.md.
 *
 * Two ways this fires:
 * - Manually, via the "Sync Deployment Branch" R_SERVER admin verb below
 *   (triggered_by = the admin who ran it).
 * - Automatically, via SSgithub (code/controllers/subsystems/github.dm)
 *   the moment a PR merges into the configured deployment branch, but only
 *   when FORCE_COMPILE_ON_MERGE is defined (code/_compile_options.dm) --
 *   off by default, so the manual verb is the only way unless explicitly
 *   opted into (triggered_by = null for this path).
 *
 * Backgrounds the actual git pull + compile at the OS level (deploy_bg.sh/.bat)
 * rather than waiting on it: world.shelleo() blocks the entire game world
 * for however long the shelled-out command takes, and a full recompile can
 * take minutes -- backgrounding means this call only blocks for the trivial
 * time it takes to launch the background process. _watch_deploy_completion()
 * then polls scripts/deploy.log for that same run's outcome so a second,
 * separate announcement can fire once the compile actually finishes.
 */
/proc/trigger_deployment_sync(mob/triggered_by)
	// Backslashes on Windows for the same reason trigger_database_backup()
	// uses them (persistence_backups.dm) -- cmd.exe reads a leading
	// "scripts/..." as a command plus switches, not a path.
	var/command = (world.system_type == UNIX) ? "scripts/deploy_bg.sh" : "scripts\\deploy_bg.bat"
	// See the identical guard in trigger_database_backup() (persistence_backups.dm)
	// and GLOB.config.server_root_path's doc comment (configuration.dm) -- same
	// relative-command-vs-DD's-OS-cwd fragility, same fix.
	command = prefix_server_root_cd(command)
	var/list/result = world.shelleo(command)
	var/errorcode = result[1]

	if(errorcode != 0)
		if(triggered_by)
			to_chat(triggered_by, SPAN_WARNING("Failed to launch the deploy script (exit [errorcode]): [result[3]]"))
		else
			message_admins(SPAN_WARNING("Automatic deployment sync failed to launch (exit [errorcode]): [result[3]]"))
		return FALSE

	if(triggered_by)
		to_world(FONT_LARGE(SPAN_NOTICE("An admin is compiling up to the latest commit on the deployment branch, effective next boot.")))
		log_and_message_admins("triggered a deployment sync ([key_name(triggered_by)]).")
	else
		to_world(FONT_LARGE(SPAN_NOTICE("A merge to the deployment branch was detected -- compiling automatically, effective next boot.")))
		message_admins(SPAN_NOTICE("Automatic deployment sync triggered by a merge to the deployment branch."))

	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(_watch_deploy_completion))
	return TRUE

/client/proc/sync_deployment_branch()
	set category = "Server"
	set name = "Sync Deployment Branch"
	set desc = "Pulls and compiles the latest deployment-branch changes in the background, ready for the next restart."

	if(!check_rights(R_SERVER))
		return

	trigger_deployment_sync(usr)

/// Polls scripts/deploy.log for the outcome of the run that was just
/// triggered (scoped to lines after that run's own "started" header, so a
/// stale line from an earlier run can't be mistaken for this one), and
/// announces once deploy.sh/deploy.ps1 actually finishes.
/proc/_watch_deploy_completion()
	set waitfor = FALSE

	var/deadline = world.time + DEPLOY_WATCH_TIMEOUT
	while(world.time < deadline)
		sleep(DEPLOY_WATCH_INTERVAL)

		if(!fexists("scripts/deploy.log"))
			continue

		var/list/lines = splittext(rustg_file_read("scripts/deploy.log"), "\n")
		var/start_index = 0
		for(var/i = length(lines), i >= 1, i--)
			if(findtext(lines[i], "=== deploy.sh started") || findtext(lines[i], "=== deploy.ps1 started"))
				start_index = i
				break
		if(!start_index)
			continue

		for(var/i = start_index, i <= length(lines), i++)
			if(findtext(lines[i], "Compile succeeded"))
				to_world(FONT_LARGE(SPAN_GOOD("Deployment sync complete.")))
				return
			if(findtext(lines[i], "Compile FAILED"))
				message_admins(SPAN_WARNING("Deployment sync failed -- check scripts/deploy.log."))
				return
			if(findtext(lines[i], "Already compiled"))
				return

#undef DEPLOY_WATCH_TIMEOUT
#undef DEPLOY_WATCH_INTERVAL
