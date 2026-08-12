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
	/// Staged purchase lines, commodity_key -> amount. The trade cooldown is
	/// per (source, beacon) and fires on ANY completed trade, so buying one
	/// commodity at a time burned a full 30-minute lockout per item. Staging
	/// here and checking out once makes an arbitrarily large order a single
	/// transaction: one charge, one cooldown.
	var/list/cart = list()
	/// Same as `cart` above, but for staged SELL lines -- see _checkout_sale().
	var/list/sell_cart = list()

/**
 * The console's own-scope cargo telepads (faction/personal/crew, same
 * 3-way lookup Cargo Order/Cargo Exports use), filtered down to ONLY those
 * on this console's OWN Z-level.
 *
 * That same-Z restriction is deliberate and load-bearing: without it, a
 * purchase could materialize its crate on a DIFFERENT telepad the same
 * faction/character/ship owns elsewhere in the galaxy -- e.g. one already
 * conveniently parked at another Supply Beacon -- letting it be sold again
 * instantly through a different console with zero actual hauling. That
 * defeats the entire point of the trading loop (you have to physically fly
 * the goods somewhere) and makes the 30-minute cooldown meaningless, since
 * the "haul" step never has to happen at all.
 */
/datum/computer_file/program/civilian/supplybeaconterminal/proc/get_candidate_pads()
	if(!computer)
		return list()
	var/net = normalize_faction_uid(computer.persistent_network)
	var/list/candidate_pads = list()
	if(net)
		candidate_pads = persistence_find_cargo_telepads(net)
	else if(computer.personal_ckey)
		candidate_pads = persistence_find_personal_cargo_telepads(computer.personal_ckey, computer.personal_char_name)
	else if(computer.crew_tagged)
		var/datum/drydock_ship/crew_ship = _drydock_ship_at(GET_Z(computer))
		if(crew_ship)
			candidate_pads = persistence_find_crew_cargo_telepads(crew_ship.shuttle_id)

	var/console_z = GET_Z(computer)
	var/list/same_z_pads = list()
	for(var/obj/structure/machinery/telepad_cargo/pad in candidate_pads)
		if(GET_Z(pad) == console_z)
			same_z_pads += pad
	return same_z_pads

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

	// Delivery telepad choice -- same-Z-only (see get_candidate_pads()).
	data["telepad_choices"] = list()
	data["selected_telepad_ref"] = null
	var/list/candidate_pads = get_candidate_pads()
	data["telepad_choices"] = cargo_telepad_choice_data(candidate_pads, computer)
	if(length(data["telepad_choices"]) && selected_telepad && !QDELETED(selected_telepad) && (selected_telepad in candidate_pads))
		data["selected_telepad_ref"] = "\ref[selected_telepad]"

	// Cart lines rendered with current beacon pricing (if a beacon is
	// selected and in range) so the TGUI can show a running total without
	// re-deriving prices client-side.
	data["cart"] = list()
	data["cart_total"] = 0
	for(var/commodity_key in cart)
		var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
		if(!commodity)
			continue
		var/line_qty = cart[commodity_key]
		var/unit_price = (selected && !QDELETED(selected)) ? selected.commodity_prices[commodity_key] : 0
		data["cart"] += list(list(
			"key" = commodity_key,
			"name" = commodity["name"],
			"amount" = line_qty,
			"line_total" = unit_price * line_qty,
		))
		data["cart_total"] += unit_price * line_qty

	data["sell_cart"] = list()
	data["sell_cart_total"] = 0
	for(var/commodity_key in sell_cart)
		var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
		if(!commodity)
			continue
		var/line_qty = sell_cart[commodity_key]
		var/unit_price = (selected && !QDELETED(selected)) ? selected.commodity_prices[commodity_key] : 0
		data["sell_cart"] += list(list(
			"key" = commodity_key,
			"name" = commodity["name"],
			"amount" = line_qty,
			"line_total" = unit_price * line_qty,
		))
		data["sell_cart_total"] += unit_price * line_qty

	data["status_message"] = status_message
	return data

/**
 * Charges ONCE for `order` (commodity_key -> amount), spawns every crate on
 * the resolved delivery pad, applies per-commodity price impact, and sets the
 * trade cooldown a single time.
 *
 * Shared by the single-item Buy button and multi-line cart checkout so the two
 * behave identically -- the whole point of the cart is that N line items cost
 * ONE cooldown rather than N. Billing-mode resolution (personal / crew /
 * faction) mirrors the same 3-way branch get_supply_beacon_source_key() uses,
 * so "who pays" always matches "who the cooldown is keyed to".
 */
/datum/computer_file/program/civilian/supplybeaconterminal/proc/_checkout_purchase(mob/user, obj/effect/overmap/supply_beacon/B, source_key, list/order)
	if(!length(order))
		status_message = "Nothing to purchase."
		return TRUE

	var/total_cost = 0
	for(var/commodity_key in order)
		var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
		if(!commodity)
			status_message = "Unknown commodity in order."
			return TRUE
		total_cost += B.commodity_prices[commodity_key] * order[commodity_key]

	// Same-Z-only (get_candidate_pads()) -- crates MUST materialize on THIS
	// console's own ship/station, never a different telepad the same
	// faction/character/ship happens to own elsewhere.
	var/list/candidate_pads = get_candidate_pads()
	var/obj/structure/machinery/telepad_cargo/pad = (selected_telepad in candidate_pads) ? selected_telepad : (length(candidate_pads) ? candidate_pads[1] : null)
	var/turf/telepad_turf = pad ? get_turf(pad) : null

	var/net = normalize_faction_uid(computer.persistent_network)
	var/is_personal = computer.personal_ckey
	var/is_crew = computer.crew_tagged
	/// Who paid -- stamped onto each crate's label (purely informational, same
	/// as a Cargo Order crate's "(order_id - ordered_by)" tag). Deliberately
	/// does NOT gate who can later SELL the crate -- ownership here is
	/// physical possession only, so a hijacked shipment can be sold by whoever
	/// is holding it.
	var/owner_label

	if(is_personal)
		var/obj/item/card/id/I = user.GetIdCard()
		var/datum/money_account/acc = I?.associated_account_number ? SSeconomy.get_account(I.associated_account_number) : null
		if(!acc)
			status_message = "No linked bank account found on your ID."
			return TRUE
		if(acc.money < total_cost)
			status_message = "Insufficient funds -- that would cost [total_cost] cr."
			return TRUE
		if(!telepad_turf)
			status_message = "No personally-tagged telepad found on this ship/station. Place and personally tag a cargo telepad here."
			return TRUE
		acc.adjust_money(-total_cost)
		owner_label = computer.personal_char_name
	else if(is_crew)
		var/datum/drydock_ship/crew_ship = _drydock_ship_at(GET_Z(computer))
		if(!crew_ship)
			status_message = "This console isn't aboard a deployed drydock ship."
			return TRUE
		var/datum/money_account/acc = crew_ship.owner_account_number ? SSeconomy.get_account(crew_ship.owner_account_number) : null
		if(!acc)
			status_message = "This ship has no linked owner account on file."
			return TRUE
		if(acc.money < total_cost)
			status_message = "Insufficient funds -- that would cost [total_cost] cr."
			return TRUE
		if(!telepad_turf)
			status_message = "No crew-tagged telepad found aboard [crew_ship.display_name()]."
			return TRUE
		acc.adjust_money(-total_cost)
		owner_label = crew_ship.display_name()
	else if(net)
		if(!telepad_turf)
			status_message = "No faction telepad found for network '[net]' on this ship/station."
			return TRUE
		if(!faction_debit(net, total_cost, "Supply Beacon purchase (#[B.beacon_id])"))
			status_message = "[get_faction_name(net)]'s treasury can't cover that purchase."
			return TRUE
		owner_label = get_faction_name(net)
	else
		status_message = "This terminal isn't linked to a faction, personal, or crew network."
		return TRUE

	var/list/delivered = list()
	var/list/summary = list()
	for(var/commodity_key in order)
		var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
		var/line_amount = order[commodity_key]
		var/crate_type = commodity["crate_type"]
		var/obj/structure/closet/crate/supply_beacon/crate = new crate_type(telepad_turf)
		crate.amount = line_amount
		crate.refresh_label()
		// Permanently stamp which beacon this came from -- the sell handler
		// refuses to buy a crate back at its own origin, so hauling it
		// elsewhere is the only way to realize the price spread. A crate
		// property, not a timer, so it outlives the trade cooldown entirely.
		crate.origin_beacon_id = B.beacon_id
		crate.origin_beacon_label = B.name
		// Ownership tag is a removable label, not a lock. Same convention as a
		// Cargo Order crate (spawn_order_crate(), cargo.dm) and the hand
		// labeler (handlabeler.dm): name_unlabel captures the untagged name so
		// Remove Label can strip the tag later without losing the
		// commodity/amount identification underneath.
		crate.name_unlabel = crate.name
		crate.name = "[crate.name] ([owner_label])"
		crate.verbs += /atom/proc/remove_label
		delivered += crate
		B.apply_trade_impact(commodity_key, line_amount, TRUE)
		summary += "[line_amount]x [commodity["name"]]"

	persistence_telepad_deliver(delivered, telepad_turf)
	// Fold each new crate into any identical stack already on the pad (same
	// commodity AND same origin beacon) so repeat purchases don't litter it.
	for(var/obj/structure/closet/crate/supply_beacon/crate in delivered)
		if(!QDELETED(crate))
			crate.merge_stacks_on_turf()

	// ONE cooldown for the whole order, however many lines it had.
	supply_beacon_set_cooldown(source_key, B.beacon_id)
	cart = list()
	status_message = "Purchased [english_list(summary)] for [total_cost] cr."
	log_game("[key_name(user)] bought [english_list(summary)] from Supply Beacon #[B.beacon_id] for [total_cost] cr via Supply Beacon Terminal.")
	return TRUE

/**
 * Mirrors _checkout_purchase() for the sell side -- credits ONCE for `order`
 * (commodity_key -> amount), consuming crates across every candidate pad and
 * applying per-commodity price impact, then sets the trade cooldown a single
 * time for the whole basket. See _checkout_purchase()'s own doc comment for
 * why one cooldown for N lines is the entire point of the cart.
 *
 * Availability for EVERY line is validated up front before anything is
 * touched -- a partially-fillable cart refuses outright rather than selling
 * what it can and silently dropping the rest.
 */
/datum/computer_file/program/civilian/supplybeaconterminal/proc/_checkout_sale(mob/user, obj/effect/overmap/supply_beacon/B, source_key, list/order)
	if(!length(order))
		status_message = "Nothing to sell."
		return TRUE

	// Same-Z-only (get_candidate_pads()) -- only ever look for crates
	// physically sitting on THIS ship/station's own telepads, never a
	// different one the same faction/character/ship owns elsewhere.
	var/list/candidate_pads = get_candidate_pads()
	if(!length(candidate_pads))
		status_message = "No delivery-enabled telepad found on this ship/station."
		return TRUE

	var/list/found_crates_by_commodity = list()
	for(var/commodity_key in order)
		var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
		if(!commodity)
			status_message = "Unknown commodity in order."
			return TRUE
		var/list/found_crates = list()
		var/total_available = 0
		var/origin_blocked = 0
		for(var/obj/structure/machinery/telepad_cargo/pad in candidate_pads)
			var/turf/pad_turf = get_turf(pad)
			if(!pad_turf)
				continue
			for(var/obj/structure/closet/crate/supply_beacon/crate in pad_turf)
				if(crate.commodity_key != commodity_key)
					continue
				// A crate can't be sold back to the beacon it was bought from --
				// that would be a risk-free round trip on the buy/sell spread
				// without ever hauling anything. Counted separately so the
				// refusal can say why.
				if(crate.origin_beacon_id && crate.origin_beacon_id == B.beacon_id)
					origin_blocked += crate.amount
					continue
				found_crates += crate
				total_available += crate.amount
		if(total_available < order[commodity_key])
			if(origin_blocked)
				status_message = "Only [total_available]x [commodity["name"]] sellable here -- [origin_blocked]x was bought from this beacon and must be hauled elsewhere to sell."
			else
				status_message = "Only [total_available]x [commodity["name"]] found on your telepad(s) -- need [order[commodity_key]]."
			return TRUE
		found_crates_by_commodity[commodity_key] = found_crates

	var/total_proceeds = 0
	var/list/touched_turfs = list()
	var/list/summary = list()
	for(var/commodity_key in order)
		var/list/commodity = GLOB.supply_beacon_commodities[commodity_key]
		var/remaining = order[commodity_key]
		// Consume crates greedily until `remaining` units are accounted for --
		// a fully-consumed crate is deleted, a partially-consumed one just has
		// its stack (and label) shrunk.
		for(var/obj/structure/closet/crate/supply_beacon/crate in found_crates_by_commodity[commodity_key])
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
		total_proceeds += B.commodity_prices[commodity_key] * order[commodity_key]
		B.apply_trade_impact(commodity_key, order[commodity_key], FALSE)
		summary += "[order[commodity_key]]x [commodity["name"]]"

	// Send-off feedback -- matches Cargo Exports' own export_now exactly, so a
	// Supply Beacon sale looks/sounds consistent with every other way goods
	// leave through a telepad.
	for(var/turf/touched in touched_turfs)
		spark(touched, 5, GLOB.alldirs)
		playsound(touched, 'sound/effects/transport.ogg', 50, 1)
		new /obj/effect/portal/decorative/fading(touched)

	var/net = normalize_faction_uid(computer.persistent_network)
	var/is_personal = computer.personal_ckey
	var/is_crew = computer.crew_tagged

	if(is_personal)
		var/obj/item/card/id/I = user.GetIdCard()
		var/datum/money_account/acc = I?.associated_account_number ? SSeconomy.get_account(I.associated_account_number) : null
		if(!acc)
			status_message = "Sold [english_list(summary)] for [total_proceeds] cr, but no linked bank account was found to credit."
		else
			acc.adjust_money(total_proceeds)
			status_message = "Sold [english_list(summary)] for [total_proceeds] cr to your personal account."
	else if(is_crew)
		var/datum/drydock_ship/crew_ship = _drydock_ship_at(GET_Z(computer))
		var/datum/money_account/acc = (crew_ship && crew_ship.owner_account_number) ? SSeconomy.get_account(crew_ship.owner_account_number) : null
		if(!acc)
			status_message = "Sold [english_list(summary)] for [total_proceeds] cr, but [crew_ship ? crew_ship.display_name() : "the ship"]'s owner account could not be found."
		else
			acc.adjust_money(total_proceeds)
			status_message = "Sold [english_list(summary)] for [total_proceeds] cr to [crew_ship.display_name()]'s account."
	else
		faction_credit(net, total_proceeds, "Supply Beacon sale (#[B.beacon_id])")
		status_message = "Sold [english_list(summary)] for [total_proceeds] cr to [get_faction_name(net)]."

	// ONE cooldown for the whole order, however many lines it had.
	supply_beacon_set_cooldown(source_key, B.beacon_id)
	sell_cart = list()
	log_game("[key_name(user)] sold [english_list(summary)] to Supply Beacon #[B.beacon_id] for [total_proceeds] cr via Supply Beacon Terminal.")
	return TRUE

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
				for(var/obj/structure/machinery/telepad_cargo/pad in get_candidate_pads())
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

			// A single "Buy" is just a one-line cart checked out immediately --
			// same code path, so it charges and sets the trade cooldown exactly
			// once, identically to a multi-line cart.
			return _checkout_purchase(user, B, source_key, list("[commodity_key]" = amount))

		// ---- Cart ------------------------------------------------------------
		// The 30-minute trade cooldown is per (source, beacon) and fires on ANY
		// completed trade, so buying commodities one at a time cost a whole
		// lockout per item. Staging lines in a cart and checking out once makes
		// an arbitrarily large order a single transaction -- one charge, one
		// price impact per commodity, one cooldown.
		if("cart_add")
			var/commodity_key = params["commodity"]
			if(!GLOB.supply_beacon_commodities[commodity_key])
				status_message = "Unknown commodity."
				return TRUE
			var/amount = text2num(params["amount"])
			if(!amount || amount <= 0)
				status_message = "Enter a valid amount."
				return TRUE
			cart[commodity_key] = (cart[commodity_key] || 0) + amount
			status_message = "Cart: [cart[commodity_key]]x [GLOB.supply_beacon_commodities[commodity_key]["name"]]."
			return TRUE

		if("cart_remove")
			var/commodity_key = params["commodity"]
			cart -= commodity_key
			status_message = "Removed from cart."
			return TRUE

		if("cart_clear")
			cart = list()
			status_message = "Cart cleared."
			return TRUE

		if("cart_checkout")
			if(!length(cart))
				status_message = "Cart is empty."
				return TRUE
			var/obj/effect/overmap/supply_beacon/B = selected_beacon_id ? SSsupply_beacons.beacons["[selected_beacon_id]"] : null
			if(!B || QDELETED(B))
				status_message = "Select a beacon first."
				return TRUE
			if(!computer || !supply_beacon_ship_in_range(GET_Z(computer), B))
				status_message = "Your ship must be adjacent to the beacon to trade."
				return TRUE
			var/source_key = get_supply_beacon_source_key(computer)
			if(!source_key)
				status_message = "This terminal isn't linked to a faction, personal, or crew network."
				return TRUE
			var/cooldown = supply_beacon_cooldown_remaining(source_key, B.beacon_id)
			if(cooldown > 0)
				status_message = "This beacon is on cooldown for [DisplayTimeText(cooldown SECONDS)] more."
				return TRUE
			return _checkout_purchase(user, B, source_key, cart.Copy())

		if("sell")
			var/obj/effect/overmap/supply_beacon/B = selected_beacon_id ? SSsupply_beacons.beacons["[selected_beacon_id]"] : null
			if(!B || QDELETED(B))
				status_message = "Select a beacon first."
				return TRUE
			if(!computer || !supply_beacon_ship_in_range(GET_Z(computer), B))
				status_message = "Your ship must be adjacent to the beacon to trade."
				return TRUE
			var/commodity_key = params["commodity"]
			if(!GLOB.supply_beacon_commodities[commodity_key])
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

			// A single "Sell" is just a one-line cart checked out immediately --
			// see _checkout_sale()'s own doc comment for why this matters.
			return _checkout_sale(user, B, source_key, list("[commodity_key]" = amount))

		// ---- Sell cart ---------------------------------------------------
		if("sell_cart_add")
			var/commodity_key = params["commodity"]
			if(!GLOB.supply_beacon_commodities[commodity_key])
				status_message = "Unknown commodity."
				return TRUE
			var/amount = text2num(params["amount"])
			if(!amount || amount <= 0)
				status_message = "Enter a valid amount."
				return TRUE
			sell_cart[commodity_key] = (sell_cart[commodity_key] || 0) + amount
			status_message = "Sell cart: [sell_cart[commodity_key]]x [GLOB.supply_beacon_commodities[commodity_key]["name"]]."
			return TRUE

		if("sell_cart_remove")
			var/commodity_key = params["commodity"]
			sell_cart -= commodity_key
			status_message = "Removed from sell cart."
			return TRUE

		if("sell_cart_clear")
			sell_cart = list()
			status_message = "Sell cart cleared."
			return TRUE

		if("sell_cart_checkout")
			if(!length(sell_cart))
				status_message = "Sell cart is empty."
				return TRUE
			var/obj/effect/overmap/supply_beacon/B = selected_beacon_id ? SSsupply_beacons.beacons["[selected_beacon_id]"] : null
			if(!B || QDELETED(B))
				status_message = "Select a beacon first."
				return TRUE
			if(!computer || !supply_beacon_ship_in_range(GET_Z(computer), B))
				status_message = "Your ship must be adjacent to the beacon to trade."
				return TRUE
			var/source_key = get_supply_beacon_source_key(computer)
			if(!source_key)
				status_message = "This terminal isn't linked to a faction, personal, or crew network."
				return TRUE
			var/cooldown = supply_beacon_cooldown_remaining(source_key, B.beacon_id)
			if(cooldown > 0)
				status_message = "This beacon is on cooldown for [DisplayTimeText(cooldown SECONDS)] more."
				return TRUE
			return _checkout_sale(user, B, source_key, sell_cart.Copy())
