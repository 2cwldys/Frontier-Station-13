/*
 * Dermal Regenerator
 * A reusable medical device with three modes, chosen via a TGUI prompt each
 * time it's used:
 *   - Repair Facial Damage: clears disfigurement and heals brute/burn damage
 *     on the head. Quick (3 seconds).
 *   - Restore Husk: reverses the HUSK mutation and heals burn damage across
 *     the whole body -- a longer, more involved cycle (15 seconds) with its
 *     own looping sound and a blue glow on the patient while it runs.
 *   - Change Appearance: hair/facial hair/skin/eye color only
 *     (APPEARANCE_DERMAL_REGENERATOR, __DEFINES/mobs.dm) -- never style,
 *     race, or gender. That split is what separates this mode from a mirror
 *     (style only, self-use only) and from the cosmetic_surgery_kit (a
 *     painful, single-use, self-only "become a new identity" tool that
 *     deliberately does NOT persist) -- this one is calm, reusable, works on
 *     someone else with their consent, and DOES persist to the character's
 *     saved record (persistence_sync_appearance_to_db(), appearance.dm,
 *     called from human_appearance.dm's ui_close() whenever this item is
 *     what opened the dialog). The other two modes never touch persistence
 *     -- they're just healing, no appearance actually changes.
 */
/obj/item/dermal_regenerator
	name = "dermal regenerator"
	desc = "A hand-held medical device that resurfaces skin, hair follicles, and iris pigment, repairs facial trauma, or reverses severe burn husking. Cosmetic changes are color only -- it can't alter someone's underlying features."
	// Borrowed sprite from the cosmetic surgery auto-kit -- PLACEHOLDER until
	// dedicated sprite work is done, same approach already used elsewhere
	// this session for a new item with no art of its own yet.
	icon = 'icons/obj/item/autoimplanter.dmi'
	icon_state = "autoimplanter"
	item_state = "electronic"
	slot_flags = SLOT_BELT
	throwforce = 2
	throw_speed = 1
	throw_range = 5
	w_class = WEIGHT_CLASS_SMALL
	origin_tech = list(
		TECH_BIO = 3,
		TECH_MAGNET = 2
	)

	var/static/list/dermal_regenerator_choices = list("Repair Facial Damage", "Restore Husk", "Change Appearance")

/// Self-use -- no consent prompt needed, you're the one holding it against yourself.
/obj/item/dermal_regenerator/attack_self(mob/living/carbon/human/user)
	if(!istype(user))
		return
	_use_on(user, user)

/// Used on someone else -- a genuine medical-tool use case, gated on their
/// consent (same alert-then-revalidate shape resleever.dm's own
/// _insert_occupant() uses) unless they're unconscious/dead/have no client,
/// in which case there's no one to ask.
/obj/item/dermal_regenerator/attack(mob/living/carbon/human/M, mob/living/user, target_zone)
	if(!istype(M) || !istype(user))
		return
	if(M == user)
		return attack_self(user)

	if(M.stat == CONSCIOUS && M.client)
		var/original_loc = M.loc
		if(alert(M, "Would you like [user] to use a dermal regenerator on you?", "Dermal Regenerator", "Yes", "No") != "Yes")
			return
		if(QDELETED(M) || QDELETED(user) || M.loc != original_loc || !user.Adjacent(M))
			return

	_use_on(user, M)

/// Shared mode-select + dispatch for both self- and other-use. `user` is
/// whoever's holding the device; `M` is whoever it's being used on (== user
/// for self-use). Each mode handles its own do_after -- Restore Husk's is
/// much longer and has its own sound/visual, so there's no single shared
/// channel duration to factor out here.
/obj/item/dermal_regenerator/proc/_use_on(mob/living/user, mob/living/carbon/human/M)
	var/choice = tgui_alert(user, "What would you like to do with \the [src]?", "Dermal Regenerator", dermal_regenerator_choices)
	if(!choice)
		return
	if(QDELETED(M) || QDELETED(user) || !user.Adjacent(M))
		return

	switch(choice)
		if("Repair Facial Damage")
			_repair_face(user, M)
		if("Restore Husk")
			_restore_husk(user, M)
		if("Change Appearance")
			_change_appearance(user, M)

/// Quick mode -- clears disfigurement and heals the head's brute/burn
/// damage. Deliberately not gated behind surgery (open face, trained skill)
/// the way a real reconstructive procedure is -- that's the tradeoff of
/// this being a fast, hand-held fix instead.
/obj/item/dermal_regenerator/proc/_repair_face(mob/living/user, mob/living/carbon/human/M)
	var/obj/item/organ/external/head/head = M.get_organ(BP_HEAD)
	if(!istype(head))
		to_chat(user, SPAN_WARNING("\The [M] has no head to repair!"))
		return
	if(!head.disfigured && !head.brute_dam && !head.burn_dam)
		to_chat(user, SPAN_NOTICE("\The [M == user ? "your" : "[M]'s"] face shows no damage to repair."))
		return

	var/self_use = (M == user)
	user.visible_message(
		SPAN_NOTICE("\The [user] holds \the [src] up to [self_use ? "[user.get_pronoun("his")] own" : "[M]'s"] skin."),
		SPAN_NOTICE("You hold \the [src] up to [self_use ? "your" : "[M]'s"] skin."),
		range = 3
	)
	if(!do_after(user, 3 SECONDS, M))
		return
	if(QDELETED(M) || !user.Adjacent(M))
		return

	head.disfigured = FALSE
	head.heal_damage(head.brute_dam, head.burn_dam, TRUE, TRUE)
	M.update_body()
	M.UpdateDamageIcon()

	user.visible_message(
		SPAN_NOTICE("\The [user] finishes repairing [self_use ? "[user.get_pronoun("his")] own" : "[M]'s"] facial damage with \the [src]."),
		SPAN_NOTICE("You finish repairing [self_use ? "your own" : "[M]'s"] facial damage."),
		range = 3
	)

/// Longer, more involved mode -- reverses the HUSK mutation and heals burn
/// damage across the whole body, since a husked patient is otherwise left
/// cosmetically cured but still critically burned underneath. 15-second
/// channel with a looping sound and a blue glow on the patient the whole
/// time, both cleaned up on success, interruption, or the patient/user
/// going away mid-channel.
/obj/item/dermal_regenerator/proc/_restore_husk(mob/living/user, mob/living/carbon/human/M)
	if(!(M.mutations & HUSK) && !M.getFireLoss())
		to_chat(user, SPAN_NOTICE("\The [M == user ? "you show" : "[M] shows"] no signs of husking to restore."))
		return

	var/self_use = (M == user)
	user.visible_message(
		SPAN_NOTICE("\The [user] holds \the [src] up against [self_use ? "[user.get_pronoun("his")] own" : "[M]'s"] husked skin. It begins to hum."),
		SPAN_NOTICE("You hold \the [src] up against [self_use ? "your own" : "[M]'s"] husked skin. It begins to hum."),
		range = 3
	)

	var/datum/looping_sound/dermal_regenerator/soundloop = new(user, TRUE)
	M.set_light(1.5, 2, LIGHT_COLOR_BLUE)

	var/success = do_after(user, 15 SECONDS, M)

	QDEL_NULL(soundloop)
	if(!QDELETED(M))
		M.set_light(0)

	if(!success || QDELETED(M) || !user.Adjacent(M))
		return

	M.mutations &= ~HUSK
	M.heal_organ_damage(0, M.getFireLoss())
	M.update_body()
	M.UpdateDamageIcon()

	user.visible_message(
		SPAN_NOTICE("\The [user] finishes restoring [self_use ? "[user.get_pronoun("his")] own" : "[M]'s"] husked skin with \the [src]."),
		SPAN_GOOD("You finish restoring [self_use ? "your own" : "[M]'s"] husked skin."),
		range = 3
	)

/// Color-only appearance mode -- opens the shared appearance dialog
/// (change_appearance(), appearance.dm), scoped to hair/facial hair/skin/eye
/// color. Persists via human_appearance.dm's ui_close(), which recognizes
/// this item as the state_object.
/obj/item/dermal_regenerator/proc/_change_appearance(mob/living/user, mob/living/carbon/human/M)
	var/self_use = (M == user)
	user.visible_message(
		SPAN_NOTICE("\The [user] holds \the [src] up to [self_use ? "[user.get_pronoun("his")] own" : "[M]'s"] skin."),
		SPAN_NOTICE("You hold \the [src] up to [self_use ? "your" : "[M]'s"] skin."),
		range = 3
	)
	if(!do_after(user, 3 SECONDS, M))
		return
	if(QDELETED(M) || !user.Adjacent(M))
		return

	M.change_appearance(APPEARANCE_DERMAL_REGENERATOR, user, ui_state = GLOB.default_state, state_object = src)
