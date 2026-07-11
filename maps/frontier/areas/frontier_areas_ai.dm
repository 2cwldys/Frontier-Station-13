/*
	/// Only used for the Frontier, and mostly for mapping checks.
	var/horizon_deck = null
	/// Only used for the Frontier, and mostly for mapping checks.
	var/department = null
	/// Only used for the Frontier, and mostly for mapping checks.
	var/subdepartment = null
*/

/area/frontier/ai
	name = "AI Area (PARENT AREA - DON'T USE)"
	icon_state = "ai_chamber"
	ambience = AMBIENCE_AI
	area_lighting = LIGHT_HIGHSEC_COLORS
	horizon_deck = 3
	department = LOC_AI
	area_flags = AREA_FLAG_RAD_SHIELDED | AREA_FLAG_HIDE_FROM_HOLOMAP
	area_blurb = "Ticking, beeping, and buzzing. Great tides of invisible signal traffic across the electromagnetic spectrum, flowing in both directions. Otherwise, the silence and stillness of a tomb."

/area/frontier/ai/chamber
	name = "AI Chamber"

/area/frontier/ai/upload
	name = "AI Upload Chamber"
	icon_state = "ai_upload"

/area/frontier/ai/upload_foyer
	name = "AI Upload Access"
	icon_state = "ai_foyer"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
