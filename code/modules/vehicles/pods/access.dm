/*
 * Pod ID-based ownership/access -- replaces the leftover bike.dm "key"
 * examine text with something real. Built entirely on real, already-shipping
 * patterns rather than invented from scratch:
 *   - Claim-on-first-swipe + re-swipe-to-toggle-lock, same shape as
 *     /obj/structure/closet/secure_closet/personal
 *     (code/game/objects/structures/crates_lockers/closets/secure/personal.dm) --
 *     ownership keyed on the swiped card's registered_name string.
 *   - Faction ownership option keyed on normalize_faction_uid(employer_faction),
 *     the same comparison already used by faction-scoped airlocks
 *     (code/game/objects/structures/machinery/doors/airlock.dm) and drydock
 *     ship crew checks (code/modules/telesci/telepad_drydock_boarding.dm).
 * Deliberately not reusing IPC's ipc_tag organ (body/organ-coupled, no
 * gating proc exists for it) or req_access/req_one_access lists (a
 * staff/crew-manifest model, not a single-owner-or-faction model).
 */
/obj/vehicle/bike/pod
	/// Personal claim -- an ID's registered_name string, or null if unclaimed
	/// or faction-claimed instead. Mutually exclusive with owner_faction.
	var/owner_name
	/// Faction claim -- a normalize_faction_uid() result, or null. Mutually
	/// exclusive with owner_name.
	var/owner_faction

/// TRUE if boarding/access should be allowed: always true while unclaimed or
/// unlocked, otherwise requires the user's own ID to match the claim.
/obj/vehicle/bike/pod/proc/pod_allowed(mob/user)
	if(!locked || (!owner_name && !owner_faction))
		return TRUE
	return owner_matches(user)

/// TRUE only if user's ID actually matches this pod's claim -- unlike
/// pod_allowed(), there's no unlocked/unclaimed shortcut here. Boarding an
/// unlocked pod is deliberately open to anyone, but renaming (rename_via_tagger()
/// below) needs a real ownership match regardless of lock state, and refuses
/// outright on an unclaimed pod (nothing to match against).
/obj/vehicle/bike/pod/proc/owner_matches(mob/user)
	if(!owner_name && !owner_faction)
		return FALSE
	var/obj/item/card/id/id_card = user.GetIdCard()
	if(!id_card)
		return FALSE
	if(owner_name && id_card.registered_name == owner_name)
		return TRUE
	if(owner_faction && normalize_faction_uid(id_card.employer_faction) == owner_faction)
		return TRUE
	return FALSE

/// Handles swiping an ID (or anything with GetID(), per code/game/jobs/access.dm --
/// a bare ID, a wallet, a PDA) onto the pod. First swipe on an unclaimed pod
/// prompts personal vs. faction registration and locks it; subsequent swipes
/// toggle the lock for a matching ID, or refuse for a non-matching one.
/obj/vehicle/bike/pod/proc/swipe_id(mob/user, obj/item/swiped)
	var/obj/item/card/id/id_card = swiped.GetID()
	if(!id_card)
		return FALSE

	if(!owner_name && !owner_faction)
		var/choice = tgui_alert(user, "Register \the [src] to yourself, or to your faction?", "Pod Registration", list("Personal", "Faction", "Cancel"))
		if(choice == "Personal")
			owner_name = id_card.registered_name
			locked = TRUE
			to_chat(user, SPAN_NOTICE("You register \the [src] to yourself and lock it."))
		else if(choice == "Faction")
			if(!id_card.employer_faction)
				to_chat(user, SPAN_WARNING("\The [id_card] has no faction affiliation to register \the [src] to."))
				return TRUE
			owner_faction = normalize_faction_uid(id_card.employer_faction)
			locked = TRUE
			to_chat(user, SPAN_NOTICE("You register \the [src] to [get_faction_name(owner_faction)] personnel and lock it."))
		return TRUE

	if(pod_allowed(user))
		locked = !locked
		to_chat(user, SPAN_NOTICE("You [locked ? "lock" : "unlock"] \the [src]."))
	else
		to_chat(user, SPAN_WARNING("Access denied."))
	return TRUE

/**
 * Renames the pod via a faction tagger -- reachable if you own it personally,
 * or it's faction-claimed and your ID matches that faction. Deliberately not
 * routed through faction_tagger.dm's own faction_tagger_compatible()/
 * faction_tagger_set() machinery: that system's generic "set"/"release"
 * actions apply to any compatible target with no per-type gating at all,
 * keyed on faction officer rank -- a different ownership model than this
 * pod's own personal-or-faction claim, and making pods compatible with it
 * would open a second, conflicting way to reassign ownership on the same
 * object. This stays entirely inside the pod's own attackby()/access.dm.
 */
/obj/vehicle/bike/pod/proc/rename_via_tagger(mob/user)
	if(!owner_matches(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return
	var/new_name = tgui_input_text(user, "Enter a new name for \the [src]:", "Rename Pod", name, 42)
	if(!new_name || !length(new_name))
		return
	name = new_name
	to_chat(user, SPAN_NOTICE("You rename \the [src] to [new_name]."))

/// Drops bike.dm's leftover "does not have a key in" line (pods never used
/// the physical-key ignition system, see pod.dm's spawns_with_key/key_type)
/// and adds ownership + occupant info in its place. Deliberately not listing
/// every POD_PART_* slot's contents here -- the cockpit tgui is where
/// installed parts actually get managed; examine only needs seats + owner.
/obj/vehicle/bike/pod/feedback_hints(mob/user, distance, is_adjacent)
	. = ..()
	. -= "\The [src] does not have a key in."
	. -= "\The [src] has \a [key] in."
	if(distance <= 4)
		if(owner_name)
			. += "\The [src] is registered to [owner_name]."
		else if(owner_faction)
			. += "\The [src] is registered to [get_faction_name(owner_faction)] personnel."
		. += "Pilot seat: [buckled ? "[buckled]" : "empty"]."
		. += "Passenger seat: [passenger ? "[passenger]" : "empty"]."
