/*
 * Persistence - Hostile NPC Presets
 * Admin-authored, DB-backed (ss13_hostile_npc_presets), runtime-editable
 * named equipment/stat/faction presets for /mob/living/carbon/human/npc/hostile
 * (code/modules/mob/living/carbon/human/npc/hostile_npc.dm) -- mirrors the
 * exact shape missions/factions already use in this file family (a cached
 * GLOBAL_LIST, an Initialize() proc called from SSpersistence.Initialize(),
 * an admin verb that mutates the DB row and the cached entry together with
 * no restart needed, and a small lookup helper).
 *
 * Consumed by: manage_missions()'s kill-mission authoring flow
 * (persistence_missions.dm), fauna_spawner's mob_choices "preset" key
 * (mob_spawner.dm), the faction barracks machine, the personal commander
 * summon item, and the ad-hoc "Spawn Hostile NPC" admin verb below.
 */

/// Cached hostile NPC presets: list of list(id, name, outfit_path,
/// faction_uid, aggro_range, ranged_attack_range, attack_delay,
/// destroy_surroundings, move_speed, description, enabled).
GLOBAL_LIST_EMPTY(hostile_npc_presets)

/**
 * Load hostile NPC presets into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/hostileNpcPresetsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.hostile_npc_presets = list()

	if(!databaseCheckConnection("hostileNpcPresetsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT id, name, outfit_path, faction_uid, aggro_range, ranged_attack_range, attack_delay, destroy_surroundings, move_speed, description, enabled, outfit_template_id, pack_id FROM ss13_hostile_npc_presets WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "hostileNpcPresetsInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.hostile_npc_presets += list(list(
			"id"                   = text2num(query.item[1]),
			"name"                 = query.item[2],
			"outfit_path"          = query.item[3],
			"faction_uid"          = query.item[4],
			"aggro_range"          = text2num(query.item[5]),
			"ranged_attack_range"  = text2num(query.item[6]),
			"attack_delay"         = text2num(query.item[7]),
			"destroy_surroundings" = text2num(query.item[8]),
			"move_speed"           = text2num(query.item[9]),
			"description"          = query.item[10] || "",
			"enabled"              = text2num(query.item[11]),
			"outfit_template_id"   = query.item[12] ? text2num(query.item[12]) : null,
			"pack_id"              = query.item[13] || null
		))
	qdel(query)
	log_subsystem_persistence_info("Hostile NPC presets: loaded [length(GLOB.hostile_npc_presets)] preset(s).")

/// Finds a cached hostile NPC preset by numeric id, or null.
/proc/get_hostile_npc_preset(id)
	if(isnull(id))
		return null
	for(var/list/preset in GLOB.hostile_npc_presets)
		if(preset["id"] == id)
			return preset
	return null

/// Finds a cached hostile NPC preset by name, or null -- for DM-authored
/// callers (fauna_spawner subtypes) that can't know a DB autoincrement id at
/// compile time.
/proc/get_hostile_npc_preset_by_name(name)
	if(!name)
		return null
	for(var/list/preset in GLOB.hostile_npc_presets)
		if(preset["name"] == name)
			return preset
	return null

/// TRUE if preset has no faction restriction of its own (authored with
/// Faction = "(none)"), or its stored faction_uid exactly matches
/// faction_uid -- the single source of truth for "can this barracks/
/// commander's beacon use this preset." A preset hard-tagged to a specific
/// faction is exclusive to that faction; everyone else is refused outright,
/// not merely overridden. Checked both when building a picker and again at
/// actual spawn time (in case the caller's own faction tag changed since).
/proc/hostile_npc_preset_allowed_for_faction(list/preset, faction_uid)
	if(!preset)
		return FALSE
	return !preset["faction_uid"] || preset["faction_uid"] == faction_uid

/// Enabled presets usable by faction_uid -- generic ("(none)") presets plus
/// anything specifically tagged to faction_uid itself.
/proc/get_hostile_npc_presets_for_faction(faction_uid)
	var/list/result = list()
	for(var/list/preset in GLOB.hostile_npc_presets)
		if(!preset["enabled"])
			continue
		if(!hostile_npc_preset_allowed_for_faction(preset, faction_uid))
			continue
		result += list(preset)
	return result

/**
 * Spawns a hostile NPC from a preset at T, fully configured (outfit, faction
 * tag/coloring, stats) and thinking -- the single shared choke point every
 * integration (missions, spawners, barracks, commander item, ad-hoc admin
 * spawn) should use. override_faction_uid (if given) wins over the preset's
 * own stored faction_uid -- lets the same preset be reused by different
 * factions' barracks/commander items. Returns the new mob, or null if the
 * preset doesn't exist/is disabled or T is invalid.
 */
/proc/spawn_hostile_npc_from_preset(preset_id, turf/T, override_faction_uid = null)
	var/list/preset = get_hostile_npc_preset(preset_id)
	if(!preset || !preset["enabled"] || !T)
		return null
	new /obj/effect/portal/decorative/fading(T, null, null, 5 SECONDS, 0)
	spark(T, 3, GLOB.alldirs)
	var/mob/living/carbon/human/npc/hostile/H = new(T)
	H.apply_hostile_preset(preset, override_faction_uid)
	return H

/// Merges the compile-time GLOB.outfit_cache with admin-captured
/// GLOB.custom_outfit_templates (persistence_outfit_templates.dm) into one
/// combined picker options list, used by both Add Preset and Edit Preset's
/// outfit step. Each value is tagged list("kind"="builtin", "outfit"=instance)
/// or list("kind"="custom", "template_id"=id).
/proc/build_hostile_npc_outfit_options()
	var/list/options = list()
	for(var/label in GLOB.outfit_cache)
		options[label] = list("kind" = "builtin", "outfit" = GLOB.outfit_cache[label])
	for(var/list/template in GLOB.custom_outfit_templates)
		options["[template["name"]] (custom)"] = list("kind" = "custom", "template_id" = template["id"])
	return options

/datum/admins/proc/manage_hostile_npc_presets()
	set name = "Manage Hostile NPC Presets"
	set category = "Persistence.Away Sites & Missions"
	set desc = "Add, edit, remove, or toggle admin-authored hostile NPC equipment/stat presets."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- hostile NPC presets are inactive."))
		return

	while(usr && usr.client)
		var/msg = "Hostile NPC presets ([length(GLOB.hostile_npc_presets)]):\n"
		for(var/list/preset in GLOB.hostile_npc_presets)
			var/list/preset_outfit_template = preset["outfit_template_id"] ? get_outfit_template(preset["outfit_template_id"]) : null
			var/preset_outfit_desc = preset_outfit_template ? "[preset_outfit_template["name"]] (custom)" : preset["outfit_path"]
			msg += "  #[preset["id"]] [preset["name"]] -- [preset["enabled"] ? "ENABLED" : "disabled"], outfit [preset_outfit_desc][preset["faction_uid"] ? ", faction [get_faction_name(preset["faction_uid"])]" : ""]\n"
		to_chat(usr, SPAN_NOTICE(msg))

		var/choice = tgui_input_list(usr, "Select action:", "Manage Hostile NPC Presets", list("Add Preset", "Edit Preset", "Remove Preset", "Toggle Enabled", "Close"))
		if(!choice || choice == "Close")
			return

		if(choice == "Add Preset")
			var/name = tgui_input_text(usr, "Preset name:", "Add Preset", "", max_length = 128)
			if(!name)
				continue
			var/list/outfit_options = build_hostile_npc_outfit_options()
			var/chosen_outfit = tgui_input_list(usr, "Select an outfit:", "Add Preset", outfit_options)
			if(!chosen_outfit)
				continue
			var/list/chosen_outfit_pick = outfit_options[chosen_outfit]
			var/outfit_path = null
			var/outfit_template_id = null
			if(chosen_outfit_pick["kind"] == "builtin")
				var/obj/outfit/picked_outfit = chosen_outfit_pick["outfit"]
				outfit_path = "[picked_outfit.type]"
			else
				outfit_template_id = chosen_outfit_pick["template_id"]

			var/faction_uid = null
			if(length(GLOB.persistence_faction_cache))
				var/list/faction_options = list("(none)" = null)
				for(var/uid in GLOB.persistence_faction_cache)
					faction_options[get_faction_name(uid)] = uid
				var/chosen_label = tgui_input_list(usr, "Faction (optional, can be overridden by whatever spawns this preset):", "Add Preset", faction_options)
				if(isnull(chosen_label))
					continue
				faction_uid = faction_options[chosen_label]

			var/aggro_range = tgui_input_number(usr, "Aggro/search range (tiles):", "Add Preset", 10, 30, 1)
			if(isnull(aggro_range))
				continue
			var/ranged_attack_range = tgui_input_number(usr, "Ranged attack range (tiles, used if this preset's outfit has a gun):", "Add Preset", 6, 20, 1)
			if(isnull(ranged_attack_range))
				continue
			var/attack_delay = tgui_input_number(usr, "Delay between attacks (deciseconds):", "Add Preset", 10, 100, 1)
			if(isnull(attack_delay))
				continue
			var/move_speed = tgui_input_number(usr, "Movement delay (lower = faster):", "Add Preset", 5, 20, 1)
			if(isnull(move_speed))
				continue
			var/destroy_surroundings = tgui_alert(usr, "Should this NPC smash through obstacles (tables/windows/closets) while pathing to a target?", "Add Preset", list("Yes", "No")) == "Yes"
			var/description = tgui_input_text(usr, "Description (optional):", "Add Preset", "", max_length = 512)
			var/pack_id = tgui_input_text(usr, "Pack tag (optional -- presets sharing the same tag won't attack each other, e.g. multiple 'pirate' variants; only matters for FACTIONLESS presets, leave blank otherwise):", "Add Preset", "", max_length = 64)
			if(pack_id == "")
				pack_id = null

			var/datum/db_query/q = SSdbcore.NewQuery(
				{"INSERT INTO ss13_hostile_npc_presets (map_path, name, outfit_path, outfit_template_id, faction_uid, aggro_range, ranged_attack_range, attack_delay, destroy_surroundings, move_speed, description, enabled, pack_id)
				VALUES (:mp, :name, :outfit, :outfit_template, :faction, :aggro, :ranged, :delay, :destroy, :speed, :desc, 1, :pack)"},
				list(
					"mp" = "[SSatlas.current_map.path]", "name" = name, "outfit" = outfit_path, "outfit_template" = outfit_template_id, "faction" = faction_uid,
					"aggro" = aggro_range, "ranged" = ranged_attack_range, "delay" = attack_delay, "destroy" = destroy_surroundings, "speed" = move_speed,
					"desc" = (description != "" ? description : null), "pack" = pack_id
				)
			)
			q.Execute()
			SSpersistence.databaseCheckQueryResult(q, "manage_hostile_npc_presets add")
			var/new_id = text2num(q.last_insert_id)
			qdel(q)

			GLOB.hostile_npc_presets += list(list(
				"id" = new_id, "name" = name, "outfit_path" = outfit_path, "outfit_template_id" = outfit_template_id, "faction_uid" = faction_uid,
				"aggro_range" = aggro_range, "ranged_attack_range" = ranged_attack_range, "attack_delay" = attack_delay,
				"destroy_surroundings" = destroy_surroundings, "move_speed" = move_speed, "description" = description, "enabled" = TRUE, "pack_id" = pack_id
			))
			log_and_message_admins("added hostile NPC preset '[name]'", usr)
			to_chat(usr, SPAN_GOOD("Added preset '[name]'."))

		if(choice == "Edit Preset")
			if(!length(GLOB.hostile_npc_presets))
				to_chat(usr, SPAN_NOTICE("No presets to edit."))
				continue
			var/list/edit_choices = list()
			for(var/list/preset in GLOB.hostile_npc_presets)
				edit_choices["#[preset["id"]] [preset["name"]]"] = preset
			var/edit_pick = tgui_input_list(usr, "Edit which preset?", "Edit Preset", edit_choices)
			if(!edit_pick)
				continue
			var/list/edit_preset = edit_choices[edit_pick]

			var/field = tgui_input_list(usr, "Edit which field?", "Edit Preset", list("Outfit", "Faction", "Pack Tag", "Aggro Range", "Ranged Attack Range", "Attack Delay", "Move Speed", "Destroy Surroundings"))
			if(!field)
				continue

			if(field == "Outfit")
				var/list/outfit_options = build_hostile_npc_outfit_options()
				var/chosen_outfit = tgui_input_list(usr, "Select an outfit:", "Edit Preset", outfit_options)
				if(!chosen_outfit)
					continue
				var/list/chosen_outfit_pick = outfit_options[chosen_outfit]
				if(chosen_outfit_pick["kind"] == "builtin")
					var/obj/outfit/picked_outfit = chosen_outfit_pick["outfit"]
					_hostile_npc_preset_update_field(edit_preset, "outfit_path", "[picked_outfit.type]", usr)
					_hostile_npc_preset_update_field(edit_preset, "outfit_template_id", null, usr)
				else
					_hostile_npc_preset_update_field(edit_preset, "outfit_template_id", chosen_outfit_pick["template_id"], usr)
					_hostile_npc_preset_update_field(edit_preset, "outfit_path", null, usr)
			else if(field == "Faction")
				var/list/faction_options = list("(none)" = null)
				for(var/uid in GLOB.persistence_faction_cache)
					faction_options[get_faction_name(uid)] = uid
				var/chosen_label = tgui_input_list(usr, "Faction:", "Edit Preset", faction_options)
				if(isnull(chosen_label))
					continue
				_hostile_npc_preset_update_field(edit_preset, "faction_uid", faction_options[chosen_label], usr)
			else if(field == "Pack Tag")
				var/new_pack_id = tgui_input_text(usr, "Pack tag (blank to clear -- presets sharing the same tag won't attack each other; only matters for FACTIONLESS presets):", "Edit Preset", edit_preset["pack_id"] || "", max_length = 64)
				if(isnull(new_pack_id))
					continue
				_hostile_npc_preset_update_field(edit_preset, "pack_id", (new_pack_id != "" ? new_pack_id : null), usr)
			else if(field == "Aggro Range")
				var/new_val = tgui_input_number(usr, "Aggro/search range (tiles):", "Edit Preset", edit_preset["aggro_range"], 30, 1)
				if(!isnull(new_val))
					_hostile_npc_preset_update_field(edit_preset, "aggro_range", new_val, usr)
			else if(field == "Ranged Attack Range")
				var/new_val = tgui_input_number(usr, "Ranged attack range (tiles):", "Edit Preset", edit_preset["ranged_attack_range"], 20, 1)
				if(!isnull(new_val))
					_hostile_npc_preset_update_field(edit_preset, "ranged_attack_range", new_val, usr)
			else if(field == "Attack Delay")
				var/new_val = tgui_input_number(usr, "Delay between attacks (deciseconds):", "Edit Preset", edit_preset["attack_delay"], 100, 1)
				if(!isnull(new_val))
					_hostile_npc_preset_update_field(edit_preset, "attack_delay", new_val, usr)
			else if(field == "Move Speed")
				var/new_val = tgui_input_number(usr, "Movement delay (lower = faster):", "Edit Preset", edit_preset["move_speed"], 20, 1)
				if(!isnull(new_val))
					_hostile_npc_preset_update_field(edit_preset, "move_speed", new_val, usr)
			else if(field == "Destroy Surroundings")
				var/new_val = tgui_alert(usr, "Smash through obstacles while pathing?", "Edit Preset", list("Yes", "No")) == "Yes"
				_hostile_npc_preset_update_field(edit_preset, "destroy_surroundings", new_val, usr)

		if(choice == "Remove Preset")
			if(!length(GLOB.hostile_npc_presets))
				to_chat(usr, SPAN_NOTICE("No presets to remove."))
				continue
			var/list/remove_choices = list()
			for(var/list/preset in GLOB.hostile_npc_presets)
				remove_choices["#[preset["id"]] [preset["name"]]"] = preset
			var/remove_pick = tgui_input_list(usr, "Remove which preset?", "Remove Preset", remove_choices)
			if(!remove_pick)
				continue
			var/list/remove_preset = remove_choices[remove_pick]
			var/datum/db_query/rq = SSdbcore.NewQuery(
				"DELETE FROM ss13_hostile_npc_presets WHERE id = :id",
				list("id" = remove_preset["id"])
			)
			rq.Execute()
			SSpersistence.databaseCheckQueryResult(rq, "manage_hostile_npc_presets remove")
			qdel(rq)
			GLOB.hostile_npc_presets -= list(remove_preset)
			log_and_message_admins("removed hostile NPC preset '[remove_preset["name"]]'", usr)
			to_chat(usr, SPAN_GOOD("Removed '[remove_preset["name"]]'."))

		if(choice == "Toggle Enabled")
			if(!length(GLOB.hostile_npc_presets))
				to_chat(usr, SPAN_NOTICE("No presets to toggle."))
				continue
			var/list/toggle_choices = list()
			for(var/list/preset in GLOB.hostile_npc_presets)
				toggle_choices["#[preset["id"]] [preset["name"]] ([preset["enabled"] ? "ENABLED" : "disabled"])"] = preset
			var/toggle_pick = tgui_input_list(usr, "Toggle which preset?", "Toggle Enabled", toggle_choices)
			if(!toggle_pick)
				continue
			var/list/toggle_preset = toggle_choices[toggle_pick]
			var/new_state = toggle_preset["enabled"] ? 0 : 1
			var/datum/db_query/tq = SSdbcore.NewQuery(
				"UPDATE ss13_hostile_npc_presets SET enabled = :en WHERE id = :id",
				list("en" = new_state, "id" = toggle_preset["id"])
			)
			tq.Execute()
			SSpersistence.databaseCheckQueryResult(tq, "manage_hostile_npc_presets toggle")
			qdel(tq)
			toggle_preset["enabled"] = new_state
			log_and_message_admins("[new_state ? "enabled" : "disabled"] hostile NPC preset '[toggle_preset["name"]]'", usr)

/// Shared single-field DB+cache update for the Edit Preset flow above.
/proc/_hostile_npc_preset_update_field(list/preset, field, value, mob/user)
	var/column_map = list(
		"outfit_path" = "outfit_path", "outfit_template_id" = "outfit_template_id", "faction_uid" = "faction_uid", "pack_id" = "pack_id", "aggro_range" = "aggro_range",
		"ranged_attack_range" = "ranged_attack_range", "attack_delay" = "attack_delay",
		"move_speed" = "move_speed", "destroy_surroundings" = "destroy_surroundings"
	)
	var/column = column_map[field]
	if(!column)
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_hostile_npc_presets SET [column] = :val WHERE id = :id",
		list("val" = value, "id" = preset["id"])
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "manage_hostile_npc_presets edit")
	qdel(q)
	preset[field] = value
	log_and_message_admins("edited hostile NPC preset '[preset["name"]]' [field] to [value]", user)
	to_chat(user, SPAN_GOOD("Updated '[preset["name"]]' [field]."))

/// Ad-hoc manual-testing spawn -- picks a preset and drops it at the admin's feet.
/datum/admins/proc/spawn_hostile_npc()
	set name = "Spawn Hostile NPC"
	set category = "Fun"
	set desc = "Spawn a hostile NPC from an admin-authored preset at your location."

	if(!check_rights(R_ADMIN))
		return
	if(!length(GLOB.hostile_npc_presets))
		to_chat(usr, SPAN_WARNING("No hostile NPC presets exist -- create one via 'Manage Hostile NPC Presets' first."))
		return

	var/list/preset_options = list()
	for(var/list/preset in GLOB.hostile_npc_presets)
		if(!preset["enabled"])
			continue
		preset_options["#[preset["id"]] [preset["name"]]"] = preset
	if(!length(preset_options))
		to_chat(usr, SPAN_WARNING("No enabled hostile NPC presets exist."))
		return

	var/pick = tgui_input_list(usr, "Spawn which preset?", "Spawn Hostile NPC", preset_options)
	if(!pick)
		return
	var/list/preset = preset_options[pick]
	var/turf/T = get_turf(usr)
	var/mob/living/carbon/human/npc/hostile/H = spawn_hostile_npc_from_preset(preset["id"], T)
	if(!H)
		to_chat(usr, SPAN_WARNING("Failed to spawn -- preset may be disabled."))
		return
	log_and_message_admins("spawned hostile NPC preset '[preset["name"]]' at ([T.x],[T.y],[T.z])", usr)
	to_chat(usr, SPAN_GOOD("Spawned '[preset["name"]]'."))
