/*
 * Drydock Ship -- IAC Rescue Ship
 * Converted from maps/away/ships/iac/iac_rescue_ship.dmm (Bucket B) -- see
 * coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale.
 */

/datum/map_template/drydock_ship/iac_rescue_ship
	name = "IAC Rescue Ship"
	id = "iac_rescue_ship_dd"
	mappath = "maps/drydock_ships/iac_rescue_ship/iac_rescue_ship.dmm"
	price = 0
	bridge_area_type = /area/ship/iac_rescue_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/iac_rescue_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/iac_rescue_ship
	name = "IAC Rescue Ship"
	class = "IAV"
	shuttle = "IAC Rescue Ship (Drydock)"
	desc = "The Sanctuary-class rescue ship is a fast response medical vessel, based in large part off of the Asclepius-class medical transport, a widespread clinic ship, designed to operate mainly between planets rather than in open space. Most Sanctuary-class hulls are heavily refitted to accomodate for the new conditions in the Wildlands."
	icon_state = "sanctuary"
	moving_state = "sanctuary_moving"
	colors = list("#ace8fa", "#71abf7")
	scanimage = "hospital.png"
	designer = "Zeng-Hu Pharmaceuticals, Hephaestus Industries"
	volume = "48 meters length, 32 meters beam/width, 19 meters vertical height"
	sizeclass = "Sanctuary-class Rescue Ship"
	shiptype = "Emergency medical logistics relief and distress response"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/iac_rescue_ship
	name = "IAC Rescue Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/ship/iac_rescue_ship,
		/area/ship/iac_rescue_ship/bridge,
		/area/ship/iac_rescue_ship/hangar,
		/area/ship/iac_rescue_ship/starboardengine,
		/area/ship/iac_rescue_ship/portengine,
		/area/ship/iac_rescue_ship/engineering,
		/area/ship/iac_rescue_ship/atmospherics,
		/area/ship/iac_rescue_ship/bathroom,
		/area/ship/iac_rescue_ship/mainstorage,
		/area/ship/iac_rescue_ship/medical,
		/area/ship/iac_rescue_ship/surgery,
		/area/ship/iac_rescue_ship/machinist,
		/area/ship/iac_rescue_ship/pharmacy,
		/area/ship/iac_rescue_ship/dorms,
		/area/ship/iac_rescue_ship/hydro,
		/area/ship/iac_rescue_ship/kitchen,
		/area/ship/iac_rescue_ship/custodial,
		/area/ship/iac_rescue_ship/evaprep,
		/area/ship/iac_rescue_ship/portdocking,
		/area/ship/iac_rescue_ship/starboarddocking,
		/area/ship/iac_rescue_ship/coord,
		/area/ship/iac_rescue_ship/forehallway,
		/area/ship/iac_rescue_ship/centralhallway,
		/area/ship/iac_rescue_ship/afthallway,
	)
	current_location = "nav_iac_rescue_ship_space_dd"
	landmark_transition = "nav_iac_rescue_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/iac_rescue_ship
	shuttle_name = "IAC Rescue Ship (Drydock)"
	landmark_tag = "nav_iac_rescue_ship_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/iac_rescue_ship_transit
	name = "In transit"
	landmark_tag = "nav_iac_rescue_ship_transit_dd"
	base_turf = /turf/space/transit/north
