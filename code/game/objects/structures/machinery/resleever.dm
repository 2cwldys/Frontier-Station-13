/*
 * Resleever Machine
 * Transfers a neural lace consciousness into a new or original body.
 * Medical staff insert an extracted lace and a target body (or use adjacent
 * surgical table with stabilized original body).
 */

/obj/structure/machinery/resleever
	name = "resleeving machine"
	desc = "A medical device that transfers a neural lace consciousness into a new body."
	icon = 'icons/obj/machinery/cryopod.dmi'
	icon_state = "resleever"
	anchored = TRUE
	density = TRUE

	var/obj/item/organ/internal/neural_lace/inserted_lace = null
	var/mob/living/carbon/human/target_body = null

/obj/structure/machinery/resleever/examine(mob/user)
	. = ..()
	. += SPAN_NOTICE("Lace slot: [inserted_lace ? "[inserted_lace.registered_name]'s lace ([inserted_lace.lace_occupied ? "OCCUPIED" : "empty"])" : "empty"]")
	. += SPAN_NOTICE("Body slot: [target_body ? target_body.real_name : "no body"]")

/obj/structure/machinery/resleever/attack_hand(mob/user)
	// Context-sensitive interaction
	if(!inserted_lace && !target_body)
		to_chat(user, SPAN_NOTICE("Insert a neural lace or place a body adjacent to use this machine."))
		return

	if(inserted_lace && target_body)
		// Both present — perform resleeve
		if(tgui_alert(user, "Resleeve [inserted_lace.registered_name] into [target_body.real_name]?", "Confirm Resleeve", list("Resleeve", "Cancel")) == "Resleeve")
			_do_resleeve(user)
		return

	to_chat(user, SPAN_NOTICE("Lace: [inserted_lace ? inserted_lace.registered_name : "none"] | Body: [target_body ? target_body.real_name : "none"]"))

/obj/structure/machinery/resleever/attackby(obj/item/I, mob/user, params)
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

	// Look for a dead/empty body on adjacent surgical tables or floor
	var/list/candidates = list()
	for(var/mob/living/carbon/human/H in range(2, src))
		if(H.stat == DEAD && !H.mind?.key)
			candidates["[H.real_name] at ([H.x],[H.y],[H.z])"] = H
		else if(H.stat == DEAD && H != target_body)
			candidates["[H.real_name] (HAS MIND - careful!) at ([H.x],[H.y],[H.z])"] = H

	if(!length(candidates))
		to_chat(usr, SPAN_WARNING("No suitable bodies nearby. A dead, mindless body is required."))
		return

	var/chosen = tgui_input_list(usr, "Select target body:", "Set Target Body", candidates)
	if(!chosen) return
	target_body = candidates[chosen]
	to_chat(usr, SPAN_NOTICE("Target body set to [target_body.real_name]."))

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
