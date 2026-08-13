/// Set the first time LateLogin() (below) handles the welcome line/music
/// for this client -- lives on /client, not the new_player mob, so it
/// survives a mob returning to character select mid-connection (cryo) and
/// actually gates this to once per real connection.
/client/var/welcomed_this_connection = FALSE

/mob/abstract/new_player
	var/datum/persistent_menu/persistent_menu_datum
	/// Resolved by _resolve_welcome_line(), fired immediately from
	/// LateLogin() rather than deferred, so its DB lookup has the full
	/// 1-second head start to finish before _play_welcome_line() actually
	/// plays it -- see both procs below.
	var/welcome_line = 'sound/AI/announcements/welcome_to_frontier_station.ogg'

/mob/abstract/new_player/LateLogin()
	..()

	update_Login_details()	//handles setting lastKnownIP and computer_id for use by the ban systems as well as checking for multikeying

	if(!mind)
		mind = new /datum/mind(key)
		mind.active = 1
		mind.current = src

	set_sight(BLIND)
	GLOB.player_list |= src

	if(GLOB.motd)
		to_chat(src, "<div class=\"motd\">[GLOB.motd]</div>")
	to_chat(src, "<div class='info'>Game ID: </div><div class='danger'>[GLOB.round_id]</div>")

#ifdef SHOW_GIT_LOG
	var/commit_url = SSgithub.get_commit_url()
	if(commit_url)
		to_chat(src, MATRIX_NOTICE("Running commit <a href='[commit_url]'>[copytext(GLOB.revdata.revision, 1, 8)]</a>"))
#endif

	// Open the Character Select UI first so it isn't competing with the
	// welcome line's own download for the same connection right at first
	// impression -- the welcome line starts a moment later, once the UI has
	// already had a head start, and the lobby music is chained to start
	// only once the welcome line has actually finished (see
	// _play_welcome_line()) instead of racing it.
	show_persistent_menu()
	// LateLogin() fires again every time this client's mob becomes a FRESH
	// /mob/abstract/new_player instance -- not just on the true first
	// connect, but also e.g. returning to character select after cryo-ing
	// mid-round. welcomed_this_connection (a /client var, so it survives
	// that mob churn) makes this genuinely once-per-connection, matching
	// what the rest of this system already assumes.
	if(client && !client.welcomed_this_connection)
		client.welcomed_this_connection = TRUE
		// INVOKE_ASYNC, not a direct call -- _resolve_welcome_line() calls
		// SSdbcore.Connect() first, which has no yield point of its own
		// (one straight-line native call). A direct call, even with
		// waitfor=FALSE on the callee, still runs synchronously up to ITS
		// OWN first yield -- so without this, a slow/unreachable DB blocks
		// LateLogin(), and with it the entire single-threaded world, for
		// however long that connection attempt takes. INVOKE_ASYNC hands
		// control back here immediately regardless.
		INVOKE_ASYNC(src, PROC_REF(_resolve_welcome_line))
		addtimer(CALLBACK(src, PROC_REF(_play_welcome_line)), 1 SECOND)
	else if(client)
		// Not the true first connection -- the welcome voice line already
		// played once and must stay that way, but lobby music itself has to
		// restart every time a client actually reaches the lobby (returning
		// via cryo/store-character, an AFK/prison force-store, or a failed
		// spawn all recreate this mob and re-enter LateLogin()). Without this
		// branch the music silently never plays again for the rest of the
		// connection, since it otherwise only ever starts chained off the
		// one-time welcome line above. playtitlemusic() (sound.dm) is safe to
		// call again any time -- it clears CHANNEL_LOBBYMUSIC before queuing
		// a freshly-shuffled playlist.
		client.playtitlemusic()

/**
 * Resolves welcome_line ahead of _play_welcome_line() actually playing it --
 * WELCOME_TO_FRONTIER_STATION by default, or WELCOME_BACK for a ckey that's
 * certifiably spawned a character at least once before (SQL COUNT against
 * ss13_characters' first_spawned_at column, the same "has this character
 * actually been played" signal new_player.dm's own starter-PDA grant already
 * uses) -- only under WELCOME_BACK_VOICE_LINES; leave that undefined to
 * always play the plain welcome line with no DB query at all.
 */
/mob/abstract/new_player/proc/_resolve_welcome_line()
	set waitfor = FALSE
	if(!client)
		return
#ifdef WELCOME_BACK_VOICE_LINES
	if(GLOB.config.sql_saves && SSdbcore.Connect())
		var/datum/db_query/query = SSdbcore.NewQuery(
			"SELECT COUNT(*) FROM ss13_characters WHERE ckey = :ckey AND first_spawned_at IS NOT NULL",
			list("ckey" = client.ckey))
		query.Execute()
		if(query.NextRow())
			if((text2num(query.item[1]) || 0) > 0)
				welcome_line = 'sound/AI/announcements/welcome_back.ogg'
		qdel(query)
#endif

/**
 * Plays the one-time lobby-connect welcome voice line welcome_line already
 * resolved to, then chains the lobby music to start right as it finishes --
 * GLOB.announcer_sound_durations (_announcer_sound_durations.dm) is the
 * same known-length table play_announcer_sound() itself already consumes
 * for its own per-client queue, so this doesn't invent a second source of
 * truth for how long the line runs. Gated the same way every other
 * play_announcer_sound() call site gates itself (ASFX_ANNOUNCER,
 * client.prefs already loaded by LateLogin() -- InitPrefs() runs before it
 * in client/New()) -- if no line is going to play at all (sound disabled),
 * the music starts immediately instead of waiting on nothing.
 */
/mob/abstract/new_player/proc/_play_welcome_line()
	if(!client)
		return
	if(client.prefs && (client.prefs.sfx_toggles & ASFX_ANNOUNCER))
		play_announcer_sound(src, welcome_line)
		// "[welcome_line]" -- welcome_line is a file (sound resource)
		// value; the list is keyed by plain strings, same coercion
		// play_announcer_sound() itself uses for this identical lookup
		// (announce.dm). Without it this always misses and silently falls
		// back to the 2-second default below, regardless of which line
		// actually played.
		addtimer(CALLBACK(client, /client/proc/playtitlemusic), GLOB.announcer_sound_durations["[welcome_line]"] || 2 SECONDS)
	else
		client.playtitlemusic()

/// A spawn attempt aborted after PersistentAutoSpawn() closed the menu and
/// flagged spawning -- reset and give the menu back so the player isn't stranded.
/mob/abstract/new_player/proc/reopen_menu_after_failed_spawn()
	if(persistent_menu_datum)
		persistent_menu_datum.spawning = FALSE
	show_persistent_menu()

/mob/abstract/new_player/proc/show_persistent_menu()
	set waitfor = FALSE
	if(!client) return
	// Wait for goonchat's real doneLoading() ack (browserOutput.dm) before
	// showing Character Select, when goonchat is enabled -- bounded by its
	// own loading_fallback() timer (~8s) so a client that never acks still
	// gets in. This also means the menu can no longer open while chat is
	// still being contested between goonchat and tgui_panel's shared pane
	// (see the race fix in tgui_panel.dm/browserOutput.dm), removing one
	// more source of goonchat intermittently failing to load.
	UNTIL(!GLOB.config.goonchat || client?.chatOutput?.loaded)
	if(!client) return // client may have disconnected during the wait
	// A stale reopen-timer (scheduled by ui_close() while spawning was still
	// FALSE) can fire after the player has since clicked Play on the current
	// menu datum -- without this check the menu reopens right on top of an
	// in-progress or just-completed spawn, since client only goes null once
	// the key transfer to the spawned character actually completes.
	if(persistent_menu_datum && persistent_menu_datum.spawning)
		return
	if(!persistent_menu_datum || QDELETED(persistent_menu_datum))
		persistent_menu_datum = new /datum/persistent_menu(src)
	persistent_menu_datum.ui_interact(src)
