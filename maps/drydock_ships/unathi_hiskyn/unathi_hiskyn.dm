/*
 * Drydock Ship -- Hiskyn's Revanchists Ship
 * Converted from maps/away/ships/unathi_pirate/hiskyn/unathi_pirate_hiskyn.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/hiskyn
	name = "Hiskyn's Revanchists Ship"
	id = "hiskyn_revanchists"
	mappath = "maps/drydock_ships/unathi_hiskyn/unathi_pirate_hiskyn.dmm"
	price = 1000000
	bridge_area_type = /area/hiskyn_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/hiskyn, /datum/shuttle/autodock/overmap/hiskyn_shuttle)
	sub_shuttle_tags = list("Hiskyn's Revanchist Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/hiskyn
	name = "Hiskyn's Revanchists Ship"
	desc = "An Obrirava-class tanker, commonly used for transport of Helium-3 and other valuable gases by the Empire of Dominia. This one appears to have been heavily modified, with most of its fuel tanks seemingly removed and replaced based on initial scans."
	class = "ICV"
	shuttle = "Hiskyn's Revanchists Ship (Drydock)"
	icon_state = "freighter"
	moving_state = "freighter_moving"
	colors = list("#9c0101")
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL
	designer = "Zhurong Imperial Shipbuilding, Zavodskoi Interstellar"
	volume = "65 meters length, 25 meters beam/width, 18 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual wingtip-mounted heavy ballistic, port obscured flight craft bay"
	sizeclass = "Modified Obrirava-class tanker"
	shiptype = "Unknown"

/datum/shuttle/autodock/overmap/drydock_ship/hiskyn
	name = "Hiskyn's Revanchists Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/hiskyn_ship,
		/area/hiskyn_ship/bridge,
		/area/hiskyn_ship/hallf,
		/area/hiskyn_ship/hallc,
		/area/hiskyn_ship/blaster,
		/area/hiskyn_ship/francisca,
		/area/hiskyn_ship/crew,
		/area/hiskyn_ship/captain,
		/area/hiskyn_ship/bathroom,
		/area/hiskyn_ship/cargobay,
		/area/hiskyn_ship/trophy,
		/area/hiskyn_ship/medbay,
		/area/hiskyn_ship/cic,
		/area/hiskyn_ship/engineering,
		/area/hiskyn_ship/thrustp,
		/area/hiskyn_ship/thrusts,
		/area/hiskyn_ship/armory,
	)
	current_location = "nav_hiskyn_space_dd"
	landmark_transition = "nav_hiskyn_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/hiskyn
	shuttle_name = "Hiskyn's Revanchists Ship (Drydock)"
	landmark_tag = "nav_hiskyn_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/hiskyn_transit
	name = "In transit"
	landmark_tag = "nav_hiskyn_transit_dd"
	base_turf = /turf/space/transit/north
