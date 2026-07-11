/*
 * Faction Tagger -- declarative per-type hooks
 * Mirrors the worldstate_get_content()/worldstate_apply_content() pattern:
 * any type that wants to be configurable via the faction tagger overrides
 * these three procs. The tagger item itself (code/game/objects/items/devices/
 * faction_tagger.dm) never needs to know about individual types.
 */

/// Whether this atom can be configured by the faction tagger at all.
/atom/movable/proc/faction_tagger_compatible()
	return FALSE

/// Current faction_uid this atom is shackled/networked to, or null.
/atom/movable/proc/faction_tagger_get_uid()
	return null

/// Apply a new faction_uid (or null to release). Returns TRUE on success.
/atom/movable/proc/faction_tagger_set(new_uid, mob/user)
	return FALSE

// ------- Modular computers (PDAs included -- unlike the beacon's own bulk
// sweep, the tagger is a deliberate single-target action, so personal
// devices aren't exempted here) -------

/obj/item/modular_computer/faction_tagger_compatible()
	return TRUE

/obj/item/modular_computer/faction_tagger_get_uid()
	return persistent_network

/obj/item/modular_computer/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	faction_shackled = new_uid ? TRUE : FALSE
	return TRUE

// ------- Cargo/security telepads -------

/obj/structure/machinery/telepad_cargo/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/telepad_cargo/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/telepad_cargo/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	persistent_spawn   = new_uid ? TRUE : FALSE
	faction_shackled   = new_uid ? TRUE : FALSE
	return TRUE

// ------- Cryopods -------

/obj/structure/machinery/cryopod/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/cryopod/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/cryopod/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	persistent_spawn   = new_uid ? TRUE : FALSE
	// Spawned (non-map-placed) pods need to register with persistent_objects
	// to be recreated on restart -- map-placed pods use worldstate instead,
	// which already runs automatically. Safe to call even if already tracked.
	if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)
	return TRUE

// ------- Neural lace vault -------

/obj/structure/machinery/lace_storage/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/lace_storage/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/lace_storage/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	return TRUE

// ------- Telecomms machinery -------

/obj/structure/machinery/telecomms/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/telecomms/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/telecomms/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	return TRUE

// ------- Autodoc (restricts treatment to the tagged faction -- see the
// authorization gate in patient_acceptable(), autodoc.dm) -------

/obj/structure/machinery/autodoc/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/autodoc/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/autodoc/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	return TRUE

// ------- Faction beacon (delegates to its own network-sweep logic) -------

/obj/structure/machinery/faction_beacon/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/faction_beacon/faction_tagger_get_uid()
	return faction_uid

/obj/structure/machinery/faction_beacon/faction_tagger_set(new_uid, mob/user)
	if(!new_uid)
		faction_uid = ""
		active = FALSE
		_release_z_claim()
		update_icon()
		return TRUE
	var/refusal = _claim_refusal_reason()
	if(refusal)
		to_chat(user, SPAN_WARNING("Cannot activate: [refusal]."))
		return FALSE
	faction_uid = new_uid
	_apply_network()
	return TRUE

// ------- Airlock (delegates to the pre-existing req_access_faction lock --
// see allowed() in airlock.dm, already fully persisted via worldstate_vars) -------

/obj/structure/machinery/door/airlock/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/door/airlock/faction_tagger_get_uid()
	return req_access_faction

/obj/structure/machinery/door/airlock/faction_tagger_set(new_uid, mob/user)
	req_access_faction = new_uid || ""
	return TRUE

// ------- Portable turrets (ownership marker + faction-aware targeting mode,
// see turret_faction_target_mode in portable_turret.dm) -------

/obj/structure/machinery/porta_turret/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/porta_turret/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/porta_turret/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	return TRUE
