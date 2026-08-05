/*
 * Drydock Ship -- TCFL Corvette
 * Converted from maps/away/ships/biesel/tcfl_patrol (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale. This hull has minimal area subdivision in
 * its source (only its own base area is declared) -- shuttle_area and
 * bridge_area_type both fall back to that single area.
 */

/datum/map_template/drydock_ship/tcfl_peacekeeper_ship
	name = "TCFL Corvette"
	id = "tcfl_peacekeeper_ship_dd"
	mappath = "maps/drydock_ships/biesel_tcfl_patrol/tcfl_peacekeeper_ship.dmm"
	price = 1000000
	bridge_area_type = /area/ship/tcfl_peacekeeper_ship
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/tcfl_peacekeeper_ship, /datum/shuttle/autodock/overmap/tcfl_shuttle)
	sub_shuttle_tags = list("TCFL Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/tcfl_peacekeeper_ship
	name = "TCFL Corvette"
	class = "BLV"
	shuttle = "TCFL Corvette (Drydock)"
	desc = "Serving as the very foundation of the SCC's (and more specifically, NanoTrasen's) fleet of asset protection vessels, the Cetus-class is versatile and durable, but also clumsy and somewhat underpowered in regards to its engine and propulsion."
	icon_state = "cetus"
	moving_state = "cetus_moving"
	colors = list("#263aeb", "#3d8cfa")
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	scanimage = "tcfl_cetus.png"
	designer = "NanoTrasen, Stellar Corporate Conglomerate"
	volume = "51 meters length, 42 meters beam/width, 12 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Two extruding wing mounted naval ballistic weapon mounts, aft obscured flight craft bay"
	sizeclass = "Cetus Class Corvette"
	shiptype = "Military patrol and combat utility"

/datum/shuttle/autodock/overmap/drydock_ship/tcfl_peacekeeper_ship
	name = "TCFL Corvette (Drydock)"
	move_time = 25
	range = 2
	fuel_consumption = 3
	shuttle_area = list(/area/ship/tcfl_peacekeeper_ship)
	current_location = "nav_tcfl_peacekeeper_ship_space_dd"
	landmark_transition = "nav_tcfl_peacekeeper_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/tcfl_peacekeeper_ship
	shuttle_name = "TCFL Corvette (Drydock)"
	landmark_tag = "nav_tcfl_peacekeeper_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/tcfl_peacekeeper_ship_transit
	name = "In transit"
	landmark_tag = "nav_tcfl_peacekeeper_ship_transit_dd"
	base_turf = /turf/space/transit/north
