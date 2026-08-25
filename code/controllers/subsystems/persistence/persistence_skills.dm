/*
 * Persistence - Character Skills
 *
 * Round-to-round record of what a character has actually EARNED: the
 * Professional tiers gained from a cargo skill manual (library/skill_manual.dm)
 * or from being taught by somebody who already held them (Teach Skills verb),
 * and the tiers lost again to resleeving.
 *
 * Deliberately separate from ss13_characters.skills, which is chargen-slot data
 * keyed by the slot's own id and only ever holds the Trained default fill
 * (preference_setup/skills/skills.dm). That column is the character's starting
 * point; this table is where they've got to since. Keyed (ckey, char_name) like
 * every other ss13_char_* table so it lines up with the persistence layer's
 * notion of a character, and so the existing delete sweep
 * (persistence_delete_character_data(), persistence_mobs.dm) and rename map
 * (persistence_character_rename.dm) carry it along with the rest.
 *
 * Shape mirrors the ss13_char_identity round trip in persistence_mobs.dm --
 * boot load into a cache, save-one that also refreshes that cache and writes
 * through to central, and an apply that falls back to a central read-through
 * plus local self-heal on a cache miss. Central sync is gated behind
 * CENTRAL_SYNC_CHARACTERS by the shared helpers, so with central off none of
 * it runs.
 */

/// Cached skill rows, keyed "[ckey]|[char_name]" -> skills_json string.
GLOBAL_LIST_EMPTY(persistence_skills_cache)

/**
 * Load every saved skill row into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/charSkillsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_skills_cache = list()

	if(!databaseCheckConnection("charSkillsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, skills_json FROM ss13_char_skills",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "charSkillsInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		GLOB.persistence_skills_cache["[query.item[1]]|[query.item[2]]"] = query.item[3]
		loaded++
	qdel(query)
	log_subsystem_persistence_info("CharSkills: Loaded [loaded] skill entries.")

/**
 * Writes one character's current skill levels. Snapshot is taken live off the
 * mob's components (get_skill_snapshot(), skill_progression.dm) -- those are
 * the runtime authority, the same way mob.languages is for languages.
 */
/datum/controller/subsystem/persistence/proc/charSkillsSaveOne(mob/living/carbon/human/H)
	if(!istype(H) || !H.ckey || !H.real_name)
		return FALSE
	if(!databaseCheckConnection("charSkillsSaveOne"))
		return FALSE

	var/list/levels = get_skill_snapshot(H)
	if(!length(levels))
		return FALSE
	var/list/payload = list("levels" = levels, "last_used" = get_skill_activity_snapshot(H))
	var/skills_json = json_encode(payload)

	var/datum/db_query/query = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_skills (ckey, char_name, skills_json)
		VALUES (:ckey, :char_name, :skills_json)
		ON DUPLICATE KEY UPDATE skills_json = VALUES(skills_json), saved_at = NOW()"},
		list("ckey" = H.ckey, "char_name" = H.real_name, "skills_json" = skills_json)
	)
	query.Execute()
	var/success = databaseCheckQueryResult(query, "charSkillsSaveOne")
	qdel(query)
	if(!success)
		return FALSE

	// Refreshed here because applyPersistentSkills() reads the cache, not the
	// DB -- same reason charIdentitySaveOne() does it.
	GLOB.persistence_skills_cache["[H.ckey]|[H.real_name]"] = skills_json

	_centralCharacterWriteThrough("ss13_char_skills",
		list("ckey", "char_name", "skills_json"),
		list(H.ckey, H.real_name, skills_json))
	return TRUE

/**
 * Direct DB write for a character with no live mob to read a snapshot off
 * of -- the offline counterpart to charSkillsSaveOne(), same shape as
 * economyCreditOfflineAccount() (persistence_economy.dm) relative to
 * charge_to_account(). Used by the Modify Skills admin panel to edit an
 * offline character's skills. `skills_json` is expected to already be in
 * the wrapped {"levels": {...}, "last_used": {...}} shape.
 */
/datum/controller/subsystem/persistence/proc/charSkillsSetOffline(ckey, char_name, skills_json)
	if(!ckey || !char_name || !skills_json)
		return FALSE
	if(!databaseCheckConnection("charSkillsSetOffline"))
		return FALSE

	var/datum/db_query/query = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_skills (ckey, char_name, skills_json)
		VALUES (:ckey, :char_name, :skills_json)
		ON DUPLICATE KEY UPDATE skills_json = VALUES(skills_json), saved_at = NOW()"},
		list("ckey" = ckey, "char_name" = char_name, "skills_json" = skills_json)
	)
	query.Execute()
	var/success = databaseCheckQueryResult(query, "charSkillsSetOffline")
	qdel(query)
	if(!success)
		return FALSE

	GLOB.persistence_skills_cache["[ckey]|[char_name]"] = skills_json
	_centralCharacterWriteThrough("ss13_char_skills",
		list("ckey", "char_name", "skills_json"),
		list(ckey, char_name, skills_json))
	return TRUE

/**
 * Resolves the current wrapped {"levels": {...}, "last_used": {...}} skill
 * snapshot for (ckey, char_name) WITHOUT a live mob -- cache first, then a
 * central read-through + local self-heal on a miss, mirroring
 * applyPersistentSkills()'s own resolution exactly, but returning the
 * decoded data instead of applying it to anyone. Old bare-map rows (saved
 * before this feature existed) come back as {"levels": <the old map>,
 * "last_used": list()}, same backward-compat handling as
 * applyPersistentSkills(). Empty list() if nothing is found anywhere.
 */
/datum/controller/subsystem/persistence/proc/charSkillsResolveOffline(ckey, char_name)
	if(!ckey || !char_name)
		return list()

	var/key = "[ckey]|[char_name]"
	var/skills_json = GLOB.persistence_skills_cache[key]

	if(isnull(skills_json))
		var/list/row = _centralCharacterReadThrough("ss13_char_skills", list("skills_json"), ckey, char_name)
		if(row)
			skills_json = row[1]
		if(!isnull(skills_json))
			GLOB.persistence_skills_cache[key] = skills_json
			_centralCharacterSelfHealLocal("ss13_char_skills",
				list("ckey", "char_name", "skills_json"),
				list(ckey, char_name, skills_json))

	if(isnull(skills_json))
		return list()

	var/list/decoded
	try
		decoded = json_decode(skills_json)
	catch(var/exception/decode_e)
		log_subsystem_persistence_error("CharSkills: could not decode skills for [key]: [decode_e]")
		return list()
	if(!islist(decoded) || !length(decoded))
		return list()

	var/list/levels = islist(decoded["levels"]) ? decoded["levels"] : decoded
	var/list/last_used = islist(decoded["last_used"]) ? decoded["last_used"] : list()
	return list("levels" = levels, "last_used" = last_used)

/**
 * Sweeps every embodied player and saves their skills. Called alongside the
 * other character Finalize passes.
 */
/datum/controller/subsystem/persistence/proc/charSkillsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("charSkillsFinalize"))
		return

	var/saved = 0
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.ckey || !H.z)
			continue
		if(charSkillsSaveOne(H))
			saved++
	log_subsystem_persistence_info("CharSkills: Saved [saved] skill entries.")

/**
 * Re-applies a character's saved skills onto their body. Called at spawn AFTER
 * copy_to() has laid down the chargen defaults, so the saved levels win.
 *
 * Levels are still clamped per skill on the way in
 * (set_skill_progression_level()), so a row saved under a different education
 * or an older cap can't push anything past its current ceiling.
 */
/mob/living/carbon/human/proc/applyPersistentSkills()
	if(!GLOB.config.sql_enabled || !ckey || !real_name)
		return FALSE

	var/key = "[ckey]|[real_name]"
	var/skills_json = GLOB.persistence_skills_cache[key]

	// Cache miss -- this server may simply never have seen this character.
	// Pull from central if it's on, and self-heal the local table so future
	// spawns are a plain cache hit.
	if(isnull(skills_json))
		var/list/row = SSpersistence._centralCharacterReadThrough("ss13_char_skills", list("skills_json"), ckey, real_name)
		if(!row)
			return FALSE
		skills_json = row[1]
		if(isnull(skills_json))
			return FALSE
		GLOB.persistence_skills_cache[key] = skills_json
		SSpersistence._centralCharacterSelfHealLocal("ss13_char_skills",
			list("ckey", "char_name", "skills_json"),
			list(ckey, real_name, skills_json))

	var/list/decoded
	try
		decoded = json_decode(skills_json)
	catch(var/exception/decode_e)
		log_subsystem_persistence_error("CharSkills: could not decode skills for [key]: [decode_e]")
		return FALSE
	if(!islist(decoded) || !length(decoded))
		return FALSE

	// New shape is {"levels": {...}, "last_used": {...}}. Anything saved
	// before this feature existed is a bare {"typepath": level, ...} map --
	// treat the whole decoded object as the levels map in that case, with no
	// activity data (each component's own fresh-creation last_used_time,
	// REALTIMEOFDAY at this exact restore, is left alone -- no retroactive
	// mass-decay for a character who's never seen this feature before).
	var/list/levels = islist(decoded["levels"]) ? decoded["levels"] : decoded
	var/list/last_used = islist(decoded["last_used"]) ? decoded["last_used"] : list()

	. = apply_skill_snapshot(src, levels)
	apply_skill_activity_snapshot(src, last_used)

// ============================================================
// ADMIN: MODIFY SKILLS
// ============================================================
//
// Lets an admin set any skill's tier for a (ckey, char_name) character even
// when they're not currently connected -- same (ckey, char_name)-targeting-
// while-possibly-offline shape as Give Credits/Rename Character
// (persistence_factions.dm / persistence_character_rename.dm). Writes to
// every representation that currently exists for that identity:
//   - Live mob (currently embodied): set_skill_progression_level() per
//     changed skill (immediate in-round effect, no relog needed), then
//     charSkillsSaveOne() for the full local+central+cache write -- an
//     installed neural lace is synced automatically as part of
//     set_skill_progression_level() itself (skill_progression.dm).
//   - Disembodied neural lace (consciousness captured, no live mob): patched
//     directly, so a later resleeve doesn't overwrite the edit with the
//     stale captured snapshot.
//   - DB + central, always: charSkillsSetOffline(), covering the fully
//     offline case and keeping the DB row correct regardless of the above.

/datum/admins/proc/modify_character_skills()
	set name = "Modify Skills"
	set category = "Persistence.Characters"
	set desc = "Set any skill's tier for a character, online or offline."

	if(!check_rights(R_ADMIN))
		return

	var/target_ckey = tgui_input_text(usr, "Enter ckey:", "Modify Skills", usr.ckey, max_length = 32)
	if(!target_ckey) return
	target_ckey = ckey(target_ckey)

	var/char_name
	var/list/characters = persistence_get_saved_characters(target_ckey)
	if(length(characters) > 1)
		char_name = tgui_input_list(usr, "Which character?", "Modify Skills", characters)
		if(!char_name) return
	else if(length(characters) == 1)
		char_name = characters[1]
	else
		char_name = tgui_input_text(usr, "No cached characters found for '[target_ckey]'. Exact character name:", "Modify Skills", "", max_length = 64, encode = FALSE)
		if(!char_name) return

	var/datum/tgui_module/admin/skill_editor/panel = new(target_ckey, char_name)
	panel.ui_interact(usr)

/datum/tgui_module/admin/skill_editor
	var/target_ckey
	var/target_char_name

/datum/tgui_module/admin/skill_editor/New(ckey, char_name)
	. = ..()
	target_ckey = ckey
	target_char_name = char_name

/datum/tgui_module/admin/skill_editor/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SkillEditor", "Modify Skills", 480, 640)
		ui.open()

/// TRUE if target_ckey is currently embodying target_char_name right now --
/// the one case set_skill_progression_level() alone is enough for (it
/// updates the live component directly; persistence needs its own explicit
/// save on top, since that proc was never a persistence chokepoint).
/datum/tgui_module/admin/skill_editor/proc/_resolve_live_mob()
	var/client/C = GLOB.directory[target_ckey]
	if(C && istype(C.mob, /mob/living/carbon/human) && C.mob.real_name == target_char_name)
		return C.mob
	return null

/datum/tgui_module/admin/skill_editor/ui_data(mob/user)
	var/list/data = list()
	data["ckey"] = target_ckey
	data["char_name"] = target_char_name

	var/mob/living/carbon/human/H = _resolve_live_mob()
	data["is_live"] = !!H

	var/list/levels
	if(H)
		levels = get_skill_snapshot(H)
	else
		var/list/resolved = SSpersistence.charSkillsResolveOffline(target_ckey, target_char_name)
		levels = resolved["levels"] || list()

	var/list/skills = list()
	for(var/singleton/skill/sk as anything in SSskills.all_skills)
		if(!sk.component_type)
			continue
		var/current = levels["[sk.type]"] || SKILL_LEVEL_UNFAMILIAR
		var/list/options = list()
		for(var/lvl = SKILL_LEVEL_UNFAMILIAR, lvl <= sk.maximum_level, lvl++)
			options += list(list("level" = lvl, "name" = get_skill_level_name(sk, lvl)))
		skills += list(list(
			"type" = "[sk.type]",
			"name" = sk.name,
			"level" = current,
			"level_name" = get_skill_level_name(sk, current),
			"options" = options
		))
	data["skills"] = skills
	return data

/datum/tgui_module/admin/skill_editor/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(!check_rights(R_ADMIN))
		log_and_message_admins("attempted to use the Modify Skills panel without sufficient rights.")
		return

	if(action == "apply")
		var/list/changes = params["changes"]
		if(!islist(changes) || !length(changes))
			return TRUE
		_apply_changes(usr, changes)
		return TRUE

/// TGUI act() params can arrive as a native num or as text depending on how
/// the JS side sent them -- accept either rather than assuming.
/datum/tgui_module/admin/skill_editor/proc/_coerce_level(value)
	return isnum(value) ? value : text2num(value)

/// `changes` is skill typepath (text) -> new level (number), from the UI's
/// per-row dropdowns. Only actually-changed rows are expected, but every
/// entry is validated/re-clamped here regardless of what the client sent.
/datum/tgui_module/admin/skill_editor/proc/_apply_changes(mob/admin, list/changes)
	var/mob/living/carbon/human/H = _resolve_live_mob()
	var/list/log_lines = list()

	if(H)
		for(var/skill_key in changes)
			var/skill_path = text2path(skill_key)
			if(!skill_path)
				continue
			var/singleton/skill/sk = GET_SINGLETON(skill_path)
			if(!istype(sk) || !sk.component_type)
				continue
			var/old_level = get_skill_progression_level(H, sk)
			var/applied = set_skill_progression_level(H, sk, _coerce_level(changes[skill_key]))
			if(isnull(applied) || applied == old_level)
				continue
			var/datum/component/skill/comp = H.GetComponent(sk.component_type)
			if(comp)
				comp.last_used_time = REALTIMEOFDAY
				comp.training_progress = 0
			log_lines += "[sk.name]: [get_skill_level_name(sk, old_level)] -> [get_skill_level_name(sk, applied)]"
		SSpersistence.charSkillsSaveOne(H)
	else
		var/list/resolved = SSpersistence.charSkillsResolveOffline(target_ckey, target_char_name)
		var/list/levels = resolved["levels"] || list()
		var/list/last_used = resolved["last_used"] || list()

		// Look for a disembodied consciousness (dead, captured, no live mob)
		// registered to this exact identity -- same world-scan idiom
		// persistence_character_rename.dm's live identity update already uses.
		var/obj/item/organ/internal/neural_lace/lace
		for(var/obj/item/organ/internal/neural_lace/candidate in world)
			if(candidate.registered_ckey == target_ckey && candidate.registered_name == target_char_name && candidate.lace_occupied)
				lace = candidate
				break

		for(var/skill_key in changes)
			var/skill_path = text2path(skill_key)
			if(!skill_path)
				continue
			var/singleton/skill/sk = GET_SINGLETON(skill_path)
			if(!istype(sk) || !sk.component_type)
				continue
			var/old_level = levels[skill_key] || SKILL_LEVEL_UNFAMILIAR
			var/new_level = clamp(_coerce_level(changes[skill_key]), SKILL_LEVEL_UNFAMILIAR, sk.maximum_level)
			if(new_level == old_level)
				continue
			levels[skill_key] = new_level
			last_used[skill_key] = list("last_used" = REALTIMEOFDAY, "progress" = 0)
			if(lace)
				LAZYINITLIST(lace.stored_skills)
				lace.stored_skills[skill_key] = new_level
			log_lines += "[sk.name]: [get_skill_level_name(sk, old_level)] -> [get_skill_level_name(sk, new_level)]"

		if(length(log_lines))
			var/skills_json = json_encode(list("levels" = levels, "last_used" = last_used))
			SSpersistence.charSkillsSetOffline(target_ckey, target_char_name, skills_json)

	if(!length(log_lines))
		to_chat(admin, SPAN_NOTICE("No skills changed."))
		return

	to_chat(admin, SPAN_GOOD("Updated [target_char_name]'s skills:\n[jointext(log_lines, "\n")]"))
	log_and_message_admins("modified [target_char_name]'s ([target_ckey]) skills: [jointext(log_lines, ", ")]", admin)
