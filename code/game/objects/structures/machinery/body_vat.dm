/*
 * Body Vat
 * Grows a blank human body from a DNA sample for neural lace resleeving.
 * Takes 10 minutes to produce a mindless body ready for the resleever.
 */

#define BODY_VAT_GROW_TIME (10 MINUTES)

/obj/structure/machinery/body_vat
	name = "body cultivation vat"
	desc = "A cylindrical vat for cultivating blank human bodies from genetic material."
	icon = 'icons/obj/machinery/cryopod.dmi'
	icon_state = "body_vat_idle"
	anchored = TRUE
	density = TRUE

	var/growing = FALSE
	var/grow_complete = FALSE
	var/list/stored_dna = null  // DNA data from which to grow the body
	var/stored_name = "Vat Body"
	var/grow_timer = null

/obj/structure/machinery/body_vat/examine(mob/user)
	. = ..()
	if(growing)
		. += SPAN_NOTICE("The vat is actively growing a body.")
	else if(grow_complete)
		. += SPAN_GOOD("A blank body is ready for extraction.")
	else
		. += SPAN_NOTICE("The vat is idle. Insert a neural lace or DNA sample to begin.")

/obj/structure/machinery/body_vat/attackby(obj/item/I, mob/user, params)
	// Accept a neural lace to start growing a matching body
	if(istype(I, /obj/item/organ/internal/neural_lace))
		var/obj/item/organ/internal/neural_lace/lace = I
		if(growing || grow_complete)
			to_chat(user, SPAN_WARNING("The vat is busy. Extract the body first."))
			return
		stored_name = lace.registered_name
		if(lace.lace_mob?.dna)
			stored_dna = lace.lace_mob.dna
		else
			stored_dna = null
		user.put_in_hands(lace)  // Return lace to user
		_start_growing(user)
		return
	. = ..()

/obj/structure/machinery/body_vat/proc/_start_growing(mob/user)
	growing = TRUE
	grow_complete = FALSE
	update_icon()
	to_chat(user, SPAN_NOTICE("Body cultivation begun. Estimated completion: [BODY_VAT_GROW_TIME / (1 MINUTE)] minutes."))
	to_world(SPAN_NOTICE("The body cultivation vat begins growing a blank body."))

	var/datum/callback/cb = new /datum/callback(src, TYPE_PROC_REF(/obj/structure/machinery/body_vat, _finish_growing))
	grow_timer = addtimer(cb, BODY_VAT_GROW_TIME, TIMER_STOPPABLE | TIMER_DELETE_ME)

/obj/structure/machinery/body_vat/proc/_finish_growing()
	grow_timer = null
	growing = FALSE
	grow_complete = TRUE
	update_icon()
	to_world(SPAN_GOOD("A body cultivation vat has finished growing a blank body. It is ready for extraction."))
	playsound(src, 'sound/machines/chime.ogg', 75, 0)

/obj/structure/machinery/body_vat/attack_hand(mob/user)
	if(!grow_complete)
		to_chat(user, SPAN_WARNING("No body ready yet."))
		return

	var/confirm = tgui_alert(user, "Extract the blank body from the vat?", "Extract Body", list("Extract", "Cancel"))
	if(confirm != "Extract") return

	// Create the blank body
	var/mob/living/carbon/human/vat_body = new /mob/living/carbon/human(get_turf(src))
	vat_body.real_name = "[stored_name]'s Clone"
	vat_body.name = "[stored_name]'s Clone"
	vat_body.set_stat(DEAD)  // Mindless — will be resleeved
	if(stored_dna && istype(stored_dna, /datum/dna) && vat_body.dna)
		// Apply stored DNA appearance where possible
		try
			vat_body.dna.b_type = stored_dna:b_type
		catch(var/exception/dna_e)
			log_debug("Body vat: DNA copy failed: [dna_e]")

	to_chat(user, SPAN_GOOD("Blank body extracted. Place in the resleever to transfer a consciousness."))
	log_game("[user.real_name] extracted a vat body for '[stored_name]'.")

	grow_complete = FALSE
	stored_name = "Vat Body"
	stored_dna = null
	update_icon()

/obj/structure/machinery/body_vat/update_icon()
	if(growing)
		icon_state = "body_vat_growing"
	else if(grow_complete)
		icon_state = "body_vat_ready"
	else
		icon_state = "body_vat_idle"

/obj/structure/machinery/body_vat/verb/admin_instant_grow()
	set name = "Instant Grow Body (Admin)"
	set category = "Persistence"
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	if(!growing)
		to_chat(usr, SPAN_WARNING("Start a grow cycle first by inserting a neural lace."))
		return

	if(grow_timer)
		deltimer(grow_timer)
		grow_timer = null
	_finish_growing()
	to_chat(usr, SPAN_GOOD("Body growth instantly completed."))

#undef BODY_VAT_GROW_TIME
