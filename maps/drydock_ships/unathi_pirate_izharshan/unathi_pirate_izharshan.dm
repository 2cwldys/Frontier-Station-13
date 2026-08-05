/*
 * Drydock Ship -- Izharshan Freighter
 * Converted from maps/away/ships/unathi_pirate/izharshan (Bucket A, already
 * a fully flyable/dockable away-site craft) -- see lone_spacer.dm for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/unathi_pirate_izharshan
	name = "Izharshan Shuttle"
	id = "unathi_pirate_izharshan"
	mappath = "maps/drydock_ships/unathi_pirate_izharshan/unathi_pirate_izharshan.dmm"
	price = 1000000
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/unathi_pirate_izharshan)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/unathi_pirate_izharshan
	name = "Izharshan freighter (Landable)"
	class = "ISV"
	shuttle = "Izharshan Freighter (Drydock)"
	designation = "Anvil"
	desc = "Though the sensors identify the engine signature and overall rough profile of the signal as being from an older Hegemonic Brick-class civilian freight shuttle, many modifications are detected, such as possible anti-ship weaponry onboard."
	icon_state = "generic"
	moving_state = "generic_moving"
	colors = list("#95de9c")
	scanimage = "unathi_freighter1.png"
	max_speed = 1/(2 SECONDS)
	burn_delay = 2 SECONDS
	vessel_mass = 7500
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH
	comms_name = "modified"

/obj/effect/overmap/visitable/ship/landable/drydock_ship/unathi_pirate_izharshan/get_skybox_representation()
	var/image/skybox_image = image('icons/skybox/subcapital_ships.dmi', "unathi_freighter1")
	skybox_image.pixel_x = rand(0,64)
	skybox_image.pixel_y = rand(128,256)
	return skybox_image

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/unathi_pirate_izharshan
	shuttle_tag = "Izharshan Freighter (Drydock)"

/datum/shuttle/autodock/overmap/drydock_ship/unathi_pirate_izharshan
	name = "Izharshan Freighter (Drydock)"
	move_time = 35
	range = 2
	fuel_consumption = 6
	shuttle_area = list(/area/shuttle/unathi_pirate_izharshan/operations, /area/shuttle/unathi_pirate_izharshan/dorms, /area/shuttle/unathi_pirate_izharshan/helm)
	current_location = "nav_izharshan_space_dd"
	dock_target = "unathi_pirate_izharshan"
	landmark_transition = "nav_izharshan_transit_dd"
	logging_home_tag = "nav_izharshan_space_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/unathi_pirate_izharshan
	shuttle_name = "Izharshan Freighter (Drydock)"
	landmark_tag = "nav_izharshan_space_dd"

/obj/effect/shuttle_landmark/drydock_ship/izharshan_transit
	name = "In transit"
	landmark_tag = "nav_izharshan_transit_dd"
	base_turf = /turf/space
