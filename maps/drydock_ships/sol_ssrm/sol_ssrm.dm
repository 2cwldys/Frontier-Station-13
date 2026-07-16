/*
 * Drydock Ship -- Solarian Navy Reconnaissance Corvette
 * Converted from maps/away/ships/sol/sol_ssrm/ssrm_ship.dmm (Bucket B) --
 * see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/ssrm_corvette
	name = "Solarian Navy Reconnaissance Corvette"
	id = "ssrm_corvette"
	mappath = "maps/drydock_ships/sol_ssrm/ssrm_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/ssrm_corvette/cic
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/ssrm_corvette)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/ssrm_corvette
	name = "Solarian Navy Reconnaissance Corvette"
	class = "SAMV"
	desc = "A long-range reconnaissance corvette design in use by the Solarian Navy, the Uhlan-class is a relatively costly and somewhat uncommon ship to be seen in the Alliance's fleets, and is typically reserved for more elite units. Designed to operate alone or as part of a small task force with minimal support in unfriendly space."
	icon_state = "corvette"
	moving_state = "corvette_moving"
	colors = list("#9dc04c", "#52c24c")
	scanimage = "corvette.png"
	designer = "Solarian Navy"
	volume = "41 meters length, 43 meters beam/width, 19 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding fore caliber ballistic armament, fore obscured flight craft bay"
	sizeclass = "Uhlan-class Corvette"
	shiptype = "Military reconnaissance and extended-duration combat utility"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 6500
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/ssrm_corvette
	name = "Solarian Navy Reconnaissance Corvette (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/ssrm_corvette,
		/area/ship/ssrm_corvette/hallway,
		/area/ship/ssrm_corvette/cic,
		/area/ship/ssrm_corvette/telecomms,
		/area/ship/ssrm_corvette/docking_port,
		/area/ship/ssrm_corvette/starboard_thrusters,
		/area/ship/ssrm_corvette/atmospherics,
		/area/ship/ssrm_corvette/port_thrusters,
		/area/ship/ssrm_corvette/engineering,
		/area/ship/ssrm_corvette/synthroom,
		/area/ship/ssrm_corvette/bunks,
		/area/ship/ssrm_corvette/eva_preperation,
		/area/ship/ssrm_corvette/armoury,
		/area/ship/ssrm_corvette/brig,
		/area/ship/ssrm_corvette/starboard_battery,
		/area/ship/ssrm_corvette/starboard_gunnery,
		/area/ship/ssrm_corvette/port_battery,
		/area/ship/ssrm_corvette/port_gunnery,
		/area/ship/ssrm_corvette/crew_lounge,
		/area/ship/ssrm_corvette/head,
		/area/ship/ssrm_corvette/safe_room,
		/area/ship/ssrm_corvette/captain_office,
		/area/ship/ssrm_corvette/captain_cabin,
		/area/ship/ssrm_corvette/cpo_cabin,
		/area/ship/ssrm_corvette/canteen,
		/area/ship/ssrm_corvette/freezer,
		/area/ship/ssrm_corvette/garage,
		/area/ship/ssrm_corvette/infirmary,
		/area/ship/ssrm_corvette/cryo,
		/area/ship/ssrm_corvette/reactor,
	)
	current_location = "nav_ssrm_corvette_space_dd"
	landmark_transition = "nav_ssrm_corvette_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/ssrm_corvette
	shuttle_name = "Solarian Navy Reconnaissance Corvette (Drydock)"
	landmark_tag = "nav_ssrm_corvette_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/ssrm_corvette_transit
	name = "In transit"
	landmark_tag = "nav_ssrm_corvette_transit_dd"
	base_turf = /turf/space/transit/north
