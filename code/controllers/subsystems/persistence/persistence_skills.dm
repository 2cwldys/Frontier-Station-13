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

	var/list/snapshot = get_skill_snapshot(H)
	if(!length(snapshot))
		return FALSE
	var/skills_json = json_encode(snapshot)

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

	var/list/snapshot
	try
		snapshot = json_decode(skills_json)
	catch(var/exception/decode_e)
		log_subsystem_persistence_error("CharSkills: could not decode skills for [key]: [decode_e]")
		return FALSE
	if(!islist(snapshot) || !length(snapshot))
		return FALSE

	return apply_skill_snapshot(src, snapshot)
