//Runs the command in the system's shell, returns a list of (error code, stdout, stderr)

#define SHELLEO_NAME "data/shelleo."
#define SHELLEO_ERR ".err"
#define SHELLEO_OUT ".out"
/world/proc/shelleo(command)
	var/static/list/shelleo_ids = list()
	var/stdout = ""
	var/stderr = ""
	var/errorcode = 1
	var/shelleo_id
	var/out_file = ""
	var/err_file = ""
	// Windows: wscript (not cmd) so the two shelleo() callers (Trigger
	// Database Backup, Sync Deployment Branch) never flash a console window
	// -- hidden_run.vbs relaunches the same command through its own hidden
	// "cmd /c", preserving the ">"/"2>" redirection appended below exactly
	// as before. See hidden_run.vbs's own header for the full reasoning.
	var/static/list/interpreters = list("[MS_WINDOWS]" = "wscript //nologo //B scripts\\hidden_run.vbs", "[UNIX]" = "sh -c")
	var/interpreter = interpreters["[world.system_type]"]
	if(interpreter)
		for(var/seo_id in shelleo_ids)
			if(!shelleo_ids[seo_id])
				shelleo_ids[seo_id] = TRUE
				shelleo_id = "[seo_id]"
				break
		if(!shelleo_id)
			shelleo_id = "[shelleo_ids.len + 1]"
			shelleo_ids += shelleo_id
			shelleo_ids[shelleo_id] = TRUE
		out_file = "[SHELLEO_NAME][shelleo_id][SHELLEO_OUT]"
		err_file = "[SHELLEO_NAME][shelleo_id][SHELLEO_ERR]"
		if(world.system_type == UNIX)
			errorcode = shell("[interpreter] \"[replacetext(command, "\"", "\\\"")]\" > [out_file] 2> [err_file]")
		else
			errorcode = shell("[interpreter] \"[command]\" > [out_file] 2> [err_file]")
		if(fexists(out_file))
			stdout = file2text(out_file)
			fdel(out_file)
		if(fexists(err_file))
			stderr = file2text(err_file)
			fdel(err_file)
		shelleo_ids[shelleo_id] = FALSE
	else
		CRASH("Operating System: [world.system_type] not supported") // If you encounter this error, you are encouraged to update this proc with support for the new operating system
	. = list(errorcode, stdout, stderr)
#undef SHELLEO_NAME
#undef SHELLEO_ERR
#undef SHELLEO_OUT

/// Prefixes `command` with a `cd`/`cd /d` into GLOB.config.server_root_path
/// when set (no-op otherwise) -- shared by persistence_backups.dm and
/// deploy.dm so this only needs fixing in one place.
///
/// On Windows, the returned command still has to survive being wrapped in
/// ANOTHER `cmd /c "..."` by world.shelleo() itself. A `cd /d "..."` (needed
/// because server_root_path can contain spaces) is its own quoted substring
/// inside that outer pair -- cmd.exe's documented workaround for a `/c`
/// argument containing more than one quoted section requires the *whole*
/// argument to both start AND end with a quote, which held right up until
/// shelleo() started appending output redirection (`> ... 2> ...`) after
/// the closing quote this proc produced, silently breaking the precondition
/// and sending cmd.exe back to its normal (here, wrong) parsing of the
/// nested quotes -- symptom: "The filename, directory name, or volume label
/// syntax is incorrect." Rather than re-deriving the quote arithmetic,
/// sidestep it: write the cd + real command to a small temp .bat file
/// (always a space-free relative path, so it never itself needs quoting)
/// and hand shelleo() a plain, quote-free command to run instead -- with at
/// most shelleo()'s own single outer quote pair in play, there's nothing
/// left to mismanage. Not needed on UNIX -- /bin/sh -c has no such quirk.
///
/// The .bat is also what makes shelleo()'s exit code and captured output
/// actually belong to the command being run -- see the body for why the
/// earlier "run it, then delete it in the same shell command" form reported
/// success for every failure.
/proc/prefix_server_root_cd(command)
	if(!GLOB.config.server_root_path)
		return command
	if(world.system_type == UNIX)
		return "cd \"[GLOB.config.server_root_path]\" && [command]"
	// One fixed filename, cleaned up on the way IN rather than by a trailing
	// `& del` in the shell command itself. That old form had two problems, both
	// of which silently reported success for a failed run:
	//
	//  * `cmd /c "A & B"` exits with **B's** code, not A's -- so errorcode was
	//    always `del`'s (0), never the actual command's, and every failure
	//    looked like a clean backup.
	//  * with `del` as the last statement, the real command's own output was no
	//    longer what the caller was inspecting.
	//
	// Running the .bat as the ONLY statement makes shelleo()'s captured exit
	// code and output genuinely those of the command. `shell()` blocks until
	// the process exits, so no two calls can ever overlap on this filename.
	var/bat_file = "data\\shelleo_cd.bat"
	fdel(bat_file) // leftover from the previous call
	// `call` so control RETURNS here when command is itself a .bat (without it
	// cmd transfers permanently and the exit line below never runs), then
	// propagate that command's real errorlevel as this script's exit code.
	rustg_file_write("@echo off\ncd /d \"[GLOB.config.server_root_path]\"\ncall [command]\nexit /b %errorlevel%\n", bat_file)
	return bat_file

/proc/shell_url_scrub(url)
	var/static/regex/bad_chars_regex = regex("\[^#%&./:=?\\w]*", "g")
	var/scrubbed_url = ""
	var/bad_match = ""
	var/last_good = 1
	var/bad_chars = 1
	do
		bad_chars = bad_chars_regex.Find(url)
		scrubbed_url += copytext(url, last_good, bad_chars)
		if(bad_chars)
			bad_match = url_encode(bad_chars_regex.match)
			scrubbed_url += bad_match
			last_good = bad_chars + length(bad_chars_regex.match)
	while(bad_chars)
	. = scrubbed_url
