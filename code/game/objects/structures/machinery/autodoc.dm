// Automated surgery table -- lie down and it diagnoses and repairs
// everything a surgeon could fix, over a timed cycle. Uses the operating
// table sprite/interactions verbatim until dedicated autodoc sprites exist.
/obj/structure/machinery/autodoc
	parent_type = /obj/structure/machinery/optable
	name = "autodoc"
	desc = "An automated surgical suite. Lie down and it will diagnose and repair anything a surgeon could fix."

	/// How long a repair cycle takes once a patient is detected lying on the table.
	var/heal_duration = 20 SECONDS
	/// Timer id for the pending heal, so it can be cancelled if the patient gets up early.
	var/heal_timer_id

// The base optable spawns permanently anchored with no wrench interaction.
// The autodoc is ordered via cargo and needs to be positioned by hand after
// unwrapping, so it gets a standard wrench-to-(un)anchor toggle.
/obj/structure/machinery/autodoc/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 100)
		user.visible_message("[user.name] [anchored ? "secures" : "unsecures"] the bolts holding [src] to the floor.", \
					"You [anchored ? "secure" : "unsecure"] the bolts holding [src] to the floor.", \
					"You hear a ratchet")
		anchored = !anchored
		return TRUE
	return ..()

// The base optable registers its patient-detection signals on the tile it
// spawned on and never re-binds them -- fine when it's permanently anchored,
// but the autodoc can now be wrenched loose and pushed elsewhere, so it has
// to re-register on its new tile or it'd go permanently inert after a move.
/obj/structure/machinery/autodoc/Moved(atom/old_loc, movement_dir, forced, list/old_locs)
	. = ..()
	if(old_loc && old_loc != loc)
		UnregisterSignal(old_loc, COMSIG_ATOM_ENTERED)
		UnregisterSignal(old_loc, COMSIG_ATOM_EXITED)
		RegisterSignal(loc, COMSIG_ATOM_ENTERED, TYPE_PROC_REF(/obj/structure/machinery/optable, mark_patient))
		RegisterSignal(loc, COMSIG_ATOM_EXITED, TYPE_PROC_REF(/obj/structure/machinery/optable, unmark_patient))

/obj/structure/machinery/autodoc/check_occupant(seconds_per_tick)
	var/had_occupant = !!occupant
	. = ..()
	if(!had_occupant && occupant && !heal_timer_id)
		var/mob/living/carbon/human/H = occupant.resolve()
		if(istype(H))
			heal_timer_id = addtimer(CALLBACK(src, PROC_REF(perform_full_heal), occupant), heal_duration, TIMER_STOPPABLE)
			visible_message(SPAN_NOTICE("\The [src] hums to life, scanning [H]."))

/obj/structure/machinery/autodoc/unmark_patient(datum/source, mob/living/carbon/potential_patient)
	var/occupant_resolved = occupant?.resolve()
	var/was_occupant = (potential_patient == occupant_resolved)
	. = ..()
	if(was_occupant && heal_timer_id)
		deltimer(heal_timer_id)
		heal_timer_id = null
		visible_message(SPAN_WARNING("\The [src]'s repair cycle is interrupted!"))

/obj/structure/machinery/autodoc/proc/perform_full_heal(datum/weakref/patient_ref)
	heal_timer_id = null

	var/mob/living/carbon/human/H = patient_ref?.resolve()
	if(!istype(H) || QDELETED(H))
		return
	if(occupant != patient_ref)
		return
	if(H.stat == DEAD)
		visible_message(SPAN_WARNING("\The [src] beeps an error -- patient is deceased. Repair cycle aborted."))
		return

	H.heal_overall_damage(H.getBruteLoss(), H.getFireLoss())

	// Regrow anything missing/reduced to a stump. Limbs that are merely
	// damaged (or robotic prosthetics already installed) are left alone --
	// only empty slots and stumps get a fresh organic limb.
	for(var/limb_zone in H.species.has_limbs)
		var/obj/item/organ/external/existing = H.get_organ(limb_zone)
		if(existing && !existing.is_stump())
			continue
		if(istype(existing))
			existing.removed()
		var/list/organ_data = H.species.has_limbs[limb_zone]
		var/limb_path = organ_data["path"]
		if(limb_path)
			new limb_path(H)

	for(var/obj/item/organ/O in H.internal_organs)
		O.rejuvenate()

	// External rejuvenate() also clears wounds/broken bones/cut arteries/
	// tendons and extracts embedded shrapnel, cascading to any internal
	// organs it houses.
	for(var/obj/item/organ/external/E in H.organs)
		E.rejuvenate()

	H.restore_blood()

	H.setToxLoss(0)
	H.setOxyLoss(0)
	H.setCloneLoss(0)
	H.setBrainLoss(0)
	H.total_radiation = 0

	H.update_body()
	H.UpdateDamageIcon()
	H.updatehealth()

	playsound(src, 'sound/machines/twobeep.ogg', 50, 1)
	visible_message(SPAN_NOTICE("\The [src] chimes -- repair cycle complete. [H] looks fully healed."))
	refresh_icon_state()
