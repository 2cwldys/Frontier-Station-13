/*
 * Drydock Ship -- Civilian Yacht
 * Converted from maps/away/ships/yacht_civ/yacht_civ.dmm (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/yacht_civ
	name = "Civilian Yacht"
	id = "yacht_civ"
	mappath = "maps/drydock_ships/yacht_civ/yacht_civ.dmm"
	price = 0
	bridge_area_type = /area/ship/yacht_civ/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/yacht_civ)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/yacht_civ
	name = "Civilian Yacht"
	class = "ICV"
	desc = "Diamond-class Yacht, commonly seen in more affluent systems and usually used for short-range flights between civilised planets, moons, and other nearby sectors, shuttling the rich between work, home, and recreation. Designed by Einstein Engines and produced by Hephaestus Industries."
	icon_state = "canary"
	moving_state = "canary_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	designer = "Einstein Engines"
	volume = "63 meters length, 24 meters beam/width, 20 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	propulsion = "Superheated Composite Gas Thrust"
	weapons = "None"
	sizeclass = "Diamond-class Yacht"
	shiptype = "Leisure yacht"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 3000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/yacht_civ
	name = "Civilian Yacht (Drydock)"
	move_time = 25
	range = 2
	fuel_consumption = 3
	shuttle_area = list(
		/area/ship/yacht_civ,
		/area/ship/yacht_civ/bridge,
		/area/ship/yacht_civ/quarters,
		/area/ship/yacht_civ/kitchen,
		/area/ship/yacht_civ/lounge,
		/area/ship/yacht_civ/storage,
		/area/ship/yacht_civ/engineering,
		/area/ship/yacht_civ/propulsion,
		/area/ship/yacht_civ/hangar,
		/area/ship/yacht_civ/hallway_aft,
		/area/ship/yacht_civ/hallway_mid,
		/area/ship/yacht_civ/hallway_fore,
	)
	current_location = "nav_yacht_civ_space_dd"
	landmark_transition = "nav_yacht_civ_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/yacht_civ
	shuttle_name = "Civilian Yacht (Drydock)"
	landmark_tag = "nav_yacht_civ_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/yacht_civ_transit
	name = "In transit"
	landmark_tag = "nav_yacht_civ_transit_dd"
	base_turf = /turf/space/transit/north
