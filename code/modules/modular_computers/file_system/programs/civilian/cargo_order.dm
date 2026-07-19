/datum/computer_file/program/civilian/cargoorder
	filename = "cargoorder"
	filedesc = "Cargo Order"
	extended_desc = "Application to Order Items from Cargo."
	program_icon_state = "request"
	program_key_icon_state = "yellow_key"
	size = 10
	requires_ntnet = TRUE
	available_on_ntnet = TRUE
	usage_flags = PROGRAM_ALL
	tgui_id = "CargoOrder"
	ui_auto_update = TRUE  // keeps faction balance live

	var/page = "main" //main - Main Menu, order - Order Page, item_details - Item Details Page, tracking - Tracking Page
	var/selected_category = null // Category that is currently selected
	var/selected_item = "" // Path of the currently selected item
	var/datum/cargo_order/co
	var/status_message //Status Message to be displayed to the user
	var/user_tracking_id = 0 //Tracking id of the user
	var/user_tracking_code = 0 //Tracking Code of the user

/// TRUE if this console is faction-shackled AND its Z-level has an operational
/// piracy beacon -- gates the syndicate uplink terminal cargo item.
/datum/computer_file/program/civilian/cargoorder/proc/can_order_syndicate_uplink()
	if(!computer || !computer.persistent_network)
		return FALSE
	return piracy_beacon_active_on_z(GET_Z(computer))

/datum/computer_file/program/civilian/cargoorder/ui_data(mob/user)	//Check if a cargo order exists. If not create a new one
	if(!co)
		var/datum/cargo_order/crord = new
		co = crord

	var/list/data = initial_data()

	// Faction balance -- show when computer is linked to a faction
	var/co_net = computer ? normalize_faction_uid(computer.persistent_network) : null
	data["faction_network"] = co_net
	data["faction_name"]    = co_net ? get_faction_name(co_net) : null
	data["faction_balance"] = co_net ? get_faction_account_balance(co_net) : null

	// Personal balance -- mutually exclusive with faction mode, mirrors
	// Cargo Exports' own display (cargo_exports.dm). Orders placed from a
	// personally-tagged console are paid from this account at submission.
	var/is_personal = computer && computer.personal_ckey
	data["is_personal"]         = is_personal
	data["personal_owner_name"] = is_personal ? computer.personal_char_name : null
	if(is_personal)
		var/obj/item/card/id/viewer_id = user.GetIdCard()
		var/datum/money_account/viewer_acc = viewer_id?.associated_account_number ? SSeconomy.get_account(viewer_id.associated_account_number) : null
		data["personal_balance"] = viewer_acc ? viewer_acc.money : null
		// Reference-only, same as Cargo Exports -- the operator's own faction
		// balance if they belong to one, even though this console won't bill it.
		var/viewer_uid = (viewer_id && viewer_id.employer_faction) ? normalize_faction_uid(viewer_id.employer_faction) : null
		data["operator_faction_name"]    = viewer_uid ? get_faction_name(viewer_uid) : null
		data["operator_faction_balance"] = viewer_uid ? get_faction_account_balance(viewer_uid) : null

	// Crew balance -- mutually exclusive with faction/personal mode. Orders
	// placed from a crew-tagged console bill the SHIP OWNER's account (not
	// the operator's own), resolved via _drydock_ship_at() on this console's
	// current Z rather than a stored identity -- see deliver_crew_order()
	// (cargo.dm).
	var/is_crew = computer && computer.crew_tagged
	data["is_crew"] = is_crew
	if(is_crew)
		var/datum/drydock_ship/crew_ship = _drydock_ship_at(GET_Z(computer))
		data["crew_ship_name"] = crew_ship ? crew_ship.display_name() : null
		var/datum/money_account/crew_acc = (crew_ship && crew_ship.owner_account_number) ? SSeconomy.get_account(crew_ship.owner_account_number) : null
		data["crew_balance"] = crew_acc ? crew_acc.money : null

	// Delivery telepad choice -- only surfaced when the faction has more than
	// one delivery-enabled cargo pad (see persistence_find_cargo_telepads()).
	// A single (or no) match behaves exactly as before -- no selector shown.
	data["telepad_choices"] = list()
	data["selected_telepad_ref"] = null
	if(co_net)
		var/list/telepads = persistence_find_cargo_telepads(co_net)
		if(length(telepads) > 1)
			// List the closest pad to the ordering console/PDA first. Same-Z
			// candidates (real tile distance) always outrank cross-Z ones (only
			// comparable via overmap sector distance) -- +10000 offset keeps the
			// two tiers from ever interleaving. Mirrors the sector-adjacency
			// convention used by the drydock/faction proximity checks.
			var/turf/console_turf = get_turf(computer)
			var/console_z = GET_Z(computer)
			var/obj/effect/overmap/visitable/console_sector = console_z ? GLOB.map_sectors["[console_z]"] : null
			var/list/pad_distances = list()
			for(var/obj/structure/machinery/telepad_cargo/pad in telepads)
				var/turf/pad_turf = get_turf(pad)
				var/dist = 99999
				if(pad_turf && console_turf && pad_turf.z == console_z)
					dist = get_dist(console_turf, pad_turf)
				else if(pad_turf)
					var/obj/effect/overmap/visitable/pad_sector = GLOB.map_sectors["[pad_turf.z]"]
					if(console_sector && istype(pad_sector))
						dist = 10000 + get_dist(console_sector, pad_sector)
				pad_distances[pad] = dist
			sortTim(pad_distances, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
			for(var/obj/structure/machinery/telepad_cargo/pad in pad_distances)
				var/area/A = get_area(pad)
				data["telepad_choices"] += list(list(
					"ref" = "\ref[pad]",
					"area_name" = A ? A.name : "Unknown Area"
				))
			if(co.delivery_telepad && !QDELETED(co.delivery_telepad) && (co.delivery_telepad in telepads))
				data["selected_telepad_ref"] = "\ref[co.delivery_telepad]"

	//Pass the ID Data
	data["username"] = GetNameAndAssignmentFromId(user.GetIdCard())

	//Pass the list of all ordered items and the order value
	data["order_items"] = co.get_item_list()
	data["order_value"] = co.get_value(0)
	data["order_item_count"] = co.get_item_count()

	if(!selected_category)
		selected_category = SScargo.get_default_category()

	//Pass Data for Main page
	if(page == "main")
		//Pass all available categories and the selected category
		data["cargo_categories"] = SScargo.get_category_list()
		data["selected_category"] = selected_category

		//Pass a list of items in the selected category
		data["category_items"] = SScargo.get_items_for_category(selected_category)
		if(!can_order_syndicate_uplink())
			for(var/list/entry in data["category_items"])
				var/singleton/cargo_item/ci = SScargo.cargo_items[entry["name"]]
				if(ci?.requires_piracy_beacon)
					data["category_items"] -= entry

	else if (page == "tracking")
		data["tracking_id"] = user_tracking_id
		data["tracking_code"] = user_tracking_code
		//If no tracking id / code is entered the page the enter them should be displayed
		if(!user_tracking_id || !user_tracking_code)
			data["tracking_status"] = "Incomplete Input"
		//If we have a tracking id / code, then try to find a order with mathing details
		else if(user_tracking_id && user_tracking_code)
			//Now, lets try to find a order with a matching id
			var/datum/cargo_order/co = SScargo.get_order_by_id(user_tracking_id)
			if(co)
				if(co.tracking_code == user_tracking_code)
					data["tracking_status"] = "Success"
					data["tracked_order"] = co.get_list()
					data["tracked_order_report"] = co.get_report_invoice()
				else
					data["tracking_status"] = "Invalid Tracking Code"
			else
				data["tracking_status"] = "Invalid Order"

	//Pass the current page
	data["page"] = page

	//Pass the status message along
	data["status_message"] = status_message

	data["handling_fee"] = SScargo.get_handlingfee_cost(co.get_value(2))
	data["crate_fee"] = SScargo.get_cratefee()

	return data

/datum/computer_file/program/civilian/cargoorder/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	var/obj/item/card/id/I = usr.GetIdCard()

	switch(action)
		//Send the order to cargo
		if("submit_order")
			if(!co.items.len)
				return TRUE //Only submit the order if there are items in it

			if(!I)
				status_message = "Unable to submit order. ID could not be located."
				return TRUE

			var/reason = sanitize(input(usr, "Reason:", "Why do you require this item?", "") as null|text)
			if(!reason)
				status_message = "Unable to submit order. No reason supplied."
				return TRUE

			// Personal orders are paid NOW, while the ordering character's own
			// ID card is physically in hand -- there's no reliable way to
			// resolve an arbitrary (ckey, char_name)'s bank account later at
			// delivery time the way a faction account always can be (a
			// faction always exists in GLOB.persistence_faction_cache; an
			// offline character's account does not). Refuse the whole
			// submission if payment fails -- never enters the approval queue.
			if(computer && computer.personal_ckey)
				if(!I.associated_account_number)
					status_message = "Unable to submit order. No linked bank account on your ID."
					return TRUE
				var/transfer_error = SSeconomy.transfer_money(I.associated_account_number, SScargo.supply_account.account_number, "Cargo order", "Cargo Order Console", co.get_value(0))
				if(transfer_error)
					status_message = "Unable to submit order. [transfer_error]"
					return TRUE

			// Crew orders bill the SHIP OWNER's account, not whoever's
			// physically holding this ID card -- deferred to delivery time
			// (deliver_crew_order(), cargo.dm), since owner_account_number is
			// a stable identifier that resolves even while the owner is
			// offline. Only the ship reference itself needs to be captured
			// now, while this console still knows what Z it's on.
			var/datum/drydock_ship/crew_ship
			if(computer && computer.crew_tagged)
				crew_ship = _drydock_ship_at(GET_Z(computer))
				if(!crew_ship)
					status_message = "Unable to submit order. This console isn't aboard a deployed drydock ship."
					return TRUE
				if(!crew_ship.owner_account_number)
					status_message = "Unable to submit order. This ship has no linked owner account on file."
					return TRUE

			co.set_submitted(GetNameAndAssignmentFromId(I), usr.character_id, reason)
			// Faction instancing: the submitting console's network owns the
			// order from birth. Null for unshackled (station) consoles.
			co.delivery_network = (computer && computer.persistent_network) ? normalize_faction_uid(computer.persistent_network) : null

			if(computer && computer.personal_ckey)
				// Personal orders are synchronous and self-contained -- no
				// cargo officer needed (they're already paid, and the console
				// is personally locked to begin with, so there's nobody else
				// who could have submitted it). Approve and attempt delivery
				// in this same call instead of waiting in the shared queue --
				// order_network_matches() (cargo.dm) also hides it from every
				// console's queue entirely, so this is the only chance for
				// synchronous feedback; a delivery that can't resolve a
				// telepad right now still gets picked up by the ordinary
				// automatic per-tick retry.
				co.personal_ckey = computer.personal_ckey
				co.personal_char_name = computer.personal_char_name
				co.set_paid(computer.personal_char_name, 0, "Personal")
				co.set_approved(computer.personal_char_name, usr.character_id)
				if(SScargo.deliver_personal_order(co))
					status_message = "Order submitted, paid, and delivered instantly. Order ID: [co.order_id] Tracking code: [co.get_tracking_code()]"
				else
					status_message = "Order submitted and paid. No delivery-enabled personal telepad found right now -- it will deliver automatically once one is available. Order ID: [co.order_id] Tracking code: [co.get_tracking_code()]"
			else if(computer && computer.crew_tagged)
				// Same synchronous/self-contained reasoning as personal mode
				// above (only this ship's crew can even reach this console),
				// but payment itself is deferred into deliver_crew_order() --
				// see its own docstring for why crew mode can safely bill at
				// delivery time instead of pre-paying like personal mode must.
				co.crew_shuttle_id = crew_ship.shuttle_id
				co.set_approved(GetNameAndAssignmentFromId(I), usr.character_id)
				if(SScargo.deliver_crew_order(co))
					status_message = "Order submitted and delivered instantly, billed to [crew_ship.display_name()]'s account. Order ID: [co.order_id] Tracking code: [co.get_tracking_code()]"
				else
					status_message = "Order submitted. No delivery-enabled crew telepad found right now -- it will deliver (and bill the ship's account) automatically once one is available. Order ID: [co.order_id] Tracking code: [co.get_tracking_code()]"
			else
				status_message = "Order submitted successfully. Order ID: [co.order_id] Tracking code: [co.get_tracking_code()]"

			co = null
			return TRUE

		//Add item to the order list
		if("add_item")
			var/datum/cargo_order_item/coi = new
			var/singleton/cargo_item/ci = SScargo.cargo_items[params["add_item"]]
			if(ci?.requires_piracy_beacon && !can_order_syndicate_uplink())
				status_message = "Unable to locate item in sales database - Internal Error 602."
				LOG_DEBUG("Cargo Order: Warning - Attempted to order piracy-beacon-gated item [ci.name] without an eligible console.")
				qdel(coi)
				return TRUE
			if(ci)
				coi.ci = ci
				coi.calculate_price()
				if(coi.price > 0)
					status_message = co.add_item(coi)
				else
					status_message = "Unable to add item [text2num(params["add_item"])] - Internal Error 601."
					LOG_DEBUG("Cargo Order: Warning - Attempted to order item [coi.ci.name] with invalid purchase price")
					qdel(coi)
			else
				status_message = "Unable to locate item in sales database - Internal Error 602."
				LOG_DEBUG("Cargo Order: Warning - Attempted to order item with non-existant id: [params["add_item"]]")
				qdel(coi)
			return TRUE

		//Remove item from the order list
		if("remove_item")
			status_message = co.remove_item(text2num(params["remove_item"]))
			return TRUE

		//Clear the items in the order list
		if("clear_order")
			status_message = "Order Cleared"
			qdel(co)
			co = new
			return TRUE

		if("page")
			page = params["page"]
			return TRUE

		//Tracking Stuff
		if("trackingid")
			var/trackingid = text2num(sanitize(input(usr, "Order ID:", "ID of the Order that you want to track", "") as null|text))
			if(trackingid)
				user_tracking_id = trackingid
			return TRUE

		if("trackingcode")
			var/trackingcode = text2num(sanitize(input(usr, "Tracking Code:", "Tracking Code of the Order that you want to track", "") as null|text))
			if(trackingcode)
				user_tracking_code = trackingcode
			return TRUE

		//Change the displayed item category
		if("select_category")
			selected_category = params["select_category"]
			return TRUE

		//Pick which of the faction's cargo telepads this order should land on
		if("select_telepad")
			var/co_net = computer ? normalize_faction_uid(computer.persistent_network) : null
			var/target_ref = params["select_telepad"]
			co.delivery_telepad = null
			if(co_net && target_ref)
				for(var/obj/structure/machinery/telepad_cargo/pad in persistence_find_cargo_telepads(co_net))
					if("\ref[pad]" == target_ref)
						co.delivery_telepad = pad
						break
			return TRUE

		if("clear_message")
			status_message = null
			return TRUE
