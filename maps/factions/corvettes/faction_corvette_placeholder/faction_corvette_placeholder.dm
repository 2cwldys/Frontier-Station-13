/*
 * Faction Corvette -- Placeholder Hull
 *
 * Minimal proof-of-framework hull for Phase 8 (docs/shuttlesystem-architecture.md
 * Part 7): a small room with the required shuttle_landmark/ship, transit
 * landmark, and shuttle console. Proves the Buy/Retrieve/Stash lifecycle and
 * beacon-radius overmap placement end-to-end. The real multi-deck interior
 * is separate, later content-authorship work -- this hull's code never
 * changes when a real one replaces it, only faction_corvette_placeholder.dmm
 * does.
 */

/datum/map_template/faction_corvette/placeholder
	name = "Placeholder Corvette"
	id = "faction_corvette_placeholder"
	mappath = "maps/factions/corvettes/faction_corvette_placeholder/faction_corvette_placeholder.dmm"

	price = 0
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/faction_corvette/placeholder)

/obj/effect/overmap/visitable/ship/landable/faction_corvette/placeholder
	name = "Placeholder Corvette"
	class = "CIV"
	shuttle = "Placeholder Corvette"
	desc = "A minimal test hull used to prove the faction corvette framework end-to-end."
	icon_state = "shuttle"
	moving_state = "shuttle_moving"
	max_speed = 1/(2 SECONDS)
	burn_delay = 2 SECONDS
	vessel_mass = 5000
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH

/obj/structure/machinery/computer/shuttle_control/explore/terminal/faction_corvette/placeholder
	shuttle_tag = "Placeholder Corvette"

/datum/shuttle/autodock/overmap/faction_corvette/placeholder
	name = "Placeholder Corvette"
	move_time = 20
	range = 2
	fuel_consumption = 2
	shuttle_area = list(/area/faction_corvette/placeholder)
	current_location = "nav_faction_corvette_placeholder_space"
	dock_target = "faction_corvette_placeholder"
	landmark_transition = "nav_faction_corvette_placeholder_transit"
	logging_home_tag = "nav_faction_corvette_placeholder_space"

/obj/effect/shuttle_landmark/ship/faction_corvette_placeholder
	shuttle_name = "Placeholder Corvette"
	landmark_tag = "nav_faction_corvette_placeholder_space"

/obj/effect/shuttle_landmark/faction_corvette_placeholder_transit
	name = "In transit"
	landmark_tag = "nav_faction_corvette_placeholder_transit"
	base_turf = /turf/space

/area/faction_corvette/placeholder
	name = "Placeholder Corvette"
