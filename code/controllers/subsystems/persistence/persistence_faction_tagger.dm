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
	// Spawned (non-map-placed) pads need to register with persistent_objects
	// to be recreated on restart -- map-placed pads use worldstate instead,
	// which already runs automatically. Mirrors cryopod/faction_tagger_set()
	// above; this pad type was previously missing this call entirely, so a
	// player-dropped (telepad_beacon) pad silently never survived a restart.
	if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)
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

// ------- Clothing/equipment (tints to the faction's color, get_faction_color()/
// set_faction_color(), persistence_factions.dm) -- unlike every other type
// above, this is a genuinely portable item, not fixed machinery, so it
// persists via the generic persistent_objects_get_content()/apply_content()
// passthrough (serializePersistentItem(), persistence_mobs.dm) instead of
// worldstate/objectsRegisterTrack -- that passthrough already fires for an
// item wherever it happens to be serialized (character inventory, closet
// contents, or loose floor items), no registration call needed here. -------

/// Original (pre-tag) color, captured once ever on first tag so "Default"
/// (the tagger's existing "release" action) can restore it exactly --
/// never recaptured on later tag/release cycles so it can't drift into
/// whatever the faction color happened to be at the time.
/obj/item/clothing/var/faction_tag_uid = null
/obj/item/clothing/var/faction_tag_original_color = null
/obj/item/clothing/var/faction_tag_original_captured = FALSE

/obj/item/clothing/faction_tagger_compatible()
	return TRUE

/obj/item/clothing/faction_tagger_get_uid()
	return faction_tag_uid

/obj/item/clothing/faction_tagger_set(new_uid, mob/user)
	if(!faction_tag_original_captured)
		faction_tag_original_color = color
		faction_tag_original_captured = TRUE
	faction_tag_uid = new_uid
	color = new_uid ? get_faction_color(new_uid) : faction_tag_original_color
	update_icon()
	update_clothing_icon()
	return TRUE

/// Generic persistence passthrough (see serializePersistentItem(),
/// persistence_mobs.dm) -- no-op until this item has actually been tagged at
/// least once, so untagged clothing (the overwhelming majority) never grows
/// an extra saved blob.
/obj/item/clothing/persistent_objects_get_content()
	var/list/content = ..()
	if(!faction_tag_original_captured)
		return content
	content["faction_tag_uid"] = faction_tag_uid
	content["faction_tag_original_color"] = faction_tag_original_color
	content["faction_tag_original_captured"] = TRUE
	return content

/// Re-resolves color from the faction's CURRENT color (not a frozen saved
/// value) so a restored item stays consistent even if the faction's color
/// changed while this item was serialized away.
/obj/item/clothing/persistent_objects_apply_content(content, x, y, z)
	. = ..()
	if(!islist(content) || !content["faction_tag_original_captured"])
		return
	faction_tag_uid = content["faction_tag_uid"]
	faction_tag_original_color = content["faction_tag_original_color"]
	faction_tag_original_captured = TRUE
	color = faction_tag_uid ? get_faction_color(faction_tag_uid) : faction_tag_original_color
	update_icon()
	update_clothing_icon()

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

// ------- Docking beacon (drydock pads/corvette docking -- "public" is
// just the released/unclaimed state, matching the beacon's own ID-swipe
// wording) -------

/obj/structure/machinery/docking_beacon/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/docking_beacon/faction_tagger_get_uid()
	return faction_restricted

/obj/structure/machinery/docking_beacon/faction_tagger_set(new_uid, mob/user)
	if(!beacon_active)
		to_chat(user, SPAN_WARNING("Activate \the [src] before configuring its faction access."))
		return FALSE
	faction_restricted = new_uid || ""
	beacon_shackled     = new_uid ? TRUE : FALSE
	_sync_landmark_faction()
	return TRUE
