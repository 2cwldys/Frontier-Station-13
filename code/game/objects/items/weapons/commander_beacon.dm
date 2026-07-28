/*
 * Commander's Beacon
 * A personal, player-carried version of the faction barracks
 * (faction_barracks.dm) -- maintains up to 2 hostile NPC "soldiers" (an
 * admin-authored preset, persistence_hostile_npcs.dm) that follow and
 * protect whoever activated it, instead of guarding a fixed location.
 * Requires the user to actually be a member of a real, currently-existing
 * faction (employer_faction on their ID card, same bridge
 * portable_turret.dm already uses) -- refuses to activate otherwise, and
 * force-deactivates if they lose that membership mid-operation. That same
 * faction is passed down to the soldiers so they also treat the summoner's
 * faction-mates as friendly. The summoner themselves is never targeted,
 * via the commander mob-reference exemption already built into
 * hostile_npc.dm's targeting.
 *
 * Controlled via a TGUI window (attack_self() opens it, mirroring
 * faction_barracks.dm's ui_interact()/ui_data()/ui_act() shape): toggle
 * active, pick a preset, and order current+future followers to "Follow"
 * (the default -- close distance to the owner when idle) or "Hold
 * Position" (stay put when idle, but still fight anything they find --
 * see hostile_npc.dm's hold_position var). Also reachable via the mob's
 * action-button HUD row (action_button_name below) whenever it's on the
 * mob at all -- held, or worn in belt/pocket/suit storage (slot_flags
 * below) -- no need to draw it into a hand first. This is a separate,
 * additive access point only; normal click/pickup/attack_hand() behavior on
 * the item itself is completely untouched.
 *
 * Individual followers can also be given a one-off "go stand over there"
 * order: pick one from the soldier list in the TGUI itself (no verb-panel
 * hunting -- this used to be a hidden held-item verb, which players
 * reasonably never found), then click anywhere visible in the world (need
 * not be adjacent, and -- since the TGUI is reachable without holding the
 * item at all, per the action button above -- need not be holding the
 * beacon either). This is done via a one-shot COMSIG_MOB_CLICKON
 * registration on the commanding mob (_arm_destination_click()/
 * _on_destination_click() below), not an afterattack() override, since
 * afterattack() only ever fires for clicks made with this exact item
 * actively wielded -- which would silently break the destination step
 * whenever the beacon is worn instead of held. Deliberately NOT built on the
 * game's vanilla "Point To" verb/COMSIG_MOB_POINT either -- that verb
 * shares one 2.5-second cooldown per pointing mob regardless of target
 * (mob.dm's "point_verb_emote_cooldown"), which silently swallows the
 * second of two quick point actions and broke the intended fast
 * select-soldier-then-tap-turf workflow. This has no such cooldown, and
 * manually replicates the same visual feedback (add_point_filter() glow, a
 * fading ground decal/point marker) the vanilla verb would have given for
 * free.
 *
 * Optionally faction-taggable (persistent_network, same compatibility
 * interface faction_barracks.dm uses) -- if tagged, only members of that
 * SPECIFIC faction can activate it, regardless of who's currently holding
 * it or what preset is set. Untagged (the default) keeps the item usable
 * by whoever holds it, per their own personal faction -- tagging is purely
 * opt-in theft protection for an owner who wants their looted beacon to be
 * a dead brick in a rival's hands.
 */
/obj/item/commander_beacon
	name = "commander's beacon"
	desc = "A compact holographic emitter that rallies loyal soldiers to fight at your side."
	icon = 'icons/obj/item/hand_tele.dmi'
	icon_state = "hand_tele"
	item_state = "electronic"
	w_class = WEIGHT_CLASS_SMALL
	slot_flags = SLOT_BELT | SLOT_S_STORE
	origin_tech = list(TECH_MAGNET = 3, TECH_COMBAT = 4)
	// Adds a clickable icon to the mob's own action-button HUD row (the
	// "Hide Buttons"/"Show Buttons" toggle, alongside flashlight/helmet-light
	// style toggles) whenever this is on the mob (held OR worn in belt/
	// pocket/suit storage -- NOT buried inside a backpack/box). Clicking it
	// calls ui_action_click() -> attack_self() by default (items.dm), which
	// already opens this exact TGUI below -- no override needed. Completely
	// separate from, and doesn't touch, normal click/pickup/attack_hand()
	// interaction with the item itself.
	action_button_name = "Commander's Beacon"

	/// Which hostile_npc_presets row this beacon summons -- picked once by
	/// whoever first activates it, from the same admin-authored preset list
	/// the barracks machine uses.
	var/preset_id
	var/mob/living/owner
	var/list/active_mobs = list()
	var/max_active_mobs = 2
	/// Replenish cooldown range, in seconds -- deliberately not instant.
	var/min_spawn_cooldown = 30
	var/max_spawn_cooldown = 90
	var/spawning_enabled = FALSE
	/// "follow" (default) -- idle followers close distance to the owner.
	/// "hold" -- idle followers stay put wherever they currently are.
	var/stance_mode = "follow"
	/// "hostile" (default) -- followers proactively attack non-faction
	/// targets. "passive" -- followers never initiate combat at all.
	var/hostility_mode = "hostile"
	/// Which of active_mobs the owner most recently targeted via
	/// select_soldier -- the target of their next move-to-turf order.
	var/mob/living/carbon/human/npc/hostile/selected_soldier
	/// Mob currently armed with a one-shot COMSIG_MOB_CLICKON registration
	/// (see _arm_destination_click()) -- tracked separately from
	/// selected_soldier/owner so it can be reliably unregistered from the
	/// right mob even if a new soldier is selected, or this item is
	/// destroyed, before they actually click anywhere.
	var/mob/pending_click_user
	/// Faction tagger compatible var -- "" (personal/untagged) or a real
	/// faction_uid. When set, activation refuses for anyone not a member
	/// of that specific faction, regardless of what preset is set.
	var/persistent_network = ""
	/// world.time deadline before the "Fetch" button can be used again.
	var/fetch_cooldown_until = 0

/// Reuses dismiss_soldiers() (VFX + qdel + list/selection cleanup) rather
/// than just dropping the tracking list -- previously this only forgot
/// about active_mobs without actually removing them, so admin-deleting (or
/// any other destruction of) the beacon left its soldiers wandering around
/// with no commander and no way to dismiss them anymore.
/obj/item/commander_beacon/Destroy()
	spawning_enabled = FALSE
	owner = null
	_disarm_destination_click()
	dismiss_soldiers(null)
	return ..()

// ------- Faction tagger compatibility -------

/obj/item/commander_beacon/faction_tagger_compatible()
	return TRUE

/obj/item/commander_beacon/faction_tagger_get_uid()
	return persistent_network

/obj/item/commander_beacon/faction_tagger_set(new_uid, mob/user)
	if(spawning_enabled)
		to_chat(user, SPAN_WARNING("Deactivate \the [src] before retagging it."))
		return FALSE
	persistent_network = new_uid || ""
	return TRUE

/obj/item/commander_beacon/attack_self(mob/user)
	if(!istype(loc, /mob) || loc != user)
		return
	ui_interact(user)

/obj/item/commander_beacon/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "CommanderBeacon", "Commander's Beacon", 380, 500)
		ui.open()

/obj/item/commander_beacon/ui_data(mob/user)
	var/list/data = list()
	data["active"] = spawning_enabled
	data["stance_mode"] = stance_mode
	data["soldier_count"] = length(active_mobs)
	data["max_active_mobs"] = max_active_mobs
	data["faction_ready"] = _owner_faction_ready(user)
	data["hostility_mode"] = hostility_mode
	var/tagged_uid = normalize_faction_uid(persistent_network)
	data["tag_name"] = tagged_uid ? get_faction_name(tagged_uid) : null
	var/list/preset = get_hostile_npc_preset(preset_id)
	data["preset_name"] = preset ? preset["name"] : null
	var/list/soldiers = list()
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		soldiers += list(list(
			"ref"      = "\ref[M]",
			"name"     = M.name,
			"selected" = (M == selected_soldier)
		))
	data["soldiers"] = soldiers
	return data

/obj/item/commander_beacon/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/living/user = usr
	if(!istype(loc, /mob) || loc != user)
		return
	switch(action)
		if("toggle")
			if(spawning_enabled)
				// Only the deliberate button press dismisses -- deactivate()
				// is also called from dropped()/faction-loss, which should
				// keep leaving followers standing behind, per its own doc
				// comment.
				deactivate(user)
				dismiss_soldiers(user)
			else
				activate(user)
			. = TRUE
		if("set_preset")
			var/list/available = get_hostile_npc_presets_for_faction(_owner_faction_uid(user))
			if(!length(available))
				to_chat(user, SPAN_WARNING("No hostile NPC presets are available to your faction -- either none exist yet, or the only ones that do are exclusive to a different faction."))
				return TRUE
			var/list/preset_options = list()
			for(var/list/preset in available)
				preset_options["#[preset["id"]] [preset["name"]]"] = preset["id"]
			var/pick = tgui_input_list(user, "Soldier preset to summon:", "Commander's Beacon", preset_options)
			if(!pick)
				return TRUE
			preset_id = preset_options[pick]
			to_chat(user, SPAN_GOOD("Soldier preset set to '[pick]'."))
			. = TRUE
		if("set_follow")
			set_stance_mode("follow", user)
			. = TRUE
		if("set_hold")
			set_stance_mode("hold", user)
			. = TRUE
		if("dismiss")
			dismiss_soldiers(user)
			. = TRUE
		if("fetch")
			recall_stragglers(user)
			. = TRUE
		if("set_hostile")
			set_hostility_mode("hostile", user)
			. = TRUE
		if("set_passive")
			set_hostility_mode("passive", user)
			. = TRUE
		if("select_soldier")
			var/target_ref = params["ref"]
			if(selected_soldier && "\ref[selected_soldier]" == target_ref)
				selected_soldier = null
				_disarm_destination_click()
				to_chat(user, SPAN_NOTICE("You stand down -- no soldier is being individually commanded."))
				. = TRUE
				return
			for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
				if("\ref[M]" == target_ref)
					selected_soldier = M
					M.add_point_filter()
					_arm_destination_click(user)
					to_chat(user, SPAN_NOTICE("You single out [M] to command -- click a location anywhere visible to send them there."))
					break
			. = TRUE

/obj/item/commander_beacon/proc/activate(mob/living/user)
	if(spawning_enabled)
		return
	if(!preset_id)
		to_chat(user, SPAN_WARNING("\The [src] has no soldier preset set -- set one first."))
		return
	if(!_owner_faction_ready(user))
		to_chat(user, SPAN_WARNING("\The [src] refuses to activate -- you must be a member of a faction to command soldiers."))
		return
	var/tagged_uid = normalize_faction_uid(persistent_network)
	if(tagged_uid && _owner_faction_uid(user) != tagged_uid)
		to_chat(user, SPAN_WARNING("\The [src] refuses to respond -- it's keyed to a different faction."))
		return
	owner = user
	spawning_enabled = TRUE
	to_chat(user, SPAN_NOTICE("\The [src] activates, rallying your soldiers."))
	start_maintaining()

/obj/item/commander_beacon/proc/deactivate(mob/user)
	spawning_enabled = FALSE
	if(user)
		to_chat(user, SPAN_NOTICE("\The [src] deactivates. Your soldiers will no longer be replenished."))

/// Orders current followers to either close distance to the owner when
/// idle ("follow") or stay put when idle ("hold") -- future soldiers
/// spawned while this mode is active inherit it too (see spawn_soldier()).
/// A bulk order like this is a clean override -- it cancels any individual
/// point-to-move order a follower might currently be mid-route to.
/// Deliberately does NOT early-return when stance_mode already matches mode
/// -- an individually-commanded soldier (afterattack() above) has its own
/// hold_position set TRUE out of band, decoupled from this beacon-level
/// var, so "Follow" must always re-apply to every current soldier or a
/// point-ordered one stays stuck holding forever even after Follow is
/// clicked (the regression this fixes: stance_mode was already "follow" by
/// default, so the guard skipped the loop below and never actually reset
/// that soldier's hold_position back to FALSE).
/obj/item/commander_beacon/proc/set_stance_mode(mode, mob/user)
	stance_mode = mode
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		if(!QDELETED(M))
			M.hold_position = (mode == "hold")
			M.ordered_destination = null
	if(user)
		user.custom_emote(VISIBLE_MESSAGE, "does a military gesture towards their troops.")
	to_chat(user, SPAN_NOTICE("Your soldiers will now [mode == "hold" ? "hold their position." : "follow you."]"))

/// Orders current followers to either proactively attack non-faction
/// targets ("hostile", the default) or never initiate combat at all
/// ("passive") -- future followers spawned while this mode is active
/// inherit it too (see spawn_soldier()).
/obj/item/commander_beacon/proc/set_hostility_mode(mode, mob/user)
	if(hostility_mode == mode)
		return
	hostility_mode = mode
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		if(!QDELETED(M))
			M.passive_mode = (mode == "passive")
	to_chat(user, SPAN_NOTICE("Your soldiers will now [mode == "passive" ? "hold their fire unless ordered." : "engage non-faction targets on sight."]"))

/// Second half of "Command Soldier" -- arms a ONE-SHOT COMSIG_MOB_CLICKON
/// registration on user (see click.dm's ClickOn()), called right after
/// selecting a follower in the TGUI ("select_soldier" in ui_act() above).
/// Deliberately mob-scoped, not an afterattack() item override -- this way
/// the destination click works whether the beacon is held, on the belt, in
/// a pocket, or in suit storage, matching the action button's own "doesn't
/// need to be in-hand" reach. One-shot (disarmed the instant a click comes
/// through, success or not) rather than staying armed indefinitely -- a
/// persistent intercept would silently eat every future click anywhere
/// (attacking, opening doors, moving) until manually cleared, which is far
/// worse than just needing to hit "Command" again for a follow-up order.
/obj/item/commander_beacon/proc/_arm_destination_click(mob/user)
	if(pending_click_user && pending_click_user != user)
		UnregisterSignal(pending_click_user, COMSIG_MOB_CLICKON)
	pending_click_user = user
	RegisterSignal(user, COMSIG_MOB_CLICKON, PROC_REF(_on_destination_click))

/obj/item/commander_beacon/proc/_disarm_destination_click()
	if(pending_click_user)
		UnregisterSignal(pending_click_user, COMSIG_MOB_CLICKON)
	pending_click_user = null

/// SIGNAL_HANDLER for COMSIG_MOB_CLICKON -- source is always pending_click_user
/// itself (the mob the signal was registered on), passed automatically as
/// the first arg. Returning COMSIG_MOB_CANCEL_CLICKON stops the click from
/// ALSO resolving as a normal move/attack/interact on whatever was clicked.
/obj/item/commander_beacon/proc/_on_destination_click(mob/user, atom/target, list/modifiers)
	SIGNAL_HANDLER
	_disarm_destination_click()
	if(QDELETED(selected_soldier) || !(selected_soldier in active_mobs))
		return
	var/turf/T = get_turf(target)
	if(!T)
		return
	selected_soldier.ordered_destination = T
	selected_soldier.hold_position = TRUE
	// /obj/effect/decal/point has no lifetime of its own (it's a permanent
	// decal by default) -- same 2-second cleanup the vanilla point verb uses
	// (mob.dm's pointed()/end_pointing_effect()), otherwise every order
	// issued leaves another arrow behind forever.
	QDEL_IN(new /obj/effect/decal/point(T), 2 SECONDS)
	user.custom_emote(VISIBLE_MESSAGE, "does a military gesture towards their troops.")
	to_chat(user, SPAN_NOTICE("[selected_soldier] moves to cover the marked position."))
	return COMSIG_MOB_CANCEL_CLICKON

/// Mirrors portable_turret.dm's already-shipped employer_faction/
/// normalize_faction_uid() bridge -- returns null if the user holds no ID,
/// no employer_faction, or an ID tagged personal/public/crew.
/obj/item/commander_beacon/proc/_owner_faction_uid(mob/living/user)
	if(!ishuman(user))
		return null
	var/mob/living/carbon/human/H = user
	var/obj/item/card/id/ID = H.GetIdCard()
	return (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null

/// TRUE only if the user belongs to a real, currently-existing faction --
/// same "personal/public/crew are not a faction" rule faction_barracks.dm
/// enforces for its own activation gate.
/obj/item/commander_beacon/proc/_owner_faction_ready(mob/living/user)
	var/uid = _owner_faction_uid(user)
	return uid && islist(GLOB.persistence_faction_cache) && (uid in GLOB.persistence_faction_cache)

/// fauna_spawner.start_spawning()'s exact shape (mob_spawner.dm), capped at
/// 2 instead of 5 -- see faction_barracks.dm's identical loop for the
/// faction-machine counterpart. Same departure as that loop: the long
/// randomized cooldown only applies once already at cap -- while still
/// under cap (e.g. right after activation) it fills up quickly instead of
/// making the owner wait up to max_spawn_cooldown for their 2nd soldier.
/obj/item/commander_beacon/proc/start_maintaining()
	spawn()
		while(spawning_enabled && src)
			for(var/i = length(active_mobs); i >= 1; i--)
				var/mob/living/M = active_mobs[i]
				if(!M || QDELETED(M) || M.stat == DEAD)
					active_mobs.Cut(i, i + 1)
			if(QDELETED(owner) || owner.stat)
				spawning_enabled = FALSE
				// Merely unconscious (stunned/knocked out) just pauses
				// replenishment -- they might wake up and want their
				// followers back. Actually dead/deleted releases them
				// permanently, since there's no "waking up" from that.
				if(QDELETED(owner) || owner.stat == DEAD)
					release_followers()
				break
			if(!_owner_faction_ready(owner))
				spawning_enabled = FALSE
				to_chat(owner, SPAN_WARNING("\The [src] deactivates -- you are no longer part of a faction."))
				break
			var/tagged_uid = normalize_faction_uid(persistent_network)
			if(tagged_uid && _owner_faction_uid(owner) != tagged_uid)
				spawning_enabled = FALSE
				to_chat(owner, SPAN_WARNING("\The [src] deactivates -- it's keyed to a different faction."))
				break
			if(length(active_mobs) < max_active_mobs)
				spawn_soldier()
				sleep(2 SECONDS)
				continue
			sleep(rand(min_spawn_cooldown, max_spawn_cooldown) SECONDS)

/obj/item/commander_beacon/proc/spawn_soldier()
	if(!preset_id || QDELETED(owner))
		return
	var/summoner_faction = _owner_faction_uid(owner)
	// Catches the owner's faction changing (or a preset becoming exclusive
	// to a different faction) after this beacon's preset was already set.
	if(!hostile_npc_preset_allowed_for_faction(get_hostile_npc_preset(preset_id), summoner_faction))
		return
	var/turf/T = get_turf(src)
	if(!T)
		return
	var/mob/living/carbon/human/npc/hostile/H = spawn_hostile_npc_from_preset(preset_id, T, summoner_faction)
	if(!H)
		return
	H.commander = owner
	H.passive_mode = (hostility_mode == "passive")
	H.hold_position = (stance_mode == "hold")
	active_mobs += H
	RegisterSignal(H, COMSIG_QDELETING, PROC_REF(soldier_died))

/// Releases current followers from active command once their commander is
/// dead/gone -- clears the commander link and settles them into guarding
/// their current spot (mirrors faction_barracks.dm's patrol behavior)
/// instead of leaving them to walk toward/idle by a corpse forever. Their
/// faction and current Follow/Hold order are otherwise untouched.
/obj/item/commander_beacon/proc/release_followers()
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		if(QDELETED(M))
			continue
		M.commander = null
		M.ordered_destination = null
		M.patrol_anchor_turf = get_turf(M)
		M.visible_message(SPAN_NOTICE("[M] looks around, no longer awaiting orders."))

/// Deactivates if the beacon actually leaves the owner's possession
/// entirely (dropped on the floor, thrown, given/stolen to someone else) --
/// get_holding_mob() (mob_helpers.dm) still resolves to owner if it was
/// merely moved into their own backpack/pocket, so that does NOT deactivate
/// it, matching dropped()'s own doc comment that it fires for ANY inventory
/// removal, not just leaving a hand.
/obj/item/commander_beacon/dropped(mob/user)
	. = ..()
	if(!spawning_enabled)
		return
	if(get_holding_mob() != owner)
		deactivate(owner)

/obj/item/commander_beacon/proc/soldier_died(mob/living/mob_ref)
	SIGNAL_HANDLER
	UnregisterSignal(mob_ref, COMSIG_QDELETING)
	active_mobs -= mob_ref

/// The explicit "get rid of them" action -- also called from the TGUI's
/// "Deactivate" button (ui_act()'s "toggle") alongside deactivate() itself,
/// since that's a deliberate stand-down. deactivate() on its own (dropped()/
/// losing faction membership) only stops replenishment and leaves existing
/// followers standing -- those aren't the player choosing to send them away.
/obj/item/commander_beacon/proc/dismiss_soldiers(mob/user)
	for(var/mob/m in active_mobs)
		UnregisterSignal(m, COMSIG_QDELETING)
		if(!QDELETED(m))
			// Same fading bluespace portal + sparks recall_stragglers() uses --
			// dismissed soldiers vanish with the same tell, not a silent qdel.
			var/turf/origin = get_turf(m)
			if(origin)
				new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
				spark(origin, 3, GLOB.alldirs)
			qdel(m)
	active_mobs.Cut()
	selected_soldier = null
	if(user)
		to_chat(user, SPAN_NOTICE("Your soldiers have been dismissed."))

/// "Fetch" button -- teleports any CURRENT follower (commander == user,
/// not a stale/released one from a previous owner still sitting in
/// active_mobs) that's too far away on the same Z -- beyond world.view,
/// i.e. likely not even visible to the owner anymore -- back to their
/// side. Same VFX as hostile_npc.dm's own cross-Z catch_up_to_commander().
/// Rate-limited to once per 30 seconds so it can't be spammed as a combat
/// escape/repositioning tool. Z-mismatched followers are untouched here --
/// that case is already handled every idle tick regardless of this button.
/obj/item/commander_beacon/proc/recall_stragglers(mob/user)
	if(world.time < fetch_cooldown_until)
		to_chat(user, SPAN_WARNING("\The [src] is still recalibrating -- wait a moment before fetching again."))
		return
	fetch_cooldown_until = world.time + 30 SECONDS
	var/turf/destination = get_turf(user)
	if(!destination)
		return
	var/fetched_any = FALSE
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		if(QDELETED(M) || M.commander != user || M.z != user.z)
			continue
		if(get_dist(M, user) <= world.view)
			continue
		var/turf/origin = get_turf(M)
		if(origin)
			new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
			spark(origin, 3, GLOB.alldirs)
		M.forceMove(destination)
		new /obj/effect/portal/decorative/fading(destination, null, null, 5 SECONDS, 0)
		spark(destination, 3, GLOB.alldirs)
		fetched_any = TRUE
	if(!fetched_any)
		to_chat(user, SPAN_NOTICE("Your soldiers are already close by."))
