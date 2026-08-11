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
	// The base /datum/map_template default (ZTRAITS_AWAY) tags a hull's own
	// interior Z as an away site -- wrong for a ship's own home Z, and the
	// reason shield/cloak generators (is_away_level(), ship_shield_generator.dm/
	// ship_cloaking_device.dm) refused to activate while genuinely docked at
	// the ship's own drydock, not an actual away site.
	traits = list(list())
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
	/// TRUE for the shared blank-canvas shell every player-commissioned
	/// shuttle deploys onto (ship_commissioning_console.dm) -- every
	/// subtypesof()-discovered /datum/map_template/drydock_ship auto-registers
	/// into SSmapping.drydock_ship_templates (mapping.dm) and would otherwise
	/// show up as a normal purchasable hull in the Drydock program's own
	/// listing (drydock.dm) alongside real ships, which it isn't: it has no
	/// price and no pre-authored interior of its own, only whatever a player
	/// actually built and commissioned. Filtered out there by this flag.
	var/hidden_from_catalog = FALSE

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
	/// TRUE for a ship materialized via drydockCommission() -- never set for
	/// a template-bought ship (drydockBuy()/drydockRetrieve() never touch
	/// this, staying FALSE). Read by player_dock/is_valid() (docking_beacon.dm)
	/// to decide whether a beacon's own player-built-specific max footprint
	/// applies to this ship instead of its generic one.
	var/player_built = FALSE

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship
	name = "shuttle control console"

/// Cargo-orderable variant a player can build into their own commissioned
/// hull (ship_commissioning_console.dm) -- unlike the mapped-in base
/// type above (always pre-anchored, spawned pre-anchored by
/// drydockAutoFurnish() too), this one starts loose like every other kit
/// machine and needs a wrench first. shuttle_tag starts unset here --
/// drydockCommission() (persistence_shuttles.dm) assigns it once the built
/// hull is captured onto its new dedicated Z, the same way
/// drydockAutoFurnish() already does for its own auto-spawned console. From
/// then on it's persisted (get/apply_content below), since a stash tears
/// this object down and recreates it fresh on every retrieve.
/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable
	anchored = FALSE
	circuit = /obj/item/circuitboard/ship/shuttle_control
	/// Stable identity tag, lazily minted once -- lets a ship_commissioning
	/// console's saved link to this specific console survive a restart. See
	/// GLOB.drydock_linkable_devices_by_tag's own doc comment
	/// (ship_commissioning_console.dm).
	var/id_tag

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable/Initialize()
	. = ..()
	// Survives normally as a station-side object for however long it sits
	// there before being built into a hull and captured (drydockCommission(),
	// persistence_shuttles.dm) -- same registration every other player-placed
	// kit machine does in its own Initialize() (docking_beacon.dm, etc.).
	if(!id_tag)
		id_tag = "shuttle_console_[REF(src)]"
	GLOB.drydock_linkable_devices_by_tag[id_tag] = src
	if(GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable/Destroy()
	GLOB.drydock_linkable_devices_by_tag -= id_tag
	return ..()

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable/persistent_objects_get_content()
	var/list/content = list()
	content["id_tag"] = id_tag
	content["shuttle_tag"] = shuttle_tag
	return content

/**
 * shuttle_tag is restored here, but Initialize() (shuttle_console.dm) has
 * ALREADY run by this point -- objectsInstantiateRows() (persistence_objects.dm)
 * calls new typepath(spawn_turf), which runs Initialize() synchronously,
 * before ever applying saved content -- so the object's own Initialize()
 * saw shuttle_tag still unset and already filed it into
 * SSshuttle.lonely_shuttle_computers instead of the real ship's own
 * shuttle_computers list. Restoring the var alone doesn't undo that
 * bookkeeping, so redo the hookup here explicitly -- the exact same shape
 * drydockCommission()'s own capture step uses
 * (persistence_shuttles.dm:2060-2063) -- instead of relying on someone
 * happening to open the console's UI first to lazily self-heal via
 * _resolve_shuttle() (shuttle_console.dm).
 */
/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable/persistent_objects_apply_content(content, x, y, z)
	..()
	if(content["id_tag"])
		GLOB.drydock_linkable_devices_by_tag -= id_tag
		id_tag = content["id_tag"]
		GLOB.drydock_linkable_devices_by_tag[id_tag] = src
	if(content["shuttle_tag"])
		shuttle_tag = content["shuttle_tag"]
		var/datum/shuttle/shuttle = SSshuttle.shuttles[shuttle_tag]
		if(istype(shuttle))
			SSshuttle.lonely_shuttle_computers -= src
			shuttle.shuttle_computers += src

/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Shuttle control console secured in place.") : SPAN_NOTICE("Shuttle control console unsecured."))
		return TRUE
	// No facing concept for a console -- multitool just buffers it directly
	// (same multitool.dm buffer airlock controller wiring already uses), for
	// linking to a ship_commissioning console (ship_commissioning_console.dm).
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		if(!istype(attacking_item, /obj/item/multitool))
			to_chat(user, SPAN_WARNING("\The [attacking_item] can't hold a buffer."))
			return TRUE
		var/obj/item/multitool/tool = attacking_item
		tool.set_buffer(src)
		to_chat(user, SPAN_NOTICE("You buffer \the [src] into \the [tool]."))
		return TRUE
	return ..(attacking_item, user, params)

/area/drydock_ship
	name = "Drydock Ship"
	icon_state = "bluenew"
	requires_power = TRUE
	area_flags = AREA_FLAG_RAD_SHIELDED
