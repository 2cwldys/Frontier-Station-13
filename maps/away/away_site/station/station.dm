/*
 * "Station" -- a bare 10x10 airless construction platform in open space.
 * No walls, no power, nothing else: meant to be placed deliberately via the
 * Generate Away Site admin verb, pinned via Persistent Overmap Sites, and
 * expanded by players into their own station. RUIN_STARTS_DISALLOWED keeps
 * it out of the boot-time random away-site pool entirely.
 */
/datum/map_template/ruin/away_site/station
	name = "Station"
	id = "station"
	description = "A bare construction platform anchored in open space, ready to be built upon."
	sectors = list(ALL_TAU_CETI_SECTORS, ALL_BADLAND_SECTORS, ALL_COALITION_SECTORS)

	prefix = "away_site/station/"
	suffix = "station.dmm"

	spawn_weight = 1
	spawn_cost = 0
	template_flags = TEMPLATE_FLAG_NO_RUINS | TEMPLATE_FLAG_RUIN_STARTS_DISALLOWED

/obj/effect/overmap/visitable/sector/station
	name = "construction platform"
	desc = "Sensors detect a bare construction platform anchored in open space."
	icon_state = "object"

	initial_generic_waypoints = list(
		"nav_station_1",
		"nav_station_2",
		"nav_station_3",
		"nav_station_4"
	)

/obj/effect/shuttle_landmark/nav_station/nav1
	name = "Construction Platform Navpoint #1"
	landmark_tag = "nav_station_1"
	base_area = /area/space
	base_turf = /turf/space

/obj/effect/shuttle_landmark/nav_station/nav2
	name = "Construction Platform Navpoint #2"
	landmark_tag = "nav_station_2"
	base_area = /area/space
	base_turf = /turf/space

/obj/effect/shuttle_landmark/nav_station/nav3
	name = "Construction Platform Navpoint #3"
	landmark_tag = "nav_station_3"
	base_area = /area/space
	base_turf = /turf/space

/obj/effect/shuttle_landmark/nav_station/nav4
	name = "Construction Platform Navpoint #4"
	landmark_tag = "nav_station_4"
	base_area = /area/space
	base_turf = /turf/space
