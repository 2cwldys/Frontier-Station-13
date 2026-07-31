/*
 * Guard Beacon
 * A leaner sibling of faction_barracks.dm -- once wrenched down, tagged to a
 * real faction, and powered on, maintains exactly ONE hostile NPC "soldier"
 * (an admin-authored preset, persistence_hostile_npcs.dm) standing motionless
 * at its own position, facing a direction set from its own TGUI. Unlike a
 * barracks soldier (which wanders patrol_anchor_turf) or a commander's beacon
 * follower (which chases its owner), a guard-beacon soldier gets
 * guard_post_turf/guard_facing_dir set instead (hostile_npc.dm) -- it walks
 * straight back to its exact post (no wandering) if ever bumped/pushed/
 * thrown off it, and holds its facing once there. It still fights anything
 * that gets close, same as any other hostile_npc -- "just stand there" only
 * applies to idle behavior.
 *
 * The beacon itself is invisible (alpha = 0, density = FALSE) -- the whole
 * point is an unseen spawn marker, so the standing guard reads as a natural
 * sentry rather than an obviously-spawned mob tied to a visible prop. Still
 * fully interactable (mouse_opacity untouched) to reopen its TGUI.
 *
 * Same reboot-persistence shape as faction_barracks.dm (preset/hostility/
 * faction tag/active survive; active_mobs does not -- a dead server means
 * that reference is gone regardless). Facing doesn't need its own entry --
 * dir is already saved/restored for free by the generic tracked-objects
 * system, and reactivation only actually spawns the guard a couple seconds
 * later via the async start_maintaining() loop, well after dir is restored.
 *
 * Deactivating (power off or Destroy()) immediately dismisses the current
 * guard too (fading portal + sparks VFX, the same as the explicit "Dismiss"
 * action, not a silent qdel) -- powering back on posts a fresh guard.
 */
/obj/structure/machinery/guard_beacon
	name = "guard beacon"
	desc = "A concealed emitter that maintains an unseen post."
	icon = 'icons/obj/machinery/telecomms.dmi'
	icon_state = "bspacerelay"
	alpha = 0 // Invisible -- the standing guard is the only visible thing.
	anchored = FALSE // spawns loose on purchase -- must be wrenched down before it can activate
	density = FALSE // invisible AND dense would be a nasty invisible-wall trap
	maxhealth = OBJECT_HEALTH_HIGH
	idle_power_usage = 0
	active_power_usage = 0

	var/active = FALSE
	/// Faction tagger compatible var -- "" (personal/untagged), "public", or
	/// a real faction_uid. Activation refuses unless this resolves to a
	/// genuine, currently-existing faction.
	var/persistent_network = ""
	/// Which hostile_npc_presets row this beacon spawns -- freely re-editable
	/// at any time; changing it only affects the NEXT spawn cycle.
	var/preset_id
	var/list/active_mobs = list()
	var/max_active_mobs = 1
	/// Replenish cooldown range, in seconds -- deliberately not instant.
	var/min_spawn_cooldown = 30
	var/max_spawn_cooldown = 90
	var/spawning_enabled = FALSE
	/// "hostile" (default) -- the guard proactively attacks non-faction
	/// targets. "passive" -- never initiates combat at all.
	var/hostility_mode = "hostile"

/obj/structure/machinery/guard_beacon/Initialize()
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/// Reuses dismiss_soldiers() (VFX + qdel + list cleanup) -- see
/// faction_barracks.dm's identical reasoning.
/obj/structure/machinery/guard_beacon/Destroy()
	spawning_enabled = FALSE
	dismiss_soldiers(null)
	return ..()

// ------- Faction tagger compatibility -------

/obj/structure/machinery/guard_beacon/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/guard_beacon/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/guard_beacon/faction_tagger_set(new_uid, mob/user)
	if(active)
		to_chat(user, SPAN_WARNING("Power down \the [src] before retagging it."))
		return FALSE
	persistent_network = new_uid || ""
	return TRUE

/// TRUE only if persistent_network resolves to a real, currently-existing
/// faction -- personal (""), "public", and crew-tagged states are all
/// explicitly rejected, matching faction_barracks.dm's own gate.
/obj/structure/machinery/guard_beacon/proc/_faction_ready()
	var/uid = normalize_faction_uid(persistent_network)
	if(!uid || uid == "public")
		return FALSE
	return islist(GLOB.persistence_faction_cache) && (uid in GLOB.persistence_faction_cache)

// ------- Reboot persistence -- see faction_barracks.dm's identical block for
// the full reasoning (auto-registered for free by structures.dm's
// Initialize(), this just fills in the config the base persistent_objects_
// get_content() doesn't). active_mobs is deliberately NOT restored. -------

/obj/structure/machinery/guard_beacon/persistent_objects_get_content()
	var/list/content = ..()
	content["preset_id"] = preset_id
	content["hostility_mode"] = hostility_mode
	content["persistent_network"] = persistent_network
	content["active"] = active
	return content

/obj/structure/machinery/guard_beacon/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["preset_id"]))
		preset_id = content["preset_id"]
	if(!isnull(content["hostility_mode"]))
		hostility_mode = content["hostility_mode"]
	if(!isnull(content["persistent_network"]))
		persistent_network = content["persistent_network"]
	// __anchored is only applied by the caller AFTER this proc returns
	// (persistence_objects.dm) -- anchored itself isn't trustworthy yet here.
	var/was_anchored = !isnull(content["__anchored"]) ? content["__anchored"] : anchored
	// Deliberately not re-checking _faction_ready() here -- process()'s
	// existing periodic check force-deactivates it within its own next tick
	// if the faction turned out to be gone/invalid by boot.
	if(content["active"] && was_anchored && preset_id)
		_set_active(TRUE)

/obj/structure/machinery/guard_beacon/proc/toggle_active(mob/user)
	if(!active)
		if(!anchored)
			to_chat(user, SPAN_WARNING("\The [src] must be anchored before it can be activated."))
			return
		if(!_faction_ready())
			to_chat(user, SPAN_WARNING("\The [src] must be tagged to a real faction before it can be activated -- personal, crew, and public networks are refused."))
			return
		if(!preset_id)
			to_chat(user, SPAN_WARNING("\The [src] has no soldier preset configured -- set one first."))
			return
	_set_active(!active, user)

/obj/structure/machinery/guard_beacon/proc/_set_active(new_state, mob/user)
	if(active == new_state)
		return
	active = new_state
	if(active)
		if(user)
			to_chat(user, SPAN_NOTICE("\The [src] powers up and takes up its post."))
		start_maintaining()
	else
		spawning_enabled = FALSE
		if(user)
			to_chat(user, SPAN_NOTICE("\The [src] powers down."))
		dismiss_soldiers(user)

/// Force-deactivates if anchor or faction-tag prerequisites are lost
/// mid-operation -- same choke-point precedent as faction_barracks.dm.
/obj/structure/machinery/guard_beacon/process()
	if(active && (!anchored || !_faction_ready()))
		_set_active(FALSE)

/// The maintenance loop -- faction_barracks.dm's exact shape, just capped at
/// 1 instead of 5.
/obj/structure/machinery/guard_beacon/proc/start_maintaining()
	if(spawning_enabled)
		return
	spawning_enabled = TRUE
	spawn()
		// A reboot-restored beacon (persistent_objects_apply_content(), called
		// mid-objectsInitialize()) can call this well before
		// SSpersistence.Initialize() has gotten to factionInitialize() --
		// spawning too early left the restored guard's gear untinted, since
		// get_faction_color() (persistence_faction_tagger.dm) silently returns
		// null until GLOB.persistence_faction_cache is populated. Waiting here
		// costs nothing during normal (already-booted) activation, since
		// persistence_ready is already TRUE by then.
		while(!GLOB.persistence_ready && spawning_enabled && src)
			sleep(1 SECOND)
		while(spawning_enabled && active && src)
			for(var/i = length(active_mobs); i >= 1; i--)
				var/mob/living/M = active_mobs[i]
				if(!M || QDELETED(M) || M.stat == DEAD)
					active_mobs.Cut(i, i + 1)
			if(length(active_mobs) < max_active_mobs)
				spawn_soldier()
				sleep(2 SECONDS)
				continue
			sleep(rand(min_spawn_cooldown, max_spawn_cooldown) SECONDS)

/// Unlike faction_barracks.dm's spawn_soldier(), never sets
/// patrol_anchor_turf -- that's the entire mechanism keeping this soldier
/// from wandering. guard_facing_dir/dir instead lock it to face wherever
/// this beacon is currently set to (see set_facing()).
/obj/structure/machinery/guard_beacon/proc/spawn_soldier()
	if(!preset_id)
		return
	if(!hostile_npc_preset_allowed_for_faction(get_hostile_npc_preset(preset_id), normalize_faction_uid(persistent_network)))
		return
	var/turf/T = get_turf(src)
	if(!T)
		return
	var/mob/living/carbon/human/npc/hostile/H = spawn_hostile_npc_from_preset(preset_id, T, persistent_network)
	if(!H)
		return
	H.passive_mode = (hostility_mode == "passive")
	H.guard_post_turf = T
	H.guard_facing_dir = dir
	H.dir = dir
	active_mobs += H
	RegisterSignal(H, COMSIG_QDELETING, PROC_REF(soldier_died))

/obj/structure/machinery/guard_beacon/proc/soldier_died(mob/living/mob_ref)
	SIGNAL_HANDLER
	UnregisterSignal(mob_ref, COMSIG_QDELETING)
	active_mobs -= mob_ref

/// Orders the current guard to either proactively attack non-faction
/// targets ("hostile", the default) or never initiate combat at all
/// ("passive") -- a future replacement spawned while this mode is active
/// inherits it too (see spawn_soldier()). Also the entry point the
/// commander's beacon's bulk same-faction toggle calls directly (user may be
/// null in that case, matching faction_barracks.dm's own tolerant style).
/obj/structure/machinery/guard_beacon/proc/set_hostility_mode(mode, mob/user)
	if(hostility_mode == mode)
		return
	hostility_mode = mode
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		if(!QDELETED(M))
			M.passive_mode = (mode == "passive")
	if(user)
		to_chat(user, SPAN_NOTICE("\The [src]'s guard will now [mode == "passive" ? "hold their fire unless ordered." : "engage non-faction targets on sight."]"))

/// Rotates the beacon to face new_dir and immediately turns its current
/// guard (if any) to match -- future guards inherit it too (spawn_soldier()).
/obj/structure/machinery/guard_beacon/proc/set_facing(new_dir, mob/user)
	dir = new_dir
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		if(!QDELETED(M))
			M.guard_facing_dir = new_dir
			M.dir = new_dir
	if(user)
		to_chat(user, SPAN_NOTICE("\The [src] will now face [dir2text(new_dir)]."))

/// Dismisses the current guard (fading portal + sparks VFX, not a silent
/// qdel) -- called both by the explicit "Dismiss" UI button and
/// automatically whenever the beacon powers off or is destroyed (see
/// _set_active()/Destroy()). Safe to call with an empty active_mobs list.
/obj/structure/machinery/guard_beacon/proc/dismiss_soldiers(mob/user)
	for(var/mob/m in active_mobs)
		UnregisterSignal(m, COMSIG_QDELETING)
		if(!QDELETED(m))
			var/turf/origin = get_turf(m)
			if(origin)
				new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
				spark(origin, 3, GLOB.alldirs)
			qdel(m)
	active_mobs.Cut()
	if(user)
		to_chat(user, SPAN_NOTICE("\The [src]'s guard has been dismissed."))

/obj/structure/machinery/guard_beacon/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		if(anchored && active)
			to_chat(user, SPAN_WARNING("Power down \the [src] before unwrenching it."))
			return TRUE
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, SPAN_NOTICE("You [anchored ? "wrench \the [src] to" : "unwrench \the [src] from"] the floor."))
		return TRUE
	return ..()

/obj/structure/machinery/guard_beacon/attack_hand(mob/user)
	if(..())
		return
	ui_interact(user)

/obj/structure/machinery/guard_beacon/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GuardBeacon", "Guard Beacon", 380, 480)
		ui.open()

/obj/structure/machinery/guard_beacon/ui_data(mob/user)
	var/list/data = list()
	data["active"] = active
	data["anchored"] = anchored
	data["faction_uid"] = persistent_network
	data["faction_name"] = _faction_ready() ? get_faction_name(persistent_network) : null
	data["faction_ready"] = _faction_ready()
	data["can_configure"] = can_configure_faction_shackle(user, normalize_faction_uid(persistent_network), 1)
	data["soldier_count"] = length(active_mobs)
	data["max_active_mobs"] = max_active_mobs
	data["hostility_mode"] = hostility_mode
	data["facing"] = dir2text(dir)
	data["facing_options"] = list("NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST")
	var/list/preset = get_hostile_npc_preset(preset_id)
	data["preset_name"] = preset ? preset["name"] : null
	return data

/obj/structure/machinery/guard_beacon/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	if(!can_configure_faction_shackle(user, normalize_faction_uid(persistent_network), 1))
		to_chat(user, SPAN_WARNING("You don't have permission to configure this."))
		return
	switch(action)
		if("toggle")
			toggle_active(user)
			. = TRUE
		if("set_preset")
			var/list/available = get_hostile_npc_presets_for_faction(normalize_faction_uid(persistent_network))
			if(!length(available))
				to_chat(user, SPAN_WARNING("No hostile NPC presets are available to your faction -- either none exist yet, or the only ones that do are exclusive to a different faction."))
				return TRUE
			var/list/preset_options = list()
			for(var/list/preset in available)
				preset_options["#[preset["id"]] [preset["name"]]"] = preset["id"]
			var/pick = tgui_input_list(user, "Soldier preset:", "Guard Beacon", preset_options)
			if(!pick)
				return TRUE
			preset_id = preset_options[pick]
			to_chat(user, SPAN_GOOD("Soldier preset set to '[pick]'."))
			. = TRUE
		if("dismiss")
			dismiss_soldiers(user)
			. = TRUE
		if("set_hostile")
			set_hostility_mode("hostile", user)
			. = TRUE
		if("set_passive")
			set_hostility_mode("passive", user)
			. = TRUE
		if("set_facing")
			var/new_dir = text2dir(params["dir"])
			if(!new_dir)
				return TRUE
			set_facing(new_dir, user)
			. = TRUE
