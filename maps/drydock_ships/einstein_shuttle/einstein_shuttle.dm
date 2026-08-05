/*
 * Drydock Ship -- Einstein Shuttle
 * Converted from maps/away/ships/konyang/einstein_shuttle (Bucket A, already
 * a fully flyable/dockable away-site craft) -- see lone_spacer.dm for the
 * general conversion approach/rationale. The source's ghostrole spawner is
 * deliberately excluded (it lived inline in the same source .dm file rather
 * than a separate _ghostroles.dm, but the effect is the same: a purchased
 * ship shouldn't spawn hostile/NPC crew on retrieve).
 */

/datum/map_template/drydock_ship/einstein_shuttle
	name = "Einstein Shuttle"
	id = "einstein_shuttle"
	mappath = "maps/drydock_ships/einstein_shuttle/einstein_shuttle.dmm"
	price = 1000000
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/einstein_shuttle)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/einstein_shuttle
	name = "Einstein Shuttle (Landable)"
	class = "EEV"
	shuttle = "Einstein Shuttle (Drydock)"
	designation = "Ferryman"
	desc = "The Chariot-class Executive Transport is an older Einstein Engines design for localised luxury transport. These days, it is largely used by Einstein corporate personnel for short-range business journeys, as well as occasionally being attached to larger Einstein vessels."
	icon_state = "shuttle"
	moving_state = "shuttle_moving"
	colors = list("#18e9b5", "#6aa9dd")
	max_speed = 1/(2 SECONDS)
	burn_delay = 2 SECONDS
	vessel_mass = 3000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/einstein_shuttle
	shuttle_tag = "Einstein Shuttle (Drydock)"

/datum/shuttle/autodock/overmap/drydock_ship/einstein_shuttle
	name = "Einstein Shuttle (Drydock)"
	move_time = 20
	shuttle_area = list(/area/shuttle/einstein_shuttle/helm, /area/shuttle/einstein_shuttle/main, /area/shuttle/einstein_shuttle/room, /area/shuttle/einstein_shuttle/room/two, /area/shuttle/einstein_shuttle/room/three, /area/shuttle/einstein_shuttle/room/four, /area/shuttle/einstein_shuttle/conference, /area/shuttle/einstein_shuttle/bathroom, /area/shuttle/einstein_shuttle/porteng, /area/shuttle/einstein_shuttle/starbeng, /area/shuttle/einstein_shuttle/dock)
	current_location = "nav_start_einstein_dd"
	landmark_transition = "nav_transit_einstein_dd"
	range = 1
	fuel_consumption = 2
	logging_home_tag = "nav_start_einstein_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/einstein_shuttle
	shuttle_name = "Einstein Shuttle (Drydock)"
	landmark_tag = "nav_start_einstein_dd"

/obj/effect/shuttle_landmark/drydock_ship/einstein_shuttle_transit
	name = "In transit"
	landmark_tag = "nav_transit_einstein_dd"
	base_turf = /turf/space/transit/north
