/*
 * Drydock Ship -- Adhomian Traveling Circus
 * Converted from maps/away/ships/tajara/circus/adhomian_circus.dmm (Bucket
 * B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the
 * general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/adhomian_circus
	name = "Adhomian Traveling Circus"
	id = "adhomian_circus_ship"
	mappath = "maps/drydock_ships/tajara_circus/adhomian_circus.dmm"
	price = 1000000
	bridge_area_type = /area/adhomian_circus/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/adhomian_circus, /datum/shuttle/autodock/overmap/adhomian_circus_shuttle)
	sub_shuttle_tags = list("Adhomian Circus Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/adhomian_circus
	name = "Adhomian Traveling Circus"
	class = "ACV"
	shuttle = "Adhomian Traveling Circus (Drydock)"
	desc = "The N'hanzafu class is a bulky Adhomian freighter designed with a large crew and cargo in mind. This one is painted in bright colors."
	icon_state = "generic"
	moving_state = "generic_moving"
	scanimage = "tramp_freighter.png"
	designer = "Independent/no designation"
	volume = "60 meters length, 27 meters beam/width, 20 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Not apparent"
	sizeclass = "Hanzafu Freighter"
	shiptype = "Long-term shipping utilities"
	colors = list(COLOR_CYAN, COLOR_WARM_YELLOW, COLOR_PALE_BTL_GREEN, COLOR_HOT_PINK)
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/adhomian_circus
	name = "Adhomian Traveling Circus (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/adhomian_circus,
		/area/adhomian_circus/port,
		/area/adhomian_circus/starboard,
		/area/adhomian_circus/bridge,
		/area/adhomian_circus/crew,
		/area/adhomian_circus/fortune,
		/area/adhomian_circus/clown,
		/area/adhomian_circus/tamer,
		/area/adhomian_circus/maintenance,
		/area/adhomian_circus/engine,
		/area/adhomian_circus/engine/port,
		/area/adhomian_circus/hangar,
	)
	current_location = "nav_adhomian_circus_space_dd"
	landmark_transition = "nav_adhomian_circus_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/adhomian_circus
	shuttle_name = "Adhomian Traveling Circus (Drydock)"
	landmark_tag = "nav_adhomian_circus_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/adhomian_circus_transit
	name = "In transit"
	landmark_tag = "nav_adhomian_circus_transit_dd"
	base_turf = /turf/space/transit/north
