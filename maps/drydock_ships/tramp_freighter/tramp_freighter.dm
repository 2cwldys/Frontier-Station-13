/*
 * Drydock Ship -- Independent Freighter
 * Converted from maps/away/ships/tramp_freighter/tramp_freighter.dmm (Bucket
 * B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/tramp_freighter
	name = "Independent Freighter"
	id = "tramp_freighter"
	mappath = "maps/drydock_ships/tramp_freighter/tramp_freighter.dmm"
	price = 0
	bridge_area_type = /area/tramp_freighter/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/tramp_freighter, /datum/shuttle/autodock/overmap/freighter_shuttle)
	sub_shuttle_tags = list("Freight Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/tramp_freighter
	name = "Independent Freighter"
	class = "ICV"
	shuttle = "Independent Freighter (Drydock)"
	desc = "A favourite of small-scale independent businesses, the Farthing-class is one of few popular commercial designs of hauling vessel not manufactured by any particular megacorporation. Tolerances are cut throughout the ship to achieve its legendary cost efficiency."
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	scanimage = "tramp_freighter.png"
	designer = "Independent, Unknown"
	volume = "49 meters length, 26 meters beam/width, 11 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Fore low-end ballistic weapon mount, aft flight craft dock"
	sizeclass = "Farthing Class Freighter"
	shiptype = "Long-term shipping utilities"

/datum/shuttle/autodock/overmap/drydock_ship/tramp_freighter
	name = "Independent Freighter (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/tramp_freighter,
		/area/tramp_freighter/bridge,
		/area/tramp_freighter/crew_quarters,
		/area/tramp_freighter/lounge,
		/area/tramp_freighter/captain,
		/area/tramp_freighter/captain_bed,
		/area/tramp_freighter/cargo,
		/area/tramp_freighter/engi,
		/area/tramp_freighter/armory,
		/area/tramp_freighter/power,
		/area/tramp_freighter/atmos,
		/area/tramp_freighter/portthrust,
		/area/tramp_freighter/starboardthrust,
		/area/tramp_freighter/afthallway,
		/area/tramp_freighter/centralhallway,
		/area/tramp_freighter/custodial,
		/area/tramp_freighter/kitchen,
		/area/tramp_freighter/equipment,
		/area/tramp_freighter/disposals,
		/area/tramp_freighter/refinery,
		/area/tramp_freighter/hydroponics,
		/area/tramp_freighter/washroom,
		/area/tramp_freighter/starboard_docking,
		/area/tramp_freighter/port_docking,
		/area/tramp_freighter/port_docking_processing,
		/area/tramp_freighter/starboard_docking_processing,
	)
	current_location = "nav_tramp_freighter_space_dd"
	landmark_transition = "nav_tramp_freighter_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/tramp_freighter
	shuttle_name = "Independent Freighter (Drydock)"
	landmark_tag = "nav_tramp_freighter_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/tramp_freighter_transit
	name = "In transit"
	landmark_tag = "nav_tramp_freighter_transit_dd"
	base_turf = /turf/space/transit/north
