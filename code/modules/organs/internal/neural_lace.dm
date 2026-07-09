/*
 * Neural Lace — Consciousness Preservation Implant
 *
 * A head-mounted augment that preserves a player's consciousness on death.
 * When the host dies, their mind transfers into a dormant lace_mob inside
 * the lace item. Medics extract it via head surgery; it can then be resleeved
 * into a new or original body, or transferred to a lace storage pod.
 *
 * Flow:
 *   Install → death → mind → lace_mob → surgery extracts lace → resleever
 *                                      OR 10min timer → lace_storage pod
 */

// ============================================================
// NEURAL LACE ORGAN
// ============================================================

/// Damage thresholds for extracted lace
#define LACE_DAMAGE_NONE     0
#define LACE_DAMAGE_MINOR   26   // flickers — warning messages
#define LACE_DAMAGE_MODERATE 51  // static — consciousness hears interference
#define LACE_DAMAGE_SEVERE  76   // critical — consciousness degrading
#define LACE_DAMAGE_DESTROYED 100 // destroyed — mind lost

/obj/item/organ/internal/neural_lace
	name = "neural lace"
	desc = "A microscopic mesh of neural fibers that records and preserves consciousness."
	organ_tag = "neural_lace"
	parent_organ = BP_HEAD
	vital = FALSE
	robotic = ROBOTIC_MECHANICAL
	emp_coeff = 3
	is_augment = TRUE
	w_class = WEIGHT_CLASS_TINY
	icon = 'icons/obj/organs/neural_lace.dmi'
	icon_state = "cortical-stack"

	/// Physical/electronic damage to the extracted lace (0–100). Only accumulates when NOT installed.
	var/lace_damage = 0
	/// Maximum damage before the lace is destroyed and consciousness lost
	var/lace_max_damage = 100

	/// The disembodied consciousness mob (created on death while lace is still installed)
	var/mob/living/carbon/lace_mob/lace_mob = null
	/// TRUE when a consciousness is currently stored in this lace
	var/lace_occupied = FALSE
	/// Timer ID for auto-transfer to storage pod if not extracted in time
	var/auto_transfer_timer = null
	/// ckey of the registered owner (set on install)
	var/registered_ckey = ""
	/// Real name of the registered owner
	var/registered_name = ""
	/// Faction UID of the owner (for routing to faction storage)
	var/owner_faction = ""

/obj/item/organ/internal/neural_lace/Initialize(mapload, internal)
	. = ..()
	// _bind_to_owner is NOT called here — Initialize fires on every construction including
	// persistence restores (applyPersistentHealthData creates augments via new aug_path(mob)).
	// Install sites call _bind_to_owner explicitly: new_player.dm, replaced(), admin verb.

/obj/item/organ/internal/neural_lace/Destroy()
	if(auto_transfer_timer)
		deltimer(auto_transfer_timer)
		auto_transfer_timer = null
	if(lace_mob && !QDELETED(lace_mob))
		qdel(lace_mob)
	lace_mob = null
	return ..()

// ── Examine ───────────────────────────────────────────────────────────────────
/obj/item/organ/internal/neural_lace/examine(mob/user)
	. = ..()
	if(owner)
		return  // Still installed — no damage possible
	if(lace_damage >= LACE_DAMAGE_DESTROYED)
		. += SPAN_DANGER("The lace is completely destroyed. Any stored consciousness is gone.")
	else if(lace_damage >= LACE_DAMAGE_SEVERE)
		. += SPAN_DANGER("The lace is critically damaged. The stored consciousness is degrading rapidly.")
	else if(lace_damage >= LACE_DAMAGE_MODERATE)
		. += SPAN_WARNING("The lace shows significant damage. Repair it before resleeving.")
	else if(lace_damage >= LACE_DAMAGE_MINOR)
		. += SPAN_WARNING("The lace shows minor signs of wear. It remains functional.")
	else
		. += SPAN_NOTICE("The lace is in good condition.")
	if(lace_occupied)
		. += SPAN_ITALIC("A faint presence can be felt within.")

// ── Damage system (only when extracted — installed lace is protected by skull) ──

/// Deal damage to an extracted lace. Does nothing when installed.
/obj/item/organ/internal/neural_lace/proc/take_lace_damage(amount, damage_type = "physical")
	if(owner)
		return  // Protected inside body — cannot be damaged
	if(lace_damage >= LACE_DAMAGE_DESTROYED)
		return  // Already destroyed

	lace_damage = min(lace_damage + amount, lace_max_damage)
	_notify_damage_state(damage_type)

	if(lace_damage >= LACE_DAMAGE_DESTROYED)
		_destroy_consciousness()

/// Notify the stored consciousness of the damage state
/obj/item/organ/internal/neural_lace/proc/_notify_damage_state(damage_type)
	if(!lace_mob || !lace_occupied) return
	switch(lace_damage)
		if(LACE_DAMAGE_MINOR to LACE_DAMAGE_MODERATE - 1)
			to_chat(lace_mob, SPAN_WARNING("You feel a distant tremor — your lace has taken minor damage."))
		if(LACE_DAMAGE_MODERATE to LACE_DAMAGE_SEVERE - 1)
			to_chat(lace_mob, SPAN_WARNING("Interference. Your thoughts fray at the edges. The lace is moderately damaged."))
		if(LACE_DAMAGE_SEVERE to LACE_DAMAGE_DESTROYED - 1)
			to_chat(lace_mob, SPAN_DANGER("ERROR — CRITICAL LACE FAILURE — your consciousness is DEGRADING. Seek immediate repair!"))

/// Consciousness is lost when lace is destroyed
/obj/item/organ/internal/neural_lace/proc/_destroy_consciousness()
	if(lace_mob && !QDELETED(lace_mob))
		if(lace_mob.mind)
			to_chat(lace_mob, SPAN_DANGER("The lace collapses. You feel yourself dissolving into static... nothing..."))
			sleep(2 SECONDS)
			lace_mob.ghostize()  // Release as ghost — no body to return to
		qdel(lace_mob)
	lace_mob = null
	lace_occupied = FALSE
	name = "destroyed neural lace"
	desc = "The delicate neural mesh is completely fried. Nothing can be recovered from this."
	log_game("Neural lace destroyed — [registered_name] ([registered_ckey]) consciousness lost.")

/// Repair is done through attackby() welder logic; this proc handles programmatic repair (admin tools etc.)
/obj/item/organ/internal/neural_lace/proc/repair_lace_tier()
	if(owner || lace_damage >= LACE_DAMAGE_DESTROYED || lace_damage <= LACE_DAMAGE_NONE)
		return FALSE
	if(lace_damage >= LACE_DAMAGE_SEVERE)
		lace_damage = LACE_DAMAGE_MODERATE - 1
	else if(lace_damage >= LACE_DAMAGE_MODERATE)
		lace_damage = LACE_DAMAGE_MINOR - 1
	else if(lace_damage >= LACE_DAMAGE_MINOR)
		lace_damage = LACE_DAMAGE_NONE
	if(lace_mob && lace_occupied)
		to_chat(lace_mob, SPAN_NOTICE("You feel the interference recede. Someone is repairing your lace."))
	return TRUE

// ── Physical damage hooks (only active when extracted) ───────────────────────

/obj/item/organ/internal/neural_lace/attackby(obj/item/I, mob/user, params)
	// Welder repairs one full damage tier per use
	if(I.tool_behaviour == TOOL_WELDER && !owner)
		if(lace_damage >= LACE_DAMAGE_DESTROYED)
			to_chat(user, SPAN_WARNING("The lace is completely destroyed. No amount of welding can fix this."))
			return
		if(lace_damage <= LACE_DAMAGE_NONE)
			to_chat(user, SPAN_NOTICE("The lace is undamaged. No repairs needed."))
			return
		// Step down one tier
		var/old_damage = lace_damage
		if(lace_damage >= LACE_DAMAGE_SEVERE)
			lace_damage = LACE_DAMAGE_MODERATE - 1     // Severe → top of Moderate
		else if(lace_damage >= LACE_DAMAGE_MODERATE)
			lace_damage = LACE_DAMAGE_MINOR - 1        // Moderate → top of Minor
		else if(lace_damage >= LACE_DAMAGE_MINOR)
			lace_damage = LACE_DAMAGE_NONE              // Minor → undamaged
		playsound(src, 'sound/items/welder.ogg', 50, 1)
		to_chat(user, SPAN_NOTICE("You carefully reseal the lace's neural mesh. Damage reduced from [old_damage] to [lace_damage]."))
		if(lace_mob && lace_occupied)
			to_chat(lace_mob, SPAN_NOTICE("The interference clears somewhat. Someone is welding your lace."))
		return
	// Physical impact damages the lace
	if(!owner && I.force > 0)
		take_lace_damage(max(1, round(I.force * 0.3)), "physical")
		to_chat(user, SPAN_WARNING("The lace sparks from the impact!"))
	. = ..()

/obj/item/organ/internal/neural_lace/fire_act(exposed_temperature, exposed_volume)
	if(!owner)
		take_lace_damage(15, "fire")
		visible_message(SPAN_WARNING("\The [src] scorches from the heat!"))

/obj/item/organ/internal/neural_lace/emp_act(severity)
	if(!owner)
		// EMP is devastating to the electronics — lace is highly vulnerable
		var/emp_damage = 30 / severity  // severity 1 = heavy, 2 = medium, 4 = light
		take_lace_damage(emp_damage, "EMP")
		visible_message(SPAN_DANGER("\The [src] sparks violently from the electromagnetic pulse!"))

// ── Undef thresholds ──────────────────────────────────────────────────────────
/// Called when inserted into a mob — capture biometrics and register owner
/obj/item/organ/internal/neural_lace/proc/_bind_to_owner(mob/living/carbon/human/H)
	if(!istype(H)) return
	// Only show the install message when the lace is genuinely new (no prior owner).
	// Persistence restores set registered_ckey before calling _bind_to_owner, so they stay silent.
	var/is_fresh = !length(registered_ckey)
	registered_name = H.real_name
	if(H.ckey) registered_ckey = H.ckey
	if(H.employer_faction) owner_faction = normalize_faction_uid(H.employer_faction)
	else if(H.wear_id && istype(H.wear_id, /obj/item/card/id))
		var/obj/item/card/id/card = H.wear_id
		if(card.employer_faction) owner_faction = normalize_faction_uid(card.employer_faction)
	if(is_fresh)
		to_chat(H, SPAN_NOTICE("You feel a faint tingle at the base of your skull as the neural lace comes online."))
	add_verb(H, /mob/living/carbon/human/proc/check_neural_lace_status)

/// Called when surgically installed via the normal organ replacement path
/obj/item/organ/internal/neural_lace/replaced(mob/living/carbon/human/target, obj/item/organ/external/affected)
	_bind_to_owner(target)
	. = ..()

/// Called when surgically removed from a mob
/obj/item/organ/internal/neural_lace/removed(mob/living/carbon/human/target, mob/living/user, drop_organ = TRUE, detach = TRUE)
	remove_verb(target, /mob/living/carbon/human/proc/check_neural_lace_status)

	// If the host is dead and still has a mind attached, extraction is the
	// moment their consciousness gets captured into the lace -- not death.
	if(!lace_occupied && target.stat == DEAD && target.mind)
		registered_name = target.real_name
		if(target.ckey) registered_ckey = target.ckey
		if(target.wear_id && istype(target.wear_id, /obj/item/card/id))
			var/obj/item/card/id/card = target.wear_id
			if(card.employer_faction) owner_faction = normalize_faction_uid(card.employer_faction)

		lace_mob = new /mob/living/carbon/lace_mob(get_turf(target))
		lace_mob.name      = target.real_name
		lace_mob.real_name = target.real_name
		lace_mob.neural_lace = src
		if(target.dna)
			lace_mob.dna = target.dna.Clone()

		target.mind.transfer_to(lace_mob)
		lace_occupied = TRUE
		lace_mob.forceMove(src)

		to_chat(lace_mob, SPAN_NOTICE("Your body is dead. Your neural lace has been removed, and your consciousness now resides within it."))
		to_chat(lace_mob, SPAN_NOTICE("You can hear nearby voices. Whisper to communicate. Medical staff can resleeve you."))
		log_game("[registered_name] ([registered_ckey]) died and had their neural lace extracted -- consciousness captured.")

		var/datum/callback/cb = new /datum/callback(src, TYPE_PROC_REF(/obj/item/organ/internal/neural_lace, _auto_transfer_to_storage))
		auto_transfer_timer = addtimer(cb, 4 HOURS, TIMER_STOPPABLE | TIMER_DELETE_ME)
	. = ..()

/// Called when the 4-hour timer expires, or directly to route immediately
/// (e.g. a dead+logged-off despawn) — teleport lace to nearest faction/public storage.
/obj/item/organ/internal/neural_lace/proc/_auto_transfer_to_storage()
	if(auto_transfer_timer)
		deltimer(auto_transfer_timer)
	auto_transfer_timer = null
	// If still inside a body, surgically eject first
	if(owner && istype(owner, /mob/living/carbon/human))
		removed(owner, null, TRUE, TRUE)
		return  // removed() will call this again indirectly — but we clear the timer

	// Find a storage vault
	var/obj/structure/machinery/lace_storage/pod = _find_storage()
	if(pod && pod.store_lace(src))
		if(lace_mob)
			to_chat(lace_mob, SPAN_NOTICE("You feel yourself moved to a lace storage vault. Medical staff can retrieve you here."))
		log_game("[registered_name] lace auto-transferred to storage vault at ([pod.x],[pod.y],[pod.z]).")
	else
		if(lace_mob)
			to_chat(lace_mob, SPAN_NOTICE("No lace storage found. You remain where you are — seek medical attention."))

/obj/item/organ/internal/neural_lace/proc/_find_storage()
	// Priority 1: faction storage
	if(owner_faction)
		for(var/obj/structure/machinery/lace_storage/pod in world)
			if(is_station_level(pod.z) && pod.persistent_network == owner_faction && pod.has_free_slot())
				return pod
	// Priority 2: public storage
	for(var/obj/structure/machinery/lace_storage/pod in world)
		if(is_station_level(pod.z) && pod.persistent_network == "public" && pod.has_free_slot())
			return pod
	return null

// ============================================================
// LACE MOB — Disembodied Consciousness
// ============================================================

/mob/living/carbon/lace_mob
	name = "disembodied consciousness"
	real_name = "unknown"
	stat = DEAD
	invisibility = INVISIBILITY_OBSERVER
	density = FALSE
	anchored = FALSE
	layer = MOB_LAYER
	see_invisible = SEE_INVISIBLE_LEVEL_TWO

	/// Reference to the neural lace containing this consciousness
	var/obj/item/organ/internal/neural_lace/neural_lace = null

/mob/living/carbon/lace_mob/Initialize()
	. = ..()
	GLOB.dead_mob_list |= src
	GLOB.living_mob_list -= src

/mob/living/carbon/lace_mob/Destroy()
	GLOB.dead_mob_list -= src
	neural_lace = null
	return ..()

// Limit hearing range to 3 tiles; block radio (can't receive radio while dormant in a lace)
/mob/living/carbon/lace_mob/get_clarity(datum/say_message/msg)
	if(msg.say_mode == SAYMODE_RADIO)
		return CLARITY_NONE
	var/mob/speaker = msg.speaker
	if(speaker && get_dist(src, speaker) > 3)
		return CLARITY_NONE
	return ..()

// The base mob hear_message/display_message chain handles formatting and delivery automatically
// via the spatial grid (become_hearing_sensitive is called from mob/Initialize)

// Whisper verb — disembodied voice
/mob/living/carbon/lace_mob/verb/lace_whisper()
	set name = "Whisper"
	set category = "Persistence"
	set desc = "Speak as a disembodied voice."

	var/msg = sanitize(input(src, "What do you say?", "Disembodied Whisper") as text|null)
	if(!msg || !length(msg)) return

	// Deliver as a ghostly whisper to nearby mobs
	for(var/mob/M in range(2, src))
		to_chat(M, SPAN_ITALIC("...a disembodied voice whispers: \"[msg]\""))

	to_chat(src, SPAN_ITALIC("You whisper: \"[msg]\""))

// Override Move — confined to lace item when inside it
/mob/living/carbon/lace_mob/Move(newloc, dir, step_x, step_y)
	// Cannot move if inside the lace item
	if(istype(loc, /obj/item/organ/internal/neural_lace))
		return FALSE
	return ..()

// ============================================================
// EMERGENCY CONSCIOUSNESS ASSIGNMENT (ADMIN)
// ============================================================

/// Disaster recovery: when a player's body AND lace are both lost, an admin
/// can bind that player's consciousness to a blank lace, then run it through
/// the normal body_vat -> resleever pipeline to rebuild them a body.
/obj/item/organ/internal/neural_lace/verb/assign_consciousness()
	set name = "Assign Consciousness"
	set category = "Persistence"
	set src in view(1)
	set hidden = TRUE

	if(!check_rights(R_ADMIN))
		return
	if(owner)
		to_chat(usr, SPAN_WARNING("This lace is installed in someone. Extract it first."))
		return
	if(lace_occupied)
		to_chat(usr, SPAN_WARNING("This lace already holds a consciousness."))
		return

	var/target_ckey = tgui_input_text(usr, "Enter the ckey whose consciousness should be bound to this lace:", "Assign Consciousness")
	if(!target_ckey) return
	target_ckey = ckey(target_ckey)

	var/client/C = GLOB.directory[target_ckey]
	if(!C)
		to_chat(usr, SPAN_WARNING("No connected client found for ckey '[target_ckey]'."))
		return

	var/char_name = tgui_input_text(usr, "Character name to register the lace to:", "Assign Consciousness", C.prefs?.real_name)
	if(!char_name) return

	var/confirm = tgui_alert(usr, "Bind [target_ckey]'s consciousness to this lace as '[char_name]'? They will be pulled out of their current mob.", "Confirm", list("Bind", "Cancel"))
	if(confirm != "Bind") return

	// Re-validate after the blocking prompts -- state can change while they sit open.
	if(owner || lace_occupied)
		to_chat(usr, SPAN_WARNING("The lace's state changed while you were deciding. Aborting."))
		return
	C = GLOB.directory[target_ckey]
	if(!C)
		to_chat(usr, SPAN_WARNING("[target_ckey] disconnected. Aborting."))
		return

	lace_mob = new /mob/living/carbon/lace_mob(get_turf(src))
	lace_mob.name      = char_name
	lace_mob.real_name = char_name
	lace_mob.neural_lace = src

	// Ghosts/observers keep their mind -- transfer preserves it. A mob with
	// no mind (e.g. lobby) gets pulled in by ckey and a fresh mind built.
	if(C.mob?.mind)
		C.mob.mind.transfer_to(lace_mob)
	else
		lace_mob.ckey = target_ckey
		lace_mob.mind_initialize()

	registered_name = char_name
	registered_ckey = target_ckey
	lace_occupied = TRUE
	lace_mob.forceMove(src)

	to_chat(lace_mob, SPAN_NOTICE("Your consciousness has been bound to a neural lace. Medical staff can resleeve you into a new body."))
	to_chat(usr, SPAN_GOOD("[target_ckey]'s consciousness bound to the lace as '[char_name]'."))
	log_and_message_admins("bound [target_ckey]'s consciousness to a neural lace as '[char_name]'", usr)

/// Admin: install this lace into the VV-marked mob, skipping surgery.
/// Matches the surgical install semantics exactly (replaced() chain).
/obj/item/organ/internal/neural_lace/verb/assign_body()
	set name = "Assign Body"
	set category = "Persistence"
	set src in view(1)
	set hidden = TRUE

	if(!check_rights(R_ADMIN))
		return
	if(owner)
		to_chat(usr, SPAN_WARNING("This lace is already installed in [owner]. Extract it first."))
		return

	var/datum/marked = usr.client?.holder?.marked_datum
	if(!marked)
		to_chat(usr, SPAN_WARNING("No marked datum. Use VV -> Mark Object on the target mob first."))
		return
	var/mob/living/carbon/human/H = marked
	if(!istype(H))
		to_chat(usr, SPAN_WARNING("The marked datum is not a living human mob ([marked.type])."))
		return
	if(QDELETED(H))
		to_chat(usr, SPAN_WARNING("The marked mob no longer exists."))
		return
	for(var/obj/item/organ/internal/neural_lace/existing in H.internal_organs)
		to_chat(usr, SPAN_WARNING("[H.real_name] already has a neural lace installed."))
		return

	var/confirm = tgui_alert(usr, "Install this lace into [H.real_name]?", "Assign Body", list("Install", "Cancel"))
	if(confirm != "Install")
		return
	// Re-validate after the blocking prompt.
	if(owner || QDELETED(H))
		to_chat(usr, SPAN_WARNING("State changed while you were deciding. Aborting."))
		return

	forceMove(H)
	var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
	if(head)
		replaced(H, head)
	else
		// Species without a head limb -- register directly on the mob.
		owner = H
		H.internal_organs |= src
		H.internal_organs_by_name[organ_tag] = src

	to_chat(usr, SPAN_GOOD("Neural lace installed in [H.real_name]."))
	log_and_message_admins("assigned a neural lace into [H.real_name]'s body via Assign Body", usr)

#undef LACE_DAMAGE_NONE
#undef LACE_DAMAGE_MINOR
#undef LACE_DAMAGE_MODERATE
#undef LACE_DAMAGE_SEVERE
#undef LACE_DAMAGE_DESTROYED

// ============================================================
// PLAYER STATUS VERB
// ============================================================

/mob/living/carbon/human/proc/check_neural_lace_status()
	set name = "Check Neural Lace"
	set category = "Persistence"
	set desc = "Query your neural lace for a status report."

	var/obj/item/organ/internal/neural_lace/lace = internal_organs_by_name["neural_lace"]
	if(!lace)
		to_chat(src, SPAN_WARNING("Neural lace: not detected. Contact medical staff for installation."))
		return

	var/damage_desc
	if(lace.lace_damage >= 100)
		damage_desc = SPAN_DANGER("DESTROYED")
	else if(lace.lace_damage >= 76)
		damage_desc = SPAN_DANGER("SEVERE ([lace.lace_damage]/100)")
	else if(lace.lace_damage >= 51)
		damage_desc = SPAN_WARNING("MODERATE ([lace.lace_damage]/100)")
	else if(lace.lace_damage >= 26)
		damage_desc = SPAN_WARNING("MINOR ([lace.lace_damage]/100)")
	else
		damage_desc = SPAN_GOOD("NOMINAL")

	to_chat(src, SPAN_NOTICE("<b>Neural Lace Status Report</b>"))
	to_chat(src, SPAN_NOTICE("  Registered to: [lace.registered_name]"))
	to_chat(src, SPAN_NOTICE("  Integrity: [damage_desc]"))
	// Resolve faction from actual DB membership — not the ID card stamp,
	// which may have a stale or incorrect employer_faction value.
	var/live_faction = GLOB.config.sql_enabled ? persistence_get_player_faction(ckey) : null
	if(live_faction)
		var/faction_display = get_faction_name(live_faction) || live_faction
		to_chat(src, SPAN_NOTICE("  Faction routing: [faction_display]"))
	to_chat(src, SPAN_NOTICE("  Consciousness preservation: [lace.lace_occupied ? SPAN_WARNING("ACTIVE - consciousness stored") : SPAN_GOOD("STANDBY")]"))

