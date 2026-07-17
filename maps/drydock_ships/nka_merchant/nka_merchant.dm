/*
 * Drydock Ship -- Her Majesty's Mercantile Flotilla Ship
 * Converted from maps/away/ships/nka/nka_merchant (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/nka_merchant
	name = "Her Majesty's Mercantile Flotilla Ship"
	id = "nka_merchant"
	mappath = "maps/drydock_ships/nka_merchant/nka_merchant.dmm"
	price = 0
	bridge_area_type = /area/nka_merchant/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/nka_merchant)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/nka_merchant
	name = "Her Majesty's Mercantile Flotilla Ship"
	desc = "The Hma'trra class is a modified version of the corporate freighter sold by the SCC to the New Kingdom. It is simple model adapted to the long journey between Adhomai and Tau Ceti."
	class = "NKAMV"
	shuttle = "Her Majesty's Mercantile Flotilla Ship (Drydock)"
	icon_state = "hmatrra"
	moving_state = "hmatrra_moving"
	colors = list("#3e9af0", "#2b5cff")
	vessel_mass = 10000
	max_speed = 1/(2 SECONDS)
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	scanimage = "nka_freighter.png"
	designer = "NanoTrasen, New Kingdom of Adhomai"
	volume = "49 meters length, 28 meters beam/width, 11 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Not apparent, port obscured flight craft bay"
	sizeclass = "Hma'trra Freighter"
	shiptype = "Long-term shipping utilities"

/obj/effect/overmap/visitable/ship/landable/drydock_ship/nka_merchant/get_skybox_representation()
	var/image/skybox_image = image('icons/skybox/subcapital_ships.dmi', "nka_freighter")
	skybox_image.pixel_x = rand(0,64)
	skybox_image.pixel_y = rand(128,256)
	return skybox_image

/datum/shuttle/autodock/overmap/drydock_ship/nka_merchant
	name = "Her Majesty's Mercantile Flotilla Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/nka_merchant,
		/area/nka_merchant/hangar,
		/area/nka_merchant/barracks,
		/area/nka_merchant/captain_quarters,
		/area/nka_merchant/engineering,
		/area/nka_merchant/engine,
		/area/nka_merchant/bridge,
		/area/nka_merchant/warehouse,
		/area/nka_merchant/merchant,
		/area/nka_merchant/mess,
		/area/nka_merchant/eva,
	)
	current_location = "nav_nka_merchant_space_dd"
	landmark_transition = "nav_nka_merchant_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/nka_merchant
	shuttle_name = "Her Majesty's Mercantile Flotilla Ship (Drydock)"
	landmark_tag = "nav_nka_merchant_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/nka_merchant_transit
	name = "In transit"
	landmark_tag = "nav_nka_merchant_transit_dd"
	base_turf = /turf/space/transit/north
