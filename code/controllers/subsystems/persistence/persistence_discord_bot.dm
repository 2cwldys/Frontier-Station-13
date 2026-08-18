/*
 * Persistence - Discord Status Bot Lifecycle
 *
 * Starts scripts/discord_status_bot.py with the server and stops it when the
 * server genuinely closes. Everything here is gated behind
 * DISCORD_STATUS_BOT_AUTOSTART (_compile_options.dm) -- undefined by default,
 * in which case none of it compiles and the bot is started by hand as before.
 *
 * The one thing that would break the server if got wrong: world.shelleo()
 * BLOCKS the entire game world until the command it ran returns (see
 * trigger_deployment_sync(), deploy.dm). The bot runs forever, so shelling out
 * to it directly would hang the world at startup, permanently. Both procs
 * below therefore call a *_bg-style wrapper (scripts/discord_bot_start.*)
 * whose whole job is to background the real process and return immediately --
 * the same arrangement deploy_bg.bat/.sh already uses for compiles.
 */

#ifdef DISCORD_STATUS_BOT_AUTOSTART

/// TRUE if this instance can actually run world.shelleo() right now.
///
/// Identical reasoning and identical null handling to _autoBackupSecurityOK()
/// (persistence_backups.dm) and trigger_deployment_sync() (deploy.dm): BYOND
/// refuses raw shell-outs under Safe/Ultrasafe, and a null security level
/// means TGS is absent entirely (a bare local server), which is treated as
/// Trusted because nothing is imposing a restriction in that case.
/datum/controller/subsystem/persistence/proc/_discordBotSecurityOK()
	var/current_security = world.TgsSecurityLevel()
	return isnull(current_security) || current_security == TGS_SECURITY_TRUSTED

/// Shared command builder for the two wrappers. Backslashes on Windows for the
/// same reason run_database_backup() uses them -- cmd.exe reads a leading
/// "scripts/..." as a command plus switches rather than a path -- and wrapped
/// in prefix_server_root_cd() because DreamDaemon's OS cwd is not guaranteed
/// to be the repo root (see GLOB.config.server_root_path, configuration.dm).
///
/// script_name is a fixed literal from the callers below, never built from
/// user input, so there is no injection surface here.
/datum/controller/subsystem/persistence/proc/_discordBotCommand(script_name)
	var/command = (world.system_type == UNIX) \
		? "scripts/[script_name].sh" \
		: "scripts\\[script_name].bat"
	return prefix_server_root_cd(command)

/// Launches the status bot. Called from Initialize().
///
/// The wrapper kills any previously-recorded bot before starting a new one, so
/// this also cleans up an orphan left behind by a DreamDaemon that died
/// without ever reaching Shutdown().
/datum/controller/subsystem/persistence/proc/discordStatusBotStart()
	if(!_discordBotSecurityOK())
		log_subsystem_persistence_warning("Discord bot: not starting -- server security level is Safe/Ultrasafe, which blocks the shell-out. Set it to Trusted to enable.")
		return FALSE

	var/list/result = world.shelleo(_discordBotCommand("discord_bot_start"))
	var/errorcode = result[1]
	if(errorcode)
		// Exit 1 is the wrapper's own "no config file" refusal, which is a
		// normal state on a server that never set the bot up -- report it as
		// information rather than as a failure needing attention.
		log_subsystem_persistence_info("Discord bot: not started (exit [errorcode]). [result[2]][result[3]]")
		return FALSE

	log_subsystem_persistence_info("Discord bot: launch requested.")
	return TRUE

/// Stops the status bot. Called from Shutdown(), but ONLY when the process is
/// genuinely ending -- see GLOB.world_shutdown_is_hard. A soft round reboot
/// runs Shutdown() too, and killing the bot there would drop and rebuild its
/// Discord connection every single round for no reason.
/datum/controller/subsystem/persistence/proc/discordStatusBotStop()
	if(!GLOB.world_shutdown_is_hard)
		return FALSE
	if(!_discordBotSecurityOK())
		return FALSE

	var/list/result = world.shelleo(_discordBotCommand("discord_bot_stop"))
	// The wrapper exits 0 whether it killed something or found nothing to
	// kill, so a non-zero here means the wrapper itself failed to run.
	if(result[1])
		log_subsystem_persistence_warning("Discord bot: stop script failed (exit [result[1]]): [result[3]]")
		return FALSE
	log_subsystem_persistence_info("Discord bot: stop requested.")
	return TRUE

#endif
