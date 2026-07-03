/*********************************
For the main html chat area
*********************************/

//Precaching a bunch of shit
GLOBAL_DATUM_INIT(iconCache, /savefile, new("tmp/iconCache.sav")) //Cache of icons for the browser output

//Should match the value set in the browser js
#define MAX_COOKIE_LENGTH 5
#define SPAM_TRIGGER_AUTOMUTE 10

//On client, created on login
/datum/chatOutput
	var/client/owner	 //client ref
	// How many times client data has been checked
	var/total_checks = 0
	// When to next clear the client data checks counter
	var/next_time_to_clear = 0
	var/loaded       = FALSE // Has the client loaded the browser output area?
	var/list/messageQueue //If they haven't loaded chat, this is where messages will go until they do
	var/cookieSent   = FALSE // Has the client sent a cookie for analysis
	var/broken       = FALSE
	var/list/connectionHistory //Contains the connection history passed from chat cookie
	var/loading_fallback_timer_id // Cancelled if the real JS doneLoading() ack arrives first
	var/degraded     = FALSE // Set TRUE only when the fallback timer had to force completion

/datum/chatOutput/New(client/C)
	owner = C
	messageQueue = list()
	connectionHistory = list()

/datum/chatOutput/proc/start()
	if(!owner)
		return FALSE
	// Skip winexists() check — Aurora's skin always has the window; just load directly
	load()
	return TRUE

/datum/chatOutput/proc/load()
	set waitfor = FALSE
	if(!owner)
		return

	// Send all assets via browse_rsc so the browser can find them by filename
	owner << browse_rsc(file('code/modules/goonchat/browserassets/js/jquery.min.js'), "jquery.min.js")
	owner << browse_rsc(file('code/modules/goonchat/browserassets/js/json2.min.js'), "json2.min.js")
	owner << browse_rsc(file('code/modules/goonchat/browserassets/js/browserOutput.js'), "browserOutput.js")
	owner << browse_rsc(file('code/modules/goonchat/browserassets/css/browserOutput.css'), "browserOutput.css")
	owner << browse_rsc(file('code/modules/goonchat/browserassets/css/browserOutput_white.css'), "browserOutput_white.css")
	owner << browse_rsc(file('icons/misc/chatbg.png'), "chatbg.png")
	owner << browse_rsc(file('code/modules/goonchat/browserassets/html/tchatshadow.png'), "tchatshadow.png")
	owner << browse_rsc(file('code/modules/goonchat/browserassets/css/cursor.cur'), "cursor.cur")

	// Wait for genuine confirmation the assets above actually arrived and were
	// cached by the client's embedded browser control before loading HTML that
	// references them by filename. Queuing browse_rsc() then browse()ing
	// immediately after does NOT guarantee that -- issue-order on the
	// connection isn't the same as "already received and cached locally,"
	// especially under resource contention (this was the leading suspect for
	// clients ending up with broken/half-loaded chat requiring a restart:
	// the HTML's <script>/<link> tags would resolve against a local cache
	// that hadn't finished catching up yet). browse_queue_flush() is the same
	// primitive the generic asset-cache transport already uses for exactly
	// this guarantee (asset_transport.dm's send_assets_slow()).
	owner.browse_queue_flush()

	// tgui_panel targets the SAME physical "browseroutput" window/pane as we
	// do (see /datum/tgui_panel/New -> window = new(client, "browseroutput")).
	// A fixed sleep here to "go after tgui_panel" is a guess that can lose the
	// race under load, letting tgui_panel's later browse() silently overwrite
	// our HTML after it already rendered ("loaded, then unloaded itself").
	// So: paint immediately for the fast-path case, AND let tgui_panel's own
	// ready-handler (on_message() in tgui_panel.dm, which fires only once its
	// init has genuinely finished) re-assert us afterward as the guaranteed
	// final write -- see assert_chat_html().
	assert_chat_html()

/// (Re)browses the goonchat HTML into the shared "browseroutput" pane and
/// arms the load-completion fallback. Safe to call more than once: called
/// once immediately from load() for the fast path, and again from
/// tgui_panel's on_message() "ready" handler once its own init is confirmed
/// done, so goonchat's content is guaranteed to be the last thing written to
/// the shared pane regardless of which side's init was slower.
/datum/chatOutput/proc/assert_chat_html()
	if(!owner)
		return

	if(loaded)
		log_world("goonchat: [key_name(owner)] re-asserting chat HTML after an earlier successful load (tgui_panel likely just wrote over the shared pane).")

	owner << browse(file('code/modules/goonchat/browserassets/html/browserOutput.html'), "window=browseroutput")
	showChat()

	// A re-assert after an earlier successful load means something (tgui_panel)
	// just overwrote us -- treat it as a fresh load so the real doneLoading()
	// ack drives completion again instead of leaving loaded stuck TRUE against
	// a pane that was just replaced out from under it.
	loaded = FALSE

	// The JS sends a real doneLoading() ack once it has actually finished
	// rendering (browserOutput.js ~line 1173) -- that's what should drain the
	// message queue, not an optimistic guess made right after browse(). Under
	// resource contention (slow asset downloads, etc.) the browser control can
	// still be mid-render here. Only a fallback timer forces completion, in
	// case the ack genuinely never arrives.
	loading_fallback_timer_id = addtimer(CALLBACK(src, PROC_REF(loading_fallback)), 8 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE | TIMER_STOPPABLE)

/datum/chatOutput/Topic(href, list/href_list)
	if(usr.client != owner)
		return TRUE

	// Build arguments.
	// Arguments are in the form "param[paramname]=thing"
	var/list/params = list()
	for(var/key in href_list)
		if(length(key) > 7 && findtext(key, "param")) // 7 is the amount of characters in the basic param key template.
			var/param_name = copytext(key, 7, -1)
			var/item       = href_list[key]

			params[param_name] = item

	var/data // Data to be sent back to the chat.
	switch(href_list["proc"])
		if("doneLoading")
			data = doneLoading(arglist(params))

		if("debug")
			data = debug(arglist(params))

		if("ping")
			data = ping(arglist(params))

		if("analyzeClientData")
			data = analyzeClientData(arglist(params))

		if("swaptodarkmode")
			swaptodarkmode()

		if("swaptolightmode")
			swaptolightmode()

	if(data)
		ehjax_send(data = data)


//Called on chat output done-loading by JS.
/datum/chatOutput/proc/doneLoading()
	if(loaded)
		return
	if(loading_fallback_timer_id)
		deltimer(loading_fallback_timer_id)
		loading_fallback_timer_id = null

	loaded = TRUE
	showChat()

	for(var/message in messageQueue)
		// whitespace has already been handled by the original to_chat
		to_chat(owner, message, handle_whitespace=FALSE)

	messageQueue = null
	sendClientData()

	syncRegex()

	if(degraded)
		log_world("goonchat: [key_name(owner)] hit the loading_fallback() timeout (no real doneLoading() ack arrived in time) -- degraded to old chat.")
		//do not convert to to_chat()
		legacy_chat(owner, "<span class=\"userdanger\">Failed to load fancy chat, reverting to old chat. Certain features won't work.</span>")
	else
		log_world("goonchat: [key_name(owner)] loaded successfully (real doneLoading() ack).")

	pingLoop()

/// Safety net only -- fires if the JS never sent its real doneLoading() ack
/// within a reasonable window, so chat can't get stuck forever waiting on it.
/datum/chatOutput/proc/loading_fallback()
	loading_fallback_timer_id = null
	if(loaded)
		return
	degraded = TRUE
	doneLoading()

/datum/chatOutput/proc/showChat()
	// Swap to output_browser pane (where our HTML now lives) — same winset tgui_panel uses
	winset(owner, "output_selector.legacy_output_selector", "left=output_browser")

/datum/chatOutput/proc/pingLoop()
	set waitfor = FALSE

	while (owner)
		ehjax_send(data = owner.is_afk(29) ? "softPang" : "pang") // SoftPang isn't handled anywhere but it'll always reset the opts.lastPang.
		sleep(30)

/proc/syncChatRegexes()
	for (var/user in GLOB.clients)
		var/client/C = user
		var/datum/chatOutput/Cchat = C.chatOutput
		if (Cchat && !Cchat.broken && Cchat.loaded)
			Cchat.syncRegex()

/datum/chatOutput/proc/syncRegex()
	var/list/regexes = list()

	if (regexes.len)
		ehjax_send(data = list("syncRegex" = regexes))

/datum/chatOutput/proc/ehjax_send(client/C = owner, window = "browseroutput", data)
	if(islist(data))
		data = json_encode(data)
	send_output(C, "[data]", "[window]:ehjaxCallback")

//Sends client connection details to the chat to handle and save
/datum/chatOutput/proc/sendClientData()
	//Get dem deets
	var/list/deets = list("clientData" = list())
	deets["clientData"]["ckey"] = owner.ckey
	deets["clientData"]["ip"] = owner.address
	deets["clientData"]["compid"] = owner.computer_id
	var/data = json_encode(deets)
	ehjax_send(data = data)

//Called by client, sent data to investigate (cookie history so far)
/datum/chatOutput/proc/analyzeClientData(cookie = "")
	//Spam check
	if(world.time  >  next_time_to_clear)
		next_time_to_clear = world.time + (3 SECONDS)
		total_checks = 0

	total_checks += 1

	if(total_checks > SPAM_TRIGGER_AUTOMUTE)
		message_admins("[key_name(owner)] kicked for goonchat topic spam")
		qdel(owner)
		return

	if(!cookie)
		return

	if(cookie != "none")
		var/list/connData = json_decode(cookie)
		if (connData && islist(connData) && connData.len > 0 && connData["connData"])
			connectionHistory = connData["connData"] //lol fuck
			var/list/found = new()

			if(connectionHistory.len > MAX_COOKIE_LENGTH)
				message_admins("[key_name(src.owner)] was kicked for an invalid ban cookie)")
				qdel(owner)
				return

			for(var/i in connectionHistory.len to 1 step -1)
				if(QDELETED(owner))
					//he got cleaned up before we were done
					return
				var/list/row = src.connectionHistory[i]
				if (!row || row.len < 3 || (!row["ckey"] || !row["compid"] || !row["ip"])) //Passed malformed history object
					return
				if (world.IsBanned(row["ckey"], row["ip"], row["compid"]))
					found = row
					break
				CHECK_TICK

			//Uh oh this fucker has a history of playing on a banned account!!
			if (found.len > 0)
				var/msg = "[key_name(src.owner)] has a cookie from a banned account! (Matched: [found["ckey"]], [found["ip"]], [found["compid"]])"
				//TODO: add a new evasion ban for the CURRENT client details, using the matched row details
				message_admins(msg)
				log_admin(msg)

	cookieSent = TRUE

//Called by js client every 60 seconds
/datum/chatOutput/proc/ping()
	return "pong"

//Called by js client on js error
/datum/chatOutput/proc/debug(error)
	log_world("\[[time2text(world.realtime, "YYYY-MM-DD hh:mm:ss")]\] Client: [(src.owner.key ? src.owner.key : src.owner)] triggered JS error: [error]")

// to_chat_immediate is defined in Aurora's tgchat module; goonchat routes through it
/proc/goonchat_send_immediate(target, message, handle_whitespace = TRUE, trailing_newline = TRUE)
	if(!target || !message)
		return

	if(target == world)
		target = GLOB.clients

	var/original_message = message
	if(handle_whitespace)
		message = replacetext(message, "\n", "<br>")
		message = replacetext(message, "\t", "[FOURSPACES][FOURSPACES]")

	//Replace expanded \icon macro with icon2html
	//regex/Replace with a proc won't work here because icon2html takes target as an argument and there is no way to pass it to the replacement proc
	//not even hacks with reassigning usr work
	var/static/regex/i = new(@/<IMG CLASS=icon SRC=(\[[^]]+])(?: ICONSTATE='([^']+)')?>/, "g")
	while(i.Find(message))
		message = copytext(message,1,i.index)+icon2html(locate(i.group[1]), target, icon_state=i.group[2])+copytext(message,i.next)
	/*
	message = \
		symbols_to_unicode(
			cyrillic_to_unicode(
				cp1251_to_utf8(
					strip_improper(
						color_macro_to_html(
							message
						)
					)
				)
			)
		)
	*/
	if(trailing_newline)
		message += "<br>"
	if(islist(target))
		// Do the double-encoding outside the loop to save nanoseconds
		var/twiceEncoded = url_encode(url_encode(message))
		for(var/I in target)
			var/client/C = CLIENT_FROM_VAR(I) //Grab us a client if possible
			if (!C)
				continue
			//Send it to the old style output window.
			legacy_chat(C, original_message)
			if(!C.chatOutput || C.chatOutput.broken) // A player who hasn't updated his skin file.
				continue

			if(!C.chatOutput.loaded)
				//Client still loading, put their messages in a queue
				C.chatOutput.messageQueue += message
				continue

			send_output(C, twiceEncoded, "browseroutput:output")
	else
		var/client/C = CLIENT_FROM_VAR(target) //Grab us a client if possible

		if (!C)
			return

		//Send it to the old style output window.
		legacy_chat(C, original_message)

		if(!C.chatOutput || C.chatOutput.broken) // A player who hasn't updated his skin file.
			return

		if(!C.chatOutput.loaded)
			//Client still loading, put their messages in a queue
			C.chatOutput.messageQueue += message
			return

		// url_encode it TWICE, this way any UTF-8 characters are able to be decoded by the Javascript.
		send_output(C, url_encode(url_encode(message)), "browseroutput:output")

/datum/chatOutput/proc/swaptolightmode()
	return // theme switching not implemented in this port

/*
/client/verb/switch_dark_mode()
	set name = "Switch to Dark Mode"
	set category = "OOC"

	var/client/owner
	owner.force_dark_theme()

/client/verb/switch_white_mode()
	set name = "Switch to White Mode"
	set category = "OOC"

	var/client/owner
	owner.force_white_theme()
*/

/datum/chatOutput/proc/swaptodarkmode()
	return // theme switching not implemented in this port

// to_chat is defined in Aurora's tgchat module; see to_chat.dm for goonchat routing

#undef MAX_COOKIE_LENGTH
