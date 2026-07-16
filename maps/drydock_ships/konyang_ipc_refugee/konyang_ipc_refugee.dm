/*
 * Drydock Ship -- IPC Refugee Ship
 * Converted from maps/away/ships/konyang/ipc_refugee/ipc_refugee_ship.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/ipc_refugee_ship
	name = "IPC Refugee Ship"
	id = "ipc_refugee_ship_dd"
	mappath = "maps/drydock_ships/konyang_ipc_refugee/ipc_refugee_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/ipc_refugee/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/ipc_refugee_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/ipc_refugee_ship
	name = "IPC Refugee Ship"
	class = "ICV"
	desc = "The Akers-class freighter is an ancient design, dating back nearly two hundred years. It was considered a reliable freighter for its time, but is completely obsolete by modern standards, making it a rare sight outside of ship graveyards."
	icon_state = "freighter"
	moving_state = "freighter_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	scanimage = "tramp_freighter.png"
	designer = "ERROR"
	volume = "52 meters length, 28 meters beam/width, 17 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	sizeclass = "Akers-class Freighter"
	shiptype = "Light Cargo Freighter"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/ipc_refugee_ship
	name = "IPC Refugee Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/ipc_refugee,
		/area/ship/ipc_refugee/engie,
		/area/ship/ipc_refugee/atmos,
		/area/ship/ipc_refugee/dock,
		/area/ship/ipc_refugee/mainhall,
		/area/ship/ipc_refugee/forehall,
		/area/ship/ipc_refugee/cargopod_a,
		/area/ship/ipc_refugee/cargopod_b,
		/area/ship/ipc_refugee/crew,
		/area/ship/ipc_refugee/captain,
		/area/ship/ipc_refugee/bridge,
	)
	current_location = "nav_ipc_refugee_ship_space_dd"
	landmark_transition = "nav_ipc_refugee_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/ipc_refugee_ship
	shuttle_name = "IPC Refugee Ship (Drydock)"
	landmark_tag = "nav_ipc_refugee_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/ipc_refugee_ship_transit
	name = "In transit"
	landmark_tag = "nav_ipc_refugee_ship_transit_dd"
	base_turf = /turf/space/transit/north
