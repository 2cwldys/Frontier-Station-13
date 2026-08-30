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

/// Cached one-time pre-resleeve species backups, keyed "[ckey]|[char_name]"
/// -> species id string. Written automatically by
/// persistence_sync_character_species() the first time it changes a
/// character's permanent chargen species; cleared by the "Modify Neural
/// Lace" panel's Restore Original Species action once consumed.
GLOBAL_LIST_EMPTY(persistence_lace_original_species_cache)

/**
 * Load every saved lace DNA row (and any admin species override) into the
 * cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_lace_dna_cache = list()
	GLOB.persistence_lace_species_override_cache = list()
	GLOB.persistence_lace_original_species_cache = list()

	if(!databaseCheckConnection("charLaceDnaInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, dna_json, species_override, original_species FROM ss13_char_lace_dna",
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
		if(!isnull(query.item[5]))
			GLOB.persistence_lace_original_species_cache[key] = query.item[5]
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

/**
 * Sets (or clears, with a null original_species) the one-time pre-resleeve
 * species backup for (ckey, char_name). Written automatically by
 * persistence_sync_character_species() the first time it changes this
 * character's permanent species; cleared by the "Modify Neural Lace" panel's
 * Restore Original Species action once consumed. Never touched by anything
 * else -- completely separate from species_override (an admin's forward-
 * looking clone choice) and dna_json (the lace object's own auto-synced
 * physical state) above.
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaSetOriginalSpecies(ckey, char_name, original_species)
	if(!ckey || !char_name)
		return FALSE
	if(!databaseCheckConnection("charLaceDnaSetOriginalSpecies"))
		return FALSE

	if(!original_species)
		original_species = null

	var/datum/db_query/query = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_lace_dna (ckey, char_name, original_species)
		VALUES (:ckey, :char_name, :original_species)
		ON DUPLICATE KEY UPDATE original_species = VALUES(original_species), saved_at = NOW()"},
		list("ckey" = ckey, "char_name" = char_name, "original_species" = original_species)
	)
	query.Execute()
	var/success = databaseCheckQueryResult(query, "charLaceDnaSetOriginalSpecies")
	qdel(query)
	if(!success)
		return FALSE

	var/key2 = "[ckey]|[char_name]"
	if(isnull(original_species))
		GLOB.persistence_lace_original_species_cache -= key2
	else
		GLOB.persistence_lace_original_species_cache[key2] = original_species

	_centralCharacterWriteThrough("ss13_char_lace_dna",
		list("ckey", "char_name", "original_species"),
		list(ckey, char_name, original_species))
	return TRUE

/**
 * Resolves the pre-resleeve species backup for (ckey, char_name) -- cache
 * first, then a central read-through + local self-heal on a miss, same
 * shape as charLaceDnaGetSpeciesOverride(). Returns the species id string,
 * or null if no backup is on record -- the normal case for a character
 * who's never been resleeved into a different species.
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaGetOriginalSpecies(ckey, char_name)
	if(!ckey || !char_name)
		return null

	var/key3 = "[ckey]|[char_name]"
	if(GLOB.persistence_lace_original_species_cache[key3])
		return GLOB.persistence_lace_original_species_cache[key3]

	var/list/row3 = _centralCharacterReadThrough("ss13_char_lace_dna", list("original_species"), ckey, char_name)
	if(row3 && !isnull(row3[1]))
		GLOB.persistence_lace_original_species_cache[key3] = row3[1]
		_centralCharacterSelfHealLocal("ss13_char_lace_dna",
			list("ckey", "char_name", "original_species"),
			list(ckey, char_name, row3[1]))
		return row3[1]
	return null

/**
 * Syncs a character's PERMANENT chargen species (ss13_characters.species) to
 * match whatever they actually just got embodied as -- called
 * unconditionally after every successful consciousness transfer
 * (resleever.dm's _do_resleeve(), neural_lace.dm's
 * _transfer_consciousness_into()), regardless of whether an admin species
 * override was involved. Without this, PersistentAutoSpawn() (new_player.dm)
 * reloads species fresh from this same column on every spawn and silently
 * reverts a resleeved character to their old species the next time they
 * Store Character and hit Play -- ss13_char_lace_dna's species_override only
 * ever affects the ONE clone body grown at order_clone_from_lace() time
 * (resleever_cloning.dm), never the character's own permanent record.
 *
 * A no-op when the species already matches -- the overwhelmingly common
 * case (resleeving back into your own native species), so this is safe to
 * call unconditionally rather than gating callers on "was an override
 * involved". Captures a one-time original-species backup (above) the first
 * time it actually changes something, so the "Modify Neural Lace" panel can
 * offer to revert it later.
 *
 * organs_data/organs_robotic are reset to blank on an actual species change
 * -- those are chargen-UI-authored, species-specific prosthetic/amputation
 * choices (preference_setup/general/03_body.dm); leaving stale entries
 * authored for the OLD species' limb layout risks copy_to() choking on a
 * preference that doesn't map onto the new species at all. Round-time
 * appearance is driven by the saved health/organ JSON overlay
 * (mobsHealthRestoreOne, persistence_mobs.dm) regardless, so losing this
 * chargen default costs nothing real.
 *
 * Writes directly via SQL rather than through save_character() (which
 * refuses once first_spawned_at is set) -- same bypass pattern already
 * established by save_metadata_to_db() (preference_setup/general/01_basic.dm).
 */
/proc/persistence_sync_character_species(ckey, char_name, datum/species/S)
	if(!ckey || !char_name || !istype(S) || !GLOB.config.sql_saves || !SSdbcore.Connect())
		return

	var/datum/db_query/current_q = SSdbcore.NewQuery(
		"SELECT species FROM ss13_characters WHERE ckey = :ckey AND name = :name AND deleted_at IS NULL LIMIT 1",
		list("ckey" = ckey, "name" = char_name))
	current_q.Execute()
	var/current_species
	if(current_q.NextRow())
		current_species = current_q.item[1]
	qdel(current_q)

	if(current_species == S.name)
		return

	if(isnull(SSpersistence.charLaceDnaGetOriginalSpecies(ckey, char_name)))
		SSpersistence.charLaceDnaSetOriginalSpecies(ckey, char_name, current_species)

	var/datum/db_query/upd = SSdbcore.NewQuery(
		{"UPDATE ss13_characters SET species = :species, organs_data = '', organs_robotic = ''
		WHERE ckey = :ckey AND name = :name AND deleted_at IS NULL"},
		list("ckey" = ckey, "name" = char_name, "species" = S.name))
	upd.Execute()
	SSpersistence.databaseCheckQueryResult(upd, "persistence_sync_character_species")
	qdel(upd)
	log_subsystem_persistence_info("CharLaceDna: Synced [char_name]'s ([ckey]) chargen species [current_species || "(none)"] -> [S.name].")

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
	data["original_species"] = SSpersistence.charLaceDnaGetOriginalSpecies(target_ckey, target_char_name) || ""

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

	if(action == "restore_original_species")
		_restore_original_species(usr)
		return TRUE

/**
 * Reverts this character's permanent chargen species (ss13_characters.species)
 * to whatever it was before the first time a lace resleeve/robotic transfer
 * changed it (persistence_sync_character_species(), above). One-shot: the
 * backup is cleared once consumed, since the current state IS the original
 * again afterward -- a later resleeve into yet another species captures a
 * fresh backup from whatever's current at that point.
 */
/datum/tgui_module/admin/lace_editor/proc/_restore_original_species(mob/admin)
	var/original = SSpersistence.charLaceDnaGetOriginalSpecies(target_ckey, target_char_name)
	if(!original)
		to_chat(admin, SPAN_WARNING("No original species is on record for [target_char_name] -- nothing to restore."))
		return

	var/datum/species/S = GLOB.all_species[original]
	if(!istype(S))
		to_chat(admin, SPAN_WARNING("'[original]' is no longer a valid species -- cannot restore."))
		return

	persistence_sync_character_species(target_ckey, target_char_name, S)
	SSpersistence.charLaceDnaSetOriginalSpecies(target_ckey, target_char_name, null)
	to_chat(admin, SPAN_GOOD("Restored [target_char_name]'s chargen species to [original]."))
	log_and_message_admins("restored [target_char_name]'s ([target_ckey]) chargen species to [original] via Modify Neural Lace.", admin)

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

// ============================================================
// LOOSE LACE POSITION
// ============================================================
//
// ss13_neural_lace_vault (lace_storage.dm) already persists a lace sitting
// in a vault; the organ-augment save path (persistence_mobs.dm) already
// persists one installed in a human; persistence_floor_items.dm's own
// sweep already persists one bare on a floor tile. None of those catch a
// registered lace just sitting loose somewhere else -- in a bag, a locker,
// a closet -- so it was silently lost on restart. This sweep catches
// everything those three don't.
//
// Deliberately NOT central-synced, unlike this table's ss13_char_* siblings
// -- a raw (map_path, x, y, z) is only ever meaningful to the exact server
// instance that saved it. A different server running a different map has
// nowhere sensible to put a restored lace at those coordinates; syncing it
// there would just be dead weight, never actually consumed (charLacePositionRestore()'s
// own map_path filter means it wouldn't even be misused, just wasted).

/**
 * Periodic sweep: wipe-and-reinsert, same convention floorItemsFinalize()
 * uses -- delete every row for this map, then write one fresh row per
 * currently-loose registered lace. Deliberately NOT a plain per-row UPSERT:
 * a lace that WAS loose and got installed into a body (or vaulted) since
 * the last sweep has to stop having a row here at all, or a stale one
 * would survive to the next restart and charLacePositionRestore() would
 * spawn a phantom duplicate of a lace that's actually sitting correctly
 * installed/vaulted elsewhere. Wipe-and-reinsert makes that impossible by
 * construction instead of requiring a delete hook at every place a lace's
 * state can change (replaced(), store_lace(), etc.). Called from
 * forceSaveAll() alongside charSkillsFinalize().
 */
/datum/controller/subsystem/persistence/proc/charLacePositionFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("charLacePositionFinalize"))
		return

	var/datum/db_query/wipe_q = SSdbcore.NewQuery(
		"DELETE FROM ss13_char_lace_position WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	wipe_q.Execute()
	databaseCheckQueryResult(wipe_q, "charLacePositionFinalize wipe")
	qdel(wipe_q)

	var/saved = 0
	for(var/obj/item/organ/internal/neural_lace/L in world)
		if(QDELETED(L) || L.owner)
			continue
		if(istype(L.loc, /obj/structure/machinery/lace_storage))
			continue
		if(!length(L.registered_ckey) || !length(L.registered_name))
			continue
		var/turf/T = get_turf(L)
		if(!T)
			continue
		// Drydock ships have their own separate ship-scoped persistence
		// (persistence_ship_interiors.dm) with no stable x/y/z across a
		// redeploy -- this table isn't ship-scope-aware, so a lace there
		// would get a position that's meaningless (or wrong) on restore.
		// Non-pinned away sites are procedurally regenerated each round --
		// nothing there is meant to survive a restart. A PINNED away site
		// is exempted, same as every other persistence sweep already
		// exempts them. Station/centcom z's need no special-casing here --
		// they're just never excluded by either check, the default.
		if(GLOB.persistence_ship_z["[T.z]"])
			continue
		if(is_away_level(T.z) && !(T.z in GLOB.persistence_pinned_site_z))
			continue

		var/datum/db_query/query = SSdbcore.NewQuery(
			{"INSERT INTO ss13_char_lace_position
			(ckey, char_name, map_path, pos_x, pos_y, pos_z, owner_faction, lace_damage)
			VALUES (:ckey, :char_name, :mp, :x, :y, :z, :faction, :damage)
			ON DUPLICATE KEY UPDATE map_path = VALUES(map_path), pos_x = VALUES(pos_x),
				pos_y = VALUES(pos_y), pos_z = VALUES(pos_z), owner_faction = VALUES(owner_faction),
				lace_damage = VALUES(lace_damage), saved_at = NOW()"},
			list(
				"ckey" = L.registered_ckey, "char_name" = L.registered_name,
				"mp" = "[SSatlas.current_map.path]", "x" = T.x, "y" = T.y, "z" = T.z,
				"faction" = L.owner_faction || "", "damage" = L.lace_damage,
			)
		)
		query.Execute()
		if(databaseCheckQueryResult(query, "charLacePositionFinalize"))
			saved++
		qdel(query)
	if(saved)
		log_subsystem_persistence_info("CharLacePosition: Saved [saved] loose lace position(s).")

/**
 * Boot restore: rebuild a fresh neural lace object on the saved turf for
 * every row matching the current map. Mirrors laceVaultInitialize()'s own
 * restore shape (persistence_cryo.dm) -- placed on the open turf rather
 * than re-nested inside whatever bag/locker it was last sitting in, same
 * simplification persistence_floor_items.dm's own restore already makes.
 * Called from SSpersistence.Initialize() alongside laceVaultInitialize().
 */
/datum/controller/subsystem/persistence/proc/charLacePositionRestore()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("charLacePositionRestore"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, pos_x, pos_y, pos_z, owner_faction, lace_damage FROM ss13_char_lace_position WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "charLacePositionRestore"))
		qdel(query)
		return

	var/restored = 0
	var/orphaned = 0
	while(query.NextRow())
		var/ckey = query.item[1]
		var/char_name = query.item[2]
		var/px = text2num(query.item[3])
		var/py = text2num(query.item[4])
		var/pz = text2num(query.item[5])
		if(pz < 1 || pz > world.maxz)
			orphaned++
			continue
		var/turf/T = locate(px, py, pz)
		if(!T)
			orphaned++
			continue
		var/obj/item/organ/internal/neural_lace/lace = new(T)
		lace.registered_ckey = ckey
		lace.registered_name = char_name
		lace.owner_faction = query.item[6] || ""
		lace.lace_damage = text2num(query.item[7]) || 0
		restored++
	qdel(query)
	log_subsystem_persistence_info("CharLacePosition: Restored [restored] loose lace(s)[orphaned ? ", [orphaned] row(s) skipped (no valid turf)" : ""].")
