/*
 * Drydock Ship -- Private Yacht
 * Converted from maps/away/ships/yacht/yacht.dmm (Bucket B -- one of the two
 * fully static hulls with zero shuttle scaffolding of any kind in the source
 * directory, fitting its derelict/mystery flavor) -- see coc_surveyor.dm
 * (maps/drydock_ships/coc_surveyor/) for the general conversion
 * approach/rationale.
 */

/datum/map_template/drydock_ship/yacht
	name = "Private Yacht"
	id = "drydock_yacht"
	mappath = "maps/drydock_ships/yacht/yacht.dmm"
	price = 0
	bridge_area_type = /area/shuttle/yacht/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/yacht)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/yacht
	name = "Private Yacht"
	desc = "A private pleasure yacht. The design appears to be from the Idris Incorporated 'Starfarer' line."
	class = "IPV"
	icon_state = "generic"
	moving_state = "generic_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	designer = "Idris Incorporated"
	volume = "27 meters length, 19 meters beam/width, 11 meters vertical height"
	sizeclass = "Starfarer-line Pleasure Yacht"
	shiptype = "Private passenger utility, long-distance travel case"
	vessel_mass = 3000
	max_speed = 1/(2 SECONDS)
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/yacht
	name = "Private Yacht (Drydock)"
	move_time = 25
	range = 2
	fuel_consumption = 3
	shuttle_area = list(
		/area/shuttle/yacht,
		/area/shuttle/yacht/bridge,
		/area/shuttle/yacht/living,
		/area/shuttle/yacht/engine,
	)
	current_location = "nav_yacht_space_dd"
	landmark_transition = "nav_yacht_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/yacht
	shuttle_name = "Private Yacht (Drydock)"
	landmark_tag = "nav_yacht_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/yacht_transit
	name = "In transit"
	landmark_tag = "nav_yacht_transit_dd"
	base_turf = /turf/space/transit/north
