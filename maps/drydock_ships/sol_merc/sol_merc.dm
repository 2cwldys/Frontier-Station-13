/*
 * Drydock Ship -- FSF Corvette
 * Converted from maps/away/ships/sol/sol_merc/fsf_patrol_ship.dmm (Bucket B)
 * -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/fsf_patrol_ship
	name = "FSF Corvette"
	id = "fsf_patrol_ship"
	mappath = "maps/drydock_ships/sol_merc/fsf_patrol_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/fsf_patrol_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/fsf_patrol_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/fsf_patrol_ship
	name = "FSF Corvette"
	class = "FSFV"
	shuttle = "FSF Corvette (Drydock)"
	desc = "A small corvette manufactured for the Solarian Navy by Einstein Engines, the Montevideo-class is an anti-piracy vessel through and through - with a shuttle bay that takes up a third of the ship and only a single weapon hardpoint located in one arm of the ship, the Montevideo is designed for long-term, self-sufficient operations in inhabited space against small-time pirate vessels."
	icon_state = "corvette"
	moving_state = "corvette_moving"
	colors = list("#9dc04c", "#52c24c")
	scanimage = "corvette.png"
	designer = "Solarian Navy, Tiscareno y Volante Shipbuilding modifications"
	volume = "41 meters length, 39 meters beam/width, 17 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding fore and starboard-mounted medium caliber ballistic armament, fore obscured flight craft bay"
	sizeclass = "Montevideo-class Corvette"
	shiptype = "Military patrol and combat utility"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/fsf_patrol_ship
	name = "FSF Corvette (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/fsf_patrol_ship,
		/area/ship/fsf_patrol_ship/bridge,
		/area/ship/fsf_patrol_ship/officer,
		/area/ship/fsf_patrol_ship/briefing,
		/area/ship/fsf_patrol_ship/starboardhallway,
		/area/ship/fsf_patrol_ship/brig,
		/area/ship/fsf_patrol_ship/storage,
		/area/ship/fsf_patrol_ship/mess,
		/area/ship/fsf_patrol_ship/gym,
		/area/ship/fsf_patrol_ship/hangar,
		/area/ship/fsf_patrol_ship/engineering,
		/area/ship/fsf_patrol_ship/atmos,
		/area/ship/fsf_patrol_ship/cic,
		/area/ship/fsf_patrol_ship/portpropulsion,
		/area/ship/fsf_patrol_ship/starboardpropulsion,
		/area/ship/fsf_patrol_ship/medical,
		/area/ship/fsf_patrol_ship/bathroom,
		/area/ship/fsf_patrol_ship/quarters,
		/area/ship/fsf_patrol_ship/requisitions,
		/area/ship/fsf_patrol_ship/armory,
		/area/ship/fsf_patrol_ship/ammo,
		/area/ship/fsf_patrol_ship/grauwolf,
		/area/ship/fsf_patrol_ship/dock,
		/area/ship/fsf_patrol_ship/dock/fore,
	)
	current_location = "nav_fsf_patrol_ship_space_dd"
	landmark_transition = "nav_fsf_patrol_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/fsf_patrol_ship
	shuttle_name = "FSF Corvette (Drydock)"
	landmark_tag = "nav_fsf_patrol_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/fsf_patrol_ship_transit
	name = "In transit"
	landmark_tag = "nav_fsf_patrol_ship_transit_dd"
	base_turf = /turf/space/transit/north
