/*
 * Drydock Ship -- Player-Built Shuttle Shell
 *
 * The shared blank-canvas Z every player-commissioned shuttle deploys onto
 * (ship_commissioning_console.dm) -- mirrors drydock_ship_placeholder's
 * proven registration shape (map_template/marker/shuttle datum/landmarks)
 * exactly, but deliberately contains no console: unlike a real hull, this
 * one is never flown as-is. At commission time, drydockCommission()
 * (persistence_shuttles.dm) captures whatever the player actually built --
 * including their own placed shuttle_control console -- onto this same
 * bare room via shipInteriorApply(), the same way any stashed ship's saved
 * interior overlays onto its own template on every retrieve. Sized/scaled
 * SHIP_SIZE_TINY to match how a small sub-ship (Xanu Fighter/Boarder,
 * maps/away/ships/xanu/xanu_frigate.dm) is scaled, not a full warship --
 * these are shuttles, not ships. hidden_from_catalog keeps this shell out
 * of the normal Drydock Buy listing (drydock.dm) and drydockBuy() itself.
 */

/datum/map_template/drydock_ship/player_built_shuttle
	name = "Player-Built Shuttle"
	id = "player_built_shuttle"
	mappath = "maps/drydock_ships/player_built_shuttle/player_built_shuttle.dmm"
	price = 0
	hidden_from_catalog = TRUE
	shuttles_to_initialise = list(/datum/shuttle/autodock/overmap/drydock_ship/player_built_shuttle)

/obj/effect/overmap/visitable/ship/landable/drydock_ship/player_built_shuttle
	name = "Player-Built Shuttle"
	class = "SHU"
	shuttle = "Player-Built Shuttle"
	desc = "A shuttle built and commissioned by its owner, not from a shipyard template."
	icon_state = "shuttle"
	moving_state = "shuttle_moving"
	max_speed = 1/(2 SECONDS)
	burn_delay = 1.5 SECONDS
	vessel_mass = 2000
	vessel_size = SHIP_SIZE_TINY
	fore_dir = SOUTH

/datum/shuttle/autodock/overmap/drydock_ship/player_built_shuttle
	name = "Player-Built Shuttle"
	move_time = 20
	range = 2
	fuel_consumption = 2
	shuttle_area = list(/area/drydock_ship/player_built_shuttle)
	current_location = "nav_drydock_ship_player_built_shuttle_space"
	dock_target = "player_built_shuttle"
	landmark_transition = "nav_drydock_ship_player_built_shuttle_transit"
	logging_home_tag = "nav_drydock_ship_player_built_shuttle_space"

/// base_turf/base_area pinned to space, and SLANDMARK_FLAG_AUTOSET
/// deliberately dropped, matching every working template hull
/// (xanu_frigate.dm, orion_miner.dm, ...).
///
/// translate_turfs() (__HELPERS/turfs.dm) reverts a departing ship's vacated
/// turfs to `current_location.base_area`/`base_turf`. Template hulls map this
/// landmark out in open space, so AUTOSET derives space for both and home
/// correctly empties out when they leave. THIS landmark is mapped inside the
/// 9x9 room (and repositioned onto the hull by
/// _drydock_reposition_ship_landmark()), so AUTOSET was deriving the SHIP'S
/// OWN area and the room's floor instead -- meaning home never reverted to
/// space on departure and the ship's shuttle_area silently spanned both home
/// AND wherever it had docked. get_turf_translation() then built its
/// footprint from both places at once, which is what produced the
/// "would land outside this z-level's map bounds" refusals and left the ship
/// unable to pick anything, including its own home.
/obj/effect/shuttle_landmark/ship/drydock_ship_player_built_shuttle
	name = "Open Space"
	shuttle_name = "Player-Built Shuttle"
	landmark_tag = "nav_drydock_ship_player_built_shuttle_space"
	landmark_flags = SLANDMARK_FLAG_ZERO_G
	base_turf = /turf/space
	base_area = /area/space

/obj/effect/shuttle_landmark/drydock_ship_player_built_shuttle_transit
	name = "In transit"
	landmark_tag = "nav_drydock_ship_player_built_shuttle_transit"
	base_turf = /turf/space

/area/drydock_ship/player_built_shuttle
	name = "Player-Built Shuttle"
