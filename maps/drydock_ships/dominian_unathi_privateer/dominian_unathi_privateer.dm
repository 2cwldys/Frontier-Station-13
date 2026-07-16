/*
 * Drydock Ship -- Kazhkz Privateer Ship
 * Converted from maps/away/ships/dominia/dominian_unathi_privateer (Bucket
 * B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/dominian_unathi
	name = "Kazhkz Privateer Ship"
	id = "dominian_unathi_dd"
	mappath = "maps/drydock_ships/dominian_unathi_privateer/dominian_unathi_privateer.dmm"
	price = 0
	bridge_area_type = /area/ship/dominian_unathi/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/dominian_unathi)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/dominian_unathi
	name = "Kazhkz Privateer Ship"
	class = "ICV"
	desc = "A Dragoon-class corvette - the predecessor to the Empire of Dominia's modern Lammergier-class. Though these once served a similar role in the early days of the Imperial Fleet, they have since been entirely decomissioned in favor of the Lammergier. This one's IFF marks it as a civilian vessel, of no specific affiliation."
	icon_state = "dragoon"
	moving_state = "dragoon_moving"
	colors = list("#e67f09", "#fcf9f5")
	designer = "Zhurong Naval Arsenal, Empire of Dominia"
	volume = "54 meters length, 25 meters beam/width, 17 meters vertical height"
	sizeclass = "Dragoon-class corvette"
	shiptype = "Long-distance patrol and scouting action"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Port wingtip-mounted extruding medium-caliber ballistic armament, starboard obscured flight craft bay"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/dominian_unathi
	name = "Kazhkz Privateer Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/dominian_unathi,
		/area/ship/dominian_unathi/bridge,
		/area/ship/dominian_unathi/bridgefoyer,
		/area/ship/dominian_unathi/engineering,
		/area/ship/dominian_unathi/portthrust,
		/area/ship/dominian_unathi/starboardthrust,
		/area/ship/dominian_unathi/porthall,
		/area/ship/dominian_unathi/starboardhall,
		/area/ship/dominian_unathi/armory,
		/area/ship/dominian_unathi/eva,
		/area/ship/dominian_unathi/hangar,
		/area/ship/dominian_unathi/gun,
		/area/ship/dominian_unathi/chapel,
		/area/ship/dominian_unathi/crew,
		/area/ship/dominian_unathi/captain,
		/area/ship/dominian_unathi/canteen,
		/area/ship/dominian_unathi/cic,
		/area/ship/dominian_unathi/loot,
		/area/ship/dominian_unathi/med,
		/area/ship/dominian_unathi/pods,
		/area/ship/dominian_unathi/janitor,
		/area/ship/dominian_unathi/toilet,
		/area/ship/dominian_unathi/storage,
		/area/ship/dominian_unathi/dock,
	)
	current_location = "nav_dominian_unathi_space_dd"
	landmark_transition = "nav_dominian_unathi_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/dominian_unathi
	shuttle_name = "Kazhkz Privateer Ship (Drydock)"
	landmark_tag = "nav_dominian_unathi_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/dominian_unathi_transit
	name = "In transit"
	landmark_tag = "nav_dominian_unathi_transit_dd"
	base_turf = /turf/space/transit/north
