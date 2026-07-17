/*
 * Drydock Ship -- Tarwa Conglomerate Ship
 * Converted from maps/away/ships/unathi_pirate/tarwa/unathi_pirate_tarwa.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/tarwa
	name = "Tarwa Conglomerate Ship"
	id = "tarwa_conglomerate"
	mappath = "maps/drydock_ships/unathi_tarwa/unathi_pirate_tarwa.dmm"
	price = 0
	bridge_area_type = /area/tarwa_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/tarwa)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/tarwa
	name = "Tarwa Conglomerate Ship"
	desc = "An Azkrazal-class cargo freighter. Scans indicate it is heavily damaged, and that there appears to be some form of organic growth on the exterior hull."
	class = "ICV"
	shuttle = "Tarwa Conglomerate Ship (Drydock)"
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#c2c1ac", "#1b7325")
	scanimage = "unathi_diona_freighter.png"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	designer = "Izweski Hegemony Naval Guilds, Hephaestus Industries"
	volume = "65 meters length, 35 meters beam/width, 18 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual wingtip-mounted heavy ballistic, port obscured flight craft bay"
	sizeclass = "Modified Azkrazal-class cargo freighter"
	shiptype = "Unknown"

/datum/shuttle/autodock/overmap/drydock_ship/tarwa
	name = "Tarwa Conglomerate Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/tarwa_ship,
		/area/tarwa_ship/hangar,
		/area/tarwa_ship/gun,
		/area/tarwa_ship/engineering1,
		/area/tarwa_ship/engineering2,
		/area/tarwa_ship/captain,
		/area/tarwa_ship/crew,
		/area/tarwa_ship/diona,
		/area/tarwa_ship/armory,
		/area/tarwa_ship/oldhangar,
		/area/tarwa_ship/cic,
		/area/tarwa_ship/bridge,
		/area/tarwa_ship/medical,
		/area/tarwa_ship/eva,
		/area/tarwa_ship/canteen,
	)
	current_location = "nav_tarwa_space_dd"
	landmark_transition = "nav_tarwa_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/tarwa
	shuttle_name = "Tarwa Conglomerate Ship (Drydock)"
	landmark_tag = "nav_tarwa_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/tarwa_transit
	name = "In transit"
	landmark_tag = "nav_tarwa_transit_dd"
	base_turf = /turf/space/transit/north
