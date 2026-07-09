/datum/asset/simple/tgui
	// keep_local_name previously TRUE -- that serves these bundles under a
	// permanently fixed filename, which BYOND's client-side resource cache
	// treats as stable and never re-downloads, even across full client
	// restarts. Switching to the default hash-named scheme means every
	// rebuild gets a new filename and can never be served stale.
	assets = list(
		"tgui.bundle.js" = file("tgui/public/tgui.bundle.js"),
		"tgui.bundle.css" = file("tgui/public/tgui.bundle.css"),
	)

/datum/asset/simple/tgui_panel
	assets = list(
		"tgui-panel.bundle.js" = file("tgui/public/tgui-panel.bundle.js"),
		"tgui-panel.bundle.css" = file("tgui/public/tgui-panel.bundle.css"),
	)
