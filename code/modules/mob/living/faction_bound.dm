/*
 * Faction shackle for IPCs and cyborgs
 * Extends the faction tagger (code/game/objects/items/devices/faction_tagger.dm,
 * code/controllers/subsystems/persistence/persistence_faction_tagger.dm) to
 * also target IPC and cyborg PLAYER CHARACTERS, not just machines -- tagging
 * one ties them to that faction (TRAIT_FACTION_BOUND, a status/ownership
 * marker, same spirit as a faction-tagged MACHINE -- deliberately NOT a
 * physical restraint, movement and hand use are both untouched) until
 * they're released by an officer, release themselves with any faction
 * tagger, or gamble on the break-free TGUI below.
 *
 * Named "bound"/"shackle" is kept to player-facing text only -- internal
 * identifiers deliberately avoid the word "shackle" to stay distinct from
 * the unrelated can_configure_faction_shackle()/faction-tagged-MACHINE
 * concept (persistence_factions.dm), a completely different meaning of the
 * same word.
 */

/// world.time this mob's own consent/spool cycle may next be attempted --
/// prevents a target from being spammed with repeated shackle attempts
/// (refused consent, interrupted spool) back to back.
#define FACTION_BOUND_ATTEMPT_COOLDOWN 30 SECONDS
/// Same windup Personal Travel uses (personal_travel.dm) -- reused here so
/// applying a shackle has the same "charging up" feel as teleport travel.
#define FACTION_BOUND_SHACKLE_SPOOLUP 15 SECONDS
#define FACTION_BOUND_BREAK_FREE_COOLDOWN 150 SECONDS
/// First-pass tuning, same "rebalance here" spirit as
/// TRACTOR_BREAK_FREE_CHANCE (ship_tractor_beam.dm).
#define FACTION_BOUND_BREAK_FREE_CHANCE 35
#define FACTION_BOUND_DAMAGE_MIN 5
#define FACTION_BOUND_DAMAGE_MAX 15

/mob/living
	/// Faction UID this mob is currently shackled to, or null. Persists
	/// independent of whatever ID card this mob currently holds/whatever
	/// faction that card claims -- see persistence_set_faction_bound().
	var/faction_bound_uid = null
	/// Self-throttle for the consent/spool cycle in faction_tagger_set().
	var/faction_bound_attempt_at = 0
	/// Self-throttle for _attempt_break_free_faction_bound().
	var/faction_bound_break_attempt_at = 0
	/// Invalidates in-flight spool pulses if this mob is released/destroyed
	/// mid-spool -- same pattern personal_travel.dm's own spool_seq uses.
	var/faction_bound_spool_seq = 0
	/// Lazily-created TGUI module for the break-free status window -- see
	/// the verb below.
	var/datum/tgui_module/faction_bound_status/faction_bound_status_ui
	/// This mob's .color before a faction restrain tint was applied, so
	/// unrestrain can restore it exactly -- captured once per restrain
	/// cycle (_apply_faction_restrained_visual()), same "capture original,
	/// restore on release" shape faction-tagged clothing already uses
	/// (persistence_faction_tagger.dm).
	var/faction_restrained_original_color

/mob/living/faction_tagger_get_uid()
	return faction_bound_uid

/// Compatible mob targets are gated per-type by faction_tagger_compatible()
/// (isipc() for humans, unconditional for cyborgs) -- re-checked here too
/// (not just by the one caller, afterattack(), that currently happens to
/// check it first) so this proc is self-enforcing regardless of what else
/// might call it in the future.
/mob/living/faction_tagger_set(new_uid, mob/user)
	if(!faction_tagger_compatible())
		return FALSE
	if(!new_uid)
		// Reached by BOTH release paths -- self-release (Path A,
		// faction_tagger.dm's own ui_act() "release" bypass) calls this with
		// user == src; officer release (Path B, the ordinary rank-gated
		// "release" action) calls it with user == whoever's holding the
		// tagger. Differentiate the flavor text, not the mechanics -- both
		// end up in the exact same unshackled state.
		var/released_faction = faction_bound_uid
		var/self_release = (user == src)
		_faction_bound_clear()
		if(self_release)
			to_chat(src, SPAN_GOOD("You wipe the shackle tying you to [get_faction_name(released_faction)] with a faction tagger."))
			visible_message(SPAN_NOTICE("[src] clears their own faction shackle with a tagger."))
		else
			to_chat(src, SPAN_GOOD("The shackle tying you to [get_faction_name(released_faction)] is cleared."))
			visible_message(SPAN_NOTICE("[user] clears [src]'s faction shackle with a tagger."))
		return TRUE

	if(HAS_TRAIT(src, TRAIT_FACTION_BOUND))
		to_chat(user, SPAN_WARNING("[src] is already shackled -- release the existing tag first."))
		return FALSE

	if(world.time < faction_bound_attempt_at)
		to_chat(user, SPAN_WARNING("[src] isn't ready to be shackled again so soon."))
		return FALSE

	// Highsec is Hub-only, full stop -- regardless of the acting user's own
	// faction rank (already verified as an officer of new_uid by the
	// generic "set" ui_act() case before this proc was ever called).
	if(zone_security_overmap_tier(get_turf(src)) == ZONE_HIGHSEC)
		if(!check_rights(R_ADMIN, 0, user) && !get_faction_member(user.ckey, "hub"))
			to_chat(user, SPAN_WARNING("Highsec regulations restrict shackling to Hub personnel only."))
			return FALSE

	// Consent, every zone, no exceptions.
	faction_bound_attempt_at = world.time + FACTION_BOUND_ATTEMPT_COOLDOWN
	var/fname = get_faction_name(new_uid)
	if(tgui_alert(src, "[user.real_name] wants to shackle you to [fname]. Consent?", "Faction Shackle", list("Consent", "Refuse")) != "Consent")
		to_chat(user, SPAN_WARNING("[src] refuses to be shackled."))
		return FALSE
	if(QDELETED(src) || QDELETED(user) || !user.Adjacent(src) || HAS_TRAIT(src, TRAIT_FACTION_BOUND))
		return FALSE

	// Spool-up + spark effect, same visual/audio Personal Travel uses for
	// its own windup -- a tagging/branding process, not a restraint, so
	// nothing here touches movement or hand use.
	visible_message(SPAN_WARNING("Sparks crackle around [src] as [user] writes a faction shackle..."))
	var/turf/spool_turf = get_turf(src)
	var/seq = ++faction_bound_spool_seq
	_start_travel_spool_pulses(spool_turf, null, FACTION_BOUND_SHACKLE_SPOOLUP, CALLBACK(src, PROC_REF(_faction_bound_spool_still_valid), seq), show_phase_effect = TRUE, facing_dir = dir)
	if(!do_after(user, FACTION_BOUND_SHACKLE_SPOOLUP, src))
		faction_bound_spool_seq++
		to_chat(user, SPAN_WARNING("Shackling interrupted."))
		return FALSE
	faction_bound_spool_seq++
	if(QDELETED(src) || HAS_TRAIT(src, TRAIT_FACTION_BOUND))
		return FALSE

	faction_bound_uid = new_uid
	ADD_TRAIT(src, TRAIT_FACTION_BOUND, TRAIT_SOURCE_FACTION_TAGGER)
	persistence_set_faction_bound(ckey, real_name, TRUE, new_uid)
	to_chat(src, SPAN_DANGER("You have been shackled to [fname]."))
	visible_message(SPAN_DANGER("[src]'s faction shackle takes hold with a final spark."))
	return TRUE

/mob/living/proc/_faction_bound_spool_still_valid(seq)
	return seq == faction_bound_spool_seq

/mob/living/proc/_faction_bound_clear()
	PRIVATE_PROC(TRUE)
	_faction_bound_clear_restrained_state()
	REMOVE_TRAIT(src, TRAIT_FACTION_BOUND, TRAIT_SOURCE_FACTION_TAGGER)
	faction_bound_uid = null
	persistence_set_faction_bound(ckey, real_name, FALSE, null)

/mob/living/carbon/human/faction_tagger_compatible()
	return isipc(src)

/mob/living/silicon/robot/faction_tagger_compatible()
	return TRUE

/**
 * Restrain/unrestrain authorization gate -- separate from, and generally
 * looser than, can_configure_faction_shackle()'s officer-rank requirement
 * used for applying/releasing the shackle itself. Any actual member of the
 * faction the target is already shackled to (rank 0+, i.e. ordinary crew)
 * may toggle restraint on them -- EXCEPT the Hub faction specifically,
 * which requires officer/command (rank 1+, the same threshold shackle
 * apply/release already use) since handling Hub personnel is meant to
 * stay an officer-level call. get_effective_faction_rank()
 * (persistence_factions.dm) already covers admin bypass, ckey/rank lookup,
 * and the bearer master card case -- its -1 sentinel (not a member at all)
 * fails both branches below regardless of faction.
 */
/proc/_can_toggle_faction_restrained(mob/user, faction_uid)
	var/required_rank = (normalize_faction_uid(faction_uid) == "hub") ? 1 : 0
	return get_effective_faction_rank(user, faction_uid) >= required_rank

/// Silent internal clear -- no messaging, used when the shackle itself is
/// being wiped entirely (_faction_bound_clear()) rather than a deliberate
/// restrain/unrestrain action. The user-facing toggle below has its own
/// flavor text and calls this too, so the trait/visual teardown only lives
/// in one place.
/mob/living/proc/_faction_bound_clear_restrained_state()
	PRIVATE_PROC(TRUE)
	if(!HAS_TRAIT(src, TRAIT_FACTION_RESTRAINED))
		return
	REMOVE_TRAIT(src, TRAIT_FACTION_RESTRAINED, TRAIT_SOURCE_FACTION_TAGGER)
	_update_faction_restrained_visual(FALSE)

/**
 * Restrain/unrestrain toggle -- a separate, opt-in action layered on top of
 * an existing shackle (TRAIT_FACTION_BOUND), never implied by it. Callers
 * (faction_tagger.dm's "restrain"/"unrestrain" ui_act() cases) have already
 * checked _can_toggle_faction_restrained() and that the target is actually
 * shackled -- this proc only applies the trait, the visual, and the
 * flavor text.
 */
/mob/living/proc/_faction_bound_set_restrained(new_state, mob/user)
	PRIVATE_PROC(TRUE)
	if(new_state)
		ADD_TRAIT(src, TRAIT_FACTION_RESTRAINED, TRAIT_SOURCE_FACTION_TAGGER)
		_update_faction_restrained_visual(TRUE)
		to_chat(src, SPAN_DANGER("[user] restrains you with a faction tagger."))
		visible_message(SPAN_DANGER("[user] restrains [src] with a faction tagger."))
	else
		_faction_bound_clear_restrained_state()
		to_chat(src, SPAN_GOOD("[user] releases your restraints with a faction tagger."))
		visible_message(SPAN_NOTICE("[user] releases [src]'s restraints with a faction tagger."))

/// Base stub -- only human/robot (the two faction_tagger_compatible() types)
/// ever actually get restrained, so this is just here so the call site in
/// _faction_bound_set_restrained()/_faction_bound_clear_restrained_state()
/// (typed /mob/living) compiles regardless of which subtype it runs on.
/mob/living/proc/_update_faction_restrained_visual(new_state)
	return

/// Reuses the exact overlay slot/art update_inv_handcuffed()
/// (human/update_icons.dm) already uses for real handcuffs -- if the mob is
/// ALSO wearing real cuffs, skip touching the slot entirely rather than
/// fight over it (accepted as a known, minor edge case).
/mob/living/carbon/human/_update_faction_restrained_visual(new_state)
	if(handcuffed)
		return
	overlays_raw[HANDCUFF_LAYER] = new_state ? image('icons/mob/mob.dmi', "handcuff1") : null
	update_icon()

/// No existing lockdown visual to hook into (SetLockdown()/lock_charge is
/// purely mechanical, robot.dm) -- a straightforward color tint instead,
/// captured/restored the same "grab original once, restore on release"
/// shape faction-tagged clothing already uses (persistence_faction_tagger.dm).
/mob/living/silicon/robot/_update_faction_restrained_visual(new_state)
	if(new_state)
		faction_restrained_original_color = color
		color = COLOR_DARK_RED
	else
		color = faction_restrained_original_color
		faction_restrained_original_color = null

/// New verb, visible any time this mob is shackled -- opens the small
/// status/break-free window. Deliberately its own dedicated interface
/// rather than hooking into either mob type's own existing UI: IPC/human
/// has no status panel suited to this, and the robotics console is built
/// for the CONTROLLING side, not the bound mob itself.
/mob/living/verb/attempt_break_free_of_faction_shackle()
	set name = "Break Free of Shackle"
	set category = "IC"
	set src = usr

	if(!HAS_TRAIT(src, TRAIT_FACTION_BOUND))
		to_chat(src, SPAN_WARNING("You are not shackled to anything."))
		return
	if(!faction_bound_status_ui)
		faction_bound_status_ui = new(src)
	faction_bound_status_ui.ui_interact(src)

/mob/living/proc/_attempt_break_free_faction_bound()
	if(!HAS_TRAIT(src, TRAIT_FACTION_BOUND))
		return
	if(world.time < faction_bound_break_attempt_at)
		to_chat(src, SPAN_WARNING("You aren't ready to try again -- [round((faction_bound_break_attempt_at - world.time) / 10)] second\s left."))
		return

	var/held_faction = faction_bound_uid
	visible_message(SPAN_WARNING("[src] fights to overload their own faction shackle!"))

	if(prob(FACTION_BOUND_BREAK_FREE_CHANCE))
		_faction_bound_clear()
		to_chat(src, SPAN_GOOD("The shackle overloads and burns out -- you're free!"))
		visible_message(SPAN_GOOD("[src]'s faction shackle shatters in a burst of sparks!"))
		spark(src, 3)
		// NOTE: no dedicated "combat drone dying" sound exists in this repo
		// yet -- using a generic spark stinger as a placeholder. Swap for a
		// real one under this same call once you have a file for it.
		playsound(src, pick('sound/effects/sparks1.ogg', 'sound/effects/sparks2.ogg', 'sound/effects/sparks3.ogg', 'sound/effects/sparks4.ogg'), 50, TRUE)
		announce_faction_bound_event(held_faction, "[real_name] has broken free of their shackle.")
		return

	faction_bound_break_attempt_at = world.time + FACTION_BOUND_BREAK_FREE_COOLDOWN
	to_chat(src, SPAN_WARNING("The shackle holds -- and the overload attempt backfires on you!"))
	visible_message(SPAN_WARNING("[src]'s faction shackle crackles violently, punishing the attempt!"))
	announce_faction_bound_event(held_faction, "[real_name] attempted to break free of their shackle and failed.")
	_apply_faction_bound_failure_damage(src)

/**
 * Faction-wide "broke free"/"attempted to break free" notice -- generalized
 * past announce_faction_event()'s (persistence_factions.dm) human-only
 * typing and live-ID-derived membership, since a cyborg needs to be able
 * to both trigger and receive this, and the event is anchored to the
 * shackle's STORED faction_uid, not whatever the bound mob's own ID
 * currently says (which may have changed or been removed).
 */
/proc/announce_faction_bound_event(faction_uid, message)
	if(!faction_uid)
		return
	var/fname = get_faction_name(faction_uid)
	for(var/mob/living/M in GLOB.player_list)
		if(!M.client)
			continue
		var/obj/item/card/id/ID = M.GetIdCard()
		var/m_uid = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
		if(m_uid != faction_uid)
			continue
		to_chat(M, SPAN_NOTICE("<b>[fname]:</b> [message]"))

/**
 * Failed break-free penalty -- deliberately capped well below any
 * limb-loss/death threshold for either mob type (see faction_bound.dm's
 * plan notes: neither apply_damage() nor take_overall_damage() have a
 * built-in safe cap, so this is new, conservative, single-purpose code,
 * not a general damage utility).
 */
/proc/_apply_faction_bound_failure_damage(mob/living/L)
	if(isrobot(L))
		_apply_faction_bound_robot_damage(L)
	else if(ishuman(L))
		_apply_faction_bound_ipc_damage(L)

/// Chest specifically -- the one limb that structurally cannot be
/// amputated (no ORGAN_CAN_AMPUTATE on it), which trivially guarantees
/// "never limb loss." Roll range kept well under its max_damage (100) with
/// a wide safety margin against organ-splash risk into the posibrain (the
/// only actual IPC death path).
/proc/_apply_faction_bound_ipc_damage(mob/living/carbon/human/H)
	var/amount = rand(FACTION_BOUND_DAMAGE_MIN, FACTION_BOUND_DAMAGE_MAX)
	H.apply_damage(amount, DAMAGE_BURN, BP_CHEST)

/// Picks one installed, non-critical component (excluding the actuator --
/// destroying it would cripple movement independent of the shackle, a
/// worse outcome than "damage" implies) and clamps the roll to that
/// component's own remaining headroom, so it can never reach its
/// destroy() threshold.
/proc/_apply_faction_bound_robot_damage(mob/living/silicon/robot/R)
	var/list/safe_components = list()
	for(var/key in R.components)
		if(key == "actuator")
			continue
		var/datum/robot_component/C = R.components[key]
		if(C && C.installed == 1)
			safe_components += C
	if(!length(safe_components))
		return
	var/datum/robot_component/picked = pick(safe_components)
	var/headroom = picked.max_damage - (picked.brute_damage + picked.electronics_damage) - 5
	if(headroom <= 0)
		return
	var/amount = min(rand(FACTION_BOUND_DAMAGE_MIN, FACTION_BOUND_DAMAGE_MAX), headroom)
	if(amount <= 0)
		return
	picked.take_damage(amount, 0)
	R.updatehealth()

/datum/tgui_module/faction_bound_status
	var/mob/living/owner

/datum/tgui_module/faction_bound_status/New(mob/living/L)
	. = ..()
	owner = L

/datum/tgui_module/faction_bound_status/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FactionBoundStatus", "Shackle Status", 380, 220)
		ui.open()

/datum/tgui_module/faction_bound_status/ui_data(mob/user)
	var/list/data = list()
	if(!owner)
		return data
	data["bound"] = HAS_TRAIT(owner, TRAIT_FACTION_BOUND)
	data["faction_uid"] = owner.faction_bound_uid
	data["faction_name"] = owner.faction_bound_uid ? get_faction_name(owner.faction_bound_uid) : null
	data["cooldown_seconds_left"] = (world.time < owner.faction_bound_break_attempt_at) ? round((owner.faction_bound_break_attempt_at - world.time) / 10) : 0
	// Third parties (multitool.dm's own read-only reflection) see the same
	// data but never the break-free control -- ui_act() below already
	// refuses the action for anyone but the owner, this just keeps the
	// button from being shown greyed-out/confusingly to someone who could
	// never actually use it.
	data["is_self"] = (user == owner)
	data["target_name"] = owner.name
	return data

/datum/tgui_module/faction_bound_status/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(!owner || usr != owner)
		return
	if(action == "break_free")
		owner._attempt_break_free_faction_bound()
		. = TRUE

/**
 * Restores a still-active shackle on reconnect/body-repossession --
 * ss13_mob_position's faction_bound/faction_bound_uid columns (V149
 * migration) are the source of truth, checked live off the in-memory
 * cache persistence_set_faction_bound() keeps in sync. Only IPCs/cyborgs
 * can ever have been bound in the first place (faction_tagger_compatible()),
 * but the check itself is cheap and type-agnostic, so it lives once on
 * /mob/living rather than duplicated per type.
 */
/mob/living/Login()
	. = ..()
	if(!ckey || !real_name || HAS_TRAIT(src, TRAIT_FACTION_BOUND))
		return
	var/restored_uid = persistence_character_faction_bound(ckey, real_name)
	if(!restored_uid)
		return
	faction_bound_uid = restored_uid
	ADD_TRAIT(src, TRAIT_FACTION_BOUND, TRAIT_SOURCE_FACTION_TAGGER)
	to_chat(src, SPAN_DANGER("You are still shackled to [get_faction_name(restored_uid)]."))
