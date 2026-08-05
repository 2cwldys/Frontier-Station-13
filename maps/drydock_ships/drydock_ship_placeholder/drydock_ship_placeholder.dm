/*
 * Drydock Ship -- Placeholder Hull
 *
 * Minimal proof-of-framework hull, mirroring faction_corvette_placeholder:
 * a small room with the required shuttle_landmark/ship, transit landmark,
 * and shuttle console. Proves the Buy/Retrieve/Stash lifecycle end-to-end.
 * The real multi-deck interior is separate, later content-authorship work
 * -- this hull's code never changes when a real one replaces it, only
 * drydock_ship_placeholder.dmm does.
 */

/datum/map_template/drydock_ship/placeholder
	name = "Placeholder Drydock Ship"
	id = "drydock_ship_placeholder"
	mappath = "maps/drydock_ships/drydock_ship_placeholder/drydock_ship_placeholder.dmm"

	price = 1000000
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/placeholder)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/placeholder
	name = "Placeholder Drydock Ship"
	class = "CIV"
	shuttle = "Placeholder Drydock Ship"
	desc = "A minimal test hull used to prove the drydock ship framework end-to-end."
	icon_state = "shuttle"
	moving_state = "shuttle_moving"
	max_speed = 1/(2 SECONDS)
	burn_delay = 2 SECONDS
	vessel_mass = 5000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/placeholder
	shuttle_tag = "Placeholder Drydock Ship"

/datum/shuttle/autodock/overmap/drydock_ship/placeholder
	name = "Placeholder Drydock Ship"
	move_time = 20
	range = 2
	fuel_consumption = 2
	shuttle_area = list(/area/drydock_ship/placeholder)
	current_location = "nav_drydock_ship_placeholder_space"
	dock_target = "drydock_ship_placeholder"
	landmark_transition = "nav_drydock_ship_placeholder_transit"
	logging_home_tag = "nav_drydock_ship_placeholder_space"

/obj/effect/shuttle_landmark/ship/drydock_ship_placeholder
	shuttle_name = "Placeholder Drydock Ship"
	landmark_tag = "nav_drydock_ship_placeholder_space"

/obj/effect/shuttle_landmark/drydock_ship_placeholder_transit
	name = "In transit"
	landmark_tag = "nav_drydock_ship_placeholder_transit"
	base_turf = /turf/space

/area/drydock_ship/placeholder
	name = "Placeholder Drydock Ship"
