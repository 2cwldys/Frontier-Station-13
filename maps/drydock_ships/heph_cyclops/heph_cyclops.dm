/*
 * Drydock Ship -- Cyclops Mining Vessel
 * Converted from maps/away/ships/heph/cyclops/cyclops.dmm (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/cyclops_mining
	name = "Cyclops Mining Vessel"
	id = "cyclops_mining_dd"
	mappath = "maps/drydock_ships/heph_cyclops/cyclops.dmm"
	price = 0
	bridge_area_type = /area/hephmining_ship/cyclops/cyclops_bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/cyclops_mining)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/cyclops_mining
	name = "Cyclops Mining Vessel"
	class = "HCV"
	shuttle = "Cyclops Mining Vessel (Drydock)"
	desc = "This bulky vessel is designed and operated by Hephaestus Industries. From asteroid cracking to planetary operations, this ship can do it all."
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#BAB86C", "#8B4000")
	designer = "Hephaestus Industries"
	weapons = "Not apparent"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	sizeclass = "Cyclops Mining Freighter"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/cyclops_mining
	name = "Cyclops Mining Vessel (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/hephmining_ship/cyclops,
		/area/hephmining_ship/cyclops/cyclops_bridge,
		/area/hephmining_ship/cyclops/cyclops_captain,
		/area/hephmining_ship/cyclops/cyclops_kitchen,
		/area/hephmining_ship/cyclops/cyclops_vault,
		/area/hephmining_ship/cyclops/cyclops_barracks,
		/area/hephmining_ship/cyclops/cyclops/bathroom,
		/area/hephmining_ship/cyclops/cyclops_hangar,
		/area/hephmining_ship/cyclops/cyclops_engineering,
		/area/hephmining_ship/cyclops/cyclops_starboard_thrust,
		/area/hephmining_ship/cyclops/cyclops_port_thrust,
	)
	current_location = "nav_cyclops_mining_space_dd"
	landmark_transition = "nav_cyclops_mining_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/cyclops_mining
	shuttle_name = "Cyclops Mining Vessel (Drydock)"
	landmark_tag = "nav_cyclops_mining_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/cyclops_mining_transit
	name = "In transit"
	landmark_tag = "nav_cyclops_mining_transit_dd"
	base_turf = /turf/space/transit/north
