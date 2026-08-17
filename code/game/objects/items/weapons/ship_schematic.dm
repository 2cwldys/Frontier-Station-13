/*
 * Ship Schematic
 * A physical, tradeable, lootable bearer token that IS ownership of a
 * drydock ship -- whoever currently carries a valid one (anywhere on their
 * person, not just in an active hand) is treated as that ship's owner for
 * every purpose (/datum/drydock_ship/proc/owned_by(), persistence_shuttles.dm).
 * This applies to personal AND faction-purchased ships alike -- there is no
 * separate faction-officer-rank fallback anymore.
 *
 * Using it (attack_self, i.e. in an active hand) opens a TGUI covering
 * everything about THIS ship: Stash/Retrieve, Board/Invite/Exit, Rename,
 * Crew management, and Remove/Scuttle. All of it used to also exist on the
 * Drydock console program (drydock.dm) -- that's been gutted down to just
 * Buy (there's no schematic to act on before one is minted) and Withdraw
 * Schematic (the recovery path for when there's no physical item to act on
 * yet), since day-to-day ship management is entirely object-based now.
 *
 * Depositing it into a console/laptop (not handheld) "banks" it -- destroys
 * the physical item and marks the ship recoverable via the Drydock
 * program's "withdraw_schematic" action, gated on the ship's CURRENT owner
 * identity (owner_ckey/owner_char_name/faction_uid) OR its permanent title
 * (is_title_holder(), persistence_shuttles.dm), since there's no item to
 * check during a withdrawal. Banking a ship you're not titled to transfers
 * that current-owner identity to you and flags the schematic
 * reported_stolen -- but never touches title, which only a deliberate
 * "Give Title" (drydockGiveSchematic(), the Drydock program) can move.
 * reported_stolen clears passively once the title-holder is confirmed
 * holding it again (_maybe_clear_stolen()).
 *
 * First Responder repossession (drydockRepossess(), persistence_shuttles.dm)
 * finds and permanently invalidates whatever live schematic exists for a
 * seized ship -- shows REPOSSESSED, grants no access ever again -- mirroring
 * ID card revocation exactly.
 */
/obj/item/ship_schematic
	name = "ship schematic"
	desc = "A folded technical schematic -- and the deed of ownership -- for a drydock-class vessel."
	icon = 'icons/obj/item/blueprints.dmi'
	icon_state = "blueprints2"
	item_state = "blueprints2"
	w_class = WEIGHT_CLASS_SMALL
	// This is a deed, not a tool -- it must never wear out and "break" from
	// ordinary use/time (items.dm's degrade_durability()/wear_broken), which
	// would otherwise strand whatever ship it controls with no schematic and
	// nothing banked to withdraw. FALSE makes every degrade path (passive
	// time-worn ticks, tool-use, melee-hit) an unconditional no-op.
	degrades_with_use = FALSE

	/// The ship this schematic is bound to (GLOB.drydock_ships, keyed by
	/// stringified shuttle_id). Not durable on its own -- see
	/// bound_purchased_at below, shuttle_id gets reused once a ship is
	/// scuttled/sold.
	var/shuttle_id
	/// Snapshot of the ship's purchased_at at mint time -- guards against
	/// shuttle_id reuse (V099__drydock_shuttle_id_reuse.sql). A live lookup
	/// whose purchased_at no longer matches this means the shuttle_id slot
	/// was freed and reassigned to an unrelated later ship -- this
	/// schematic controls nothing anymore, rather than silently granting
	/// access to whatever ship now holds that slot.
	var/bound_purchased_at
	/// TRUE once repossessed by the Hub (drydockRepossess()) -- permanently
	/// dead, mirrors ID card revoked exactly. Distinct from "stale"
	/// (shuttle_id reused): this is deliberate seizure, not slot collision.
	var/repossessed = FALSE
	/// Per-ckey Enter Ship cooldown -- same shape/purpose as the Drydock
	/// console program's own former last_boarded_by_ckey, just scoped to
	/// this item now that boarding is triggered from the schematic instead.
	var/list/last_boarded_by_ckey = list()

/// Resolves the live /datum/drydock_ship this schematic actually controls
/// right now, or null if repossessed, or if shuttle_id/purchased_at no
/// longer match anything live (stale/scuttled-and-reused).
/obj/item/ship_schematic/proc/resolve_ship()
	if(repossessed || !shuttle_id)
		return null
	var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
	if(!DS || DS.purchased_at != bound_purchased_at)
		return null
	return DS

/// Keeps name/desc in sync with current state -- call after minting,
/// restoring from persistence, or repossessing.
/obj/item/ship_schematic/proc/refresh_name()
	if(repossessed)
		name = "REPOSSESSED"
		return
	var/datum/drydock_ship/DS = resolve_ship()
	if(!DS)
		name = "voided ship schematic"
		return
	name = "ship schematic -- [DS.display_name()]"

/// Passive "stolen" clear -- called from get_examine_text()/ui_data(), the
/// two places a mob meaningfully interacts with this exact schematic. Only
/// clears if user is the one ACTUALLY holding this item (not just standing
/// nearby examining someone else's) and is DS's permanent title-holder --
/// otherwise a true owner glancing at someone else's stolen schematic from
/// across the room would incorrectly clear it.
/obj/item/ship_schematic/proc/_maybe_clear_stolen(mob/user, datum/drydock_ship/DS)
	if(!DS.reported_stolen || !user)
		return
	if(!(src in user.get_all_contents()))
		return
	if(!DS.is_title_holder(user))
		return
	SSpersistence.drydockClearStolenFlag(DS.shuttle_id)

/obj/item/ship_schematic/get_examine_text(mob/user, distance, is_adjacent, infix = "", suffix = "", show_extended)
	. = ..()
	if(repossessed)
		. += SPAN_WARNING("It has been stamped REPOSSESSED and no longer functions.")
		return
	var/datum/drydock_ship/DS = resolve_ship()
	if(!DS)
		. += SPAN_WARNING("It no longer corresponds to any ship -- it's gone stale.")
		return
	_maybe_clear_stolen(user, DS)
	. += "The title belongs to: [DS.title_faction_uid ? get_faction_name(DS.title_faction_uid) : (DS.title_char_name || "Unknown")]."
	if(DS.reported_stolen)
		. += SPAN_WARNING("This schematic has been reported stolen.")

/obj/item/ship_schematic/attack_self(mob/user)
	. = ..()
	ui_interact(user)

/obj/item/ship_schematic/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShipSchematic", "Ship Schematic")
		ui.open()

/obj/item/ship_schematic/ui_data(mob/user)
	var/list/data = list()
	var/datum/drydock_ship/DS = resolve_ship()
	data["repossessed"] = repossessed
	data["valid"] = !!DS
	if(!DS)
		return data

	_maybe_clear_stolen(user, DS)

	data["display_name"] = DS.display_name()
	data["stashed"] = DS.stashed
	data["ready"] = DS.ready
	data["title_holder_name"] = DS.title_faction_uid ? get_faction_name(DS.title_faction_uid) : (DS.title_char_name || "Unknown")
	data["reported_stolen"] = DS.reported_stolen
	// Title transfer is title-holder-only (see the "give_title" ui_act) --
	// surfaced so the button is hidden outright for everyone else rather than
	// offered and then refused.
	data["can_give_title"] = DS.can_transfer_title(user) ? TRUE : FALSE
	data["needs_rename"] = !DS.custom_name
	data["shuttle_id"] = DS.shuttle_id
	data["save_in_progress"] = SSpersistence.save_in_progress
	data["busy"] = _drydock_ship_busy(DS.shuttle_id)
	// _drydockStashRun() refuses a non-forced stash whenever the ship is away
	// from its own home landmark (docked at a beacon, in a hangar slot, or
	// nested in another ship's visiting slot). It only said so AFTER the
	// click, so the Stash button looked perfectly available right up until it
	// wasn't -- report the exact same comparison here so the button and the
	// server can't disagree.
	data["away_from_home"] = FALSE
	if(!DS.stashed && DS.z)
		var/obj/effect/overmap/visitable/ship/landable/home_marker = GLOB.map_sectors["[DS.z]"]
		var/datum/shuttle/home_shuttle = istype(home_marker) ? SSshuttle.shuttles[home_marker.shuttle] : null
		// The exact proc _drydockStashRun() gates on, so the button and the
		// server can never disagree. Asks whether the hull is physically in its
		// own open space rather than comparing landmark objects -- that
		// comparison reported a ship sitting at home as docked whenever
		// marker.landmark had gone stale, with no way to clear it.
		if(istype(home_shuttle) && !_drydock_ship_is_home(DS, home_shuttle))
			data["away_from_home"] = TRUE

	var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
	data["sub_shuttle_tags"] = (template && length(template.sub_shuttle_tags)) ? template.sub_shuttle_tags : list()

	var/board_ready_at = last_boarded_by_ckey[user.ckey] ? (last_boarded_by_ckey[user.ckey] + 30) : 0
	data["can_board"] = world.time >= board_ready_at
	data["board_cooldown"] = max(0, round((board_ready_at - world.time) / 10))
	data["can_disembark"] = !!_drydock_ship_at(GET_Z(user))
	data["aboard_this_ship"] = !DS.stashed && GET_Z(user) == DS.z

	data["crew"] = list()
	if(SSpersistence.databaseCheckConnection("ship_schematic ui_data crew"))
		var/datum/db_query/crewq = SSdbcore.NewQuery(
			"SELECT ckey, char_name, label FROM ss13_ship_crew WHERE shuttle_id = :id",
			list("id" = DS.shuttle_id)
		)
		crewq.Execute()
		if(SSpersistence.databaseCheckQueryResult(crewq, "ship_schematic ui_data crew select"))
			while(crewq.NextRow())
				data["crew"] += list(list("ckey" = crewq.item[1], "char_name" = crewq.item[2], "label" = crewq.item[3]))
		qdel(crewq)

	return data

/obj/item/ship_schematic/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	var/datum/drydock_ship/DS = resolve_ship()
	if(!DS)
		return TRUE
	switch(action)
		if("retrieve")
			var/turf/from_turf = get_turf(user)
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested retrieve of shuttle_id=[DS.shuttle_id].")
			SSpersistence.drydockRetrieve(DS.shuttle_id, null, from_turf, user)
			. = TRUE

		if("stash")
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested stash of shuttle_id=[DS.shuttle_id].")
			SSpersistence.drydockStash(DS.shuttle_id, user)
			. = TRUE

		if("board")
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested Enter Ship.")
			_drydock_board_core(user, null, last_boarded_by_ckey)
			. = TRUE

		// Same delivery pipeline "board" above uses (cooldown, combat/dead
		// checks, spool-up VFX, re-validation) -- the only difference is the
		// landing turf, forced to the sub-ship's own console
		// (_drydock_subship_console_turf(), telepad_drydock_boarding.dm)
		// instead of letting _drydock_board_deliver() resolve the main
		// hull's. target stays the main ship (DS) since a sub-ship has no
		// independent ledger entry of its own -- ownership/distance/ready
		// checks correctly apply to the ship this schematic actually
		// controls. Shares last_boarded_by_ckey with "board" deliberately,
		// so rapidly switching between the two can't be used to dodge the
		// cooldown.
		if("board_subship")
			var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
			if(!template || !length(template.sub_shuttle_tags))
				return TRUE
			var/tag = (template.sub_shuttle_tags.len == 1) ? template.sub_shuttle_tags[1] : tgui_input_list(user, "Board which sub-ship?", "Enter Sub-Ship", template.sub_shuttle_tags)
			if(!tag)
				return TRUE
			var/turf/sub_console = _drydock_subship_console_turf(tag)
			if(!sub_console)
				to_chat(user, SPAN_WARNING("Could not locate that sub-ship's navigation console."))
				return TRUE
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested Enter Sub-Ship ('[tag]').")
			_drydock_board_deliver(user, DS, last_boarded_by_ckey, sub_console)
			. = TRUE

		if("invite_board")
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested Invite to Board.")
			_drydock_invite_board_core(user, last_boarded_by_ckey)
			. = TRUE

		if("disembark")
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested Exit Ship.")
			_drydock_disembark_core(user)
			. = TRUE

		if("rename_ship")
			var/new_name = tgui_input_text(user, "New display name for this ship (blank to reset to default):", "Rename Ship", "", max_length = 64)
			if(isnull(new_name))
				return TRUE
			var/new_class = tgui_input_text(user, "New class designation (blank to reset to default):", "Rename Ship", "", max_length = 32)
			SSpersistence.drydockRename(DS.shuttle_id, new_name, new_class || "", user)
			. = TRUE

		if("rename_subship")
			var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
			if(!template || !length(template.sub_shuttle_tags))
				return TRUE
			var/tag = (template.sub_shuttle_tags.len == 1) ? template.sub_shuttle_tags[1] : tgui_input_list(user, "Rename which sub-ship?", "Rename Sub-ship", template.sub_shuttle_tags)
			if(!tag)
				return TRUE
			var/new_name = tgui_input_text(user, "New display name for '[tag]':", "Rename Sub-ship", tag, max_length = 64)
			if(!new_name)
				return TRUE
			SSpersistence.drydockRenameSubship(DS.shuttle_id, tag, new_name, user)
			. = TRUE

		if("add_crew")
			var/target_ckey = tgui_input_text(user, "Ckey to add to this ship's crew:", "Add Crew", "", max_length = 32)
			if(!target_ckey)
				return TRUE
			// Crew access is scoped to one specific CHARACTER, not the whole
			// account -- see owned_by()/drydockAddCrew() (persistence_shuttles.dm).
			// encode = FALSE -- this is an identity key later compared raw
			// against real_name (_drydock_full_access_check(),
			// telepad_drydock_boarding.dm), not text for HTML display. The
			// default HTML-encoding a name with an apostrophe/&/<>/" would
			// silently break that exact-string match.
			var/target_char_name = tgui_input_text(user, "Exact character name for '[target_ckey]' to grant boarding access to:", "Add Crew", "", max_length = 64, encode = FALSE)
			if(!target_char_name)
				return TRUE
			var/label = tgui_input_text(user, "Optional label (e.g. their role):", "Add Crew", "", max_length = 64)
			SSpersistence.drydockAddCrew(DS.shuttle_id, target_ckey, target_char_name, label || "", user)
			. = TRUE

		if("remove_crew")
			SSpersistence.drydockRemoveCrew(DS.shuttle_id, params["ckey"], params["char_name"], user)
			. = TRUE

		// Moved here from the Drydock console, and re-gated in the process.
		// The console let whoever CURRENTLY owned the hull hand the title on,
		// which let a thief who banked a stolen ship launder its provenance.
		// is_title_holder() (persistence_shuttles.dm) is the permanent
		// provenance check and covers both the personally-titled and
		// faction-titled cases, so only the original holder (or an admin) can
		// sign the title over.
		if("give_title")
			// can_transfer_title() (persistence_shuttles.dm) -- title holder for
			// a personal ship, officer/command rank for a faction-titled one.
			if(!DS.can_transfer_title(user))
				to_chat(user, DS.title_faction_uid \
					? SPAN_WARNING("Only an officer or command member of [get_faction_name(DS.title_faction_uid)] can sign this ship's title over.") \
					: SPAN_WARNING("Only this ship's title holder can sign its title over."))
				log_drydock_warning("drydock ui_act (schematic): [key_name(user)] may not transfer the title for shuttle_id=[DS.shuttle_id].")
				return TRUE
			// Handing off a stolen ship is still handing off a stolen ship --
			// refuse outright rather than let this launder reported_stolen.
			if(DS.reported_stolen && !check_rights(R_ADMIN, 0, user))
				to_chat(user, SPAN_WARNING("This ship is reported stolen -- its title can't be legitimately transferred until it's back with its rightful owner."))
				log_drydock_warning("drydock ui_act (schematic): [key_name(user)] tried to give away reported_stolen shuttle_id=[DS.shuttle_id].")
				return TRUE
			var/target_ckey = tgui_input_text(user, "Ckey to give this ship's title to:", "Give Title", "", max_length = 32)
			if(!target_ckey)
				return TRUE
			// encode = FALSE for the same reason add_crew above uses it -- an
			// identity key compared raw against real_name, not display text.
			var/target_char_name = tgui_input_text(user, "Exact character name for '[target_ckey]' to title the ship to:", "Give Title", "", max_length = 64, encode = FALSE)
			if(!target_char_name)
				return TRUE
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested give_title for shuttle_id=[DS.shuttle_id] to '[target_char_name]' ([target_ckey]).")
			SSpersistence.drydockGiveSchematic(DS.shuttle_id, target_ckey, target_char_name, user)
			. = TRUE

		if("sell")
			if(!DS.stashed)
				to_chat(user, SPAN_WARNING("Stash the ship before removing it."))
				return TRUE
			if(tgui_alert(user, "Permanently remove this ship? This cannot be undone.", "Remove Ship", list("Remove", "Cancel")) != "Remove")
				return TRUE
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested sell of shuttle_id=[DS.shuttle_id].")
			if(SSpersistence.drydockSell(DS.shuttle_id, user))
				qdel(src)
			. = TRUE

		if("scuttle")
			if(tgui_alert(user, "Permanently scuttle this ship? This costs 25000cr and cannot be undone.", "Scuttle Ship", list("Scuttle", "Cancel")) != "Scuttle")
				return TRUE
			log_drydock("drydock ui_act (schematic): [key_name(user)] requested scuttle of shuttle_id=[DS.shuttle_id].")
			if(SSpersistence.drydockScuttle(DS.shuttle_id, user))
				qdel(src)
			. = TRUE

/// Tapping this schematic directly with a First Responder device in
/// tap_mode == "repossess" seizes its ship the same way tapping the
/// schematic's holder (handle_ship_seizure_tap(), first_responder.dm)
/// already does -- the item itself is a valid tap target too, not just
/// whoever's currently carrying it.
/obj/item/ship_schematic/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, /obj/item/modular_computer))
		var/obj/item/modular_computer/computer = attacking_item
		var/datum/computer_file/program/security/first_responder/FR = computer.active_program
		if(istype(FR) && FR.tap_mode == "repossess")
			FR.handle_ship_seizure_tap_item(src, user)
			return TRUE
	return ..()

/// Never let a console/laptop's own attackby() consume this click -- a
/// modular computer has its own generic tool/item fallbacks that would
/// otherwise swallow the deposit before it ever reaches afterattack()
/// below. Same fix applied to the hyperspanner earlier, same reason.
/obj/item/ship_schematic/resolve_attackby(atom/A, mob/user, click_parameters)
	if(_is_valid_deposit_target(A))
		pre_attack(A, user)
		add_fingerprint(user)
		return FALSE
	return ..()

/obj/item/ship_schematic/proc/_is_valid_deposit_target(atom/A)
	if(!istype(A, /obj/item/modular_computer))
		return FALSE
	if(istype(A, /obj/item/modular_computer/handheld))
		return FALSE
	return TRUE

/obj/item/ship_schematic/afterattack(atom/target, mob/user, proximity_flag)
	. = ..()
	if(!proximity_flag || !_is_valid_deposit_target(target))
		return
	var/datum/drydock_ship/DS = resolve_ship()
	if(!DS)
		to_chat(user, SPAN_WARNING("\The [src] is voided -- there's nothing to deposit."))
		return
	if(!DS.stashed)
		to_chat(user, SPAN_WARNING("[DS.display_name()] is currently deployed -- stash it before depositing the schematic."))
		return
	if(!SSpersistence.drydockBankSchematic(DS.shuttle_id, user))
		to_chat(user, SPAN_WARNING("\The [target] refuses the deposit."))
		return
	to_chat(user, SPAN_GOOD("\The [src] is banked in \the [target] -- withdrawable from any Drydock terminal."))
	qdel(src)

/obj/item/ship_schematic/persistent_objects_get_content()
	var/list/content = ..()
	content["shuttle_id"] = shuttle_id
	content["bound_purchased_at"] = bound_purchased_at
	content["repossessed"] = repossessed
	return content

/obj/item/ship_schematic/persistent_objects_apply_content(content, x, y, z)
	. = ..()
	if(!islist(content))
		return
	shuttle_id = content["shuttle_id"]
	bound_purchased_at = content["bound_purchased_at"]
	repossessed = content["repossessed"]
	refresh_name()
