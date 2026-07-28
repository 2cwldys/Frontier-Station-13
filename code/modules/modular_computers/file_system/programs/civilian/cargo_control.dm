/datum/computer_file/program/civilian/cargocontrol
	filename = "cargocontrol"
	filedesc = "Cargo Control"
	extended_desc = "Application to Control Cargo Orders"
	program_icon_state = "supply"
	program_key_icon_state = "yellow_key"
	size = 12
	requires_ntnet = TRUE
	available_on_ntnet = TRUE
	required_access_download = ACCESS_CARGO
	required_access_run = ACCESS_CARGO
	usage_flags = PROGRAM_LAPTOP | PROGRAM_CONSOLE | PROGRAM_TELESCREEN
	tgui_id = "CargoControl"

	var/page = "overview_main" //overview_main - Main Menu, overview_submitted - Submitted Order Overview, overview_approved - Approved Order Overview, settings - Settings, details - order details, bounties - centcom bounties
	var/status_message //A status message that can be displayed
	var/list/order_details = list() //Order Details for the order
	var/list/shipment_details = list() //Shipment Details for a selected shipment
	// persistent_network is now on the machine (computer.persistent_network) -- no per-program var

/datum/computer_file/program/civilian/cargocontrol/ui_data(mob/user)
	var/list/data = initial_data()

	post_signal("supply")

	//Send the page to display
	data["page"] = page
	//Send the status message
	data["status_message"] = status_message

	data["username"] = GetNameAndAssignmentFromId(user.GetIdCard())

	// Always present as lists -- the frontend .map()s these unguarded, and a
	// page/data desync (e.g. a runtime truncating this proc) must not crash
	// the whole window.
	data["order_list"] = list()
	data["shipment_list"] = list()

	// Faction instancing: this console only sees orders belonging to its own
	// network. Unshackled consoles see only the station's network-less queue.
	var/console_net = (computer && computer.persistent_network) ? normalize_faction_uid(computer.persistent_network) : ""

	var/list/submitted_orders = SScargo.get_orders_by_status("submitted", 1, null, console_net, TRUE)
	data["order_submitted_number"] = submitted_orders.len
	data["order_submitted_value"] = SScargo.get_orders_value_by_status("submitted", 1, console_net, TRUE)
	data["order_submitted_suppliers"] = SScargo.get_order_suppliers_by_status("submitted", 1, console_net, TRUE)
	data["order_submitted_shuttle_time"] = SScargo.get_pending_shipment_time("submitted", console_net, TRUE)
	data["order_submitted_shuttle_price"] = SScargo.get_pending_shipment_cost("submitted", console_net, TRUE)
	if(page == "overview_submitted")
		data["order_list"] = submitted_orders

	var/list/approved_orders = SScargo.get_orders_by_status("approved", 1, null, console_net, TRUE)
	data["order_approved_number"] = approved_orders.len
	data["order_approved_value"] = SScargo.get_orders_value_by_status("approved", 1, console_net, TRUE)
	data["order_approved_suppliers"] = SScargo.get_order_suppliers_by_status("approved", 1, console_net, TRUE)
	data["order_approved_shuttle_time"] = SScargo.get_pending_shipment_time("approved", console_net, TRUE)
	data["order_approved_shuttle_price"] = SScargo.get_pending_shipment_cost("approved", console_net, TRUE)
	if(page == "overview_approved")
		data["order_list"] = approved_orders

	var/list/shipped_orders = SScargo.get_orders_by_status("shipped", 1, null, console_net, TRUE)
	data["order_shipped_number"] = shipped_orders.len
	data["order_shipped_value"] = SScargo.get_orders_value_by_status("shipped", 1, console_net, TRUE)
	if(page == "overview_shipped")
		data["order_list"] = shipped_orders

	var/list/delivered_orders = SScargo.get_orders_by_status("delivered", 1, null, console_net, TRUE)
	data["order_delivered_number"] = shipped_orders.len
	data["order_delivered_value"] = SScargo.get_orders_value_by_status("delivered", 1, console_net, TRUE)
	if(page == "overview_delivered")
		data["order_list"] = delivered_orders

	if(length(order_details))
		data["order_details"] = order_details

	if(page == "overview_shipments")
		data["shipment_list"] = SScargo.get_shipment_list()

	if(page == "shipment_details")
		data["shipment_details"] = shipment_details

	data["cargo_money"] = SScargo.get_cargo_money()
	data["handling_fee"] = SScargo.get_handlingfee()
	data["bounties"] = SScargo.get_bounty_list()

	data["have_printer"] = !!computer.nano_printer

	//Shuttle Stuff
	var/datum/shuttle/autodock/ferry/supply/shuttle = SScargo.shuttle
	if(shuttle)
		data["shuttle_available"] = 1
		data["shuttle_has_arrive_time"] = shuttle.has_arrive_time()
		data["shuttle_eta_seconds"] = shuttle.eta_seconds()
		data["shuttle_can_launch"] = shuttle.can_launch()
		data["shuttle_can_cancel"] = shuttle.can_cancel()
		data["shuttle_can_force"] = shuttle.can_force()
		data["shuttle_at_station"] = shuttle.at_station()
		if(shuttle.active_docking_controller)
			data["shuttle_docking_status"] = shuttle.active_docking_controller.get_docking_status()
		else
			data["shuttle_docking_status"] = "error"
	else
		data["shuttle_available"] = 0

	return data

/datum/computer_file/program/civilian/cargocontrol/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return TRUE

	var/obj/item/card/id/I = usr.GetIdCard()

	// Faction instancing: order actions only apply to orders belonging to
	// this console's network (empty = the station's network-less queue).
	var/console_net = (computer && computer.persistent_network) ? normalize_faction_uid(computer.persistent_network) : ""

	// No top-level shuttle guard here: only the three shuttle_* actions need
	// SScargo.shuttle to exist. Maps without a supply shuttle must still be
	// able to switch pages, approve/reject orders, and change settings.
	switch(action)
		//Page switch between main, submitted, approved and settings
		if("page")
			switch(params["page"])
				if("overview_main")
					page = "overview_main" //Main overview page with links to the different sub overview pages - submitted, approved, shipped
				if("overview_submitted")
					page = "overview_submitted" //Overview page listing the orders that have been submitted with options to view them, approve them and reject them
				if("overview_approved")
					page = "overview_approved" //Overview page listing the current shuttle price and time as well as orders that have been approved, with options to view the details
				if("overview_shipped")
					page = "overview_shipped" //Overview page listing the orders that have been shipped to the station but not delivered
				if("overview_delivered")
					page = "overview_delivered" //Overview page listing the orders that have been delivered
				if("overview_shipments") //Overview of the shipments to / from the station
					page = "overview_shipments"
				if("settings")
					page = "settings" //Settings page that allows to tweak various settings such as the cargo handling fee
				if("bounties")
					page = "bounties"
				if("exports")
					page = "exports" //Faction export page -- sell items at the faction telepad for faction credits
				// (no else -- unknown pages fall through without changing; the switch handles the default)
			return TRUE

		//Approve a order
		if("order_approve")
			var/datum/cargo_order/co = SScargo.get_order_by_id(text2num(params["order_approve"]))
			if(co && !SScargo.order_network_matches(co, console_net))
				return TRUE
			if(co)
				var/message = co.set_approved(GetNameAndAssignmentFromId(I), usr.character_id)
				if(message)
					status_message = message
				// Tag order for faction telepad delivery if this console has a network configured.
				// Never overwrite a personal order's routing -- it already paid at
				// submission time, and re-tagging it here would misroute it into
				// deliver_faction_order() below for a second (faction) charge.
				if(computer && computer.persistent_network && !co.delivery_network && !co.personal_ckey)
					co.delivery_network = computer.persistent_network
				// Faction orders deliver instantly via the telepad -- no supply
				// shuttle needed (shuttle-less maps have no other delivery path).
				if(co.delivery_network && co.status == "approved")
					if(SScargo.deliver_faction_order(co))
						status_message = "Order [co.order_id] approved and delivered to the faction telepad."
					else if(co.status == "rejected")
						status_message = "Order [co.order_id] rejected: the faction account could not cover [co.price] credits."
					else
						status_message = "Order [co.order_id] approved, but no delivery-enabled telepad was found for '[co.delivery_network]'."
				// Personal orders (already paid at submission) deliver instantly
				// via the character's own tagged telepad the same way.
				else if(co.personal_ckey && co.status == "approved")
					if(SScargo.deliver_personal_order(co))
						status_message = "Order [co.order_id] approved and delivered to [co.personal_char_name]'s personal telepad."
					else
						status_message = "Order [co.order_id] approved, but no delivery-enabled personal telepad was found for [co.personal_char_name]."
			return TRUE

		//Reject a order
		if("order_reject")
			var/datum/cargo_order/co = SScargo.get_order_by_id(text2num(params["order_reject"]))
			if(co && !SScargo.order_network_matches(co, console_net))
				return TRUE
			if(co)
				var/message = co.set_rejected()
				if(message)
					status_message = message
			return TRUE

		// Configure faction supply network (admin only)
		if("set_supply_network")
			if(!check_rights(R_ADMIN, 0, usr))
				status_message = "Insufficient permissions to configure supply network."
				return TRUE
			var/new_net = params["network"]
			computer.persistent_network = (new_net && new_net != "") ? normalize_faction_uid(new_net) : ""
			status_message = computer.persistent_network ? "Supply network set to '[computer.persistent_network]'. Approved orders will be routed to faction telepads." : "Supply network cleared. Orders will use the supply shuttle."
			return TRUE

		// Export items at the faction telepad → credit faction account
		if("export_faction")
			var/exp_net = console_net
			if(!exp_net)
				status_message = "This console is not linked to a faction network."
				return TRUE
			var/turf/exp_turf = persistence_find_cargo_telepad(exp_net)
			if(!exp_turf)
				status_message = "No faction telepad found for network '[exp_net]'."
				return TRUE

			// Reset all export datum totals before scanning
			for(var/datum/export/E in SScargo.exports_list)
				E.export_end()

			// Process every movable on the telepad turf (skip machinery)
			for(var/atom/movable/A in exp_turf)
				if(istype(A, /obj/structure/machinery)) continue
				SScargo.export_item_and_contents(A)

			// Collect results
			var/exp_total = 0
			var/list/exp_lines = list()
			for(var/datum/export/E in SScargo.exports_list)
				if(E.total_cost <= 0) continue
				exp_lines += "[E.unit_name]: [E.total_amount] units -- [E.total_cost] cr"
				exp_total += E.total_cost
				E.export_end()  // reset for next run

			if(!exp_total)
				status_message = "No exportable items found at the faction telepad."
				return TRUE

			// Taxed if this telepad falls inside a DIFFERENT faction's beacon
			// territory -- exempt (no-op) when it's this faction's own
			// claimed territory, the common case.
			var/taxed_total = apply_cargo_territory_tax(GET_Z(exp_turf), exp_total, FALSE, exp_net, usr, "Export sale via cargo console by [usr.ckey] -- territory tax")
			faction_credit(exp_net, taxed_total, "Export sale via cargo console by [usr.ckey]")
			var/exp_summary = exp_lines.len ? jointext(exp_lines, "; ") : "unknown items"
			status_message = "Exported for [exp_total] cr: [exp_summary]. Credited [taxed_total] cr to [get_faction_name(exp_net)][taxed_total < exp_total ? " (after territory tax)" : ""]."
			log_game("[usr.ckey] exported [exp_total] cr of goods to faction [exp_net] via cargo console (credited [taxed_total]).")
			return TRUE

		//Send shuttle
		if("shuttle_send")
			if(!SScargo.shuttle)
				status_message = "No supply shuttle is available on this installation."
				return TRUE
			var/message = SScargo.shuttle_call(GetNameAndAssignmentFromId(I))
			if(message)
				status_message = message
			return TRUE

		//Cancel shuttle
		if("shuttle_cancel")
			if(!SScargo.shuttle)
				status_message = "No supply shuttle is available on this installation."
				return TRUE
			var/message = SScargo.shuttle_cancel()
			if(message)
				status_message = message
			return TRUE

		//Force shuttle
		if("shuttle_force")
			if(!SScargo.shuttle)
				status_message = "No supply shuttle is available on this installation."
				return TRUE
			var/message = SScargo.shuttle_force()
			if(message)
				status_message = message
			return TRUE

		//Clear Status Message
		if("clear_message")
			status_message = null
			return TRUE

		//Change the handling fee
		if("handling_fee")
			var/handling_fee = sanitize(input(usr, "Handling Fee:", "Set the new handling fee?", SScargo.get_handlingfee()) as null|text)
			status_message = SScargo.set_handlingfee(text2num(handling_fee))
			return TRUE

		//Claim a bounty
		if("claim_bounty")
			for(var/datum/bounty/b in SScargo.bounties_list)
				if(b.name == params["claim_bounty"])
					if(b.claim())
						status_message = "Bounty for [b.name] claimed successfully"
						return TRUE
					else
						status_message = "Could not claim Bounty for [b.name]"
					return

		if("order_details")
			var/datum/cargo_order/co = SScargo.get_order_by_id(text2num(params["order_details"]))
			if(!co || !SScargo.order_network_matches(co, console_net))
				return TRUE
			order_details = co.get_list()
			return TRUE

		//Print functions
		if("order_print")
			//Get the order
			var/datum/cargo_order/co = SScargo.get_order_by_id(text2num(params["order_print"]))
			if(co && !SScargo.order_network_matches(co, console_net))
				return TRUE
			if(co && computer.nano_printer)
				if(!computer.nano_printer.print_text(co.get_report_invoice(),"Order Invoice #[co.order_id]"))
					to_chat(usr, SPAN_WARNING("Hardware error: Printer was unable to print the file. It may be out of paper."))
					return
				else
					computer.visible_message(SPAN_NOTICE("\The [computer] prints out paper."))
		if("shipment_print")
			var/datum/cargo_shipment/cs = SScargo.get_shipment_by_id(text2num(params["shipment_print"]))
			if(cs?.completed && computer?.nano_printer)
				var/obj/item/paper/P = computer.nano_printer.print_text(cs.get_invoice(),"Shipment Invoice #[cs.shipment_num]")
				if(!P)
					to_chat(usr, SPAN_WARNING("Hardware error: Printer was unable to print the file. It may be out of paper."))
					return
				else
					//stamp the paper
					var/image/stampoverlay = image('icons/obj/bureaucracy.dmi')
					stampoverlay.icon_state = "paper_stamp-cent"
					if(!P.stamped)
						P.stamped = new
					P.stamped += /obj/item/stamp
					P.AddOverlays(stampoverlay)
					P.stamps += "<HR><i>This paper has been stamped by the Shipping Server.</i>"
					computer.visible_message(SPAN_NOTICE("\The [computer] prints out paper."))
		if("bounty_print")
			if(computer && computer.nano_printer)
				var/text = ""
				text += "<center>"
				text += "<H3>SCC Bounty requisition manifest</H3>"
				text += "<table border=1 cellspacing=0 cellpadding=3 style='border: 1px solid black;'>"
				text += "</td><tr><td><img src = scclogo_small.png><td><font size = \"1\">Manifest of requisition requests for the operations department.</font><BR><font size = \"1\">Manifest version: [worlddate2text()] [worldtime2text()]</font>"
				text += "</td></tr></table><BR>"
				text += "<table border=1 cellspacing=0 cellpadding=3 style='border: 1px solid black;'>"
				for(var/datum/bounty/B in SScargo.bounties_list)
					if(B.claimed)
						continue
					text += "</td><tr><td><font size=\"4\"><B>[B.name]</B></font><BR><font size = \"1\">[B.description]</font><BR><BR>Requisitioned: <B>[B.completion_string()]</B><BR>Payment: [B.reward_string()]<BR>"
				text += "</td></tr></table><BR>"
				text += "<font size = \"1\">"
				text += "<table border=1 cellspacing=0 cellpadding=3 style='border: 1px solid black;'>"
				text += "</td><tr><td>Powered by Orion Express logistics software.<BR><center><I>Faster than light.</I></center><td><img src = orionlogo_small.png>"
				text += "</td></tr></table>"
				text += "<BR><I>This document has been automatically generated based off of current inventory statistics. Under no circumstances should the requisition count or the resulting payment be adjusted by personnel. Payment is automatically credited to the operations department and not towards any individual. Requisitions above the requested count receive no additional payment above the listed values. This manifest is a public read-only version, and can be shared. It does not need to be returned.</I>"
				text += "</font>"
				text += "</center><BR>"
				text += "<font size = \"1\">"
				text += "Generated by OE.SCC.ReqApp 2.4<BR>Manifest form version 5.87, Hash:<BR>456E6A6F79696E6720796F7572207061706572776F726B3F"
				text += "</font>"
				if(!computer.nano_printer.print_text(text,"paper - Bounties"))
					to_chat(usr, SPAN_WARNING("Hardware error: Printer was unable to print the file. It may be out of paper."))
					return
				else
					computer.visible_message(SPAN_NOTICE("\The [computer] prints out paper."))

/datum/computer_file/program/civilian/cargocontrol/proc/post_signal(var/command) //Old code right here - Used to send a refresh command to the status screens incargo
	var/datum/radio_frequency/frequency = SSradio.return_frequency(1435)

	if(!frequency)
		return

	var/datum/signal/status_signal = new
	status_signal.source = src
	status_signal.transmission_method = TRANSMISSION_RADIO
	status_signal.data["command"] = command

	frequency.post_signal(src, status_signal)
