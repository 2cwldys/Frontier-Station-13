/*
 * Drydock Ship -- Hegemony Corvette
 * Converted from maps/away/ships/hegemony/hegemony_corvette (Bucket B) --
 * see coc_surveyor.dm for the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/hegemony_corvette
	name = "Hegemony Corvette"
	id = "hegemony_corvette"
	mappath = "maps/drydock_ships/hegemony_corvette/hegemony_corvette.dmm"
	price = 0
	bridge_area_type = /area/hegemony_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/hegemony_corvette)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/hegemony_corvette
	name = "Hegemony Corvette"
	class = "HMV"
	shuttle = "Hegemony Corvette (Drydock)"
	desc = "The Foundation-class corvette is the backbone of the Izweski Hegemony Navy, especially as many of their larger ships cannot operate without ready supplies of phoron. Under Not'zar's reign, Foundation-class vessels are often seen patrolling the Badlands and Sparring Sea, to secure Izweski trade routes against pirate incursion."
	icon_state = "foundation"
	moving_state = "foundation-moving"
	colors = list("#e38222", "#f0ba3e")
	scanimage = "hegemony_corvette.png"
	designer = "Hephaestus Industries, Izweski Hegemonic Naval Guilds"
	volume = "75 meters length, 35 meters beam/width, 21 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding medium-caliber ballistic armament, port obscured flight craft bay"
	sizeclass = "Foundation-class corvette"
	shiptype = "Military patrol and anti-pirate operation."
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/obj/effect/overmap/visitable/ship/landable/drydock_ship/hegemony_corvette/get_skybox_representation()
	var/image/skybox_image = image('icons/skybox/subcapital_ships.dmi', "hegemony_corvette")
	skybox_image.pixel_x = rand(0,64)
	skybox_image.pixel_y = rand(128,256)
	return skybox_image

/datum/shuttle/autodock/overmap/drydock_ship/hegemony_corvette
	name = "Hegemony Corvette (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/hegemony_ship,
		/area/hegemony_ship/bridge,
		/area/hegemony_ship/engineering,
		/area/hegemony_ship/port_propulsion,
		/area/hegemony_ship/starboard_propulsion,
		/area/hegemony_ship/temple,
		/area/hegemony_ship/warpriests_quarters,
		/area/hegemony_ship/gunnery_foyer,
		/area/hegemony_ship/ammo_storage,
		/area/hegemony_ship/gun_deck_bruiser,
		/area/hegemony_ship/atmos_waste,
		/area/hegemony_ship/atmos_distro,
		/area/hegemony_ship/tcomms,
		/area/hegemony_ship/canteen,
		/area/hegemony_ship/aux_cic,
		/area/hegemony_ship/medbay,
		/area/hegemony_ship/crew_quarters,
		/area/hegemony_ship/trophy_room,
		/area/hegemony_ship/restroom,
		/area/hegemony_ship/docking_port,
		/area/hegemony_ship/captains_quarters,
		/area/hegemony_ship/brig,
		/area/hegemony_ship/eva_storage,
		/area/hegemony_ship/armory,
		/area/hegemony_ship/gun_deck_flak,
	)
	current_location = "nav_hegemony_corvette_space_dd"
	landmark_transition = "nav_hegemony_corvette_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/hegemony_corvette
	shuttle_name = "Hegemony Corvette (Drydock)"
	landmark_tag = "nav_hegemony_corvette_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/hegemony_corvette_transit
	name = "In transit"
	landmark_tag = "nav_hegemony_corvette_transit_dd"
	base_turf = /turf/space/transit/north
