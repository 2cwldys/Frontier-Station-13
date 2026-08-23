/*
 * Persistence - Mob Health & Inventory
 * Saves and restores character physical state (organ damage, temperature, stamina, fire)
 * and equipment loadout (typepath-based serialization of worn/held items) across rounds.
 *
 * Health key:     ckey + char_name
 * Inventory key:  ckey + char_name
 *
 * Restore hook: /mob/living/carbon/human/LateInitialize()  fires after mob spawns and
 * job gear is issued, so we overlay saved inventory on top of default equips.
 *
 * Only runs on the SCCV Horizon map.
 */

// ============================================================
// CENTRAL CHARACTER SYNC (CENTRAL_SYNC_CHARACTERS)
// ============================================================
//
// Write-through + read-through-on-miss, shared by the identity/health/
// inventory/position systems below -- see docs/cross_server_persistence.md.
// The presence lock (persistenceLockAcquire()/Release(), persistence_cryo.dm)
// already guarantees only one server has a character active at a time, so
// there's no concurrent-write conflict to solve here -- whichever server
// currently holds the lock is the only one ever writing or read-through-
// hydrating that character's data.

/// Shared upsert builder -- issues the INSERT ... ON DUPLICATE KEY UPDATE
/// against whichever dbcore instance is passed (SSdbcore for the
/// self-heal-local write below, SScentraldb for the write-through) so this
/// SQL-building logic exists exactly once. Callers check
/// toggles/reachability themselves before calling this -- it always
/// executes unconditionally. `columns`/`values` are parallel lists; every
/// column except ckey/char_name is included in the UPDATE half.
/datum/controller/subsystem/persistence/proc/_characterRowUpsert(datum/controller/subsystem/dbcore/db, table, list/columns, list/values, log_tag)
	var/list/col_list = list()
	var/list/val_placeholders = list()
	var/list/update_clauses = list()
	var/list/params = list()
	for(var/i in 1 to length(columns))
		var/col = columns[i]
		col_list += "`[col]`"
		val_placeholders += ":[col]"
		if(col != "ckey" && col != "char_name")
			update_clauses += "`[col]` = VALUES(`[col]`)"
		params[col] = values[i]
	update_clauses += "`saved_at` = NOW()"

	var/datum/db_query/q = db.NewQuery(
		"INSERT INTO `[table]` ([jointext(col_list, ", ")]) VALUES ([jointext(val_placeholders, ", ")]) ON DUPLICATE KEY UPDATE [jointext(update_clauses, ", ")]",
		params
	)
	q.Execute()
	databaseCheckQueryResult(q, "[log_tag]([table])")
	qdel(q)

/// Shared gate for every central-character-sync helper below -- TRUE only
/// when BOTH central_sql_enabled AND central_sync_characters are genuinely
/// on, AND central is reachable right now. central_sql_enabled is checked
/// explicitly here rather than just leaving it to centralDatabaseReachable()
/// -- that proc returns TRUE when central is OFF (a no-op shortcut meant
/// for UI reachability gating), which would let a caller fire a query
/// against SScentraldb even when it was never connected at all. Existing
/// local-only saves are completely unaffected either way -- every write-
/// through/read-through/partial-update call in this file always does its
/// local work first/regardless, this gate only decides whether the
/// ADDITIONAL central step also runs.
/datum/controller/subsystem/persistence/proc/_centralCharacterSyncActive()
	if(!GLOB.config.central_sql_enabled || !GLOB.config.central_sync_characters)
		return FALSE
	return centralDatabaseReachable()

/// Write-through: upserts one row into `table` on the CENTRAL DB. Non-fatal
/// -- the local save this always runs alongside already succeeded, so a
/// central sync failure is logged and otherwise ignored, never surfaced
/// to the player.
/datum/controller/subsystem/persistence/proc/_centralCharacterWriteThrough(table, list/columns, list/values)
	if(!_centralCharacterSyncActive())
		return
	_characterRowUpsert(SScentraldb, table, columns, values, "_centralCharacterWriteThrough")

/// Partial write-through for the three ss13_mob_position setter procs
/// below (persistence_set_last_pod/_imprisoned/_faction_bound) -- an
/// UPDATE, not an upsert, mirroring their own local UPDATE-only shape
/// exactly (they never INSERT; the row is guaranteed to already exist by
/// the time any of them runs, since every path into them goes through
/// mobPositionSave() first -- same assumption their local queries already
/// make). Using the full upsert builder here would require supplying
/// values for every NOT NULL column (x/y/z) that these procs don't have,
/// and would be wrong regardless -- an UPDATE against a row that doesn't
/// exist centrally yet is correctly a no-op, not a reason to fabricate one.
/datum/controller/subsystem/persistence/proc/_centralCharacterPartialUpdate(table, list/set_columns, list/set_values, ckey, char_name)
	if(!_centralCharacterSyncActive())
		return
	var/list/set_clauses = list()
	var/list/params = list("ckey" = ckey, "char_name" = char_name)
	for(var/i in 1 to length(set_columns))
		var/col = set_columns[i]
		set_clauses += "`[col]` = :[col]"
		params[col] = set_values[i]
	var/datum/db_query/q = SScentraldb.NewQuery(
		"UPDATE `[table]` SET [jointext(set_clauses, ", ")] WHERE ckey = :ckey AND char_name = :char_name",
		params
	)
	q.Execute()
	databaseCheckQueryResult(q, "_centralCharacterPartialUpdate([table])")
	qdel(q)

/// Deletes this character's row from `table` on the CENTRAL DB. Without
/// this, deletion was local-only: the central row survived, and the next
/// cache miss for the same (ckey, char_name) hit
/// _centralCharacterReadThrough() below, which pulled it back AND
/// self-healed it into the local table -- resurrecting a character the
/// player or an admin had deliberately deleted. Non-fatal, same as every
/// other central step here: the local delete has already happened and is
/// authoritative for this server regardless.
/datum/controller/subsystem/persistence/proc/_centralCharacterDelete(table, ckey, char_name)
	if(!_centralCharacterSyncActive())
		return
	var/datum/db_query/q = SScentraldb.NewQuery(
		"DELETE FROM `[table]` WHERE ckey = :ckey AND char_name = :char_name",
		list("ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()
	databaseCheckQueryResult(q, "_centralCharacterDelete([table])")
	qdel(q)

/// Re-points this character's central row at a new name. A rename was
/// local-only too, so central kept the OLD char_name: the new name never
/// reached other servers, and a read-through keyed on the old one could
/// resurrect the pre-rename character alongside the renamed one.
/// Deliberately an UPDATE rather than reusing the metadata write-through --
/// that one is an upsert keyed on (ckey, char_name), so under a new name it
/// would insert a SECOND central row and orphan the first.
/datum/controller/subsystem/persistence/proc/_centralCharacterRename(table, ckey, old_name, new_name)
	if(!_centralCharacterSyncActive())
		return
	var/datum/db_query/q = SScentraldb.NewQuery(
		"UPDATE `[table]` SET char_name = :new_name WHERE ckey = :ckey AND char_name = :old_name",
		list("new_name" = new_name, "ckey" = ckey, "old_name" = old_name)
	)
	q.Execute()
	databaseCheckQueryResult(q, "_centralCharacterRename([table])")
	qdel(q)

/// Self-heal: writes a row just hydrated FROM central into this server's
/// own LOCAL table, so this server behaves like a normal cache-primed
/// server for this character from now on (no repeated central round-trips
/// on every future spawn). Always unconditional -- only ever called right
/// after a successful _centralCharacterReadThrough() hit.
/datum/controller/subsystem/persistence/proc/_centralCharacterSelfHealLocal(table, list/columns, list/values)
	_characterRowUpsert(SSdbcore, table, columns, values, "_centralCharacterSelfHealLocal")

/// Read-through-on-miss: SELECTs `columns` from `table` on the central DB
/// for this ckey/char_name, when CENTRAL_SYNC_CHARACTERS is on and central
/// is reachable. Returns a list of raw column values (same order as
/// `columns`, same raw-string/text2num()-needing shape SQL always returns)
/// or null if not found/unreachable/off. Callers map the result into their
/// own cache-entry shape AND write it back into their own local table
/// (self-heal) -- see each call site.
/datum/controller/subsystem/persistence/proc/_centralCharacterReadThrough(table, list/columns, ckey, char_name)
	if(!_centralCharacterSyncActive())
		return null

	var/list/col_list = list()
	for(var/col in columns)
		col_list += "`[col]`"

	var/datum/db_query/q = SScentraldb.NewQuery(
		"SELECT [jointext(col_list, ", ")] FROM `[table]` WHERE ckey = :ckey AND char_name = :char_name",
		list("ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "_centralCharacterReadThrough([table])") || !q.NextRow())
		qdel(q)
		return null
	var/list/row = q.item.Copy()
	qdel(q)
	return row

// ============================================================
// SYSTEM 8: MOB HEALTH
// ============================================================

/// Cached health data keyed by "[ckey]|[char_name]"
GLOBAL_LIST_EMPTY(persistence_health_cache)

/**
 * Load saved health state into cache.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/mobsHealthInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_health_cache = list()

	if(!databaseCheckConnection("mobsHealthInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, organ_damage_json, stamina, bodytemperature, on_fire, fire_stacks, nutrition, hydration FROM ss13_char_health",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "mobsHealthInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/key = "[query.item[1]]|[query.item[2]]"
		GLOB.persistence_health_cache[key] = list(
			"organ_damage_json" = query.item[3],
			"stamina"           = text2num(query.item[4]),
			"bodytemperature"   = text2num(query.item[5]),
			"on_fire"           = text2num(query.item[6]),
			"fire_stacks"       = text2num(query.item[7]),
			"nutrition"         = text2num(query.item[8]),
			"hydration"         = text2num(query.item[9])
		)
		loaded++

	qdel(query)
	log_subsystem_persistence_info("MobHealth: Loaded [loaded] health entries.")

/**
 * Save health state for all connected living human mobs at round end.
 * Called from SSpersistence.Shutdown().
 */
/datum/controller/subsystem/persistence/proc/mobsHealthFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("mobsHealthFinalize"))
		return

	// Delegates to mobsHealthSaveOne() so the finalize sweep refreshes
	// GLOB.persistence_health_cache exactly like the logout/cryo save path --
	// otherwise a force-save followed by a same-round rejoin restores stale data.
	var/saved = 0
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.ckey || !H.real_name)
			continue
		if(!H.z)
			continue
		mobsHealthSaveOne(H)
		saved++

	log_subsystem_persistence_info("MobHealth: Saved health state for [saved] mobs.")

/**
 * Apply cached health data to a newly spawned human mob.
 * Called from /mob/living/carbon/human/LateInitialize().
 */
/mob/living/carbon/human/proc/applyPersistentHealthData()
	// !islist(), not !length() -- an empty cache (e.g. a fresh shard that's
	// never locally saved anyone) must still fall through to the
	// read-through-on-miss lookup below, not bail out before ever checking
	// this specific character.
	if(!GLOB.config.sql_enabled || !islist(GLOB.persistence_health_cache))
		return
	if(!ckey || !real_name)
		return

	var/key = "[ckey]|[real_name]"
	var/list/entry = GLOB.persistence_health_cache[key]
	if(!entry)
		var/list/row = SSpersistence._centralCharacterReadThrough("ss13_char_health",
			list("organ_damage_json", "stamina", "bodytemperature", "on_fire", "fire_stacks", "nutrition", "hydration"),
			ckey, real_name)
		if(!row)
			return
		entry = list(
			"organ_damage_json" = row[1],
			"stamina"           = text2num(row[2]),
			"bodytemperature"   = text2num(row[3]),
			"on_fire"           = text2num(row[4]),
			"fire_stacks"       = text2num(row[5]),
			"nutrition"         = text2num(row[6]),
			"hydration"         = text2num(row[7])
		)
		GLOB.persistence_health_cache[key] = entry
		SSpersistence._centralCharacterSelfHealLocal("ss13_char_health",
			list("ckey", "char_name", "organ_damage_json", "stamina", "bodytemperature", "on_fire", "fire_stacks", "nutrition", "hydration"),
			list(ckey, real_name, entry["organ_damage_json"], entry["stamina"], entry["bodytemperature"], entry["on_fire"], entry["fire_stacks"], entry["nutrition"], entry["hydration"]))

	// Apply organ state: damage, robolimb, augments
	if(entry["organ_damage_json"])
		var/list/organ_data = json_decode(entry["organ_damage_json"])
		if(organ_data && islist(organ_data))
			for(var/limb_name in organ_data)
				var/obj/item/organ/external/O = organs_by_name[limb_name]
				if(!O)
					continue
				var/list/limb = organ_data[limb_name]
				if(limb["missing"])
					O.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
					qdel(O) // don't leave a severed-limb prop item sitting at the spawn point
					continue
				var/brute_amt = isnull(limb["brute"]) ? 0 : (limb["brute"] + 0)
				var/burn_amt  = isnull(limb["burn"])  ? 0 : (limb["burn"]  + 0)
				if(brute_amt > 0 || burn_amt > 0)
					O.take_damage(brute_amt, burn_amt)
				// Restore robolimb state
				if(limb["robotic"])
					var/company = limb["model"] || null
					if(!O.robotic)
						O.robotize(company)
				// Restore augments
				if(limb["augments"] && islist(limb["augments"]))
					for(var/aug_entry in limb["augments"])
						var/aug_type_str
						var/list/aug_data = null
						if(islist(aug_entry))
							aug_data = aug_entry
							aug_type_str = aug_data["type"]
						else
							aug_type_str = aug_entry
						var/aug_path = text2path(aug_type_str)
						if(!aug_path || !ispath(aug_path, /obj/item/organ))
							continue
						var/already_installed = FALSE
						for(var/obj/item/organ/A in O.internal_organs)
							if(A.type == aug_path)
								already_installed = TRUE
								break
						if(!already_installed)
							try
								// /atom/New() overwrites args[1] (loc) with mapload and forwards the
								// rest unchanged (atoms_initializing_EXPENSIVE.dm) -- so only ONE
								// extra arg belongs here (internal); a second one shifts internal
								// out of Initialize()'s parameter list and it's silently dropped.
								var/obj/item/organ/new_aug = new aug_path(src, TRUE)
								if(aug_data && istype(new_aug, /obj/item/organ/internal/neural_lace))
									var/obj/item/organ/internal/neural_lace/lace = new_aug
									lace.lace_damage     = isnull(aug_data["lace_damage"]) ? 0 : aug_data["lace_damage"]
									lace.registered_name = aug_data["registered_name"] || ""
									lace.registered_ckey = aug_data["registered_ckey"] || ""
									lace.owner_faction   = aug_data["owner_faction"] || ""
							catch(var/exception/aug_e)
								log_subsystem_persistence_error("MobHealth: Failed to restore augment [aug_type_str] for [real_name]: [aug_e]")

	// Apply systemic stats
	if(!isnull(entry["bodytemperature"]))
		bodytemperature = text2num(entry["bodytemperature"])
	if(!isnull(entry["stamina"]))
		stamina = text2num(entry["stamina"])
	if(!isnull(entry["nutrition"]))
		nutrition  = entry["nutrition"] + 0
	if(!isnull(entry["hydration"]))
		hydration  = entry["hydration"] + 0

	if(entry["on_fire"] && text2num(entry["on_fire"]))
		IgniteMob(text2num(entry["fire_stacks"]) || 1)

	log_subsystem_persistence_info("MobHealth: Restored health state for [real_name] ([ckey]).")

// ============================================================
// SYSTEM 9A: CHARACTER IDENTITY (citizenship, voice, flavor texts)
// ============================================================

/// Cached identity data keyed by "[ckey]|[char_name]"
GLOBAL_LIST_EMPTY(persistence_identity_cache)

/datum/controller/subsystem/persistence/proc/charIdentityInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_identity_cache = list()

	if(!databaseCheckConnection("charIdentityInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, citizenship, special_voice, flavor_texts, languages_json FROM ss13_char_identity",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "charIdentityInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/key = "[query.item[1]]|[query.item[2]]"
		GLOB.persistence_identity_cache[key] = list(
			"citizenship"   = query.item[3],
			"special_voice" = query.item[4],
			"flavor_texts"  = query.item[5],
			"languages_json" = query.item[6]
		)
		loaded++
	qdel(query)
	log_subsystem_persistence_info("CharIdentity: Loaded [loaded] identity entries.")

/datum/controller/subsystem/persistence/proc/charIdentityFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("charIdentityFinalize"))
		return

	var/saved = 0
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.ckey || !H.real_name)
			continue
		if(!H.z)
			continue
		charIdentitySaveOne(H)
		saved++
	log_subsystem_persistence_info("CharIdentity: Saved [saved] identity entries.")

/datum/controller/subsystem/persistence/proc/charIdentitySaveOne(mob/living/carbon/human/H)
	if(!H || !H.ckey || !H.real_name)
		return
	if(!databaseCheckConnection("charIdentitySaveOne"))
		return

	var/flavor_json   = length(H.flavor_texts) ? json_encode(H.flavor_texts) : null

	// Languages are live /datum/language object references, not primitives --
	// JSON can't represent a BYOND object reference, so they must be
	// stringified by name first (matching add_language()'s own GLOB.all_languages
	// lookup-by-name convention) or the round trip silently loses them.
	var/list/lang_names = list()
	for(var/datum/language/L in H.languages)
		lang_names += L.name
	var/language_json = length(lang_names) ? json_encode(lang_names) : null

	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_identity (ckey, char_name, citizenship, special_voice, flavor_texts, languages_json)
		VALUES (:ckey, :char_name, :citizenship, :special_voice, :flavor_texts, :languages_json)
		ON DUPLICATE KEY UPDATE citizenship = VALUES(citizenship), special_voice = VALUES(special_voice),
		flavor_texts = VALUES(flavor_texts), languages_json = VALUES(languages_json), saved_at = NOW()"},
		list(
			"ckey"           = H.ckey,
			"char_name"      = H.real_name,
			"citizenship"    = H.citizenship || null,
			"special_voice"  = H.special_voice || null,
			"flavor_texts"   = flavor_json,
			"languages_json" = language_json
		)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "charIdentitySaveOne")
	qdel(ins)

	// Refresh the in-memory cache too -- restore reads the cache, not the DB.
	GLOB.persistence_identity_cache["[H.ckey]|[H.real_name]"] = list(
		"citizenship"    = H.citizenship || null,
		"special_voice"  = H.special_voice || null,
		"flavor_texts"   = flavor_json,
		"languages_json" = language_json
	)

	_centralCharacterWriteThrough("ss13_char_identity",
		list("ckey", "char_name", "citizenship", "special_voice", "flavor_texts", "languages_json"),
		list(H.ckey, H.real_name, H.citizenship || null, H.special_voice || null, flavor_json, language_json))

/mob/living/carbon/human/proc/applyPersistentIdentity()
	if(!GLOB.config.sql_enabled || !islist(GLOB.persistence_identity_cache))
		return
	if(!ckey || !real_name)
		return

	var/key = "[ckey]|[real_name]"
	var/list/entry = GLOB.persistence_identity_cache[key]
	if(!entry)
		var/list/row = SSpersistence._centralCharacterReadThrough("ss13_char_identity",
			list("citizenship", "special_voice", "flavor_texts", "languages_json"),
			ckey, real_name)
		if(!row)
			return
		entry = list(
			"citizenship"    = row[1],
			"special_voice"  = row[2],
			"flavor_texts"   = row[3],
			"languages_json" = row[4]
		)
		GLOB.persistence_identity_cache[key] = entry
		SSpersistence._centralCharacterSelfHealLocal("ss13_char_identity",
			list("ckey", "char_name", "citizenship", "special_voice", "flavor_texts", "languages_json"),
			list(ckey, real_name, entry["citizenship"], entry["special_voice"], entry["flavor_texts"], entry["languages_json"]))

	if(entry["citizenship"])
		citizenship = entry["citizenship"]
	if(entry["special_voice"])
		special_voice = entry["special_voice"]
	if(length(entry["flavor_texts"]))
		var/list/ft = json_decode(entry["flavor_texts"])
		if(ft && islist(ft))
			flavor_texts = ft

	if(length(entry["languages_json"]))
		var/list/lang_names = json_decode(entry["languages_json"])
		if(islist(lang_names) && length(lang_names))
			var/list/restored_langs = list()
			for(var/lname in lang_names)
				var/datum/language/L = GLOB.all_languages[lname]
				if(istype(L))
					restored_langs += L
			if(length(restored_langs))
				languages = restored_langs

	log_subsystem_persistence_info("CharIdentity: Restored identity for [real_name] ([ckey]).")

// ============================================================
// SYSTEM 9: MOB INVENTORY
// ============================================================

/// Cached inventory data keyed by "[ckey]|[char_name]"
GLOBAL_LIST_EMPTY(persistence_inventory_cache)

/// Equipment slots to serialize: slot_define => slot_name_key
GLOBAL_LIST_INIT(persistence_inventory_slots, list(
	"w_uniform" = slot_w_uniform,
	"wear_suit" = slot_wear_suit,
	"head"      = slot_head,
	"gloves"    = slot_gloves,
	"shoes"     = slot_shoes,
	"glasses"   = slot_glasses,
	"wear_mask" = slot_wear_mask,
	"wear_id"   = slot_wear_id,
	"l_ear"     = slot_l_ear,
	"r_ear"     = slot_r_ear,
	"belt"      = slot_belt,
	"back"      = slot_back,
	"pants"     = slot_pants,
	"wrists"    = slot_wrists,
	"l_hand"    = slot_l_hand,
	"r_hand"    = slot_r_hand,
	"s_store"   = slot_s_store,
	"l_store"   = slot_l_store,
	"r_store"   = slot_r_store,
	// Restraints -- previously missing entirely, so a character rebuilt from
	// the database (as opposed to reconnecting to their still-resident mob
	// object) always came back unrestrained even if cuffed at store time.
	// get_equipped_item()/equip_to_slot()'s existing slot_handcuffed/
	// slot_legcuffed cases (human/inventory.dm) already set the handcuffed/
	// legcuffed var and call handcuff_update()/legcuff_update() (visual
	// overlay + restrained() mechanics) -- no extra restore-side code needed
	// beyond listing the slots here.
	"handcuffed" = slot_handcuffed,
	"legcuffed"  = slot_legcuffed
))

/**
 * Load saved inventory state into cache.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/mobsInventoryInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_inventory_cache = list()

	if(!databaseCheckConnection("mobsInventoryInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, inventory_json FROM ss13_char_inventory",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "mobsInventoryInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/key = "[query.item[1]]|[query.item[2]]"
		GLOB.persistence_inventory_cache[key] = query.item[3]
		loaded++

	qdel(query)
	log_subsystem_persistence_info("MobInventory: Loaded [loaded] inventory entries.")

/**
 * Save inventory state for all connected living human mobs at round end.
 * Called from SSpersistence.Shutdown().
 */
/datum/controller/subsystem/persistence/proc/mobsInventoryFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("mobsInventoryFinalize"))
		return

	// Delegates to mobsInventorySaveOne() so the finalize sweep refreshes
	// GLOB.persistence_inventory_cache exactly like the logout/cryo save path --
	// otherwise a force-save followed by a same-round rejoin restores stale data.
	var/saved = 0
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.ckey || !H.real_name)
			continue
		if(!H.z)
			continue
		mobsInventorySaveOne(H)
		saved++

	log_subsystem_persistence_info("MobInventory: Saved inventory state for [saved] mobs.")

// ============================================================
// SYSTEM 10: MOB POSITION
// ============================================================

/// Cached position data keyed by "[ckey]|[char_name]"
GLOBAL_LIST_EMPTY(persistence_position_cache)

/**
 * Load saved mob positions into cache.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/mobPositionInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_position_cache = list()

	if(!databaseCheckConnection("mobPositionInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, x, y, z, char_state, in_lace, lace_pod_x, lace_pod_y, lace_pod_z, last_pod_x, last_pod_y, last_pod_z, imprisoned, imprisoned_until, imprisoned_by_faction_uid FROM ss13_mob_position",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "mobPositionInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/key = "[query.item[1]]|[query.item[2]]"
		GLOB.persistence_position_cache[key] = list(
			"x"                         = text2num(query.item[3]),
			"y"                         = text2num(query.item[4]),
			"z"                         = text2num(query.item[5]),
			"char_state"                = query.item[6] || "alive",
			"in_lace"                   = text2num(query.item[7]),
			"lace_pod_x"                = text2num(query.item[8]),
			"lace_pod_y"                = text2num(query.item[9]),
			"lace_pod_z"                = text2num(query.item[10]),
			"last_pod_x"                = text2num(query.item[11]),
			"last_pod_y"                = text2num(query.item[12]),
			"last_pod_z"                = text2num(query.item[13]),
			"imprisoned"                = text2num(query.item[14]),
			"imprisoned_until"          = query.item[15],
			"imprisoned_by_faction_uid" = query.item[16]
		)
		loaded++

	qdel(query)
	log_subsystem_persistence_info("MobPosition: Loaded [loaded] saved positions.")

/**
 * Delete all persistence data for a specific character from every SQL table.
 * Called when a player deletes their character via the preferences panel.
 */
/proc/persistence_delete_character_data(ckey, char_name)
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return
	var/tables = list("ss13_char_health", "ss13_char_inventory", "ss13_char_identity", "ss13_mob_position")
	for(var/table in tables)
		var/datum/db_query/q = SSdbcore.NewQuery(
			"DELETE FROM [table] WHERE ckey = :ckey AND char_name = :char_name",
			list("ckey" = ckey, "char_name" = char_name)
		)
		q.Execute()
		qdel(q)
		// These four are exactly the tables _centralCharacterWriteThrough()
		// mirrors, so a local-only delete left the central copy behind for
		// the read-through to resurrect. No-op unless central sync is on.
		SSpersistence._centralCharacterDelete(table, ckey, char_name)
	// Bank account -- no other deletion path touches this at all, so a
	// "deleted" character otherwise keeps a genuinely live, spendable
	// account forever (same query/cache-clear shape as the admin
	// "Reset Player Bank Account" verb, persistence_factions.dm, just
	// scoped to this one character instead of every account for the ckey).
	var/datum/db_query/mq = SSdbcore.NewQuery(
		"DELETE FROM ss13_money_accounts WHERE ckey = :ckey AND char_name = :char_name",
		list("ckey" = ckey, "char_name" = char_name)
	)
	mq.Execute()
	qdel(mq)
	_economyDeleteAccountCentral(ckey, char_name)
	// Also clear from in-memory caches so the character stops appearing in selection
	var/key = "[ckey]|[char_name]"
	GLOB.persistence_health_cache    -= key
	GLOB.persistence_inventory_cache -= key
	GLOB.persistence_identity_cache  -= key
	GLOB.persistence_position_cache  -= key
	GLOB.persistence_economy_cache   -= key
	log_world("Persistence: Deleted all data for character '[char_name]' ([ckey]).")

/**
 * Save position for all living human mobs (called from forceSaveAll / Shutdown).
 */
/datum/controller/subsystem/persistence/proc/mobsPositionFinalizeAll()
	PRIVATE_PROC(TRUE)
	if(!databaseCheckConnection("mobsPositionFinalizeAll"))
		return
	var/saved = 0
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.ckey || !H.real_name)
			continue
		if(!H.z)
			continue
		mobPositionSave(H)
		saved++
	log_subsystem_persistence_info("MobPosition: Saved positions for [saved] mobs.")

/**
 * Save one mob's current position to the database immediately.
 * Called on logout / cryo.
 */
/datum/controller/subsystem/persistence/proc/mobPositionSave(mob/living/carbon/human/H)
	if(!H || !H.ckey || !H.real_name)
		return
	if(!databaseCheckConnection("mobPositionSave"))
		return

	// A human write always means the character is embodied (alive or dead-in-body),
	// never in_lace -- that state is written separately by lacePositionSave()
	// when the consciousness is extracted into a neural lace.
	var/state = (H.stat == DEAD) ? "dead_body" : "alive"

	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_mob_position (ckey, char_name, x, y, z, char_state, in_lace, lace_pod_x, lace_pod_y, lace_pod_z)
		VALUES (:ckey, :char_name, :x, :y, :z, :char_state, 0, NULL, NULL, NULL)
		ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z), char_state = VALUES(char_state),
		in_lace = 0, lace_pod_x = NULL, lace_pod_y = NULL, lace_pod_z = NULL, saved_at = NOW()"},
		list("ckey" = H.ckey, "char_name" = H.real_name, "x" = H.x, "y" = H.y, "z" = H.z, "char_state" = state)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "mobPositionSave")
	qdel(ins)

	// Update cache in place -- replacing the entry would drop fields this
	// write doesn't own (last_pod_*, which only pod stores touch).
	var/key = "[H.ckey]|[H.real_name]"
	var/list/entry = GLOB.persistence_position_cache[key]
	if(!islist(entry))
		entry = list()
		GLOB.persistence_position_cache[key] = entry
	entry["x"]          = H.x
	entry["y"]          = H.y
	entry["z"]          = H.z
	entry["char_state"] = state
	entry["in_lace"]    = 0
	entry["lace_pod_x"] = null
	entry["lace_pod_y"] = null
	entry["lace_pod_z"] = null

	// Core position fields only -- last_pod_*/imprisoned*/faction_bound*
	// (set by separate procs further down, not here) are NOT yet wired to
	// central. See SQL/migrate-central/V006__character_sync.sql's header.
	_centralCharacterWriteThrough("ss13_mob_position",
		list("ckey", "char_name", "x", "y", "z", "char_state", "in_lace", "lace_pod_x", "lace_pod_y", "lace_pod_z"),
		list(H.ckey, H.real_name, H.x, H.y, H.z, state, 0, null, null, null))

/**
 * Save the "in_lace" position state for a captured consciousness, keyed on the
 * lace's REGISTERED identity (not the disembodied lace_mob's own ckey, which
 * may be blank if it was created via Assign Consciousness). Called on
 * lace_mob logout and whenever a lace is slotted into a storage vault.
 */
/datum/controller/subsystem/persistence/proc/lacePositionSave(ckey, char_name, turf/T)
	if(!ckey || !char_name || !T)
		return
	if(!databaseCheckConnection("lacePositionSave"))
		return

	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_mob_position (ckey, char_name, x, y, z, char_state, in_lace, lace_pod_x, lace_pod_y, lace_pod_z)
		VALUES (:ckey, :char_name, :x, :y, :z, 'in_lace', 1, :x, :y, :z)
		ON DUPLICATE KEY UPDATE char_state = 'in_lace', in_lace = 1,
		lace_pod_x = VALUES(lace_pod_x), lace_pod_y = VALUES(lace_pod_y), lace_pod_z = VALUES(lace_pod_z), saved_at = NOW()"},
		list("ckey" = ckey, "char_name" = char_name, "x" = T.x, "y" = T.y, "z" = T.z)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "lacePositionSave")
	qdel(ins)

	// In-place for the same reason as mobPositionSave: don't drop last_pod_*.
	var/key = "[ckey]|[char_name]"
	var/list/entry = GLOB.persistence_position_cache[key]
	if(!islist(entry))
		entry = list()
		GLOB.persistence_position_cache[key] = entry
	entry["x"]          = T.x
	entry["y"]          = T.y
	entry["z"]          = T.z
	entry["char_state"] = "in_lace"
	entry["in_lace"]    = 1
	entry["lace_pod_x"] = T.x
	entry["lace_pod_y"] = T.y
	entry["lace_pod_z"] = T.z

	_centralCharacterWriteThrough("ss13_mob_position",
		list("ckey", "char_name", "x", "y", "z", "char_state", "in_lace", "lace_pod_x", "lace_pod_y", "lace_pod_z"),
		list(ckey, char_name, T.x, T.y, T.z, "in_lace", 1, T.x, T.y, T.z))

/**
 * Reset a character's persisted state to "alive" without touching position --
 * called by every successful revival path (resleeve, rejoin-wake) so a stale
 * in_lace/dead_body flag doesn't stick around after the character is back up.
 */
/proc/persistence_set_char_state(ckey, char_name, state)
	if(!GLOB.config.sql_enabled || !ckey || !char_name)
		return
	if(!SSpersistence.databaseCheckConnection("persistence_set_char_state"))
		return

	var/datum/db_query/upd = SSdbcore.NewQuery(
		{"UPDATE ss13_mob_position SET char_state = :state, in_lace = 0, lace_pod_x = NULL, lace_pod_y = NULL, lace_pod_z = NULL
		WHERE ckey = :ckey AND char_name = :char_name"},
		list("ckey" = ckey, "char_name" = char_name, "state" = state)
	)
	upd.Execute()
	SSpersistence.databaseCheckQueryResult(upd, "persistence_set_char_state")
	qdel(upd)

	var/key = "[ckey]|[char_name]"
	var/list/entry = GLOB.persistence_position_cache[key]
	if(islist(entry))
		entry["char_state"] = state
		entry["in_lace"]    = 0
		entry["lace_pod_x"] = null
		entry["lace_pod_y"] = null
		entry["lace_pod_z"] = null

/**
 * Remember the cryopod this character last stored at, so rejoins (including
 * across restarts) wake them from the same pod. Overwrites on every pod
 * store -- "last used". The row exists by the time this runs: every store
 * flow calls mobPositionSave() first.
 */
/proc/persistence_set_last_pod(ckey, char_name, obj/structure/machinery/cryopod/pod)
	if(!GLOB.config.sql_enabled || !ckey || !char_name)
		return
	if(!istype(pod) || !pod.z)
		return
	if(!SSpersistence.databaseCheckConnection("persistence_set_last_pod"))
		return

	var/datum/db_query/upd = SSdbcore.NewQuery(
		{"UPDATE ss13_mob_position SET last_pod_x = :x, last_pod_y = :y, last_pod_z = :z
		WHERE ckey = :ckey AND char_name = :char_name"},
		list("ckey" = ckey, "char_name" = char_name, "x" = pod.x, "y" = pod.y, "z" = pod.z)
	)
	upd.Execute()
	SSpersistence.databaseCheckQueryResult(upd, "persistence_set_last_pod")
	qdel(upd)

	var/key = "[ckey]|[char_name]"
	var/list/entry = GLOB.persistence_position_cache[key]
	if(!islist(entry))
		entry = list()
		GLOB.persistence_position_cache[key] = entry
	entry["last_pod_x"] = pod.x
	entry["last_pod_y"] = pod.y
	entry["last_pod_z"] = pod.z

	SSpersistence._centralCharacterPartialUpdate("ss13_mob_position",
		list("last_pod_x", "last_pod_y", "last_pod_z"),
		list(pod.x, pod.y, pod.z),
		ckey, char_name)

/**
 * Sets (or clears) a character's imprisonment -- used by the cryogenic
 * prison storage machine (cryopod_prison.dm). until_minutes null/0 combined
 * with imprisoned=TRUE means an indefinite sentence; a positive until_minutes
 * computes the release DATETIME as NOW() + that many minutes in SQL, so wall-
 * clock expiry math never has to happen in DM. faction_uid records WHICH
 * faction currently holds this character -- imprisonment is exclusive per
 * faction (see cryopod_prison.dm's cross-faction refusal check); always
 * cleared to NULL when imprisoned=FALSE regardless of what's passed. Mirrors
 * persistence_set_char_state()'s exact shape.
 */
/proc/persistence_set_imprisoned(ckey, char_name, imprisoned, until_minutes = null, faction_uid = null)
	if(!GLOB.config.sql_enabled || !ckey || !char_name)
		return
	if(!SSpersistence.databaseCheckConnection("persistence_set_imprisoned"))
		return

	faction_uid = imprisoned ? normalize_faction_uid(faction_uid) : null

	var/datum/db_query/upd
	if(!imprisoned)
		upd = SSdbcore.NewQuery(
			"UPDATE ss13_mob_position SET imprisoned = 0, imprisoned_until = NULL, imprisoned_by_faction_uid = NULL WHERE ckey = :ckey AND char_name = :char_name",
			list("ckey" = ckey, "char_name" = char_name)
		)
	else if(isnull(until_minutes) || until_minutes <= 0)
		upd = SSdbcore.NewQuery(
			"UPDATE ss13_mob_position SET imprisoned = 1, imprisoned_until = NULL, imprisoned_by_faction_uid = :faction WHERE ckey = :ckey AND char_name = :char_name",
			list("ckey" = ckey, "char_name" = char_name, "faction" = faction_uid)
		)
	else
		upd = SSdbcore.NewQuery(
			"UPDATE ss13_mob_position SET imprisoned = 1, imprisoned_until = DATE_ADD(NOW(), INTERVAL :minutes MINUTE), imprisoned_by_faction_uid = :faction WHERE ckey = :ckey AND char_name = :char_name",
			list("ckey" = ckey, "char_name" = char_name, "minutes" = until_minutes, "faction" = faction_uid)
		)
	upd.Execute()
	SSpersistence.databaseCheckQueryResult(upd, "persistence_set_imprisoned")
	qdel(upd)

	var/key = "[ckey]|[char_name]"
	var/list/entry = GLOB.persistence_position_cache[key]
	if(!islist(entry))
		entry = list()
		GLOB.persistence_position_cache[key] = entry
	entry["imprisoned"] = imprisoned ? 1 : 0
	entry["imprisoned_by_faction_uid"] = faction_uid
	// The actual release DATETIME is never cached -- persistence_character_
	// imprisonment_status() always re-reads it live from SQL, since NOW()-
	// relative expiry is exactly what the database should be doing, not DM.
	entry["imprisoned_until"] = null

	// Mirrors the 3-branch local query above verbatim, against
	// SScentraldb instead -- NOT routed through
	// _centralCharacterPartialUpdate() (persistence_mobs.dm's shared
	// helper), which only binds plain column=value pairs and can't express
	// the DATE_ADD(NOW(), ...) expression the timed-sentence branch needs.
	// Same "let SQL do wall-clock arithmetic, not DM" reasoning as
	// everywhere else in this codebase that computes an expiry.
	if(SSpersistence._centralCharacterSyncActive())
		var/datum/db_query/central_upd
		if(!imprisoned)
			central_upd = SScentraldb.NewQuery(
				"UPDATE ss13_mob_position SET imprisoned = 0, imprisoned_until = NULL, imprisoned_by_faction_uid = NULL WHERE ckey = :ckey AND char_name = :char_name",
				list("ckey" = ckey, "char_name" = char_name)
			)
		else if(isnull(until_minutes) || until_minutes <= 0)
			central_upd = SScentraldb.NewQuery(
				"UPDATE ss13_mob_position SET imprisoned = 1, imprisoned_until = NULL, imprisoned_by_faction_uid = :faction WHERE ckey = :ckey AND char_name = :char_name",
				list("ckey" = ckey, "char_name" = char_name, "faction" = faction_uid)
			)
		else
			central_upd = SScentraldb.NewQuery(
				"UPDATE ss13_mob_position SET imprisoned = 1, imprisoned_until = DATE_ADD(NOW(), INTERVAL :minutes MINUTE), imprisoned_by_faction_uid = :faction WHERE ckey = :ckey AND char_name = :char_name",
				list("ckey" = ckey, "char_name" = char_name, "minutes" = until_minutes, "faction" = faction_uid)
			)
		central_upd.Execute()
		SSpersistence.databaseCheckQueryResult(central_upd, "persistence_set_imprisoned (central)")
		qdel(central_upd)

/**
 * Sets (or clears) a character's faction shackle -- same shape as
 * persistence_set_imprisoned() above, ckey+char_name keyed so it survives
 * relog/restart independent of whatever ID card the character currently
 * holds. See faction_bound.dm.
 */
/proc/persistence_set_faction_bound(ckey, char_name, bound, faction_uid = null)
	if(!GLOB.config.sql_enabled || !ckey || !char_name)
		return
	if(!SSpersistence.databaseCheckConnection("persistence_set_faction_bound"))
		return

	faction_uid = bound ? normalize_faction_uid(faction_uid) : null

	var/datum/db_query/upd = SSdbcore.NewQuery(
		"UPDATE ss13_mob_position SET faction_bound = :bound, faction_bound_uid = :faction WHERE ckey = :ckey AND char_name = :char_name",
		list("ckey" = ckey, "char_name" = char_name, "bound" = bound ? 1 : 0, "faction" = faction_uid)
	)
	upd.Execute()
	SSpersistence.databaseCheckQueryResult(upd, "persistence_set_faction_bound")
	qdel(upd)

	var/key = "[ckey]|[char_name]"
	var/list/entry = GLOB.persistence_position_cache[key]
	if(!islist(entry))
		entry = list()
		GLOB.persistence_position_cache[key] = entry
	entry["faction_bound"] = bound ? 1 : 0
	entry["faction_bound_uid"] = faction_uid

	SSpersistence._centralCharacterPartialUpdate("ss13_mob_position",
		list("faction_bound", "faction_bound_uid"),
		list(bound ? 1 : 0, faction_uid),
		ckey, char_name)

/// Live re-check, mirrored on the in-memory cache populated at boot from
/// ss13_mob_position -- returns the faction_uid this character is still
/// shackled to, or null if not (or never) bound. No live SQL round-trip
/// needed on the hot path (mob Login()) since the cache is already kept in
/// sync by persistence_set_faction_bound() above.
/proc/persistence_character_faction_bound(ckey, char_name)
	if(!ckey || !char_name)
		return null
	var/list/entry = GLOB.persistence_position_cache["[ckey]|[char_name]"]
	if(!islist(entry) || !entry["faction_bound"])
		return null
	return entry["faction_bound_uid"]

/**
 * Shared core for the two public procs below -- always re-verified live
 * against SQL (wall-clock expiry) and against whether the specific prison
 * pod this character was stored in still physically exists. Returns null if
 * not imprisoned at all (including a sentence that just expired, or whose
 * pod is gone -- both cleared here rather than waiting for a sweep, a
 * safety valve against ever being permanently trapped), or
 * list("indefinite"=, "remaining_seconds"=, "cell"=) if still genuinely
 * on the books -- regardless of that cell's own locked/unlocked state,
 * which the two wrappers below interpret differently.
 */
/proc/_persistence_imprisonment_core(ckey, char_name)
	if(!GLOB.config.sql_enabled || !ckey || !char_name)
		return null
	var/list/entry = GLOB.persistence_position_cache["[ckey]|[char_name]"]
	if(!islist(entry) || !entry["imprisoned"])
		return null
	if(!SSpersistence.databaseCheckConnection("_persistence_imprisonment_core"))
		return null

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"SELECT imprisoned_until IS NULL AS indefinite, TIMESTAMPDIFF(SECOND, NOW(), imprisoned_until) AS remaining
		FROM ss13_mob_position WHERE ckey = :ckey AND char_name = :char_name AND imprisoned = 1"},
		list("ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()
	if(!SSpersistence.databaseCheckQueryResult(q, "_persistence_imprisonment_core") || !q.NextRow())
		qdel(q)
		return null
	var/indefinite = text2num(q.item[1])
	var/remaining = text2num(q.item[2])
	qdel(q)

	if(!indefinite && remaining <= 0)
		// Sentence expired -- clear it now rather than waiting for a sweep.
		persistence_set_imprisoned(ckey, char_name, FALSE)
		return null

	// Pod-existence check -- a destroyed/missing cell first tries to reassign
	// to another live cell belonging to the same faction (mirrors the manual
	// "transfer" operator action, prison_management.dm) before falling back
	// to auto-freeing. Confirmed with the user this reassignment should
	// happen rather than a silent, unconditional pardon.
	var/list/pos = GLOB.persistence_position_cache["[ckey]|[char_name]"]
	var/pod_pz = pos ? pos["last_pod_z"] : null
	var/obj/structure/machinery/cryopod/prison/cell
	if(pod_pz && pod_pz >= 1 && pod_pz <= world.maxz)
		var/turf/T = locate(pos["last_pod_x"], pos["last_pod_y"], pod_pz)
		if(T)
			cell = locate(/obj/structure/machinery/cryopod/prison) in T
	if(!cell)
		var/imprisoning_faction = normalize_faction_uid(pos ? pos["imprisoned_by_faction_uid"] : null)
		for(var/obj/structure/machinery/cryopod/prison/P in world)
			if(normalize_faction_uid(P.persistent_network) == imprisoning_faction)
				cell = P
				break
		if(cell)
			persistence_set_last_pod(ckey, char_name, cell)
			if(islist(pos))
				pos["last_pod_x"] = cell.x
				pos["last_pod_y"] = cell.y
				pos["last_pod_z"] = cell.z
			log_and_message_admins("Prison pod for [ckey]/[char_name] was gone -- automatically reassigned to another [get_faction_name(imprisoning_faction)] cell at ([cell.x],[cell.y],[cell.z]).")
		else
			log_and_message_admins("Prison pod for [ckey]/[char_name] was gone and no other [get_faction_name(imprisoning_faction)] cell exists -- auto-pardoned.")
			persistence_set_imprisoned(ckey, char_name, FALSE)
			return null

	return list(
		"indefinite"        = !!indefinite,
		"remaining_seconds" = indefinite ? 0 : remaining,
		"cell"              = cell,
		"faction_uid"       = pos["imprisoned_by_faction_uid"]
	)

/**
 * "Should this character's Play button be blocked right now" -- returns null
 * (may play) or list("indefinite"=, "remaining_seconds"=). Unlocked is a
 * furlough/parole-style bypass, not a release (confirmed with the user):
 * the character may spawn/play despite their sentence, but the sentence
 * itself (and the row backing it) is left untouched, so re-locking the pod
 * -- or the pod vanishing entirely, per the core check -- resumes/ends
 * enforcement exactly where the timer already is. Single source of truth
 * for both the lobby Play-button gate (persistent_menu.dm) and
 * PersistentAutoSpawn()'s defense-in-depth check.
 */
/proc/persistence_character_imprisonment_status(ckey, char_name)
	var/list/core = _persistence_imprisonment_core(ckey, char_name)
	if(!core)
		return null
	if(!core["cell"].frozen)
		return null
	return list("indefinite" = core["indefinite"], "remaining_seconds" = core["remaining_seconds"])

/**
 * Full imprisonment record for management UIs (the prison pod's own TGUI,
 * the Prison Management program) -- unlike persistence_character_imprisonment_status(),
 * this does NOT hide an unlocked/paroled prisoner (an operator still needs
 * to see and manage them), and additionally reports the tied cell's locked
 * state and a reference to it. Returns null if not currently imprisoned at
 * all (same expiry/pod-missing clearing as the core proc).
 */
/proc/persistence_character_imprisonment_record(ckey, char_name)
	var/list/core = _persistence_imprisonment_core(ckey, char_name)
	if(!core)
		return null
	return list(
		"indefinite"        = core["indefinite"],
		"remaining_seconds" = core["remaining_seconds"],
		"frozen"            = core["cell"].frozen,
		"cell"              = core["cell"],
		"faction_uid"       = core["faction_uid"]
	)

/// TRUE if ckey/char_name currently has an unexpired sentence -- the one
/// live check every enforcement point (movement, speech, emotes) re-runs,
/// so natural expiry lifts every restriction on its own without needing a
/// separate timer/callback to unset anything.
/proc/persistence_character_actively_imprisoned(ckey, char_name)
	return !!_persistence_imprisonment_core(ckey, char_name)

/// TRUE if ANY of this ckey's (non-deleted) characters is currently
/// imprisoned per persistence_character_imprisonment_status() -- same
/// frozen/parole-respecting semantics as the Play-button gate, so an admin
/// paroling a character also lifts this. Used to block character-roster
/// moves that would otherwise let a player sidestep an active sentence:
/// deleting the imprisoned character itself (persistent_menu.dm's
/// "delete_char"), or creating a fresh alt in another slot to play instead
/// ("create") while the sentence keeps ticking untouched either way.
/proc/persistence_ckey_has_imprisoned_character(ckey)
	if(!GLOB.config.sql_enabled || !ckey)
		return FALSE
	if(!SSpersistence.databaseCheckConnection("persistence_ckey_has_imprisoned_character"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT name FROM ss13_characters WHERE ckey = :ckey AND deleted_at IS NULL",
		list("ckey" = ckey)
	)
	q.Execute()
	var/list/names = list()
	while(q.NextRow())
		names += q.item[1]
	qdel(q)
	for(var/char_name in names)
		if(persistence_character_imprisonment_status(ckey, char_name))
			return TRUE
	return FALSE

/**
 * Restore mob to their last saved position, or spawn at default landmark.
 */
/mob/living/carbon/human/proc/applyPersistentPosition()
	if(!GLOB.config.sql_enabled || !islist(GLOB.persistence_position_cache))
		_persistentSpawnDefault()
		return

	var/key = "[ckey]|[real_name]"
	var/list/entry = GLOB.persistence_position_cache[key]
	if(!entry)
		// Same column set mobPositionInitialize()'s own boot-time bulk load
		// selects, plus faction_bound/faction_bound_uid (which that proc's
		// SELECT omits -- a separate, pre-existing local-only gap, not
		// something this read-through needs to replicate: central's copy of
		// faction_bound is kept correct by persistence_set_faction_bound()'s
		// own write-through regardless of that unrelated boot-load hole).
		var/list/row = SSpersistence._centralCharacterReadThrough("ss13_mob_position",
			list("x", "y", "z", "char_state", "in_lace", "lace_pod_x", "lace_pod_y", "lace_pod_z",
				"last_pod_x", "last_pod_y", "last_pod_z", "imprisoned", "imprisoned_until", "imprisoned_by_faction_uid",
				"faction_bound", "faction_bound_uid"),
			ckey, real_name)
		if(!row)
			_persistentSpawnDefault()
			return
		entry = list(
			"x"                         = text2num(row[1]),
			"y"                         = text2num(row[2]),
			"z"                         = text2num(row[3]),
			"char_state"                = row[4] || "alive",
			"in_lace"                   = text2num(row[5]),
			"lace_pod_x"                = text2num(row[6]),
			"lace_pod_y"                = text2num(row[7]),
			"lace_pod_z"                = text2num(row[8]),
			"last_pod_x"                = text2num(row[9]),
			"last_pod_y"                = text2num(row[10]),
			"last_pod_z"                = text2num(row[11]),
			"imprisoned"                = text2num(row[12]),
			"imprisoned_until"          = row[13],
			"imprisoned_by_faction_uid" = row[14],
			"faction_bound"             = text2num(row[15]),
			"faction_bound_uid"         = row[16]
		)
		GLOB.persistence_position_cache[key] = entry
		SSpersistence._centralCharacterSelfHealLocal("ss13_mob_position",
			list("ckey", "char_name", "x", "y", "z", "char_state", "in_lace", "lace_pod_x", "lace_pod_y", "lace_pod_z",
				"last_pod_x", "last_pod_y", "last_pod_z", "imprisoned", "imprisoned_until", "imprisoned_by_faction_uid",
				"faction_bound", "faction_bound_uid"),
			list(ckey, real_name, entry["x"], entry["y"], entry["z"], entry["char_state"], entry["in_lace"],
				entry["lace_pod_x"], entry["lace_pod_y"], entry["lace_pod_z"],
				entry["last_pod_x"], entry["last_pod_y"], entry["last_pod_z"],
				entry["imprisoned"], entry["imprisoned_until"], entry["imprisoned_by_faction_uid"],
				entry["faction_bound"], entry["faction_bound_uid"]))

	var/sx = text2num(entry["x"]) || entry["x"]
	var/sy = text2num(entry["y"]) || entry["y"]
	var/sz = text2num(entry["z"]) || entry["z"]
	var/turf/T = locate(sx, sy, sz)
	if(T && sz)
		forceMove(T)
		log_subsystem_persistence_info("MobPosition: Restored [real_name] to ([sx],[sy],[sz]).")
	else
		_persistentSpawnDefault()

/mob/living/carbon/human/proc/_persistentSpawnDefault()
	var/list/landmarks = list()
	for(var/obj/effect/landmark/start/L in world)
		landmarks += L
	if(length(landmarks))
		forceMove(get_turf(pick(landmarks)))
	else
		forceMove(GLOB.newplayer_start)

// ============================================================
// PER-MOB SAVE HELPERS (used by cryo-on-logout)
// ============================================================

/**
 * Save health state for a single mob immediately.
 */
/datum/controller/subsystem/persistence/proc/mobsHealthSaveOne(mob/living/carbon/human/H)
	if(!H || !H.ckey || !H.real_name)
		return
	if(!databaseCheckConnection("mobsHealthSaveOne"))
		return

	var/list/organ_damage = list()
	var/list/serialized_laces = list()
	for(var/limb_name in H.species.has_limbs)
		var/obj/item/organ/external/O = H.organs_by_name[limb_name]
		if(!O || O.is_stump())
			organ_damage[limb_name] = list("missing" = 1)
			continue
		var/list/augments = list()
		for(var/obj/item/organ/A in O.internal_organs)
			if(!A.is_augment)
				continue
			if(istype(A, /obj/item/organ/internal/neural_lace))
				var/obj/item/organ/internal/neural_lace/lace = A
				serialized_laces += lace
				augments += list(list(
					"type"            = "[A.type]",
					"lace_damage"     = lace.lace_damage,
					"registered_name" = lace.registered_name,
					"registered_ckey" = lace.registered_ckey,
					"owner_faction"   = lace.owner_faction
				))
			else
				augments += "[A.type]"
		if(!O.brute_dam && !O.burn_dam && !O.robotic && !length(augments))
			continue
		var/list/limb = list("brute" = O.brute_dam, "burn" = O.burn_dam)
		if(O.robotic)
			limb["robotic"] = 1
			if(O.model) limb["model"] = O.model
		if(length(augments))
			limb["augments"] = augments
		organ_damage[limb_name] = limb

	// Defensive: a lace registered on the mob but absent from every external
	// organ's internal_organs list (wiring bug somewhere) would silently drop
	// from the save -- serialize it under the head entry so it always round-trips.
	for(var/obj/item/organ/internal/neural_lace/stray in H.internal_organs)
		if(QDELETED(stray) || (stray in serialized_laces))
			continue
		var/list/head_limb = organ_damage["head"]
		if(!islist(head_limb))
			head_limb = list("brute" = 0, "burn" = 0)
			organ_damage["head"] = head_limb
		var/list/head_augs = head_limb["augments"]
		if(!islist(head_augs))
			head_augs = list()
			head_limb["augments"] = head_augs
		head_augs += list(list(
			"type"            = "[stray.type]",
			"lace_damage"     = stray.lace_damage,
			"registered_name" = stray.registered_name,
			"registered_ckey" = stray.registered_ckey,
			"owner_faction"   = stray.owner_faction
		))
		log_subsystem_persistence_info("MobHealth: Lace for [H.real_name] was missing from limb organ lists -- serialized defensively under head.")

	var/organ_json = length(organ_damage) ? json_encode(organ_damage) : null
	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_health (ckey, char_name, organ_damage_json, stamina, bodytemperature, on_fire, fire_stacks, nutrition, hydration, saved_at)
		VALUES (:ckey, :char_name, :organ_damage_json, :stamina, :bodytemperature, :on_fire, :fire_stacks, :nutrition, :hydration, NOW())
		ON DUPLICATE KEY UPDATE organ_damage_json = VALUES(organ_damage_json), stamina = VALUES(stamina),
		bodytemperature = VALUES(bodytemperature), on_fire = VALUES(on_fire), fire_stacks = VALUES(fire_stacks),
		nutrition = VALUES(nutrition), hydration = VALUES(hydration), saved_at = NOW()"},
		list(
			"ckey"              = H.ckey,
			"char_name"         = H.real_name,
			"organ_damage_json" = organ_json,
			"stamina"           = H.stamina,
			"bodytemperature"   = H.bodytemperature,
			"on_fire"           = H.on_fire ? 1 : 0,
			"fire_stacks"       = H.fire_stacks,
			"nutrition"         = H.nutrition,
			"hydration"         = H.hydration
		)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "mobsHealthSaveOne")
	qdel(ins)

	// Refresh the in-memory cache too -- restore reads the cache, not the DB,
	// so a same-round store/rejoin must see this save (matches the pattern
	// mobPositionSave already uses).
	GLOB.persistence_health_cache["[H.ckey]|[H.real_name]"] = list(
		"organ_damage_json" = organ_json,
		"stamina"           = H.stamina,
		"bodytemperature"   = H.bodytemperature,
		"on_fire"           = H.on_fire ? 1 : 0,
		"fire_stacks"       = H.fire_stacks,
		"nutrition"         = H.nutrition,
		"hydration"         = H.hydration
	)

	_centralCharacterWriteThrough("ss13_char_health",
		list("ckey", "char_name", "organ_damage_json", "stamina", "bodytemperature", "on_fire", "fire_stacks", "nutrition", "hydration"),
		list(H.ckey, H.real_name, organ_json, H.stamina, H.bodytemperature, H.on_fire ? 1 : 0, H.fire_stacks, H.nutrition, H.hydration))

// ============================================================
// VITALS ADMIN VERB
// ============================================================

/datum/admins/proc/check_vitals()
	set name = "Check Vitals"
	set category = "Persistence.Characters"

	if(!check_rights(R_ADMIN))
		return

	var/target_ckey = tgui_input_text(usr, "Enter the ckey to check:", "Check Vitals")
	if(!target_ckey) return
	target_ckey = ckey(target_ckey)

	var/client/C = GLOB.directory[target_ckey]
	if(!C || !C.mob)
		to_chat(usr, SPAN_WARNING("No connected client found for ckey '[target_ckey]'."))
		return

	var/mob/living/carbon/human/H = C.mob
	if(!istype(H))
		to_chat(usr, SPAN_WARNING("[key_name(C)]'s current mob is not a living human ([C.mob.type])."))
		return

	to_chat(usr, SPAN_NOTICE("<b>Vitals for [H.real_name] ([target_ckey])</b>"))
	to_chat(usr, SPAN_NOTICE("State: [H.stat == CONSCIOUS ? "Conscious" : (H.stat == UNCONSCIOUS ? "Unconscious" : "Dead")]"))
	to_chat(usr, SPAN_NOTICE("Health: [H.health]/[H.maxhealth]"))
	to_chat(usr, SPAN_NOTICE("Nutrition (hunger): [H.nutrition]"))
	to_chat(usr, SPAN_NOTICE("Hydration (thirst): [H.hydration]"))
	to_chat(usr, SPAN_NOTICE("Body temperature: [H.bodytemperature]K"))

	var/obj/item/organ/internal/neural_lace/lace = H.internal_organs_by_name["neural_lace"]
	if(!lace)
		to_chat(usr, SPAN_WARNING("Neural lace: not installed."))
	else
		var/damage_desc
		if(lace.lace_damage >= 100)
			damage_desc = "DESTROYED"
		else if(lace.lace_damage >= 76)
			damage_desc = "SEVERE ([lace.lace_damage]/100)"
		else if(lace.lace_damage >= 51)
			damage_desc = "MODERATE ([lace.lace_damage]/100)"
		else if(lace.lace_damage >= 26)
			damage_desc = "MINOR ([lace.lace_damage]/100)"
		else
			damage_desc = "NOMINAL"
		to_chat(usr, SPAN_NOTICE("Neural lace: installed. Integrity: [damage_desc][lace.lace_occupied ? " -- CONSCIOUSNESS STORED" : ""]"))

	log_and_message_admins("checked vitals for [key_name(C)]", usr)

/**
 * TRUE if `I` is an inbuilt component of a rig or voidsuit that `H` also has equipped.
 *
 * Deployed suits push their own parts out into real inventory slots -- a voidsuit's
 * equipped() sends helmet to slot_head, boots to slot_shoes and tank/cooler to
 * slot_s_store, and a rig's toggle_piece() does the same for helmet/chest/gloves/boots.
 * The slot walk in mobsInventorySaveOne() has no idea those objects are already owned
 * by the suit in another slot, so without this check the SAME object gets written to
 * the database twice: once nested under its parent (void_helmet/rig_helmet...) and
 * again as a standalone top-level slot entry.
 *
 * That double-write is what breaks restore. applyPersistentInventory() qdels whatever
 * occupies a slot before restoring into it, so the voidsuit (wear_suit, restored early)
 * deploys its helmet into slot_head and the very next loop iteration destroys it --
 * leaving V.helmet/boots/tank/cooler null and the suit reporting "does not have
 * anything installed". Rigs live in slot_back and get the mirror-image failure: four
 * orphan pieces are equipped first and then block the real suit from deploying.
 *
 * Both the save path and the restore path consult this proc so they can never disagree
 * about what counts as suit-owned.
 */
/proc/_persistence_item_is_suit_component(mob/living/carbon/human/H, obj/item/I)
	if(!istype(H) || !I)
		return FALSE
	for(var/slot_name in GLOB.persistence_inventory_slots)
		var/obj/item/W = H.get_equipped_item(GLOB.persistence_inventory_slots[slot_name])
		if(!W || W == I)
			continue
		if(istype(W, /obj/item/rig))
			var/obj/item/rig/R = W
			if(I == R.helmet || I == R.chest || I == R.gloves || I == R.boots)
				return TRUE
		else if(istype(W, /obj/item/clothing/suit/space/void))
			var/obj/item/clothing/suit/space/void/V = W
			if(I == V.helmet || I == V.boots || I == V.tank || I == V.cooler)
				return TRUE
	return FALSE

/**
 * Pull a just-restored voidsuit's inbuilt components back inside the suit.
 *
 * The suit's equipped() deploys helmet/boots/tank/cooler into head/shoes/s_store the
 * instant it is worn, which is not what we want on restore -- installed gear should
 * come back stowed, and leaving it deployed puts it in the path of the slot loop.
 *
 * The suit's own cleanup_from_mob() cannot be reused for this. It retracts the tank
 * and cooler with a bare forceMove(), which moves the object but leaves H.s_store
 * still pointing at it, because only u_equip() clears an inventory slot var. That is
 * harmless in cleanup_from_mob()'s normal callers (dropped() / on_slotmove(), which
 * run from inside remove_from_mob(suit) -- u_equip() has already dropped s_store by
 * then), but here the suit is being put ON, so nothing clears the slot. Going through
 * drop_from_inventory() unequips properly and then moves the part into the suit.
 */
/proc/_persistence_retract_voidsuit(mob/living/carbon/human/H, obj/item/clothing/suit/space/void/V)
	if(!istype(H) || !istype(V))
		return
	for(var/obj/item/component in list(V.helmet, V.boots, V.tank, V.cooler))
		component.canremove = TRUE
		if(component.loc == H)
			H.drop_from_inventory(component, V)
		else if(component.loc != V)
			component.forceMove(V)

/**
 * Save inventory state for a single mob immediately.
 */
/datum/controller/subsystem/persistence/proc/mobsInventorySaveOne(mob/living/carbon/human/H)
	if(!H || !H.ckey || !H.real_name)
		return
	if(!databaseCheckConnection("mobsInventorySaveOne"))
		return

	var/list/inv = list()
	for(var/slot_name in GLOB.persistence_inventory_slots)
		var/slot_id = GLOB.persistence_inventory_slots[slot_name]
		var/obj/item/I = H.get_equipped_item(slot_id)
		// A deployed rig/voidsuit part is already carried by its parent suit's own
		// blob. Recording it here as well is what used to duplicate it and then get
		// it destroyed on restore, so save the slot as empty and let the suit hand
		// the part back on load.
		if(I && _persistence_item_is_suit_component(H, I))
			inv[slot_name] = null
			continue
		// serializePersistentItem() has no internal guard and this proc has no outer
		// one, so an uncaught throw on a single item used to abandon the whole save.
		// The row then kept its previous contents, which the player experiences as
		// their gear silently reverting to an older loadout. Losing one slot is bad;
		// losing the character's entire save is worse.
		try
			inv[slot_name] = I ? serializePersistentItem(I) : null
		catch(var/exception/item_ex)
			inv[slot_name] = null
			log_subsystem_persistence_error("MobInventory: serialization failed for [I ? "[I.type]" : "null"] in slot [slot_name] for [H.real_name]: [item_ex] -- slot saved empty, rest of the character preserved.")

	// Summary of what actually went into the row, so a save that quietly dropped a
	// slot is visible here rather than only in a database dump.
	var/list/saved_slots = list()
	for(var/slot_name in inv)
		if(inv[slot_name])
			saved_slots += slot_name
	log_subsystem_persistence_info("MobInventory: Saving [H.real_name] ([H.ckey]) -- slots: [length(saved_slots) ? jointext(saved_slots, ", ") : "none"].")

	var/inv_json = json_encode(inv)
	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_inventory (ckey, char_name, inventory_json, saved_at)
		VALUES (:ckey, :char_name, :inventory_json, NOW())
		ON DUPLICATE KEY UPDATE inventory_json = VALUES(inventory_json), saved_at = NOW()"},
		list(
			"ckey"           = H.ckey,
			"char_name"      = H.real_name,
			"inventory_json" = inv_json
		)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "mobsInventorySaveOne")
	qdel(ins)

	// Refresh the in-memory cache too -- restore reads the cache, not the DB.
	GLOB.persistence_inventory_cache["[H.ckey]|[H.real_name]"] = inv_json

	_centralCharacterWriteThrough("ss13_char_inventory",
		list("ckey", "char_name", "inventory_json"),
		list(H.ckey, H.real_name, inv_json))

/**
 * Recursively serialize an item as a typepath + contents tree.
 * Only saves typepath; per-item internal state is out of scope for v1.
 * RETURN: list with "type" key and optional "contents" list for storage items.
 */
/proc/serializePersistentItem(obj/item/I)
	if(!I)
		return null
	var/list/data = list("type" = "[I.type]")

	// Storage contents  recursive.
	//
	// The key is emitted even when the storage is EMPTY, deliberately. It used
	// to be gated on length(), which meant an emptied container serialized to
	// nothing but its type -- the floor-item writer then skipped the extra blob
	// entirely (it only emits when the blob has more than "type"), so restore
	// fell back to a plain new(), Initialize() ran fill(), and the container
	// came back stocked with its original starts_with contents. That's the
	// inflatable box handing back 5 doors and 7 walls after you'd emptied it.
	// An explicit empty list records "this really is empty" and forces the
	// restore path to clear the fill() defaults.
	if(istype(I, /obj/item/storage))
		var/obj/item/storage/S = I
		var/list/contents = list()
		for(var/obj/item/child in S.contents)
			var/list/child_data = serializePersistentItem(child)
			if(child_data)
				contents += list(child_data)
		data["contents"] = contents

	// Internal storage -- suits-with-pockets, webbing/storage accessories,
	// helmets: an /obj/item/storage/internal living in the item's contents
	// rather than the item being a storage itself.
	var/obj/item/storage/internal/IS = locate() in I
	if(IS && length(IS.contents))
		var/list/internal_contents = list()
		for(var/obj/item/child in IS.contents)
			var/list/child_data = serializePersistentItem(child)
			if(child_data)
				internal_contents += list(child_data)
		if(length(internal_contents))
			data["internal_storage"] = internal_contents

	// Clothing accessories (uniforms AND suits): holsters, webbing, armbands...
	// Each accessory serializes recursively, so its own internal storage /
	// holstered item comes along.
	if(istype(I, /obj/item/clothing))
		var/obj/item/clothing/C = I
		if(LAZYLEN(C.accessories))
			var/list/acc_out = list()
			for(var/obj/item/clothing/accessory/A in C.accessories)
				var/list/acc_data = serializePersistentItem(A)
				if(acc_data)
					acc_out += list(acc_data)
			if(length(acc_out))
				data["accessories"] = acc_out

	// Holstered weapon inside a holster accessory
	if(istype(I, /obj/item/clothing/accessory/holster))
		var/obj/item/clothing/accessory/holster/HO = I
		if(HO.holstered)
			var/list/holstered_data = serializePersistentItem(HO.holstered)
			if(holstered_data)
				data["holstered"] = holstered_data

	// Boot knife (or shard/utensil) shoved into a shoe's hidden knife slot
	if(istype(I, /obj/item/clothing/shoes))
		var/obj/item/clothing/shoes/SH = I
		if(SH.holding)
			var/list/knife_data = serializePersistentItem(SH.holding)
			if(knife_data)
				data["boot_knife"] = knife_data

	// Hardsuit components -- helmet/chest/gloves/boots are separate obj/item
	// instances parented to the rig, rebuilt fresh (to the rig's defaults)
	// by Initialize() every time, so without this a saved/restored rig
	// silently discards whatever the player actually had attached.
	if(istype(I, /obj/item/rig))
		var/obj/item/rig/R = I
		data["rig_helmet"] = serializePersistentItem(R.helmet)
		data["rig_chest"]  = serializePersistentItem(R.chest)
		data["rig_gloves"] = serializePersistentItem(R.gloves)
		data["rig_boots"]  = serializePersistentItem(R.boots)
		// Air tank and power cell are held in dedicated vars, not contents, and
		// Initialize() respawns air_type/cell_type over whatever the player slotted
		// in. The generic get_cell() branch further down only carries a charge
		// NUMBER, so without this a swapped cell silently reverts to cell_type at
		// the saved charge. Serializing the object keeps the actual type.
		data["rig_air"]  = serializePersistentItem(R.air_supply)
		data["rig_cell"] = serializePersistentItem(R.cell)
		// Installed modules. Initialize() rebuilds the loadout from initial_modules
		// on every new(), so before this every save/load cycle destroyed each
		// player-installed module and resurrected each screwdrivered-out one.
		//
		// The key is emitted even when the list is EMPTY, deliberately, for the same
		// reason as the storage "contents" key above: an emptied rig has to be able
		// to record "this really is empty" and override the initial_modules that
		// Initialize() will have spawned on the restored copy.
		//
		// Recursing through serializePersistentItem() also runs the internal_storage
		// sweep with the module as the subject, which is what finally captures a
		// mounted storage unit's pockets -- they sit at rig.contents -> module.contents,
		// one level deeper than the rig-level sweep can see.
		var/list/module_data = list()
		for(var/obj/item/rig_module/RM in R.installed_modules)
			var/list/mod_entry = serializePersistentItem(RM)
			if(!mod_entry)
				continue
			if(RM == R.selected_module)
				mod_entry["rig_module_selected"] = 1
			module_data += list(mod_entry)
		data["rig_modules"] = module_data

	// Void-suit inbuilt components -- helmet/boots/tank/cooler are player
	// installed/removed via attackby() into dedicated vars (void.dm), not the
	// generic clothing accessories list, and default to null with nothing in
	// Initialize() to rebuild them. Same shape as the rig components above,
	// for the same reason: without this, an installed component silently
	// vanishes (var resets to null) on the next save/restore cycle.
	if(istype(I, /obj/item/clothing/suit/space/void))
		var/obj/item/clothing/suit/space/void/V = I
		data["void_helmet"] = serializePersistentItem(V.helmet)
		data["void_boots"]  = serializePersistentItem(V.boots)
		data["void_tank"]   = serializePersistentItem(V.tank)
		data["void_cooler"] = serializePersistentItem(V.cooler)

	// Power cells carry their exact charge (Initialize refills them to max,
	// so the restore must overwrite afterwards)
	if(istype(I, /obj/item/cell))
		var/obj/item/cell/PC = I
		data["cell_charge"] = PC.charge
	else
		// Devices holding a cell (flashlights, batons, energy guns...) --
		// uniform via get_cell()
		var/obj/item/cell/HC = I.get_cell()
		if(istype(HC) && HC != I)
			data["device_cell_charge"] = HC.charge

	// Visor/mask toggle state -- see persistent_toggle_vars' own doc comment
	// (obj/item base vars, items.dm) for why this is a declared list instead
	// of another istype() branch per helmet/goggle type.
	if(length(I.persistent_toggle_vars))
		var/list/toggle_data = list()
		for(var/vname in I.persistent_toggle_vars)
			toggle_data[vname] = I.vars[vname]
		data["toggle_vars"] = toggle_data

	// Ballistic guns: internal rounds, chambered state, fitted magazine
	if(istype(I, /obj/item/gun/projectile))
		var/obj/item/gun/projectile/G = I
		var/live_loaded = 0
		for(var/obj/item/ammo_casing/CS in G.loaded)
			if(CS.BB)
				live_loaded++
		data["gun_loaded"] = live_loaded
		data["gun_chambered"] = (G.chambered && G.chambered.BB) ? 1 : 0
		if(G.ammo_magazine)
			var/mag_live = 0
			for(var/obj/item/ammo_casing/MC in G.ammo_magazine.stored_ammo)
				if(MC.BB)
					mag_live++
			data["gun_mag"] = list("type" = "[G.ammo_magazine.type]", "live" = mag_live)
	// Standalone magazines: live round count (refilled with the mag's own
	// ammo_type -- mixed handloads are out of scope)
	else if(istype(I, /obj/item/ammo_magazine))
		var/obj/item/ammo_magazine/M = I
		var/live = 0
		for(var/obj/item/ammo_casing/MC in M.stored_ammo)
			if(MC.BB)
				live++
		data["mag_live"] = live
	// Loose casings: spent or live
	else if(istype(I, /obj/item/ammo_casing))
		var/obj/item/ammo_casing/AC = I
		if(!AC.BB)
			data["casing_spent"] = 1

	// RFD matter units
	if(istype(I, /obj/item/rfd))
		var/obj/item/rfd/R = I
		data["rfd_matter"] = R.stored_matter

	// Reagent contents (beakers, bottles, syringes, spray bottles, extinguishers, etc.)
	if(I.reagents && I.reagents.total_volume > 0 && length(I.reagents.reagent_volumes))
		var/list/reagents = list()
		for(var/rtype in I.reagents.reagent_volumes)
			reagents["[rtype]"] = I.reagents.reagent_volumes[rtype]
		data["reagents"] = json_encode(reagents)

	// Paper / note written content
	if(istype(I, /obj/item/paper))
		var/obj/item/paper/P = I
		if(P.info)
			data["paper_info"] = P.info

	// ID cards -- registered name, assignment, access, bank account, revoked state
	if(istype(I, /obj/item/card/id))
		var/obj/item/card/id/ID = I
		data["id_content"] = ID.persistent_objects_get_content()
	else
		// Generic passthrough for any other item type with a
		// persistent_objects_get_content() override (faction charge cards,
		// modular computers, invoices, etc) -- catches state that would
		// otherwise come back blank on a fresh /new item_type(holder).
		var/list/generic_content = I.persistent_objects_get_content()
		if(islist(generic_content) && length(generic_content))
			data["obj_content"] = generic_content
			// Diagnostic: confirm program lists are captured for computers/PDAs
			if(istype(I, /obj/item/modular_computer) && islist(generic_content["programs"]))
				log_subsystem_persistence_info("Modcomp save: [I] programs=[json_encode(generic_content["programs"])]")

	// Stack material amounts
	if(istype(I, /obj/item/stack))
		var/obj/item/stack/ST = I
		data["stack_amount"] = ST.amount

	// Gas tanks -- contents, distribution pressure, tamper marker. Without
	// this a tank saved only its typepath, and Initialize()'s
	// adjust_initial_gas() (tanks.dm) refilled the restored copy to that
	// type's default: a part-used tank came back full (a quiet infinite-air
	// exploit), a custom distribution pressure reverted to ONE_ATMOSPHERE,
	// and a sabotaged tank's manipulated_by marker -- which internals.dm
	// reads to decide whether to trust the label -- was laundered clean.
	// Same gas round-trip the canister worldstate override already uses
	// (persistence_worldstate.dm).
	if(istype(I, /obj/item/tank))
		var/obj/item/tank/TK = I
		data["tank_distribute_pressure"] = TK.distribute_pressure
		if(TK.manipulated_by)
			data["tank_manipulated_by"] = TK.manipulated_by
		if(TK.air_contents)
			data["tank_air_gas"] = json_encode(TK.air_contents.gas)
			data["tank_air_temperature"] = TK.air_contents.temperature

	// Fingerprints/forensics
	if(length(I.fingerprints))
		data["fingerprints"] = json_encode(I.fingerprints)
	if(I.fingerprintshidden)
		data["fingerprintshidden"] = I.fingerprintshidden
	if(I.fingerprintslast)
		data["fingerprintslast"] = I.fingerprintslast
	if(I.suit_fibers)
		data["suit_fibers"] = I.suit_fibers

	return data

/**
 * Apply cached inventory data to a newly spawned human mob.
 * Called from /mob/living/carbon/human/LateInitialize() after job gear is issued.
 * Replaces default job-given items with saved items slot-by-slot.
 */
/mob/living/carbon/human/proc/applyPersistentInventory()
	// !islist(), not !length() -- see applyPersistentHealthData()'s matching
	// comment: an empty cache must still fall through to the
	// read-through-on-miss lookup below, not bail out early.
	if(!GLOB.config.sql_enabled || !islist(GLOB.persistence_inventory_cache))
		return
	if(!ckey || !real_name)
		return

	var/key = "[ckey]|[real_name]"
	var/json = GLOB.persistence_inventory_cache[key]
	if(!json)
		var/list/row = SSpersistence._centralCharacterReadThrough("ss13_char_inventory", list("inventory_json"), ckey, real_name)
		if(!row)
			return
		json = row[1]
		if(!json)
			return
		GLOB.persistence_inventory_cache[key] = json
		SSpersistence._centralCharacterSelfHealLocal("ss13_char_inventory",
			list("ckey", "char_name", "inventory_json"),
			list(ckey, real_name, json))

	var/list/inv = json_decode(json)
	if(!inv || !islist(inv))
		return

	for(var/slot_name in GLOB.persistence_inventory_slots)
		if(!(slot_name in inv))
			continue
		var/slot_id = GLOB.persistence_inventory_slots[slot_name]
		var/list/item_data = inv[slot_name]

		// A rig/voidsuit restored into an earlier slot may have deployed one of its
		// own parts into this one. Those belong to the suit, not to this slot, so
		// leave them be -- qdeling them here is precisely what used to strip a
		// restored voidsuit of its helmet, boots, tank and cooler.
		var/obj/item/existing = get_equipped_item(slot_id)
		if(existing && _persistence_item_is_suit_component(src, existing))
			continue

		// CONSTRUCT BEFORE DESTROYING. This proc used to qdel `existing` here, up
		// front, and only afterwards try to build the replacement -- so anything that
		// made deserializePersistentItem() return null (a typepath that no longer
		// exists, or a runtime unwinding it from any depth of the recursion) left the
		// slot permanently empty with the original already destroyed. On the back slot
		// that original is the player's hardsuit, and /obj/item/rig/Destroy() takes its
		// modules, cell, air tank and all four pieces down with it. A failed restore
		// has to degrade to "you keep what you had", never to "you have nothing".
		var/obj/item/restored = item_data ? deserializePersistentItem(item_data, src) : null

		if(item_data && !restored)
			log_subsystem_persistence_error("MobInventory: Failed to restore item in slot [slot_name] ([item_data["type"] || "unknown type"]) for [real_name] -- keeping existing [existing ? "[existing.type]" : "empty slot"].")
			continue

		// Only now that a replacement is in hand is it safe to drop the old item.
		if(existing)
			unEquip(existing, TRUE)
			qdel(existing)

		// Null entry means saved as empty; leave slot empty
		if(!restored)
			continue

		// equip_to_slot_if_possible(), not equip_to_slot_or_del(): a slot the item no
		// longer fits (species refit, changed slot_flags) must not cost the player the
		// item. Put it on the floor instead -- recoverable, unlike deletion. Argument
		// list is equip_to_slot_or_del()'s own (mob/inventory.dm:78) with delete_on_fail
		// flipped off, so nothing else about the equip behaviour changes.
		if(!equip_to_slot_if_possible(restored, slot_id, FALSE, TRUE, FALSE, TRUE, TRUE))
			restored.forceMove(get_turf(src))
			log_subsystem_persistence_error("MobInventory: Could not equip [restored.type] to slot [slot_name] for [real_name] -- dropped at their feet rather than deleted.")
			continue

		// equip_to_slot_if_possible() above is called with redraw_mob = FALSE (a batch-equip
		// optimization -- see the callers' own follow-up regenerate_icons()), so nothing composited
		// the mob yet. That's fine for state baked into the worn icon_state/mob_icon themselves, but
		// an item whose worn sprite is built from its OWN current contents (e.g. belt.dm's
		// content_overlays -- tools shown sticking out of a restored belt) needs a fresh, live redraw
		// AFTER the equip, not merely after the class-level defaults. update_worn_icon() is exactly
		// that: a cheap, item-driven "my visible state just changed" refresh, the same idiom every
		// other worn item in this codebase already uses (update_clothing_icon()).
		restored.update_worn_icon()

		// A voidsuit's equipped() immediately deploys its helmet/boots/tank/cooler
		// back out into head/shoes/s_store. Retract them so everything installed in
		// a suit comes back inside that suit, the way it would after taking the suit
		// off. Rigs need no equivalent -- /obj/item/rig has no equipped() override,
		// so a restored rig is already fully retracted.
		if(istype(restored, /obj/item/clothing/suit/space/void))
			_persistence_retract_voidsuit(src, restored)
		log_subsystem_persistence_info("MobInventory: Equipped [restored.type] in slot [slot_name] for [real_name].")

	// Strip any QDELETED items  prevents ghost items stuck in HUD slots
	for(var/slot_name in GLOB.persistence_inventory_slots)
		var/slot_id = GLOB.persistence_inventory_slots[slot_name]
		var/obj/item/equipped = get_equipped_item(slot_id)
		if(equipped && QDELETED(equipped))
			equipped.forceMove(get_turf(src))
			unEquip(equipped, TRUE)

	// Heal saves made before ID serialization carried account numbers:
	// re-link the worn ID to the restored bank account
	var/obj/item/card/id/ID = wear_id ? wear_id.GetID() : null
	if(istype(ID) && !ID.associated_account_number && mind?.initial_account)
		ID.associated_account_number = mind.initial_account.account_number
		log_subsystem_persistence_info("MobInventory: Relinked ID card to account #[ID.associated_account_number] for [real_name].")

	log_subsystem_persistence_info("MobInventory: Restored inventory for [real_name] ([ckey]).")

/// Trim or refill a magazine's stored rounds to exactly the given live
/// count, using the magazine's own ammo_type (Initialize preloads it full).
/proc/_persistence_set_magazine_rounds(obj/item/ammo_magazine/M, want)
	if(!istype(M))
		return
	want = clamp(want, 0, M.max_ammo)
	while(length(M.stored_ammo) > want)
		var/obj/item/ammo_casing/extra = M.stored_ammo[length(M.stored_ammo)]
		M.stored_ammo -= extra
		qdel(extra)
	while(length(M.stored_ammo) < want && M.ammo_type)
		M.stored_ammo += new M.ammo_type(M)
	M.update_icon()

/**
 * Recursively deserialize an item from a typepath + contents tree.
 * Creates the item in the holder's loc; fills storage contents recursively.
 * RETURN: the created item, or null on failure.
 */
/proc/deserializePersistentItem(list/data, atom/holder)
	CHECK_TICK
	if(!data || !islist(data))
		return null
	var/item_type = text2path(data["type"])
	if(!item_type || !ispath(item_type, /obj/item))
		return null

	var/obj/item/I = new item_type(holder)
	if(!I || QDELETED(I))
		return null

	// Visor/mask toggle state -- see persistent_toggle_vars' own doc comment
	// (obj/item base vars, items.dm). Restored before the other blocks below
	// purely for proximity to construction; order doesn't matter here since
	// nothing else reads these vars during restore.
	if(data["toggle_vars"])
		var/list/toggle_data = data["toggle_vars"]
		for(var/vname in toggle_data)
			I.vars[vname] = toggle_data[vname]

	// Storage contents. Keyed on PRESENCE, not truthiness -- a saved-empty
	// container serializes "contents" as an empty list, and that still has to
	// clear the fill() defaults below or the container restores stocked.
	if(("contents" in data) && istype(I, /obj/item/storage))
		var/obj/item/storage/S = I
		// Clear any default items the storage placed during Initialize before restoring saved contents
		while(length(S.contents))
			qdel(S.contents[1])
		for(var/list/child_data in data["contents"])
			var/obj/item/child = deserializePersistentItem(child_data, I)
			if(child)
				S.handle_item_insertion(child, TRUE)
		// handle_item_insertion() (storage.dm) never calls update_icon() on its
		// own -- harmless for storage whose sprite doesn't depend on contents,
		// but anything that renders its contents directly (e.g. yoke.dm's
		// per-can overlays) would otherwise stay stale until something
		// unrelated happened to trigger a redraw.
		S.update_icon()

	// Internal storage (suit pockets, webbing holds, helmet holds)
	if(data["internal_storage"])
		var/obj/item/storage/internal/IS = locate() in I
		if(IS)
			for(var/list/child_data in data["internal_storage"])
				var/obj/item/child = deserializePersistentItem(child_data, IS)
				if(child)
					IS.handle_item_insertion(child, TRUE)

	// Clothing accessories -- rebuild and attach through the real attach
	// proc so overlays/verbs/slowdown wire up like an attackby attach.
	if(data["accessories"] && istype(I, /obj/item/clothing))
		var/obj/item/clothing/C = I
		// Saved state is authoritative: strip the factory-default accessories
		// spawned at Initialize first, or every save/load cycle stacks another
		// copy of each default on top (plate carriers etc).
		if(LAZYLEN(C.accessories))
			for(var/obj/item/clothing/accessory/default_acc in C.accessories.Copy())
				C.remove_accessory(null, default_acc)
				qdel(default_acc)
		for(var/list/acc_data in data["accessories"])
			var/obj/item/clothing/accessory/A = deserializePersistentItem(acc_data, C)
			if(istype(A))
				C.attach_accessory(null, A)
			else if(A)
				// Saved entry wasn't an accessory type -- don't leave it in limbo
				qdel(A)

	// Holstered weapon
	if(data["holstered"] && istype(I, /obj/item/clothing/accessory/holster))
		var/obj/item/clothing/accessory/holster/HO = I
		if(!HO.holstered)
			var/obj/item/holstered_item = deserializePersistentItem(data["holstered"], HO)
			if(holstered_item)
				holstered_item.forceMove(HO)
				HO.holstered = holstered_item
				HO.update_name()

	// Boot knife
	if(data["boot_knife"] && istype(I, /obj/item/clothing/shoes))
		var/obj/item/clothing/shoes/SH = I
		if(!SH.holding)
			var/obj/item/knife_item = deserializePersistentItem(data["boot_knife"], SH)
			if(knife_item)
				SH.holding = knife_item
				SH.verbs |= /obj/item/clothing/shoes/proc/draw_knife
				SH.update_icon()

	// Hardsuit components -- replace Initialize()'s freshly auto-generated
	// defaults with whatever was actually saved. "in data" (key existence,
	// not just truthiness) distinguishes an old save made before this fix
	// existed (key absent -- leave Initialize()'s default alone) from a
	// component that was genuinely absent when saved (key present, value
	// null -- wipe it to match).
	if(istype(I, /obj/item/rig))
		var/obj/item/rig/R = I
		// _configure_rig_piece() (rig.dm) is what actually gives a piece its
		// correct sprite (borrows the rig's own icon -- a bare helmet/glove/
		// boot/chest type has no sprite of its own for this specific model).
		// New()'s own default pieces already go through it; a piece rebuilt
		// here via deserializePersistentItem()'s plain new() never does on
		// its own, which is what left a restored rig's components with a
		// missing/generic sprite after cryo-exit instead of matching the rig.
		if("rig_helmet" in data)
			if(R.helmet)
				qdel(R.helmet)
			R.helmet = data["rig_helmet"] ? deserializePersistentItem(data["rig_helmet"], R) : null
			R._configure_rig_piece(R.helmet)
		if("rig_chest" in data)
			if(R.chest)
				qdel(R.chest)
			R.chest = data["rig_chest"] ? deserializePersistentItem(data["rig_chest"], R) : null
			R._configure_rig_piece(R.chest)
		if("rig_gloves" in data)
			if(R.gloves)
				qdel(R.gloves)
			R.gloves = data["rig_gloves"] ? deserializePersistentItem(data["rig_gloves"], R) : null
			R._configure_rig_piece(R.gloves)
		if("rig_boots" in data)
			if(R.boots)
				qdel(R.boots)
			R.boots = data["rig_boots"] ? deserializePersistentItem(data["rig_boots"], R) : null
			R._configure_rig_piece(R.boots)
		// Everything past this point is wrapped. An uncaught throw here would unwind
		// the whole proc and return null to applyPersistentInventory(), costing the
		// player the entire hardsuit rather than one broken component. Same defensive
		// shape as the floor-item writer (persistence_floor_items.dm:339).
		if("rig_air" in data)
			try
				if(R.air_supply)
					qdel(R.air_supply)
				R.air_supply = data["rig_air"] ? deserializePersistentItem(data["rig_air"], R) : null
			catch(var/exception/air_ex)
				log_subsystem_persistence_error("MobInventory: rig air supply restore failed on [R.type]: [air_ex] -- suit kept, tank lost.")
		// Must stay ahead of the device_cell_charge block further down: that block
		// reads I.get_cell(), which for a rig returns this very var, and re-clamps
		// the saved charge onto whatever cell is installed by then.
		if("rig_cell" in data)
			try
				if(R.cell)
					qdel(R.cell)
				R.cell = data["rig_cell"] ? deserializePersistentItem(data["rig_cell"], R) : null
			catch(var/exception/cell_ex)
				log_subsystem_persistence_error("MobInventory: rig cell restore failed on [R.type]: [cell_ex] -- suit kept, cell lost.")
		if("rig_modules" in data)
			// Tear down the initial_modules loadout Initialize() just spawned --
			// saved state is authoritative, or removed modules come back from the
			// dead every restore. Iterate a copy: /obj/item/rig_module/Destroy()
			// already splices itself out of holder.installed_modules.
			for(var/obj/item/rig_module/old_module in R.installed_modules.Copy())
				R.installed_modules -= old_module
				qdel(old_module)
			R.installed_modules = list()
			R.selected_module = null
			R.visor = null
			R.speech = null
			if(islist(data["rig_modules"]))
				for(var/list/mod_entry in data["rig_modules"])
					// Per-entry, so one bad module costs that module only.
					try
						var/obj/item/restored_module = deserializePersistentItem(mod_entry, R)
						if(!istype(restored_module, /obj/item/rig_module))
							// Saved entry wasn't a module type -- don't leave it rattling
							// around loose inside the suit.
							if(restored_module)
								qdel(restored_module)
							continue
						var/obj/item/rig_module/RM = restored_module
						R.installed_modules += RM
						// installed() is what re-points holder.visor / holder.speech at
						// their modules, so go through it rather than setting holder by hand.
						RM.installed(R)
						if(mod_entry["rig_module_selected"])
							R.selected_module = RM
					catch(var/exception/mod_ex)
						log_subsystem_persistence_error("MobInventory: rig module restore failed on [R.type] for [mod_entry["type"] || "unknown type"]: [mod_ex] -- suit kept, module skipped.")
			try
				R.update_icon()
			catch(var/exception/icon_ex)
				log_subsystem_persistence_error("MobInventory: rig update_icon() failed on [R.type]: [icon_ex]")

	// Void-suit inbuilt components -- "in data" (key existence, not just
	// truthiness) distinguishes an old save made before this fix existed
	// (key absent -- leave whatever's already there, i.e. null, alone) from
	// a component that was genuinely absent when saved (key present, value
	// null -- wipe it to match). Mirrors the rig restore block above.
	if(istype(I, /obj/item/clothing/suit/space/void))
		var/obj/item/clothing/suit/space/void/V = I
		if("void_helmet" in data)
			if(V.helmet)
				qdel(V.helmet)
			V.helmet = data["void_helmet"] ? deserializePersistentItem(data["void_helmet"], V) : null
		if("void_boots" in data)
			if(V.boots)
				qdel(V.boots)
			V.boots = data["void_boots"] ? deserializePersistentItem(data["void_boots"], V) : null
		if("void_tank" in data)
			if(V.tank)
				qdel(V.tank)
			V.tank = data["void_tank"] ? deserializePersistentItem(data["void_tank"], V) : null
		if("void_cooler" in data)
			if(V.cooler)
				qdel(V.cooler)
			V.cooler = data["void_cooler"] ? deserializePersistentItem(data["void_cooler"], V) : null

	// Power cell charge (Initialize refilled it to max)
	if(!isnull(data["cell_charge"]) && istype(I, /obj/item/cell))
		var/obj/item/cell/PC = I
		PC.charge = clamp(text2num("[data["cell_charge"]]"), 0, PC.maxcharge)
	else if(!isnull(data["device_cell_charge"]))
		var/obj/item/cell/HC = I.get_cell()
		if(istype(HC))
			HC.charge = clamp(text2num("[data["device_cell_charge"]]"), 0, HC.maxcharge)

	// Ballistic gun state -- clear the Initialize preload, rebuild to the
	// saved counts using the gun/magazine's own casing types
	if(istype(I, /obj/item/gun/projectile) && (!isnull(data["gun_loaded"]) || !isnull(data["gun_chambered"]) || data["gun_mag"]))
		var/obj/item/gun/projectile/G = I
		for(var/obj/item/ammo_casing/OC in G.loaded)
			G.loaded -= OC
			qdel(OC)
		if(G.chambered)
			qdel(G.chambered)
			G.chambered = null
		if(G.ammo_magazine)
			qdel(G.ammo_magazine)
			G.ammo_magazine = null
		var/load_n = text2num("[data["gun_loaded"]]") || 0
		if(G.ammo_type)
			for(var/j = 1 to min(load_n, G.max_shells))
				G.loaded += new G.ammo_type(G)
		if(islist(data["gun_mag"]))
			var/list/mag_data = data["gun_mag"]
			var/mag_path = text2path(mag_data["type"])
			if(mag_path && ispath(mag_path, /obj/item/ammo_magazine))
				var/obj/item/ammo_magazine/GM = new mag_path(G)
				_persistence_set_magazine_rounds(GM, text2num("[mag_data["live"]]") || 0)
				G.ammo_magazine = GM
		if(text2num("[data["gun_chambered"]]"))
			var/chamber_type = G.ammo_type || G.ammo_magazine?.ammo_type
			if(chamber_type)
				G.chambered = new chamber_type(G)
		G.update_icon()

	// Standalone magazine round count
	if(!isnull(data["mag_live"]) && istype(I, /obj/item/ammo_magazine))
		var/obj/item/ammo_magazine/M = I
		_persistence_set_magazine_rounds(M, text2num("[data["mag_live"]]") || 0)

	// Spent casing
	if(data["casing_spent"] && istype(I, /obj/item/ammo_casing))
		var/obj/item/ammo_casing/AC = I
		if(AC.BB)
			AC.expend()

	// RFD matter (starts full; initial() is the documented maximum)
	if(!isnull(data["rfd_matter"]) && istype(I, /obj/item/rfd))
		var/obj/item/rfd/R = I
		R.stored_matter = clamp(text2num("[data["rfd_matter"]]"), 0, initial(R.stored_matter))
		R.update_icon()

	// Reagents
	if(data["reagents"] && I.reagents)
		I.reagents.clear_reagents()
		var/list/reagents = json_decode(data["reagents"])
		if(islist(reagents))
			for(var/rtype_str in reagents)
				var/rtype = text2path(rtype_str)
				if(rtype)
					I.reagents.add_reagent(rtype, text2num(reagents[rtype_str]))

	// Paper text
	if(data["paper_info"] && istype(I, /obj/item/paper))
		var/obj/item/paper/P = I
		P.info = data["paper_info"]

	// ID cards -- restore registered name, assignment, access, bank account, revoked state
	if(data["id_content"] && istype(I, /obj/item/card/id))
		var/obj/item/card/id/ID = I
		ID.persistent_objects_apply_content(data["id_content"], null, null, null)
	else if(data["obj_content"])
		I.persistent_objects_apply_content(data["obj_content"], null, null, null)

	// Stack amount
	if(!isnull(data["stack_amount"]) && istype(I, /obj/item/stack))
		var/obj/item/stack/ST = I
		ST.amount = text2num(data["stack_amount"]) || ST.amount
		ST.update_icon()

	// Gas tank contents/settings -- overwrites the full default fill
	// Initialize()'s adjust_initial_gas() just applied. See the matching
	// serialize block for why each field matters.
	if(istype(I, /obj/item/tank))
		var/obj/item/tank/TK = I
		if(!isnull(data["tank_distribute_pressure"]))
			TK.distribute_pressure = data["tank_distribute_pressure"] + 0
		if(data["tank_manipulated_by"])
			TK.manipulated_by = data["tank_manipulated_by"]
		if(TK.air_contents && data["tank_air_gas"])
			var/list/tank_gases = json_decode(data["tank_air_gas"])
			if(islist(tank_gases))
				TK.air_contents.gas = tank_gases
			if(!isnull(data["tank_air_temperature"]))
				TK.air_contents.temperature = data["tank_air_temperature"] + 0
			TK.air_contents.update_values()
		// Same refresh the tank's own Initialize() ends on -- without it the
		// gauge sprite keeps showing the pre-overwrite full reading.
		TK.update_gauge()

	// Fingerprints/forensics
	if(data["fingerprints"])
		var/list/fp = json_decode(data["fingerprints"])
		if(islist(fp)) I.fingerprints = fp
	if(data["fingerprintshidden"]) I.fingerprintshidden = data["fingerprintshidden"]
	if(data["fingerprintslast"])   I.fingerprintslast   = data["fingerprintslast"]
	if(data["suit_fibers"])        I.suit_fibers        = data["suit_fibers"]

	return I
