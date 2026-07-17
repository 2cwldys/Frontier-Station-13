/*
 * Drydock Ship -- Kataphract Chapter Ship
 * Converted from maps/away/ships/kataphracts/kataphract_ship.dmm (Bucket B)
 * -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for the general
 * conversion approach/rationale. The source's own small internal escort
 * shuttle (Kataphract Transport) is left in place as inert decoration -- its
 * datum is deliberately not registered in shuttles_to_initialise below.
 */

/datum/map_template/drydock_ship/kataphract_ship
	name = "Kataphract Chapter Ship"
	id = "kataphract_ship_dd"
	mappath = "maps/drydock_ships/kataphracts/kataphract_ship.dmm"
	price = 0
	bridge_area_type = /area/kataphract_chapter/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/kataphract_ship)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/kataphract_ship
	name = "kataphract chapter ship"
	desc = "A large corvette manufactured by a Hephaestus sponsored Hegemonic Guild. This is a heavily armoured Kataphract Chapter ship of the venerable 'Voidbreaker' class, a relative of the more common 'Foundation' class used by their counterparts in the Hegemony Navy."
	class = "IHKV"
	shuttle = "Kataphract Chapter Ship (Drydock)"
	icon_state = "voidbreaker"
	moving_state = "voidbreaker_moving"
	colors = list("#e38222", "#f0ba3e")
	scanimage = "unathi_corvette.png"
	designer = "Hephaestus Industries, Izweski Hegemonic Naval Guilds"
	volume = "65 meters length, 45 meters beam/width, 21 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Not apparent, port obscured flight craft bay"
	sizeclass = "Voidbreaker-class Armored Corvette"
	shiptype = "Specialist long-distance extended-duration combat utility"
	vessel_mass = 10000
	max_speed = 1/(2 SECONDS)
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/kataphract_ship
	name = "Kataphract Chapter Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/kataphract_chapter,
		/area/kataphract_chapter/bridge,
		/area/kataphract_chapter/sparring_chamber,
		/area/kataphract_chapter/armoury,
		/area/kataphract_chapter/main_ring,
		/area/kataphract_chapter/aft_hall,
		/area/kataphract_chapter/portentry,
		/area/kataphract_chapter/starentry,
		/area/kataphract_chapter/medical,
		/area/kataphract_chapter/dorms,
		/area/kataphract_chapter/toilets,
		/area/kataphract_chapter/office,
		/area/kataphract_chapter/specoffice,
		/area/kataphract_chapter/mess,
		/area/kataphract_chapter/brig,
		/area/kataphract_chapter/engineering,
		/area/kataphract_chapter/atmospherics,
		/area/kataphract_chapter/starboardpropulsion,
		/area/kataphract_chapter/portpropulsion,
		/area/kataphract_chapter/hangar,
		/area/kataphract_chapter/cic,
		/area/kataphract_chapter/frankie,
		/area/kataphract_chapter/bruiser,
		/area/kataphract_chapter/hull,
	)
	current_location = "nav_kataphract_ship_space_dd"
	landmark_transition = "nav_kataphract_ship_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/kataphract_ship
	shuttle_name = "Kataphract Chapter Ship (Drydock)"
	landmark_tag = "nav_kataphract_ship_space_dd"
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/kataphract_ship_transit
	name = "In transit"
	landmark_tag = "nav_kataphract_ship_transit_dd"
	base_turf = /turf/space/transit/north
