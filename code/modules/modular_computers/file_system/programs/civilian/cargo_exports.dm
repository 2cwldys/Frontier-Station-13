/*
 * Cargo Exports Terminal
 * Standalone program for exporting goods via faction supply telepads.
 * Players place items/crates on their faction's telepad, then click "Export Now"
 * to sell them and credit the faction account.
 *
 * Requires: computer shackled to a faction (computer.persistent_network set)
 * and a faction telepad with matching persistent_network placed nearby.
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
	size = 6
	color = LIGHT_COLOR_BLUE
	tgui_id = "CargoExports"
	ui_auto_update = TRUE  // re-poll ui_data every tick so faction link changes are reflected immediately

	var/status_message = ""

/datum/computer_file/program/civilian/cargoexports/ui_data(mob/user)
	var/list/data = initial_data()
	// Normalize defensively: consoles shackled before uid normalization carry
	// raw display names in their saved worldstate
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : ""

	var/raw_balance = net ? get_faction_account_balance(net) : null

	data["faction_uid"]     = net
	data["faction_name"]    = net ? get_faction_name(net) : null
	data["faction_balance"] = isnull(raw_balance) ? 0 : raw_balance
	data["has_telepad"]     = net ? !!persistence_find_cargo_telepad(net) : FALSE
	data["status_message"]  = status_message

	// Export catalog -- all exportable types and their current prices
	var/list/catalog = list()
	for(var/datum/export/E in SScargo.exports_list)
		if(!E.unit_name)
			continue
		catalog += list(list("name" = E.unit_name, "price" = E.get_cost()))
	data["export_catalog"] = catalog

	// Operator rank (officer+ required to export)
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
			var/card_faction = normalize_faction_uid(I.employer_faction)
			if(computer.faction_shackled && computer.persistent_network != card_faction)
				status_message = "This console is already linked to [get_faction_name(computer.persistent_network)]. Only their officers can release it."
				return TRUE
			computer.persistent_network = card_faction
			computer.faction_shackled   = TRUE
			status_message = "Console linked to [get_faction_name(card_faction)]. Refreshing..."
			log_game("[key_name(user)] linked cargo exports console at ([computer.x],[computer.y],[computer.z]) to faction '[card_faction]' via program.")
			return TRUE

		if("export_now")
			if(!net)
				status_message = "This terminal is not linked to a faction network."
				return TRUE

			// Operator rank gate -- officer+
			var/list/op_member = user.ckey ? get_faction_member(user.ckey, net) : null
			var/op_rank = op_member ? (isnull(op_member["rank"]) ? 0 : (op_member["rank"] + 0)) : -1
			if(op_rank < 1 && !check_rights(R_ADMIN, 0, user))
				status_message = "Officer access required to process exports."
				return TRUE

			// Find faction telepad
			var/turf/pad_turf = persistence_find_cargo_telepad(net)
			if(!pad_turf)
				status_message = "No faction telepad found for network '[net]'. Place and link a cargo telepad nearby."
				return TRUE

			// Reset generic export totals before scanning
			SScargo.reset_generic_export_totals()

			// Scan everything on the telepad turf (skip the telepad machinery itself)
			for(var/atom/movable/A in pad_turf)
				if(istype(A, /obj/structure/machinery)) continue
				SScargo.export_item_and_contents(A)

			// Collect results
			var/exp_total = SScargo.generic_export_total
			var/list/exp_lines = list()
			for(var/item_name in SScargo.generic_export_lines)
				exp_lines += "[item_name]: [SScargo.generic_export_lines[item_name]] cr"

			if(!exp_total)
				status_message = "No exportable items found on the telepad. Place items or crates on the telepad first."
				return TRUE

			faction_credit(net, exp_total, "Cargo export by [user.ckey]")
			var/summary = exp_lines.len ? jointext(exp_lines, "; ") : "miscellaneous items"
			status_message = "Exported [exp_total] cr: [summary]. Credited to [get_faction_name(net)]."
			log_game("[key_name(user)] exported [exp_total] cr of goods to faction [net] via cargo exports terminal.")
			return TRUE
