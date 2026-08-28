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

/**
 * Load every saved lace DNA row into the cache. Called from
 * SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/charLaceDnaInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_lace_dna_cache = list()

	if(!databaseCheckConnection("charLaceDnaInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, dna_json FROM ss13_char_lace_dna",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "charLaceDnaInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		GLOB.persistence_lace_dna_cache["[query.item[1]]|[query.item[2]]"] = query.item[3]
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
