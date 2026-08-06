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

/// "ckey|char_name" composite for whoever this atom is personally tagged
/// to, or null if untagged. Mirrors the (ckey, char_name) identity pairing
/// used throughout this codebase (drydock ships' owned_by(), neural lace's
/// registered_ckey/registered_name) -- a personal tag belongs to a
/// CHARACTER, not just an account.
/atom/movable/proc/personal_tagger_get_owner()
	return null

/// Personally tags this atom to user (self only -- there is no "tag it to
/// someone else" path). Returns TRUE on success.
/atom/movable/proc/personal_tagger_set(mob/user)
	return FALSE

/// TRUE if this atom is tagged to its drydock ship's crew. Unlike
/// faction_tagger_get_uid()/personal_tagger_get_owner(), this carries no
/// identity of its own -- "crew" is resolved dynamically per-Z at
/// access-check time (_drydock_crew_check(), telepad_drydock_boarding.dm)
/// against whichever ship currently occupies that Z, so a plain boolean is
/// all this atom needs to remember.
/atom/movable/proc/crew_tagger_is_set()
	return FALSE

/// Tags this atom to its drydock ship's crew (owner + crew_ckeys), clearing
/// whichever of the other two mutually-exclusive modes (Faction/Personal)
/// was active. Returns TRUE on success.
/atom/movable/proc/crew_tagger_set(mob/user)
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
	// Faction and personal/crew tags are mutually exclusive.
	personal_ckey = null
	personal_char_name = null
	crew_tagged = FALSE
	return TRUE

/obj/item/modular_computer/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/item/modular_computer/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	// Mutually exclusive with a faction/crew tag.
	persistent_network = ""
	faction_shackled = FALSE
	crew_tagged = FALSE
	return TRUE

/obj/item/modular_computer/crew_tagger_is_set()
	return crew_tagged

/obj/item/modular_computer/crew_tagger_set(mob/user)
	crew_tagged = TRUE
	// Mutually exclusive with a faction/personal tag.
	persistent_network = ""
	faction_shackled = FALSE
	personal_ckey = null
	personal_char_name = null
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
	// Faction and personal/crew tags are mutually exclusive.
	personal_ckey = null
	personal_char_name = null
	crew_tagged = FALSE
	// Spawned (non-map-placed) pads need to register with persistent_objects
	// to be recreated on restart -- map-placed pads use worldstate instead,
	// which already runs automatically. Mirrors cryopod/faction_tagger_set()
	// above; this pad type was previously missing this call entirely, so a
	// player-dropped (telepad_beacon) pad silently never survived a restart.
	if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)
	return TRUE

/obj/structure/machinery/telepad_cargo/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/structure/machinery/telepad_cargo/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	persistent_spawn = TRUE // still "accepts deliveries", just keyed to a person now
	// Mutually exclusive with a faction/crew tag.
	persistent_network = ""
	faction_shackled = FALSE
	crew_tagged = FALSE
	if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)
	return TRUE

/obj/structure/machinery/telepad_cargo/crew_tagger_is_set()
	return crew_tagged

/obj/structure/machinery/telepad_cargo/crew_tagger_set(mob/user)
	crew_tagged = TRUE
	persistent_spawn = TRUE // still "accepts deliveries", just keyed to the ship's crew now
	// Mutually exclusive with a faction/personal tag.
	persistent_network = ""
	faction_shackled = FALSE
	personal_ckey = null
	personal_char_name = null
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
	// Faction and personal/crew tags are mutually exclusive.
	personal_ckey = null
	personal_char_name = null
	crew_tagged = FALSE
	// Spawned (non-map-placed) pods need to register with persistent_objects
	// to be recreated on restart -- map-placed pods use worldstate instead,
	// which already runs automatically. Safe to call even if already tracked.
	if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)
	return TRUE

/obj/structure/machinery/cryopod/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/structure/machinery/cryopod/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	// Mutually exclusive with a faction/crew tag.
	persistent_network = ""
	persistent_spawn = FALSE
	crew_tagged = FALSE
	if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)
	return TRUE

/obj/structure/machinery/cryopod/crew_tagger_is_set()
	return crew_tagged

/obj/structure/machinery/cryopod/crew_tagger_set(mob/user)
	crew_tagged = TRUE
	// Mutually exclusive with a faction/personal tag.
	persistent_network = ""
	persistent_spawn = FALSE
	personal_ckey = null
	personal_char_name = null
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
	// Faction and personal/crew tags are mutually exclusive.
	personal_ckey = null
	personal_char_name = null
	crew_tagged = FALSE
	return TRUE

/obj/structure/machinery/autodoc/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/structure/machinery/autodoc/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	// Mutually exclusive with a faction/crew tag.
	persistent_network = ""
	crew_tagged = FALSE
	return TRUE

/obj/structure/machinery/autodoc/crew_tagger_is_set()
	return crew_tagged

/obj/structure/machinery/autodoc/crew_tagger_set(mob/user)
	crew_tagged = TRUE
	// Mutually exclusive with a faction/personal tag.
	persistent_network = ""
	personal_ckey = null
	personal_char_name = null
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
/obj/item/clothing/var/faction_tag_original_accent_color = null
/obj/item/clothing/var/faction_tag_original_captured = FALSE

/obj/item/clothing/faction_tagger_compatible()
	return TRUE

/obj/item/clothing/faction_tagger_get_uid()
	return faction_tag_uid

/// Tints only the accent overlay (has_accents/accent_color, items.dm) when
/// this item actually has one -- the base garment's own color stays
/// untouched, so tagging doesn't blot out the item's own look. Items with
/// no accent layer fall back to the original full-atom recolor, since
/// accent_color would otherwise have nothing to tint and tagging would
/// silently become invisible.
/obj/item/clothing/faction_tagger_set(new_uid, mob/user)
	if(!faction_tag_original_captured)
		faction_tag_original_color = color
		faction_tag_original_accent_color = accent_color
		faction_tag_original_captured = TRUE
	faction_tag_uid = new_uid
	if(has_accents)
		accent_color = new_uid ? get_faction_color(new_uid) : faction_tag_original_accent_color
	else
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
	content["faction_tag_original_accent_color"] = faction_tag_original_accent_color
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
	faction_tag_original_accent_color = content["faction_tag_original_accent_color"]
	faction_tag_original_captured = TRUE
	if(has_accents)
		accent_color = faction_tag_uid ? get_faction_color(faction_tag_uid) : faction_tag_original_accent_color
	else
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
	// Mutually exclusive with a crew tag.
	crew_tagged = FALSE
	return TRUE

/obj/structure/machinery/door/airlock/crew_tagger_is_set()
	return crew_tagged

/obj/structure/machinery/door/airlock/crew_tagger_set(mob/user)
	crew_tagged = TRUE
	// Mutually exclusive with a faction tag (airlocks have no Personal mode).
	req_access_faction = ""
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

/*
 * One-time admin remedy for a fixed bug: _sweep_unassigned_objects_for_faction()
 * (faction_beacon.dm) used to claim a cryopod/telepad_cargo/modular computer/
 * autodoc for a faction without checking personal_ckey first, clobbering an
 * already personally-tagged device with a faction network on top instead of
 * skipping it -- leaving both set simultaneously (mutual exclusivity broken).
 * The sweep itself is fixed now (checks personal_ckey before claiming), but
 * that doesn't retroactively repair devices already left in this state.
 * Personal wins on repair -- the sweep is what mistakenly added the faction
 * tag on top of a deliberately-set personal one, never the other way around.
 * Restores each type to exactly the state its own personal_tagger_set()
 * would have left it in.
 */
/datum/admins/proc/repair_dual_tagged_devices()
	set name = "Repair Dual-Tagged Devices"
	set category = "Persistence"
	set desc = "Finds cryopods/telepads/computers/autodocs left tagged to both a faction AND a personal owner by a now-fixed sweep bug -- clears the erroneous faction tag, keeps the personal one."

	if(!check_rights(R_ADMIN))
		return

	var/list/fixed_lines = list()

	for(var/obj/structure/machinery/cryopod/pod in world)
		if(!pod.personal_ckey || !pod.persistent_network)
			continue
		var/turf/T = get_turf(pod)
		fixed_lines += "Cryopod at ([T.x],[T.y],[T.z]): faction '[pod.persistent_network]' cleared, kept personal to [pod.personal_ckey]|[pod.personal_char_name]"
		pod.persistent_network = ""
		pod.persistent_spawn = FALSE
		if(!pod.persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
			SSpersistence.objectsRegisterTrack(pod)

	for(var/obj/structure/machinery/telepad_cargo/pad in world)
		if(!pad.personal_ckey || !pad.persistent_network)
			continue
		var/turf/T = get_turf(pad)
		fixed_lines += "Cargo telepad at ([T.x],[T.y],[T.z]): faction '[pad.persistent_network]' cleared, kept personal to [pad.personal_ckey]|[pad.personal_char_name]"
		pad.persistent_network = ""
		pad.persistent_spawn = TRUE // still "accepts deliveries", just keyed to a person -- matches personal_tagger_set()
		pad.faction_shackled = FALSE
		if(!pad.persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
			SSpersistence.objectsRegisterTrack(pad)

	for(var/obj/item/modular_computer/MC in world)
		if(!MC.personal_ckey || !MC.persistent_network)
			continue
		var/turf/T = get_turf(MC)
		fixed_lines += "Modular computer at ([T.x],[T.y],[T.z]): faction '[MC.persistent_network]' cleared, kept personal to [MC.personal_ckey]|[MC.personal_char_name]"
		MC.persistent_network = ""
		MC.faction_shackled = FALSE

	for(var/obj/structure/machinery/autodoc/AD in world)
		if(!AD.personal_ckey || !AD.persistent_network)
			continue
		var/turf/T = get_turf(AD)
		fixed_lines += "Autodoc at ([T.x],[T.y],[T.z]): faction '[AD.persistent_network]' cleared, kept personal to [AD.personal_ckey]|[AD.personal_char_name]"
		AD.persistent_network = ""

	if(!length(fixed_lines))
		to_chat(usr, SPAN_NOTICE("No dual-tagged devices found."))
		return

	to_chat(usr, SPAN_GOOD("Repaired [length(fixed_lines)] dual-tagged device(s):\n[jointext(fixed_lines, "\n")]"))
	log_and_message_admins("ran Repair Dual-Tagged Devices -- fixed [length(fixed_lines)] device(s): [jointext(fixed_lines, "; ")]", usr)

