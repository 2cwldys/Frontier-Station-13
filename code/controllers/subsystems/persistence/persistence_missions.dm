/*
 * Persistence - Missions
 * Admin-authored mission templates (fetch-item, visit-site, and kill-NPC
 * types), DB-backed (ss13_missions, V088/V121) and admin-editable
 * (manage_missions()). Kill missions are compiled out by default (see
 * ENABLE_KILL_MISSIONS, _compile_options.dm) -- the type/DB value/runtime
 * plumbing stays in place, just inert and hidden from the board/admin
 * authoring UI until re-enabled. Single-claim-at-a-time: once accepted, a
 * template is locked to that ckey until they complete, abandon, or an admin
 * frees it. Per-accepter progress is runtime-only (current_accepter_ckey on
 * the cached row, plus a /datum/mission_instance for visit/kill missions) --
 * a server restart mid-mission resets it to available again; only the
 * templates themselves persist.
 *
 * Visit and kill missions both target an away-site TEMPLATE
 * (sector_template_id), not a specific instance -- away sites aren't
 * guaranteed to exist in a given session (dynamic sites are drawn from an RNG
 * pool each boot). accept_mission() uses whatever live nullsec instance of
 * the template currently exists, or auto-generates one on demand (up to
 * MISSION_AUTOGEN_SECTOR_LIMIT, GLOB.mission_spawned_zs) via
 * _spawn_away_site_for_template() (persistence_factions.dm) -- this pool
 * never touches the normal per-round RNG dynamic-site budget. Both also
 * require a manual Turn In (like fetch missions) once objective_complete --
 * reaching the sector (visit) or killing the last mob (kill) only flips the
 * instance to "objective complete," away from the sector; it does not pay
 * out directly (see /datum/mission_instance, turn_in_visit_mission(),
 * turn_in_kill_mission()). A mission-auto-generated sector despawns itself
 * once its mission is turned in, provided no one is still on it and no other
 * active instance still targets it (_try_cleanup_mission_sector()) -- freeing
 * the cap slot.
 */

/// Sectors this system itself auto-generated for a mission (via
/// _spawn_away_site_for_template()) -- distinct from admin-generated/pinned/
/// RNG dynamic sites, which never count against the cap and are never
/// auto-despawned by _try_cleanup_mission_sector().
GLOBAL_LIST_EMPTY(mission_spawned_zs)

/// Cap on how many sectors this system will auto-generate for missions at
/// once. Admin-generated sites (via "Generate Away Site") don't count
/// against this -- it only limits missions' own on-demand generation.
#define MISSION_AUTOGEN_SECTOR_LIMIT 3

/// Retry interval for _try_cleanup_mission_sector() when a mission-spawned
/// sector can't yet be safely despawned (someone's still on it, or another
/// active mission instance still targets it).
#define MISSION_CLEANUP_RETRY_DELAY 30 SECONDS

/// Cached mission templates: list of list(id, mission_type, title,
/// description, fetch_item_path, fetch_count, kill_mob_path, kill_count,
/// sector_template_id, reward, enabled, current_accepter_ckey, instance).
/// current_accepter_ckey/instance are runtime-only, never written to DB.
GLOBAL_LIST_EMPTY(mission_templates)

/// TRUE if any currently-active mission instance has z among its target
/// sector's Zs -- used both by is_active_mission_sector() below and by
/// _try_cleanup_mission_sector()'s "is anyone else still using this Z"
/// check (which used to duplicate this same loop inline; now shares it).
/proc/mission_instance_targets_z(z)
	for(var/list/tmpl in GLOB.mission_templates)
		var/datum/mission_instance/instance = tmpl["instance"]
		if(istype(instance) && (z in instance.sector_zs))
			return TRUE
	return FALSE

/**
 * TRUE if z is currently reserved for an active mission -- either a sector
 * this system auto-generated (GLOB.mission_spawned_zs, reserved for its
 * whole lifetime until despawned) or a dynamic/admin-placed away site a
 * live mission_instance is currently targeting (reserved only while that
 * mission is in progress). Checked by faction_beacon.dm/piracy_beacon.dm to
 * refuse claiming/assembly, and by persistence_zone_security.dm's zone-entry
 * banner. The dynamic/admin case needs no explicit "un-protect" step when
 * the mission ends -- turn-in/abandon already qdel()s the instance and
 * nulls tmpl["instance"], so this live scan simply stops matching on its
 * own. Never torn down either way -- only GLOB.mission_spawned_zs entries
 * are ever despawned by mission cleanup (_try_cleanup_mission_sector()).
 */
/proc/is_active_mission_sector(z)
	return (z in GLOB.mission_spawned_zs) || mission_instance_targets_z(z)

/**
 * Load mission templates into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/missionsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.mission_templates = list()

	if(!databaseCheckConnection("missionsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT id, mission_type, title, description, fetch_item_path, fetch_count, kill_mob_path, kill_count, sector_template_id, reward, enabled, kill_preset_id FROM ss13_missions WHERE map_path = :mp",
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
			"sector_template_id"    = query.item[9],
			"reward"                = text2num(query.item[10]),
			"enabled"               = text2num(query.item[11]),
			"kill_preset_id"        = query.item[12] ? text2num(query.item[12]) : null,
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

/**
 * Finds a currently-loaded, nullsec instance of the away-site TEMPLATE
 * sector_template_id (any origin -- RNG dynamic pick, admin-generated via
 * "Generate Away Site", or mission-auto-generated) -- or null if none
 * currently qualifies. Templates are targeted rather than a specific
 * instance since away sites aren't guaranteed to exist in a given session;
 * an instance that no longer qualifies (e.g. it's since fallen inside a
 * beacon's claimed radius, or someone's assembled a piracy beacon there) is
 * treated the same as none at all -- kill missions only ever run in
 * nullsec, uncontested ground.
 */
/proc/find_mission_sector(sector_template_id)
	if(!sector_template_id)
		return null
	for(var/key in GLOB.map_templates)
		var/datum/map_template/tmpl = GLOB.map_templates[key]
		if(!istype(tmpl, /datum/map_template/ruin/away_site) || tmpl.id != sector_template_id)
			continue
		var/z = text2num(key)
		if(!z || zone_security_get(z) != ZONE_NULLSEC || piracy_beacon_present_on_z(z))
			continue
		var/obj/effect/overmap/visitable/marker = GLOB.map_sectors[key]
		if(istype(marker))
			return marker
	return null

/// Finds a safe, non-dense turf on the given Z for spawning mission mobs.
/// By default this is SOLID FLOOR only -- deliberately never /turf/space
/// (unlike personal_travel_find_space_landing(), which is for player leap
/// landings and prefers open space): mission NPCs should always land on
/// solid ground. allow_space (set by check_sector_arrival() for carp targets
/// specifically -- they're lore-wise space-swimming creatures) also
/// considers /turf/space. Skips turfs blocked by a dense anchored object,
/// same safety shape as first_responder_clear_turf_near()/
/// personal_travel_find_space_landing().
/proc/find_mission_spawn_turf(z, allow_space = FALSE)
	var/list/candidates = list()
	if(allow_space)
		for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			CHECK_TICK
			if(T.density)
				continue
			var/blocked = FALSE
			for(var/atom/A in T)
				if(A.density && (!isobj(A) || A:anchored))
					blocked = TRUE
					break
			if(!blocked)
				candidates += T
	else
		for(var/turf/simulated/floor/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			CHECK_TICK
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
 * kill missions, resolves the target sector -- reusing a live nullsec
 * instance of the template if one exists, auto-generating one if not (and
 * under MISSION_AUTOGEN_SECTOR_LIMIT), or failing if neither works -- and
 * starts watching accepter's mob for arrival (see /datum/mission_instance).
 * Returns TRUE on success.
 */
/proc/accept_mission(template_id, mob/living/carbon/human/accepter)
	var/list/tmpl = get_mission_template(template_id)
	if(!tmpl || !tmpl["enabled"] || tmpl["current_accepter_ckey"])
		return FALSE
	if(!accepter || !accepter.ckey)
		return FALSE

	if(tmpl["mission_type"] == "kill" || tmpl["mission_type"] == "visit")
		var/obj/effect/overmap/visitable/sector_marker = find_mission_sector(tmpl["sector_template_id"])
		if(!sector_marker || !length(sector_marker.map_z))
			if(length(GLOB.mission_spawned_zs) >= MISSION_AUTOGEN_SECTOR_LIMIT)
				return FALSE
			var/datum/map_template/ruin/away_site/site = SSmapping.away_sites_templates[tmpl["sector_template_id"]]
			if(!site)
				return FALSE
			to_chat(accepter, SPAN_NOTICE("Locating a suitable sector for this mission -- this may take a moment..."))
			var/new_z = _spawn_away_site_for_template(site, null, TRUE)
			if(!new_z)
				to_chat(accepter, SPAN_WARNING("No suitable sector could be found right now -- try again later."))
				return FALSE
			sector_marker = GLOB.map_sectors["[new_z]"]
			if(!sector_marker || !length(sector_marker.map_z))
				return FALSE
			// Every deck the sector spans, not just new_z -- otherwise
			// _try_cleanup_mission_sector()'s "if(!(z in GLOB.mission_spawned_zs))
			// return" guard silently skips every deck past the first, and a
			// multi-Z sector's extra decks are never torn down/pooled once
			// the mission ends.
			GLOB.mission_spawned_zs |= sector_marker.map_z
			to_chat(accepter, SPAN_NOTICE("Mission sector located and prepared."))
		var/datum/mission_instance/instance = new()
		instance.template_id = template_id
		instance.mission_type = tmpl["mission_type"]
		instance.accepter_ckey = accepter.ckey
		instance.accepter_mob = accepter
		instance.sector_zs = sector_marker.map_z.Copy()
		instance.kill_mob_path = tmpl["kill_mob_path"]
		instance.kill_preset_id = tmpl["kill_preset_id"]
		instance.remaining_kills = tmpl["kill_count"]
		instance.reward = tmpl["reward"]
		tmpl["instance"] = instance
		instance.start_watching()

	tmpl["current_accepter_ckey"] = accepter.ckey
	return TRUE

/**
 * Abandons a claimed mission, freeing the slot. No refund -- nothing is
 * escrowed for missions, unlike bounties. Also kicks off a cleanup attempt
 * for the mission's sector (if it was auto-generated) -- otherwise an
 * abandoned kill mission would permanently hold its cap slot forever.
 */
/proc/abandon_mission(template_id)
	var/list/tmpl = get_mission_template(template_id)
	if(!tmpl || !tmpl["current_accepter_ckey"])
		return FALSE
	var/datum/mission_instance/instance = tmpl["instance"]
	var/list/sector_zs = list()
	var/mob/notify_mob = instance?.accepter_mob
	if(instance)
		sector_zs = instance.sector_zs.Copy()
		qdel(instance)
	tmpl["instance"] = null
	tmpl["current_accepter_ckey"] = null
	for(var/z in sector_zs)
		_try_cleanup_mission_sector(z, notify_mob)
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

#ifdef ENABLE_KILL_MISSIONS
/**
 * Completes a kill mission for accepter -- requires every target already
 * dead (instance.objective_complete) AND accepter no longer on any Z
 * belonging to the mission's sector (must leave before turning in -- same
 * reasoning as why you can't unload a Z you're still standing on). Pays the
 * reward, frees the slot, and kicks off a cleanup attempt for the sector if
 * this system auto-generated it. Returns TRUE on success.
 */
/proc/turn_in_kill_mission(template_id, mob/living/carbon/human/accepter)
	var/list/tmpl = get_mission_template(template_id)
	if(!tmpl || tmpl["mission_type"] != "kill" || tmpl["current_accepter_ckey"] != accepter.ckey)
		return FALSE
	var/datum/mission_instance/instance = tmpl["instance"]
	if(!istype(instance) || !instance.objective_complete)
		return FALSE
	if(GET_Z(accepter) in instance.sector_zs)
		return FALSE

	var/datum/money_account/account = SSeconomy.get_account_by_ckey(accepter.ckey)
	if(account)
		account.adjust_money(tmpl["reward"])

	var/list/sector_zs = instance.sector_zs.Copy()
	tmpl["current_accepter_ckey"] = null
	tmpl["instance"] = null
	qdel(instance)

	for(var/z in sector_zs)
		_try_cleanup_mission_sector(z, accepter)

	return TRUE
#endif

/**
 * Completes a visit mission for accepter -- requires having already reached
 * the target sector (instance.objective_complete, set the moment
 * check_sector_arrival() sees them arrive) AND no longer on any Z belonging
 * to the mission's sector, same leave-before-turning-in shape as
 * turn_in_kill_mission(). Pays the reward, frees the slot, and kicks off a
 * cleanup attempt for the sector if this system auto-generated it. Returns
 * TRUE on success.
 */
/proc/turn_in_visit_mission(template_id, mob/living/carbon/human/accepter)
	var/list/tmpl = get_mission_template(template_id)
	if(!tmpl || tmpl["mission_type"] != "visit" || tmpl["current_accepter_ckey"] != accepter.ckey)
		return FALSE
	var/datum/mission_instance/instance = tmpl["instance"]
	if(!istype(instance) || !instance.objective_complete)
		return FALSE
	if(GET_Z(accepter) in instance.sector_zs)
		return FALSE

	var/datum/money_account/account = SSeconomy.get_account_by_ckey(accepter.ckey)
	if(account)
		account.adjust_money(tmpl["reward"])

	var/list/sector_zs = instance.sector_zs.Copy()
	tmpl["current_accepter_ckey"] = null
	tmpl["instance"] = null
	qdel(instance)

	for(var/z in sector_zs)
		_try_cleanup_mission_sector(z, accepter)

	return TRUE

/**
 * Attempts to despawn a mission-auto-generated sector (z in
 * GLOB.mission_spawned_zs) once its mission is turned in/abandoned -- only
 * if no one is still on it and no other currently-active mission instance
 * still targets it. If either check fails, self-reschedules a retry instead
 * of giving up -- eventually the accepter (and everyone else) leaves. Never
 * touches sites this system didn't spawn (admin-generated/pinned/RNG
 * dynamic sites are never auto-torn-down). notify_mob (optional, the
 * accepter who triggered this) is told once the sector actually comes down
 * -- this can be a while after the retry loop starts, so it's threaded
 * through every rescheduled retry rather than just the first attempt.
 */
/proc/_try_cleanup_mission_sector(z, mob/notify_mob)
	if(!(z in GLOB.mission_spawned_zs))
		return
	if(zlevel_has_players(z))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_try_cleanup_mission_sector), z, notify_mob), MISSION_CLEANUP_RETRY_DELAY)
		return
	if(mission_instance_targets_z(z))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_try_cleanup_mission_sector), z, notify_mob), MISSION_CLEANUP_RETRY_DELAY)
		return

	GLOB.mission_spawned_zs -= z
	_despawn_away_site_z(z)
	if(notify_mob && !QDELETED(notify_mob) && notify_mob.client)
		to_chat(notify_mob, SPAN_NOTICE("The mission sector has been cleared and removed."))

// ============================================================
// KILL MISSION RUNTIME INSTANCE
// ============================================================

/// Tracks one active kill-mission claim: watches the accepter's mob for
/// arrival at the target sector, spawns the kill-mobs once there, and marks
/// itself objective_complete when the last one dies -- payout and cleanup
/// only happen via turn_in_kill_mission(), once the accepter has left the
/// sector. One instance per active kill-mission claim.
/datum/mission_instance
	var/template_id
	var/mission_type
	var/accepter_ckey
	var/mob/accepter_mob
	var/list/sector_zs = list()
	var/kill_mob_path
	/// If set, overrides kill_mob_path -- spawns via
	/// spawn_hostile_npc_from_preset() (persistence_hostile_npcs.dm) instead
	/// of a bare `new kill_mob_path(...)`, so admins can equip kill-mission
	/// targets with a real, tuned hostile NPC preset.
	var/kill_preset_id
	var/remaining_kills = 0
	var/reward = 0
	var/list/spawned_mobs = list()
	var/spawned = FALSE
	var/objective_complete = FALSE

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

	if(mission_type == "visit")
		objective_complete = TRUE
		if(accepter_mob.client)
			to_chat(accepter_mob, SPAN_GOOD("You've reached the mission site -- turn the mission in to collect payment."))
		return

#ifdef ENABLE_KILL_MISSIONS
	var/mob_type = text2path(kill_mob_path)
	var/allow_space = mob_type && ispath(mob_type, /mob/living/simple_animal/hostile/carp)

	var/spawn_z = GET_Z(accepter_mob)
	for(var/i in 1 to remaining_kills)
		var/turf/spawn_turf = find_mission_spawn_turf(spawn_z, allow_space)
		if(!spawn_turf)
			continue
		var/mob/living/new_mob
		if(kill_preset_id)
			new_mob = spawn_hostile_npc_from_preset(kill_preset_id, spawn_turf)
		else
			new_mob = new kill_mob_path(spawn_turf)
		if(!new_mob)
			continue
		spawned_mobs += new_mob
		GLOB.death_event.register(new_mob, src, PROC_REF(on_kill_mob_died))

	if(accepter_mob.client)
		to_chat(accepter_mob, SPAN_DANGER("Hostiles detected -- mission targets have arrived."))
#endif

/datum/mission_instance/proc/on_kill_mob_died(mob/dead_mob)
	GLOB.death_event.unregister(dead_mob, src, PROC_REF(on_kill_mob_died))
	spawned_mobs -= dead_mob
	remaining_kills--
	if(remaining_kills <= 0 && !objective_complete)
		objective_complete = TRUE
		var/client/C = GLOB.directory[accepter_ckey]
		if(C?.mob)
			to_chat(C.mob, SPAN_GOOD("All mission targets eliminated -- leave the sector and turn the mission in to collect payment."))

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
	set category = "Persistence.Away Sites & Missions"
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
			var/list/type_choices = list("fetch", "visit")
#ifdef ENABLE_KILL_MISSIONS
			type_choices += "kill"
#endif
			var/mission_type = tgui_input_list(usr, "Mission type:", "Add Mission", type_choices)
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
			var/kill_preset_id = null
			var/sector_template_id = null

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
#ifdef ENABLE_KILL_MISSIONS
			else if(mission_type == "kill")
				var/target_kind = tgui_input_list(usr, "Kill target:", "Add Mission", list("Hostile NPC preset", "Raw mob type path"))
				if(!target_kind)
					continue
				if(target_kind == "Hostile NPC preset")
					if(!length(GLOB.hostile_npc_presets))
						to_chat(usr, SPAN_WARNING("No hostile NPC presets exist -- create one via 'Manage Hostile NPC Presets' first."))
						continue
					var/list/preset_options = list()
					for(var/list/preset in GLOB.hostile_npc_presets)
						if(preset["enabled"])
							preset_options["#[preset["id"]] [preset["name"]]"] = preset
					var/preset_pick = tgui_input_list(usr, "Which preset?", "Add Mission", preset_options)
					if(!preset_pick)
						continue
					kill_preset_id = preset_options[preset_pick]["id"]
					kill_mob_path = "[/mob/living/carbon/human/npc/hostile]"
				else
					var/typed_path = tgui_input_text(usr, "Hostile mob type path to kill (e.g. /mob/living/simple_animal/hostile/carp):", "Add Mission", "", max_length = 128)
					var/path = text2path(typed_path)
					if(!path || !(ispath(path, /mob/living/simple_animal/hostile) || ispath(path, /mob/living/carbon/human/npc/hostile)))
						to_chat(usr, SPAN_WARNING("'[typed_path]' is not a valid hostile mob type -- it must be a /mob/living/simple_animal/hostile or /mob/living/carbon/human/npc/hostile subtype. A plain human/player-type mob has no combat AI and will never attack."))
						continue
					kill_mob_path = "[path]"
				kill_count = tgui_input_number(usr, "How many to kill:", "Add Mission", 1, 100, 1)
				if(isnull(kill_count))
					continue
				// Away-site TEMPLATE, not a specific instance -- a live instance
				// doesn't need to exist yet, one is auto-generated on demand
				// (up to MISSION_AUTOGEN_SECTOR_LIMIT) when the mission's
				// accepted. Nullsec-only is enforced at that point too.
				var/tmpl_pick = tgui_input_list(usr, "Target away-site template:", "Add Mission", SSmapping.away_sites_templates)
				if(!tmpl_pick)
					continue
				var/datum/map_template/ruin/away_site/target_site = SSmapping.away_sites_templates[tmpl_pick]
				if(!target_site)
					continue
				sector_template_id = target_site.id
#endif
			else if(mission_type == "visit")
				// Same away-site TEMPLATE targeting as kill missions (see
				// comment above/find_mission_sector()) -- just no mob path/
				// count, since the objective is reaching the site, not
				// fighting anything there.
				var/tmpl_pick = tgui_input_list(usr, "Target away-site template:", "Add Mission", SSmapping.away_sites_templates)
				if(!tmpl_pick)
					continue
				var/datum/map_template/ruin/away_site/target_site = SSmapping.away_sites_templates[tmpl_pick]
				if(!target_site)
					continue
				sector_template_id = target_site.id

			var/datum/db_query/q = SSdbcore.NewQuery(
				{"INSERT INTO ss13_missions (map_path, mission_type, title, description, fetch_item_path, fetch_count, kill_mob_path, kill_count, sector_template_id, reward, enabled, kill_preset_id)
				VALUES (:mp, :mt, :title, :desc, :fip, :fc, :kmp, :kc, :stid, :reward, 1, :kpid)"},
				list(
					"mp" = "[SSatlas.current_map.path]", "mt" = mission_type, "title" = title, "desc" = (description != "" ? description : null),
					"fip" = fetch_item_path, "fc" = fetch_count, "kmp" = kill_mob_path, "kc" = kill_count, "stid" = sector_template_id, "reward" = reward,
					"kpid" = kill_preset_id
				)
			)
			q.Execute()
			SSpersistence.databaseCheckQueryResult(q, "manage_missions add")
			var/new_id = text2num(q.last_insert_id)
			qdel(q)

			GLOB.mission_templates += list(list(
				"id" = new_id, "mission_type" = mission_type, "title" = title, "description" = description,
				"fetch_item_path" = fetch_item_path, "fetch_count" = fetch_count, "kill_mob_path" = kill_mob_path,
				"kill_count" = kill_count, "sector_template_id" = sector_template_id, "reward" = reward, "enabled" = TRUE,
				"kill_preset_id" = kill_preset_id, "current_accepter_ckey" = null, "instance" = null
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
