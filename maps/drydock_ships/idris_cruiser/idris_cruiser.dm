/*
 * Drydock Ship -- Idris Cruiser
 * Converted from maps/away/ships/idris/idris_cruiser.dmm (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/idris_cruiser
	name = "Idris Cruiser"
	id = "idris_cruiser"
	mappath = "maps/drydock_ships/idris_cruiser/idris_cruiser.dmm"
	price = 0
	bridge_area_type = /area/ship/idris_cruiser/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/idris_cruiser)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/idris_cruiser
	name = "Idris Cruiser"
	class = "IIV"
	shuttle = "Idris Cruiser (Drydock)"
	desc = "A small luxury cruiser run by Idris Incorporated's subsidiary, Celestial Cruises. The Argentum-class is more of a yacht than a proper cruise ship, and is easily dwarfed by the fleet's larger vessels. However, it makes up for its diminuitive size by its speed, flexibility, and low maintenance cost. It adopts a unique wandering business model, where it roams the Spur and caters to tired traveling vessel crews seeking a getaway among the stars. It comes with a bar and restaurant, a pool, a spa, and a viewing lounge, as well as four suites for overnight stayers."
	icon_state = "sanctuary"
	moving_state = "sanctuary_moving"
	colors = "#5acfc0"
	designer = "Idris Incorporated - Celestial Cruises"
	volume = "82 meters length, 60 meters beam/width, 28 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	propulsion = "Superheated Composite Gas Thrust"
	weapons = "None"
	sizeclass = "Argentum-class Cruise Yacht"
	shiptype = "Luxury cruise yacht"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/idris_cruiser
	name = "Idris Cruiser (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/idris_cruiser,
		/area/ship/idris_cruiser/bridge,
		/area/ship/idris_cruiser/armory,
		/area/ship/idris_cruiser/crew_quarters,
		/area/ship/idris_cruiser/medbay,
		/area/ship/idris_cruiser/security,
		/area/ship/idris_cruiser/brig,
		/area/ship/idris_cruiser/breakroom,
		/area/ship/idris_cruiser/hydroponics,
		/area/ship/idris_cruiser/kitchen,
		/area/ship/idris_cruiser/custodial,
		/area/ship/idris_cruiser/bar,
		/area/ship/idris_cruiser/great_room,
		/area/ship/idris_cruiser/pool,
		/area/ship/idris_cruiser/locker_rooms,
		/area/ship/idris_cruiser/locker_rooms/room_1,
		/area/ship/idris_cruiser/locker_rooms/room_2,
		/area/ship/idris_cruiser/spa,
		/area/ship/idris_cruiser/spa/spa1,
		/area/ship/idris_cruiser/spa/spa2,
		/area/ship/idris_cruiser/lounge,
		/area/ship/idris_cruiser/cargo_bay,
		/area/ship/idris_cruiser/laundromat,
		/area/ship/idris_cruiser/engineering,
		/area/ship/idris_cruiser/engineering/reactor,
		/area/ship/idris_cruiser/engineering/disposals,
		/area/ship/idris_cruiser/suite,
		/area/ship/idris_cruiser/suite/suite_1,
		/area/ship/idris_cruiser/suite/suite_2,
		/area/ship/idris_cruiser/suite/suite_3,
		/area/ship/idris_cruiser/suite/suite_4,
		/area/ship/idris_cruiser/restroom,
		/area/ship/idris_cruiser/restroom/suite_1,
		/area/ship/idris_cruiser/restroom/suite_2,
		/area/ship/idris_cruiser/restroom/suite_3,
		/area/ship/idris_cruiser/restroom/suite_4,
		/area/ship/idris_cruiser/restroom/public,
		/area/ship/idris_cruiser/corridor,
		/area/ship/idris_cruiser/corridor/crew_fore,
		/area/ship/idris_cruiser/corridor/crew_aft,
		/area/ship/idris_cruiser/corridor/lobby,
		/area/ship/idris_cruiser/corridor/civ_fore,
		/area/ship/idris_cruiser/corridor/civ_aft,
		/area/ship/idris_cruiser/corridor/maintenance_foyer,
		/area/ship/idris_cruiser/corridor/port_lobby,
		/area/ship/idris_cruiser/corridor/starboard_lobby,
		/area/ship/idris_cruiser/corridor/suites_a,
		/area/ship/idris_cruiser/corridor/suites_b,
		/area/ship/idris_cruiser/corridor/dockingarm,
		/area/ship/idris_cruiser/corridor/dockingarm/port,
		/area/ship/idris_cruiser/corridor/dockingarm/starboard,
	)
	current_location = "nav_idris_cruiser_space_dd"
	landmark_transition = "nav_idris_cruiser_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/idris_cruiser
	shuttle_name = "Idris Cruiser (Drydock)"
	landmark_tag = "nav_idris_cruiser_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/idris_cruiser_transit
	name = "In transit"
	landmark_tag = "nav_idris_cruiser_transit_dd"
	base_turf = /turf/space/transit/north
