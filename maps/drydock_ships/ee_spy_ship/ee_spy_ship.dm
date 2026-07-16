/*
 * Drydock Ship -- Einstein Engines Research Ship
 * Converted from maps/away/ships/einstein/ee_spy_ship.dmm (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/ee_spy_ship
	name = "Einstein Engines Research Ship"
	id = "ee_spy_ship_dd"
	mappath = "maps/drydock_ships/ee_spy_ship/ee_spy_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/ee_spy_ship
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/ee_spy_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/ee_spy_ship
	name = "Einstein Engines Research Ship"
	class = "EERV"
	desc = "A research ship belonging to Einstein Engines, the Stellar Corporate Conglomerate's main competitor."
	icon_state = "light_cruiser"
	moving_state = "light_cruiser_moving"
	colors = list("#18e9b5", "#6aa9dd")
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/ee_spy_ship
	name = "Einstein Engines Research Ship (Drydock)"
	move_time = 25
	range = 2
	fuel_consumption = 3
	shuttle_area = list(/area/ship/ee_spy_ship)
	current_location = "nav_ee_spy_ship_space_dd"
	landmark_transition = "nav_ee_spy_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/ee_spy_ship
	shuttle_name = "Einstein Engines Research Ship (Drydock)"
	landmark_tag = "nav_ee_spy_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/ee_spy_ship_transit
	name = "In transit"
	landmark_tag = "nav_ee_spy_ship_transit_dd"
	base_turf = /turf/space/transit/north
