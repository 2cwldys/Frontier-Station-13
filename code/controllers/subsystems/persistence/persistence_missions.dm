/*
 * Persistence - Missions
 * Admin-authored mission templates (fetch-item and kill-NPC types), DB-backed
 * (ss13_missions, V088) and admin-editable (manage_missions()). Single-claim-
 * at-a-time: once accepted, a template is locked to that ckey until they
 * complete, abandon, or an admin frees it. Per-accepter progress is
 * runtime-only (current_accepter_ckey on the cached row, plus a
 * /datum/mission_instance for kill missions) -- a server restart mid-mission
 * resets it to available again; only the templates themselves persist.
 */

/// Cached mission templates: list of list(id, mission_type, title,
/// description, fetch_item_path, fetch_count, kill_mob_path, kill_count,
/// sector_uid, reward, enabled, current_accepter_ckey, instance).
/// current_accepter_ckey/instance are runtime-only, never written to DB.
GLOBAL_LIST_EMPTY(mission_templates)

/**
 * Load mission templates into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/missionsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.mission_templates = list()

	if(!databaseCheckConnection("missionsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT id, mission_type, title, description, fetch_item_path, fetch_count, kill_mob_path, kill_count, sector_uid, reward, enabled FROM ss13_missions WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "missionsInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.mission_templates += list(list(
			"id"                    = text2num(query.item[1]),
			"mission_type"          = query.item[2],
			"title"                 = query.item[3],
			"description"           = query.item[4] || "",
			"fetch_item_path"       = query.item[5],
			"fetch_count"           = text2num(query.item[6]),
			"kill_mob_path"         = query.item[7],
			"kill_count"            = text2num(query.item[8]),
			"sector_uid"            = query.item[9],
			"reward"                = text2num(query.item[10]),
			"enabled"               = text2num(query.item[11]),
			"current_accepter_ckey" = null,
			"instance"              = null
		))
	qdel(query)
	log_subsystem_persistence_info("Missions: loaded [length(GLOB.mission_templates)] mission template(s).")

/// Finds a cached mission template by id, or null.
/proc/get_mission_template(template_id)
	for(var/list/tmpl in GLOB.mission_templates)
		if(tmpl["id"] == template_id)
			return tmpl
	return null

/// Finds a currently-loaded overmap sector marker by name (sector_uid), or
/// null if it isn't loaded this session -- away-site Z's aren't stable
/// across reboots, so this is resolved live at accept time, not stored.
/proc/find_mission_sector(sector_uid)
	if(!sector_uid)
		return null
	for(var/key in GLOB.map_sectors)
		var/obj/effect/overmap/visitable/marker = GLOB.map_sectors[key]
		if(istype(marker) && marker.name == sector_uid)
			return marker
	return null

/// Finds a safe, non-dense SOLID FLOOR turf on the given Z for spawning
/// mission mobs -- deliberately never considers /turf/space (unlike
/// personal_travel_find_space_landing(), which is for player leap landings
/// and prefers open space): mission NPCs should always land on solid ground.
/// Skips turfs blocked by a dense anchored object, same safety shape as
/// first_responder_clear_turf_near()/personal_travel_find_space_landing().
/proc/find_mission_spawn_turf(z)
	var/list/candidates = list()
	for(var/turf/simulated/floor/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.density)
			continue
		var/blocked = FALSE
		for(var/atom/A in T)
			if(A.density && (!isobj(A) || A:anchored))
				blocked = TRUE
				break
		if(!blocked)
			candidates += T
	if(length(candidates))
		return pick(candidates)
	return null

/**
 * Accepts a mission template for accepter, locking it to their ckey. For
 * kill missions, resolves the target sector and starts watching accepter's
 * mob for arrival (see /datum/mission_instance). Returns TRUE on success.
 */
/proc/accept_mission(template_id, mob/living/carbon/human/accepter)
	var/list/tmpl = get_mission_template(template_id)
	if(!tmpl || !tmpl["enabled"] || tmpl["current_accepter_ckey"])
		return FALSE
	if(!accepter || !accepter.ckey)
		return FALSE

	if(tmpl["mission_type"] == "kill")
		var/obj/effect/overmap/visitable/sector_marker = find_mission_sector(tmpl["sector_uid"])
		if(!sector_marker || !length(sector_marker.map_z))
			return FALSE
		var/datum/mission_instance/instance = new()
		instance.template_id = template_id
		instance.accepter_ckey = accepter.ckey
		instance.accepter_mob = accepter
		instance.sector_zs = sector_marker.map_z.Copy()
		instance.kill_mob_path = tmpl["kill_mob_path"]
		instance.remaining_kills = tmpl["kill_count"]
		instance.reward = tmpl["reward"]
		tmpl["instance"] = instance
		instance.start_watching()

	tmpl["current_accepter_ckey"] = accepter.ckey
	return TRUE

/**
 * Abandons a claimed mission, freeing the slot. No refund -- nothing is
 * escrowed for missions, unlike bounties.
 */
/proc/abandon_mission(template_id)
	var/list/tmpl = get_mission_template(template_id)
	if(!tmpl || !tmpl["current_accepter_ckey"])
		return FALSE
	var/datum/mission_instance/instance = tmpl["instance"]
	if(instance)
		qdel(instance)
	tmpl["instance"] = null
	tmpl["current_accepter_ckey"] = null
	return TRUE

/**
 * Completes a fetch mission for accepter -- scans their inventory for
 * fetch_count items matching fetch_item_path (typecacheof-based matching,
 * same shape as /datum/bounty/item), consumes them, pays the reward, frees
 * the slot. Returns TRUE on success.
 */
/proc/turn_in_fetch_mission(template_id, mob/living/carbon/human/accepter)
	var/list/tmpl = get_mission_template(template_id)
	if(!tmpl || tmpl["mission_type"] != "fetch" || tmpl["current_accepter_ckey"] != accepter.ckey)
		return FALSE
	var/wanted_type = text2path(tmpl["fetch_item_path"])
	if(!wanted_type)
		return FALSE
	var/needed = tmpl["fetch_count"]
	var/list/found_items = list()
	for(var/obj/item/I in accepter.GetAllContents())
		if(istype(I, wanted_type))
			found_items += I
			if(length(found_items) >= needed)
				break
	if(length(found_items) < needed)
		return FALSE

	for(var/obj/item/I in found_items)
		qdel(I)

	var/datum/money_account/account = SSeconomy.get_account_by_ckey(accepter.ckey)
	if(account)
		account.adjust_money(tmpl["reward"])

	tmpl["current_accepter_ckey"] = null
	tmpl["instance"] = null
	return TRUE

// ============================================================
// KILL MISSION RUNTIME INSTANCE
// ============================================================

/// Tracks one active kill-mission claim: watches the accepter's mob for
/// arrival at the target sector, spawns the kill-mobs once there, and pays
/// out when the last one dies. One instance per active kill-mission claim.
/datum/mission_instance
	var/template_id
	var/accepter_ckey
	var/mob/accepter_mob
	var/list/sector_zs = list()
	var/kill_mob_path
	var/remaining_kills = 0
	var/reward = 0
	var/list/spawned_mobs = list()
	var/spawned = FALSE

/datum/mission_instance/proc/start_watching()
	RegisterSignal(accepter_mob, COMSIG_MOVABLE_MOVED, PROC_REF(on_accepter_moved))
	check_sector_arrival() // in case they're already at the sector when accepted

/datum/mission_instance/proc/on_accepter_moved(atom/mover, atom/old_loc, movement_dir, forced)
	SIGNAL_HANDLER
	check_sector_arrival()

/datum/mission_instance/proc/check_sector_arrival()
	if(spawned || !accepter_mob)
		return
	if(!(GET_Z(accepter_mob) in sector_zs))
		return
	spawned = TRUE
	UnregisterSignal(accepter_mob, COMSIG_MOVABLE_MOVED)

	var/spawn_z = GET_Z(accepter_mob)
	for(var/i in 1 to remaining_kills)
		var/turf/spawn_turf = find_mission_spawn_turf(spawn_z)
		if(!spawn_turf)
			continue
		var/mob/living/new_mob = new kill_mob_path(spawn_turf)
		spawned_mobs += new_mob
		GLOB.death_event.register(new_mob, src, PROC_REF(on_kill_mob_died))

	if(accepter_mob.client)
		to_chat(accepter_mob, SPAN_DANGER("Hostiles detected -- mission targets have arrived."))

/datum/mission_instance/proc/on_kill_mob_died(mob/dead_mob)
	GLOB.death_event.unregister(dead_mob, src, PROC_REF(on_kill_mob_died))
	spawned_mobs -= dead_mob
	remaining_kills--
	if(remaining_kills <= 0)
		complete_mission()

/datum/mission_instance/proc/complete_mission()
	var/datum/money_account/account = SSeconomy.get_account_by_ckey(accepter_ckey)
	if(account)
		account.adjust_money(reward)
	var/client/C = GLOB.directory[accepter_ckey]
	if(C?.mob)
		to_chat(C.mob, SPAN_GOOD("Mission complete! You've been paid [reward] cr."))

	var/list/tmpl = get_mission_template(template_id)
	if(tmpl)
		tmpl["current_accepter_ckey"] = null
		tmpl["instance"] = null
	qdel(src)

/datum/mission_instance/Destroy()
	if(accepter_mob)
		UnregisterSignal(accepter_mob, COMSIG_MOVABLE_MOVED)
	for(var/mob/m in spawned_mobs)
		if(m && !QDELETED(m))
			GLOB.death_event.unregister(m, src, PROC_REF(on_kill_mob_died))
	spawned_mobs.Cut()
	return ..()

// ============================================================
// MISSIONS ADMIN VERB
// ============================================================

/datum/admins/proc/manage_missions()
	set name = "Manage Missions"
	set category = "Persistence"
	set desc = "Add, edit, remove, or toggle admin-authored missions."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- missions are inactive."))
		return

	while(usr && usr.client)
		var/msg = "Mission templates ([length(GLOB.mission_templates)]):\n"
		for(var/list/tmpl in GLOB.mission_templates)
			msg += "  #[tmpl["id"]] [tmpl["title"]] ([tmpl["mission_type"]]) -- [tmpl["enabled"] ? "ENABLED" : "disabled"], reward [tmpl["reward"]] cr[tmpl["current_accepter_ckey"] ? ", claimed by [tmpl["current_accepter_ckey"]]" : ""]\n"
		to_chat(usr, SPAN_NOTICE(msg))

		var/choice = tgui_input_list(usr, "Select action:", "Manage Missions", list("Add Mission", "Edit Mission", "Remove Mission", "Toggle Enabled", "Close"))
		if(!choice || choice == "Close")
			return

		if(choice == "Add Mission")
			var/mission_type = tgui_input_list(usr, "Mission type:", "Add Mission", list("fetch", "kill"))
			if(!mission_type)
				continue
			var/title = tgui_input_text(usr, "Mission title:", "Add Mission", "", max_length = 128)
			if(!title)
				continue
			var/description = tgui_input_text(usr, "Description (optional):", "Add Mission", "", max_length = 512)
			var/reward = tgui_input_number(usr, "Reward (credits):", "Add Mission", 1000, 1000000, 1)
			if(isnull(reward))
				continue

			var/fetch_item_path = null
			var/fetch_count = null
			var/kill_mob_path = null
			var/kill_count = null
			var/sector_uid = null

			if(mission_type == "fetch")
				var/typed_path = tgui_input_text(usr, "Item type path to fetch (e.g. /obj/item/ore/diamond):", "Add Mission", "", max_length = 128)
				var/path = text2path(typed_path)
				if(!path || !ispath(path, /obj/item))
					to_chat(usr, SPAN_WARNING("'[typed_path]' is not a valid /obj/item type path."))
					continue
				fetch_item_path = "[path]"
				fetch_count = tgui_input_number(usr, "How many required:", "Add Mission", 1, 1000, 1)
				if(isnull(fetch_count))
					continue
			else
				var/typed_path = tgui_input_text(usr, "Mob type path to kill (e.g. /mob/living/simple_animal/hostile/carp):", "Add Mission", "", max_length = 128)
				var/path = text2path(typed_path)
				if(!path || !ispath(path, /mob/living))
					to_chat(usr, SPAN_WARNING("'[typed_path]' is not a valid /mob/living type path."))
					continue
				kill_mob_path = "[path]"
				kill_count = tgui_input_number(usr, "How many to kill:", "Add Mission", 1, 100, 1)
				if(isnull(kill_count))
					continue
				sector_uid = tgui_input_text(usr, "Target sector name (must exactly match a currently-loaded sector's name):", "Add Mission", "", max_length = 128)
				if(!sector_uid)
					continue
				if(!find_mission_sector(sector_uid))
					to_chat(usr, SPAN_WARNING("Warning: no currently-loaded sector named '[sector_uid]' -- saved anyway, but it won't be acceptable until a matching sector exists."))

			var/datum/db_query/q = SSdbcore.NewQuery(
				{"INSERT INTO ss13_missions (map_path, mission_type, title, description, fetch_item_path, fetch_count, kill_mob_path, kill_count, sector_uid, reward, enabled)
				VALUES (:mp, :mt, :title, :desc, :fip, :fc, :kmp, :kc, :su, :reward, 1)"},
				list(
					"mp" = "[SSatlas.current_map.path]", "mt" = mission_type, "title" = title, "desc" = (description != "" ? description : null),
					"fip" = fetch_item_path, "fc" = fetch_count, "kmp" = kill_mob_path, "kc" = kill_count, "su" = sector_uid, "reward" = reward
				)
			)
			q.Execute()
			SSpersistence.databaseCheckQueryResult(q, "manage_missions add")
			var/new_id = text2num(q.last_insert_id)
			qdel(q)

			GLOB.mission_templates += list(list(
				"id" = new_id, "mission_type" = mission_type, "title" = title, "description" = description,
				"fetch_item_path" = fetch_item_path, "fetch_count" = fetch_count, "kill_mob_path" = kill_mob_path,
				"kill_count" = kill_count, "sector_uid" = sector_uid, "reward" = reward, "enabled" = TRUE,
				"current_accepter_ckey" = null, "instance" = null
			))
			log_and_message_admins("added mission '[title]' ([mission_type])", usr)
			to_chat(usr, SPAN_GOOD("Added mission '[title]'."))

		if(choice == "Edit Mission")
			if(!length(GLOB.mission_templates))
				to_chat(usr, SPAN_NOTICE("No missions to edit."))
				continue
			var/list/edit_choices = list()
			for(var/list/tmpl in GLOB.mission_templates)
				edit_choices["#[tmpl["id"]] [tmpl["title"]]"] = tmpl
			var/edit_pick = tgui_input_list(usr, "Edit which mission?", "Edit Mission", edit_choices)
			if(!edit_pick)
				continue
			var/list/edit_tmpl = edit_choices[edit_pick]
			var/new_reward = tgui_input_number(usr, "New reward (credits):", "Edit Mission", edit_tmpl["reward"], 1000000, 1)
			if(isnull(new_reward))
				continue
			var/datum/db_query/eq = SSdbcore.NewQuery(
				"UPDATE ss13_missions SET reward = :reward WHERE id = :id",
				list("reward" = new_reward, "id" = edit_tmpl["id"])
			)
			eq.Execute()
			SSpersistence.databaseCheckQueryResult(eq, "manage_missions edit")
			qdel(eq)
			edit_tmpl["reward"] = new_reward
			log_and_message_admins("edited mission '[edit_tmpl["title"]]' reward to [new_reward]", usr)
			to_chat(usr, SPAN_GOOD("Updated '[edit_tmpl["title"]]' reward to [new_reward] cr."))

		if(choice == "Remove Mission")
			if(!length(GLOB.mission_templates))
				to_chat(usr, SPAN_NOTICE("No missions to remove."))
				continue
			var/list/remove_choices = list()
			for(var/list/tmpl in GLOB.mission_templates)
				remove_choices["#[tmpl["id"]] [tmpl["title"]]"] = tmpl
			var/remove_pick = tgui_input_list(usr, "Remove which mission?", "Remove Mission", remove_choices)
			if(!remove_pick)
				continue
			var/list/remove_tmpl = remove_choices[remove_pick]
			if(remove_tmpl["current_accepter_ckey"])
				abandon_mission(remove_tmpl["id"])
			var/datum/db_query/rq = SSdbcore.NewQuery(
				"DELETE FROM ss13_missions WHERE id = :id",
				list("id" = remove_tmpl["id"])
			)
			rq.Execute()
			SSpersistence.databaseCheckQueryResult(rq, "manage_missions remove")
			qdel(rq)
			GLOB.mission_templates -= list(remove_tmpl)
			log_and_message_admins("removed mission '[remove_tmpl["title"]]'", usr)
			to_chat(usr, SPAN_GOOD("Removed '[remove_tmpl["title"]]'."))

		if(choice == "Toggle Enabled")
			if(!length(GLOB.mission_templates))
				to_chat(usr, SPAN_NOTICE("No missions to toggle."))
				continue
			var/list/toggle_choices = list()
			for(var/list/tmpl in GLOB.mission_templates)
				toggle_choices["#[tmpl["id"]] [tmpl["title"]] ([tmpl["enabled"] ? "ENABLED" : "disabled"])"] = tmpl
			var/toggle_pick = tgui_input_list(usr, "Toggle which mission?", "Toggle Enabled", toggle_choices)
			if(!toggle_pick)
				continue
			var/list/toggle_tmpl = toggle_choices[toggle_pick]
			var/new_state = toggle_tmpl["enabled"] ? 0 : 1
			var/datum/db_query/tq = SSdbcore.NewQuery(
				"UPDATE ss13_missions SET enabled = :en WHERE id = :id",
				list("en" = new_state, "id" = toggle_tmpl["id"])
			)
			tq.Execute()
			SSpersistence.databaseCheckQueryResult(tq, "manage_missions toggle")
			qdel(tq)
			toggle_tmpl["enabled"] = new_state
			log_and_message_admins("[new_state ? "enabled" : "disabled"] mission '[toggle_tmpl["title"]]'", usr)
