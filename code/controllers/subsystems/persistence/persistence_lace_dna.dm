/*
 * Persistence - Neural Lace DNA/Species
 *
 * A neural lace's /datum/dna and organ species singleton now get synced to
 * whichever body it's installed in every time it's genuinely surgically
 * replaced() (organs_internal.dm's transplant step, and the resleever's own
 * _do_resleeve(), resleever.dm, which now calls that same proc instead of
 * hand-splicing organ lists). See get_lace_dna_snapshot()/
 * apply_lace_dna_snapshot() (neural_lace.dm) for what's actually captured.
 *
 * Without this table that sync only lives as long as the physical lace
 * object does -- persistence_mobs.dm's existing augment save/restore already
 * round-trips lace_damage/registered_name/registered_ckey/owner_faction, but
 * rebuilds the lace fresh via new() on restore, which reset dna/species to
 * blank regardless of what they'd last been synced to.
 *
 * Keyed (ckey, char_name) like every other ss13_char_* table -- specifically
 * the LACE's own registered_ckey/registered_name (whoever it represents),
 * not whatever body happens to currently house it, the same way
 * stored_skills already works. Round-trips through the exact same save/
 * restore call sites as those other four fields (persistence_mobs.dm's
 * organ-augment block), not a separate periodic sweep.
 *
 * Shape mirrors the ss13_char_skills round trip in persistence_skills.dm --
 * cache, boot load, save-with-central-writethrough, read-back-with-
 * central-readthrough. Central sync is gated behind CENTRAL_SYNC_CHARACTERS
 * by the shared helpers, so with central off none of it runs.
 */

/// Cached lace DNA rows, keyed "[ckey]|[char_name]" -> dna_json string.
GLOBAL_LIST_EMPTY(persistence_lace_dna_cache)

/// Cached admin-set clone-species overrides, keyed "[ckey]|[char_name]" ->
/// species id string. Deliberately a separate cache from the one above --
/// this one is only ever written by the "Modify Neural Lace" admin panel,
/// never by the automatic organ-replaced() dna sync.
GLOBAL_LIST_EMPTY(persistence_lace_species_override_cache)

/**
 * Load every saved lace DNA row (and any admin species override) into the
 * cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_lace_dna_cache = list()
	GLOB.persistence_lace_species_override_cache = list()

	if(!databaseCheckConnection("charLaceDnaInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, dna_json, species_override FROM ss13_char_lace_dna",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "charLaceDnaInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/key = "[query.item[1]]|[query.item[2]]"
		GLOB.persistence_lace_dna_cache[key] = query.item[3]
		if(!isnull(query.item[4]))
			GLOB.persistence_lace_species_override_cache[key] = query.item[4]
		loaded++
	qdel(query)
	log_subsystem_persistence_info("CharLaceDna: Loaded [loaded] lace DNA entries.")

/**
 * Writes one character's lace DNA snapshot. Called directly from
 * persistence_mobs.dm's existing organ-augment save block, the same moment
 * lace_damage/registered_name/registered_ckey/owner_faction get captured --
 * not a separate periodic sweep.
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaSaveOne(ckey, char_name, dna_json)
	if(!ckey || !char_name || !dna_json)
		return FALSE
	if(!databaseCheckConnection("charLaceDnaSaveOne"))
		return FALSE

	var/datum/db_query/query = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_lace_dna (ckey, char_name, dna_json)
		VALUES (:ckey, :char_name, :dna_json)
		ON DUPLICATE KEY UPDATE dna_json = VALUES(dna_json), saved_at = NOW()"},
		list("ckey" = ckey, "char_name" = char_name, "dna_json" = dna_json)
	)
	query.Execute()
	var/success = databaseCheckQueryResult(query, "charLaceDnaSaveOne")
	qdel(query)
	if(!success)
		return FALSE

	GLOB.persistence_lace_dna_cache["[ckey]|[char_name]"] = dna_json
	_centralCharacterWriteThrough("ss13_char_lace_dna",
		list("ckey", "char_name", "dna_json"),
		list(ckey, char_name, dna_json))
	return TRUE

/**
 * Resolves a character's saved lace DNA snapshot -- cache first, then a
 * central read-through + local self-heal on a miss, mirroring
 * applyPersistentSkills()'s own resolution exactly. Returns the decoded
 * snapshot list (get_lace_dna_snapshot()'s own shape), or null if nothing is
 * found anywhere -- a lace that's never been synced to a body has nothing
 * saved, which is normal, not an error.
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaResolve(ckey, char_name)
	if(!ckey || !char_name)
		return null

	var/key = "[ckey]|[char_name]"
	var/dna_json = GLOB.persistence_lace_dna_cache[key]

	if(isnull(dna_json))
		var/list/row = _centralCharacterReadThrough("ss13_char_lace_dna", list("dna_json"), ckey, char_name)
		if(row)
			dna_json = row[1]
		if(!isnull(dna_json))
			GLOB.persistence_lace_dna_cache[key] = dna_json
			_centralCharacterSelfHealLocal("ss13_char_lace_dna",
				list("ckey", "char_name", "dna_json"),
				list(ckey, char_name, dna_json))

	if(isnull(dna_json))
		return null

	var/list/decoded
	try
		decoded = json_decode(dna_json)
	catch(var/exception/decode_e)
		log_subsystem_persistence_error("CharLaceDna: could not decode lace DNA for [key]: [decode_e]")
		return null
	if(!islist(decoded) || !length(decoded))
		return null
	return decoded

/**
 * Sets (or clears, with a null/empty species_override) the admin-controlled
 * clone-species override for (ckey, char_name). Read by
 * build_cloned_body_for_character() (resleever_cloning.dm) to decide what
 * species a fresh clone of this character grows as -- completely separate
 * from dna_json above, which is only ever written by the automatic organ
 * replaced() sync and must never be touched here.
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaSetSpeciesOverride(ckey, char_name, species_override)
	if(!ckey || !char_name)
		return FALSE
	if(!databaseCheckConnection("charLaceDnaSetSpeciesOverride"))
		return FALSE

	if(!species_override)
		species_override = null

	var/datum/db_query/query = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_lace_dna (ckey, char_name, species_override)
		VALUES (:ckey, :char_name, :species_override)
		ON DUPLICATE KEY UPDATE species_override = VALUES(species_override), saved_at = NOW()"},
		list("ckey" = ckey, "char_name" = char_name, "species_override" = species_override)
	)
	query.Execute()
	var/success = databaseCheckQueryResult(query, "charLaceDnaSetSpeciesOverride")
	qdel(query)
	if(!success)
		return FALSE

	var/key = "[ckey]|[char_name]"
	if(isnull(species_override))
		GLOB.persistence_lace_species_override_cache -= key
	else
		GLOB.persistence_lace_species_override_cache[key] = species_override

	_centralCharacterWriteThrough("ss13_char_lace_dna",
		list("ckey", "char_name", "species_override"),
		list(ckey, char_name, species_override))
	return TRUE

/**
 * Resolves the admin-set clone-species override for (ckey, char_name) --
 * cache first, then a central read-through + local self-heal on a miss, same
 * shape as charLaceDnaResolve(). Returns the species id string (a
 * GLOB.all_species key), or null if no override is set -- which is the
 * normal case, meaning clone growth should use the character's own chargen
 * species untouched.
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaGetSpeciesOverride(ckey, char_name)
	if(!ckey || !char_name)
		return null

	var/key = "[ckey]|[char_name]"
	if(GLOB.persistence_lace_species_override_cache[key])
		return GLOB.persistence_lace_species_override_cache[key]

	// A cache miss is ambiguous between "no override" and "never loaded" --
	// only worth a central round-trip when central sync is actually on,
	// otherwise every override-less clone would pay a central lookup for
	// nothing.
	var/list/row = _centralCharacterReadThrough("ss13_char_lace_dna", list("species_override"), ckey, char_name)
	if(row && !isnull(row[1]))
		GLOB.persistence_lace_species_override_cache[key] = row[1]
		_centralCharacterSelfHealLocal("ss13_char_lace_dna",
			list("ckey", "char_name", "species_override"),
			list(ckey, char_name, row[1]))
		return row[1]
	return null

// ============================================================
// ADMIN: MODIFY NEURAL LACE
// ============================================================
//
// Lets an admin view and edit a (ckey, char_name) character's neural lace
// data even when they're offline and no physical lace exists anywhere --
// same targeting shape as Modify Skills (persistence_skills.dm). Two
// independent concerns live in one panel:
//   - Clone-species override (charLaceDnaSetSpeciesOverride() above): always
//     editable, purely a DB row, no physical lace required. This is what
//     changes what species a FUTURE clone of this character grows as
//     (build_cloned_body_for_character(), resleever_cloning.dm) -- clearing
//     it reverts to their normal chargen species.
//   - Physical lace fields (lace_damage, owner_faction): only editable when
//     a matching lace object actually exists somewhere in the world right
//     now (installed, vaulted, or loose) -- found via the same world-scan
//     idiom jump_to_neural_lace() (adminjump.dm) uses. Written directly onto
//     the object; the existing organ-augment save path (persistence_mobs.dm)
//     already round-trips them whenever that lace/body is next saved.

/datum/admins/proc/modify_neural_lace()
	set name = "Modify Neural Lace"
	set category = "Persistence.Characters"
	set desc = "View or edit a character's neural lace data, online or offline."

	if(!check_rights(R_ADMIN))
		return

	var/target_ckey = tgui_input_text(usr, "Enter ckey:", "Modify Neural Lace", usr.ckey, max_length = 32)
	if(!target_ckey) return
	target_ckey = ckey(target_ckey)

	var/char_name
	var/list/characters = persistence_get_saved_characters(target_ckey)
	if(length(characters) > 1)
		char_name = tgui_input_list(usr, "Which character?", "Modify Neural Lace", characters)
		if(!char_name) return
	else if(length(characters) == 1)
		char_name = characters[1]
	else
		char_name = tgui_input_text(usr, "No cached characters found for '[target_ckey]'. Exact character name:", "Modify Neural Lace", "", max_length = 64, encode = FALSE)
		if(!char_name) return

	var/datum/tgui_module/admin/lace_editor/panel = new(target_ckey, char_name)
	panel.ui_interact(usr)

/datum/tgui_module/admin/lace_editor
	var/target_ckey
	var/target_char_name

/datum/tgui_module/admin/lace_editor/New(ckey, char_name)
	. = ..()
	target_ckey = ckey
	target_char_name = char_name

/datum/tgui_module/admin/lace_editor/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LaceEditor", "Modify Neural Lace", 480, 520)
		ui.open()

/// Finds a physical neural lace object registered to this identity anywhere
/// in the world (installed, vaulted, disembodied-consciousness, or loose),
/// classified the same way jump_to_neural_lace() (adminjump.dm) does. Null
/// if none exists -- normal for a character who's never died with a lace
/// installed, not an error.
/datum/tgui_module/admin/lace_editor/proc/_resolve_live_lace()
	for(var/obj/item/organ/internal/neural_lace/candidate in world)
		if(QDELETED(candidate))
			continue
		if(candidate.registered_ckey != target_ckey || candidate.registered_name != target_char_name)
			continue
		return candidate
	return null

/datum/tgui_module/admin/lace_editor/proc/_lace_status(obj/item/organ/internal/neural_lace/L)
	if(istype(L.loc, /obj/structure/machinery/lace_storage))
		return "Vaulted"
	if(L.owner)
		return (L.owner.stat == DEAD) ? "Installed (corpse)" : "Installed (alive)"
	if(L.lace_occupied)
		return "Consciousness, unvaulted"
	return "Loose"

/// TRUE if a GLOB.all_species key names an organically-cloneable species --
/// species_organically_cloneable() (mob_helpers.dm). Shared by the dropdown
/// build below and _apply_changes()' validation.
/datum/tgui_module/admin/lace_editor/proc/_species_cloneable(species_name)
	return species_organically_cloneable(GLOB.all_species[species_name])

/datum/tgui_module/admin/lace_editor/ui_data(mob/user)
	var/list/data = list()
	data["ckey"] = target_ckey
	data["char_name"] = target_char_name
	data["species_override"] = SSpersistence.charLaceDnaGetSpeciesOverride(target_ckey, target_char_name) || ""

	var/list/species_options = list()
	for(var/species_name in GLOB.all_species)
		if(_species_cloneable(species_name))
			species_options += species_name
	data["species_options"] = species_options

	var/obj/item/organ/internal/neural_lace/L = _resolve_live_lace()
	if(L)
		data["lace_status"] = _lace_status(L)
		data["lace_damage"] = L.lace_damage
		data["owner_faction"] = L.owner_faction
	else
		data["lace_status"] = null
		data["lace_damage"] = null
		data["owner_faction"] = null
	return data

/datum/tgui_module/admin/lace_editor/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(!check_rights(R_ADMIN))
		log_and_message_admins("attempted to use the Modify Neural Lace panel without sufficient rights.")
		return

	if(action == "apply")
		_apply_changes(usr, params)
		return TRUE

/datum/tgui_module/admin/lace_editor/proc/_apply_changes(mob/admin, list/params)
	var/list/log_lines = list()

	var/new_override = params["species_override"]
	if(!isnull(new_override))
		new_override = trim("[new_override]")
		if(length(new_override) && !_species_cloneable(new_override))
			to_chat(admin, SPAN_WARNING("'[new_override]' is not a valid, organically-cloneable species -- ignored."))
		else
			var/old_override = SSpersistence.charLaceDnaGetSpeciesOverride(target_ckey, target_char_name) || ""
			var/normalized_new = length(new_override) ? new_override : null
			if(normalized_new != (length(old_override) ? old_override : null))
				SSpersistence.charLaceDnaSetSpeciesOverride(target_ckey, target_char_name, normalized_new)
				log_lines += "Clone species override: [length(old_override) ? old_override : "(none)"] -> [normalized_new || "(none, use character default)"]"

	var/obj/item/organ/internal/neural_lace/L = _resolve_live_lace()
	if(L)
		if(!isnull(params["lace_damage"]))
			var/new_damage = clamp(text2num(params["lace_damage"]) || 0, 0, L.lace_max_damage)
			if(new_damage != L.lace_damage)
				log_lines += "Lace damage: [L.lace_damage] -> [new_damage]"
				L.lace_damage = new_damage
		if(!isnull(params["owner_faction"]))
			var/new_faction_raw = trim("[params["owner_faction"]]")
			var/new_faction = length(new_faction_raw) ? normalize_faction_uid(new_faction_raw) : ""
			if(length(new_faction) && !get_faction_name(new_faction))
				to_chat(admin, SPAN_WARNING("'[new_faction_raw]' is not a recognized faction -- owner faction left unchanged."))
			else if(new_faction != L.owner_faction)
				log_lines += "Owner faction: [L.owner_faction || "(none)"] -> [new_faction || "(none)"]"
				L.owner_faction = new_faction

	if(!length(log_lines))
		to_chat(admin, SPAN_NOTICE("No changes made."))
		return

	to_chat(admin, SPAN_GOOD("Updated [target_char_name]'s neural lace:\n[jointext(log_lines, "\n")]"))
	log_and_message_admins("modified [target_char_name]'s ([target_ckey]) neural lace: [jointext(log_lines, ", ")]", admin)
