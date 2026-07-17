/*
 * Drydock Ship -- Merchants' Guild Freighter
 * Converted from maps/away/ships/hegemony/merchants_guild (Bucket B) -- see
 * coc_surveyor.dm for the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/merchants_guild
	name = "Merchants' Guild Freighter"
	id = "merchants_guild"
	mappath = "maps/drydock_ships/merchants_guild/merchant_freighter.dmm"
	price = 0
	bridge_area_type = /area/merchants_guild/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/merchants_guild)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/merchants_guild
	name = "Merchants' Guild Freighter"
	desc = "The Azkrazal-class freighter is a common civilian design from the Izweski Hegemony's shipbuilding guilds, designed in collaberation with Hephaestus Industries. They are mostly found in the possession of Unathi guilds, as well as the occasional smuggler or pirate fleet."
	class = "IHGV"
	shuttle = "Merchants' Guild Freighter (Drydock)"
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("5a189a")
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	scanimage = "unathi_freighter2.png"
	designer = "Hephaestus Industries, Izweski Hegemonic Naval Guilds"
	volume = "65 meters length, 35 meters beam/width, 18 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Not apparent, starboard obscured flight craft bay"
	sizeclass = "Azkrazal-class cargo freighter"
	shiptype = "Long-term shipping utilities"

/obj/effect/overmap/visitable/ship/landable/drydock_ship/merchants_guild/get_skybox_representation()
	var/image/skybox_image = image('icons/skybox/subcapital_ships.dmi', "unathi_freighter2")
	skybox_image.pixel_x = rand(0,64)
	skybox_image.pixel_y = rand(128,256)
	return skybox_image

/datum/shuttle/autodock/overmap/drydock_ship/merchants_guild
	name = "Merchants' Guild Freighter (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/merchants_guild,
		/area/merchants_guild/hangar,
		/area/merchants_guild/crew,
		/area/merchants_guild/captain,
		/area/merchants_guild/portengine,
		/area/merchants_guild/starboardengine,
		/area/merchants_guild/warehouse,
		/area/merchants_guild/office,
		/area/merchants_guild/canteen,
		/area/merchants_guild/armory,
		/area/merchants_guild/eva,
		/area/merchants_guild/bridge,
	)
	current_location = "merchantsguild_nav_space_dd"
	landmark_transition = "merchantsguild_nav_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/merchants_guild
	shuttle_name = "Merchants' Guild Freighter (Drydock)"
	landmark_tag = "merchantsguild_nav_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/merchants_guild_transit
	name = "In transit"
	landmark_tag = "merchantsguild_nav_transit_dd"
	base_turf = /turf/space/transit/north
