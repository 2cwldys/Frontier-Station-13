//Runs the command in the system's shell, returns a list of (error code, stdout, stderr)

#define SHELLEO_NAME "data/shelleo."
#define SHELLEO_ERR ".err"
#define SHELLEO_OUT ".out"
/world/proc/shelleo(command)
	var/stdout = ""
	var/stderr = ""
	var/errorcode = 1
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
		// Ever-incrementing, GLOB.round_id-qualified -- never a reused small
		// integer pool. That reused-slot scheme (shelleo_ids, a free-list of
		// "1", "2", ...) is what let a call that never returned (a child
		// process wedged on an interactive prompt with no console to answer
		// it, holding its "> out_file" handle open forever) permanently
		// contaminate the SAME filename for every future boot, since a fresh
		// DreamDaemon process's own pool always starts back at "1" too.
		// CONFIRMED live: a "Trigger Database Backup" run read back a Discord
		// bot launch's stdout -- including its "Press any key to continue"
		// prompt -- from a zombie cmd.exe that had been sitting on
		// data/shelleo.1.out since a boot hours earlier. Same fix already
		// applied to the wrapper .bat filenames in prefix_server_root_cd();
		// this is the sibling naming scheme that was missed. These are tiny
		// (~100 byte) scratch files, so never reusing a name is not a real
		// disk-space concern -- scripts/cleanup_shelleo_zombies.ps1 sweeps
		// leftovers if it ever is.
		var/static/shelleo_counter = 0
		shelleo_counter++
		var/shelleo_id = "[GLOB.round_id]_[shelleo_counter]"
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
	// A never-repeating filename, not a reused fixed name or a small rotating
	// pool of them (both tried before, both wrong). CONFIRMED live, not
	// theoretical: with an 8-slot rotating pool, a database backup's call
	// landed on the same slot number a Discord-bot-start call had just used,
	// and read back the Discord bot's own leftover output as if it were the
	// backup's -- fdel()/rustg_file_write()'s return values are never
	// checked, so a write that silently fails to actually overwrite a reused
	// slot leaves its previous, completely unrelated content in place for
	// shelleo() to dutifully execute. Any reused name -- one fixed name or a
	// handful cycled through -- has this same failure mode; it's just a
	// matter of how often it collides. A name that is NEVER reused for the
	// life of the process has no stale prior content to ever fall back to:
	// if the write fails, shelleo() gets "file not found" and fails cleanly,
	// instead of silently running a stranger's command.
	//
	// These are tiny (~100 bytes) plaintext files, so never deleting the old
	// ones is not a real disk-space concern for how long a server actually
	// runs between restarts.
	//
	// The counter alone is NOT enough, and getting that wrong broke every
	// shelled command on this server: it is a per-process static, so it resets
	// to 0 on every restart and boot N+1 reuses boot N's filenames. With the
	// fdel() below also removed, a write that failed to overwrite the existing
	// file left the PREVIOUS BOOT's command sitting there to be run instead.
	// Confirmed from disk, not theory: data\shelleo_cd_1.bat still carried an
	// 01:56 mtime during an 05:52 boot -- the write had silently done nothing
	// for hours. GLOB.round_id is regenerated per boot, so including it makes
	// the name unique across restarts as well as within one.
	var/static/bat_counter = 0
	bat_counter++
	var/bat_file = "data\\shelleo_cd_[GLOB.round_id]_[bat_counter].bat"
	// Restored from the pre-rewrite version. Belt and braces next to the
	// unique name above: if a file somehow does exist, it is gone before the
	// write rather than a candidate for silently surviving it.
	fdel(bat_file)
	// `call` so control RETURNS here when command is itself a .bat (without it
	// cmd transfers permanently and the exit line below never runs), then
	// propagate that command's real errorlevel as this script's exit code.
	rustg_file_write("@echo off\ncd /d \"[GLOB.config.server_root_path]\"\ncall [command]\nexit /b %errorlevel%\n", bat_file)
	// rustg_file_write()'s return value is not trustworthy enough to gate on,
	// so confirm the file is actually THERE. Without this a failed write is
	// invisible: shelleo() runs a nonexistent .bat, cmd returns 1 with no
	// output at all, and the caller reports a bare "exit 1" that looks like
	// the command itself failed -- which is exactly how this presented, as
	// "Backup failed (exit code 1):" with nothing after the colon.
	if(!fexists(bat_file))
		log_world("ERROR: prefix_server_root_cd() could not write [bat_file] -- shelling out [command] would fail with a bare exit 1. Running it without the cd prefix instead.")
		return command
	// Hand back an ABSOLUTE path, not the relative one the file was written
	// with. BYOND's file APIs resolve relative to the WORLD directory, so
	// rustg_file_write() above put the file exactly where intended -- but the
	// cmd.exe that eventually runs it resolves relative paths against
	// DreamDaemon's OS working directory, and those two being different is the
	// entire reason server_root_path and this proc exist. Returning a relative
	// path meant this helper handed back something that only resolved if the
	// cwd was already what it was written to correct.
	//
	// A wrapper cmd cannot find produces precisely the reported signature:
	// exit 1, no stdout, no stderr. Verified the other way round too -- run
	// with a correct cwd, the identical chain exits 0 and writes a real backup.
	//
	// Backslashes throughout: this is a Windows-only branch, and mixing
	// separators in a path that gets quoted and re-parsed by cmd is not worth
	// the risk.
	var/root_windows = replacetext(GLOB.config.server_root_path, "/", "\\")
	return "[root_windows]\\[bat_file]"

/// Deletes every leftover shelleo()/prefix_server_root_cd() scratch file --
/// data/shelleo.<id>.out, data/shelleo.<id>.err, data/shelleo_cd_<id>.bat --
/// from data/. Called from SSpersistence's Initialize() and Shutdown()
/// (persistence.dm), NOT periodically and NOT tied to any single shelleo()
/// call's own completion.
///
/// That timing matters: both callers generate a NEVER-repeating name for the
/// live duration of a session specifically because shell()'s return does not
/// guarantee every descendant process is actually gone (a wrapper stuck on
/// an interactive prompt, or the Discord bot's deliberately-detached
/// grandchild) -- reusing/overwriting a name on that signal is what caused a
/// confirmed, hours-long production corruption once already (see the header
/// comments on shelleo()/prefix_server_root_cd() above). Sweeping at
/// Initialize() is safe because nothing THIS session could still be using
/// exists yet -- every match found there is unconditionally a leftover from
/// before this boot. Sweeping again at Shutdown() (hard shutdowns only,
/// gated by the caller) leaves a clean slate for whichever boot comes next,
/// rather than making every boot the only place cleanup ever happens.
/proc/sweep_shelleo_scratch_files()
	var/swept = 0
	for(var/filename in flist("data/"))
		if(copytext(filename, 1, 8) != "shelleo")
			continue
		var/extension = copytext(filename, -4)
		if(extension != ".out" && extension != ".err" && extension != ".bat")
			continue
		fdel("data/[filename]")
		swept++
	if(swept)
		log_world("sweep_shelleo_scratch_files: removed [swept] leftover shelleo scratch file\s.")

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
