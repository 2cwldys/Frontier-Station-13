/*
 * Ship Drydock
 * Ownership of a drydock ship is entirely object-based now -- whoever holds
 * a valid /obj/item/ship_schematic (ship_schematic.dm) for a ship can
 * retrieve/stash/board/invite/disembark/rename/manage crew/sell/scuttle it
 * directly from the schematic's own TGUI. This console program only covers
 * the two things that genuinely can't live on an item: Buying a ship (there
 * is no schematic to act on before one is minted) and Withdrawing a banked
 * schematic (the recovery path for when there's no physical item to act on
 * yet -- after a voluntary deposit, or after a First Responder repossession
 * + Return to Owner). See SSpersistence.drydockBuy()/drydockWithdrawSchematic()
 * (persistence_shuttles.dm) for the actual backend engine.
 */
/datum/computer_file/program/drydock
	filename = "drydock"
	filedesc = "Ship Drydock"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Buy a drydock ship, or withdraw a banked schematic."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_TABLET
	requires_ntnet = FALSE
	size = 4
	tgui_id = "ShuttleDrydock"
	ui_auto_update = TRUE

/datum/computer_file/program/drydock/ui_data(mob/user)
	var/list/data = initial_data()

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

	data["templates"] = list()
	for(var/tid in SSmapping.drydock_ship_templates)
		var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[tid]
		data["templates"] += list(list(
			"template_id" = tid, "display_name" = T.name,
			"price" = T.price
		))

	// Withdraw candidates -- every ship this user has a historical claim to
	// (the same identity check withdraw_schematic itself re-verifies below)
	// that's currently banked with no live schematic anywhere.
	data["withdrawable"] = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS || !DS.schematic_banked || DS.repossessed)
			continue
		var/has_claim = (DS.owner_ckey == user.ckey && DS.owner_char_name == user.real_name) || (DS.faction_uid && can_configure_faction_shackle(user, DS.faction_uid, 1)) || data["is_admin"]
		if(!has_claim)
			continue
		data["withdrawable"] += list(list("shuttle_id" = DS.shuttle_id, "display_name" = DS.display_name()))

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
			// The one place still gated by the historical owner_ckey/
			// owner_char_name/faction_uid identity instead of item-possession,
			// since the whole point is there's no item to check right now.
			// See owned_by()'s doc comment (persistence_shuttles.dm).
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
