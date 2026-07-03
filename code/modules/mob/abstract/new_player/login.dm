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

	// Open the Character Select UI first so it isn't competing with the lobby
	// music download for the same connection right at first impression --
	// music starts a moment later, once the UI has already had a head start.
	show_persistent_menu()
	addtimer(CALLBACK(client, /client/proc/playtitlemusic), 1 SECOND)

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
	if(!persistent_menu_datum || QDELETED(persistent_menu_datum))
		persistent_menu_datum = new /datum/persistent_menu(src)
	persistent_menu_datum.ui_interact(src)
