/*
 * Drydock Ship -- Air Konyang Transport
 * Converted from maps/away/ships/konyang/air_konyang (Bucket A, already a
 * fully flyable/dockable away-site craft) -- see lone_spacer.dm for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/air_konyang
	name = "Air Konyang Transport"
	id = "air_konyang"
	mappath = "maps/drydock_ships/air_konyang/air_konyang.dmm"
	price = 0
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/air_konyang)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/air_konyang
	name = "Air Konyang Transport (Landable)"
	class = "AKPV"
	shuttle = "Air Konyang Transport (Drydock)"
	desc = "The Peregrine-class civilian transport, manufactured by Einstein Engines, is a frequent favorite for interstellar travel. The design is most commonly seen owned by Solarian spacelines, as well as the Konyang-based Air Konyang."
	icon_state = "generic"
	moving_state = "generic_moving"
	designer = "Einstein Engines"
	volume = "75 meters length, 35 meters beam/width, 21 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "No weapons detected"
	sizeclass = "Peregrine-class civilian transport"
	shiptype = "Civilian passenger transport."
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/obj/effect/overmap/visitable/ship/landable/drydock_ship/air_konyang/New()
	designation = "[pick("Qianlima", "Senrima", "Cheollima", "Chollima")]"
	..()

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/air_konyang
	shuttle_tag = "Air Konyang Transport (Drydock)"

/datum/shuttle/autodock/overmap/drydock_ship/air_konyang
	name = "Air Konyang Transport (Drydock)"
	move_time = 35
	range = 2
	fuel_consumption = 6
	shuttle_area = list(/area/shuttle/air_konyang/atmos, /area/shuttle/air_konyang/engineering, /area/shuttle/air_konyang/storage, /area/shuttle/air_konyang/starbwing, /area/shuttle/air_konyang/crew, /area/shuttle/air_konyang/mainroom, /area/shuttle/air_konyang/bridge, /area/shuttle/air_konyang/rear_hall)
	current_location = "nav_air_konyang_start_dd"
	dock_target = "airlock_air_konyang"
	landmark_transition = "nav_air_konyang_transit_dd"
	logging_home_tag = "nav_air_konyang_start_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/air_konyang
	shuttle_name = "Air Konyang Transport (Drydock)"
	landmark_tag = "nav_air_konyang_start_dd"

/obj/effect/shuttle_landmark/drydock_ship/air_konyang_transit
	name = "In transit"
	landmark_tag = "nav_air_konyang_transit_dd"
	base_turf = /turf/space/transit/north
