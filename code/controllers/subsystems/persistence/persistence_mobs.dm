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

	var/saved = 0
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.ckey || !H.real_name)
			continue
		if(!H.z)
			continue

		// Serialize organ state: limb_name => {brute, burn, robotic, model, augments}
		var/list/organ_damage = list()
		for(var/obj/item/organ/external/O in H.organs)
			if(!O.limb_name)
				continue
			var/list/augments = list()
			for(var/obj/item/organ/A in O.internal_organs)
				if(!A.is_augment)
					continue
				if(istype(A, /obj/item/organ/internal/neural_lace))
					var/obj/item/organ/internal/neural_lace/lace = A
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

		var/datum/db_query/insert = SSdbcore.NewQuery(
			{"INSERT INTO ss13_char_health (ckey, char_name, organ_damage_json, stamina, bodytemperature, on_fire, fire_stacks, nutrition, hydration, saved_at)
			VALUES (:ckey, :char_name, :organ_damage_json, :stamina, :bodytemperature, :on_fire, :fire_stacks, :nutrition, :hydration, NOW())
			ON DUPLICATE KEY UPDATE organ_damage_json = VALUES(organ_damage_json), stamina = VALUES(stamina),
			bodytemperature = VALUES(bodytemperature), on_fire = VALUES(on_fire), fire_stacks = VALUES(fire_stacks),
			nutrition = VALUES(nutrition), hydration = VALUES(hydration), saved_at = NOW()"},
			list(
				"ckey"             = H.ckey,
				"char_name"        = H.real_name,
				"organ_damage_json"= length(organ_damage) ? json_encode(organ_damage) : null,
				"stamina"          = H.stamina,
				"bodytemperature"  = H.bodytemperature,
				"on_fire"          = H.on_fire ? 1 : 0,
				"fire_stacks"      = H.fire_stacks,
				"nutrition"        = H.nutrition,
				"hydration"        = H.hydration
			)
		)
		insert.Execute()
		databaseCheckQueryResult(insert, "mobsHealthFinalize insert")
		qdel(insert)
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
								// new path(loc, mapload, internal)  internal=TRUE hooks the augment into
								// parent_organ/internal_organs/internal_organs_by_name automatically (organ.dm)
								var/obj/item/organ/new_aug = new aug_path(src, FALSE, TRUE)
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
	var/language_json = length(H.languages)   ? json_encode(H.languages)   : null

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
		var/list/langs = json_decode(entry["languages_json"])
		if(langs && islist(langs))
			languages = langs

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

	var/saved = 0
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(!H.ckey || !H.real_name)
			continue
		if(!H.z)
			continue

		var/list/inv = list()
		for(var/slot_name in GLOB.persistence_inventory_slots)
			var/slot_id = GLOB.persistence_inventory_slots[slot_name]
			var/obj/item/I = H.get_equipped_item(slot_id)
			inv[slot_name] = I ? serializePersistentItem(I) : null

		var/datum/db_query/insert = SSdbcore.NewQuery(
			{"INSERT INTO ss13_char_inventory (ckey, char_name, inventory_json, saved_at)
			VALUES (:ckey, :char_name, :inventory_json, NOW())
			ON DUPLICATE KEY UPDATE inventory_json = VALUES(inventory_json), saved_at = NOW()"},
			list(
				"ckey"           = H.ckey,
				"char_name"      = H.real_name,
				"inventory_json" = json_encode(inv)
			)
		)
		insert.Execute()
		databaseCheckQueryResult(insert, "mobsInventoryFinalize insert")
		qdel(insert)
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
		"SELECT ckey, char_name, x, y, z FROM ss13_mob_position",
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
			"x" = text2num(query.item[3]),
			"y" = text2num(query.item[4]),
			"z" = text2num(query.item[5])
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

	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_mob_position (ckey, char_name, x, y, z)
		VALUES (:ckey, :char_name, :x, :y, :z)
		ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z), saved_at = NOW()"},
		list("ckey" = H.ckey, "char_name" = H.real_name, "x" = H.x, "y" = H.y, "z" = H.z)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "mobPositionSave")
	qdel(ins)

	// Update cache
	var/key = "[H.ckey]|[H.real_name]"
	GLOB.persistence_position_cache[key] = list("x" = H.x, "y" = H.y, "z" = H.z)

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
	for(var/obj/item/organ/external/O in H.organs)
		if(!O.limb_name)
			continue
		var/list/augments = list()
		for(var/obj/item/organ/A in O.internal_organs)
			if(!A.is_augment)
				continue
			if(istype(A, /obj/item/organ/internal/neural_lace))
				var/obj/item/organ/internal/neural_lace/lace = A
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

	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_health (ckey, char_name, organ_damage_json, stamina, bodytemperature, on_fire, fire_stacks, saved_at)
		VALUES (:ckey, :char_name, :organ_damage_json, :stamina, :bodytemperature, :on_fire, :fire_stacks, NOW())
		ON DUPLICATE KEY UPDATE organ_damage_json = VALUES(organ_damage_json), stamina = VALUES(stamina),
		bodytemperature = VALUES(bodytemperature), on_fire = VALUES(on_fire), fire_stacks = VALUES(fire_stacks), saved_at = NOW()"},
		list(
			"ckey"              = H.ckey,
			"char_name"         = H.real_name,
			"organ_damage_json" = length(organ_damage) ? json_encode(organ_damage) : null,
			"stamina"           = H.stamina,
			"bodytemperature"   = H.bodytemperature,
			"on_fire"           = H.on_fire ? 1 : 0,
			"fire_stacks"       = H.fire_stacks
		)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "mobsHealthSaveOne")
	qdel(ins)

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

	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_char_inventory (ckey, char_name, inventory_json, saved_at)
		VALUES (:ckey, :char_name, :inventory_json, NOW())
		ON DUPLICATE KEY UPDATE inventory_json = VALUES(inventory_json), saved_at = NOW()"},
		list(
			"ckey"           = H.ckey,
			"char_name"      = H.real_name,
			"inventory_json" = json_encode(inv)
		)
	)
	ins.Execute()
	databaseCheckQueryResult(ins, "mobsInventorySaveOne")
	qdel(ins)

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

/**
 * Recursively deserialize an item from a typepath + contents tree.
 * Creates the item in the holder's loc; fills storage contents recursively.
 * RETURN: the created item, or null on failure.
 */
/proc/deserializePersistentItem(list/data, atom/holder)
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
