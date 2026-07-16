/*
 * Drydock Ship -- Solarian Navy Frigate
 * Converted from maps/away/ships/sol/sol_frigate (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale. The source's own small internal escort
 * shuttle (Solarian Frigate Shuttle) is left in place as inert decoration --
 * its datum is deliberately not registered in shuttles_to_initialise below.
 */

/datum/map_template/drydock_ship/sol_frigate
	name = "Solarian Navy Frigate"
	id = "sol_frigate"
	mappath = "maps/drydock_ships/sol_frigate/sol_frigate.dmm"
	price = 0
	bridge_area_type = /area/ship/sol_frigate/cic
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/sol_frigate)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/sol_frigate
	name = "Solarian Navy Frigate"
	class = "SAMV"
	desc = "A long-range frigate currently seeing extensive service in the Solarian Navy, the Curiassier-Class Frigate was a inexpensive pre-civil war design that was only intended to perform common anti-piracy tasks and to provide escort for ships of minor importance to the Navy."
	icon_state = "xanu_frigate"
	moving_state = "xanu_frigate_moving"
	colors = list("#9dc04c", "#52c24c")
	scanimage = "corvette.png"
	designer = "Solarian Navy"
	volume = "80 meters length, 42 meters beam/width, 37 meters vertical height"
	drive = "Medum-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding fore caliber ballistic armament, fore unobscured docking arm and catwalk"
	sizeclass = "Cuirassier-Class Frigate (Revised)"
	shiptype = "Naval Frigate"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 6200
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_LARGE

/datum/shuttle/autodock/overmap/drydock_ship/sol_frigate
	name = "Solarian Navy Frigate (Drydock)"
	move_time = 40
	range = 2
	fuel_consumption = 6
	shuttle_area = list(
		/area/ship/sol_frigate,
		/area/ship/sol_frigate/exterior,
		/area/ship/sol_frigate/hallway_fore,
		/area/ship/sol_frigate/hallway_mid,
		/area/ship/sol_frigate/cic,
		/area/ship/sol_frigate/Port_docking_port,
		/area/ship/sol_frigate/Starboard_docking_port,
		/area/ship/sol_frigate/starboard_thrusters,
		/area/ship/sol_frigate/port_thrusters,
		/area/ship/sol_frigate/engineering,
		/area/ship/sol_frigate/ocountry,
		/area/ship/sol_frigate/oquarters,
		/area/ship/sol_frigate/bunks,
		/area/ship/sol_frigate/eva_storage,
		/area/ship/sol_frigate/armoury,
		/area/ship/sol_frigate/brig,
		/area/ship/sol_frigate/starboard_battery,
		/area/ship/sol_frigate/starboard_gunnery,
		/area/ship/sol_frigate/port_battery,
		/area/ship/sol_frigate/crew_lounge,
		/area/ship/sol_frigate/head,
		/area/ship/sol_frigate/safe_room,
		/area/ship/sol_frigate/captain_office,
		/area/ship/sol_frigate/captain_cabin,
		/area/ship/sol_frigate/canteen,
		/area/ship/sol_frigate/freezer,
		/area/ship/sol_frigate/Exo_Bay,
		/area/ship/sol_frigate/sickbay,
		/area/ship/sol_frigate/hangar,
	)
	current_location = "nav_sol_frigate_space_dd"
	landmark_transition = "nav_sol_frigate_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/sol_frigate
	shuttle_name = "Solarian Navy Frigate (Drydock)"
	landmark_tag = "nav_sol_frigate_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/sol_frigate_transit
	name = "In transit"
	landmark_tag = "nav_sol_frigate_transit_dd"
	base_turf = /turf/space/transit/north
