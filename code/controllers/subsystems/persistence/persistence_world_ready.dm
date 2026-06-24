/*
 * Persistence - World Ready Gate
 * Subsystem with init_order = -100, running after:
 *   atoms(30), air(-1), away_maps(-2), ghost_roles(-2.1), misc(-2.2), codex(-3), persistence(-10)
 * Sets GLOB.persistence_ready = TRUE only when the entire world is fully initialized,
 * including all dynamic Z-levels (away missions, derelicts, etc.).
 */

SUBSYSTEM_DEF(persistence_world_ready)
	name = "Persistence World Ready"
	init_order = -100  // Runs after EVERYTHING: away maps(-2), misc(-2.2), codex(-3), persistence(-10)
	flags = SS_NO_FIRE  // Only needs to run Initialize(), never fires

/datum/controller/subsystem/persistence_world_ready/Initialize(timeofday)
	. = ..()
	// All other subsystems have now completed their Initialize().
	// Signal that the persistent world is open for players.
	SSticker.start_persistent_world()
	log_world("Persistent world: all subsystems initialized. Server is now open.")
	return SS_INIT_SUCCESS
