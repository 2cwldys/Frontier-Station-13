/*
 * Drydock Ship -- COC Survey Ship
 * Converted from maps/away/ships/coc/coc_surveyor (Bucket B -- the mothership
 * was a static away-site encounter with only its small internal escort
 * shuttle flyable). Flight stats copied verbatim from the original static
 * /obj/effect/overmap/visitable/ship/coc_surveyor -- see the Phase 4B recipe
 * (persistence_shuttles.dm's drydockAutoFurnish()) for how the bridge console
 * gets furnished at first retrieve instead of being hand-placed in the .dmm.
 */

/datum/map_template/drydock_ship/coc_surveyor
	name = "COC Survey Ship"
	id = "coc_surveyor"
	mappath = "maps/drydock_ships/coc_surveyor/coc_surveyor.dmm"
	price = 0
	bridge_area_type = /area/coc_survey_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/coc_surveyor)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/coc_surveyor
	name = "COC Survey Ship"
	class = "CCV"
	shuttle = "COC Survey Ship (Drydock)"
	desc = "The Galga-class Surveyor is a very recent design, created as apart of a joint venture between Xanu and Himeo, in an effort to better map out the Weeping Stars. Created to be largely self sufficient, its on board refinery allows it to create products for market between ventures into the uncharted areas of the Spur. While the ship is armed, its thin hull, powerful thrusters, and large fuel tanks encourage retreat."
	icon_state = "tramp"
	moving_state = "tramp_moving"
	colors = list("#8492fd", "#4d61fc")
	designer = "Coalition of Colonies, Xanu Prime"
	volume = "60 meters length, 58 meters beam/width, 12 meters vertical height"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	weapons = "Dual extruding port fore and starboard fore-mounted medium caliber armament, aft obscured flight craft bay"
	sizeclass = "Galga-class Surveyor"
	shiptype = "Exploration, mineral and artifact recovery"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/coc_surveyor
	name = "COC Survey Ship (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/coc_survey_ship,
		/area/coc_survey_ship/bridge,
		/area/coc_survey_ship/engineering,
		/area/coc_survey_ship/atmos,
		/area/coc_survey_ship/port_propulsion,
		/area/coc_survey_ship/starboard_propulsion,
		/area/coc_survey_ship/quarters,
		/area/coc_survey_ship/kitchen,
		/area/coc_survey_ship/hangar,
		/area/coc_survey_ship/miningeva,
		/area/coc_survey_ship/mess_hall,
		/area/coc_survey_ship/captain,
		/area/coc_survey_ship/blaster,
		/area/coc_survey_ship/grauwolf,
		/area/coc_survey_ship/research,
		/area/coc_survey_ship/anomaly,
		/area/coc_survey_ship/cargo,
		/area/coc_survey_ship/cryo,
		/area/coc_survey_ship/medical,
	)
	current_location = "nav_coc_surveyor_space_dd"
	landmark_transition = "nav_coc_surveyor_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/coc_surveyor
	shuttle_name = "COC Survey Ship (Drydock)"
	landmark_tag = "nav_coc_surveyor_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/coc_surveyor_transit
	name = "In transit"
	landmark_tag = "nav_coc_surveyor_transit_dd"
	base_turf = /turf/space/transit/north
