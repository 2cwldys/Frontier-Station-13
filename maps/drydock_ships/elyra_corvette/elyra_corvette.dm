/*
 * Drydock Ship -- Elyran Corvette
 * Converted from maps/away/ships/elyra/elyra_corvette/elyra_corvette.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/elyran_corvette
	name = "Elyran Corvette"
	id = "elyran_corvette_dd"
	mappath = "maps/drydock_ships/elyra_corvette/elyra_corvette.dmm"
	price = 0
	bridge_area_type = /area/ship/elyran_corvette/cic
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/elyran_corvette)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/elyran_corvette
	name = "Elyran Corvette"
	class = "ENV"
	desc = "One of the first vessels from Elyra's recent military modernization efforts to enter active service, the Sahin-class has taken great strides in improved quality and survivability from previous designs and is on track to become the backbone of the Elyran Republic's border control efforts."
	icon_state = "corvette"
	moving_state = "corvette_moving"
	colors = list("#ffae17", "#ffcd70")
	scanimage = "elyran_corvette.png"
	designer = "Jewel Aerospace, Republic of Elyra"
	volume = "52 meters length, 44 meters beam/width, 18 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding fore-mounted medium caliber ballistic armament, fore obscured flight craft bay"
	sizeclass = "Sahin-class Corvette"
	shiptype = "Military patrol and combat utility"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/elyran_corvette
	name = "Elyran Corvette (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/elyran_corvette,
		/area/ship/elyran_corvette/cic,
		/area/ship/elyran_corvette/mainhallway,
		/area/ship/elyran_corvette/porthallway,
		/area/ship/elyran_corvette/starboardhallway,
		/area/ship/elyran_corvette/washroom,
		/area/ship/elyran_corvette/brig,
		/area/ship/elyran_corvette/hangar,
		/area/ship/elyran_corvette/starboardwep,
		/area/ship/elyran_corvette/portwep,
		/area/ship/elyran_corvette/medbay,
		/area/ship/elyran_corvette/briefing,
		/area/ship/elyran_corvette/messhall,
		/area/ship/elyran_corvette/dorm,
		/area/ship/elyran_corvette/captain,
		/area/ship/elyran_corvette/prayerhall,
		/area/ship/elyran_corvette/engineering,
		/area/ship/elyran_corvette/portthrust,
		/area/ship/elyran_corvette/starboardthrust,
	)
	current_location = "nav_elyran_corvette_space_dd"
	landmark_transition = "nav_elyran_corvette_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/elyran_corvette
	shuttle_name = "Elyran Corvette (Drydock)"
	landmark_tag = "nav_elyran_corvette_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/elyran_corvette_transit
	name = "In transit"
	landmark_tag = "nav_elyran_corvette_transit_dd"
	base_turf = /turf/space/transit/north
