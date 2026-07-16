/*
 * Drydock Ship -- SCC Scout Ship
 * Converted from maps/away/ships/scc/scc_scout_ship.dmm (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/scc_scout_ship
	name = "SCC Scout Ship"
	id = "scc_scout_ship"
	mappath = "maps/drydock_ships/scc_scout_ship/scc_scout_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/scc_scout_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/scc_scout_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/scc_scout_ship
	name = "SCC Scout Ship"
	class = "SCCV"
	desc = "A small ship commonly fielded by the Stellar Corporate Conglomerate, the Serendipity-class, Hephaestus-designed and produced. It is supposed to be a small platform, entirely self-sufficient general-purpose scouting and surveying ship, the Serendipity is equipped with both a bluespace and a warp drive and two different engines."
	icon_state = "corvette"
	moving_state = "corvette_moving"
	colors = list("#cfd4ff", "#78adf8")
	designer = "Hephaestus Industries"
	volume = "42 meters length, 48 meters beam/width, 23 meters vertical height"
	drive = "First-Gen Warp Capable, Hybrid Phoron Bluespace Drive"
	propulsion = "Superheated Composite Gas Thrust"
	weapons = "Flak battery"
	sizeclass = "Serendipity-class Scout Ship"
	shiptype = "Multi-purpose scout"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/scc_scout_ship
	name = "SCC Scout Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/scc_scout_ship,
		/area/ship/scc_scout_ship/bridge,
		/area/ship/scc_scout_ship/hydroponics,
		/area/ship/scc_scout_ship/quarters,
		/area/ship/scc_scout_ship/mess,
		/area/ship/scc_scout_ship/medbay,
		/area/ship/scc_scout_ship/eva,
		/area/ship/scc_scout_ship/engineering_cargo,
		/area/ship/scc_scout_ship/maint_power,
		/area/ship/scc_scout_ship/maint_atmos,
		/area/ship/scc_scout_ship/maint_propulsion_starboard,
		/area/ship/scc_scout_ship/maint_propulsion_port,
		/area/ship/scc_scout_ship/exterior,
	)
	current_location = "nav_scc_scout_ship_space_dd"
	landmark_transition = "nav_scc_scout_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/scc_scout_ship
	shuttle_name = "SCC Scout Ship (Drydock)"
	landmark_tag = "nav_scc_scout_ship_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/scc_scout_ship_transit
	name = "In transit"
	landmark_tag = "nav_scc_scout_ship_transit_dd"
	base_turf = /turf/space/transit/north
