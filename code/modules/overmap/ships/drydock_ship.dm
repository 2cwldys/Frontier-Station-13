/*
 * Drydock Ship -- generic framework
 *
 * Purpose-built player-flyable overmap ship, bought/stashed/retrieved via
 * a docking beacon instead of a faction beacon (see persistence_shuttles.dm)
 * -- otherwise identical in shape to the faction corvette framework
 * (faction_corvette.dm), reusing the exact same off-the-shelf overmap ship
 * movement/fuel/docking machinery. Unlike corvettes, ownership can be
 * personal (owner_ckey) as well as faction (faction_uid).
 *
 * A concrete hull (its own .dm + .dmm) subtypes all four types below --
 * see maps/drydock_ships/ for the first one.
 */

/datum/map_template/drydock_ship
	/// Credits charged by drydockBuy() (persistence_shuttles.dm). 0 = free.
	var/price = 0

/obj/effect/overmap/visitable/ship/landable/drydock_ship
	use_mapped_z_levels = TRUE
	invisible_until_ghostrole_spawn = FALSE

/datum/shuttle/autodock/overmap/drydock_ship
	defer_initialisation = TRUE
	/// Set by drydockRetrieve() right after materialization, from the
	/// owning ss13_drydock_ships ledger row -- mirrors the old player_built
	/// pattern of keeping faction ownership directly on the shuttle datum.
	/// Read by player_dock/is_valid() (shuttle_core.dm) to enforce a
	/// beacon's faction restriction. Null for a personally-owned ship,
	/// same as an unrestricted beacon -- both compare as "no faction".
	var/faction_uid

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship
	name = "shuttle control console"

/area/drydock_ship
	name = "Drydock Ship"
	icon_state = "bluenew"
	requires_power = TRUE
	area_flags = AREA_FLAG_RAD_SHIELDED
