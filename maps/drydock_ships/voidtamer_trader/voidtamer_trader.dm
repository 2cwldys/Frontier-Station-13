/*
 * Drydock Ship -- Voidtamer Trade Ship
 * Converted from maps/away/ships/voidtamer/trader/voidtamer_trader.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/voidtamer_trader
	name = "Voidtamer Trade Ship"
	id = "voidtamer_trade_ship_dd"
	mappath = "maps/drydock_ships/voidtamer_trader/voidtamer_trader.dmm"
	price = 1000000
	bridge_area_type = /area/voidtamer/trader/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/voidtamer_trader, /datum/shuttle/autodock/overmap/voidtamer_trade_ship_shuttle)
	sub_shuttle_tags = list("Voidtamer Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/voidtamer_trader
	name = "Voidtamer Trade Ship"
	desc = "A trade ship of the Voidtamer Conflux. While far from being built for combat, the vessel is outfitted for self-defense against space fauna and potentially hostile ships. The vessel is loaded for trade, looking for various ports and ships to trade at."
	class = "VCV"
	shuttle = "Voidtamer Trade Ship (Drydock)"
	icon_state = "asteroid_cluster"
	moving_state = "asteroid_cluster_moving"
	colors = list("#9900FF")
	designer = "Obfuscated, hull origin uncertain"
	volume = "Unknown"
	drive = "Unknown"
	weapons = "Unknown"
	sizeclass = "Unknown"
	shiptype = "Unknown"
	vessel_mass = 12000
	max_speed = 1/(2 SECONDS)
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/voidtamer_trader
	name = "Voidtamer Trade Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/voidtamer/trader,
		/area/voidtamer/trader/bridge,
		/area/voidtamer/trader/warehouse,
		/area/voidtamer/trader/autocannon_gun,
		/area/voidtamer/trader/mining_blaster,
		/area/voidtamer/trader/crew,
		/area/voidtamer/trader/armory,
		/area/voidtamer/trader/temple,
		/area/voidtamer/trader/kitchen,
		/area/voidtamer/trader/supermatter,
		/area/voidtamer/trader/mining,
		/area/voidtamer/trader/dock,
		/area/voidtamer/trader/engineering,
		/area/voidtamer/trader/engineering/starboard,
		/area/voidtamer/trader/engineering/port,
		/area/voidtamer/trader/exterior,
	)
	current_location = "nav_voidtamer_trade_ship_space_dd"
	landmark_transition = "nav_voidtamer_trade_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/voidtamer_trade_ship
	shuttle_name = "Voidtamer Trade Ship (Drydock)"
	landmark_tag = "nav_voidtamer_trade_ship_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/voidtamer_trade_ship_transit
	name = "In transit"
	landmark_tag = "nav_voidtamer_trade_ship_transit_dd"
	base_turf = /turf/space/transit/north
