/*
 * Drydock Ship -- Water Barge
 * Converted from maps/away/ships/konyang/water_barge (Bucket B) -- see
 * coc_surveyor.dm for the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/water_barge
	name = "Water Barge"
	id = "water_barge"
	mappath = "maps/drydock_ships/water_barge/water_barge.dmm"
	price = 1000000
	bridge_area_type = /area/water_barge/helm
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/water_barge, /datum/shuttle/autodock/overmap/water_barge_shuttle)
	sub_shuttle_tags = list("Water Barge Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/water_barge
	name = "Water Barge"
	class = "PCV"
	shuttle = "Water Barge (Drydock)"
	desc = "The Shelfer-class cargo transport is a common sight in the shipyards of Konyang - designed by Einstein Engines and frequently used by Konyang corporations for long-distance cargo hauling throughout the Orion Spur."
	icon_state = "freighter"
	moving_state = "freighter_moving"
	designer = "Einstein Engines"
	volume = "75 meters length, 55 meters beam/width, 21 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "No weapons detected"
	sizeclass = "Shelfer-class cargo transport"
	shiptype = "Long-distance cargo hauling"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 8000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/water_barge
	name = "Water Barge (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/water_barge,
		/area/water_barge/helm,
		/area/water_barge/hangar,
		/area/water_barge/mainhallway,
		/area/water_barge/medbay,
		/area/water_barge/engineering,
		/area/water_barge/fuelbay,
		/area/water_barge/toolstorage,
		/area/water_barge/cargo,
		/area/water_barge/dockingport,
		/area/water_barge/dockingport/port,
		/area/water_barge/office,
		/area/water_barge/breakroom,
		/area/water_barge/bathroom,
		/area/water_barge/cryo,
		/area/water_barge/thrust,
		/area/water_barge/thrust/port,
		/area/water_barge/quarters,
	)
	current_location = "nav_water_barge_space_dd"
	landmark_transition = "nav_water_barge_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/water_barge
	shuttle_name = "Water Barge (Drydock)"
	landmark_tag = "nav_water_barge_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/water_barge_transit
	name = "In transit"
	landmark_tag = "nav_water_barge_transit_dd"
	base_turf = /turf/space/transit/north
