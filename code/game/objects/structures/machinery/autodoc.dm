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
	/// Looping sound played while a repair cycle is in progress.
	var/looping_sound_type = /datum/looping_sound/autodoc
	VAR_PRIVATE/datum/looping_sound/autodoc_looping_sound
	COOLDOWN_DECLARE(suit_warning_cd)

/obj/structure/machinery/autodoc/Destroy()
	QDEL_NULL(autodoc_looping_sound)
	. = ..()

// Refuses to accept a patient still wearing an outer suit -- error buzz +
// chat message instead, throttled so it doesn't spam every process tick
// while they remain lying there suited up.
/obj/structure/machinery/autodoc/patient_acceptable(mob/living/carbon/human/H)
	if(H.wear_suit)
		if(COOLDOWN_FINISHED(src, suit_warning_cd))
			playsound(src, 'sound/machines/buzz-sigh.ogg', 50, TRUE)
			to_chat(H, SPAN_WARNING("\The [src] buzzes an error -- remove your [H.wear_suit.name] before use."))
			COOLDOWN_START(src, suit_warning_cd, 3 SECONDS)
		return FALSE
	return TRUE

// The base optable spawns permanently anchored with no wrench interaction.
// The autodoc is ordered via cargo and needs to be positioned by hand after
// unwrapping, so it gets a standard wrench-to-(un)anchor toggle.
/obj/structure/machinery/autodoc/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 100)
		user.visible_message("[user.name] [anchored ? "unsecures" : "secures"] the bolts holding [src] to the floor.", \
					"You [anchored ? "unsecure" : "secure"] the bolts holding [src] to the floor.", \
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
			if(is_patient_fully_healthy(H))
				playsound(src, 'sound/machines/autodoc_ping.ogg', 50, 1)
				to_chat(H, SPAN_NOTICE("\The [src] beeps -- you're already at full health."))
				visible_message(SPAN_NOTICE("\The [src] beeps -- [H] is already at full health."))
				return
			suppressing = TRUE
			if(!autodoc_looping_sound)
				autodoc_looping_sound = new looping_sound_type(src)
				autodoc_looping_sound.start()
			heal_timer_id = addtimer(CALLBACK(src, PROC_REF(perform_full_heal), occupant), heal_duration, TIMER_STOPPABLE)
			visible_message(SPAN_NOTICE("\The [src] hums to life, scanning [H]."))

/obj/structure/machinery/autodoc/unmark_patient(datum/source, mob/living/carbon/potential_patient)
	var/occupant_resolved = occupant?.resolve()
	var/was_occupant = (potential_patient == occupant_resolved)
	. = ..()
	if(was_occupant && heal_timer_id)
		deltimer(heal_timer_id)
		heal_timer_id = null
		if(autodoc_looping_sound)
			autodoc_looping_sound.stop()
			QDEL_NULL(autodoc_looping_sound)
		visible_message(SPAN_WARNING("\The [src]'s repair cycle is interrupted!"))

/**
 * TRUE if H has nothing left for a repair cycle to fix: no brute/fire/tox/
 * oxy/clone/brain loss, no missing-or-stump limb, and no organ damage
 * (matches exactly what perform_full_heal() below would otherwise change).
 */
/obj/structure/machinery/autodoc/proc/is_patient_fully_healthy(mob/living/carbon/human/H)
	if(H.getBruteLoss() || H.getFireLoss() || H.getToxLoss() || H.getOxyLoss() || H.getCloneLoss() || H.getBrainLoss())
		return FALSE

	for(var/limb_zone in H.species.has_limbs)
		var/obj/item/organ/external/E = H.get_organ(limb_zone)
		if(!E || E.is_stump())
			return FALSE
		if(E.brute_dam || E.burn_dam || (E.status & ORGAN_DAMAGE_STATES) || LAZYLEN(E.wounds))
			return FALSE
		for(var/obj/implanted_object in E.implants)
			if(!istype(implanted_object, /obj/item/implant))
				return FALSE

	for(var/obj/item/organ/O in H.internal_organs)
		if(O.damage)
			return FALSE

	return TRUE

/obj/structure/machinery/autodoc/proc/perform_full_heal(datum/weakref/patient_ref)
	heal_timer_id = null

	var/mob/living/carbon/human/H = patient_ref?.resolve()
	if(!istype(H) || QDELETED(H))
		return
	if(occupant != patient_ref)
		return
	if(H.stat == DEAD)
		suppressing = FALSE
		if(autodoc_looping_sound)
			autodoc_looping_sound.stop()
			QDEL_NULL(autodoc_looping_sound)
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

	suppressing = FALSE
	H.SetSleeping(0)
	if(autodoc_looping_sound)
		autodoc_looping_sound.stop()
		QDEL_NULL(autodoc_looping_sound)

	playsound(src, 'sound/machines/autodoc_ping.ogg', 50, 1)
	visible_message(SPAN_NOTICE("\The [src] chimes -- repair cycle complete. [H] looks fully healed."))
	refresh_icon_state()
