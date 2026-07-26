/*
 * Cryogenic Prison Storage -- a cryopod subtype that adds a genuine
 * detention mechanic on top of the inherited store/wake machinery
 * (cryopod.dm): a security-access-gated TGUI lets an operator imprison
 * whoever's occupying the pod, for a fixed duration or indefinitely.
 *
 * Everything about physically entering/storing/waking is inherited
 * unchanged from /obj/structure/machinery/cryopod (faction tagger
 * compatibility, persistence registration, go_in()/set_occupant()/
 * persistence_force_store(), the faction entry gate, update_icon()'s
 * "[initial(icon_state)]-working/-closed/-broken" derivation -- bodyscanner.dmi
 * already ships matching states). Only the imprison/release TGUI is new.
 *
 * Deliberately refuses to imprison anyone while unassigned/public/personally
 * tagged -- imprisonment requires real faction accountability, confirmed
 * with the user. See persistence_character_imprisonment_status()/
 * persistence_set_imprisoned() (persistence_mobs.dm) for the persisted
 * flag itself, and persistence_cryopod_discovery_ignore (persistence_cryo.dm)
 * for why this type is excluded from the general pod-discovery cascade
 * while still resolving fine as a released prisoner's own saved last-pod.
 */
/obj/structure/machinery/cryopod/prison
	name = "cryogenic prison storage"
	desc = "A reinforced cryogenic pod modified for indefinite detention."
	icon = 'icons/obj/machinery/bodyscanner.dmi'
	icon_state = "body_scanner"
	/// While TRUE (default), the tied prisoner's sentence is enforced
	/// normally -- Play stays disabled per persistence_character_imprisonment_status().
	/// While FALSE, that same prisoner is allowed to spawn/play normally
	/// EVEN THOUGH their sentence keeps ticking in the background --
	/// confirmed with the user as a furlough/parole-style toggle, not a
	/// release: the persisted imprisoned/imprisoned_until row is untouched,
	/// so re-locking (or the pod itself vanishing) resumes/ends enforcement
	/// exactly where the timer already is. Only Release (or an admin) ever
	/// actually clears the sentence outright.
	var/locked = TRUE

/obj/structure/machinery/cryopod/prison/persistent_objects_get_content()
	var/list/content = ..()
	content["locked"] = locked
	return content

/obj/structure/machinery/cryopod/prison/persistent_objects_apply_content(list/content, x, y, z)
	..()
	if(islist(content) && !isnull(content["locked"]))
		locked = !!content["locked"]

/// Security access, respecting faction tagging (confirmed with the user):
/// the user's worn ID must grant ACCESS_SECURITY, and if this pod is
/// faction-tagged, the ID's employer_faction must also match it.
/obj/structure/machinery/cryopod/prison/proc/_prison_access_ok(mob/user)
	var/obj/item/card/id/ID = user.GetIdCard()
	if(!ID || !(ACCESS_SECURITY in ID.access))
		return FALSE
	if(persistent_network && persistent_network != "public")
		if(normalize_faction_uid(ID.employer_faction) != normalize_faction_uid(persistent_network))
			return FALSE
	return TRUE

/obj/structure/machinery/cryopod/prison/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	if(!_prison_access_ok(user))
		to_chat(user, SPAN_WARNING("\The [src] refuses to respond -- security access is required."))
		return
	ui_interact(user)

/obj/structure/machinery/cryopod/prison/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PrisonPod", "Cryogenic Prison Storage")
		ui.open()

/obj/structure/machinery/cryopod/prison/ui_data(mob/user)
	var/list/data = list()
	data["occupant_name"] = occupant ? occupant.real_name : null
	data["nopower"] = !!(stat & NOPOWER)
	data["broken"] = !!(stat & BROKEN)
	data["faction_name"] = (persistent_network && persistent_network != "public") ? get_faction_name(persistent_network) : null
	data["can_imprison"] = !!(persistent_network && persistent_network != "public")
	data["locked"] = locked
	// The _record() variant (not the Play-gate _status() one) -- an operator
	// needs to see and manage a currently-unlocked/paroled occupant too, not
	// just ones actively blocked from playing.
	var/list/status = occupant ? persistence_character_imprisonment_record(occupant.ckey, occupant.real_name) : null
	data["imprisoned"] = !!status
	data["indefinite"] = status ? !!status["indefinite"] : FALSE
	data["remaining_seconds"] = status ? status["remaining_seconds"] : 0
	return data

/obj/structure/machinery/cryopod/prison/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	if(!_prison_access_ok(user))
		to_chat(user, SPAN_WARNING("Security access is required."))
		return

	switch(action)
		if("imprison")
			if(!occupant)
				to_chat(user, SPAN_WARNING("There's no one in \the [src] to imprison."))
				return
			if(!persistent_network || persistent_network == "public")
				to_chat(user, SPAN_WARNING("\The [src] must be tagged to a faction before it can be used to imprison someone -- an unassigned, public, or personally-tagged unit refuses."))
				return
			var/mob/living/carbon/human/prisoner = occupant
			var/prisoner_ckey = prisoner.ckey
			var/prisoner_name = prisoner.real_name
			if(!prisoner_ckey)
				to_chat(user, SPAN_WARNING("That occupant has no active session to imprison."))
				return
			// Imprisonment is exclusive per faction -- a prisoner already held
			// by a DIFFERENT faction can't be silently re-imprisoned/overwritten
			// by this one; that faction must release them first. Re-processing
			// by the SAME faction (re-sentencing) is fine and falls through.
			var/list/existing = persistence_character_imprisonment_record(prisoner_ckey, prisoner_name)
			if(existing && normalize_faction_uid(existing["faction_uid"]) != normalize_faction_uid(persistent_network))
				to_chat(user, SPAN_WARNING("[prisoner_name] is already imprisoned by [existing["faction_uid"] ? get_faction_name(existing["faction_uid"]) : "another faction"] -- they must be released first."))
				return
			var/duration_choice = tgui_alert(user, "Set a fixed sentence, or imprison indefinitely?", "Imprison", list("Fixed Duration", "Indefinite", "Cancel"))
			if(!duration_choice || duration_choice == "Cancel")
				return
			var/minutes = null
			if(duration_choice == "Fixed Duration")
				minutes = tgui_input_number(user, "Sentence length in minutes:", "Imprison", 60, 100000, 1)
				if(isnull(minutes) || minutes <= 0)
					return
			else
				var/confirm_indef = tgui_alert(user, "Imprison [prisoner_name] INDEFINITELY? This lasts until an operator (or an admin) releases them.", "Confirm Indefinite Sentence", list("Imprison", "Cancel"))
				if(confirm_indef != "Imprison")
					return
			if(!persistence_force_store(prisoner))
				to_chat(user, SPAN_WARNING("Failed to process [prisoner_name] into storage -- try again."))
				return
			persistence_set_imprisoned(prisoner_ckey, prisoner_name, TRUE, minutes, persistent_network)
			to_chat(user, SPAN_GOOD("[prisoner_name] has been imprisoned[minutes ? " for [minutes] minute\s" : " indefinitely"]."))
			log_and_message_admins("imprisoned [prisoner_name] ([prisoner_ckey]) in cryogenic prison storage[minutes ? " for [minutes] minute(s)" : " indefinitely"] at ([x],[y],[z]).", user)
			. = TRUE

		if("release")
			if(!occupant)
				to_chat(user, SPAN_WARNING("There's no one in \the [src] to release."))
				return
			persistence_set_imprisoned(occupant.ckey, occupant.real_name, FALSE)
			to_chat(user, SPAN_GOOD("[occupant.real_name] has been released from imprisonment."))
			log_and_message_admins("released [occupant.real_name] ([occupant.ckey]) from cryogenic prison storage at ([x],[y],[z]).", user)
			. = TRUE

		if("toggle_lock")
			locked = !locked
			to_chat(user, SPAN_GOOD("\The [src] is now [locked ? "LOCKED -- the sentence is enforced normally" : "UNLOCKED -- the tied prisoner may spawn/play despite their sentence, which keeps ticking regardless"]."))
			log_and_message_admins("[locked ? "locked" : "unlocked"] cryogenic prison storage at ([x],[y],[z]).", user)
			. = TRUE
