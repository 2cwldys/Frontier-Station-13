/*
 * Drydock Ship -- Militia Ship
 * Converted from maps/away/ships/wildlands_militia/militia_ship.dmm (Bucket
 * B -- a very minimal away-site with almost no interior detail besides its
 * own base area) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/)
 * for the general conversion approach/rationale. The source's own small
 * internal escort shuttle is left in place as inert decoration -- its datum
 * is deliberately not registered in shuttles_to_initialise below.
 */

/datum/map_template/drydock_ship/militia_ship
	name = "Militia Ship"
	id = "militia_ship_dd"
	mappath = "maps/drydock_ships/wildlands_militia/militia_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/militia_ship
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/militia_ship, /datum/shuttle/autodock/overmap/militia_shuttle)
	sub_shuttle_tags = list("Militia Ship")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/militia_ship
	name = "Militia Ship"
	class = "IPV"
	shuttle = "Militia Ship (Drydock)"
	desc = "An unarmed and extremely prolific design of large, self-sufficient shuttle, prized for its modularity. Found all throughout the spur, the Yak-class shuttle can be configured to conceivably serve in any role, though it is only rarely armed with ship-to-ship weapons. Manufactured by Hephaestus."
	icon_state = "generic"
	moving_state = "generic_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/militia_ship
	name = "Militia Ship (Drydock)"
	move_time = 25
	range = 2
	fuel_consumption = 3
	shuttle_area = list(/area/ship/militia_ship)
	current_location = "nav_militia_ship_space_dd"
	landmark_transition = "nav_militia_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/militia_ship
	shuttle_name = "Militia Ship (Drydock)"
	landmark_tag = "nav_militia_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/militia_ship_transit
	name = "In transit"
	landmark_tag = "nav_militia_ship_transit_dd"
	base_turf = /turf/space/transit/north
