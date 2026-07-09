/datum/map/voidwork
	name = "Voidwork"
	full_name = "Voidwork Construction Sector"
	path = "voidwork"

	traits = list(
		//Z1
		list(ZTRAIT_STATION = TRUE, ZTRAIT_UP = TRUE, ZTRAIT_DOWN = FALSE),
		//Z2
		list(ZTRAIT_STATION = TRUE, ZTRAIT_UP = TRUE, ZTRAIT_DOWN = TRUE),
		//Z3
		list(ZTRAIT_STATION = TRUE, ZTRAIT_UP = FALSE, ZTRAIT_DOWN = TRUE),
	)

	force_spawnpoint = TRUE

	lobby_icons = list('icons/misc/titlescreens/runtime/developers.dmi', 'icons/misc/titlescreens/runtime/away.dmi')
	lobby_transitions = FALSE

	contact_levels = list(1, 2, 3)
	player_levels = list(1, 2, 3)
	accessible_z_levels = list(1, 2, 3)

	overmap_event_areas = 10

	station_name = "Voidwork Sector"
	station_short = "Voidwork"
	dock_name = "void anchor"
	boss_name = "Sector Oversight"
	boss_short = "Oversight"
	company_name = "Independent"
	company_short = "IND"
	station_type = "construction sector"

	use_overmap = TRUE
	overmap_size = 35

	shuttle_docked_message = "Attention all hands: Jump preparation complete. The bluespace drive is now spooling up, secure all stations for departure. Time to jump: approximately %ETA%."
	shuttle_leaving_dock = "Attention all hands: Jump initiated, exiting bluespace in %ETA%."
	shuttle_called_message = "Attention all hands: Jump sequence initiated. Transit procedures are now in effect. Jump in %ETA%."
	shuttle_recall_message = "Attention all hands: Jump sequence aborted, return to normal operating conditions."

	overmap_visitable_type = /obj/effect/overmap/visitable/ship/voidwork

	evac_controller_type = /datum/evacuation_controller/starship

	station_networks = list(
		NETWORK_CIVILIAN_MAIN,
		NETWORK_COMMAND,
		NETWORK_ENGINEERING,
	)

	num_exoplanets = 0
	away_site_budget = 0
	away_ship_budget = 0
