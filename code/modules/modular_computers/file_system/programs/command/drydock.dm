/*
 * Ship Drydock
 * Ownership of a drydock ship is entirely object-based now -- whoever holds
 * a valid /obj/item/ship_schematic (ship_schematic.dm) for a ship can
 * retrieve/stash/board/invite/disembark/rename/manage crew/sell/scuttle it
 * directly from the schematic's own TGUI. This console program covers
 * things that genuinely can't live on an item: Buying a ship (there is no
 * schematic to act on before one is minted), Withdrawing a banked schematic
 * (the recovery path for when there's no physical item to act on yet --
 * after a voluntary deposit, or after a First Responder repossession +
 * Return to Owner), and formally Giving a banked ship's title to someone
 * else. Both Withdraw and Give are gated on the CURRENT owner identity
 * (owner_ckey/owner_char_name/faction_uid) -- deliberately NOT the permanent
 * title (is_title_holder(), persistence_shuttles.dm): a thief who
 * successfully banks a stolen ship (drydockBankSchematic() reassigns current
 * ownership to them) fully controls its fate from then on, title included --
 * the original title-holder has no console-side recovery right, only
 * physically getting the schematic back. See SSpersistence.drydockBuy()/
 * drydockWithdrawSchematic()/drydockGiveSchematic() (persistence_shuttles.dm)
 * for the actual backend engine.
 *
 * It also duplicates the schematic's Enter/Invite/Exit boarding actions --
 * boarding rights were never exclusive to holding the item: a ship's
 * separate crew list (DS.crew_ckeys, drydockAddCrew()/drydockRemoveCrew(),
 * persistence_shuttles.dm) grants specific characters access without ever
 * handing them ownership or a schematic. Without this, a crew member would
 * have no UI at all to exercise access the backend already grants them --
 * _drydock_board_resolve_ship() (telepad_drydock_boarding.dm) already
 * searches every ship the calling mob has access to (owner, faction, or
 * crew) and prompts a picker if more than one is in range, so this console
 * just needs its own copy of the same three-button wiring, no new backend
 * logic required.
 */
/datum/computer_file/program/drydock
	filename = "drydock"
	filedesc = "Ship Drydock"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Buy a drydock ship, withdraw a banked schematic, give a banked ship's title to someone else, or board/disembark a ship you have crew access to."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_TABLET
	requires_ntnet = FALSE
	size = 4
	tgui_id = "ShuttleDrydock"
	ui_auto_update = TRUE
	/// Per-ckey Enter Ship cooldown -- independent of the schematic's own
	/// last_boarded_by_ckey (ship_schematic.dm); the console and a schematic
	/// are separate physical entry points, so each tracks its own cooldown.
	var/list/last_boarded_by_ckey = list()

/datum/computer_file/program/drydock/ui_data(mob/user)
	var/list/data = initial_data()

	// CENTRAL_SYNC_SHIPS -- pulls in any ship centrally owned by this
	// character that this server has never seen locally yet (bought on a
	// different server sharing the same central database), before the
	// "your ships" list below is built. No-op entirely when central sync
	// is off (gated inside the proc itself).
	_shipHydrateOwnedFromCentral(user.ckey, user.real_name)

	var/obj/item/card/id/ID = user.GetIdCard()
	var/own_faction = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
	data["own_faction_name"] = own_faction ? get_faction_name(own_faction) : null

	// Shown in the Market section so a purchase's affordability is visible
	// without needing to check an ATM or the cargo console first.
	var/datum/money_account/personal_account = SSeconomy.get_account_by_ckey_and_name(user.ckey, user.real_name)
	data["personal_balance"] = personal_account ? personal_account.money : null
	data["faction_balance"] = own_faction ? get_faction_account_balance(own_faction) : null
	data["is_admin"] = check_rights(R_ADMIN, 0, user)
	data["can_buy_faction"] = own_faction && can_configure_faction_shackle(user, own_faction, 1)
	data["save_in_progress"] = SSpersistence.save_in_progress

	var/board_ready_at = last_boarded_by_ckey[user.ckey] ? (last_boarded_by_ckey[user.ckey] + 30) : 0
	data["can_board"] = world.time >= board_ready_at
	data["board_cooldown"] = max(0, round((board_ready_at - world.time) / 10))
	// Grey out Enter Ship while the user's own ship is still mid-retrieve --
	// this console isn't bound to one specific ship, so unlike
	// ship_schematic.dm's own "ready" field this is a best-effort "is there
	// one of yours still retrieving right now" hint, not a guarantee of
	// which ship "board" will actually resolve to.
	data["ship_retrieving"] = _drydock_user_has_retrieving_ship(user)
	// Gates the Enter Sub-Ship button, same best-effort "one of yours has one"
	// basis as ship_retrieving just above.
	data["sub_shuttle_tags"] = _drydock_user_boardable_subship_tags(user)
	// Doubles as the "hide Enter Ship" signal too -- there's no single ship
	// this console is bound to, so "already aboard some drydock ship" is the
	// closest equivalent to the schematic's own per-ship aboard_this_ship.
	data["can_disembark"] = !!_drydock_ship_at(GET_Z(user))

	data["templates"] = list()
	for(var/tid in SSmapping.drydock_ship_templates)
		var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[tid]
		if(T.hidden_from_catalog)
			continue
		data["templates"] += list(list(
			"template_id" = tid, "display_name" = T.name,
			"price" = T.price
		))

	// Withdraw/Give candidates -- every ship this user is the CURRENT
	// recognized owner of (or admin) that's currently banked with no live
	// schematic anywhere. Deliberately NOT the permanent title -- once a
	// theft-then-bank (drydockBankSchematic()) reassigns current ownership
	// to someone else, the original title-holder genuinely loses this
	// access; title is a record of provenance and what flags reported_stolen,
	// not a standing recovery right. Getting a stolen ship back means
	// physically recovering the schematic (or the current owner giving it
	// back), not walking up to any console.
	data["withdrawable"] = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || !DS.schematic_banked || DS.repossessed)
			continue
		var/has_claim = (DS.owner_ckey == user.ckey && DS.owner_char_name == user.real_name) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1)) || data["is_admin"]
		if(!has_claim)
			continue
		data["withdrawable"] += list(list("shuttle_id" = DS.shuttle_id, "display_name" = DS.display_name(), "reported_stolen" = DS.reported_stolen))

	// EVA Recall candidates -- every currently-deployed, non-repossessed ship
	// this user holds the permanent title for (or officer+ rank in, for a
	// faction ship) -- see can_trigger_eva_recall() (persistence_shuttles.dm).
	// Excludes repossessed ships for the same reason withdrawable does just
	// above: a Hub-repossessed ship isn't the title holder's to act on.
	data["eva_recallable"] = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || DS.stashed || DS.repossessed)
			continue
		if(!DS.can_trigger_eva_recall(user))
			continue
		var/recall_cooldown = max(0, round((DS.last_recall_at + DRYDOCK_EVA_RECALL_COOLDOWN - world.time) / 10))
		data["eva_recallable"] += list(list("shuttle_id" = DS.shuttle_id, "display_name" = DS.display_name(), "cooldown" = recall_cooldown))

	return data

/datum/computer_file/program/drydock/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE
	var/mob/user = usr

	// Buying still requires a real console/laptop -- a PDA shouldn't be able
	// to spend a faction's/personal account's money this freely.
	if(action == "buy_template" && istype(computer, /obj/item/modular_computer/handheld))
		to_chat(user, SPAN_WARNING("This requires a full console or laptop, not a handheld device."))
		return TRUE

	switch(action)
		if("buy_template")
			var/template_id = params["template_id"]
			var/as_faction = params["as_faction"] ? TRUE : FALSE
			var/obj/item/card/id/ID = user.GetIdCard()
			var/owner_ckey = null
			var/faction_uid = null
			if(as_faction)
				faction_uid = (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null
			else
				owner_ckey = user.ckey
			log_drydock("drydock ui_act: [key_name(user)] requested buy_template '[template_id]' ([as_faction ? "faction" : "personal"]).")
			SSpersistence.drydockBuy(template_id, owner_ckey, faction_uid, user)
			return TRUE

		if("withdraw_schematic")
			// Gated by the CURRENT owner_ckey/owner_char_name/faction_uid
			// identity, not the permanent title -- see the doc comment on
			// ui_data()'s "withdrawable" list above. There's no item to check
			// during a withdrawal, so this identity check is what stands in
			// for it. See owned_by()'s doc comment (persistence_shuttles.dm).
			var/shuttle_id = text2num(params["shuttle_id"])
			var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
			if(!DS)
				return TRUE
			if(!(check_rights(R_ADMIN, 0, user) || (DS.owner_ckey == user.ckey && DS.owner_char_name == user.real_name) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1))))
				to_chat(user, SPAN_WARNING("You don't have permission to withdraw this ship's schematic."))
				log_drydock_warning("drydock ui_act: [key_name(user)] lacks permission to withdraw the schematic for shuttle_id=[shuttle_id].")
				return TRUE
			log_drydock("drydock ui_act: [key_name(user)] requested withdraw_schematic for shuttle_id=[shuttle_id].")
			SSpersistence.drydockWithdrawSchematic(shuttle_id, user)
			return TRUE

		if("eva_recall")
			// Gated by can_trigger_eva_recall() -- title holder for a
			// personal ship, officer+ for a faction ship (same rule as
			// signing over the title, can_transfer_title()). Resolved by
			// shuttle_id, not proximity -- the triggering user may not be
			// anywhere near the ship they're recalling crew to.
			var/shuttle_id = text2num(params["shuttle_id"])
			var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
			if(!DS || DS.stashed)
				to_chat(user, SPAN_WARNING("That ship isn't currently deployed."))
				return TRUE
			if(!DS.can_trigger_eva_recall(user))
				to_chat(user, SPAN_WARNING("You don't have permission to issue an EVA recall for this ship."))
				log_drydock_warning("drydock ui_act: [key_name(user)] lacks permission to issue EVA recall for shuttle_id=[shuttle_id].")
				return TRUE
			if(DS.last_recall_at && world.time < (DS.last_recall_at + DRYDOCK_EVA_RECALL_COOLDOWN))
				to_chat(user, SPAN_WARNING("[DS.display_name()]'s EVA recall is still cooling down -- try again in [round((DS.last_recall_at + DRYDOCK_EVA_RECALL_COOLDOWN - world.time) / 10)] second\s."))
				return TRUE
			DS.last_recall_at = world.time
			var/reached = _drydock_eva_recall(DS, user)
			to_chat(user, SPAN_GOOD("EVA recall sent for [DS.display_name()] -- reached [reached] crew member\s."))
			log_drydock("drydock ui_act: [key_name(user)] issued EVA recall for shuttle_id=[shuttle_id] ([DS.display_name()]), reached [reached].")
			return TRUE

		// "give_schematic" deliberately no longer lives here -- title transfer
		// moved to the schematic item's own UI (ship_schematic.dm), where it is
		// gated on the PERMANENT title holder (is_title_holder()) rather than
		// whoever currently happens to own the hull. Handing over provenance is
		// the title holder's call alone; a thief who banked a stolen ship
		// should not be able to launder the title from any console.

		if("board")
			log_drydock("drydock ui_act: [key_name(user)] requested Enter Ship.")
			_drydock_board_core(user, null, last_boarded_by_ckey)
			return TRUE

		// Same action the ship schematic offers (ship_schematic.dm), just
		// reached from the program instead. The schematic is bound to one
		// ship; this isn't, so the ship is resolved exactly the way "board"
		// above resolves it -- _drydock_board_resolve_ship() -- and then its
		// own template supplies the sub-ship tags.
		if("board_subship")
			var/datum/drydock_ship/DS = _drydock_board_resolve_ship(user, null)
			if(!DS)
				return TRUE
			var/datum/map_template/drydock_ship/template = SSmapping.drydock_ship_templates[DS.template_id]
			if(!template || !length(template.sub_shuttle_tags))
				to_chat(user, SPAN_WARNING("That ship carries no sub-ship."))
				return TRUE
			var/tag = (template.sub_shuttle_tags.len == 1) ? template.sub_shuttle_tags[1] : tgui_input_list(user, "Board which sub-ship?", "Enter Sub-Ship", template.sub_shuttle_tags)
			if(!tag)
				return TRUE
			var/turf/sub_console = _drydock_subship_console_turf(DS.shuttle_id, tag)
			if(!sub_console)
				to_chat(user, SPAN_WARNING("Could not locate that sub-ship's navigation console."))
				return TRUE
			log_drydock("drydock ui_act: [key_name(user)] requested Enter Sub-Ship ('[tag]').")
			_drydock_board_deliver(user, DS, last_boarded_by_ckey, sub_console)
			return TRUE

		if("invite_board")
			log_drydock("drydock ui_act: [key_name(user)] requested Invite to Board.")
			_drydock_invite_board_core(user, last_boarded_by_ckey)
			return TRUE

		if("disembark")
			log_drydock("drydock ui_act: [key_name(user)] requested Exit Ship.")
			_drydock_disembark_core(user)
			return TRUE
