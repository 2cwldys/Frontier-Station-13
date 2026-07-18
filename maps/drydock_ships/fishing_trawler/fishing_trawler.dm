/*
 * Drydock Ship -- Fishing League Trawler
 * Converted from maps/away/ships/hegemony/fishing_trawler (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/fishing_trawler
	name = "Fishing League Trawler"
	id = "fishing_trawler_dd"
	mappath = "maps/drydock_ships/fishing_trawler/fishing_league_trawler.dmm"
	price = 0
	bridge_area_type = /area/ship/fishing_trawler/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/fishing_trawler, /datum/shuttle/autodock/overmap/fishing_trawler)
	sub_shuttle_tags = list("Fishing League Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/fishing_trawler
	name = "Fishing League Trawler"
	class = "IHGV"
	shuttle = "Fishing League Trawler (Drydock)"
	desc = "The Azkrazal-class freighter is a common civilian design from the Izweski Hegemony's shipbuilding guilds, augmented with sharpened pylons designed to harvest carp shoals."
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#F06553")
	designer = "Hephaestus Industries, Izweski Hegemonic Naval Guilds"
	volume = "54 meters length, 54 meters beam/width, 18 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Not apparent, fore of ship shows extensive catwalk and lattice network designed for piercing carp"
	sizeclass = "Azkrazal-class cargo freighter"
	shiptype = "Long-term shipping utilities"
	scanimage = "unathi_freighter2.png"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/fishing_trawler
	name = "Fishing League Trawler (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/fishing_trawler,
		/area/ship/fishing_trawler/bridge,
		/area/ship/fishing_trawler/EVA_port,
		/area/ship/fishing_trawler/EVA_starboard,
		/area/ship/fishing_trawler/Captain,
		/area/ship/fishing_trawler/crew_quarters,
		/area/ship/fishing_trawler/kitchen,
		/area/ship/fishing_trawler/galley,
		/area/ship/fishing_trawler/medical,
		/area/ship/fishing_trawler/freezer,
		/area/ship/fishing_trawler/engineering,
		/area/ship/fishing_trawler/engineering/port,
		/area/ship/fishing_trawler/engineering/Starboard,
		/area/ship/fishing_trawler/corridor,
		/area/ship/fishing_trawler/corridor/central,
		/area/ship/fishing_trawler/corridor/port,
		/area/ship/fishing_trawler/corridor/starboard,
		/area/ship/fishing/trawler/fishing_catwalk,
	)
	current_location = "nav_fishing_trawler_space_dd"
	landmark_transition = "nav_fishing_trawler_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/fishing_trawler
	shuttle_name = "Fishing League Trawler (Drydock)"
	landmark_tag = "nav_fishing_trawler_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/fishing_trawler_transit
	name = "In transit"
	landmark_tag = "nav_fishing_trawler_transit_dd"
	base_turf = /turf/space/transit/north
