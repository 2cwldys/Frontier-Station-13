/*
 * Drydock Ship -- SFA Corvette
 * Converted from maps/away/ships/sol/sol_pirate/sfa_patrol_ship.dmm (Bucket
 * B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/sfa_patrol_ship
	name = "SFA Corvette"
	id = "sfa_patrol_ship"
	mappath = "maps/drydock_ships/sol_pirate/sfa_patrol_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/sfa_patrol_ship/Bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/sfa_patrol_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/sfa_patrol_ship
	name = "SFA Corvette"
	class = "SFAV"
	shuttle = "SFA Corvette (Drydock)"
	desc = "A small ship that appears to be, at its core, a Montevideo-class corvette, a Solarian anti-piracy and patrol corvette designed with ample automation and streamlined equipment which allows for it to be manned by a small crew. This one, however, seems to have been host to a myriad of haphazard and radical modifications, and is scarcely identifiable as the original craft."
	icon_state = "corvette"
	moving_state = "corvette_moving"
	colors = list("#9dc04c", "#52c24c")
	scanimage = "corvette.png"
	designer = "Solarian Navy, Southern Fleet Administration field-modified"
	volume = "41 meters length, 39 meters beam/width, 17 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding fore and starboard-mounted medium caliber ballistic armament, fore obscured flight craft bay"
	sizeclass = "Unidentified-type Retrofitted Montevideo-class Corvette"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/sfa_patrol_ship
	name = "SFA Corvette (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/sfa_patrol_ship,
		/area/ship/sfa_patrol_ship/docking,
		/area/ship/sfa_patrol_ship/hangar,
		/area/ship/sfa_patrol_ship/destroyedmedbay,
		/area/ship/sfa_patrol_ship/kitchenmedbay,
		/area/ship/sfa_patrol_ship/destroyedrec,
		/area/ship/sfa_patrol_ship/SFA_Armory,
		/area/ship/sfa_patrol_ship/destroyedammo,
		/area/ship/sfa_patrol_ship/Engineering,
		/area/ship/sfa_patrol_ship/atmos,
		/area/ship/sfa_patrol_ship/Telecomms,
		/area/ship/sfa_patrol_ship/TreasureRoom,
		/area/ship/sfa_patrol_ship/Bridge,
		/area/ship/sfa_patrol_ship/custodialammo,
		/area/ship/sfa_patrol_ship/Quarters,
		/area/ship/sfa_patrol_ship/head,
		/area/ship/sfa_patrol_ship/Officer,
		/area/ship/sfa_patrol_ship/Brig,
		/area/ship/sfa_patrol_ship/Engine1,
		/area/ship/sfa_patrol_ship/Engine2,
		/area/ship/sfa_patrol_ship/Suit_Storage,
	)
	current_location = "nav_sfa_patrol_ship_space_dd"
	landmark_transition = "nav_sfa_patrol_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/sfa_patrol_ship
	shuttle_name = "SFA Corvette (Drydock)"
	landmark_tag = "nav_sfa_patrol_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/sfa_patrol_ship_transit
	name = "In transit"
	landmark_tag = "nav_sfa_patrol_ship_transit_dd"
	base_turf = /turf/space/transit/north
