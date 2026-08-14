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
 * order: pick any number from the soldier list in the TGUI itself (no
 * verb-panel hunting -- this used to be a hidden held-item verb, which
 * players reasonably never found), then click anywhere visible in the world
 * (need not be adjacent, and -- since the TGUI is reachable without holding
 * the item at all, per the action button above -- need not be holding the
 * beacon either). This is done via a COMSIG_MOB_CLICKON registration on the
 * commanding mob (_arm_destination_click()/_on_destination_click() below),
 * not an afterattack() override, since afterattack() only ever fires for
 * clicks made with this exact item actively wielded -- which would silently
 * break the destination step whenever the beacon is worn instead of held.
 * Deliberately NOT built on the game's vanilla "Point To" verb/
 * COMSIG_MOB_POINT either -- that verb shares one 2.5-second cooldown per
 * pointing mob regardless of target (mob.dm's "point_verb_emote_cooldown"),
 * which silently swallows the second of two quick point actions and broke
 * the intended fast select-soldier-then-tap-turf workflow. This has no such
 * cooldown, and manually replicates the same visual feedback
 * (add_point_filter() glow, a fading ground decal/point marker) the vanilla
 * verb would have given for free. The click registration stays armed across
 * repeated orders (deliberately NOT one-shot, per player feedback that
 * having to reselect for every single order was tedious) until the player
 * either deselects every soldier or closes the TGUI (ui_close() below).
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
	var/min_spawn_cooldown = 90
	var/max_spawn_cooldown = 120
	var/spawning_enabled = FALSE
	/// "follow" (default) -- idle followers close distance to the owner.
	/// "hold" -- idle followers stay put wherever they currently are.
	var/stance_mode = "follow"
	/// "hostile" (default) -- followers proactively attack non-faction
	/// targets. "passive" -- followers never initiate combat at all.
	var/hostility_mode = "hostile"
	/// Which of active_mobs the owner currently has singled out via
	/// select_soldier -- every one of these gets the next move-to-turf order.
	var/list/selected_soldiers = list()
	/// Mob currently armed with a COMSIG_MOB_CLICKON registration (see
	/// _arm_destination_click()) -- tracked separately from
	/// selected_soldiers/owner so it can be reliably unregistered from the
	/// right mob even if the selection changes, or this item is destroyed,
	/// before they actually click anywhere.
	var/mob/pending_click_user
	/// Faction tagger compatible var -- "" (personal/untagged) or a real
	/// faction_uid. When set, activation refuses for anyone not a member
	/// of that specific faction, regardless of what preset is set.
	var/persistent_network = ""
	/// world.time deadline before the "Fetch" button can be used again.
	var/fetch_cooldown_until = 0
	/// world.time deadline before the "toggle" button (activate/deactivate)
	/// can be used again -- stops instant on/off toggling from being used to
	/// duck out of a fight (dismissing soldiers right before a loss) and
	/// straight back in once safe.
	var/toggle_cooldown_until = 0

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

// ------- Reboot persistence (generic passthrough -- serializePersistentItem(),
// persistence_mobs.dm -- fires automatically wherever this item is serialized:
// worn, held, in a backpack, in a closet, or dropped loose. No registration
// call needed, unlike a placed structure. owner/active_mobs/spawning_enabled
// are deliberately NOT restored -- a live mob reference and active soldiers
// can't meaningfully survive a reboot; the player just re-activates it, and
// it summons with the restored preset/stance/hostility/tag instead of blank
// ones. -------

/obj/item/commander_beacon/persistent_objects_get_content()
	var/list/content = ..()
	content["preset_id"] = preset_id
	content["stance_mode"] = stance_mode
	content["hostility_mode"] = hostility_mode
	content["persistent_network"] = persistent_network
	return content

/obj/item/commander_beacon/persistent_objects_apply_content(content, x, y, z)
	. = ..()
	if(!islist(content))
		return
	if(!isnull(content["preset_id"]))
		preset_id = content["preset_id"]
	if(!isnull(content["stance_mode"]))
		stance_mode = content["stance_mode"]
	if(!isnull(content["hostility_mode"]))
		hostility_mode = content["hostility_mode"]
	if(!isnull(content["persistent_network"]))
		persistent_network = content["persistent_network"]

/// get_holding_mob() rather than a bare "loc == user" -- this item is
/// explicitly meant to work while WORN (belt/pocket/suit storage), which is
/// the whole point of action_button_name above. When worn, loc is the
/// belt/pocket, not the mob, so the old check silently refused every
/// interaction from exactly the carry modes this is documented to support.
/// Same resolution dropped() already uses.
/obj/item/commander_beacon/attack_self(mob/user)
	if(get_holding_mob() != user)
		return
	ui_interact(user)

/obj/item/commander_beacon/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "CommanderBeacon", "Commander's Beacon", 380, 500)
		ui.open()

/// Closing the window is the other way (besides emptying selected_soldiers)
/// to back out of Command Soldier -- otherwise the click-intercept would
/// stay armed against a menu the player can no longer see feedback in.
/obj/item/commander_beacon/ui_close(mob/user)
	. = ..()
	selected_soldiers = list()
	_disarm_destination_click()

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
	var/soldier_index = 0
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
		soldier_index++
		soldiers += list(list(
			"ref"      = "\ref[M]",
			// Same-preset soldiers share a name verbatim, so the index is the
			// only thing that tells two of them apart in the list.
			"name"     = "#[soldier_index] [M.name]",
			"selected" = (M in selected_soldiers)
		))
	data["soldiers"] = soldiers
	return data

/obj/item/commander_beacon/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/living/user = usr
	// See attack_self()'s note -- a worn (belt/pocket/suit storage) beacon has
	// loc set to the container, not the mob, so the old "loc == user" check
	// silently swallowed EVERY button press in exactly the carry modes this
	// item documents as supported.
	if(get_holding_mob() != user)
		return
	switch(action)
		if("toggle")
			if(spawning_enabled)
				// Deactivating is ALWAYS allowed. The cooldown exists to stop a
				// squad being dismissed right before a loss and re-summoned
				// fresh once the danger has passed -- that only requires gating
				// the way back ON. Blocking a player from standing their own
				// soldiers down serves no purpose, so the lockout STARTS here
				// rather than being checked here.
				//
				// Only the deliberate button press dismisses -- deactivate()
				// is also called from dropped()/faction-loss, which should
				// keep leaving followers standing behind, per its own doc
				// comment.
				deactivate(user)
				dismiss_soldiers(user)
				toggle_cooldown_until = world.time + 5 MINUTES
			else
				if(world.time < toggle_cooldown_until)
					to_chat(user, SPAN_WARNING("\The [src] is still recalibrating -- wait a moment before summoning again."))
					return TRUE
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
		if("set_all_guards_hostile")
			_set_guard_beacons_hostility("hostile", user)
			. = TRUE
		if("set_all_guards_passive")
			_set_guard_beacons_hostility("passive", user)
			. = TRUE
		if("set_all_guards_enabled")
			_set_guard_beacons_enabled(TRUE, user)
			. = TRUE
		if("set_all_guards_disabled")
			_set_guard_beacons_enabled(FALSE, user)
			. = TRUE
		if("set_turrets_enabled")
			_set_faction_turrets_enabled(TRUE, user)
			. = TRUE
		if("set_turrets_disabled")
			_set_faction_turrets_enabled(FALSE, user)
			. = TRUE
		if("set_turrets_lethal")
			_set_faction_turrets_lethal(TRUE, user)
			. = TRUE
		if("set_turrets_stun")
			_set_faction_turrets_lethal(FALSE, user)
			. = TRUE
		if("select_soldier")
			var/target_ref = params["ref"]
			for(var/mob/living/carbon/human/npc/hostile/M in active_mobs)
				if("\ref[M]" != target_ref)
					continue
				if(M in selected_soldiers)
					selected_soldiers -= M
					to_chat(user, SPAN_NOTICE("You stop singling out [_soldier_label(M)]."))
					if(!length(selected_soldiers))
						_disarm_destination_click()
				else
					selected_soldiers += M
					M.add_point_filter()
					_arm_destination_click(user)
					to_chat(user, SPAN_NOTICE("You single out [_soldier_label(M)] to command -- click a location to send them there, or click an enemy to engage."))
				break
			. = TRUE
		if("clear_selection")
			selected_soldiers = list()
			_disarm_destination_click()
			to_chat(user, SPAN_NOTICE("You stand down -- no soldiers are being individually commanded."))
			. = TRUE
		if("clear_attack_target")
			var/cleared_count = 0
			for(var/mob/living/carbon/human/npc/hostile/M in selected_soldiers)
				if(QDELETED(M) || !(M in active_mobs))
					continue
				if(M.stance != HOSTILE_STANCE_IDLE)
					M.LoseTarget()
					cleared_count++
			if(cleared_count)
				to_chat(user, SPAN_NOTICE("[cleared_count] soldier[cleared_count > 1 ? "s" : ""] stand down from combat."))
			. = TRUE
		if("remote_door_control")
			_remote_door_control(user)
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
	if(_hub_restriction_blocked(user))
		to_chat(user, SPAN_WARNING("\The [src] refuses to activate -- this is Hub-controlled territory, restricted to Hub personnel."))
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
			// A soldier mid-fight never reaches think()'s IDLE branch at all,
			// so Follow/Hold would otherwise silently do nothing until that
			// fight ended on its own. An explicit player order outranks the
			// AI's own target pick -- break off now so the new stance is
			// visibly obeyed immediately.
			if(M.stance != HOSTILE_STANCE_IDLE)
				M.LoseTarget()
			// hold_position alone only stops FUTURE follow_commander() calls
			// (guarded by !hold_position) -- an already-active chase loop
			// from before this click was never told to stop, and nothing
			// else would ever call stop_looping() on it once hold_position
			// is TRUE, so it would otherwise keep chasing indefinitely.
			GLOB.move_manager.stop_looping(M)
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

/// Bulk Hostile/Passive for every guard_beacon.dm on the user's current Z
/// level tagged to their own faction -- guard beacons are invisible and
/// scattered, so walking around clicking each one individually isn't
/// practical. Scoped to Z rather than every guard beacon that faction owns
/// anywhere, so it only affects the immediate area the user is actually in.
/obj/item/commander_beacon/proc/_set_guard_beacons_hostility(mode, mob/user)
	var/uid = _owner_faction_uid(user)
	if(!uid)
		to_chat(user, SPAN_WARNING("You must be a member of a faction to do that."))
		return
	var/affected = 0
	for(var/obj/structure/machinery/guard_beacon/G in world)
		if(G.z != user.z)
			continue
		if(normalize_faction_uid(G.persistent_network) != uid)
			continue
		G.set_hostility_mode(mode, null)
		affected++
	if(affected)
		to_chat(user, SPAN_NOTICE("[affected] guard beacon[affected > 1 ? "s" : ""] on this level set to [mode == "passive" ? "passive" : "hostile"]."))
	else
		to_chat(user, SPAN_NOTICE("No guard beacons belonging to your faction were found on this level."))

/// Bulk Activate/Deactivate for every guard_beacon.dm on the user's current Z
/// level tagged to their own faction -- same shape as
/// _set_guard_beacons_hostility() and _set_faction_turrets_enabled() below.
/// Activating skips (and reports) any beacon that isn't anchored, isn't
/// faction-ready, or has no preset configured yet -- the same prerequisites
/// toggle_active() enforces for a single beacon -- rather than silently
/// forcing them on in an invalid state. Deactivating has no such
/// prerequisites, matching _set_active()'s own tolerant shape.
/obj/item/commander_beacon/proc/_set_guard_beacons_enabled(new_value, mob/user)
	var/uid = _owner_faction_uid(user)
	if(!uid)
		to_chat(user, SPAN_WARNING("You must be a member of a faction to do that."))
		return
	var/affected = 0
	var/skipped = 0
	for(var/obj/structure/machinery/guard_beacon/G in world)
		if(G.z != user.z)
			continue
		if(normalize_faction_uid(G.persistent_network) != uid)
			continue
		if(G.active == new_value)
			continue
		if(new_value && !(G.anchored && G._faction_ready() && G.preset_id))
			skipped++
			continue
		G._set_active(new_value)
		affected++
	if(affected)
		to_chat(user, SPAN_NOTICE("[affected] guard beacon[affected > 1 ? "s" : ""] on this level [new_value ? "activated" : "deactivated"].[skipped ? " [skipped] not ready (unanchored/untagged/unconfigured)." : ""]"))
	else
		to_chat(user, SPAN_NOTICE("No guard beacons belonging to your faction needed to be [new_value ? "activated" : "deactivated"] on this level.[skipped ? " [skipped] not ready (unanchored/untagged/unconfigured)." : ""]"))

/// Bulk enable/disable for every faction-tagged portable turret on the
/// user's current Z level -- same shape as _set_guard_beacons_hostility()
/// above. set_enabled() (portable_turret.dm) is reused rather than setting
/// the var directly so process registration/cover state stay correct.
/obj/item/commander_beacon/proc/_set_faction_turrets_enabled(new_value, mob/user)
	var/uid = _owner_faction_uid(user)
	if(!uid)
		to_chat(user, SPAN_WARNING("You must be a member of a faction to do that."))
		return
	var/affected = 0
	for(var/obj/structure/machinery/porta_turret/T in world)
		if(T.z != user.z)
			continue
		if(normalize_faction_uid(T.persistent_network) != uid)
			continue
		T.set_enabled(new_value)
		affected++
	if(affected)
		to_chat(user, SPAN_NOTICE("[affected] faction turret[affected > 1 ? "s" : ""] on this level [new_value ? "enabled" : "disabled"]."))
	else
		to_chat(user, SPAN_NOTICE("No turrets belonging to your faction were found on this level."))

/// Bulk stun/lethal for every faction-tagged, mode-switchable portable
/// turret on the user's current Z level -- skips any turret with a
/// hardwired gun installed (egun FALSE), the same gate the turret's own
/// TGUI ("can_switch") already applies for a single turret.
/obj/item/commander_beacon/proc/_set_faction_turrets_lethal(new_value, mob/user)
	var/uid = _owner_faction_uid(user)
	if(!uid)
		to_chat(user, SPAN_WARNING("You must be a member of a faction to do that."))
		return
	var/affected = 0
	for(var/obj/structure/machinery/porta_turret/T in world)
		if(T.z != user.z)
			continue
		if(normalize_faction_uid(T.persistent_network) != uid)
			continue
		if(!T.egun)
			continue
		T.lethal = new_value
		T.lethal_icon = new_value
		affected++
	if(affected)
		to_chat(user, SPAN_NOTICE("[affected] faction turret[affected > 1 ? "s" : ""] on this level set to [new_value ? "lethal" : "stun"]."))
	else
		to_chat(user, SPAN_NOTICE("No mode-switchable turrets belonging to your faction were found on this level."))

/// TRUE if D's id_tag is referenced as either end of an airlock cycler
/// controller anywhere in the world -- these doors are excluded from remote
/// door control entirely (confirmed with the user): yanking a cycler-managed
/// door open/closed out of sequence bypasses the pressurization interlock
/// the cycler exists to enforce, exterior end or interior end alike.
/obj/item/commander_beacon/proc/_door_is_cycler_managed(obj/structure/machinery/door/airlock/D)
	if(!D.id_tag)
		return FALSE
	for(var/obj/structure/machinery/embedded_controller/radio/airlock/C in world)
		if(C.tag_exterior_door == D.id_tag || C.tag_interior_door == D.id_tag)
			return TRUE
	return FALSE

/// "Remote Door Control" -- lets a faction commander open/close (and for
/// airlocks, bolt/unbolt) any blast door, shutter, or airlock on their
/// current Z tagged to their own faction, without walking to it. Two native
/// list popups (door, then action) rather than an embedded TGUI list/section,
/// per explicit design -- keeps the main beacon panel exactly as it was.
/// visible_message() on the door itself is the deliberate tell that it was
/// operated remotely, not silently.
/obj/item/commander_beacon/proc/_remote_door_control(mob/living/user)
	var/uid = _owner_faction_uid(user)
	if(!uid)
		to_chat(user, SPAN_WARNING("You must be a member of a faction to do that."))
		return

	var/list/door_options = list()
	for(var/obj/structure/machinery/door/blast/BD in world)
		if(BD.z != user.z)
			continue
		if(normalize_faction_uid(BD.persistent_network) != uid)
			continue
		door_options["[BD.name] @ ([BD.x],[BD.y])"] = BD
	for(var/obj/structure/machinery/door/airlock/AL in world)
		if(AL.z != user.z)
			continue
		if(normalize_faction_uid(AL.persistent_network) != uid)
			continue
		if(_door_is_cycler_managed(AL))
			continue
		door_options["[AL.name] @ ([AL.x],[AL.y])"] = AL

	if(!length(door_options))
		to_chat(user, SPAN_NOTICE("No doors belonging to your faction were found on this level."))
		return

	var/pick = tgui_input_list(user, "Select a door to control:", "Remote Door Control", door_options)
	if(!pick)
		return
	var/obj/structure/machinery/door/D = door_options[pick]
	if(QDELETED(D))
		to_chat(user, SPAN_WARNING("That door is no longer there."))
		return

	var/is_airlock = istype(D, /obj/structure/machinery/door/airlock)
	var/list/action_options = is_airlock ? list("Open", "Close", "Bolt", "Unbolt") : list("Open", "Close")
	var/action = tgui_input_list(user, "Action for [D.name]:", "Remote Door Control", action_options)
	if(!action)
		return

	switch(action)
		if("Open")
			D.open()
		if("Close")
			D.close()
		if("Bolt")
			var/obj/structure/machinery/door/airlock/AL = D
			AL.lock()
		if("Unbolt")
			var/obj/structure/machinery/door/airlock/AL = D
			AL.unlock()

	D.visible_message(SPAN_NOTICE("[user] controls \the [D] from afar."))
	to_chat(user, SPAN_NOTICE("You remotely [lowertext(action)] \the [D]."))

/// Second half of "Command Soldier" -- arms a COMSIG_MOB_CLICKON
/// registration on user (see click.dm's ClickOn()), called right after
/// selecting a follower in the TGUI ("select_soldier" in ui_act() above).
/// Deliberately mob-scoped, not an afterattack() item override -- this way
/// the destination click works whether the beacon is held, on the belt, in
/// a pocket, or in suit storage, matching the action button's own "doesn't
/// need to be in-hand" reach. Stays armed across repeated orders (see
/// _on_destination_click() below) until the player empties selected_soldiers
/// or closes the TGUI (ui_close()).
/obj/item/commander_beacon/proc/_arm_destination_click(mob/user)
	if(pending_click_user && pending_click_user != user)
		UnregisterSignal(pending_click_user, COMSIG_MOB_CLICKON)
	pending_click_user = user
	RegisterSignal(user, COMSIG_MOB_CLICKON, PROC_REF(_on_destination_click))

/obj/item/commander_beacon/proc/_disarm_destination_click()
	if(pending_click_user)
		UnregisterSignal(pending_click_user, COMSIG_MOB_CLICKON)
	pending_click_user = null

/// Up to `count` distinct, non-dense turfs near `center` for a multi-soldier
/// move order to spread across -- center itself first (so a lone soldier
/// still lands exactly on the mark), then spiraling outward ring by ring
/// (reuses personal_travel.dm's own ring generator rather than duplicating
/// it). Pads with `center` itself if the immediate area is too cramped/dense
/// to find enough distinct spots -- callers already tolerate more than one
/// soldier sharing a tile as a degenerate fallback, this just makes it rare
/// instead of the default outcome.
/obj/item/commander_beacon/proc/_order_move_spread_turfs(turf/center, count)
	var/list/turf/found = list()
	if(!center)
		return found
	for(var/radius = 0 to 3)
		for(var/list/coord in _personal_travel_ring_coords(center.x, center.y, radius))
			var/cx = coord[1]
			var/cy = coord[2]
			if(cx < 1 || cx > world.maxx || cy < 1 || cy > world.maxy)
				continue
			var/turf/T = locate(cx, cy, center.z)
			if(!T || T.density)
				continue
			found += T
			if(length(found) >= count)
				return found
	while(length(found) < count)
		found += center
	return found

/// SIGNAL_HANDLER for COMSIG_MOB_CLICKON -- source is always pending_click_user
/// itself (the mob the signal was registered on), passed automatically as
/// the first arg. Returning COMSIG_MOB_CANCEL_CLICKON stops the click from
/// ALSO resolving as a normal move/attack/interact on whatever was clicked.
/// Deliberately stays armed after firing -- repeated clicks keep re-issuing
/// orders to every currently selected soldier until the player deselects
/// them all (ui_act()'s "select_soldier"/"clear_selection") or closes the
/// TGUI (ui_close()).
/obj/item/commander_beacon/proc/_on_destination_click(mob/user, atom/target, list/modifiers)
	SIGNAL_HANDLER
	if(!length(selected_soldiers))
		_disarm_destination_click()
		return
	// Clicking a LIVING mob is always an attack order and never silently turns
	// into "walk onto that tile." The old code fell through to the move-order
	// path below whenever no soldier accepted the attack (dead/bot/same-pack/
	// same-faction target), which is exactly the long-reported "ordering them
	// to attack also makes them move to the enemy's turf."
	if(isliving(target))
		_order_attack_target(target, user)
		return COMSIG_MOB_CANCEL_CLICKON
	var/turf/T = get_turf(target)
	if(!T)
		return
	// Spread multiple soldiers around the marked point instead of piling
	// every one of them onto the exact same tile -- same "don't stack"
	// reasoning as patrol_anchor_turf's own wander radius (hostile_npc.dm).
	// Center turf first (so a lone soldier still lands exactly on the mark),
	// then spirals outward.
	var/list/turf/spread_turfs = _order_move_spread_turfs(T, length(selected_soldiers))
	var/spread_index = 1
	var/ordered_count = 0
	for(var/mob/living/carbon/human/npc/hostile/M in selected_soldiers)
		// Never skip a selected soldier silently -- a soldier that quietly
		// does nothing is indistinguishable from a broken one, which is what
		// made "one of my two soldiers ignores orders" impossible to diagnose.
		if(QDELETED(M) || !(M in active_mobs))
			to_chat(user, SPAN_WARNING("[_soldier_label(M)] is no longer under your command."))
			continue
		// order_move_to() (hostile_npc.dm) rather than setting the vars
		// inline -- it also breaks off any fight in progress and promotes the
		// soldier to fast thinking, so the order actually starts immediately
		// instead of waiting for combat to end and/or the next slow AI tick.
		M.order_move_to(spread_turfs[spread_index] || T)
		spread_index++
		to_chat(user, SPAN_NOTICE("[_soldier_label(M)] moves to cover the marked position."))
		ordered_count++
	if(!ordered_count)
		return
	// /obj/effect/decal/point has no lifetime of its own (it's a permanent
	// decal by default) -- same 2-second cleanup the vanilla point verb uses
	// (mob.dm's pointed()/end_pointing_effect()), otherwise every order
	// issued leaves another arrow behind forever.
	QDEL_IN(new /obj/effect/decal/point(T), 2 SECONDS)
	user.custom_emote(VISIBLE_MESSAGE, "does a military gesture towards their troops.")
	return COMSIG_MOB_CANCEL_CLICKON

/// "#N Name" for a soldier, N being its 1-based position in active_mobs.
/// Soldiers summoned from one preset all share the same name
/// (apply_hostile_preset() copies it verbatim), so without an index the
/// player cannot tell two of them apart in the UI or in any order feedback.
/obj/item/commander_beacon/proc/_soldier_label(mob/living/carbon/human/npc/hostile/M)
	if(QDELETED(M))
		return "A dismissed soldier"
	var/idx = active_mobs.Find(M)
	return idx ? "#[idx] [M.name]" : "[M.name] (unlisted)"

/// Orders every currently selected soldier to attack `target`. Reports the
/// outcome for EVERY selected soldier individually -- accepted or refused,
/// with the reason -- so a soldier that ends up doing nothing always says
/// why instead of looking broken.
/obj/item/commander_beacon/proc/_order_attack_target(mob/living/target, mob/user)
	var/ordered_count = 0
	for(var/mob/living/carbon/human/npc/hostile/M in selected_soldiers)
		if(QDELETED(M) || !(M in active_mobs))
			to_chat(user, SPAN_WARNING("[_soldier_label(M)] is no longer under your command."))
			continue
		if(!M.is_valid_ordered_attack_target(target))
			if(M.is_same_persistence_faction(target))
				to_chat(user, SPAN_WARNING("[_soldier_label(M)] refuses -- [target] is recognized as friendly forces."))
			else
				to_chat(user, SPAN_WARNING("[_soldier_label(M)] won't engage [target]."))
			continue
		M.order_attack_target(target)
		to_chat(user, SPAN_NOTICE("[_soldier_label(M)] moves to engage [target]."))
		ordered_count++
	if(!ordered_count)
		return FALSE
	user.custom_emote(VISIBLE_MESSAGE, "gestures sharply towards [target].")
	return TRUE

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

/// TRUE if user is standing in a HIGHSEC area without holding an actual
/// job (FACTION_RANK_CREW/0 or above -- only FACTION_RANK_CIVILIAN/-1 is
/// excluded) in the Hub faction -- HIGHSEC is Hub jurisdiction, so a
/// commander beacon shouldn't be usable there by anyone else, same
/// get_effective_faction_rank() threshold zone_engineering_exempt()/
/// airlock.dm's allowed()/RFD.dm already use for "trusted Hub personnel."
/obj/item/commander_beacon/proc/_hub_restriction_blocked(mob/living/user)
	var/turf/T = get_turf(user)
	if(!T || zone_security_get(T.z) != ZONE_HIGHSEC)
		return FALSE
	return get_effective_faction_rank(user, "hub") <= FACTION_RANK_CIVILIAN

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
			if(_hub_restriction_blocked(owner))
				spawning_enabled = FALSE
				to_chat(owner, SPAN_WARNING("\The [src] deactivates -- you've entered Hub-controlled territory."))
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
	// Don't stack soldier #2 inside soldier #1 -- two dense mobs on one tile
	// start out immediately blocking each other's pathing (see hostile_npc.dm's
	// CanPass() note), so spread out to a free neighbour when this tile is
	// already occupied by one of ours.
	if(locate(/mob/living/carbon/human/npc/hostile) in T)
		for(var/turf/candidate in orange(1, T))
			if(candidate.density)
				continue
			if(locate(/mob/living) in candidate)
				continue
			T = candidate
			break
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
	for(var/mob/living/carbon/human/npc/hostile/M in active_mobs.Copy())
		if(QDELETED(M))
			continue
		M.commander = null
		// Without this, a soldier that was on a "Hold Position"/"Command
		// Soldier" order when released stays stuck -- hold_position gates
		// EVERY idle branch in think(), including the patrol_anchor_turf
		// fallback being assigned right below, so it would otherwise never
		// actually be reached.
		M.hold_position = FALSE
		M.ordered_destination = null
		M.patrol_anchor_turf = get_turf(M)
		M.visible_message(SPAN_NOTICE("[M] looks around, no longer awaiting orders."))
		// Otherwise never removed here -- silently leaks a "soldier slot"
		// against max_active_mobs even for a later reactivation.
		active_mobs -= M
		// Same staleness fix as soldier_died() -- a released follower that
		// was individually selected must not linger in selected_soldiers.
		if(M in selected_soldiers)
			selected_soldiers -= M
	if(!length(selected_soldiers))
		_disarm_destination_click()

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
	// Without this, a dead soldier that was individually selected via
	// "Command Soldier" lingers in selected_soldiers forever (nothing else
	// ever clears a single stale entry) -- every subsequent click silently
	// no-ops for it with no feedback, since it's filtered out by the
	// QDELETED()/active_mobs membership check wherever selected_soldiers is
	// consumed, but the click-intercept stays armed as if it were still doing
	// something.
	if(mob_ref in selected_soldiers)
		selected_soldiers -= mob_ref
		if(!length(selected_soldiers))
			_disarm_destination_click()

/// The explicit "get rid of them" action -- also called from the TGUI's
/// "Deactivate" button (ui_act()'s "toggle") alongside deactivate() itself,
/// since that's a deliberate stand-down. deactivate() on its own (dropped()/
/// losing faction membership) only stops replenishment and leaves existing
/// followers standing -- those aren't the player choosing to send them away.
/obj/item/commander_beacon/proc/dismiss_soldiers(mob/user)
	for(var/mob/m in active_mobs)
		UnregisterSignal(m, COMSIG_QDELETING)
		if(!QDELETED(m))
			// Same transporter pulse (telepad_travel.dm) drydock boarding/
			// Personal Travel use -- dismissed soldiers vanish with the same
			// tell, not a silent qdel.
			var/turf/origin = get_turf(m)
			_travel_spool_pulse(origin, null, null)
			qdel(m)
	active_mobs.Cut()
	selected_soldiers = list()
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
		_travel_spool_pulse(origin, destination, null)
		M.forceMove(destination)
		fetched_any = TRUE
	if(!fetched_any)
		to_chat(user, SPAN_NOTICE("Your soldiers are already close by."))
