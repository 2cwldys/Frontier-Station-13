/*
 * Invoice Manager
 * Creates payable invoice papers. The payee is either the operator's personal
 * bank account (from their ID) or the faction this computer is shackled to.
 * Swiping an ID / charge card / faction charge card on the printed invoice
 * settles it -- see /obj/item/paper/invoice.
 */

/datum/computer_file/program/invoice_maker
	filename = "invoices"
	filedesc = "Invoice Manager"
	program_icon_state = "generic"
	program_key_icon_state = "yellow_key"
	extended_desc = "Create and print invoices payable to your personal account or your faction's account."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 4
	color = LIGHT_COLOR_BLUE
	tgui_id = "InvoiceProgram"
	ui_auto_update = TRUE

	var/status_message = ""

/datum/computer_file/program/invoice_maker/ui_data(mob/user)
	var/list/data = initial_data()
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : ""
	var/faction_registered = net && islist(GLOB.persistence_faction_cache) && (net in GLOB.persistence_faction_cache)

	data["status_message"] = status_message

	// Operator's personal account (from worn/held ID)
	var/obj/item/card/id/I = user.GetIdCard()
	data["operator_name"]    = I ? I.registered_name : null
	data["operator_account"] = (I && I.associated_account_number) ? I.associated_account_number : null

	// Faction context. Matches the ATM's faction_deposit precedent for
	// non-privileged, faction-benefiting actions: your current ID just needs
	// to be issued by the terminal's shackled faction. This does NOT require
	// formal DB member registration (get_faction_member()) -- an ID's
	// employer_faction can be set via character prefs or an admin without
	// ever registering the wearer as a member, which otherwise locked out
	// legitimately-badged faction staff from issuing invoices.
	data["faction_uid"]        = net
	data["faction_name"]       = faction_registered ? get_faction_name(net) : null
	data["faction_registered"] = faction_registered
	data["is_faction_member"]  = faction_registered && I && (normalize_faction_uid(I.employer_faction) == net)

	data["has_printer"]  = !!computer?.nano_printer
	data["stored_paper"] = computer?.nano_printer ? computer.nano_printer.stored_paper : 0

	return data

/datum/computer_file/program/invoice_maker/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/user = usr

	switch(action)
		if("print_invoice")
			if(!computer?.nano_printer)
				status_message = "Error: no nano printer installed."
				return TRUE
			if(!computer.nano_printer.stored_paper)
				status_message = "Error: printer is out of paper."
				return TRUE

			var/amount = round(text2num(params["amount"]) || 0, 0.01)
			if(amount <= 0 || amount > 1000000)
				status_message = "Invalid amount. Must be between 0.01 and 1,000,000 credits."
				return TRUE
			var/purpose = sanitize(params["purpose"], 128)
			if(!purpose)
				purpose = "Services rendered"
			var/payee_type = params["payee_type"]

			var/obj/item/paper/invoice/INV = new(get_turf(computer))
			INV.amount = amount
			INV.purpose = purpose

			if(payee_type == "faction")
				var/net = normalize_faction_uid(computer.persistent_network)
				if(!net || !islist(GLOB.persistence_faction_cache) || !(net in GLOB.persistence_faction_cache))
					status_message = "This terminal is not linked to a registered faction."
					qdel(INV)
					return TRUE
				var/obj/item/card/id/fac_id = user.GetIdCard()
				var/id_matches_faction = istype(fac_id) && (normalize_faction_uid(fac_id.employer_faction) == net)
				if(!id_matches_faction && !check_rights(R_ADMIN, 0, user))
					status_message = "Your ID is not issued by [get_faction_name(net)]. Only members can issue faction invoices here."
					qdel(INV)
					return TRUE
				INV.payee_type = "faction"
				INV.payee_faction_uid = net
				INV.payee_name = get_faction_name(net)
			else
				var/obj/item/card/id/I = user.GetIdCard()
				if(!I || !I.associated_account_number)
					status_message = "Your ID has no bank account linked. Cannot issue a personal invoice."
					qdel(INV)
					return TRUE
				INV.payee_type = "personal"
				INV.payee_account_number = I.associated_account_number
				INV.payee_name = I.registered_name

			INV.name = "invoice #[INV.invoice_id] ([INV.payee_name])"
			var/issuer = user.real_name || "unknown"
			INV.set_content_unsafe("Invoice #[INV.invoice_id]",
				{"<b>INVOICE #[INV.invoice_id]</b><hr>
				<b>Payable to:</b> [INV.payee_name][INV.payee_type == "faction" ? " (faction account)" : ""]<br>
				<b>Amount:</b> [amount] credits<br>
				<b>For:</b> [purpose]<br>
				<b>Issued by:</b> [issuer]<hr>
				<i>Swipe an ID card or charge card on this invoice to pay it.</i>"})
			INV.update_icon()

			computer.nano_printer.stored_paper--
			user.put_in_hands(INV)
			status_message = "Invoice #[INV.invoice_id] printed: [amount] credits payable to [INV.payee_name]."
			log_game("[key_name(user)] printed invoice #[INV.invoice_id] ([amount] credits, payee: [INV.payee_name], type: [INV.payee_type]) at [computer].")
			return TRUE

		if("clear_status")
			status_message = ""
			return TRUE
