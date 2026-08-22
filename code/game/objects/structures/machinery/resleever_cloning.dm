/*
 * Resleever <-> Clone Pod cloning pipeline
 *
 * The intended operator flow:
 *   1. Multitool-link a cloning pod to a resleever (either order).
 *   2. Hold a neural lace to the pod and order a clone. The pod reads the
 *      character's identity off the lace, charges the clone fee, and grows a
 *      body wearing that character's own likeness.
 *   3. Move the clone into the resleever, insert the lace, and resleeve --
 *      the clone becomes that character's body for good.
 *
 * Billing follows the machines' faction tags: when the pod and the resleever
 * are both tagged to the SAME faction, that faction's account pays. Anything
 * else -- personal tags, untagged, or two different factions -- bills the
 * ordering character personally, rather than guessing which faction to charge.
 *
 * Whether cloning costs anything at all is the CLONING_COSTS_CREDITS toggle
 * (_compile_options.dm), along with the CLONE_ORDER_COST amount. With it
 * commented out every charge, refund and affordability check below is
 * compiled out and the UI stops advertising a price.
 */

// ---------------------------------------------------------------------------
// Faction/personal tagging -- mirrors the autodoc's (autodoc.dm), so the same
// faction tagger tool configures these.
// ---------------------------------------------------------------------------

/obj/structure/machinery/clonepod
	/// Faction UID this pod is tagged to, or "" for unrestricted.
	var/persistent_network = ""
	/// ckey this pod is personally tagged to, or null. Mutually exclusive
	/// with persistent_network.
	var/personal_ckey = null
	var/personal_char_name = null
	worldstate_vars = list("persistent_network", "personal_ckey", "personal_char_name")

/obj/structure/machinery/clonepod/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/clonepod/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/clonepod/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	personal_ckey = null
	personal_char_name = null
	return TRUE

/obj/structure/machinery/clonepod/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/structure/machinery/clonepod/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	persistent_network = ""
	return TRUE

/obj/structure/machinery/resleever
	var/persistent_network = ""
	var/personal_ckey = null
	var/personal_char_name = null
	/// Clone pod this resleever is multitool-linked to. Stored by position
	/// (below) rather than as an object reference, so the link survives the
	/// pod being rebuilt or the round restarting.
	var/obj/structure/machinery/clonepod/linked_pod = null
	/// Persisted coordinates of linked_pod, re-resolved on demand.
	var/linked_pod_x = 0
	var/linked_pod_y = 0
	var/linked_pod_z = 0
	worldstate_vars = list("persistent_network", "personal_ckey", "personal_char_name", "linked_pod_x", "linked_pod_y", "linked_pod_z")

/obj/structure/machinery/resleever/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/resleever/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/resleever/faction_tagger_set(new_uid, mob/user)
	persistent_network = new_uid
	personal_ckey = null
	personal_char_name = null
	return TRUE

/obj/structure/machinery/resleever/personal_tagger_get_owner()
	return personal_ckey ? "[personal_ckey]|[personal_char_name]" : null

/obj/structure/machinery/resleever/personal_tagger_set(mob/user)
	personal_ckey = user.ckey
	personal_char_name = user.real_name
	persistent_network = ""
	return TRUE

// ---------------------------------------------------------------------------
// Multitool linking
// ---------------------------------------------------------------------------

/// Resolves the linked pod from its saved coordinates. Object references don't
/// survive a restart, so the coordinates are the source of truth and this
/// repairs the reference in place whenever it's gone stale.
/obj/structure/machinery/resleever/proc/get_linked_pod()
	if(linked_pod && !QDELETED(linked_pod))
		return linked_pod
	linked_pod = null
	if(!linked_pod_z)
		return null
	var/turf/T = locate(linked_pod_x, linked_pod_y, linked_pod_z)
	if(!T)
		return null
	linked_pod = locate(/obj/structure/machinery/clonepod) in T
	return linked_pod

/// Links (or unlinks, if already linked to this pod) a cloning pod. Same
/// buffer-toggle shape the atmos console linking uses (atmo_control.dm).
/obj/structure/machinery/resleever/proc/link_clonepod(obj/structure/machinery/clonepod/pod, mob/user)
	if(!istype(pod))
		return
	if(get_linked_pod() == pod)
		linked_pod = null
		linked_pod_x = 0
		linked_pod_y = 0
		linked_pod_z = 0
		to_chat(user, SPAN_NOTICE("You unlink \the [pod] from \the [src]."))
		return
	var/turf/T = get_turf(pod)
	if(!T)
		return
	linked_pod = pod
	linked_pod_x = T.x
	linked_pod_y = T.y
	linked_pod_z = T.z
	to_chat(user, SPAN_NOTICE("You link \the [pod] to \the [src]."))

/// Multitool handling for the resleever, called from its own attackby
/// (resleever.dm) rather than defined here -- a second attackby definition for
/// the same type would be a duplicate. Returns TRUE if the tool was consumed.
/obj/structure/machinery/resleever/proc/handle_multitool(obj/item/multitool/MT, mob/user)
	if(!istype(MT))
		return FALSE
	var/obj/structure/machinery/clonepod/pod = MT.get_buffer(/obj/structure/machinery/clonepod)
	if(pod)
		link_clonepod(pod, user)
		MT.set_buffer(null)
		return TRUE
	MT.set_buffer(src)
	to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
	return TRUE

/// As above, for the clone pod -- called from its attackby in cloning.dm.
/obj/structure/machinery/clonepod/proc/handle_multitool(obj/item/multitool/MT, mob/user)
	if(!istype(MT))
		return FALSE
	var/obj/structure/machinery/resleever/sleever = MT.get_buffer(/obj/structure/machinery/resleever)
	if(sleever)
		sleever.link_clonepod(src, user)
		MT.set_buffer(null)
		return TRUE
	MT.set_buffer(src)
	to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
	return TRUE

// ---------------------------------------------------------------------------
// Clone ordering
// ---------------------------------------------------------------------------

/// Which account pays for a clone ordered through this pair, as
/// list("faction" = uid) or list("personal" = TRUE). Faction billing needs
/// BOTH machines tagged to the same faction -- a mismatch or any personal/
/// untagged machine falls back to the ordering character's own account rather
/// than picking one faction's treasury arbitrarily.
/obj/structure/machinery/clonepod/proc/resolve_clone_billing(obj/structure/machinery/resleever/sleever)
	var/pod_faction = normalize_faction_uid(persistent_network)
	var/sleever_faction = sleever ? normalize_faction_uid(sleever.persistent_network) : null
	if(pod_faction && sleever_faction && pod_faction == sleever_faction)
		return list("faction" = pod_faction)
	return list("personal" = TRUE)

/**
 * Builds a body wearing the saved likeness of one specific character.
 *
 * The lace only carries an identity (registered_ckey/registered_name), and
 * ss13_crew_records.blood_dna is a hash rather than a genome -- so the
 * character's own appearance has to come from their saved chargen row, which
 * is the same source their ordinary spawn uses.
 *
 * A throwaway /datum/preferences is used rather than the player's live one:
 * /datum/preferences/load_character() writes current_character back and calls
 * save_preferences(), which on a connected player's own datum would silently
 * re-point their character selection. This loads the slot directly instead,
 * leaving the player's session untouched.
 */
/proc/build_cloned_body_for_character(ckey, char_name, turf/spawn_turf)
	if(!ckey || !char_name || !spawn_turf)
		return null
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return null

	var/char_id
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT id FROM ss13_characters WHERE ckey = :ckey AND name = :name AND deleted_at IS NULL LIMIT 1",
		list("ckey" = ckey, "name" = char_name)
	)
	q.Execute()
	if(q.NextRow())
		char_id = text2num(q.item[1])
	qdel(q)
	if(!char_id)
		return null

	var/mob/living/carbon/human/clone = new(spawn_turf)
	var/datum/preferences/scratch = new()	// no client on purpose -- see above
	scratch.current_character = char_id
	try
		scratch.player_setup.load_character(null)
		scratch.copy_to(clone)
	catch(var/exception/e)
		log_debug("build_cloned_body_for_character: failed to apply likeness for '[char_name]' ([ckey]): [e]")
		qdel(scratch)
		qdel(clone)
		return null
	qdel(scratch)

	// The lace's registered name is authoritative -- copy_to() sets the name
	// from the saved slot, which is normally the same, but a character renamed
	// since the slot was written should still clone under the name the lace
	// (and every persistence record) actually uses.
	clone.real_name = char_name
	clone.name = char_name
	// Grown blank and unconscious: it has no mind until a lace is resleeved
	// into it, and it should not be walking around in the meantime.
	clone.set_stat(UNCONSCIOUS)
	return clone

/**
 * Orders a clone of whoever `lace` is registered to. Charges CLONE_ORDER_COST
 * to whichever account resolve_clone_billing() picks, then grows the body
 * inside the pod. Returns TRUE if a clone was produced.
 */
/obj/structure/machinery/clonepod/proc/order_clone_from_lace(obj/item/organ/internal/neural_lace/lace, mob/living/user)
	if(!istype(lace))
		return FALSE
	if(!lace.registered_ckey || !lace.registered_name)
		to_chat(user, SPAN_WARNING("\The [lace] carries no registered identity to clone from."))
		return FALSE
	if(occupant)
		to_chat(user, SPAN_WARNING("\The [src] is already occupied."))
		return FALSE

	var/obj/structure/machinery/resleever/sleever = null
	for(var/obj/structure/machinery/resleever/candidate in range(7, src))
		if(candidate.get_linked_pod() == src)
			sleever = candidate
			break

	var/list/billing = resolve_clone_billing(sleever)
	var/faction_uid = billing["faction"]
	var/payer_desc = faction_uid ? get_faction_name(faction_uid) : "your personal account"

#ifdef CLONING_COSTS_CREDITS
	if(tgui_alert(user, "Grow a clone of [lace.registered_name] for [CLONE_ORDER_COST] credits, billed to [payer_desc]?", "Order Clone", list("Order", "Cancel")) != "Order")
		return FALSE
#else
	if(tgui_alert(user, "Grow a clone of [lace.registered_name]?", "Order Clone", list("Order", "Cancel")) != "Order")
		return FALSE
#endif

	// Re-check after the prompt -- the pod may have been filled while it was open.
	if(occupant)
		to_chat(user, SPAN_WARNING("\The [src] is already occupied."))
		return FALSE

	if(!_charge_clone_fee(faction_uid, user, lace.registered_name))
		return FALSE

	var/mob/living/carbon/human/clone = build_cloned_body_for_character(lace.registered_ckey, lace.registered_name, get_turf(src))
	if(!clone)
		to_chat(user, SPAN_WARNING("\The [src] cannot find a genetic record for [lace.registered_name]."))
		_refund_clone_fee(faction_uid, user, lace.registered_name)
		return FALSE

	clone.forceMove(src)
	occupant = clone
	update_icon()
	playsound(src, 'sound/machines/chime.ogg', 60, 1)
	to_chat(user, SPAN_GOOD("\The [src] begins growing a clone of [lace.registered_name]."))
#ifdef CLONING_COSTS_CREDITS
	log_and_message_admins("ordered a clone of [lace.registered_name] ([lace.registered_ckey]) for [CLONE_ORDER_COST]cr, billed to [payer_desc].", user)
#else
	log_and_message_admins("ordered a clone of [lace.registered_name] ([lace.registered_ckey]) (cloning is free on this server).", user)
#endif
	return TRUE

/// Takes the clone fee. Returns FALSE (with the reason reported) if it can't.
/// Always succeeds when CLONING_COSTS_CREDITS is off -- cloning is free then.
/obj/structure/machinery/clonepod/proc/_charge_clone_fee(faction_uid, mob/living/user, clone_name)
	PRIVATE_PROC(TRUE)
#ifndef CLONING_COSTS_CREDITS
	return TRUE
#else
	// Names the subject so a faction's bank statement in Faction Management
	// (ss13_faction_transactions, read by faction_manage.dm) reads as
	// "Clone order -- Jane Doe" rather than an unattributable 10,000cr debit.
	var/reason = clone_name ? "Clone order -- [clone_name]" : "Clone order"
	if(faction_uid)
		// faction_debit() (persistence_factions.dm) does its own
		// insufficient-funds check and returns FALSE, writes the balance
		// through, and logs the transaction -- no need to pre-check.
		if(!faction_debit(faction_uid, CLONE_ORDER_COST, reason))
			to_chat(user, SPAN_WARNING("[get_faction_name(faction_uid)] cannot cover the [CLONE_ORDER_COST] credit clone fee."))
			return FALSE
		return TRUE

	var/obj/item/card/id/ID = user.GetIdCard()
	if(!ID || !ID.associated_account_number)
		to_chat(user, SPAN_WARNING("No bank account found on your ID."))
		return FALSE
	var/datum/money_account/account = SSeconomy.get_account(ID.associated_account_number)
	if(!account || account.suspended)
		to_chat(user, SPAN_WARNING("Your account is unavailable."))
		return FALSE
	if(account.money < CLONE_ORDER_COST)
		to_chat(user, SPAN_WARNING("You cannot afford the [CLONE_ORDER_COST] credit clone fee."))
		return FALSE
	SSeconomy.charge_to_account(ID.associated_account_number, "[src]", reason, "[src]", -CLONE_ORDER_COST)
	return TRUE
#endif

/// Reverses _charge_clone_fee() when the grow fails after payment. A no-op
/// when cloning is free -- nothing was taken to give back.
/obj/structure/machinery/clonepod/proc/_refund_clone_fee(faction_uid, mob/living/user, clone_name)
	PRIVATE_PROC(TRUE)
#ifdef CLONING_COSTS_CREDITS
	var/reason = clone_name ? "Clone order refund -- [clone_name]" : "Clone order refund"
	if(faction_uid)
		faction_credit(faction_uid, CLONE_ORDER_COST, reason)
		return
	var/obj/item/card/id/ID = user.GetIdCard()
	if(ID && ID.associated_account_number)
		SSeconomy.charge_to_account(ID.associated_account_number, "[src]", reason, "[src]", CLONE_ORDER_COST)
#endif
	return

#undef CLONE_ORDER_COST
