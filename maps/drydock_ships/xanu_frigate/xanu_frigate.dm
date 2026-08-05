/*
 * Drydock Ship -- Xanu Spacefleet Frigate
 * Converted from maps/away/ships/xanu/xanu_frigate.dmm (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale. The source's two internal escort craft
 * (Xanu Fighter, Xanu Boarder) are left in place as inert decoration --
 * neither datum is registered in shuttles_to_initialise below.
 */

/datum/map_template/drydock_ship/xanu_frigate
	name = "Xanu Spacefleet Frigate"
	id = "xanu_frigate"
	mappath = "maps/drydock_ships/xanu_frigate/xanu_frigate.dmm"
	price = 1000000
	bridge_area_type = /area/ship/xanu_frigate/cic
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/xanu_frigate, /datum/shuttle/autodock/overmap/xanu_fighter, /datum/shuttle/autodock/overmap/xanu_boarder)
	sub_shuttle_tags = list("Xanu Fighter", "Xanu Boarder")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/xanu_frigate
	name = "Xanu Spacefleet Frigate"
	class = "AXSV"
	shuttle = "Xanu Spacefleet Frigate (Drydock)"
	desc = "The Rapier-class Frigate is a formidable warship in widespread use by the All-Xanu Spacefleet throughout its expeditionary fleets. Originating as a robust upgrade package to the venerable Estoc class, the Rapier upgrade program has spared no expense, with thick hull plating, redundant power, life support, and engines."
	icon_state = "xanu_frigate"
	moving_state = "xanu_frigate_moving"
	colors = COLOR_COALITION
	designer = "dNA Defense & Aerospace Shipyards"
	volume = "108 meters length, 71 meters beam/width, 45 meters vertical height"
	drive = "Medium-Speed Warp Acceleration FTL Drive"
	propulsion = "Superheated Composite Gas Thrust"
	weapons = "Dual extruding fore caliber ballistic armaments, aft obscured flight craft bay"
	sizeclass = "Shrike-class Frigate"
	shiptype = "Naval frigate"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 6000
	vessel_size = SHIP_SIZE_LARGE
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/xanu_frigate
	name = "Xanu Spacefleet Frigate (Drydock)"
	move_time = 40
	range = 2
	fuel_consumption = 6
	shuttle_area = list(
		/area/ship/xanu_frigate,
		/area/ship/xanu_frigate/bridge,
		/area/ship/xanu_frigate/captain,
		/area/ship/xanu_frigate/meeting,
		/area/ship/xanu_frigate/medbay,
		/area/ship/xanu_frigate/rec_room,
		/area/ship/xanu_frigate/crew_quarters,
		/area/ship/xanu_frigate/galley,
		/area/ship/xanu_frigate/mess_hall,
		/area/ship/xanu_frigate/hydroponics,
		/area/ship/xanu_frigate/cic,
		/area/ship/xanu_frigate/weapon,
		/area/ship/xanu_frigate/weapon/longbow,
		/area/ship/xanu_frigate/weapon/longbow/ammo,
		/area/ship/xanu_frigate/weapon/grauwolf,
		/area/ship/xanu_frigate/weapon/grauwolf/ammo,
		/area/ship/xanu_frigate/weapon/francisca_storage,
		/area/ship/xanu_frigate/custodial,
		/area/ship/xanu_frigate/hangar,
		/area/ship/xanu_frigate/cargo_bay,
		/area/ship/xanu_frigate/disposals,
		/area/ship/xanu_frigate/brig,
		/area/ship/xanu_frigate/eva,
		/area/ship/xanu_frigate/engineering,
		/area/ship/xanu_frigate/engineering/port,
		/area/ship/xanu_frigate/engineering/starboard,
		/area/ship/xanu_frigate/engineering/reactor,
		/area/ship/xanu_frigate/corridor,
		/area/ship/xanu_frigate/corridor/fore_atrium,
		/area/ship/xanu_frigate/corridor/fore,
		/area/ship/xanu_frigate/corridor/central,
		/area/ship/xanu_frigate/corridor/port,
		/area/ship/xanu_frigate/corridor/starboard,
		/area/ship/xanu_frigate/corridor/aft_port,
		/area/ship/xanu_frigate/corridor/aft_starboard,
		/area/ship/xanu_frigate/corridor/aft,
	)
	current_location = "nav_xanu_frigate_space_dd"
	landmark_transition = "nav_xanu_frigate_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/xanu_frigate
	shuttle_name = "Xanu Spacefleet Frigate (Drydock)"
	landmark_tag = "nav_xanu_frigate_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/xanu_frigate_transit
	name = "In transit"
	landmark_tag = "nav_xanu_frigate_transit_dd"
	base_turf = /turf/space/transit/north
