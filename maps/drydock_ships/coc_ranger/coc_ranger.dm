/*
 * Drydock Ship -- Ranger Gunboat
 * Converted from maps/away/ships/coc/coc_ranger/coc_ship.dmm (Bucket B) --
 * see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/ranger_corvette
	name = "Ranger Gunboat"
	id = "ranger_corvette_dd"
	mappath = "maps/drydock_ships/coc_ranger/coc_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/ranger_corvette/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/ranger_corvette)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/ranger_corvette
	name = "Ranger Gunboat"
	class = "FPBS"
	desc = "The Xansan-class is not, in fact, a distinct design in of itself. It is instead Xanu Prime's variant of the Lagos-class gunboat, a Solarian light attack ship design. The Rangers make use of the craft to this day, in spite of their advanced age."
	icon_state = "xansan"
	moving_state = "xansan_moving"
	colors = list("#8492fd", "#4d61fc")
	scanimage = "ranger.png"
	designer = "Coalition of Colonies, Xanu Prime"
	volume = "65 meters length, 31 meters beam/width, 14 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding starboard-mounted medium caliber ballistic armament, starboard obscured flight craft bay"
	sizeclass = "Xansan-class Gunboat"
	shiptype = "Military patrol and combat utility"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/ranger_corvette
	name = "Ranger Gunboat (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/ranger_corvette,
		/area/ship/ranger_corvette/bridge,
		/area/ship/ranger_corvette/janitor,
		/area/ship/ranger_corvette/crew,
		/area/ship/ranger_corvette/leader,
		/area/ship/ranger_corvette/foyer,
		/area/ship/ranger_corvette/telecomms,
		/area/ship/ranger_corvette/brig,
		/area/ship/ranger_corvette/medbay,
		/area/ship/ranger_corvette/munitions,
		/area/ship/ranger_corvette/gunnery,
		/area/ship/ranger_corvette/bathroom,
		/area/ship/ranger_corvette/cryo,
		/area/ship/ranger_corvette/engine1,
		/area/ship/ranger_corvette/engine2,
		/area/ship/ranger_corvette/voidsuits,
		/area/ship/ranger_corvette/atmospherics,
		/area/ship/ranger_corvette/canteen,
		/area/ship/ranger_corvette/engineering,
	)
	current_location = "nav_ranger_corvette_space_dd"
	landmark_transition = "nav_ranger_corvette_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/ranger_corvette
	shuttle_name = "Ranger Gunboat (Drydock)"
	landmark_tag = "nav_ranger_corvette_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/ranger_corvette_transit
	name = "In transit"
	landmark_tag = "nav_ranger_corvette_transit_dd"
	base_turf = /turf/space/transit/north
