/*
 * Drydock Ship -- Freebooter Ship
 * Converted from maps/away/ships/freebooter/freebooter_ship (Bucket B) --
 * see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/freebooter_ship
	name = "Freebooter Ship"
	id = "freebooter_ship_dd"
	mappath = "maps/drydock_ships/freebooter_ship/freebooter_ship_.dmm"
	price = 0
	bridge_area_type = /area/ship/freebooter_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/freebooter_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/freebooter_ship
	name = "Freebooter Ship"
	class = "ICV"
	desc = "One of the most common sights in the Orion Spur, even outside of human space, is the Hephaestus-produced Ox-class freighter. Designed to haul significant amounts of cargo on well-charted routes between civilized systems."
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	scanimage = "tramp_freighter.png"
	designer = "Hephaestus Industries"
	volume = "41 meters length, 43 meters beam/width, 19 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Duel improvised weapon arrays, port landing pad"
	sizeclass = "Ox-class Modular Freighter"
	shiptype = "Multi-purpose freight"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/freebooter_ship
	name = "Freebooter Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/freebooter_ship,
		/area/ship/freebooter_ship/foyer,
		/area/ship/freebooter_ship/gunnery,
		/area/ship/freebooter_ship/ammo,
		/area/ship/freebooter_ship/gunneryentrance,
		/area/ship/freebooter_ship/bridge,
		/area/ship/freebooter_ship/forehallway,
		/area/ship/freebooter_ship/forehallwayport,
		/area/ship/freebooter_ship/closet,
		/area/ship/freebooter_ship/cryo,
		/area/ship/freebooter_ship/dorms,
		/area/ship/freebooter_ship/lockers,
		/area/ship/freebooter_ship/head,
		/area/ship/freebooter_ship/medical,
		/area/ship/freebooter_ship/pod1,
		/area/ship/freebooter_ship/pod2,
		/area/ship/freebooter_ship/pod3,
		/area/ship/freebooter_ship/pod4,
		/area/ship/freebooter_ship/pod5,
		/area/ship/freebooter_ship/pod6,
		/area/ship/freebooter_ship/pod7,
		/area/ship/freebooter_ship/pod8,
		/area/ship/freebooter_ship/thruster1,
		/area/ship/freebooter_ship/thruster2,
		/area/ship/freebooter_ship/engineering,
		/area/ship/freebooter_ship/exterior,
	)
	current_location = "nav_freebooter_ship_space_dd"
	landmark_transition = "nav_freebooter_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/freebooter_ship
	shuttle_name = "Freebooter Ship (Drydock)"
	landmark_tag = "nav_freebooter_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/freebooter_ship_transit
	name = "In transit"
	landmark_tag = "nav_freebooter_ship_transit_dd"
	base_turf = /turf/space/transit/north
