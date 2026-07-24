/*
 * Drydock Ship -- Konyang Wreck
 * Converted from maps/away/ships/konyang/konyang_wreck (Bucket B -- one of
 * the two fully static hulls with zero shuttle scaffolding of any kind in
 * the source directory, fitting its derelict/mystery flavor) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/konyang_wreck
	name = "Konyang Wreck"
	id = "konyang_wreck_dd"
	mappath = "maps/drydock_ships/konyang_wreck/konyang_wreck.dmm"
	price = 0
	bridge_area_type = /area/konyang_wreck/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/konyang_wreck)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/konyang_wreck
	name = "Konyang Wreck"
	desc = "An Orion Express Packhorse-class freighter."
	class = "OEV"
	shuttle = "Konyang Wreck (Drydock)"
	icon_state = "freighter_large"
	moving_state = "freighter_large_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	designer = "Orion Express"
	volume = "41 meters length, 36 meters beam/width, 11 meters vertical height"
	sizeclass = "Packhorse-class cargo freighter"
	shiptype = "Long-range cargo transport"
	vessel_mass = 5000
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/konyang_wreck
	name = "Konyang Wreck (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/konyang_wreck,
		/area/konyang_wreck/bridge,
		/area/konyang_wreck/captain,
		/area/konyang_wreck/cryo,
		/area/konyang_wreck/portdock,
		/area/konyang_wreck/starboarddock,
		/area/konyang_wreck/pod1,
		/area/konyang_wreck/pod2,
		/area/konyang_wreck/pod3,
		/area/konyang_wreck/pod4,
		/area/konyang_wreck/pod5,
		/area/konyang_wreck/pod6,
		/area/konyang_wreck/pod7,
		/area/konyang_wreck/pod8,
		/area/konyang_wreck/engineering,
		/area/konyang_wreck/atmos,
		/area/konyang_wreck/portthrust,
		/area/konyang_wreck/starbthrust,
		/area/konyang_wreck/aicore,
		/area/konyang_wreck/mechbay,
	)
	current_location = "nav_konyang_wreck_space_dd"
	landmark_transition = "nav_konyang_wreck_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/konyang_wreck
	shuttle_name = "Konyang Wreck (Drydock)"
	landmark_tag = "nav_konyang_wreck_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/konyang_wreck_transit
	name = "In transit"
	landmark_tag = "nav_konyang_wreck_transit_dd"
	base_turf = /turf/space/transit/north
