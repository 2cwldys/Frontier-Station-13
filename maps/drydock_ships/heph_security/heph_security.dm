/*
 * Drydock Ship -- Hephaestus Security Vessel
 * Converted from maps/away/ships/heph/heph_security/heph_security.dmm
 * (Bucket B) -- see coc_surveyor.dm (maps/drydock_ships/coc_surveyor/) for
 * the general conversion approach/rationale.
 */

/datum/map_template/drydock_ship/heph_security
	name = "Hephaestus Security Vessel"
	id = "heph_security_dd"
	mappath = "maps/drydock_ships/heph_security/heph_security.dmm"
	price = 0
	bridge_area_type = /area/heph_security_ship/bridge
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/heph_security, /datum/shuttle/autodock/overmap/hephsec_shuttle)
	sub_shuttle_tags = list("Hephaestus Security Shuttle")

/obj/effect/overmap/visitable/ship/landable/drydock_ship/heph_security
	name = "Hephaestus Security Vessel"
	class = "HCV"
	shuttle = "Hephaestus Security Vessel (Drydock)"
	desc = "The Eumenides-class security transport is a Hephaestus design, largely used by the corporation's own asset protection forces. Designed for rapid response and usually outfited with high-grade equipment, these vessels are rarely seen far from major Hephaestus investments."
	icon_state = "cetus"
	moving_state = "cetus_moving"
	colors = list("#BAB86C", "#8B4000")
	designer = "Hephaestus Industries"
	weapons = "Dual extruding fore-mounted medium caliber ballistic armament, aftobscured flight craft docking port"
	drive = "Low-Speed Warp Acceleration FTL Drive"
	sizeclass = "Eumenides-class security transport"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1 SECONDS
	vessel_mass = 5000
	fore_dir = SOUTH
	vessel_size = SHIP_SIZE_SMALL

/datum/shuttle/autodock/overmap/drydock_ship/heph_security
	name = "Hephaestus Security Vessel (Drydock)"
	move_time = 30
	range = 2
	fuel_consumption = 4
	shuttle_area = list(
		/area/heph_security_ship,
		/area/heph_security_ship/bridge,
		/area/heph_security_ship/grauwolf,
		/area/heph_security_ship/francisca,
		/area/heph_security_ship/kitchen,
		/area/heph_security_ship/captain,
		/area/heph_security_ship/crew,
		/area/heph_security_ship/bathroom,
		/area/heph_security_ship/armory,
		/area/heph_security_ship/brig,
		/area/heph_security_ship/medbay,
		/area/heph_security_ship/atmos,
		/area/heph_security_ship/engineering,
		/area/heph_security_ship/thrusterport,
		/area/heph_security_ship/thrusterstarb,
		/area/heph_security_ship/dock,
	)
	current_location = "nav_heph_security_space_dd"
	landmark_transition = "nav_heph_security_transit_dd"

/obj/effect/shuttle_landmark/ship/drydock_ship/heph_security
	shuttle_name = "Hephaestus Security Vessel (Drydock)"
	landmark_tag = "nav_heph_security_space_dd"
	base_turf = /turf/space/dynamic
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship/heph_security_transit
	name = "In transit"
	landmark_tag = "nav_heph_security_transit_dd"
	base_turf = /turf/space/transit/north
