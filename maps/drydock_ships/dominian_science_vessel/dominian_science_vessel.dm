/*
 * Drydock Ship -- Dominian Science Vessel
 * Converted from maps/away/ships/dominia/dominian_science_vessel (Bucket B)
 * -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/dominian_science_vessel
	name = "Dominian Science Vessel"
	id = "dominian_science_vessel_dd"
	mappath = "maps/drydock_ships/dominian_science_vessel/dominian_science_vessel.dmm"
	price = 0
	bridge_area_type = /area/ship/dominian_science_vessel/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/dominian_science_vessel, /datum/shuttle/autodock/overmap/dominian_science_shuttle)
	sub_shuttle_tags = list("Dominian Science Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/dominian_science_vessel
	name = "Dominian Science Vessel"
	class = "HVS"
	shuttle = "Dominian Science Vessel (Drydock)"
	desc = "Based on the Lammergeier-class corvette, this vessel has been repurposed by House Volvalaad for long range survey and scientific tasks. Due to its repurposement, the vessel features an enlarged hangar and shuttle, as well as scientific labs and a smaller defensive armament."
	icon_state = "lammergeier"
	moving_state = "lammergeier_moving"
	colors = list("#df1032", "#d4296b")
	designer = "Zhurong Naval Arsenal, Empire of Dominia"
	volume = "36 meters length, 67 meters beam/width, 18 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Single wingtip-mounted extruding medium-caliber ballistic armament, aft obscured flight craft bay"
	sizeclass = "Explorer-class Science Vessel"
	shiptype = "Survey and scientific research"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/dominian_science_vessel
	name = "Dominian Science Vessel (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/dominian_science_vessel,
		/area/ship/dominian_science_vessel/hangar,
		/area/ship/dominian_science_vessel/infirmary,
		/area/ship/dominian_science_vessel/quarters,
		/area/ship/dominian_science_vessel/bridge,
		/area/ship/dominian_science_vessel/officer,
		/area/ship/dominian_science_vessel/armory,
		/area/ship/dominian_science_vessel/cryo,
		/area/ship/dominian_science_vessel/engineering,
		/area/ship/dominian_science_vessel/port_propulsion,
		/area/ship/dominian_science_vessel/aft_dock,
		/area/ship/dominian_science_vessel/exterior,
		/area/ship/dominian_science_vessel/eva,
		/area/ship/dominian_science_vessel/mess,
		/area/ship/dominian_science_vessel/research,
		/area/ship/dominian_science_vessel/atmospherics,
		/area/ship/dominian_science_vessel/port_hall,
		/area/ship/dominian_science_vessel/starboard_hall,
		/area/ship/dominian_science_vessel/showers,
		/area/ship/dominian_science_vessel/center_hall,
		/area/ship/dominian_science_vessel/chapel,
		/area/ship/dominian_science_vessel/isolation,
	)
	current_location = "nav_dominian_science_vessel_space_dd"
	landmark_transition = "nav_dominian_science_vessel_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/dominian_science_vessel
	shuttle_name = "Dominian Science Vessel (Drydock)"
	landmark_tag = "nav_dominian_science_vessel_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/dominian_science_vessel_transit
	name = "In transit"
	landmark_tag = "nav_dominian_science_vessel_transit_dd"
	base_turf = /turf/space/transit/north
