/*
 * Resleever Machine
 * Transfers a neural lace consciousness into a new or original body.
 * Medical staff insert an extracted lace and a target body (or use adjacent
 * surgical table with stabilized original body).
 */

/obj/structure/machinery/resleever
	name = "resleeving machine"
	desc = "A medical device that transfers a neural lace consciousness into a new body."
	// Borrows the prison cryopod's sprite (cryopod_prison.dm) -- cryopod.dmi has
	// no "resleever" state, so this rendered as a blank tile.
	icon = 'icons/obj/machinery/bodyscanner.dmi'
	icon_state = "body_scanner"
	anchored = TRUE
	density = TRUE

	var/obj/item/organ/internal/neural_lace/inserted_lace = null
	var/mob/living/carbon/human/target_body = null

/obj/structure/machinery/resleever/examine(mob/user)
	. = ..()
	. += SPAN_NOTICE("Lace slot: [inserted_lace ? "[inserted_lace.registered_name]'s lace ([inserted_lace.lace_occupied ? "OCCUPIED" : "empty"])" : "empty"]")
	. += SPAN_NOTICE("Body slot: [target_body ? target_body.real_name : "no body"]")

/obj/structure/machinery/resleever/attack_hand(mob/user)
	if(..())
		return
	ui_interact(user)

/obj/structure/machinery/resleever/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Resleever", "Resleeving Machine", 420, 460)
		ui.open()

/obj/structure/machinery/resleever/ui_data(mob/user)
	var/list/data = list()

	data["lace_name"] = inserted_lace ? inserted_lace.registered_name : null
	data["lace_occupied"] = inserted_lace ? !!inserted_lace.lace_occupied : FALSE
	data["body_name"] = target_body ? target_body.real_name : null
	// Both halves have to be present, and the lace has to actually be carrying
	// somebody -- _do_resleeve() refuses otherwise, so surface it up front
	// rather than letting the button fail on click.
	data["can_resleeve"] = (inserted_lace && target_body && inserted_lace.lace_occupied) ? TRUE : FALSE

	var/obj/structure/machinery/clonepod/pod = get_linked_pod()
	data["linked_pod"] = pod ? TRUE : FALSE
	data["pod_occupied"] = (pod && pod.occupant) ? TRUE : FALSE
	data["pod_clone_name"] = (pod && pod.occupant) ? pod.occupant.real_name : null
	// A clone can only be ordered against a lace that names someone.
	data["can_order_clone"] = (pod && !pod.occupant && inserted_lace && inserted_lace.registered_name) ? TRUE : FALSE

	// 0 when cloning is free (CLONING_COSTS_CREDITS, _compile_options.dm), so
	// the UI advertises a price only when one is actually charged.
#ifdef CLONING_COSTS_CREDITS
	data["clone_cost"] = CLONE_ORDER_COST
	// Which account an order would hit, shown before the player commits.
	var/list/billing = pod ? pod.resolve_clone_billing(src) : null
	var/billing_faction = billing ? billing["faction"] : null
	data["clone_payer"] = billing_faction ? get_faction_name(billing_faction) : "personal account"
#else
	data["clone_cost"] = 0
	data["clone_payer"] = null
#endif

	return data

/obj/structure/machinery/resleever/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/living/user = usr
	if(!istype(user))
		return TRUE

	switch(action)
		if("eject_lace")
			if(!inserted_lace)
				return TRUE
			user.put_in_hands(inserted_lace)
			inserted_lace = null
			to_chat(user, SPAN_NOTICE("Lace removed."))
			return TRUE

		if("set_target")
			_pick_target_body(user)
			return TRUE

		if("clear_target")
			target_body = null
			return TRUE

		if("order_clone")
			var/obj/structure/machinery/clonepod/pod = get_linked_pod()
			if(!pod)
				to_chat(user, SPAN_WARNING("No cloning pod is linked to \the [src]."))
				return TRUE
			if(!inserted_lace)
				to_chat(user, SPAN_WARNING("Insert the neural lace to clone from first."))
				return TRUE
			pod.order_clone_from_lace(inserted_lace, user)
			return TRUE

		if("resleeve")
			if(tgui_alert(user, "Resleeve [inserted_lace ? inserted_lace.registered_name : "nobody"] into [target_body ? target_body.real_name : "nothing"]?", "Confirm Resleeve", list("Resleeve", "Cancel")) == "Resleeve")
				_do_resleeve(user)
			return TRUE

/// Shared body picker -- used by both the UI action and the legacy verb, so
/// the two can't drift apart.
/obj/structure/machinery/resleever/proc/_pick_target_body(mob/user)
	var/list/candidates = list()
	for(var/mob/living/carbon/human/H in range(2, src))
		if(H.stat == DEAD && !H.mind?.key)
			candidates["[H.real_name] at ([H.x],[H.y],[H.z])"] = H
		else if(H.stat == DEAD && H != target_body)
			candidates["[H.real_name] (HAS MIND - careful!) at ([H.x],[H.y],[H.z])"] = H
	// A freshly grown clone is UNCONSCIOUS rather than DEAD and has no mind,
	// so it wouldn't match the dead-body checks above -- offer it explicitly.
	var/obj/structure/machinery/clonepod/pod = get_linked_pod()
	if(pod && ishuman(pod.occupant))
		var/mob/living/carbon/human/clone = pod.occupant
		if(!clone.mind?.key)
			candidates["[clone.real_name] (clone, in the linked pod)"] = clone

	if(!length(candidates))
		to_chat(user, SPAN_WARNING("No suitable bodies nearby. A dead, mindless body or a grown clone is required."))
		return
	var/chosen = tgui_input_list(user, "Select target body:", "Set Target Body", candidates)
	if(!chosen)
		return
	target_body = candidates[chosen]
	to_chat(user, SPAN_NOTICE("Target body set to [target_body.real_name]."))

/obj/structure/machinery/resleever/attackby(obj/item/I, mob/user, params)
	// Multitool links this resleever to a cloning pod (resleever_cloning.dm).
	if(I.tool_behaviour == TOOL_MULTITOOL)
		return handle_multitool(I, user)

	// Insert a neural lace
	if(istype(I, /obj/item/organ/internal/neural_lace))
		var/obj/item/organ/internal/neural_lace/lace = I
		if(inserted_lace)
			to_chat(user, SPAN_WARNING("A lace is already inserted. Remove it first."))
			return
		if(user.r_hand == lace) user.drop_r_hand()
		else if(user.l_hand == lace) user.drop_l_hand()
		lace.forceMove(src)
		inserted_lace = lace
		to_chat(user, SPAN_NOTICE("You insert [lace.registered_name]'s neural lace."))
		return
	. = ..()

/obj/structure/machinery/resleever/verb/remove_lace()
	set name = "Remove Lace"
	set category = "Persistence"
	set src in oview(1)

	if(!inserted_lace)
		to_chat(usr, SPAN_WARNING("No lace inserted."))
		return
	usr.put_in_hands(inserted_lace)
	inserted_lace = null
	to_chat(usr, SPAN_NOTICE("Lace removed."))

/obj/structure/machinery/resleever/verb/set_target_body()
	set name = "Set Target Body"
	set category = "Persistence"
	set src in oview(2)

	// Delegates to the same picker the UI uses, so the verb and the interface
	// can never offer different candidate sets.
	_pick_target_body(usr)

/obj/structure/machinery/resleever/proc/_do_resleeve(mob/living/user)
	if(!inserted_lace || !target_body)
		to_chat(user, SPAN_WARNING("Both a lace and a target body are required."))
		return

	if(!inserted_lace.lace_occupied || !inserted_lace.lace_mob)
		to_chat(user, SPAN_WARNING("The lace does not contain a consciousness."))
		return

	if(QDELETED(target_body))
		to_chat(user, SPAN_WARNING("The target body is gone."))
		target_body = null
		return

	// Install the lace into the new body's head
	var/obj/item/organ/external/head = target_body.get_organ(BP_HEAD)
	if(!head)
		to_chat(user, SPAN_WARNING("Target body has no head — cannot install lace."))
		return

	// Check no existing lace
	for(var/obj/item/organ/internal/neural_lace/existing in target_body.internal_organs)
		to_chat(user, SPAN_WARNING("Target body already has a neural lace installed."))
		return

	playsound(src, 'sound/machines/chime.ogg', 75, 1)
	to_chat(user, SPAN_NOTICE("Beginning resleeve procedure..."))
	sleep(3 SECONDS)

	// Move lace into body
	inserted_lace.forceMove(target_body)
	head.internal_organs |= inserted_lace
	target_body.internal_organs |= inserted_lace
	target_body.internal_organs_by_name[inserted_lace.organ_tag] = inserted_lace
	inserted_lace.owner = target_body

	// Transfer consciousness
	var/mob/living/carbon/lace_mob/LM = inserted_lace.lace_mob
	LM.forceMove(get_turf(target_body))
	LM.mind.transfer_to(target_body)

	// Update body vitals
	target_body.set_stat(CONSCIOUS)
	target_body.real_name = inserted_lace.registered_name
	target_body.name = inserted_lace.registered_name
	if(istype(target_body, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = target_body
		H.set_id_info(H)

	// The character is embodied again -- clear the in_lace/dead_body state so a
	// future reconnect (or server restart) doesn't route them back to the lace.
	persistence_set_char_state(inserted_lace.registered_ckey, inserted_lace.registered_name, "alive")

	inserted_lace.lace_occupied = FALSE
	inserted_lace.lace_mob = null
	qdel(LM)

	to_chat(target_body, SPAN_GOOD("You are resleeved. Welcome back."))
	to_chat(user, SPAN_GOOD("Resleeve successful. [inserted_lace.registered_name] is now in the new body."))
	log_game("[inserted_lace.registered_name] resleeved by [user.real_name] via resleever at ([x],[y],[z]).")

	inserted_lace = null
	target_body = null
