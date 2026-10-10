/*
 * Persistence - Cyborg Chassis
 *
 * Cyborgs (/mob/living/silicon/robot) had zero persistence before this --
 * a chassis was a fresh shell every round, confirmed by a full sweep of
 * this subsystem finding no reference to /mob/living/silicon/robot
 * anywhere. Synthetic Storage (synthetic_storage.dm) is the cyborg
 * counterpart to a cryopod: store a piloted cyborg, get an equivalent one
 * back later.
 *
 * Keyed by ckey ALONE, not (ckey, char_name) like every other ss13_char_*
 * table -- robots aren't chargen characters with a saved-slot roster the
 * way humans are, so there's no "which cyborg character" to disambiguate.
 * One stored cyborg slot per player.
 *
 * Deliberately NOT a byte-for-byte chassis snapshot. Saved: current/max
 * health (cyborgs use one simple pool -- getBruteLoss()/getFireLoss()
 * both resolve through it, living.dm, no per-part damage model to persist),
 * name/cosmetic sprite choices, module TYPE, law preset, cell type + charge,
 * and the toggle vars a player actually set (lights, sight mode, flash
 * resistance, overclock, crisis flags, access-scramble/emag/lock state).
 * NOT saved:
 * the module's own mutable contents (specific tool substitutions, matter
 * synth consumable charge -- restoring resets these to the module's default
 * loadout), any custom law edit beyond the preset type, and everything
 * already established as transient/derived elsewhere in this codebase's own
 * convention (wires/wires_exposed, in-flight timers, overlay/image caches,
 * connected_ai -- re-link, don't restore a stale reference).
 *
 * Shape mirrors ss13_char_skills' round trip (persistence_skills.dm) --
 * cache, boot load, save-with-central-writethrough, resolve-with-central-
 * readthrough-and-self-heal. Central sync gated behind
 * CENTRAL_SYNC_CHARACTERS by the shared helpers, so with central off none
 * of it runs.
 */

/// Cached cyborg rows, keyed by ckey -> cyborg_json string.
GLOBAL_LIST_EMPTY(persistence_cyborg_cache)

/**
 * Load every saved cyborg row into the cache. Called from
 * SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/charCyborgInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_cyborg_cache = list()

	if(!databaseCheckConnection("charCyborgInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, cyborg_json FROM ss13_char_cyborg",
		list()
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "charCyborgInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		GLOB.persistence_cyborg_cache[query.item[1]] = query.item[2]
		loaded++
	qdel(query)
	log_subsystem_persistence_info("CharCyborg: Loaded [loaded] stored cyborg entries.")

/// Builds the JSON-safe field list described in this file's doc comment.
/datum/controller/subsystem/persistence/proc/_cyborgSnapshot(mob/living/silicon/robot/R)
	return list(
		"health" = R.health,
		"maxhealth" = R.maxhealth,
		"real_name" = R.real_name,
		"custom_name" = R.custom_name,
		"custom_sprite" = R.custom_sprite,
		"icontype" = R.icontype,
		"chassistype" = R.chassistype,
		"paneltype" = R.paneltype,
		"eyetype" = R.eyetype,
		"icon_selected" = R.icon_selected,
		"mod_type" = R.mod_type,
		"law_preset" = "[R.law_preset]",
		"law_update" = R.law_update,
		"cell_type" = R.cell ? "[R.cell.type]" : "[R.cell_type]",
		"cell_charge" = R.cell ? R.cell.charge : 0,
		"has_jetpack" = R.has_jetpack,
		"has_pda" = R.has_pda,
		"lights_on" = R.lights_on,
		"intense_light" = R.intense_light,
		"sight_mode" = R.sight_mode,
		"flash_resistant" = R.flash_resistant,
		"overclocked" = R.overclocked,
		"overclock_available" = R.overclock_available,
		"crisis" = R.crisis,
		"crisis_override" = R.crisis_override,
		"malf_AI_module" = R.malf_AI_module,
		"req_access" = R.req_access ? R.req_access.Copy() : list(),
		"key_type" = R.key_type ? "[R.key_type]" : null,
		"scrambled_codes" = R.scrambled_codes,
		"emagged" = R.emagged,
		"fake_emagged" = R.fake_emagged,
		"locked" = R.locked,
	)

/**
 * Saves one player's cyborg. Called from Synthetic Storage on successful
 * entry (synthetic_storage.dm), which passes its own turf as storage_turf --
 * mirrors persistence_set_last_pod()'s "remember which pod they stored at so
 * they wake from the same one" (persistence_mobs.dm), just as its own
 * columns on this table instead of ss13_mob_position (a cyborg has no row
 * there at all).
 */
/datum/controller/subsystem/persistence/proc/charCyborgSaveOne(mob/living/silicon/robot/R, turf/storage_turf)
	if(!istype(R) || !R.ckey)
		return FALSE
	if(!databaseCheckConnection("charCyborgSaveOne"))
		return FALSE

	var/cyborg_json = json_encode(_cyborgSnapshot(R))
	var/last_x = storage_turf ? storage_turf.x : null
	var/last_y = storage_turf ? storage_turf.y : null
	var/last_z = storage_turf ? storage_turf.z : null

	_characterRowUpsert(SSdbcore, "ss13_char_cyborg",
		list("ckey", "cyborg_json", "last_x", "last_y", "last_z"),
		list(R.ckey, cyborg_json, last_x, last_y, last_z), "charCyborgSaveOne")
	GLOB.persistence_cyborg_cache[R.ckey] = cyborg_json

	if(_centralCharacterSyncActive())
		_characterRowUpsert(SScentraldb, "ss13_char_cyborg",
			list("ckey", "cyborg_json", "last_x", "last_y", "last_z"),
			list(R.ckey, cyborg_json, last_x, last_y, last_z), "charCyborgSaveOne central")

	return TRUE

/**
 * Reads back the last-used Synthetic Storage location for ckey (local DB
 * only -- this is spawn-routing convenience, not something worth a central
 * round-trip on a cache miss the way the state blob itself gets). Returns
 * list("x"=,"y"=,"z"=) or null.
 */
/datum/controller/subsystem/persistence/proc/charCyborgGetLastLocation(ckey)
	if(!ckey || !databaseCheckConnection("charCyborgGetLastLocation"))
		return null
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT last_x, last_y, last_z FROM ss13_char_cyborg WHERE ckey = :ckey",
		list("ckey" = ckey)
	)
	q.Execute()
	var/list/result = null
	if(databaseCheckQueryResult(q, "charCyborgGetLastLocation") && q.NextRow())
		if(!isnull(q.item[1]) && !isnull(q.item[2]) && !isnull(q.item[3]))
			result = list("x" = text2num(q.item[1]), "y" = text2num(q.item[2]), "z" = text2num(q.item[3]))
	qdel(q)
	return result

/**
 * Resolves a saved cyborg snapshot for ckey -- cache first, then a central
 * read-through + local self-heal on a miss. Returns the decoded snapshot
 * list, or null if nothing is found anywhere (never stored one, or already
 * retrieved -- charCyborgDelete() below).
 */
/datum/controller/subsystem/persistence/proc/charCyborgResolve(ckey)
	if(!ckey)
		return null

	var/cyborg_json = GLOB.persistence_cyborg_cache[ckey]

	// No (ckey, char_name)-shaped table here, so this can't reuse
	// _centralCharacterReadThrough() (it hardcodes a char_name column) --
	// same query by hand, everything after the SELECT reuses the shared
	// self-heal helper.
	if(isnull(cyborg_json) && _centralCharacterSyncActive())
		var/datum/db_query/q = SScentraldb.NewQuery(
			"SELECT cyborg_json FROM ss13_char_cyborg WHERE ckey = :ckey",
			list("ckey" = ckey)
		)
		q.Execute()
		if(databaseCheckQueryResult(q, "charCyborgResolve central") && q.NextRow())
			cyborg_json = q.item[1]
		qdel(q)
		if(!isnull(cyborg_json))
			GLOB.persistence_cyborg_cache[ckey] = cyborg_json
			_centralCharacterSelfHealLocal("ss13_char_cyborg", list("ckey", "cyborg_json"), list(ckey, cyborg_json))

	if(isnull(cyborg_json))
		return null

	var/list/decoded
	try
		decoded = json_decode(cyborg_json)
	catch(var/exception/decode_e)
		log_subsystem_persistence_error("CharCyborg: could not decode cyborg data for [ckey]: [decode_e]")
		return null
	if(!islist(decoded) || !length(decoded))
		return null
	return decoded

/// Deletes a player's stored cyborg row -- called once a stored cyborg is
/// successfully retrieved, so it can't be retrieved a second time.
/datum/controller/subsystem/persistence/proc/charCyborgDelete(ckey)
	if(!ckey)
		return
	GLOB.persistence_cyborg_cache -= ckey
	if(databaseCheckConnection("charCyborgDelete"))
		var/datum/db_query/query = SSdbcore.NewQuery(
			"DELETE FROM ss13_char_cyborg WHERE ckey = :ckey",
			list("ckey" = ckey)
		)
		query.Execute()
		databaseCheckQueryResult(query, "charCyborgDelete")
		qdel(query)
	if(_centralCharacterSyncActive())
		var/datum/db_query/central_q = SScentraldb.NewQuery(
			"DELETE FROM ss13_char_cyborg WHERE ckey = :ckey",
			list("ckey" = ckey)
		)
		central_q.Execute()
		databaseCheckQueryResult(central_q, "charCyborgDelete central")
		qdel(central_q)

/**
 * Reconstructs a robot mob from a saved snapshot at spawn_turf, attaching
 * ckey immediately. Builds a bog-standard robot via normal construction
 * first -- Initialize()/init() (robot.dm) already correctly wire up cell/
 * camera/radio/hud/a default law set -- then applies the saved overrides via
 * the same real procs the game already uses for live changes: module
 * assignment mirrors pick_module()'s own post-selection sequence (robot.dm)
 * instead of its interactive prompt, and the laws swap mirrors init()'s own
 * "laws = new law_preset()" line. Returns the new robot, or null if
 * construction failed.
 */
/datum/controller/subsystem/persistence/proc/charCyborgRestore(ckey, turf/spawn_turf, list/snapshot)
	if(!ckey || !spawn_turf || !islist(snapshot))
		return null

	var/mob/living/silicon/robot/R = new(spawn_turf)
	if(QDELETED(R))
		return null

	if(snapshot["maxhealth"])
		R.maxhealth = snapshot["maxhealth"]
	if(!isnull(snapshot["health"]))
		R.health = clamp(snapshot["health"], 0, R.maxhealth)

	if(snapshot["real_name"])
		R.real_name = snapshot["real_name"]
		R.name = snapshot["real_name"]
	R.custom_name = snapshot["custom_name"] || ""
	R.custom_sprite = !!snapshot["custom_sprite"]
	R.icontype = snapshot["icontype"]
	R.chassistype = snapshot["chassistype"]
	R.paneltype = snapshot["paneltype"]
	R.eyetype = snapshot["eyetype"]
	R.icon_selected = !!snapshot["icon_selected"]

	var/law_preset_path = text2path(snapshot["law_preset"])
	if(law_preset_path)
		R.law_preset = law_preset_path
		R.laws = new law_preset_path()
	R.law_update = !!snapshot["law_update"]

	var/cell_path = text2path(snapshot["cell_type"])
	if(cell_path && ispath(cell_path, /obj/item/cell))
		QDEL_NULL(R.cell)
		R.cell = new cell_path(R)
		R.cell.charge = min(snapshot["cell_charge"] || 0, R.cell.maxcharge)

	R.has_jetpack = !!snapshot["has_jetpack"]
	R.has_pda = !!snapshot["has_pda"]
	R.lights_on = !!snapshot["lights_on"]
	R.intense_light = !!snapshot["intense_light"]
	R.sight_mode = snapshot["sight_mode"] || NO_HUD
	R.flash_resistant = !!snapshot["flash_resistant"]
	R.overclocked = !!snapshot["overclocked"]
	R.overclock_available = !!snapshot["overclock_available"]
	R.crisis = !!snapshot["crisis"]
	R.crisis_override = !!snapshot["crisis_override"]
	R.malf_AI_module = !!snapshot["malf_AI_module"]
	if(islist(snapshot["req_access"]))
		R.req_access = snapshot["req_access"].Copy()
	R.key_type = snapshot["key_type"] ? text2path(snapshot["key_type"]) : null
	R.scrambled_codes = !!snapshot["scrambled_codes"]
	R.emagged = !!snapshot["emagged"]
	R.fake_emagged = !!snapshot["fake_emagged"]
	R.locked = !!snapshot["locked"]

	// Module: mirrors pick_module()'s own post-selection sequence (robot.dm)
	// rather than its interactive prompt -- same real assignment, just
	// scripted instead of chosen live. Module CONTENTS reset to that
	// module's default loadout -- see this file's doc comment.
	var/saved_mod_type = snapshot["mod_type"]
	if(saved_mod_type && saved_mod_type != "Default" && (saved_mod_type in GLOB.robot_modules))
		var/module_type = GLOB.robot_modules[saved_mod_type]
		if(module_type)
			R.mod_type = saved_mod_type
			new module_type(R, R)
			if(R.hands)
				R.hands.icon_state = lowertext(saved_mod_type)
			R.updatename()
			R.recalculate_synth_capacities()

	R.regenerate_icons()
	R.update_access()
	// Deliberately does NOT attach ckey to R itself -- the two callers need
	// different attachment mechanics (a fresh lobby mob's key can be assigned
	// directly, same as create_character() already does; a live mob mid-round
	// has to go through mind.transfer_to() instead), so each one does its own
	// attachment right after this returns. See PersistentAutoSpawnCyborg()
	// (new_player.dm) and synthetic_storage.dm's retrieve_cyborg().

	return R

// ============================================================
// SPAWN-LOCATION CASCADE
// ============================================================
//
// Mirrors the cryopod cascade (persistence_find_saved_cryopod()/
// persistence_find_available_cryopod()/persistence_collect_available_cryopods()/
// persistence_prompt_cryopod_choice(), persistence_cryo.dm) precisely, just
// walking /obj/structure/machinery/recharge_station/synthetic_storage instead of cryopods,
// including the Crew tier (drydock ship crew). Keyed by ckey alone, no
// char_name -- see _drydock_crew_check_ckey() below for how that tier
// adapts to the ckey-only shape. Used by
// /mob/abstract/new_player/proc/PersistentAutoSpawnCyborg() (new_player.dm).

/// Ckey-only variant of _drydock_crew_check_identity()
/// (telepad_drydock_boarding.dm) -- that one matches on the composite
/// "ckey|char_name" crew_ckeys shape, which a cyborg has no char_name to
/// supply for. Crew membership is a per-ckey concept in spirit; the
/// composite key is just how it's normally stored for humans. Matches if
/// ckey owns the ship, or appears as the ckey-half of any crew_ckeys entry.
/proc/_drydock_crew_check_ckey(ckey, z)
	var/datum/drydock_ship/DS = _drydock_ship_at(z)
	if(!DS)
		return FALSE
	if(DS.owner_ckey == ckey)
		return TRUE
	for(var/entry in DS.crew_ckeys)
		var/list/parts = splittext(entry, "|")
		if(length(parts) && parts[1] == ckey)
			return TRUE
	return FALSE

/// Try the exact unit this ckey (cyborg) or ckey+char_name (IPC) last stored
/// in, re-validating the same way a cryopod's own last-used check does.
/// char_name null means the ckey-only cyborg case (charCyborgGetLastLocation());
/// provided means the IPC case, reading ss13_mob_position's own
/// last_synth_x/y/z (persistence_set_last_synthetic_storage(), persistence_mobs.dm)
/// via the SAME cache every other position lookup already uses.
/proc/persistence_find_saved_synthetic_storage(ckey, char_name = null)
	if(!GLOB.config.sql_enabled || !ckey)
		return null

	var/list/loc_entry
	if(char_name)
		var/list/pos_entry = GLOB.persistence_position_cache["[ckey]|[char_name]"]
		if(islist(pos_entry) && pos_entry["last_synth_z"])
			loc_entry = list("x" = pos_entry["last_synth_x"], "y" = pos_entry["last_synth_y"], "z" = pos_entry["last_synth_z"])
	else
		loc_entry = SSpersistence.charCyborgGetLastLocation(ckey)
	if(!loc_entry)
		return null
	if(loc_entry["z"] < 1 || loc_entry["z"] > world.maxz)
		return null
	var/turf/T = locate(loc_entry["x"], loc_entry["y"], loc_entry["z"])
	var/obj/structure/machinery/recharge_station/synthetic_storage/unit = T ? (locate(/obj/structure/machinery/recharge_station/synthetic_storage) in T) : null
	if(!unit || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
		return null
	if(unit.personal_ckey && (unit.personal_ckey != ckey || (char_name && unit.personal_char_name != char_name)))
		return null
	if(unit.crew_tagged && !_drydock_crew_check_ckey(ckey, unit.z))
		return null
	if(unit.persistent_network && unit.persistent_network != "public")
		var/player_faction = persistence_get_player_faction(ckey)
		if(normalize_faction_uid(player_faction) != normalize_faction_uid(unit.persistent_network))
			return null
	return unit

/// Priority cascade for a unit this ckey doesn't have a valid last-used
/// match for: personal unit -> crew unit -> faction unit -> public unit.
/proc/persistence_find_available_synthetic_storage(faction_uid, ckey)
	if(ckey)
		for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
			if(QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
				continue
			if(unit.personal_ckey == ckey)
				return unit

		for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
			if(QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
				continue
			if(unit.crew_tagged && _drydock_crew_check_ckey(ckey, unit.z))
				return unit

	if(faction_uid)
		var/list/faction_units = list()
		for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
			if(QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
				continue
			if(unit.persistent_network == faction_uid)
				faction_units += unit
		if(length(faction_units))
			return pick(faction_units)

	// Requires BOTH persistent_network == "public" (explicitly tagged public)
	// AND persistent_spawn == TRUE (separately flagged as a spawn point via
	// the faction tagger's "Mark Public Spawn Point" toggle) -- matches
	// persistence_find_available_cryopod()'s exact same two-part gate.
	var/list/public_units = list()
	for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
		if(QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
			continue
		if(unit.persistent_network == "public" && unit.persistent_spawn)
			public_units += unit
	if(length(public_units))
		return pick(public_units)
	return null

/// Collects every currently-valid unit for this ckey, tiered and labeled,
/// for the picker below. Mirrors persistence_collect_available_cryopods()'s
/// shape exactly.
/proc/persistence_collect_available_synthetic_storage(ckey, faction_uid, char_name = null)
	. = list()
	if(!ckey)
		return
	var/list/seen = list()

	var/obj/structure/machinery/recharge_station/synthetic_storage/last_unit = persistence_find_saved_synthetic_storage(ckey, char_name)
	if(last_unit)
		. += list(list("unit" = last_unit, "tier" = "Last Used"))
		seen[last_unit] = TRUE

	for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
		if(seen[unit] || QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
			continue
		if(unit.personal_ckey == ckey)
			. += list(list("unit" = unit, "tier" = "Personal"))
			seen[unit] = TRUE

	for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
		if(seen[unit] || QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
			continue
		if(unit.crew_tagged && _drydock_crew_check_ckey(ckey, unit.z))
			. += list(list("unit" = unit, "tier" = "Crew"))
			seen[unit] = TRUE

	if(faction_uid)
		for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
			if(seen[unit] || QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
				continue
			if(unit.persistent_network == faction_uid)
				. += list(list("unit" = unit, "tier" = "Faction"))
				seen[unit] = TRUE

	for(var/obj/structure/machinery/recharge_station/synthetic_storage/unit in world)
		if(seen[unit] || QDELETED(unit) || unit.tagger_disabled || (unit.stat & (NOPOWER|BROKEN)))
			continue
		if(unit.persistent_network == "public" && unit.persistent_spawn)
			. += list(list("unit" = unit, "tier" = "Public"))
			seen[unit] = TRUE

/**
 * Mandatory-when-needed picker, mirroring persistence_prompt_cryopod_choice()
 * exactly -- re-prompts with a freshly recollected list on cancel/race until
 * a still-valid unit is chosen, or an empty recollect falls back to the
 * automatic cascade above.
 */
/proc/persistence_prompt_synthetic_storage_choice(mob/user, ckey, faction_uid, char_name = null)
	while(TRUE)
		var/list/candidates = persistence_collect_available_synthetic_storage(ckey, faction_uid, char_name)
		if(!length(candidates))
			return null

		var/list/choices = list()
		for(var/list/candidate in candidates)
			var/obj/structure/machinery/recharge_station/synthetic_storage/unit = candidate["unit"]
			var/area/A = get_area(unit)
			var/label = "[candidate["tier"]] -- [A ? A.name : "Unknown Area"] ([unit.x], [unit.y], [unit.z])"
			choices[label] = unit

		var/pick = tgui_input_list(user, "Choose a synthetic storage unit to reactivate in:", "Synthetic Storage Selection", choices, timeout = 0)
		if(QDELETED(user))
			return null
		var/obj/structure/machinery/recharge_station/synthetic_storage/chosen = pick ? choices[pick] : null
		if(!istype(chosen) || QDELETED(chosen) || chosen.tagger_disabled || (chosen.stat & (NOPOWER|BROKEN)))
			continue
		return chosen
