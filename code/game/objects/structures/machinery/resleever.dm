/*
 * Resleever Machine
 * A pod in its own right -- transfers a neural lace consciousness into
 * whatever body is physically placed inside IT (drag-drop or grab-and-click,
 * same convention as the cryopod/cloning pod), not a body sitting somewhere
 * else. Its linked cloning pod is a separate machine: order a clone there,
 * wait for it to grow, then carry it over and place it in the resleever.
 * Medical staff insert an extracted lace, place the body, and resleeve.
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
	/// The body physically placed inside this machine -- see _insert_occupant()
	/// (drag-drop/grab) and eject_occupant() (right-click). This is what
	/// _do_resleeve() acts on; there is no other way to set a resleeve target.
	var/mob/living/carbon/human/occupant = null

/obj/structure/machinery/resleever/examine(mob/user)
	. = ..()
	. += SPAN_NOTICE("Lace slot: [inserted_lace ? "[inserted_lace.registered_name]'s lace ([inserted_lace.lace_occupied ? "OCCUPIED" : "empty"])" : "empty"]")
	. += SPAN_NOTICE("Body slot: [occupant ? occupant.real_name : "no body"]")

/// Same occupant/BROKEN/NOPOWER branching as body_scanner.dm's own
/// update_icon() -- this machine borrows that sprite sheet wholesale, so the
/// same suffixed states ("-working", "-closed", "-broken", "-broken-closed")
/// already exist for it. Minus body_scanner's panel_open overlay and
/// name-append, which are specific to its own linked console and don't apply
/// here. Without this override icon_state never left its compile-time
/// default regardless of occupant.
/obj/structure/machinery/resleever/update_icon()
	if(occupant)
		if(stat & BROKEN)
			icon_state = "[initial(icon_state)]-broken-closed"
		if(stat & NOPOWER)
			icon_state = "[initial(icon_state)]-closed"
		else
			icon_state = "[initial(icon_state)]-working"
	else
		if(stat & BROKEN)
			icon_state = "[initial(icon_state)]-broken"
		else
			icon_state = initial(icon_state)

/obj/structure/machinery/resleever/attack_hand(mob/user)
	if(..())
		return
	ui_interact(user)

/obj/structure/machinery/resleever/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Resleever", "Resleeving Machine", 420, 480)
		ui.open()

/obj/structure/machinery/resleever/ui_data(mob/user)
	var/list/data = list()

	data["lace_name"] = inserted_lace ? inserted_lace.registered_name : null
	data["lace_occupied"] = inserted_lace ? !!inserted_lace.lace_occupied : FALSE

	var/obj/structure/machinery/clonepod/pod = get_linked_pod()
	data["linked_pod"] = pod ? TRUE : FALSE
	data["pod_occupied"] = (pod && pod.occupant) ? TRUE : FALSE
	data["pod_clone_name"] = (pod && pod.occupant) ? pod.occupant.real_name : null
	data["pod_growing"] = (pod && pod.growing_clone_data) ? TRUE : FALSE
	// A clone can only be ordered against a lace that names someone, and only
	// when the pod isn't already occupied or mid-grow.
	data["can_order_clone"] = (pod && !pod.occupant && !pod.growing_clone_data && inserted_lace && inserted_lace.registered_name) ? TRUE : FALSE

	// The resleever acts on whatever body is physically placed inside IT
	// (occupant) -- drag-drop or grab, see _insert_occupant(). Only a
	// MINDLESS body is a valid resleeve target -- one that already has a mind
	// in it is somebody else's body, not an empty vessel.
	data["body_name"] = (occupant && !occupant.mind?.key) ? occupant.real_name : null
	data["occupied"] = occupant ? TRUE : FALSE
	// Both halves have to be present, the body must be mindless, and the lace
	// has to actually be carrying somebody -- _do_resleeve() refuses
	// otherwise, so surface it up front rather than letting the button fail
	// on click.
	data["can_resleeve"] = (inserted_lace && inserted_lace.lace_occupied && occupant && !occupant.mind?.key) ? TRUE : FALSE

	// 0 when cloning is free (CLONING_COSTS_CREDITS, _compile_options.dm), so
	// the UI advertises a price only when one is actually charged.
#ifdef CLONING_COSTS_CREDITS
	data["clone_cost"] = CLONE_ORDER_COST
	// Which account an order would hit, shown before the player commits.
	// Passing the viewer, so the payer line reflects whoever is actually
	// standing here -- a non-member must not be shown the faction as payer
	// and then be billed personally on click.
	var/list/billing = pod ? pod.resolve_clone_billing(src, user) : null
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
			var/body_name = occupant ? occupant.real_name : "nothing"
			if(tgui_alert(user, "Resleeve [inserted_lace ? inserted_lace.registered_name : "nobody"] into [body_name]?", "Confirm Resleeve", list("Resleeve", "Cancel")) == "Resleeve")
				_do_resleeve(user)
			return TRUE

		if("eject_occupant")
			_eject_occupant(user)
			return TRUE

/obj/structure/machinery/resleever/attackby(obj/item/I, mob/user, params)
	// Multitool links this resleever to a cloning pod (resleever_cloning.dm).
	if(I.tool_behaviour == TOOL_MULTITOOL)
		return handle_multitool(I, user)

	// A grab in hand -- place the grabbed mob inside, same convention as
	// cryopod.dm's own attackby().
	var/obj/item/grab/G = I
	if(istype(G))
		if(!ismob(G.affecting))
			return
		_insert_occupant(user, G.affecting)
		return

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

/// Drag-drop entry -- same convention as cryopod.dm's mouse_drop_receive().
/obj/structure/machinery/resleever/mouse_drop_receive(atom/dropped, mob/user, params)
	if(!istype(user, /mob/living))
		return
	if(!isliving(dropped))
		return
	_insert_occupant(user, dropped)

/// Shared placement path for both the drag-drop and grab entry points.
/// `user` is whoever is doing the placing; `M` is the body being placed --
/// same split cryopod.dm's own go_in() uses, including the willing-check for
/// a conscious mob with a client (a dead or mindless clone has none, so it
/// always proceeds straight through).
/obj/structure/machinery/resleever/proc/_insert_occupant(mob/user, mob/living/M)
	if(!istype(M) || !ishuman(M))
		to_chat(user, SPAN_WARNING("\The [src] can't accept that."))
		return
	if(occupant)
		to_chat(user, SPAN_WARNING("\The [src] already holds a body. Eject it first."))
		return
	if(M.buckled_to)
		to_chat(user, SPAN_WARNING("[M == user ? "You are" : "\The [M] is"] buckled and cannot be placed inside \the [src]."))
		return

	var/willing = TRUE
	if(M.client && M.stat != DEAD)
		willing = FALSE
		var/original_loc = M.loc
		if(alert(M, "Would you like to enter \the [src]?", "Resleeving Machine", "Yes", "No") == "Yes")
			if(!M || M.loc != original_loc)
				return
			willing = TRUE
	if(!willing)
		return

	user.visible_message(
		SPAN_NOTICE("\The [user] starts placing \the [M] into \the [src]."),
		SPAN_NOTICE("You start placing \the [M] into \the [src]."),
	)
	if(!do_after(user, 2 SECONDS, M, DO_UNIQUE))
		to_chat(user, SPAN_NOTICE("You stop placing \the [M] into \the [src]."))
		return
	if(!M || QDELETED(M) || occupant)
		return

	M.forceMove(src)
	occupant = M
	update_icon()
	to_chat(user, SPAN_NOTICE("\The [M] is now inside \the [src]."))

/// Right-click "Eject Occupant" -- same convention as cryopod.dm's "Eject
/// from Pod" / cloning.dm's "Eject Cloner". Thin wrapper so the verb, the
/// TGUI button, and relaymove() below all go through the one shared proc.
/obj/structure/machinery/resleever/verb/eject_occupant()
	set name = "Eject Occupant"
	set category = "Persistence"
	set src in oview(1)

	_eject_occupant(usr)

/// Shared eject path -- see eject_occupant() (right-click), the
/// "eject_occupant" ui_act() case (TGUI button), and relaymove() (walking or
/// resisting out) below. All three used to only be wired to the verb, which
/// is exactly why neither the TGUI button nor self-eject via movement worked
/// for the occupant.
/obj/structure/machinery/resleever/proc/_eject_occupant(mob/user)
	if(!occupant)
		to_chat(user, SPAN_WARNING("\The [src] is empty."))
		return
	var/mob/living/carbon/human/leaving = occupant
	occupant = null
	leaving.forceMove(get_turf(src))
	update_icon()
	to_chat(user, SPAN_NOTICE("You eject \the [leaving] from \the [src]."))

/// Lets a conscious occupant just walk (or resist) their way out, same as
/// cryopod.dm/cloning.dm's own relaymove() overrides -- without this, the
/// only way out was another person right-clicking the machine from outside.
/// Skipped for an incapacitated occupant (stat != 0) so a stray relayed
/// movement doesn't pop an unconscious/dead body out on its own.
/obj/structure/machinery/resleever/relaymove(mob/living/user, direction)
	. = ..()
	if(user.stat)
		return
	_eject_occupant(user)

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

/obj/structure/machinery/resleever/proc/_do_resleeve(mob/living/user)
	var/mob/living/carbon/human/target_body = occupant

	if(!inserted_lace || !target_body)
		to_chat(user, SPAN_WARNING("Both a lace and a body inside \the [src] are required."))
		return

	if(target_body.mind?.key)
		to_chat(user, SPAN_WARNING("The body in \the [src] already has a mind of their own."))
		return

	if(!inserted_lace.lace_occupied || !inserted_lace.lace_mob)
		to_chat(user, SPAN_WARNING("The lace does not contain a consciousness."))
		return

	// Any damage at all blocks resleeving until repaired -- weld it, or use
	// repair nanites/nanopaste (neural_lace.dm's attackby()). > 0 mirrors
	// LACE_DAMAGE_NONE from neural_lace.dm, which #undefs it at end of file
	// so it isn't visible here.
	if(inserted_lace.lace_damage > 0)
		to_chat(user, SPAN_WARNING("The lace shows damage and cannot be resleeved until repaired."))
		return

	if(QDELETED(target_body))
		to_chat(user, SPAN_WARNING("The body in \the [src] is gone."))
		occupant = null
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

	// Install the lace the same way a real surgical transplant does
	// (organs_internal.dm's replace_organ surgery step calls this exact proc)
	// rather than hand-splicing the organ lists ourselves. This used to skip
	// what /obj/item/organ/internal/replaced() (_internal.dm) does for a
	// robotic organ specifically -- syncing species/dna to the new body
	// (BP_IS_ROBOTIC(src), which the lace is) -- leaving it with stale/absent
	// dna that didn't match its new owner. That mismatch is exactly what
	// handle_rejection() (organ.dm) checks for; it's now a permanent no-op on
	// the lace regardless (neural_lace.dm), but this was the actual root
	// cause of that necrosis report, not just a symptom to suppress.
	inserted_lace.replaced(target_body, head)

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

	// Restore what the lace was carrying BEFORE taking anything away, so the
	// loss below comes off the character's real earned levels rather than the
	// Trained baseline a clone body is built with. A clone is assembled by
	// copy_to() from the saved chargen slot (resleever_cloning.dm), which knows
	// nothing about skills learned in-round -- without this restore, resleeving
	// would quietly erase every manual and every lesson.
	if(islist(inserted_lace.stored_skills) && length(inserted_lace.stored_skills))
		apply_skill_snapshot(target_body, inserted_lace.stored_skills)

	// Coming back costs you. A random couple of skills lose a tier -- see
	// apply_resleeve_skill_loss() (skill_progression.dm) for the exact bounds.
	// Done HERE rather than when the clone body was grown because the mind has
	// only just arrived: before the transfer above there was no client to read
	// education from or to show this report to.
	var/list/lost_skills = apply_resleeve_skill_loss(target_body)
	if(length(lost_skills))
		to_chat(target_body, SPAN_WARNING(FONT_LARGE("Some of what you knew didn't survive the transfer:")))
		for(var/entry in lost_skills)
			to_chat(target_body, SPAN_WARNING("&nbsp;&nbsp;[entry]"))
		to_chat(target_body, SPAN_NOTICE("Skills can be relearned from someone who still holds them, or from a professional manual."))
		log_game("[inserted_lace.registered_name] lost skills to resleeving: [jointext(lost_skills, ", ")].")

	to_chat(user, SPAN_GOOD("Resleeve successful. [inserted_lace.registered_name] is now in the new body."))
	log_game("[inserted_lace.registered_name] resleeved by [user.real_name] via resleever at ([x],[y],[z]).")

	inserted_lace = null
	// They're conscious now -- no reason to leave them shut inside the
	// machine. Same auto-release cryopod.dm/cloning.dm never bothered adding
	// for their own success paths, but there the occupant leaves under their
	// own power via a separate eject step; here that step would just be
	// forgotten more often, so do it automatically.
	occupant = null
	target_body.forceMove(get_turf(src))
	update_icon()
