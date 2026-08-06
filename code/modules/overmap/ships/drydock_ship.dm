/*
 * Drydock Ship -- generic framework
 *
 * Purpose-built player-flyable overmap ship -- the single unified system for
 * both personally-owned and faction-owned ships. Retrieve/stash are
 * sector-relative: a faction-owned ship anchors to its own faction's
 * faction_beacon; a personally-owned ship uses whatever sector its owner's
 * computer currently is in, no beacon required (see persistence_shuttles.dm).
 * Reuses the exact same off-the-shelf overmap ship movement/fuel/docking
 * machinery every other landable ship (Intrepid/Canary/Quark/mining shuttle)
 * does.
 *
 * A concrete hull (its own .dm + .dmm) subtypes all four types below --
 * see maps/drydock_ships/ for the first one.
 */

/datum/map_template/drydock_ship
	/// Credits charged by drydockBuy() (persistence_shuttles.dm). 0 = free.
	var/price = 0
	/// Area type identifying this hull's bridge/CIC/command room, for hulls
	/// converted from a static away-site mothership that never had its own
	/// console mapped in (see drydockAutoFurnish(), persistence_shuttles.dm).
	/// Null for hulls that already ship with a mapped-in console (the
	/// placeholder, and any hull converted from an already-landable away-site
	/// craft) -- drydockAutoFurnish() no-ops when this is unset.
	var/bridge_area_type
	/// shuttle_tag(s) of any smaller craft mapped into this hull's own hangar
	/// bay, carried in `shuttles_to_initialise` alongside the hull's own
	/// shuttle -- bound entirely to this ship (no independent ledger/sale),
	/// always travels with it. Empty for hulls with no such sub-ship. Drives
	/// the rename UI, the stash-time docked guard, and missing-sub-ship
	/// detection (persistence_shuttles.dm).
	var/list/sub_shuttle_tags

/**
 * Docking creates a real, physical problem this class alone needs to solve:
 * on_landing()/on_takeoff() (landable.dm) only ever move the overmap MARKER
 * -- the ship's actual interior turfs never leave its own dedicated Z, so a
 * "docked" ship still has zero walkable connection to wherever it landed
 * unless someone builds one. That connection used to open automatically (a
 * paired /obj/effect/portal/dock_link, portals.dm) the instant landing
 * happened -- an invisible-until-you-walk-into-it gangway with no player
 * action or awareness involved, which is exactly what made it possible to
 * blindly step through one. Docking connections are now player-built
 * instead: an umbilical pad (telepad_umbilical.dm) on each end, tethered by
 * a shared access code. _sweep_stray_umbilicals() below just cleans up any
 * dock_link portal left over from before that change (or any other stray).
 */
/obj/effect/overmap/visitable/ship/landable/drydock_ship
	use_mapped_z_levels = TRUE
	invisible_until_ghostrole_spawn = FALSE

/// Sanctioned removal (drydockStash()/drydockScuttle(), both via
/// _drydockMarkerTeardown(), persistence_shuttles.dm) always flips the
/// ledger row to stashed=1 (or deletes it outright, for scuttle) BEFORE
/// qdel'ing the marker -- so if this fires and the row is still stashed=0,
/// nothing sanctioned handled it (e.g. an admin deleted the marker directly
/// via VV). Defensively recover the ledger back to stashed rather than
/// leaking the Z/row forever -- this is a recovery, not a deletion, unlike
/// drydockScuttle().
/obj/effect/overmap/visitable/ship/landable/drydock_ship/Destroy()
	var/found_deployed_row = FALSE
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(DS && !DS.stashed && DS.z == GET_Z(src))
			found_deployed_row = TRUE
			log_drydock_warning("drydock_ship/Destroy: shuttle_id=[sid] marker destroyed outside the sanctioned stash/scuttle flow -- recovering ledger to stashed.")
			GLOB.persistence_ship_z -= "[DS.z]"
			DS.stashed   = TRUE
			DS.z         = null
			DS.overmap_x = null
			DS.overmap_y = null
			if(SSdbcore.Connect())
				var/datum/db_query/q = SSdbcore.NewQuery(
					"UPDATE ss13_drydock_ships SET stashed=1, z=NULL, overmap_x=NULL, overmap_y=NULL, stashed_at=NOW() WHERE shuttle_id = :id",
					list("id" = sid)
				)
				q.Execute()
				SSpersistence.databaseCheckQueryResult(q, "drydock_ship/Destroy orphan recovery")
				qdel(q)
			break
	// Only tear down the Z here for a genuinely abnormal destruction. The
	// sanctioned flow (_drydockMarkerTeardown()) always flips the ledger to
	// stashed (or deletes it outright, for scuttle) BEFORE qdel'ing the
	// marker, then calls shipZTeardown() itself right after qdel returns --
	// found_deployed_row is only ever TRUE here when that didn't happen, so
	// this is the only place cleanup will ever run for this z.
	if(found_deployed_row)
		var/datum/shuttle/shuttle_datum = SSshuttle.shuttles[shuttle]
		SSpersistence.shipZTeardown(GET_Z(src), shuttle_datum?.name)
	. = ..()

/obj/effect/overmap/visitable/ship/landable/drydock_ship/on_landing(obj/effect/shuttle_landmark/from, obj/effect/shuttle_landmark/into)
	. = ..()
	_sweep_stray_umbilicals()

/// Cleans up any dock_link portal left on this ship's Z-level -- a leftover
/// from before docking connections became player-built (telepad_umbilical.dm),
/// or any other stray. Umbilical pads are unaffected: their own dock_link
/// pairs self-heal via _reconcile_link() if one half is swept.
/obj/effect/overmap/visitable/ship/landable/drydock_ship/proc/_sweep_stray_umbilicals()
	for(var/obj/effect/portal/dock_link/L in world)
		if(GET_Z(L) in map_z)
			qdel(L)

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
