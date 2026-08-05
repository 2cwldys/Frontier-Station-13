/*
 * Drydock Ship -- Orion Express Mining Skiff
 * Converted from maps/away/ships/orion/orion_miner (Bucket A, already a
 * fully flyable/dockable away-site craft) -- see lone_spacer.dm for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/orion_miner
	name = "Orion Express Mining Skiff"
	id = "orion_miner"
	mappath = "maps/drydock_ships/orion_miner/orion_miner.dmm"
	price = 1000000
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/orion_miner)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/orion_miner
	name = "Orion Express Mining Skiff (Landable)"
	class = "OEV"
	shuttle = "Orion Express Mining Skiff (Drydock)"
	desc = "The Argon-class mining skiff is a workhorse of Orion Express's mining division. It is a small but dependable atmospheric-capable skiff designed to land on or dock near asteroids, planets and other places and conduct all manner of mining, salvage, or extraction operations."
	icon_state = "corvette"
	moving_state = "corvette_moving"
	color = COLOR_BROWN
	colors = list(COLOR_BROWN)
	max_speed = 1/(2 SECONDS)
	burn_delay = 2 SECONDS
	vessel_mass = 6000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH
	designer = "Orion Express"
	volume = "40 meters length, 20 meters beam/width, 7 meters vertical height"
	drive = "Medium-Speed Warp Acceleration FTL Drive"
	weapons = "Starboard Grauwolf-type flak cannon"
	sizeclass = "Argon-class Miner"
	shiptype = "Multipurpose mining and salvage"

/obj/effect/overmap/visitable/ship/landable/drydock_ship/orion_miner/New()
	designation = "[pick("Charming", "Endearing", "Rusted", "Lucky", "Unlucky", "Unrelenting", "Unfortunate", "Definitive", "Difficult", "Fiery", "Willful", "Broke", "Aerial", "Starborn", "Unreal", "Orion", "Stellar", "Astral", "Flying", "Nautical ", "Miner's", "Wayward", "Duct-Taped", "Sort-of", "Barely", "Negative")] \
	[pick("Reality", "Dreamer", "Regrets", "Boltbucket", "Wayfarer", "Trailblazer", "Overtime", "Gizmo", "Express", "Deity", "Diamond", "Miner", "Skiff of Skiffs", "Wallop", "Express", "Courier", "Coal", "Pitchblende", "Ore", "Activated Charcoal", "Plywood", "Luck", "Profit", "Write-off")]"
	..()

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/orion_miner
	shuttle_tag = "Orion Express Mining Skiff (Drydock)"

/datum/shuttle/autodock/overmap/drydock_ship/orion_miner
	name = "Orion Express Mining Skiff (Drydock)"
	move_time = 20
	range = 2
	fuel_consumption = 2
	shuttle_area = list(
		/area/shuttle/orion_miner/exterior,
		/area/shuttle/orion_miner/bridge,
		/area/shuttle/orion_miner/mining_prep,
		/area/shuttle/orion_miner/grauwolf,
		/area/shuttle/orion_miner/ammo_storage,
		/area/shuttle/orion_miner/mess_hall,
		/area/shuttle/orion_miner/corridor,
		/area/shuttle/orion_miner/corridor/central,
		/area/shuttle/orion_miner/corridor/vestibule,
		/area/shuttle/orion_miner/corridor/aft,
		/area/shuttle/orion_miner/cargo_bay,
		/area/shuttle/orion_miner/medbay,
		/area/shuttle/orion_miner/eva,
		/area/shuttle/orion_miner/dorm,
		/area/shuttle/orion_miner/bathroom,
		/area/shuttle/orion_miner/hydro,
		/area/shuttle/orion_miner/main_engineering_port,
		/area/shuttle/orion_miner/main_engineering_stbd,
		/area/shuttle/orion_miner/tech_storage,
		/area/shuttle/orion_miner/reactor,
	)
	current_location = "nav_orion_miner_space_dd"
	dock_target = "orion_miner"
	landmark_transition = "nav_orion_miner_transit_dd"
	logging_home_tag = "nav_orion_miner_space_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/orion_miner
	name = "Open Space"
	shuttle_name = "Orion Express Mining Skiff (Drydock)"
	landmark_tag = "nav_orion_miner_space_dd"

/obj/effect/shuttle_landmark/drydock_ship/orion_miner_transit
	name = "In transit"
	landmark_tag = "nav_orion_miner_transit_dd"
	base_turf = /turf/space
