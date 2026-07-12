/*
 * Faction Corvette -- generic framework
 *
 * Purpose-built player-flyable overmap ship, NOT away-site content -- see
 * docs/shuttlesystem-architecture.md Part 7 for why. Movement, fuel, and
 * docking are entirely inherited, off-the-shelf from the existing overmap
 * ship framework (same one Intrepid/Canary/Quark use); this file only wires
 * together the three pieces a new player ship type always needs, plus the
 * map_template base every concrete hull's own template subtype extends.
 *
 * A concrete hull (its own .dm + .dmm) subtypes all four types below --
 * see maps/factions/corvettes/ for the first one.
 */

/datum/map_template/faction_corvette
	/// Credits charged by corvetteBuy() (persistence_corvettes.dm). 0 = free.
	var/price = 0

/obj/effect/overmap/visitable/ship/landable/faction_corvette
	use_mapped_z_levels = TRUE
	invisible_until_ghostrole_spawn = FALSE

/datum/shuttle/autodock/overmap/faction_corvette
	defer_initialisation = TRUE

/obj/structure/machinery/computer/shuttle_control/explore/terminal/faction_corvette
	name = "shuttle control console"

/area/faction_corvette
	name = "Faction Corvette"
	icon_state = "bluenew"
	requires_power = TRUE
	area_flags = AREA_FLAG_RAD_SHIELDED
