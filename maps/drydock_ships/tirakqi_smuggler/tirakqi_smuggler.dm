/*
 * Drydock Ship -- Ti'Rakqi Smuggler
 * Converted from maps/away/ships/tirakqi_smuggler/tirakqi_smuggler.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/tirakqi_smuggler
	name = "Ti'Rakqi Smuggler"
	id = "tirakqi_smuggler"
	mappath = "maps/drydock_ships/tirakqi_smuggler/tirakqi_smuggler.dmm"
	price = 0
	bridge_area_type = /area/ship/tirakqi_smuggler/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/tirakqi_smuggler)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/tirakqi_smuggler
	name = "Ti'Rakqi Smuggler"
	class = "ISV"
	shuttle = "Ti'Rakqi Smuggler (Drydock)"
	desc = "Featuring a respectable cargo bay, light frame, and large thruster nacelles, the Xroquv-class is one of the fastest federation freighters of this size. This one in particular appears to be refitted with expanded thruster nacelles and minor structural modifications."
	icon_state = "tirakqi"
	moving_state = "tirakqi_moving"
	colors = list("#27e4ee", "#4febbf")
	scanimage = "skrell_freighter.png"
	designer = "Nralakk Federation"
	volume = "37 meters length, 61 meters beam/width, 19 meters vertical height"
	drive = "Mid-Speed Warp Acceleration FTL Drive"
	weapons = "No visible armament, aft external flight craft bay"
	sizeclass = "Xroquv-class Federation Freighter"
	shiptype = "Luxupi Freighter"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/tirakqi_smuggler
	name = "Ti'Rakqi Smuggler (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/tirakqi_smuggler,
		/area/ship/tirakqi_smuggler/engi,
		/area/ship/tirakqi_smuggler/atmos,
		/area/ship/tirakqi_smuggler/med,
		/area/ship/tirakqi_smuggler/wash,
		/area/ship/tirakqi_smuggler/mess,
		/area/ship/tirakqi_smuggler/crew,
		/area/ship/tirakqi_smuggler/capt,
		/area/ship/tirakqi_smuggler/bridge,
		/area/ship/tirakqi_smuggler/cargo,
		/area/ship/tirakqi_smuggler/hall,
		/area/ship/tirakqi_smuggler/port_hall,
		/area/ship/tirakqi_smuggler/starboard_hall,
		/area/ship/tirakqi_smuggler/port_arm,
		/area/ship/tirakqi_smuggler/starboard_arm,
	)
	current_location = "nav_tirakqi_smuggler_space_dd"
	landmark_transition = "nav_tirakqi_smuggler_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/tirakqi_smuggler
	shuttle_name = "Ti'Rakqi Smuggler (Drydock)"
	landmark_tag = "nav_tirakqi_smuggler_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/tirakqi_smuggler_transit
	name = "In transit"
	landmark_tag = "nav_tirakqi_smuggler_transit_dd"
	base_turf = /turf/space/transit/north
