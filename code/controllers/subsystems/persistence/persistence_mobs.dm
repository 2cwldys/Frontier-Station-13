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
	if(!GLOB.config.sql_enabled || !length(GLOB.persistence_health_cache))
		return
	if(!ckey || !real_name)
		return

	var/key = "[ckey]|[real_name]"
	var/list/entry = GLOB.persistence_health_cache[key]
	if(!entry)
		return

	// Apply organ state: damage, robolimb, augments
	if(entry["organ_damage_json"])
		var/list/organ_data = json_decode(entry["organ_damage_json"])
		if(organ_data && islist(organ_data))
			for(var/limb_name in organ_data)
				var/obj/item/organ/external/O = organs_by_name[limb_name]
				if(!O)
					continue
				var/list/limb = organ_data[limb_name]
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

/mob/living/carbon/human/proc/applyPersistentIdentity()
	if(!GLOB.config.sql_enabled || !islist(GLOB.persistence_identity_cache))
		return
	if(!ckey || !real_name)
		return

	var/key = "[ckey]|[real_name]"
	var/list/entry = GLOB.persistence_identity_cache[key]
	if(!entry)
		return

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
	"r_store"   = slot_r_store
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
		"SELECT ckey, char_name, x, y, z, char_state, in_lace, lace_pod_x, lace_pod_y, lace_pod_z, last_pod_x, last_pod_y, last_pod_z FROM ss13_mob_position",
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
			"x"           = text2num(query.item[3]),
			"y"           = text2num(query.item[4]),
			"z"           = text2num(query.item[5]),
			"char_state"  = query.item[6] || "alive",
			"in_lace"     = text2num(query.item[7]),
			"lace_pod_x"  = text2num(query.item[8]),
			"lace_pod_y"  = text2num(query.item[9]),
			"lace_pod_z"  = text2num(query.item[10]),
			"last_pod_x"  = text2num(query.item[11]),
			"last_pod_y"  = text2num(query.item[12]),
			"last_pod_z"  = text2num(query.item[13])
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
	// Also clear from in-memory caches so the character stops appearing in selection
	var/key = "[ckey]|[char_name]"
	GLOB.persistence_health_cache    -= key
	GLOB.persistence_inventory_cache -= key
	GLOB.persistence_identity_cache  -= key
	GLOB.persistence_position_cache  -= key
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
		_persistentSpawnDefault()
		return

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
	for(var/obj/item/organ/external/O in H.organs)
		if(!O.limb_name)
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
		organ_damage[O.limb_name] = limb

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

// ============================================================
// VITALS ADMIN VERB
// ============================================================

/datum/admins/proc/check_vitals()
	set name = "Check Vitals"
	set category = "Persistence"

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
		inv[slot_name] = I ? serializePersistentItem(I) : null

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

/**
 * Recursively serialize an item as a typepath + contents tree.
 * Only saves typepath; per-item internal state is out of scope for v1.
 * RETURN: list with "type" key and optional "contents" list for storage items.
 */
/proc/serializePersistentItem(obj/item/I)
	if(!I)
		return null
	var/list/data = list("type" = "[I.type]")

	// Storage contents  recursive
	if(istype(I, /obj/item/storage))
		var/obj/item/storage/S = I
		var/list/contents = list()
		for(var/obj/item/child in S.contents)
			var/list/child_data = serializePersistentItem(child)
			if(child_data)
				contents += list(child_data)
		if(length(contents))
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
	// silently discards whatever the player actually had attached. The
	// rig's own cell is handled by the generic get_cell() branch below --
	// /obj/item/rig/get_cell() already returns its `cell` var directly.
	if(istype(I, /obj/item/rig))
		var/obj/item/rig/R = I
		data["rig_helmet"] = serializePersistentItem(R.helmet)
		data["rig_chest"]  = serializePersistentItem(R.chest)
		data["rig_gloves"] = serializePersistentItem(R.gloves)
		data["rig_boots"]  = serializePersistentItem(R.boots)

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
	if(!GLOB.config.sql_enabled || !length(GLOB.persistence_inventory_cache))
		return
	if(!ckey || !real_name)
		return

	var/key = "[ckey]|[real_name]"
	var/json = GLOB.persistence_inventory_cache[key]
	if(!json)
		return

	var/list/inv = json_decode(json)
	if(!inv || !islist(inv))
		return

	for(var/slot_name in GLOB.persistence_inventory_slots)
		if(!(slot_name in inv))
			continue
		var/slot_id = GLOB.persistence_inventory_slots[slot_name]
		var/list/item_data = inv[slot_name]

		// Qdel whatever is currently in this slot -- saved state is authoritative for persistent world
		var/obj/item/existing = get_equipped_item(slot_id)
		if(existing)
			qdel(existing)

		// Null entry means saved as empty; leave slot empty
		if(!item_data)
			continue

		// Create and equip saved item
		var/obj/item/restored = deserializePersistentItem(item_data, src)
		if(restored)
			equip_to_slot_or_del(restored, slot_id)
			log_subsystem_persistence_info("MobInventory: Equipped [restored.type] in slot [slot_name] for [real_name].")
		else
			log_subsystem_persistence_error("MobInventory: Failed to restore item in slot [slot_name] ([item_data["type"] || "unknown type"]) for [real_name].")

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

	// Storage contents
	if(data["contents"] && istype(I, /obj/item/storage))
		var/obj/item/storage/S = I
		// Clear any default items the storage placed during Initialize before restoring saved contents
		while(length(S.contents))
			qdel(S.contents[1])
		for(var/list/child_data in data["contents"])
			var/obj/item/child = deserializePersistentItem(child_data, I)
			if(child)
				S.handle_item_insertion(child, TRUE)

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
		if("rig_helmet" in data)
			if(R.helmet)
				qdel(R.helmet)
			R.helmet = data["rig_helmet"] ? deserializePersistentItem(data["rig_helmet"], R) : null
		if("rig_chest" in data)
			if(R.chest)
				qdel(R.chest)
			R.chest = data["rig_chest"] ? deserializePersistentItem(data["rig_chest"], R) : null
		if("rig_gloves" in data)
			if(R.gloves)
				qdel(R.gloves)
			R.gloves = data["rig_gloves"] ? deserializePersistentItem(data["rig_gloves"], R) : null
		if("rig_boots" in data)
			if(R.boots)
				qdel(R.boots)
			R.boots = data["rig_boots"] ? deserializePersistentItem(data["rig_boots"], R) : null

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

	// Fingerprints/forensics
	if(data["fingerprints"])
		var/list/fp = json_decode(data["fingerprints"])
		if(islist(fp)) I.fingerprints = fp
	if(data["fingerprintshidden"]) I.fingerprintshidden = data["fingerprintshidden"]
	if(data["fingerprintslast"])   I.fingerprintslast   = data["fingerprintslast"]
	if(data["suit_fibers"])        I.suit_fibers        = data["suit_fibers"]

	return I
