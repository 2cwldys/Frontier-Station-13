/** Assigned say modal of the client */
/client/var/datum/tgui_say/tgui_say

/**
 * Creates a JSON encoded message to open TGUI say modals properly.
 *
 * Arguments:
 * channel - The channel to open the modal in.
 * Returns:
 * string - A JSON encoded message to open the modal.
 */
/client/proc/tgui_say_create_open_command(channel)
	var/message = TGUI_CREATE_OPEN_MESSAGE(channel)
	return "\".output tgui_say.browser:update [message]\""

/**
 * The tgui say modal. This initializes an input window which hides until
 * the user presses one of the speech hotkeys. Once something is entered, it will
 * delegate the speech to the proper channel.
 */
/datum/tgui_say
	/// The user who opened the window
	var/client/client
	/// Injury phrases to blurt out
	var/list/hurt_phrases = list("-")
	/// Max message length
	var/max_length = MAX_MESSAGE_LEN
	/// The modal window
	var/datum/tgui_window/window
	/// Boolean for whether the tgui_say was opened by the user.
	var/window_open
	/// Last computed dock winset params ("pos=..;size=..") -- lets open()
	/// snap the window instantly with zero winget round-trips while the
	/// full recompute catches up.
	var/last_dock

/** Creates the new input window to exist in the background. */
/datum/tgui_say/New(client/client, id)
	src.client = client
	window = new(client, id)
	winset(client, "tgui_say", "size=1,1;is-visible=0;")
	window.subscribe(src, PROC_REF(on_message))
	window.is_browser = TRUE

/**
 * After a brief period, injects the scripts into
 * the window to listen for open commands.
 */
/datum/tgui_say/proc/initialize()
	set waitfor = FALSE
	// Sleep to defer initialization to after client constructor
	sleep(3 SECONDS)
	window.initialize(
			strict_mode = TRUE,
			inline_css = file("tgui/public/tgui-say.bundle.css"),
			inline_js = file("tgui/public/tgui-say.bundle.js"),
	);

/**
 * Ensures nothing funny is going on window load.
 * Minimizes the window, sets max length, closes all
 * typing and thinking indicators. This is triggered
 * as soon as the window sends the "ready" message.
 */
/datum/tgui_say/proc/load()
	window_open = FALSE

	winset(client, "tgui_say", "is-visible=0;")
	// Pre-position while hidden: the T macro shows the window client-side
	// INSTANTLY at its last position, but a dock computed at open() needs
	// several winget round-trips first (the visible ~2s jump). Docking at
	// window-ready means the first open is already in place.
	dock_to_input()

	window.send_message("props", list(
		"lightMode" = client?.prefs.tgui_say_light_mode,
		"scale" = client?.prefs.ui_scale,
		"maxLength" = max_length,
	))

	stop_thinking()
	return TRUE

/**
 * Sets the window as "opened" server side, though it is already
 * visible to the user. We do this to set local vars &
 * start typing (if enabled and in an IC channel). Logs the event.
 *
 * Arguments:
 * payload - A list containing the channel the window was opened in.
 */
/datum/tgui_say/proc/open(payload)
	if(!payload?["channel"])
		CRASH("No channel provided to an open TGUI-Say")
	window_open = TRUE
	// Instant snap from cache (zero round-trips), then recompute in case
	// the window/splitter changed since -- the recompute self-corrects.
	if(last_dock)
		winset(client, "tgui_say", last_dock)
	dock_to_input()
	if(payload["channel"] != OOC_CHANNEL)
		start_thinking()
	return TRUE

/// winget() single-value fetch tolerant of both raw ("883,10") and keyed
/// ("mainwindow.pos=883,10") return forms.
/proc/winget_value(client/C, control, param)
	var/raw = winget(C, control, param)
	if(!findtext(raw, "="))
		return raw
	var/list/parsed = params2list(raw)
	for(var/key in parsed)
		if(findtext("[key]", param))
			return parsed[key]
	return null

/**
 * Positions the say window over the blue input box at the bottom of the
 * chat column, per player, at every open.
 *
 * The catch this solves: a MAXIMIZED main window reports its RESTORED
 * bounds through winget (e.g. the dmf default 640x440), so naive pos/size
 * math lands nowhere. Detect maximization and use the client's live
 * screen-size instead (per-player monitor truth); windowed pos/size are
 * accurate as-is. The chat column's left edge comes from the LIVE
 * mainwindow.split splitter percentage (tracks the user's own dragging).
 */
/datum/tgui_say/proc/dock_to_input()
	var/win_x = 0
	var/win_y = 0
	var/win_w = 0
	var/win_h = 0
	if(winget_value(client, "mainwindow", "is-maximized") == "true")
		var/list/scr = splittext(winget_value(client, null, "screen-size"), "x")
		if(length(scr) < 2)
			return
		win_w = text2num(scr[1])
		win_h = text2num(scr[2]) - 40 // taskbar allowance
	else
		var/list/p = splittext(winget_value(client, "mainwindow", "pos"), ",")
		var/list/s = splittext(winget_value(client, "mainwindow", "size"), "x")
		if(length(p) < 2 || length(s) < 2)
			return
		win_x = text2num(p[1])
		win_y = text2num(p[2])
		win_w = text2num(s[1])
		win_h = text2num(s[2])
	if(!win_w || !win_h)
		return
	// Left edge of the chat column = the map|UI splitter position.
	var/split_pct = text2num(winget_value(client, "mainwindow.split", "splitter")) || 60
	var/col_x = win_x + round(win_w * split_pct / 100)
	var/col_w = win_w - round(win_w * split_pct / 100)
	// The input element spans the left 80% of the bottom row
	// (input_buttons_child splitter = 80); the buttons take the rest.
	var/say_w = max(200, round(col_w * 0.8))
	var/say_x = col_x
	// +6 (not -26): the computed window bottom sits ~30px above the true
	// client-area bottom (titlebar height isn't reflected in the maximized
	// geometry) -- this constant absorbs that delta. Eyeball-tuned.
	var/say_y = win_y + win_h + 6
	last_dock = "pos=[say_x],[say_y];size=[say_w]x30"
	winset(client, "tgui_say", last_dock)

/**
 * Closes the window serverside. Closes any open chat bubbles
 * regardless of preference. Logs the event.
 */
/datum/tgui_say/proc/close()
	window_open = FALSE
	stop_thinking()

/**
 * The equivalent of ui_act, this waits on messages from the window
 * and delegates actions.
 */
/datum/tgui_say/proc/on_message(type, payload)
	if(type == "ready")
		load()
		return TRUE
	if (type == "open")
		open(payload)
		return TRUE
	if (type == "close")
		close()
		return TRUE
	if (type == "thinking")
		if(payload["mode"] == TRUE)
			start_thinking()
			return TRUE
		if(payload["mode"] == FALSE)
			stop_thinking()
			return TRUE
		return FALSE
	if (type == "typing")
		start_typing()
		return TRUE
	if (type == "entry" || type == "force")
		handle_entry(type, payload)
		return TRUE
	return FALSE
