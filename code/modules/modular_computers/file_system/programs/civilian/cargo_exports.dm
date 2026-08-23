/*
 * Cargo Exports Terminal
 * Standalone program for exporting goods via faction supply telepads.
 * Players place items/crates on their faction's telepad, then click "Export Now"
 * to sell them and credit the faction account.
 *
 * Requires: computer shackled to a faction (computer.persistent_network set)
 * and a faction telepad with matching persistent_network placed nearby.
 *
 * Also supports PERSONAL mode (mutually exclusive with faction mode, same as
 * every other personal_tagger_set() type) -- a computer personally tagged via
 * the faction tagger exports to a matching personally-tagged telepad instead,
 * crediting the operator's own bank account rather than a faction's. No
 * officer-rank gate applies in personal mode: the computer's own blanket
 * personal lock (ui_interact(), modular_computer/ui.dm) already restricts the
 * console to its tagged owner (or an admin).
 */

/datum/computer_file/program/civilian/cargoexports
	filename = "cargoexports"
	filedesc = "Cargo Exports Terminal"
	program_icon_state = "supply"
	program_key_icon_state = "yellow_key"
	extended_desc = "Export goods via faction supply telepad. Items placed on the telepad are processed and credits deposited into the faction account."
	required_access_run = ACCESS_CARGO
	required_access_download = ACCESS_CARGO
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 2
	color = LIGHT_COLOR_BLUE
	tgui_id = "CargoExports"
	ui_auto_update = TRUE  // re-poll ui_data every tick so faction link changes are reflected immediately

	var/status_message = ""
	/// Explicit pad choice when the console's own scope (faction/personal/
	/// crew) has more than one delivery-enabled telepad; null falls back to
	/// the plain first-match finder for whichever mode is active. Exports
	/// have no persistent per-order datum (unlike Cargo Order's `co`) to
	/// store this on, so it lives directly on the program instance instead --
	/// re-validated against the CURRENT mode's own scoping at export_now
	/// time (never trusted blindly), same as Cargo Order's co.delivery_telepad.
	var/obj/structure/machinery/telepad_cargo/selected_export_telepad

/datum/computer_file/program/civilian/cargoexports/ui_data(mob/user)
	var/list/data = initial_data()
	// Normalize defensively: consoles shackled before uid normalization carry
	// raw display names in their saved worldstate
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : ""
	var/is_personal = computer && computer.personal_ckey

	var/raw_balance = net ? get_faction_account_balance(net) : null

	data["faction_uid"]     = net
	data["faction_name"]    = net ? get_faction_name(net) : null
	data["faction_balance"] = isnull(raw_balance) ? 0 : raw_balance
	data["has_telepad"]     = net ? !!persistence_find_cargo_telepad(net) : FALSE
	data["status_message"]  = status_message
	// Exports require being docked at a station -- unlike Cargo Order
	// (imports), which works fine anywhere. Applies uniformly across all
	// three tag modes, including Crew (which only ever exists aboard a
	// ship, so Crew-mode exports are permanently unreachable by design --
	// confirmed with the user). See export_now below for the actual
	// enforcement; this is just the UI-side signal.
	data["on_drydock_ship"] = computer ? !!_drydock_ship_at(GET_Z(computer)) : FALSE

	// Personal mode -- mutually exclusive with faction mode (same as every
	// other personal_tagger_set() type). No officer-rank concept applies:
	// the computer's own blanket personal lock (ui_interact(),
	// modular_computer/ui.dm) already restricts this console to the tagged
	// owner (or an admin), so there's nobody else who could reach export_now.
	data["is_personal"]        = is_personal
	data["personal_owner_name"] = is_personal ? computer.personal_char_name : null
	data["has_personal_telepad"] = is_personal ? !!persistence_find_personal_cargo_telepad(computer.personal_ckey, computer.personal_char_name) : FALSE
	// Whoever is physically viewing the UI right now -- in the normal case
	// this is always the tagged owner (blanket lock), same assumption
	// export_now's own crediting already makes.
	if(is_personal)
		var/obj/item/card/id/viewer_id = user.GetIdCard()
		var/datum/money_account/viewer_acc = viewer_id?.associated_account_number ? SSeconomy.get_account(viewer_id.associated_account_number) : null
		data["personal_balance"] = viewer_acc ? viewer_acc.money : null

	// Export catalog -- the actual admin-configured price list (Manage Cargo
	// Exports, persistence_cargo_exports.dm) that get_cargo_export_price()
	// really charges from, not the legacy /datum/export system (dead code --
	// see persistence_cargo_exports.dm:3-8). Anything not listed here still
	// sells, at the flat base price (export_base_price below). Illegal
	// entries are left out of this reference list entirely unless an
	// operational piracy beacon is present on THIS console's own Z -- mirrors
	// Cargo Order's can_order_syndicate_uplink() catalog filter exactly
	// (cargo_order.dm). The actual sale price is separately gated the same
	// way inside get_cargo_export_price() itself, so this is purely a "don't
	// even show it as sellable right now" display filter.
	var/console_z = computer ? GET_Z(computer) : 0
	var/beacon_active = piracy_beacon_active_on_z(console_z)
	var/list/catalog = list()
	for(var/tp in GLOB.cargo_export_prices)
		var/list/entry = GLOB.cargo_export_prices[tp]
		if(entry["illegal"] && !beacon_active)
			continue
		var/path = text2path(tp)
		var/display_name = entry["label"] || ((path && initial(path:name)) ? initial(path:name) : tp)
		catalog += list(list("name" = display_name, "price" = entry["price"]))
	data["export_catalog"] = catalog
	data["export_base_price"] = CARGO_EXPORT_BASE_PRICE

	// Crew mode -- mutually exclusive with faction/personal mode. Bills the
	// SHIP OWNER's account (not the operator's own) at export time, resolved
	// via _drydock_ship_at() on this console's current Z rather than a
	// stored identity -- see export_now below.
	var/is_crew = computer && computer.crew_tagged
	data["is_crew"] = is_crew
	if(is_crew)
		var/datum/drydock_ship/crew_ship = _drydock_ship_at(GET_Z(computer))
		data["crew_ship_name"] = crew_ship ? crew_ship.display_name() : null
		var/datum/money_account/crew_acc = (crew_ship && crew_ship.owner_account_number) ? SSeconomy.get_account(crew_ship.owner_account_number) : null
		data["crew_balance"] = crew_acc ? crew_acc.money : null
		data["has_crew_telepad"] = crew_ship ? !!persistence_find_crew_cargo_telepad(crew_ship.shuttle_id) : FALSE

	// Export telepad choice -- only surfaced when the console's OWN tag mode
	// has more than one delivery-enabled cargo pad in ITS scope (never
	// cross-mode -- mirrors Cargo Order's own picker exactly, see
	// cargo_telepad_choice_data(), persistence_cryo.dm).
	data["telepad_choices"] = list()
	data["selected_telepad_ref"] = null
	var/list/export_candidate_pads = list()
	if(net)
		export_candidate_pads = persistence_find_cargo_telepads(net)
	else if(is_personal)
		export_candidate_pads = persistence_find_personal_cargo_telepads(computer.personal_ckey, computer.personal_char_name)
	else if(is_crew)
		var/datum/drydock_ship/crew_ship_for_pads = _drydock_ship_at(GET_Z(computer))
		if(crew_ship_for_pads)
			export_candidate_pads = persistence_find_crew_cargo_telepads(crew_ship_for_pads.shuttle_id)
	data["telepad_choices"] = cargo_telepad_choice_data(export_candidate_pads, computer)
	if(length(data["telepad_choices"]) && selected_export_telepad && !QDELETED(selected_export_telepad) && (selected_export_telepad in export_candidate_pads))
		data["selected_telepad_ref"] = "\ref[selected_export_telepad]"

	// Operator rank (officer+ required to export) -- faction mode only.
	var/list/op_member = (net && user.ckey) ? get_faction_member(user.ckey, net) : null
	var/op_rank = op_member ? (isnull(op_member["rank"]) ? 0 : (op_member["rank"] + 0)) : -1
	if(check_rights(R_ADMIN, 0, user)) op_rank = 99
	data["op_rank"] = op_rank

	return data

/datum/computer_file/program/civilian/cargoexports/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/user = usr
	var/net = normalize_faction_uid(computer.persistent_network)

	switch(action)
		if("link_faction")
			// Link THIS computer to the user's faction from inside the program
			if(!computer)
				status_message = "Error: no computer reference."
				return TRUE
			var/obj/item/card/id/I = user.GetIdCard()
			if(!I || !I.employer_faction)
				status_message = "Your ID is not issued by a faction. Get a faction ID first."
				return TRUE
			// Refuse if this console is already personally or crew tagged --
			// those modes clear each other's fields via personal_tagger_set()/
			// crew_tagger_set() (persistence_faction_tagger.dm), but this
			// shortcut writes persistent_network directly and previously
			// never checked either, letting a console end up dual-tagged.
			// Use the Faction Tagger to release the existing tag first.
			if(computer.personal_ckey)
				status_message = "This console is personally tagged to [computer.personal_char_name] -- use the Faction Tagger to release it first."
				return TRUE
			if(computer.crew_tagged)
				status_message = "This console is tagged to a ship's crew -- use the Faction Tagger to release it first."
				return TRUE
			var/card_faction = normalize_faction_uid(I.employer_faction)
			if(computer.faction_shackled && computer.persistent_network != card_faction)
				if(computer.persistent_network == "public")
					status_message = "This console is marked Public -- an admin must clear it before it can be relinked."
				else
					status_message = "This console is already linked to [get_faction_name(computer.persistent_network)]. Only their officers can release it."
				return TRUE
			computer.persistent_network = card_faction
			computer.faction_shackled   = TRUE
			status_message = "Console linked to [get_faction_name(card_faction)]. Refreshing..."
			log_game("[key_name(user)] linked cargo exports console at ([computer.x],[computer.y],[computer.z]) to faction '[card_faction]' via program.")
			return TRUE

		//Pick which of the console's own-scope cargo telepads exports should
		//land on -- resolved the same 3-mode way as ui_data() above, so the
		//clicked ref can only ever match a pad already in THIS console's own
		//candidate set (never a different faction's/character's/ship's pad).
		if("select_telepad")
			var/target_ref = params["select_telepad"]
			selected_export_telepad = null
			if(target_ref)
				var/is_personal_pick = computer && computer.personal_ckey
				var/is_crew_pick = computer && computer.crew_tagged
				var/list/candidate_pads = list()
				if(net)
					candidate_pads = persistence_find_cargo_telepads(net)
				else if(is_personal_pick)
					candidate_pads = persistence_find_personal_cargo_telepads(computer.personal_ckey, computer.personal_char_name)
				else if(is_crew_pick)
					var/datum/drydock_ship/crew_ship_for_select = _drydock_ship_at(GET_Z(computer))
					if(crew_ship_for_select)
						candidate_pads = persistence_find_crew_cargo_telepads(crew_ship_for_select.shuttle_id)
				for(var/obj/structure/machinery/telepad_cargo/pad in candidate_pads)
					if("\ref[pad]" == target_ref)
						selected_export_telepad = pad
						break
			return TRUE

		if("export_now")
			// Exports require being docked at a station -- applies uniformly
			// regardless of tag mode (Faction/Personal/Crew), checked before
			// anything else. Cargo Order (imports) has no such restriction.
			if(computer && _drydock_ship_at(GET_Z(computer)))
				status_message = "Return to a station to be able to sell your exports."
				return TRUE
			var/is_personal = computer && computer.personal_ckey
			var/is_crew = computer && computer.crew_tagged
			if(!net && !is_personal && !is_crew)
				status_message = "This terminal is not linked to a faction network."
				return TRUE

			var/datum/drydock_ship/crew_ship
			var/turf/pad_turf
			if(is_personal)
				// No officer-rank gate here -- the computer's own blanket
				// personal lock already restricts this console to the tagged
				// owner (or an admin), so there's no one else to gate against.
				// Prefer the explicit pick, but ONLY if it's still actually a
				// personal pad tagged to this SAME (ckey, char_name) -- never
				// trust a stale selection left over from a since-changed tag
				// mode, same re-validation deliver_personal_order() (cargo.dm)
				// already does for Cargo Order.
				if(selected_export_telepad && !QDELETED(selected_export_telepad) && selected_export_telepad.accepts_cargo && selected_export_telepad.persistent_spawn && selected_export_telepad.z && selected_export_telepad.personal_ckey == computer.personal_ckey && selected_export_telepad.personal_char_name == computer.personal_char_name)
					pad_turf = get_turf(selected_export_telepad)
				if(!pad_turf)
					pad_turf = persistence_find_personal_cargo_telepad(computer.personal_ckey, computer.personal_char_name)
				if(!pad_turf)
					status_message = "No personally-tagged telepad found for [computer.personal_char_name]. Place and personally tag a cargo telepad nearby."
					return TRUE
			else if(is_crew)
				// No officer-rank gate here either -- same reasoning as
				// personal mode, only this ship's crew can reach this console.
				crew_ship = _drydock_ship_at(GET_Z(computer))
				if(!crew_ship)
					status_message = "This console isn't aboard a deployed drydock ship."
					return TRUE
				if(!crew_ship.owner_account_number)
					status_message = "This ship has no linked owner account on file."
					return TRUE
				// Prefer the explicit pick, but ONLY if it's still crew-tagged
				// AND still resolves to this SAME ship -- same re-validation
				// deliver_crew_order() (cargo.dm) already does.
				if(selected_export_telepad && !QDELETED(selected_export_telepad) && selected_export_telepad.accepts_cargo && selected_export_telepad.persistent_spawn && selected_export_telepad.z && selected_export_telepad.crew_tagged)
					var/datum/drydock_ship/selected_pad_ship = _drydock_ship_at(selected_export_telepad.z)
					if(selected_pad_ship == crew_ship)
						pad_turf = get_turf(selected_export_telepad)
				if(!pad_turf)
					pad_turf = persistence_find_crew_cargo_telepad(crew_ship.shuttle_id)
				if(!pad_turf)
					status_message = "No crew-tagged telepad found for [crew_ship.display_name()]. Place and crew-tag a cargo telepad nearby."
					return TRUE
			else
				// Operator rank gate -- officer+ (faction mode only)
				var/list/op_member = user.ckey ? get_faction_member(user.ckey, net) : null
				var/op_rank = op_member ? (isnull(op_member["rank"]) ? 0 : (op_member["rank"] + 0)) : -1
				if(op_rank < 1 && !check_rights(R_ADMIN, 0, user))
					status_message = "Officer access required to process exports."
					return TRUE
				// Prefer the explicit pick, but ONLY if it's still tagged to
				// THIS SAME faction -- same re-validation deliver_faction_order()
				// (cargo.dm) already does for Cargo Order.
				if(selected_export_telepad && !QDELETED(selected_export_telepad) && selected_export_telepad.accepts_cargo && selected_export_telepad.persistent_spawn && selected_export_telepad.z && normalize_faction_uid(selected_export_telepad.persistent_network) == net)
					pad_turf = get_turf(selected_export_telepad)
				if(!pad_turf)
					pad_turf = persistence_find_cargo_telepad(net)
				if(!pad_turf)
					status_message = "No faction telepad found for network '[net]'. Place and link a cargo telepad nearby."
					return TRUE

			// Reset generic export totals before scanning
			SScargo.reset_generic_export_totals()

			// Scan everything on the telepad turf (skip the telepad machinery itself,
			// and anything else is_cargo_export_excluded() rules out -- structural
			// framework like girders/lattice, not just machinery)
			//
			// Refused computers are named back to the operator rather than
			// silently passed over: a PDA left sitting on the pad after a sale
			// looks exactly like a bug ("why didn't it sell?"), and the answer
			// -- that selling it would have destroyed the ID card inside it --
			// is worth saying out loud.
			var/list/refused_computers = list()
			for(var/atom/movable/A in pad_turf)
				if(is_cargo_export_excluded(A))
					if(istype(A, /obj/item/modular_computer))
						refused_computers |= A.name
					continue
				SScargo.export_item_and_contents(A)

			// Collect results
			var/exp_total = SScargo.generic_export_total
			var/list/exp_lines = list()
			for(var/item_name in SScargo.generic_export_lines)
				exp_lines += "[item_name]: [SScargo.generic_export_lines[item_name]] cr"

			var/refusal_note = length(refused_computers) \
				? " Refused to export [jointext(refused_computers, ", ")] -- computers and PDAs carry ID cards and stored data, and are never sold." \
				: ""

			if(!exp_total)
				status_message = length(refused_computers) \
					? "Nothing exportable on the telepad.[refusal_note]" \
					: "No exportable items found on the telepad. Place items or crates on the telepad first."
				return TRUE

			var/summary = exp_lines.len ? jointext(exp_lines, "; ") : "miscellaneous items"
			if(is_personal)
				// Credited to whoever is physically operating the console right
				// now -- same present-card approach personal cargo order
				// payment already uses (cargo_order.dm), since there's no
				// reliable way to resolve an offline character's account. In
				// the normal case this is always the tagged owner anyway (the
				// blanket lock prevents anyone else from getting this far).
				var/obj/item/card/id/ID = user.GetIdCard()
				var/datum/money_account/acc = ID?.associated_account_number ? SSeconomy.get_account(ID.associated_account_number) : null
				if(!acc)
					status_message = "Export ready ([exp_total] cr: [summary]) but no linked bank account was found to credit."
					return TRUE
				acc.adjust_money(exp_total)
				status_message = "Exported [exp_total] cr: [summary]. Credited to your personal account."
				log_game("[key_name(user)] exported [exp_total] cr of goods to their personal account via cargo exports terminal.")
			else if(is_crew)
				// Credited to the SHIP OWNER's account, not whoever's operating
				// the console -- owner_account_number is a stable identifier
				// that resolves even while the owner is offline (unlike a
				// personal order's present-card approach above).
				var/datum/money_account/owner_acc = SSeconomy.get_account(crew_ship.owner_account_number)
				if(!owner_acc)
					status_message = "Export ready ([exp_total] cr: [summary]) but [crew_ship.display_name()]'s owner account could not be found to credit."
					return TRUE
				owner_acc.adjust_money(exp_total)
				status_message = "Exported [exp_total] cr: [summary]. Credited to [crew_ship.display_name()]'s account."
				log_game("[key_name(user)] exported [exp_total] cr of goods to [crew_ship.display_name()]'s owner account via cargo exports terminal.")
			else
				faction_credit(net, exp_total, "Cargo export by [user.ckey]")
				status_message = "Exported [exp_total] cr: [summary]. Credited to [get_faction_name(net)]."
				log_game("[key_name(user)] exported [exp_total] cr of goods to faction [net] via cargo exports terminal.")

			// Appended after every crediting branch rather than inside each, so
			// the operator is told what stayed behind regardless of which
			// account the sale went to.
			status_message += refusal_note

			// Send-off feedback -- matches the sound persistence_telepad_deliver()
			// already plays for an INCOMING order arriving at this same pad
			// (persistence_cryo.dm), so export and delivery sound consistent.
			spark(pad_turf, 5, GLOB.alldirs)
			playsound(pad_turf, 'sound/effects/transport.ogg', 50, 1)
			return TRUE
