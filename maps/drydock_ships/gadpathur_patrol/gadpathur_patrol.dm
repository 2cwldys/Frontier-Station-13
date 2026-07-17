/*
 * Drydock Ship -- Gadpathurian Patrol Corvette
 * Converted from maps/away/ships/coc/gadpathur_patrol (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/gadpathur_patrol
	name = "Gadpathurian Patrol Corvette"
	id = "gadpathur_patroller_dd"
	mappath = "maps/drydock_ships/gadpathur_patrol/gadpathur_patrol.dmm"
	price = 0
	bridge_area_type = /area/ship/gadpathur_patrol/cic
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/gadpathur_patrol)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/gadpathur_patrol
	name = "Gadpathurian Patrol Corvette"
	class = "GNV"
	shuttle = "Gadpathurian Patrol Corvette (Drydock)"
	desc = "The Gadpathurian Skanda-class patrol corvette is very much designed with function over form in mind. These vessels are built by Gadpathur's industrial cadres, to serve as patrol and reconnaissance craft for Gadpathur's navy."
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#474800", "#7f6300")
	designer = "Gadpathur"
	volume = "80 meters length, 58 meters beam/width, 12 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Starboard fore-mounted light caliber armament, starboard midship-mounted large caliber armanent, aft flight craft bay"
	sizeclass = "Skanda-class Patrol"
	shiptype = "Military patrol and combat utility"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 6000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/gadpathur_patrol
	name = "Gadpathurian Patrol Corvette (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/gadpathur_patrol,
		/area/ship/gadpathur_patrol/exterior,
		/area/ship/gadpathur_patrol/cic,
		/area/ship/gadpathur_patrol/cell,
		/area/ship/gadpathur_patrol/brig,
		/area/ship/gadpathur_patrol/interrogation,
		/area/ship/gadpathur_patrol/armory,
		/area/ship/gadpathur_patrol/sit_room,
		/area/ship/gadpathur_patrol/officer,
		/area/ship/gadpathur_patrol/officer_bath,
		/area/ship/gadpathur_patrol/quarters,
		/area/ship/gadpathur_patrol/quarters_bath,
		/area/ship/gadpathur_patrol/armanent/francisca,
		/area/ship/gadpathur_patrol/armanent/longbow,
		/area/ship/gadpathur_patrol/ammo,
		/area/ship/gadpathur_patrol/telecomms,
		/area/ship/gadpathur_patrol/reactor,
		/area/ship/gadpathur_patrol/fuel,
		/area/ship/gadpathur_patrol/thrusters,
		/area/ship/gadpathur_patrol/thrusters/starboard,
		/area/ship/gadpathur_patrol/thrusters/port,
		/area/ship/gadpathur_patrol/atmos,
		/area/ship/gadpathur_patrol/hangar,
		/area/ship/gadpathur_patrol/engineering,
		/area/ship/gadpathur_patrol/galley,
		/area/ship/gadpathur_patrol/medbay,
		/area/ship/gadpathur_patrol/cryo,
		/area/ship/gadpathur_patrol/corridor/starboard,
		/area/ship/gadpathur_patrol/corridor/port,
		/area/ship/gadpathur_patrol/ward,
		/area/ship/gadpathur_patrol/morgue,
		/area/ship/gadpathur_patrol/crew_prep,
		/area/ship/gadpathur_patrol/eva,
	)
	current_location = "nav_gadpathur_patrol_space_dd"
	landmark_transition = "nav_gadpathur_patrol_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/gadpathur_patrol
	shuttle_name = "Gadpathurian Patrol Corvette (Drydock)"
	landmark_tag = "nav_gadpathur_patrol_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/gadpathur_patrol_transit
	name = "In transit"
	landmark_tag = "nav_gadpathur_patrol_transit_dd"
	base_turf = /turf/space/transit/north
