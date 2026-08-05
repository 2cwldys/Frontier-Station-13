/*
 * Drydock Ship -- Adhomian Freighter
 * Converted from maps/away/ships/tajara/taj_smuggler/tajaran_smuggler.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale. The source's two internal
 * escort craft (Adhomian Freight Shuttle, and its detachable Cargo Hold) are
 * left in place as inert decoration -- neither datum is registered in
 * shuttles_to_initialise below.
 */

/datum/map_template/drydock_ship/tajaran_smuggler
	name = "Adhomian Freighter"
	id = "tajaran_smuggler"
	mappath = "maps/drydock_ships/taj_smuggler/tajaran_smuggler.dmm"
	price = 1000000
	bridge_area_type = /area/tajaran_smuggler/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/tajaran_smuggler, /datum/shuttle/autodock/overmap/tajaran_smuggler_shuttle, /datum/shuttle/autodock/overmap/tajaran_smuggler_cargo)
	sub_shuttle_tags = list("Adhomian Freight Shuttle", "Adhomian Freight Cargo")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/tajaran_smuggler
	name = "Adhomian Freighter"
	class = "ACV"
	shuttle = "Adhomian Freighter (Drydock)"
	desc = "Built with reliability in mind, the Zhsram Freighter is one of the most common Adhomian designs. This vessel is cheap and has a sizeable cargo storage. It is frequently used by Tajaran traders and smugglers."
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#c3c7eb", "#a0a8ec")
	scanimage = "tramp_freighter.png"
	designer = "Independent/no designation"
	volume = "55 meters length, 25 meters beam/width, 18 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Not apparent, port obscured flight craft bay"
	sizeclass = "Zhsram Freighter"
	shiptype = "Long-term shipping utilities"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/tajaran_smuggler
	name = "Adhomian Freighter (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/tajaran_smuggler,
		/area/tajaran_smuggler/bridge,
		/area/tajaran_smuggler/hangar,
		/area/tajaran_smuggler/dorms,
		/area/tajaran_smuggler/captain_quarters,
		/area/tajaran_smuggler/atmos,
		/area/tajaran_smuggler/engine,
		/area/tajaran_smuggler/power,
	)
	current_location = "nav_tajaran_smuggler_space_dd"
	landmark_transition = "nav_tajaran_smuggler_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/tajaran_smuggler
	shuttle_name = "Adhomian Freighter (Drydock)"
	landmark_tag = "nav_tajaran_smuggler_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/tajaran_smuggler_transit
	name = "In transit"
	landmark_tag = "nav_tajaran_smuggler_transit_dd"
	base_turf = /turf/space/transit/north
