/*
 * Drydock Ship -- Hailstorm Ship
 * Converted from maps/away/ships/dpra/hailstorm/hailstorm_ship.dmm (Bucket
 * B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/hailstorm_ship
	name = "Hailstorm Ship"
	id = "hailstorm_ship_dd"
	mappath = "maps/drydock_ships/dpra_hailstorm/hailstorm_ship.dmm"
	price = 0
	bridge_area_type = /area/hailstorm_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/hailstorm_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/hailstorm_ship
	name = "Hailstorm Ship"
	class = "DPRAMV"
	shuttle = "Hailstorm Ship (Drydock)"
	desc = "A skipjack armed with multiple weapons designed for patrolling and brief engagements. When used for patrols, the Hailstorm is loaded with supplies to last weeks on its own; its crew is specifically trained to be as frugal as possible while aboard."
	icon_state = "hailstorm"
	moving_state = "hailstorm_moving"
	colors = list("#B9BDC4")
	scanimage = "hailstorm.png"
	designer = "Obfuscated, hull origin uncertain"
	volume = "37 meters length, 24 meters beam/width, 11 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual bow-mounted extruding low-caliber rotary ballistic armament, dual port and starboard torpedo bays"
	sizeclass = "Hailstorm-type Retrofitted Skipjack"
	shiptype = "Short-distance military tasking, low-level naval interdiction"
	vessel_mass = 5000
	max_speed = 1/(2 SECONDS)
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/hailstorm_ship
	name = "Hailstorm Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/hailstorm_ship,
		/area/hailstorm_ship/bridge,
		/area/hailstorm_ship/gunnery_starboard,
		/area/hailstorm_ship/gunnery_port,
		/area/hailstorm_ship/torpedo_bay,
		/area/hailstorm_ship/central_hallway,
		/area/hailstorm_ship/central_maint,
		/area/hailstorm_ship/crew,
		/area/hailstorm_ship/kitchen,
		/area/hailstorm_ship/medbay,
		/area/hailstorm_ship/bathroom,
		/area/hailstorm_ship/command_maint,
		/area/hailstorm_ship/captain_cabin,
		/area/hailstorm_ship/captain_quarters,
		/area/hailstorm_ship/advisor_cabin,
		/area/hailstorm_ship/advisor_quarters,
		/area/hailstorm_ship/armory,
		/area/hailstorm_ship/engine_maint,
		/area/hailstorm_ship/engineering,
		/area/hailstorm_ship/propulsion,
		/area/hailstorm_ship/atmospherics,
		/area/hailstorm_ship/docking_arm,
	)
	current_location = "nav_hailstorm_ship_space_dd"
	landmark_transition = "nav_hailstorm_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/hailstorm_ship
	shuttle_name = "Hailstorm Ship (Drydock)"
	landmark_tag = "nav_hailstorm_ship_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/hailstorm_ship_transit
	name = "In transit"
	landmark_tag = "nav_hailstorm_ship_transit_dd"
	base_turf = /turf/space/transit/north
