/*
 * Supply Beacon Terminal
 * Buy and sell commodity crates at Supply Beacon trade depots
 * (code/modules/overmap/supply_beacon.dm) -- prices are per-beacon and
 * per-commodity, drifting over time and moving with local supply/demand
 * (persistence_supply_beacons.dm), so hauling the same commodity between two
 * beacons at different prices is the actual point of the loop.
 *
 * Console/laptop only (usage_flags), never a PDA -- this is a bridge/ops
 * terminal, not something you carry in a pocket. Billing follows the exact
 * same faction/personal/crew 3-way split as Cargo Order/Cargo Exports
 * (cargo_order.dm, cargo_exports.dm) -- a purchase materializes its crate at
 * a delivery telepad in that same scope via persistence_telepad_deliver()
 * (persistence_cryo.dm), reusing the existing cargo telepad pipeline exactly
 * like a faction/personal/crew cargo order does, rather than a parallel
 * delivery mechanic.
 *
 * A beacon's full price list is only ever sent to the client once the
 * console's own ship is actually within one overmap tile of it
 * (supply_beacon_ship_in_range(), persistence_supply_beacons.dm) -- a beacon
 * outside range shows only its label/coordinates.
 */
/datum/computer_file/program/civilian/supplybeaconterminal
	filename = "supplybeacon"
	filedesc = "Supply Beacon Terminal"
	program_icon_state = "supply"
	program_key_icon_state = "purple_key"
	extended_desc = "Buy and sell commodity crates at Supply Beacon trade depots. Prices vary by beacon and drift over time -- hauling the same goods to a beacon paying more is the whole game."
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 4
	tgui_id = "SupplyBeaconTerminal"
	ui_auto_update = TRUE // keeps prices/balances/range live as the ship moves

	var/selected_beacon_id
	var/status_message = ""
	/// Explicit delivery-pad choice, same "only matters with >1 candidate"
	/// convention as Cargo Order's co.delivery_telepad / Cargo Exports'
	/// selected_export_telepad.
	var/obj/structure/machinery/telepad_cargo/selected_telepad

/datum/computer_file/program/civilian/supplybeaconterminal/ui_data(mob/user)
	var/list/data = initial_data()
	var/console_z = computer ? GET_Z(computer) : 0
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : null
	var/is_personal = computer && computer.personal_ckey
	var/is_crew = computer && computer.crew_tagged

	data["faction_uid"] = net
	data["faction_name"] = net ? get_faction_name(net) : null
	data["faction_balance"] = net ? get_faction_account_balance(net) : null

	data["is_personal"] = is_personal
	data["personal_owner_name"] = is_personal ? computer.personal_char_name : null
	if(is_personal)
		var/obj/item/card/id/viewer_id = user.GetIdCard()
		var/datum/money_account/viewer_acc = viewer_id?.associated_account_number ? SSeconomy.get_account(viewer_id.associated_account_number) : null
		data["personal_balance"] = viewer_acc ? viewer_acc.money : null

	data["is_crew"] = is_crew
	if(is_crew)
		var/datum/drydock_ship/crew_ship = _drydock_ship_at(console_z)
		data["crew_ship_name"] = crew_ship ? crew_ship.display_name() : null
		var/datum/money_account/crew_acc = (crew_ship && crew_ship.owner_account_number) ? SSeconomy.get_account(crew_ship.owner_account_number) : null
		data["crew_balance"] = crew_acc ? crew_acc.money : null

	data["commodities"] = list()
	for(var/key in GLOB.supply_beacon_commodities)
		var/list/commodity = GLOB.supply_beacon_commodities[key]
		data["commodities"] += list(list("key" = key, "name" = commodity["name"]))

	data["beacons"] = list()
	for(var/bid in SSsupply_beacons.beacons)
		var/obj/effect/overmap/supply_beacon/B = SSsupply_beacons.beacons[bid]
		if(QDELETED(B))
			continue
		var/in_range = supply_beacon_ship_in_range(console_z, B)
		var/list/entry = list(
			"beacon_id" = B.beacon_id,
			"notes" = B.notes,
			"x" = B.x,
			"y" = B.y,
			"in_range" = in_range,
		)
		if(in_range)
			var/list/prices = list()
			for(var/key in GLOB.supply_beacon_commodities)
				prices += list(list(
					"key" = key,
					"current_price" = B.commodity_prices[key],
					"previous_price" = B.commodity_previous_prices[key],
					"price_high" = B.commodity_price_high[key],
					"price_low" = B.commodity_price_low[key],
				))
			entry["prices"] = prices
		data["beacons"] += list(entry)

	data["selected_beacon_id"] = selected_beacon_id
	var/obj/effect/overmap/supply_beacon/selected = selected_beacon_id ? SSsupply_beacons.beacons["[selected_beacon_id]"] : null
	var/selected_in_range = (selected && !QDELETED(selected)) ? supply_beacon_ship_in_range(console_z, selected) : FALSE
	data["selected_in_range"] = selected_in_range

	var/source_key = get_supply_beacon_source_key(computer)
	data["cooldown_remaining"] = (selected && !QDELETED(selected) && source_key) ? supply_beacon_cooldown_remaining(source_key, selected.beacon_id) : 0

	// Delivery telepad choice -- identical 3-mode pattern to Cargo Order/Exports.
	data["telepad_choices"] = list()
	data["selected_telepad_ref"] = null
	var/list/candidate_pads = list()
	if(net)
		candidate_pads = persistence_find_cargo_telepads(net)
	else if(is_personal)
		candidate_pads = persistence_find_personal_cargo_telepads(computer.personal_ckey, computer.personal_char_name)
	else if(is_crew)
		var/datum/drydock_ship/crew_ship_for_pads = _drydock_ship_at(console_z)
		if(crew_ship_for_pads)
			candidate_pads = persistence_find_crew_cargo_telepads(crew_ship_for_pads.shuttle_id)
	data["telepad_choices"] = cargo_telepad_choice_data(candidate_pads, computer)
	if(length(data["telepad_choices"]) && selected_telepad && !QDELETED(selected_telepad) && (selected_telepad in candidate_pads))
		data["selected_telepad_ref"] = "\ref[selected_telepad]"

	data["status_message"] = status_message
	return data

/datum/computer_file/program/civilian/supplybeaconterminal/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return TRUE

	var/mob/user = usr

	switch(action)
		if("select_beacon")
			selected_beacon_id = text2num(params["beacon_id"])
			return TRUE

		//Pick which of the console's own-scope cargo telepads a purchase should
		//land on -- resolved the same 3-mode way as ui_data() above, so the
		//clicked ref can only ever match a pad already in THIS console's own
		//candidate set (never a different faction's/character's/ship's pad).
		if("select_telepad")
			var/target_ref = params["select_telepad"]
			selected_telepad = null
			if(target_ref)
				var/net = normalize_faction_uid(computer.persistent_network)
				var/list/candidate_pads = list()
				if(net)
					candidate_pads = persistence_find_cargo_telepads(net)
				else if(computer.personal_ckey)
					candidate_pads = persistence_find_personal_cargo_telepads(computer.personal_ckey, computer.personal_char_name)
				else if(computer.crew_tagged)
					var/datum/drydock_ship/crew_ship_for_select = _drydock_ship_at(GET_Z(computer))
					if(crew_ship_for_select)
						candidate_pads = persistence_find_crew_cargo_telepads(crew_ship_for_select.shuttle_id)
				for(var/obj/structure/machinery/telepad_cargo/pad in candidate_pads)
					if("\ref[pad]" == target_ref)
						selected_telepad = pad
						break
			return TRUE

		if("clear_message")
			status_message = null
			return TRUE

		if("buy")
			var/obj/effect/overmap/supply_beacon/B = selected_beacon_id ? SSsupply_beacons.beacons["[selected_beacon_id]"] : null
			if(!B || QDELETED(B))
				status_message = "Select a beacon first."
				return TRUE
			if(!computer || !supply_beacon_ship_in_range(GET_Z(computer), B))
				status_message = "Your ship must be adjacent to the beacon to trade."
				return TRUE
			var/commodity_key = params["commodity"]
			var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
			if(!commodity)
				status_message = "Unknown commodity."
				return TRUE
			var/amount = text2num(params["amount"])
			if(!amount || amount <= 0)
				status_message = "Enter a valid amount."
				return TRUE

			var/source_key = get_supply_beacon_source_key(computer)
			if(!source_key)
				status_message = "This terminal isn't linked to a faction, personal, or crew network."
				return TRUE
			var/cooldown = supply_beacon_cooldown_remaining(source_key, B.beacon_id)
			if(cooldown > 0)
				status_message = "This beacon is on cooldown for [DisplayTimeText(cooldown SECONDS)] more."
				return TRUE

			var/cost = B.commodity_prices[commodity_key] * amount
			var/net = normalize_faction_uid(computer.persistent_network)
			var/is_personal = computer.personal_ckey
			var/is_crew = computer.crew_tagged
			var/turf/telepad_turf
			var/datum/drydock_ship/crew_ship
			/// Who paid -- stamped onto the crate's label below (purely
			/// informational, same as a Cargo Order crate's "(order_id -
			/// ordered_by)" tag). Deliberately does NOT gate who can later
			/// SELL the crate -- ownership here is physical possession only,
			/// so a hijacked shipment can be sold by whoever's holding it.
			var/owner_label

			if(is_personal)
				var/obj/item/card/id/I = user.GetIdCard()
				var/datum/money_account/acc = I?.associated_account_number ? SSeconomy.get_account(I.associated_account_number) : null
				if(!acc)
					status_message = "No linked bank account found on your ID."
					return TRUE
				if(acc.money < cost)
					status_message = "Insufficient funds -- that would cost [cost] cr."
					return TRUE
				if(selected_telepad && !QDELETED(selected_telepad) && selected_telepad.accepts_cargo && selected_telepad.persistent_spawn && selected_telepad.z && selected_telepad.personal_ckey == computer.personal_ckey && selected_telepad.personal_char_name == computer.personal_char_name)
					telepad_turf = get_turf(selected_telepad)
				if(!telepad_turf)
					telepad_turf = persistence_find_personal_cargo_telepad(computer.personal_ckey, computer.personal_char_name)
				if(!telepad_turf)
					status_message = "No personally-tagged telepad found. Place and personally tag a cargo telepad nearby."
					return TRUE
				acc.adjust_money(-cost)
				owner_label = computer.personal_char_name
			else if(is_crew)
				crew_ship = _drydock_ship_at(GET_Z(computer))
				if(!crew_ship)
					status_message = "This console isn't aboard a deployed drydock ship."
					return TRUE
				var/datum/money_account/acc = crew_ship.owner_account_number ? SSeconomy.get_account(crew_ship.owner_account_number) : null
				if(!acc)
					status_message = "This ship has no linked owner account on file."
					return TRUE
				if(acc.money < cost)
					status_message = "Insufficient funds -- that would cost [cost] cr."
					return TRUE
				if(selected_telepad && !QDELETED(selected_telepad) && selected_telepad.accepts_cargo && selected_telepad.persistent_spawn && selected_telepad.z && selected_telepad.crew_tagged)
					var/datum/drydock_ship/pad_ship = _drydock_ship_at(selected_telepad.z)
					if(pad_ship == crew_ship)
						telepad_turf = get_turf(selected_telepad)
				if(!telepad_turf)
					telepad_turf = persistence_find_crew_cargo_telepad(crew_ship.shuttle_id)
				if(!telepad_turf)
					status_message = "No crew-tagged telepad found for [crew_ship.display_name()]."
					return TRUE
				acc.adjust_money(-cost)
				owner_label = crew_ship.display_name()
			else if(net)
				if(selected_telepad && !QDELETED(selected_telepad) && selected_telepad.accepts_cargo && selected_telepad.persistent_spawn && selected_telepad.z && normalize_faction_uid(selected_telepad.persistent_network) == net)
					telepad_turf = get_turf(selected_telepad)
				if(!telepad_turf)
					telepad_turf = persistence_find_cargo_telepad(net)
				if(!telepad_turf)
					status_message = "No faction telepad found for network '[net]'."
					return TRUE
				if(!faction_debit(net, cost, "Supply Beacon purchase (#[B.beacon_id])"))
					status_message = "[get_faction_name(net)]'s treasury can't cover that purchase."
					return TRUE
				owner_label = get_faction_name(net)
			else
				status_message = "This terminal isn't linked to a faction, personal, or crew network."
				return TRUE

			var/crate_type = commodity["crate_type"]
			var/obj/structure/closet/crate/supply_beacon/crate = new crate_type(telepad_turf)
			crate.amount = amount
			crate.refresh_label()
			// Ownership tag is a removable label, not a lock -- see
			// owner_label's own doc comment above. Same convention as a
			// Cargo Order crate (spawn_order_crate(), cargo.dm) and the hand
			// labeler (handlabeler.dm): name_unlabel captures the untagged
			// name so Remove Label can strip the tag later without losing
			// the commodity/amount identification underneath.
			crate.name_unlabel = crate.name
			crate.name = "[crate.name] ([owner_label])"
			crate.verbs += /atom/proc/remove_label
			persistence_telepad_deliver(list(crate), telepad_turf)

			B.apply_trade_impact(commodity_key, amount, TRUE)
			supply_beacon_set_cooldown(source_key, B.beacon_id)
			status_message = "Purchased [amount]x [commodity["name"]] for [cost] cr."
			log_game("[key_name(user)] bought [amount]x [commodity_key] from Supply Beacon #[B.beacon_id] for [cost] cr via Supply Beacon Terminal.")
			return TRUE

		if("sell")
			var/obj/effect/overmap/supply_beacon/B = selected_beacon_id ? SSsupply_beacons.beacons["[selected_beacon_id]"] : null
			if(!B || QDELETED(B))
				status_message = "Select a beacon first."
				return TRUE
			if(!computer || !supply_beacon_ship_in_range(GET_Z(computer), B))
				status_message = "Your ship must be adjacent to the beacon to trade."
				return TRUE
			var/commodity_key = params["commodity"]
			var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
			if(!commodity)
				status_message = "Unknown commodity."
				return TRUE
			var/amount = text2num(params["amount"])
			if(!amount || amount <= 0)
				status_message = "Enter a valid amount."
				return TRUE

			var/source_key = get_supply_beacon_source_key(computer)
			if(!source_key)
				status_message = "This terminal isn't linked to a faction, personal, or crew network."
				return TRUE
			var/cooldown = supply_beacon_cooldown_remaining(source_key, B.beacon_id)
			if(cooldown > 0)
				status_message = "This beacon is on cooldown for [DisplayTimeText(cooldown SECONDS)] more."
				return TRUE

			var/net = normalize_faction_uid(computer.persistent_network)
			var/is_personal = computer.personal_ckey
			var/is_crew = computer.crew_tagged

			var/list/candidate_pads = list()
			if(net)
				candidate_pads = persistence_find_cargo_telepads(net)
			else if(is_personal)
				candidate_pads = persistence_find_personal_cargo_telepads(computer.personal_ckey, computer.personal_char_name)
			else if(is_crew)
				var/datum/drydock_ship/crew_ship_for_pads = _drydock_ship_at(GET_Z(computer))
				if(crew_ship_for_pads)
					candidate_pads = persistence_find_crew_cargo_telepads(crew_ship_for_pads.shuttle_id)
			if(!length(candidate_pads))
				status_message = "No delivery-enabled telepad found in scope."
				return TRUE

			// Gather every matching crate sitting on any candidate pad's turf.
			var/list/found_crates = list()
			var/total_available = 0
			for(var/obj/structure/machinery/telepad_cargo/pad in candidate_pads)
				var/turf/pad_turf = get_turf(pad)
				if(!pad_turf)
					continue
				for(var/obj/structure/closet/crate/supply_beacon/crate in pad_turf)
					if(crate.commodity_key != commodity_key)
						continue
					found_crates += crate
					total_available += crate.amount

			if(total_available < amount)
				status_message = "Only [total_available]x [commodity["name"]] found on your telepad(s) -- need [amount]."
				return TRUE

			// Consume crates greedily until `amount` units are accounted for --
			// a fully-consumed crate is deleted, a partially-consumed one just
			// has its stack (and label) shrunk. Tracks every turf actually
			// touched so the send-off flourish below can hit each of them,
			// same as Cargo Exports' own export_now.
			var/remaining = amount
			var/list/touched_turfs = list()
			for(var/obj/structure/closet/crate/supply_beacon/crate in found_crates)
				if(remaining <= 0)
					break
				var/turf/crate_turf = get_turf(crate)
				if(crate_turf)
					touched_turfs |= crate_turf
				if(crate.amount <= remaining)
					remaining -= crate.amount
					qdel(crate)
				else
					crate.amount -= remaining
					crate.refresh_label()
					remaining = 0

			// Send-off feedback -- matches Cargo Exports' own export_now
			// exactly, so a Supply Beacon sale looks/sounds consistent with
			// every other way goods leave through a telepad.
			for(var/turf/touched in touched_turfs)
				spark(touched, 5, GLOB.alldirs)
				playsound(touched, 'sound/effects/phasein.ogg', 50, 1)
				new /obj/effect/portal/decorative/fading(touched)

			var/proceeds = B.commodity_prices[commodity_key] * amount

			if(is_personal)
				var/obj/item/card/id/I = user.GetIdCard()
				var/datum/money_account/acc = I?.associated_account_number ? SSeconomy.get_account(I.associated_account_number) : null
				if(!acc)
					status_message = "Sold [amount]x [commodity["name"]] for [proceeds] cr, but no linked bank account was found to credit."
				else
					acc.adjust_money(proceeds)
					status_message = "Sold [amount]x [commodity["name"]] for [proceeds] cr to your personal account."
			else if(is_crew)
				var/datum/drydock_ship/crew_ship = _drydock_ship_at(GET_Z(computer))
				var/datum/money_account/acc = (crew_ship && crew_ship.owner_account_number) ? SSeconomy.get_account(crew_ship.owner_account_number) : null
				if(!acc)
					status_message = "Sold [amount]x [commodity["name"]] for [proceeds] cr, but [crew_ship ? crew_ship.display_name() : "the ship"]'s owner account could not be found."
				else
					acc.adjust_money(proceeds)
					status_message = "Sold [amount]x [commodity["name"]] for [proceeds] cr to [crew_ship.display_name()]'s account."
			else
				faction_credit(net, proceeds, "Supply Beacon sale (#[B.beacon_id])")
				status_message = "Sold [amount]x [commodity["name"]] for [proceeds] cr to [get_faction_name(net)]."

			B.apply_trade_impact(commodity_key, amount, FALSE)
			supply_beacon_set_cooldown(source_key, B.beacon_id)
			log_game("[key_name(user)] sold [amount]x [commodity_key] to Supply Beacon #[B.beacon_id] for [proceeds] cr via Supply Beacon Terminal.")
			return TRUE
