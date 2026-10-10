// Goonchat asset registration — ported from Serenity

/datum/asset/group/goonchat
	children = list(
		/datum/asset/simple/jquery_goonchat,
		/datum/asset/simple/goonchat,
		/datum/asset/simple/fontawesome_goonchat
#if GOONCHAT_CUSTOM_FONT != GOONCHAT_FONT_NONE
		, /datum/asset/simple/goonchat_font
#endif
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
		"cursor.cur"              = 'code/modules/goonchat/browserassets/css/cursor.cur',
	)

/datum/asset/simple/fontawesome_goonchat
	assets = list(
		"fa-regular-400.ttf" = 'html/font-awesome/webfonts/fa-regular-400.ttf',
		"fa-solid-900.ttf"   = 'html/font-awesome/webfonts/fa-solid-900.ttf',
		"font-awesome.css"   = 'html/font-awesome/css/all.min.css',
		"v4shim.css"         = 'html/font-awesome/css/v4-shims.min.css',
	)

#if GOONCHAT_CUSTOM_FONT == GOONCHAT_FONT_INDUSTRIA_SOLID
/datum/asset/simple/goonchat_font
	assets = list(
		"IndustriaSolid-Regular.otf" = 'code/modules/goonchat/browserassets/fonts/IndustriaSolid-Regular.otf',
	)
#elif GOONCHAT_CUSTOM_FONT == GOONCHAT_FONT_DEX_GOTHIC
/datum/asset/simple/goonchat_font
	assets = list(
		"DexGothicBeckerSolid-Regular.ttf" = 'code/modules/goonchat/browserassets/fonts/DexGothicBeckerSolid-Regular.ttf',
	)
#elif GOONCHAT_CUSTOM_FONT == GOONCHAT_FONT_HANDEL_GOTHIC
/datum/asset/simple/goonchat_font
	assets = list(
		"HandelGothic-Regular.ttf" = 'code/modules/goonchat/browserassets/fonts/HandelGothic-Regular.ttf',
	)
#endif
