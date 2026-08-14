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

	// persistence_disable_station: strip the default station's overmap
	// presence and wipe its Z-level(s) to open space. Has to happen here,
	// not in SSatlas (where the station actually loads) -- the marker's
	// map_z (which Z's to wipe) isn't populated until its own atom
	// Initialize() runs, during SSatoms, a later stage than SSatlas's own
	// Initialize(). This subsystem is the one guaranteed to run after
	// everything else, so map_z is always valid by the time this executes.
	if(GLOB.config.persistence_disable_station)
		var/obj/effect/overmap/visitable/station_marker
		for(var/obj/effect/overmap/visitable/V in world)
			if(V.base)
				station_marker = V
				break
		if(istype(station_marker))
			var/list/station_zs = station_marker.map_z.Copy()
			log_world("persistence_disable_station: wiping station z-level(s) [english_list(station_zs)] and removing its overmap marker.")
			// register_z_levels() (sectors.dm) points GLOB.map_sectors at this
			// marker for every Z it spans -- Destroy() doesn't clean that up
			// itself, so clear those entries first or they'd dangle on a
			// qdeleted object (istype() alone doesn't catch that).
			for(var/marker_z in station_zs)
				GLOB.map_sectors -= "[marker_z]"
			qdel(station_marker)

			// Delete everything on the station's own Z-levels -- every object,
			// mob, structure, and the turfs themselves. No reset/revert logic,
			// just gone -- open space. The Z-levels stay allocated, just empty.
			//
			// Reuses _wipeZContents() (persistence_ship_interiors.dm) rather
			// than a plain qdel() pass -- that's the same multi-pass mop-up +
			// moveToNullspace()-before-del() forced fallback already built to
			// fix this exact class of bug for ship-stash Z teardown (some
			// objects survive a single qdel() pass undeleted). Its own
			// protected-deck guard already special-cases this: decks 1-3 are
			// only protected `if(!GLOB.config.persistence_disable_station)`,
			// so it's a no-op skip everywhere else but permits exactly this
			// call.
			for(var/z in station_zs)
				SSpersistence._wipeZContents(z, "persistence_disable_station")
		else
			log_world("persistence_disable_station set, but no base=TRUE overmap marker was found to remove.")

	// All other subsystems have now completed their Initialize().
	// Signal that the persistent world is open for players.
	SSticker.start_persistent_world()
	log_world("Persistent world: all subsystems initialized. Server is now open.")
#ifdef REPUBLISH_HUB_VISIBILITY_ON_BOOT
	_republish_hub_visibility()
#endif
	return SS_INIT_SUCCESS

#ifdef REPUBLISH_HUB_VISIBILITY_ON_BOOT
/// BYOND's hub-announce handshake appears to key off an explicit runtime
/// change to world.visibility, not the implicit default it already has at
/// boot -- an initial hub-publish attempted before world state settles can
/// get lost with nothing prompting a retry. Toggling it off then back on
/// once everything is truly loaded reproduces the manual fix (flip the
/// admin "Toggle Hub Visibility" verb twice) automatically.
/proc/_republish_hub_visibility()
	set waitfor = FALSE
	if(!world.visibility)
		return
	world.visibility = FALSE
	sleep(10 SECONDS)
	world.visibility = TRUE
	log_world("Hub: republished visibility after full initialization.")
#endif
