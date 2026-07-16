/*
 * Drydock Ship -- Independent Skiff
 * Converted from maps/away/ships/lone_spacer, which is already a fully
 * flyable/dockable away-site craft in its original form (Bucket A in the
 * hull survey) -- this conversion only wraps it in the drydock template
 * naming scheme so it plugs into the buy/retrieve/stash system, and gives it
 * fresh internal shuttle/landmark identifiers so it can never collide with
 * the original away-site version if that's ever independently spawned by a
 * mission. Original area types are reused unchanged (safe -- areas aren't
 * globally-keyed like shuttle names/landmark tags are).
 */

/datum/map_template/drydock_ship/lone_spacer
	name = "Independent Skiff"
	id = "lone_spacer"
	mappath = "maps/drydock_ships/lone_spacer/lone_spacer.dmm"
	price = 0
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/lone_spacer)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/lone_spacer
	name = "Independent Skiff (Landable)"
	class = "ICV"
	shuttle = "Independent Skiff (Drydock)"
	desc = "Of all of the most ubiquitous ships in the spur today, the Minnow-class skiff has perhaps seen one of the most meteoric rises. Designed in 2443 by Hephaestus Industries as a short-distance hauling craft intended to be operated by only one or two crewmates, the Minnow-class quickly caught on with virtually every demographic imaginable - logisticians appreciated its standardised design and expansive cargo holds, scientists its ease of use and modification, smugglers its nimble speed and ability to dodge patrols with its warp drive, and pirates its discreet and inexpensive nature."
	icon_state = "spacer"
	moving_state = "spacer_moving"
	colors = list("#70a170")
	max_speed = 1/(2 SECONDS)
	burn_delay = 2 SECONDS
	vessel_mass = 7500
	vessel_size = SHIP_SIZE_SMALL
	fore_dir = SOUTH
	designer = "Hephaestus Industries"
	volume = "30 meters length, 20 meters beam/width, 7 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Starboard low-end ballistic cannon"
	sizeclass = "Minnow-class Hauler"
	shiptype = "Eclectic short-distance shipping utilities"

/obj/effect/overmap/visitable/ship/landable/drydock_ship/lone_spacer/New()
	designation = "[pick("Roach", "Moonskipper", "Thunder", "Firefly", "Starfarer", "Workhorse", "Light-in-the-Dark", "Gift Horse", "Rain", "Mirth", "Ever-Lucky", "Tin-and-Copper", "Bright Burning", "Bird-of-the-Heavens", "Ruby", "Old Story", "Fardancer", "Albedo", "Lightchaser", "Sooner-than-Later", "Sunlight", "Pearl-of-the-Morning", "Endless", "Finity", "Calm Drift", "Mercury's Hand")]"
	..()

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/lone_spacer
	shuttle_tag = "Independent Skiff (Drydock)"

/datum/shuttle/autodock/overmap/drydock_ship/lone_spacer
	name = "Independent Skiff (Drydock)"
	move_time = 20
	range = 2
	fuel_consumption = 2
	shuttle_area = list(/area/shuttle/lone_spacer/bridge, /area/shuttle/lone_spacer/bridge_foyer, /area/shuttle/lone_spacer/fore_hall, /area/shuttle/lone_spacer/washroom, /area/shuttle/lone_spacer/storage, /area/shuttle/lone_spacer/port_storage, /area/shuttle/lone_spacer/port_nacelle, /area/shuttle/lone_spacer/starboard_storage, /area/shuttle/lone_spacer/starboard_nacelle)
	current_location = "nav_lone_spacer_space_dd"
	dock_target = "lone_spacer_dd"
	landmark_transition = "nav_lone_spacer_transit_dd"
	logging_home_tag = "nav_lone_spacer_space_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/lone_spacer
	shuttle_name = "Independent Skiff (Drydock)"
	landmark_tag = "nav_lone_spacer_space_dd"

/obj/effect/shuttle_landmark/drydock_ship/lone_spacer_transit
	name = "In transit"
	landmark_tag = "nav_lone_spacer_transit_dd"
	base_turf = /turf/space

/obj/effect/map_effect/marker/airlock/shuttle/drydock_ship/lone_spacer
	name = "lone_spacer"
	master_tag = "lone_spacer_dd"
	shuttle_tag = "Independent Skiff (Drydock)"
	cycle_to_external_air = TRUE
