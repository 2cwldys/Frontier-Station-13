/*
 * Drydock Ship -- Orion Express Mobile Station
 * Converted from maps/away/ships/orion/orion_express_ship (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/orion_express_ship
	name = "Orion Express Mobile Station"
	id = "orion_express_ship_dd"
	mappath = "maps/drydock_ships/orion_express_ship/orion_express_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/orion/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/orion_express_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/orion_express_ship
	name = "Orion Express Mobile Station"
	class = "OEV"
	desc = "The Traveler-class mobile station is a relatively old design, but nonetheless venerable and one of the building blocks of interstellar commerce. Offers food, supplies, and fuel to anyone who may need it."
	icon = 'icons/obj/overmap/overmap_stationary.dmi'
	icon_state = "waystation"
	moving_state = "waystation"
	colors = list("#a1a8e2", "#818be0")
	scanimage = "oe_platform.png"
	designer = "Orion Express, Refurbished Design"
	volume = "51 meters length, 55 meters beam/width, 29 meters vertical height"
	sizeclass = "Traveler-class Mobile Waystation"
	shiptype = "Refuel, resupply and commercial logistics services"
	drive = "Medium-Speed Warp Acceleration FTL Drive"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/orion_express_ship
	name = "Orion Express Mobile Station (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/orion,
		/area/ship/orion/engie,
		/area/ship/orion/atmos,
		/area/ship/orion/cargo,
		/area/ship/orion/mainhall,
		/area/ship/orion/crew,
		/area/ship/orion/captain,
		/area/ship/orion/bridge,
		/area/ship/orion/comms,
		/area/ship/orion/forehall,
		/area/ship/orion/shop,
		/area/ship/orion/thruster1,
		/area/ship/orion/thruster2,
		/area/ship/orion/docking1,
		/area/ship/orion/docking2,
	)
	current_location = "nav_orion_express_ship_space_dd"
	landmark_transition = "nav_orion_express_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/orion_express_ship
	shuttle_name = "Orion Express Mobile Station (Drydock)"
	landmark_tag = "nav_orion_express_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/orion_express_ship_transit
	name = "In transit"
	landmark_tag = "nav_orion_express_ship_transit_dd"
	base_turf = /turf/space/transit/north
