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

		// Reference-only: the operator's OWN faction balance, if they belong
		// to one -- this console is personally tagged so it's not what gets
		// credited, but a player switching between a faction console and
		// their own personal one elsewhere likely wants both figures handy
		// without needing to check a second terminal.
		var/viewer_uid = (viewer_id && viewer_id.employer_faction) ? normalize_faction_uid(viewer_id.employer_faction) : null
		data["operator_faction_name"]    = viewer_uid ? get_faction_name(viewer_uid) : null
		data["operator_faction_balance"] = viewer_uid ? get_faction_account_balance(viewer_uid) : null

	// Export catalog -- all exportable types and their current prices
	var/list/catalog = list()
	for(var/datum/export/E in SScargo.exports_list)
		if(!E.unit_name)
			continue
		catalog += list(list("name" = E.unit_name, "price" = E.get_cost()))
	data["export_catalog"] = catalog

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
				pad_turf = persistence_find_cargo_telepad(net)
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

			// Send-off feedback -- matches the sound persistence_telepad_deliver()
			// already plays for an INCOMING order arriving at this same pad
			// (persistence_cryo.dm), so export and delivery sound consistent.
			spark(pad_turf, 5, GLOB.alldirs)
			playsound(pad_turf, 'sound/effects/phasein.ogg', 50, 1)
			return TRUE
