/*
 * Dermal Regenerator
 * A reusable medical device that resurfaces skin, hair follicles, and the
 * eyes' iris pigment -- pure color changes only (hair/facial hair/skin/eye
 * color, APPEARANCE_DERMAL_REGENERATOR, __DEFINES/mobs.dm), never style,
 * race, or gender. That split is what separates this from a mirror (style
 * only, self-use only) and from the cosmetic_surgery_kit (a painful,
 * single-use, self-only "become a new identity" tool that deliberately does
 * NOT persist) -- this one is calm, reusable, works on someone else with
 * their consent, and DOES persist to the character's saved record
 * (persistence_sync_appearance_to_db(), appearance.dm, called from
 * human_appearance.dm's ui_close() whenever this item is what opened the
 * dialog).
 */
/obj/item/dermal_regenerator
	name = "dermal regenerator"
	desc = "A hand-held medical device that resurfaces skin, hair follicles, and iris pigment. Changes color only -- it can't alter someone's underlying features."
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

/// Self-use -- no consent prompt needed, you're the one holding it against yourself.
/obj/item/dermal_regenerator/attack_self(mob/living/carbon/human/user)
	if(!istype(user))
		return

	user.visible_message(
		SPAN_NOTICE("\The [user] holds \the [src] up to [user.get_pronoun("his")] own skin."),
		SPAN_NOTICE("You hold \the [src] up to your skin."),
		range = 3
	)
	if(!do_after(user, 3 SECONDS, user))
		return

	user.change_appearance(APPEARANCE_DERMAL_REGENERATOR, user, ui_state = GLOB.default_state, state_object = src)

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

	user.visible_message(
		SPAN_NOTICE("\The [user] holds \the [src] up to [M]'s skin."),
		SPAN_NOTICE("You hold \the [src] up to [M]'s skin."),
		range = 3
	)
	if(!do_after(user, 3 SECONDS, M))
		return
	if(QDELETED(M) || !user.Adjacent(M))
		return

	M.change_appearance(APPEARANCE_DERMAL_REGENERATOR, user, ui_state = GLOB.default_state, state_object = src)
