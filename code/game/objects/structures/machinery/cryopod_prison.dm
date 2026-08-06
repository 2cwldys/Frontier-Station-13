/*
 * Cryogenic Prison Storage -- a cryopod subtype that adds a genuine
 * detention mechanic on top of the inherited store/wake machinery
 * (cryopod.dm): a security-access-gated TGUI lets an operator imprison
 * whoever's occupying the pod, for a fixed duration or indefinitely.
 *
 * Physical containment is NOT inherited unchanged -- unlike a normal
 * cryopod, a prison cell holds an arbitrary number of occupants at once
 * (var/list/prison_occupants) rather than the base's single var/mob/occupant
 * (which stays perpetually null here, so every base proc that gates on
 * `if(occupant)` -- go_in()'s "already in use" refusal, attackby()'s
 * grab-entry refusal -- naturally never blocks and needs no override).
 * set_occupant()/go_out()/the Eject verb/relaymove()/process()/update_icon()
 * are all overridden below to operate on the list instead. Faction tagger
 * compatibility, persistence registration, and the "[icon_state]-working/
 * -closed/-broken" icon derivation are still inherited in spirit (just
 * ported to the list) -- bodyscanner.dmi already ships matching states.
 *
 * Deliberately refuses to imprison anyone while unassigned/public/personally
 * tagged -- imprisonment requires real faction accountability, confirmed
 * with the user. See persistence_character_imprisonment_status()/
 * persistence_set_imprisoned()/persistence_character_actively_imprisoned()
 * (persistence_mobs.dm) for the persisted flag itself, and
 * persistence_cryopod_discovery_ignore (persistence_cryo.dm) for why this
 * type is excluded from the general pod-discovery cascade while still
 * resolving fine as a released prisoner's own saved last-pod.
 */
/obj/structure/machinery/cryopod/prison
	name = "cryogenic prison storage"
	desc = "A reinforced cryogenic pod modified for indefinite detention."
	icon = 'icons/obj/machinery/bodyscanner.dmi'
	icon_state = "body_scanner"
	/// While TRUE (default), every tied sentence is enforced normally: Play
	/// stays disabled (persistence_character_imprisonment_status()), and
	/// toggling INTO this state forcibly returns anyone currently thawed and
	/// playing in this cell to the character menu right now -- freezing
	/// isn't just a future-login block, it actively ends any live session
	/// here (confirmed with the user). While FALSE ("thawed"), a tied
	/// prisoner may spawn/play despite their sentence, which keeps ticking
	/// regardless -- a furlough/parole-style toggle, not a release: the
	/// persisted imprisoned/imprisoned_until row is untouched, so
	/// re-freezing (or the pod itself vanishing) resumes/ends enforcement
	/// exactly where the timer already is. Only Release, the sentence
	/// actually running out, or an eject (see go_out()) ever clears it.
	var/frozen = TRUE
	/// Every mob physically inside this cell right now -- a shared cell, not
	/// one-occupant-at-a-time like a normal cryopod (confirmed with the
	/// user). The base's var/mob/occupant is intentionally left untouched
	/// (always null) for this subtype; see the file header.
	var/list/prison_occupants = list()

/obj/structure/machinery/cryopod/prison/persistent_objects_get_content()
	var/list/content = ..()
	content["frozen"] = frozen
	return content

/obj/structure/machinery/cryopod/prison/persistent_objects_apply_content(list/content, x, y, z)
	..()
	if(islist(content) && !isnull(content["frozen"]))
		frozen = !!content["frozen"]

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

/obj/structure/machinery/cryopod/prison/get_examine_text(mob/user, distance, is_adjacent, infix, suffix)
	. = ..()
	if(length(prison_occupants))
		. += SPAN_NOTICE("It holds [length(prison_occupants)] occupant[length(prison_occupants) == 1 ? "" : "s"].")

/obj/structure/machinery/cryopod/prison/ui_data(mob/user)
	var/list/data = list()
	data["nopower"] = !!(stat & NOPOWER)
	data["broken"] = !!(stat & BROKEN)
	data["faction_name"] = (persistent_network && persistent_network != "public") ? get_faction_name(persistent_network) : null
	data["can_imprison"] = !!(persistent_network && persistent_network != "public")
	data["frozen"] = frozen
	data["occupants"] = list()
	for(var/mob/living/carbon/O in prison_occupants)
		// The _record() variant (not the Play-gate _status() one) -- an
		// operator needs to see and manage a currently-thawed/paroled
		// occupant too, not just ones actively blocked from playing.
		var/list/status = persistence_character_imprisonment_record(O.ckey, O.real_name)
		data["occupants"] += list(list(
			"ref"               = REF(O),
			"name"              = O.real_name,
			"imprisoned"        = !!status,
			"indefinite"        = status ? !!status["indefinite"] : FALSE,
			"remaining_seconds" = status ? status["remaining_seconds"] : 0
		))
	data["sentences"] = _get_sentence_rows()
	return data

/// Every sentence tied to THIS cell, sourced from the persisted record rather
/// than from who happens to be physically inside.
///
/// A frozen prisoner has been stored back out to the database -- their mob no
/// longer exists, so they vanish from prison_occupants entirely and the pod's
/// menu showed nothing at all. That made a frozen sentence unmanageable from
/// the pod itself: no way to see it, shorten it, or release it without first
/// thawing the cell. Mirrors the remote Prison Management program's own list
/// (prison_management.dm), scoped to this one cell.
/obj/structure/machinery/cryopod/prison/proc/_get_sentence_rows()
	var/list/rows = list()
	if(!GLOB.config.sql_enabled || !SSdbcore.Connect())
		return rows
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT ckey, char_name FROM ss13_mob_position WHERE imprisoned = 1", list())
	q.Execute()
	var/list/candidates = list()
	if(SSpersistence.databaseCheckQueryResult(q, "prison pod sentence list"))
		while(q.NextRow())
			candidates += list(list("ckey" = q.item[1], "char_name" = q.item[2]))
	qdel(q)

	for(var/list/c in candidates)
		var/list/rec = persistence_character_imprisonment_record(c["ckey"], c["char_name"])
		if(!rec)
			continue
		if(rec["cell"] != src)
			continue
		// Flag whether this prisoner is also physically present, so the UI can
		// avoid presenting the same person as two unrelated entries.
		var/present = FALSE
		for(var/mob/living/carbon/O in prison_occupants)
			if(O.ckey == c["ckey"] && O.real_name == c["char_name"])
				present = TRUE
				break
		rows += list(list(
			"ckey"              = c["ckey"],
			"char_name"         = c["char_name"],
			"indefinite"        = !!rec["indefinite"],
			"remaining_seconds" = rec["remaining_seconds"],
			"present"           = present
		))
	return rows

/obj/structure/machinery/cryopod/prison/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	if(!_prison_access_ok(user))
		to_chat(user, SPAN_WARNING("Security access is required."))
		return

	var/mob/living/carbon/human/target
	if(params["occupant_ref"])
		var/atom/found = locate(params["occupant_ref"])
		if(found && (found in prison_occupants))
			target = found

	switch(action)
		if("imprison")
			if(!target)
				to_chat(user, SPAN_WARNING("Select an occupant in \the [src] to imprison."))
				return
			if(!persistent_network || persistent_network == "public")
				to_chat(user, SPAN_WARNING("\The [src] must be tagged to a faction before it can be used to imprison someone -- an unassigned, public, or personally-tagged unit refuses."))
				return
			var/prisoner_ckey = target.ckey
			var/prisoner_name = target.real_name
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
			persistence_set_imprisoned(prisoner_ckey, prisoner_name, TRUE, minutes, persistent_network)
			// Imprisoning doesn't itself store them -- they may keep playing,
			// confined, if the cell happens to already be thawed. Only kicked
			// to the menu right now if the cell is already frozen, keeping the
			// "a frozen cell never has a live occupant" invariant intact
			// either way (confirmed with the user).
			if(frozen)
				_kick_occupant(target)
			to_chat(user, SPAN_GOOD("[prisoner_name] has been imprisoned[minutes ? " for [minutes] minute\s" : " indefinitely"]."))
			log_and_message_admins("imprisoned [prisoner_name] ([prisoner_ckey]) in cryogenic prison storage[minutes ? " for [minutes] minute(s)" : " indefinitely"] at ([x],[y],[z]).", user)
			. = TRUE

		if("release")
			if(!target)
				to_chat(user, SPAN_WARNING("Select an occupant in \the [src] to release."))
				return
			persistence_set_imprisoned(target.ckey, target.real_name, FALSE)
			to_chat(user, SPAN_GOOD("[target.real_name] has been released from imprisonment."))
			log_and_message_admins("released [target.real_name] ([target.ckey]) from cryogenic prison storage at ([x],[y],[z]).", user)
			. = TRUE

		if("toggle_freeze")
			frozen = !frozen
			if(frozen)
				// Forcibly end any live session(s) in this cell right now --
				// see the var doc comment above.
				for(var/mob/living/carbon/O in prison_occupants.Copy())
					_kick_occupant(O)
			to_chat(user, SPAN_GOOD("\The [src] is now [frozen ? "FROZEN -- the sentence is enforced normally, and no one may currently be inside" : "THAWED -- the tied prisoner(s) may spawn/play despite their sentence, which keeps ticking regardless"]."))
			log_and_message_admins("[frozen ? "froze" : "thawed"] cryogenic prison storage at ([x],[y],[z]).", user)
			. = TRUE

		// --- Sentence management, keyed by ckey/char_name rather than by a
		// live mob ref. A frozen prisoner has no mob to reference, which is
		// exactly why these exist separately from the occupant actions above.
		if("sentence_release", "sentence_adjust")
			var/target_ckey = params["ckey"]
			var/target_char_name = params["char_name"]
			if(!target_ckey || !target_char_name)
				return TRUE
			// Re-verify against the live record instead of trusting the row the
			// client last rendered -- it may have expired, been released, or
			// been moved to another cell since.
			var/list/rec = persistence_character_imprisonment_record(target_ckey, target_char_name)
			if(!rec)
				to_chat(user, SPAN_WARNING("[target_char_name] is no longer imprisoned."))
				return TRUE
			if(rec["cell"] != src)
				to_chat(user, SPAN_WARNING("[target_char_name] isn't held in \the [src]."))
				return TRUE

			if(action == "sentence_release")
				persistence_set_imprisoned(target_ckey, target_char_name, FALSE)
				to_chat(user, SPAN_GOOD("[target_char_name] has been released from imprisonment."))
				log_and_message_admins("released [target_char_name] ([target_ckey]) from cryogenic prison storage at ([x],[y],[z]).", user)
				return TRUE

			var/indefinite_choice = tgui_alert(user, "Set a new fixed sentence, or make it indefinite?", "Adjust Sentence", list("Fixed Duration", "Indefinite", "Cancel"))
			if(!indefinite_choice || indefinite_choice == "Cancel")
				return TRUE
			var/minutes = null
			if(indefinite_choice == "Fixed Duration")
				minutes = tgui_input_number(user, "New sentence length in minutes (from now):", "Adjust Sentence", 60, 100000, 1)
				if(isnull(minutes) || minutes <= 0)
					return TRUE
			persistence_set_imprisoned(target_ckey, target_char_name, TRUE, minutes, persistent_network)
			to_chat(user, SPAN_GOOD("[target_char_name]'s sentence updated[minutes ? " -- [minutes] minute\s remaining" : " -- now indefinite"]."))
			log_and_message_admins("adjusted [target_char_name] ([target_ckey])'s cryogenic prison sentence[minutes ? " to [minutes] minute(s)" : " to indefinite"] at ([x],[y],[z]).", user)
			return TRUE

/// Force-stores O out of this cell (kick to the character menu) if they're
/// still physically here with a live client -- shared by toggle_freeze
/// (every current occupant, when turning frozen on) and imprison (the
/// specific target, only if the cell is already frozen at that moment).
/// Silently does nothing for an occupant with no client (nothing to kick)
/// or one already gone.
/obj/structure/machinery/cryopod/prison/proc/_kick_occupant(mob/living/carbon/O)
	if(!O || !(O in prison_occupants) || !O.client)
		return
	persistence_force_store(O)
	prison_occupants -= O

/obj/structure/machinery/cryopod/prison/set_occupant(mob/living/carbon/new_occupant)
	prison_occupants |= new_occupant
	new_occupant.forceMove(src)
	new_occupant.stop_pulling()
	if(new_occupant.client)
		new_occupant.client.perspective = EYE_PERSPECTIVE
		new_occupant.client.eye = src
		time_entered = world.time
		new_occupant.set_respawn_time()
		// Chill visuals for as long as they sit inside; go_out() finishes the
		// effect (sound/slowdown/fade) when they step out.
		if(ishuman(new_occupant))
			var/mob/living/carbon/human/chilled_human = new_occupant
			chilled_human.apply_cryo_chill_visuals()
			chilled_human.cryo_chill_pending = TRUE
	else if(istype(new_occupant, /mob/living/carbon/human) && GLOB.config.sql_enabled)
		var/mob/living/carbon/human/H = new_occupant
		if(H.persistence_stored_ckey)
			// Uninhabited mob with persistence data placed into cryopod —
			// auto-store immediately. Cancel any pending despawn timer so it
			// doesn't fire redundantly afterward.
			if(H.persistence_cryo_timer)
				deltimer(H.persistence_cryo_timer)
				H.persistence_cryo_timer = null
			SSpersistence.persistStoreCharacter(H, src)
			prison_occupants -= H
	update_icon()

/// Takes an explicit occupant, unlike the base's zero-arg version -- there's
/// no single "the" occupant to default to in a shared cell. Ejecting always
/// clears the sentence, whether it was early or had already run out by the
/// time this fires (harmless no-op in that case) -- confirmed with the user.
/obj/structure/machinery/cryopod/prison/go_out(mob/living/carbon/which)
	if(!which || !(which in prison_occupants))
		return
	if(which.client)
		which.client.eye = which.client.mob
		which.client.perspective = MOB_PERSPECTIVE
		which.reset_death_timers()
	var/mob/living/exiting_occupant = which
	which.forceMove(get_turf(src))
	prison_occupants -= which
	playsound(loc, on_exit_sound, 25)
	// Cold vapor rolls out of the opened pod and dissipates on its own.
	var/datum/effect/effect/system/steam_spread/steam = new /datum/effect/effect/system/steam_spread()
	steam.set_up(3, 0, get_turf(src))
	steam.start()
	if(ishuman(exiting_occupant))
		var/mob/living/carbon/human/chilled_human = exiting_occupant
		if(chilled_human.cryo_chill_pending)
			chilled_human.finish_cryo_chill()
	var/exit_ckey = which.ckey || (ishuman(which) ? which:persistence_stored_ckey : null)
	if(exit_ckey && which.real_name && persistence_character_actively_imprisoned(exit_ckey, which.real_name))
		persistence_set_imprisoned(exit_ckey, which.real_name, FALSE)
		to_chat(which, SPAN_GOOD("Your sentence has been cleared -- you're free to go."))
		if(ishuman(which))
			announce_faction_event(which, "has completed their sentence and been released from cryogenic prison storage.")
		var/turf/release_turf = get_turf(src)
		log_admin("PRISON: [key_name(which)]'s sentence completed -- released from cryogenic prison storage[release_turf ? " at ([release_turf.x],[release_turf.y],[release_turf.z])" : ""].")
	update_icon()

/obj/structure/machinery/cryopod/prison/eject()
	if(use_check_and_message(usr))
		return

	var/list/items = src.contents.Copy()
	for(var/mob/living/carbon/O in prison_occupants)
		items -= O
	if(announce)
		items -= announce
	for(var/obj/item/W in items)
		W.forceMove(get_turf(src))

	if(!length(prison_occupants))
		to_chat(usr, SPAN_WARNING("\The [src] is empty."))
		return
	var/mob/living/carbon/picked
	if(length(prison_occupants) == 1)
		picked = prison_occupants[1]
	else
		var/list/choices = list()
		for(var/mob/living/carbon/O in prison_occupants)
			choices["[O.real_name]"] = O
		var/pick = tgui_input_list(usr, "Eject which occupant?", "Eject from Pod", choices)
		if(!pick)
			return
		picked = choices[pick]
	go_out(picked)
	add_fingerprint(usr)

/// Blocks self-directed movement entirely while still actively imprisoned
/// (no self-exit even once thawed, confirmed with the user) -- otherwise
/// falls through to the base's normal go_out()-on-move behavior, which is
/// exactly the self-release path once a sentence has run out.
/obj/structure/machinery/cryopod/prison/relaymove(mob/living/user, direction)
	var/user_ckey = user.ckey || (ishuman(user) ? user:persistence_stored_ckey : null)
	if(user_ckey && user.real_name && persistence_character_actively_imprisoned(user_ckey, user.real_name))
		if(prob(10)) // avoid spamming the same message on every held-direction repeat
			to_chat(user, SPAN_WARNING("You're trapped in \the [src] -- someone will have to let you out."))
		return
	. = ..()
	go_out(user)

/// Deliberately simpler than the base's process(): no idle-with-a-live-client
/// auto-store (time_till_force_cryo) -- an actively connected prisoner stays
/// confined no matter how long they sit idle, only a genuine disconnect
/// triggers a store, same as the normal logout fast path
/// (persistCharacterOnLogout(), persistence_cryo.dm) already does for a
/// clean disconnect. No gear-strip despawn path either -- every realistic
/// occupant here is a persistence character (allow_occupant_types stays
/// human-only, inherited), so force-store always applies instead.
/obj/structure/machinery/cryopod/prison/process()
	for(var/mob/living/carbon/O in prison_occupants.Copy())
		if(!O.client && O.ckey && O.stat != DEAD && GLOB.config.sql_enabled)
			if(ishuman(O) && O:persistence_in_cryo)
				continue
			persistence_force_store(O)
			prison_occupants -= O

/obj/structure/machinery/cryopod/prison/update_icon()
	flick("[initial(icon_state)]-anim", src)
	if(length(prison_occupants))
		name = "[initial(name)] ([english_list(prison_occupants)])"
		if(stat & BROKEN)
			icon_state = "[initial(icon_state)]-broken-closed"
		else if(stat & NOPOWER)
			icon_state = "[initial(icon_state)]-closed"
		else
			icon_state = "[initial(icon_state)]-working"
		return
	name = initial(name)
	if(stat & BROKEN)
		icon_state = "[initial(icon_state)]-broken"
	else if(stat & NOPOWER)
		icon_state = "[initial(icon_state)]-off"
	else
		icon_state = initial(icon_state)
