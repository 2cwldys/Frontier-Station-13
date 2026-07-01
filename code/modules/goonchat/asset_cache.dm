// Goonchat asset registration — ported from Serenity

/datum/asset/group/goonchat
	children = list(
		/datum/asset/simple/jquery_goonchat,
		/datum/asset/simple/goonchat,
		/datum/asset/simple/fontawesome_goonchat
	)

/datum/asset/simple/jquery_goonchat
	assets = list(
		"jquery.min.js" = 'code/modules/goonchat/browserassets/js/jquery.min.js',
	)

/datum/asset/simple/goonchat
	assets = list(
		"json2.min.js"            = 'code/modules/goonchat/browserassets/js/json2.min.js',
		"browserOutput.js"        = 'code/modules/goonchat/browserassets/js/browserOutput.js',
		"browserOutput.css"       = 'code/modules/goonchat/browserassets/css/browserOutput.css',
		"browserOutput_white.css" = 'code/modules/goonchat/browserassets/css/browserOutput_white.css',
		"chatbg.png"              = 'icons/misc/chatbg.png',
		"tchatshadow.png"         = 'icons/misc/tchatshadow.png',
	)

/datum/asset/simple/fontawesome_goonchat
	assets = list(
		"fa-regular-400.ttf" = 'html/font-awesome/webfonts/fa-regular-400.ttf',
		"fa-solid-900.ttf"   = 'html/font-awesome/webfonts/fa-solid-900.ttf',
		"font-awesome.css"   = 'html/font-awesome/css/all.min.css',
		"v4shim.css"         = 'html/font-awesome/css/v4-shims.min.css',
	)
