/*
 * Drydock Ship -- Database Freighter
 * Converted from maps/away/ships/pra/database_freighter (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/database_freighter
	name = "Database Freighter"
	id = "database_freighter"
	mappath = "maps/drydock_ships/database_freighter/database_freighter.dmm"
	price = 0
	bridge_area_type = /area/database_freighter/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/database_freighter, /datum/shuttle/autodock/overmap/database_freighter_shuttle)
	sub_shuttle_tags = list("Database Freighter Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/database_freighter
	name = "Database Freighter"
	desc = "Made from adapted designs of the first freighter Tajara ever worked upon, Database freighters are PRA vessels made specially for gathering information on star systems and what passes through them."
	class = "PRAMV"
	shuttle = "Database Freighter (Drydock)"
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#8C8A81")
	vessel_mass = 10000
	max_speed = 1/(2 SECONDS)
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	scanimage = "pra_freighter.png"
	designer = "People's Republic of Adhomai"
	volume = "51 meters length, 28 meters beam/width, 12 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Not apparent, port obscured flight craft bay"
	sizeclass = "Database Freighter"
	shiptype = "Stellar, cosmic study and long-term research missions"

/obj/effect/overmap/visitable/ship/landable/drydock_ship/database_freighter/get_skybox_representation()
	var/image/skybox_image = image('icons/skybox/subcapital_ships.dmi', "pra_freighter")
	skybox_image.pixel_x = rand(0,64)
	skybox_image.pixel_y = rand(128,256)
	return skybox_image

/datum/shuttle/autodock/overmap/drydock_ship/database_freighter
	name = "Database Freighter (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/database_freighter,
		/area/database_freighter/bridge,
		/area/database_freighter/hangar,
		/area/database_freighter/barracks,
		/area/database_freighter/captain_quarters,
		/area/database_freighter/engineering,
		/area/database_freighter/engine,
		/area/database_freighter/storage,
		/area/database_freighter/eva,
		/area/database_freighter/laboratory,
		/area/database_freighter/checkpoint,
	)
	current_location = "nav_database_freighter_space_dd"
	landmark_transition = "nav_database_freighter_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/database_freighter
	shuttle_name = "Database Freighter (Drydock)"
	landmark_tag = "nav_database_freighter_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/database_freighter_transit
	name = "In transit"
	landmark_tag = "nav_database_freighter_transit_dd"
	base_turf = /turf/space/transit/north
