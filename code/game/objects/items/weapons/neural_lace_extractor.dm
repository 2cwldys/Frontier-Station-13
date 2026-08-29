/*
 * Neural Lace Extractor -- a field tool for paramedics to quick-extract a
 * neural lace without the full surgery-table pipeline (skull already open,
 * organs_internal.dm's detach_organ/remove_organ steps). Trades the
 * surgical procedure's careful, multi-step safety for speed -- 15 seconds,
 * one tool, no operating table -- at the cost of a real chance of damaging
 * the lace on a botched extraction.
 *
 * Botch damage is routed through take_field_extraction_damage()
 * (neural_lace.dm), not the general take_lace_damage() every other damage
 * source uses -- that variant can never push a lace to fully destroyed by
 * itself, even on a lace that already carried damage close to that ceiling.
 * A field extraction can leave a lace badly damaged (see neural_lace.dm's
 * repair branches -- welder/repairnanites/nanopaste), but "unsalvageable"
 * only ever happens from other/cumulative damage, never a single unlucky
 * extraction (confirmed design decision).
 */
/obj/item/neural_lace_extractor
	name = "neural lace extractor"
	desc = "A handheld field device for rapidly extracting a neural lace without full surgery."
	desc_extended = "Designed for paramedics working outside a proper surgical suite. The extraction is quick but comparatively crude -- there's a real chance of damaging the lace's delicate neural mesh in the process."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "drill"
	w_class = WEIGHT_CLASS_SMALL
	force = 3
	throwforce = 2
	origin_tech = list(TECH_BIO = 3, TECH_MATERIAL = 2)
	matter = list(MATERIAL_STEEL = 2000, MATERIAL_GLASS = 500)

	/// Chance (%) an otherwise-successful extraction still botches and
	/// damages the lace.
	var/botch_chance = 30
	var/botch_damage_min = 15
	var/botch_damage_max = 35
	/// Re-entrancy guard -- one extraction at a time per tool.
	var/extracting = FALSE

/obj/item/neural_lace_extractor/attack(mob/living/target_mob, mob/living/user, target_zone)
	if(istype(target_mob, /mob/living/silicon/robot))
		return _extract_from_robot(target_mob, user)

	var/mob/living/carbon/human/H = target_mob
	if(!istype(H))
		return ..()

	if(extracting)
		to_chat(user, SPAN_WARNING("\The [src] is already mid-extraction."))
		return TRUE

	var/obj/item/organ/internal/neural_lace/lace = H.internal_organs_by_name["neural_lace"]
	if(!lace)
		to_chat(user, SPAN_WARNING("[H] has no neural lace installed."))
		return TRUE

	user.visible_message(SPAN_WARNING("\The [user] begins extracting [H]'s neural lace with \the [src]."), SPAN_WARNING("You begin extracting [H]'s neural lace..."))
	playsound(get_turf(H), 'sound/items/surgery/surgicaldrill.ogg', 50, 1)

	extracting = TRUE
	var/success = do_after(user, 15 SECONDS, H, DO_DEFAULT | DO_USER_UNIQUE_ACT)
	extracting = FALSE

	if(!success)
		to_chat(user, SPAN_WARNING("Extraction interrupted."))
		return TRUE

	// Re-validate -- the lace/host state can change during the do_after.
	lace = H.internal_organs_by_name["neural_lace"]
	if(!lace || lace.owner != H)
		to_chat(user, SPAN_WARNING("The lace is no longer there."))
		return TRUE

	if(prob(botch_chance))
		lace.take_field_extraction_damage(rand(botch_damage_min, botch_damage_max))
		playsound(get_turf(H), 'sound/machines/defib_failed.ogg', 50, 0)
		user.visible_message(SPAN_WARNING("\The [user]'s extraction is rough -- [H]'s neural lace sparks as it comes free!"), SPAN_WARNING("Your extraction is rough -- the lace sparks as it comes free!"))
	else
		playsound(get_turf(H), 'sound/machines/defib_success.ogg', 50, 0)
		user.visible_message(SPAN_NOTICE("\The [user] cleanly extracts [H]'s neural lace."), SPAN_NOTICE("You cleanly extract the neural lace."))

	lace.removed(H, user)
	user.put_in_hands(lace)
	return TRUE

/**
 * Field-extracts whatever consciousness is occupying a cyborg's MMI directly
 * -- no need to crowbar the MMI out of the chassis first. Shares the same
 * timing/botch-risk shape as the human path above, but there's no existing
 * lace to damage on a botch (there's nothing to extract FROM yet), so a
 * fresh one is created first and the botch damage lands on that instead.
 */
/obj/item/neural_lace_extractor/proc/_extract_from_robot(mob/living/silicon/robot/R, mob/living/user)
	if(extracting)
		to_chat(user, SPAN_WARNING("\The [src] is already mid-extraction."))
		return TRUE

	if(!R.mmi || !R.mmi.brainmob || !R.mmi.brainmob.mind)
		to_chat(user, SPAN_WARNING("[R] has no neural lace consciousness to extract."))
		return TRUE

	user.visible_message(SPAN_WARNING("\The [user] begins extracting a consciousness from [R]'s MMI with \the [src]."), SPAN_WARNING("You begin extracting the consciousness from [R]'s MMI..."))
	playsound(get_turf(R), 'sound/items/surgery/surgicaldrill.ogg', 50, 1)

	extracting = TRUE
	var/success = do_after(user, 15 SECONDS, R, DO_DEFAULT | DO_USER_UNIQUE_ACT)
	extracting = FALSE

	if(!success)
		to_chat(user, SPAN_WARNING("Extraction interrupted."))
		return TRUE

	// Re-validate -- state can change during the do_after (MMI pulled, robot
	// destroyed, occupant already left some other way).
	if(!R.mmi || !R.mmi.brainmob || !R.mmi.brainmob.mind)
		to_chat(user, SPAN_WARNING("There's no longer a consciousness there to extract."))
		return TRUE

	var/obj/item/organ/internal/neural_lace/lace = new(get_turf(R))
	if(!R.mmi.extract_consciousness_to_lace(lace, user))
		qdel(lace)
		return TRUE

	if(prob(botch_chance))
		lace.take_field_extraction_damage(rand(botch_damage_min, botch_damage_max))
		playsound(get_turf(R), 'sound/machines/defib_failed.ogg', 50, 0)
		user.visible_message(SPAN_WARNING("\The [user]'s extraction is rough -- the consciousness sparks as it settles into the lace!"), SPAN_WARNING("Your extraction is rough -- the consciousness sparks as it settles into the lace!"))
	else
		playsound(get_turf(R), 'sound/machines/defib_success.ogg', 50, 0)
		user.visible_message(SPAN_NOTICE("\The [user] cleanly extracts the consciousness from [R]'s MMI."), SPAN_NOTICE("You cleanly extract the consciousness."))

	user.put_in_hands(lace)
	return TRUE
