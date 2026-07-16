/*
 * Drydock Ship -- SPLF Auxiliary Vessel
 * Converted from maps/away/ships/sol/sol_splf/splf_raider.dmm (Bucket B) --
 * see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/splf_raider
	name = "SPLF Auxiliary Vessel"
	id = "splf_raider"
	mappath = "maps/drydock_ships/sol_splf/splf_raider.dmm"
	price = 0
	bridge_area_type = /area/splf_raider/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/splf_raider)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/splf_raider
	name = "SPLF Auxiliary Vessel"
	class = "SPLFV"
	desc = "The Laksamana-class hauling vessel is a relatively unusual sighting in the wider spur, native almost exclusively to the shipyards of Hang Tuah's Rest and the surrounding space. This one appears to have been substantially modified, boasting a heavily armed gunnery pod slotted into its starboard cargo pod port."
	icon_state = "freighter"
	moving_state = "freighter_moving"
	colors = list("#5a644e", "#6a7e53")
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	scanimage = "tramp_freighter.png"
	designer = "Einstein Engines, Hang Tuah's Rest Orbital Shipyards"
	volume = "50 meters length, 36 meters beam/width, 13 meters vertical height"
	weapons = "Heavily modified ballistic gunnery pod starboard, shuttle bay portside"
	sizeclass = "Laksamana-class hauler"
	shiptype = "Remote hauling operations, long-term crew habitation"

/datum/shuttle/autodock/overmap/drydock_ship/splf_raider
	name = "SPLF Auxiliary Vessel (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/splf_raider,
		/area/splf_raider/central,
		/area/splf_raider/lounge,
		/area/splf_raider/medical,
		/area/splf_raider/kitchen,
		/area/splf_raider/freezer,
		/area/splf_raider/docking,
		/area/splf_raider/bridge,
		/area/splf_raider/office,
		/area/splf_raider/quarters,
		/area/splf_raider/ready,
		/area/splf_raider/starboard_slot,
		/area/splf_raider/portside_slot,
		/area/splf_raider/gunnery,
		/area/splf_raider/cargo_1,
		/area/splf_raider/cargo_2,
		/area/splf_raider/washroom,
		/area/splf_raider/closet,
		/area/splf_raider/starboard_hall,
		/area/splf_raider/portside_hall,
		/area/splf_raider/engine,
		/area/splf_raider/propulsion,
	)
	current_location = "nav_splf_raider_space_dd"
	landmark_transition = "nav_splf_raider_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/splf_raider
	shuttle_name = "SPLF Auxiliary Vessel (Drydock)"
	landmark_tag = "nav_splf_raider_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/splf_raider_transit
	name = "In transit"
	landmark_tag = "nav_splf_raider_transit_dd"
	base_turf = /turf/space/transit/north
