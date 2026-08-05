/*
 * Drydock Ship -- Unified Sadar Fleet Scout
 * Converted from maps/away/ships/sadar_scout (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/sadar_scout
	name = "Unified Sadar Fleet Scout"
	id = "sadar_scout"
	mappath = "maps/drydock_ships/sadar_scout/sadar_scout.dmm"
	price = 1000000
	bridge_area_type = /area/ship/sadar_scout/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/sadar_scout, /datum/shuttle/autodock/overmap/sadar_shuttle)
	sub_shuttle_tags = list("Modified Salvage Skiff")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/sadar_scout
	name = "Unified Sadar Fleet Scout"
	class = "ICV"
	shuttle = "Unified Sadar Fleet Scout (Drydock)"
	desc = "The Boreas-class is a small and ancient class of expeditionary vessels dating back a couple hundreds years to when it was commissioned by the Solarian Department of Colonization for Colony Fleet SFE-528-RFS - better known now as the Scarab Fleet. Like most scarab ships, this one has been heavily modified with much of necessary equipment retrofitted and superfluous components stripped away."
	icon_state = "freighter"
	moving_state = "freighter_moving"
	colors = list("#8a0f8a", "#a201a2")
	scanimage = "ranger.png"
	designer = "Einstein Engines"
	volume = "62 meters length, 28 meters beam/width, 12 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Extruding starboard-mounted improvised medium caliber armament, port external flight craft bay"
	sizeclass = "Boreas-class Expeditionary Vessel"
	shiptype = "Long-term expeditionary utility"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/obj/effect/overmap/visitable/ship/landable/drydock_ship/sadar_scout/get_skybox_representation()
	var/image/skybox_image = image('icons/skybox/subcapital_ships.dmi', "ranger")
	skybox_image.pixel_x = rand(0,64)
	skybox_image.pixel_y = rand(128,256)
	return skybox_image

/datum/shuttle/autodock/overmap/drydock_ship/sadar_scout
	name = "Unified Sadar Fleet Scout (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/sadar_scout,
		/area/ship/sadar_scout/exterior,
		/area/ship/sadar_scout/thrusters,
		/area/ship/sadar_scout/solars,
		/area/ship/sadar_scout/tools,
		/area/ship/sadar_scout/utility,
		/area/ship/sadar_scout/atmos,
		/area/ship/sadar_scout/mainhall,
		/area/ship/sadar_scout/forehall,
		/area/ship/sadar_scout/eva,
		/area/ship/sadar_scout/hydro,
		/area/ship/sadar_scout/mess,
		/area/ship/sadar_scout/med,
		/area/ship/sadar_scout/crew,
		/area/ship/sadar_scout/bridge,
		/area/ship/sadar_scout/cic,
		/area/ship/sadar_scout/wep,
	)
	current_location = "nav_sadar_scout_space_dd"
	landmark_transition = "nav_sadar_scout_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/sadar_scout
	shuttle_name = "Unified Sadar Fleet Scout (Drydock)"
	landmark_tag = "nav_sadar_scout_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/sadar_scout_transit
	name = "In transit"
	landmark_tag = "nav_sadar_scout_transit_dd"
	base_turf = /turf/space/transit/north
