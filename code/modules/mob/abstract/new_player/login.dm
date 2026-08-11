/mob/abstract/new_player
	var/datum/persistent_menu/persistent_menu_datum

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

	// Open the Character Select UI first so it isn't competing with the lobby
	// music download for the same connection right at first impression --
	// music starts a moment later, once the UI has already had a head start.
	show_persistent_menu()
	addtimer(CALLBACK(client, /client/proc/playtitlemusic), 1 SECOND)
	// Own channel (CHANNEL_ANNOUNCER via play_announcer_sound()) from the
	// lobby music's CHANNEL_LOBBYMUSIC, so the two don't collide -- same
	// 1-second deferral as the music above, for the same reason (let the
	// Character Select UI's own asset download get a head start first).
	addtimer(CALLBACK(src, PROC_REF(_play_welcome_line)), 1 SECOND)

/**
 * Plays a one-time lobby-connect welcome voice line -- WELCOME_TO_FRONTIER_STATION
 * by default, or WELCOME_BACK for a ckey that's certifiably spawned a
 * character at least once before (SQL COUNT against ss13_characters'
 * first_spawned_at column, the same "has this character actually been
 * played" signal new_player.dm's own starter-PDA grant already uses --
 * only under WELCOME_BACK_VOICE_LINES; leave that undefined to always play
 * the plain welcome line with no DB query at all. Gated the same way every
 * other play_announcer_sound() call site gates itself (ASFX_ANNOUNCER,
 * client.prefs already loaded by LateLogin() -- InitPrefs() runs before it
 * in client/New()).
 */
/mob/abstract/new_player/proc/_play_welcome_line()
	if(!client || !client.prefs)
		return
	if(!(client.prefs.sfx_toggles & ASFX_ANNOUNCER))
		return

	var/line = 'sound/AI/announcements/welcome_to_frontier_station.ogg'

#ifdef WELCOME_BACK_VOICE_LINES
	if(GLOB.config.sql_saves && SSdbcore.Connect())
		var/datum/db_query/query = SSdbcore.NewQuery(
			"SELECT COUNT(*) FROM ss13_characters WHERE ckey = :ckey AND first_spawned_at IS NOT NULL",
			list("ckey" = client.ckey))
		query.Execute()
		if(query.NextRow())
			if((text2num(query.item[1]) || 0) > 0)
				line = 'sound/AI/announcements/welcome_back.ogg'
		qdel(query)
#endif

	play_announcer_sound(src, line)

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
