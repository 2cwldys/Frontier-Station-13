/*
 * Persistence - Minimum Client Build
 *
 * Runtime control over the minimum BYOND *build* (the 1687 of 516.1687) a
 * client is allowed to connect with. The gate itself lives in
 * client_procs.dm; this file is only the storage and the admin verb.
 *
 * Why this exists at all: config.txt is read exactly once, by
 * /datum/configuration/proc/load() from world/New(), and there is no config
 * reload anywhere in the codebase. So MIN_CLIENT_BUILD alone would mean a
 * server restart every time the number needed to move -- which is precisely
 * the wrong property for a setting whose whole purpose is reacting quickly to
 * a bad client build. The value here overrides config and can be changed on a
 * live server with no restart and no recompile.
 *
 * Layering, resolved in _resolve_min_client_build() (client_procs.dm):
 *   GLOB.min_client_build_override (this file, DB)  -- wins when non-zero
 *   GLOB.config.min_client_build   (config.txt)     -- fallback
 *   0                                               -- gate disabled
 *
 * Shape copied from the auto-backup toggle (persistence_backups.dm:85-131),
 * which is the established pattern here for a one-row admin-managed setting.
 */

/// Loads the minimum client build override from ss13_min_client_build at boot.
/// Mirrors autoBackupToggleInitialize() (persistence_backups.dm).
/datum/controller/subsystem/persistence/proc/minClientBuildInitialize()
	if(!databaseCheckConnection("minClientBuildInitialize"))
		return
	try
		var/datum/db_query/q = SSdbcore.NewQuery("SELECT build FROM ss13_min_client_build WHERE id = 1", list())
		q.Execute()
		if(databaseCheckQueryResult(q, "minClientBuildInitialize") && q.NextRow())
			GLOB.min_client_build_override = text2num(q.item[1])
		qdel(q)
	catch(var/exception/min_build_e)
		log_subsystem_persistence_error("MinClientBuild: failed to load minimum client build override: [min_build_e]")

	if(GLOB.min_client_build_override)
		log_subsystem_persistence_info("MinClientBuild: override active -- clients below build [GLOB.min_client_build_override] are refused (config value [GLOB.config.min_client_build] ignored).")

/// Stores a new minimum client build override. 0 clears the override, which
/// falls back to config.txt's MIN_CLIENT_BUILD rather than disabling the gate
/// outright -- see the layering note at the top of this file.
/datum/controller/subsystem/persistence/proc/setMinClientBuild(build)
	build = max(0, round(text2num("[build]") || 0))
	GLOB.min_client_build_override = build
	if(!databaseCheckConnection("setMinClientBuild"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"INSERT INTO ss13_min_client_build (id, build) VALUES (1, :build) ON DUPLICATE KEY UPDATE build = VALUES(build)",
		list("build" = build)
	)
	q.Execute()
	databaseCheckQueryResult(q, "setMinClientBuild")
	qdel(q)

/// Admin control: the minimum BYOND build a client may connect with. Takes
/// effect on the very next connection attempt -- no restart, no recompile --
/// and persists across restarts via ss13_min_client_build (setMinClientBuild()).
/datum/admins/proc/set_min_client_build()
	set name = "Set Minimum Client Build"
	set category = "Server"
	set desc = "Sets the minimum BYOND build (e.g. 1687) required to connect. 0 falls back to config.txt."

	if(!check_rights(R_SERVER))
		return

	var/config_build = GLOB.config.min_client_build
	var/current = GLOB.min_client_build_override
	var/effective = current || config_build

	var/prompt = "Minimum BYOND build required to connect, e.g. 1687 for 516.1687.\n\n"
	prompt += "Currently enforcing: [effective ? "build [effective]" : "nothing -- the gate is off"].\n"
	prompt += current \
		? "This is a database override; config.txt's value ([config_build ? config_build : "unset"]) is being ignored.\n" \
		: "This is config.txt's value; no database override is set.\n"
	prompt += "\nEnter 0 to clear the override and fall back to config.txt."

	var/new_build = tgui_input_number(usr, prompt, "Minimum Client Build", effective, 9999, 0)
	if(isnull(new_build))
		return

	new_build = round(new_build)
	// Admins are exempt from the gate (client_procs.dm), so a typo here can't
	// lock staff out -- but it can absolutely lock out every player, so make
	// the destructive-looking case an explicit confirmation rather than a
	// silent success.
	if(new_build > 0 && new_build > world.byond_build)
		if(tgui_alert(usr, "Build [new_build] is NEWER than the build this server itself is running ([world.byond_build]). That will refuse essentially every player. Set it anyway?", "Minimum Client Build", list("Set Anyway", "Cancel")) != "Set Anyway")
			return

	SSpersistence.setMinClientBuild(new_build)

	if(new_build)
		log_and_message_admins("set the minimum client build to [new_build] -- clients below 516.[new_build] will be refused.")
	else
		log_and_message_admins("cleared the minimum client build override -- config.txt's value ([config_build ? config_build : "unset"]) now applies.")
