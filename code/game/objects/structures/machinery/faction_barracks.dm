/*
 * Faction Barracks
 * A cargo-purchasable machine that, once wrenched down, tagged to a real
 * faction, and powered on, maintains up to 5 hostile NPC "soldiers" (an
 * admin-authored preset, persistence_hostile_npcs.dm) around it -- topping
 * losses back up over time (not instantly) whenever under the cap. Refuses
 * to activate unless tagged to a genuine, existing faction -- personal,
 * crew, and public networks are all explicitly rejected, not silently
 * treated as "no faction."
 *
 * Deliberately independent of area/APC power (idle/active_power_usage = 0,
 * never checks stat & NOPOWER) -- same reasoning as ship_cloaking_device.dm:
 * its own anchored+tag+active state is the only gate, so it works in places
 * with no actual power grid at all. No fuel/consumable either -- confirmed
 * with the user as a binary anchor+power+tag gate only.
 *
 * Deactivating (power off or Destroy()) immediately dismisses any current
 * soldiers too (fading portal + sparks VFX, the same as the explicit
 * "Dismiss Soldiers" action, not a silent qdel) -- powering back on starts
 * fresh from zero.
 */
/obj/structure/machinery/faction_barracks
	name = "faction barracks"
	desc = "A prefab garrison module that trains and re-arms soldiers for whichever faction claims it."
	icon = 'icons/obj/machinery/telecomms.dmi'
	icon_state = "bspacerelay"
	anchored = FALSE // spawns loose on purchase -- must be wrenched down before it can activate
	density = TRUE
	maxhealth = OBJECT_HEALTH_HIGH
	idle_power_usage = 0
	active_power_usage = 0

	var/active = FALSE
	/// Faction tagger compatible var -- "" (personal/untagged), "public", or
	/// a real faction_uid. Activation refuses unless this resolves to a
	/// genuine, currently-existing faction.
	var/persistent_network = ""
	/// Which hostile_npc_presets row this barracks spawns -- freely
	/// re-editable at any time; changing it only affects the NEXT spawn
	/// cycle, existing soldiers are untouched.
	var/preset_id
	var/list/active_mobs = list()
	var/max_active_mobs = 5
	/// Replenish cooldown range, in seconds -- deliberately not instant.
	var/min_spawn_cooldown = 30
	var/max_spawn_cooldown = 90
	var/spawning_enabled = FALSE
	/// "hostile" (default) -- soldiers proactively attack non-faction
	/// targets. "passive" -- soldiers never initiate combat at all.
	var/hostility_mode = "hostile"

/obj/structure/machinery/faction_barracks/Initialize()
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/// Reuses dismiss_soldiers() (VFX + qdel + list cleanup) rather than just
/// dropping the tracking list -- previously this only forgot about
/// active_mobs without actually removing them, so admin-deleting (or any
/// other destruction of) the barracks left its soldiers wandering around
/// with no way to dismiss them anymore.
/obj/structure/machinery/faction_barracks/Destroy()
	spawning_enabled = FALSE
	dismiss_soldiers(null)
	return ..()

// ------- Faction tagger compatibility -------

/obj/structure/machinery/faction_barracks/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/faction_barracks/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/faction_barracks/faction_tagger_set(new_uid, mob/user)
	if(active)
		to_chat(user, SPAN_WARNING("Power down \the [src] before retagging it."))
		return FALSE
	persistent_network = new_uid || ""
	update_icon()
	return TRUE

/// TRUE only if persistent_network resolves to a real, currently-existing
/// faction -- personal (""), "public", and crew-tagged states are all
/// explicitly rejected, matching the user's own requirement that this
/// machine works for a real faction only.
/obj/structure/machinery/faction_barracks/proc/_faction_ready()
	var/uid = normalize_faction_uid(persistent_network)
	if(!uid || uid == "public")
		return FALSE
	return islist(GLOB.persistence_faction_cache) && (uid in GLOB.persistence_faction_cache)

// ------- Reboot persistence -- every cargo-spawned (non-mapload) structure
// already auto-registers into the generic tracked-objects system for free
// (structures.dm's /obj/structure/Initialize()), which is why position/
// anchored already survive a reboot -- this just fills in the rest of the
// config the default persistent_objects_get_content() (objs.dm) doesn't.
// active_mobs is deliberately NOT restored, matching this machine's own
// existing philosophy (soldiers aren't persisted even across a normal
// deactivate/dismiss cycle -- only role/config is durable). -------

/obj/structure/machinery/faction_barracks/persistent_objects_get_content()
	var/list/content = ..()
	content["preset_id"] = preset_id
	content["hostility_mode"] = hostility_mode
	content["persistent_network"] = persistent_network
	content["active"] = active
	return content

/obj/structure/machinery/faction_barracks/persistent_objects_apply_content(content, x, y, z)
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
	// (persistence_objects.dm's objectsApplyTrackContent()) -- anchored
	// itself isn't trustworthy yet here, so read the raw saved value instead.
	var/was_anchored = !isnull(content["__anchored"]) ? content["__anchored"] : anchored
	// Deliberately not re-checking _faction_ready() here -- if the faction
	// turned out to be gone/invalid by boot, process()'s existing periodic
	// check force-deactivates it within its own next tick anyway, the same
	// self-healing path a mid-round faction disband already uses.
	if(content["active"] && was_anchored && preset_id)
		_set_active(TRUE)

/obj/structure/machinery/faction_barracks/proc/toggle_active(mob/user)
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

/obj/structure/machinery/faction_barracks/proc/_set_active(new_state, mob/user)
	if(active == new_state)
		return
	active = new_state
	if(active)
		visible_message(SPAN_NOTICE("\The [src] powers up and begins training soldiers."))
		start_maintaining()
	else
		spawning_enabled = FALSE
		visible_message(SPAN_NOTICE("\The [src] powers down."))
		dismiss_soldiers(user)
	update_icon()

/// Force-deactivates if anchor or faction-tag prerequisites are lost mid-
/// operation -- same single choke-point precedent as
/// ship_cloaking_device.dm's own process()-driven forced-off.
/obj/structure/machinery/faction_barracks/process()
	if(active && (!anchored || !_faction_ready()))
		_set_active(FALSE)

/// The maintenance loop -- fauna_spawner.start_spawning()'s exact shape
/// (mob_spawner.dm), with one deliberate departure: the long randomized
/// cooldown only applies once already AT cap (gating how fast a COMBAT
/// LOSS gets replaced). While still under cap -- e.g. right after first
/// activation -- it fills up quickly (a short fixed stagger between each,
/// so multiple soldiers don't pop in the same instant), since there's no
/// "not immediately" concern for simply finishing the initial deployment.
/obj/structure/machinery/faction_barracks/proc/start_maintaining()
	if(spawning_enabled)
		return
	spawning_enabled = TRUE
	spawn()
		// A reboot-restored barracks (persistent_objects_apply_content(),
		// called mid-objectsInitialize()) can call this well before
		// SSpersistence.Initialize() has gotten to factionInitialize() --
		// spawning too early left the very first restored soldier's gear
		// untinted, since get_faction_color() (persistence_faction_tagger.dm)
		// silently returns null until GLOB.persistence_faction_cache is
		// populated. Waiting here costs nothing during normal (already-booted)
		// activation, since persistence_ready is already TRUE by then.
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

/obj/structure/machinery/faction_barracks/proc/spawn_soldier()
	if(!preset_id)
		return
	// Catches a barracks retagged to a different faction after its preset
	// was set -- a preset exclusive to the OLD faction stops working rather
	// than silently continuing to spawn for whoever holds this barracks now.
	if(!hostile_npc_preset_allowed_for_faction(get_hostile_npc_preset(preset_id), normalize_faction_uid(persistent_network)))
		return
	var/turf/T = get_turf(src)
	if(!T)
		return
	var/mob/living/carbon/human/npc/hostile/H = spawn_hostile_npc_from_preset(preset_id, T, persistent_network)
	if(!H)
		return
	H.passive_mode = (hostility_mode == "passive")
	H.patrol_anchor_turf = T
	active_mobs += H
	RegisterSignal(H, COMSIG_QDELETING, PROC_REF(soldier_died))

/obj/structure/machinery/faction_barracks/proc/soldier_died(mob/living/mob_ref)
	SIGNAL_HANDLER
	UnregisterSignal(mob_ref, COMSIG_QDELETING)
	active_mobs -= mob_ref

/// Orders current soldiers to either proactively attack non-faction
/// targets ("hostile", the default) or never initiate combat at all
/// ("passive") -- future soldiers spawned while this mode is active
/// inherit it too (see spawn_soldier()).
/obj/structure/machinery/faction_barracks/proc/set_hostility_mode(mode, mob/user)
	if(hostility_mode == mode)
		return
	hostility_mode = mode
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		if(!QDELETED(M))
			M.passive_mode = (mode == "passive")
	to_chat(user, SPAN_NOTICE("\The [src]'s soldiers will now [mode == "passive" ? "hold their fire unless ordered." : "engage non-faction targets on sight."]"))

/// Dismisses every current soldier (instant phase-teleport visual/sound, not
/// a silent qdel) -- called both by the explicit "Dismiss Soldiers" UI button
/// and automatically whenever the barracks powers off or is destroyed (see
/// _set_active()/Destroy()). Safe to call with an empty active_mobs list.
/obj/structure/machinery/faction_barracks/proc/dismiss_soldiers(mob/user)
	for(var/mob/m in active_mobs)
		UnregisterSignal(m, COMSIG_QDELETING)
		if(!QDELETED(m))
			// Same instant phase-teleport visual/sound (telepad_travel.dm)
			// commander_beacon.dm/guard_beacon.dm use -- not a silent qdel.
			var/turf/origin = get_turf(m)
			_telepad_phase_arrival(origin, m.dir)
			qdel(m)
	active_mobs.Cut()
	if(user)
		to_chat(user, SPAN_NOTICE("\The [src]'s soldiers have been dismissed."))

/obj/structure/machinery/faction_barracks/update_icon()
	set_light(active ? 2 : 0, 1)

/obj/structure/machinery/faction_barracks/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		if(anchored && active)
			to_chat(user, SPAN_WARNING("Power down \the [src] before unwrenching it."))
			return TRUE
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		user.visible_message(SPAN_NOTICE("[user] [anchored ? "wrenches" : "unwrenches"] \the [src] [anchored ? "to" : "from"] the floor."), \
			SPAN_NOTICE("You [anchored ? "wrench \the [src] to" : "unwrench \the [src] from"] the floor."))
		return TRUE
	return ..()

/obj/structure/machinery/faction_barracks/attack_hand(mob/user)
	if(..())
		return
	ui_interact(user)

/obj/structure/machinery/faction_barracks/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FactionBarracks", "Faction Barracks", 380, 480)
		ui.open()

/obj/structure/machinery/faction_barracks/ui_data(mob/user)
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
	var/list/preset = get_hostile_npc_preset(preset_id)
	data["preset_name"] = preset ? preset["name"] : null
	return data

/obj/structure/machinery/faction_barracks/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
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
			var/pick = tgui_input_list(user, "Soldier preset:", "Faction Barracks", preset_options)
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
