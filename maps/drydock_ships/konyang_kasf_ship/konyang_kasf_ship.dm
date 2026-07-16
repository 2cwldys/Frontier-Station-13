/*
 * Drydock Ship -- KASF Corvette
 * Converted from maps/away/ships/konyang/kasf_ship/kasf_ship.dmm (Bucket B)
 * -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/kasf_corvette
	name = "KASF Corvette"
	id = "kasf_corvette_dd"
	mappath = "maps/drydock_ships/konyang_kasf_ship/kasf_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/kasf_corvette/cic
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/kasf_corvette)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/kasf_corvette
	name = "KASF Corvette"
	class = "KASFV"
	desc = "An older design of patrol corvette that saw its fair share of service in its golden days among the Xanu fleets, the Sai-class corvette would be considered obsolete by modern standards were it not retrofitted with newer weaponry, sensors, and other ship systems."
	icon_state = "xansan"
	moving_state = "xansan_moving"
	colors = list("#8492fd", "#4d61fc")
	scanimage = "ranger.png"
	designer = "Coalition of Colonies, Xanu Prime"
	volume = "54 meters length, 36 meters beam/width, 17 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding fore-mounted medium caliber ballistic armament, aft obscured flight craft bay"
	sizeclass = "Sai-class Corvette"
	shiptype = "Military patrol and combat utility"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/kasf_corvette
	name = "KASF Corvette (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/kasf_corvette,
		/area/ship/kasf_corvette/portthrust,
		/area/ship/kasf_corvette/starboardthrust,
		/area/ship/kasf_corvette/porthangarfoyer,
		/area/ship/kasf_corvette/starboardhangarfoyer,
		/area/ship/kasf_corvette/hangar,
		/area/ship/kasf_corvette/armory,
		/area/ship/kasf_corvette/cic,
		/area/ship/kasf_corvette/mainhall,
		/area/ship/kasf_corvette/engie,
		/area/ship/kasf_corvette/atmos,
		/area/ship/kasf_corvette/portwep,
		/area/ship/kasf_corvette/starboardwep,
		/area/ship/kasf_corvette/dorm,
		/area/ship/kasf_corvette/medbay,
		/area/ship/kasf_corvette/mess,
		/area/ship/kasf_corvette/forehall,
		/area/ship/kasf_corvette/cryo,
		/area/ship/kasf_corvette/captain,
		/area/ship/kasf_corvette/washroom,
		/area/ship/kasf_corvette/brig,
	)
	current_location = "nav_kasf_corvette_space_dd"
	landmark_transition = "nav_kasf_corvette_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/kasf_corvette
	shuttle_name = "KASF Corvette (Drydock)"
	landmark_tag = "nav_kasf_corvette_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/kasf_corvette_transit
	name = "In transit"
	landmark_tag = "nav_kasf_corvette_transit_dd"
	base_turf = /turf/space/transit/north
