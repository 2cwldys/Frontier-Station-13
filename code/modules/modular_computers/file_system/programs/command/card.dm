/datum/computer_file/program/card_mod
	filename = "cardmod"
	filedesc = "ID Card Modification Program"
	program_icon_state = "id"
	program_key_icon_state = "lightblue_key"
	extended_desc = "Program for programming employee ID cards to access parts of the station."
	required_access_run = ACCESS_CHANGE_IDS
	required_access_download = ACCESS_CHANGE_IDS
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 8
	color = LIGHT_COLOR_BLUE
	tgui_id = "IDCardModification"
	var/is_centcom = FALSE
	var/show_assignments = FALSE

/datum/computer_file/program/card_mod/ui_data(mob/user)
	var/list/data = initial_data()

	data["station_name"] = station_name()
	data["assignments"] = show_assignments
	data["have_id_slot"] = !!computer.card_slot
	data["have_printer"] = !!computer.nano_printer
	data["authenticated"] = can_run(user)
	data["can_print_replacement"] = TRUE  // Self-service: available to everyone
	data["centcom_access"] = is_centcom

	var/obj/item/card/id/id_card = computer.card_slot.stored_card
	data["has_id"] = !!id_card
	data["id_rank"] = id_card && id_card.assignment ? id_card.assignment : "Unassigned"
	data["id_owner"] = id_card && id_card.registered_name ? id_card.registered_name : "-----"
	data["id_name"] = id_card ? id_card.name : "-----"

	if(computer.card_slot.stored_card)
		if(is_centcom)
			var/list/all_centcom_access = list()
			for(var/access in get_all_centcom_access())
				all_centcom_access.Add(list(list(
					"desc" = get_centcom_access_desc(access),
					"ref" = access,
					"allowed" = (access in id_card.access) ? TRUE : FALSE)))
			data["all_centcom_access"] = all_centcom_access
		else
			var/list/regions = list()
			for(var/i = 1; i <= 7; i++)
				var/list/accesses = list()
				for(var/access in get_region_accesses(i))
					if (get_access_desc(access))
						accesses.Add(list(list(
							"desc" = get_access_desc(access),
							"ref" = access,
							"allowed" = (access in id_card.access) ? TRUE : FALSE)))

				regions.Add(list(list(
					"name" = get_region_accesses_name(i),
					"accesses" = accesses)))
			data["regions"] = regions

	return data

/datum/computer_file/program/card_mod/ui_static_data(mob/user)
	var/list/data = list()
	// Faction jobs — populated when this console is networked to a faction
	if(computer && computer.persistent_network)
		var/list/faction_jobs_formatted = list()
		for(var/list/j in get_faction_jobs(computer.persistent_network))
			faction_jobs_formatted += list(list(
				"job"      = j["title"],
				"rank"     = j["rank"] || 0,
				"pay_rate" = j["pay_rate"] || 0
			))
		data["faction_jobs"]    = faction_jobs_formatted
		data["faction_network"] = computer.persistent_network
		data["faction_name"]    = get_faction_name(computer.persistent_network)
		// Show dispense button when the user has no member record for this faction yet
		var/mob/ui_user = usr
		var/already_member = (ui_user && ui_user.ckey) ? !!get_faction_member(ui_user.ckey, computer.persistent_network) : FALSE
		data["can_dispense_faction_id"] = !already_member
		// Officer field: rank >= 1 in this faction, or admin -- gates job assignment UI
		var/list/op_fmember = (ui_user && ui_user.ckey) ? get_faction_member(ui_user.ckey, computer.persistent_network) : null
		data["faction_officer"] = (op_fmember && (op_fmember["rank"] || 0) >= 1) || check_rights(R_ADMIN, 0, ui_user)
	else
		data["faction_jobs"]    = list()
		data["faction_network"] = null
		data["faction_name"]    = null
		data["can_dispense_faction_id"] = FALSE
		data["faction_officer"] = FALSE
	return data

/datum/computer_file/program/card_mod/proc/format_jobs(list/jobs)
	var/obj/item/card/id/id_card = computer.card_slot.stored_card
	var/list/formatted = list()
	for(var/job in jobs)
		formatted.Add(list(list(
			"target_rank" = id_card && id_card.assignment ? id_card.assignment : "Unassigned",
			"job" = job)))

	return formatted

/datum/computer_file/program/card_mod/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/user = usr
	var/obj/item/card/id/user_id_card = user.GetIdCard()
	var/obj/item/card/id/id_card = computer.card_slot.stored_card
	switch(action)
		if("togglea")
			if(show_assignments)
				show_assignments = FALSE
			else
				show_assignments = TRUE
			. = TRUE

		if("print")
			if(computer?.nano_printer && can_run(user, 1)) //This option should never be called if there is no printer
				var/contents = {"<h4>Access Report</h4>
							<u>Prepared By:</u> [user_id_card.registered_name ? user_id_card.registered_name : "Unknown"]<br>
							<u>For:</u> [id_card.registered_name ? id_card.registered_name : "Unregistered"]<br>
							<hr>
							<u>Assignment:</u> [id_card.assignment]<br>
							<u>Account Number:</u> #[id_card.associated_account_number]<br>
							<u>Blood Type:</u> [id_card.blood_type]<br><br>
							<u>Access:</u><br>
						"}

				var/known_access_rights = get_access_ids(ACCESS_TYPE_STATION|ACCESS_TYPE_CENTCOM)
				for(var/A in id_card.access)
					if(A in known_access_rights)
						contents += "  [get_access_desc(A)]"

				if(!computer.nano_printer.print_text(contents,"access report"))
					to_chat(usr, SPAN_WARNING("Hardware error: Printer was unable to print the file. It may be out of paper."))
					return
				else
					computer.visible_message(SPAN_NOTICE("\The [computer] prints out paper."))
					. = TRUE

		if("eject")
			if(computer && computer.card_slot)
				if(id_card)
					var/datum/record/general/R = SSrecords.find_record("name", id_card.registered_name)
					if(istype(R))
						var/real_title = id_card.assignment
						for(var/datum/job/J in get_job_datums())
							if(!J)
								continue
							var/list/alttitles = get_alternate_titles(J.title)
							if(id_card.assignment in alttitles)
								real_title = J.title
								break
						R.rank = id_card.assignment
						R.real_rank = real_title
				computer.eject_id()
				. = TRUE

		if("suspend")
			if(computer && can_run(user, 1))
				id_card.assignment = "Suspended"
				remove_nt_access(id_card)
				callHook("suspend_employee", list(id_card))
				. = TRUE

		if("edit")
			if(computer && can_run(user, 1))
				if(params["name"])
					var/temp_name = sanitizeName(input("Enter name.", "Name", id_card.registered_name))
					if(temp_name)
						id_card.registered_name = temp_name
					else
						computer.visible_message(SPAN_NOTICE("[computer] buzzes rudely."))
				else if(params["account"])
					var/account_num = text2num(input("Enter account number.", "Account", id_card.associated_account_number))
					id_card.associated_account_number = account_num
				. = TRUE

		if("assign")
			if(computer && can_run(user, 1) && id_card)
				var/t1 = params["assign_target"]
				if(t1 == "Custom")
					var/temp_t = sanitize(input("Enter a custom job assignment.","Assignment", id_card.assignment), 45)
					//let custom jobs function as an impromptu alt title, mainly for sechuds
					if(temp_t)
						id_card.assignment = temp_t
				else
					var/list/access = list()
					if(is_centcom)
						access = get_centcom_access(t1)
					else
						var/datum/job/jobdatum
						for(var/jobtype in typesof(/datum/job))
							var/datum/job/J = new jobtype
							if(ckey(J.title) == ckey(t1))
								jobdatum = J
								break
						if(!jobdatum)
							to_chat(usr, SPAN_WARNING("No log exists for this job: [t1]"))
							return

						access = jobdatum.get_access(t1)

					remove_nt_access(id_card)
					apply_access(id_card, access)
					id_card.assignment = t1
					id_card.rank = t1

				// Consoles tied to a faction network stamp their faction on assignment,
				// matching faction_assign -- otherwise the spawn default (e.g. NanoTrasen) sticks
				if(computer.persistent_network)
					id_card.employer_faction = computer.persistent_network

				SSrecords.reset_manifest()
				callHook("reassign_employee", list(id_card))
				. = TRUE

		if("access")
			if(isnum(params["allowed"]) && computer && can_run(user, 1))
				var/access_type = text2num(params["access_target"])
				var/access_allowed = text2num(params["allowed"])
				if(access_type in get_access_ids(ACCESS_TYPE_STATION|ACCESS_TYPE_CENTCOM))
					id_card.access -= access_type
					if(!access_allowed)
						id_card.access += access_type
						. = TRUE

		// ── Self-print replacement ID ─────────────────────────────────────
		if("print_replacement")
			if(!computer)
				return

			// Verify user identity via crew record
			var/datum/record/general/R = SSrecords.find_record("name", user.real_name)
			if(!R)
				to_chat(usr, SPAN_WARNING("No crew record found for [user.real_name]. Cannot print replacement ID."))
				return

			// Revoke any existing ID cards for this person in the world
			for(var/obj/item/card/id/old_card in world)
				if(!old_card.revoked && old_card.registered_name == user.real_name)
					old_card.revoked = TRUE
					old_card.access = list()
					old_card.update_name()
					to_chat(usr, SPAN_NOTICE("Previous ID card ([old_card.assignment]) has been revoked."))

			// Print new card
			var/obj/item/card/id/new_card = new /obj/item/card/id(get_turf(computer))
			new_card.registered_name = user.real_name
			new_card.assignment = R.rank || "Civilian"
			new_card.rank = R.rank || "Civilian"
			if(computer && computer.persistent_network)
				new_card.employer_faction = computer.persistent_network
			new_card.update_name()

			// Re-apply access for the job
			var/datum/job/jobdatum
			for(var/jobtype in typesof(/datum/job))
				var/datum/job/J = new jobtype
				if(ckey(J.title) == ckey(new_card.assignment))
					jobdatum = J
					break
			if(jobdatum)
				apply_access(new_card, jobdatum.get_access(new_card.assignment))

			// Biometric imprint
			if(istype(user, /mob/living/carbon/human))
				var/mob/living/carbon/human/H = user
				H.set_id_info(new_card)

			// Get or create personal bank account
			var/rep_acct = 0
			var/rep_is_new = FALSE
			// 1. Check in-memory economy cache (populated at startup from DB)
			var/list/rep_econ = GLOB.persistence_economy_cache["[user.ckey]|[user.real_name]"]
			if(islist(rep_econ))
				rep_acct = rep_econ["account_number"] || 0
			// 2. Check mind.initial_account — set earlier this session by a previous ID operation
			if(!rep_acct && user.mind && user.mind.initial_account)
				rep_acct = user.mind.initial_account.account_number
			// 3. Only if still nothing, create a brand-new account
			if(!rep_acct)
				SSeconomy.create_and_assign_account(user)
				if(user.mind && user.mind.initial_account)
					rep_acct = user.mind.initial_account.account_number
					rep_is_new = TRUE
			new_card.associated_account_number = rep_acct

			// Place in ID slot if empty; otherwise hand it over -- the old
			// (revoked) card stays equipped until the player swaps it themselves
			var/placed_in_slot = FALSE
			if(istype(user, /mob/living/carbon/human))
				var/mob/living/carbon/human/H = user
				if(!H.wear_id)
					placed_in_slot = H.equip_to_slot_if_possible(new_card, SLOT_ID, 0, 0, 0, 1)
			if(!placed_in_slot)
				user.put_in_hands(new_card)

			if(rep_is_new && rep_acct)
				tgui_alert(user, "A personal Idris bank account has been created.\n\nAccount Number: #[rep_acct]\n\nYou will be asked to set a PIN next. Write this number down.", "Account Created", list("Set PIN"))
				var/rep_pin = tgui_input_text(user, "Set a PIN for ATM access (4-8 digits). Leave blank to skip.", "Set ATM PIN", "", max_length = 8)
				var/pin_display = "(random -- set at ATM)"
				if(rep_pin && length(rep_pin) >= 4 && text2num(rep_pin))
					if(user.mind?.initial_account)
						user.mind.initial_account.remote_access_pin = text2num(rep_pin)
					pin_display = rep_pin
				var/rep_note = "Idris Account: #[rep_acct] | PIN: [pin_display] | Insert ID at any Idris ATM."
				if(GLOB.config.sql_enabled && SSdbcore.Connect())
					var/datum/db_query/rn_q = SSdbcore.NewQuery(
						{"INSERT INTO ss13_crew_records (ckey, char_name, ccia_notes, saved_at)
						VALUES (:ckey, :name, :note, NOW())
						ON DUPLICATE KEY UPDATE ccia_notes = VALUES(ccia_notes), saved_at = NOW()"},
						list("ckey" = user.ckey, "name" = user.real_name, "note" = rep_note)
					)
					rn_q.Execute()
					qdel(rn_q)
				// Mirror onto the live record too, or recordsFinalize() overwrites
				// the DB note with the record's stale default at round end
				R.ccia_record = rep_note
				to_chat(usr, SPAN_GOOD("[icon2html(new_card, usr)] KEEP SAFE -- Account: #[rep_acct] | PIN: [pin_display]"))
				to_chat(usr, SPAN_NOTICE("Saved in your crew record. Access at any Idris SelfServ Teller."))
			else if(rep_acct)
				to_chat(usr, SPAN_NOTICE("Existing bank account #[rep_acct] linked to this ID."))

			to_chat(usr, SPAN_GOOD("Replacement ID card printed and revoked old card."))
			log_admin("[user.key] printed a replacement ID card for [user.real_name] via [computer].")
			. = TRUE

		// ── Faction ID dispensing (no crew record required) ──────────────
		if("dispense_faction_id")
			if(!computer || !computer.persistent_network)
				return
			if(!user.real_name || !user.ckey)
				to_chat(usr, SPAN_WARNING("You must be a living character to receive an ID."))
				return
			var/disp_net = computer.persistent_network
			var/faction_name = get_faction_name(disp_net)
			// If already a member, reprint instead
			var/already_member = !!get_faction_member(user.ckey, disp_net)
			// Revoke any existing faction ID cards for this person
			for(var/obj/item/card/id/old_card in world)
				if(!old_card.revoked && old_card.registered_name == user.real_name && old_card.employer_faction == disp_net)
					old_card.revoked = TRUE
					old_card.access = list()
					old_card.update_name()
			// Get or create personal Idris bank account (players spawn with none)
			var/dispense_acct = 0
			var/acct_is_new = FALSE
			// 1. Check in-memory economy cache (populated at startup from DB)
			var/list/econ_entry = GLOB.persistence_economy_cache["[user.ckey]|[user.real_name]"]
			if(islist(econ_entry))
				dispense_acct = econ_entry["account_number"] || 0
			// 2. Check mind.initial_account — set earlier this session
			if(!dispense_acct && user.mind && user.mind.initial_account)
				dispense_acct = user.mind.initial_account.account_number
			if(!dispense_acct)
				// Not in cache — create a fresh unique account and save to DB via economy persistence
				SSeconomy.create_and_assign_account(user)
				if(user.mind && user.mind.initial_account)
					dispense_acct = user.mind.initial_account.account_number
					acct_is_new = TRUE

			// Dispense new blank faction ID
			var/obj/item/card/id/new_card = new /obj/item/card/id(get_turf(computer))
			new_card.registered_name      = user.real_name
			new_card.assignment           = "Unassigned"
			new_card.rank                 = "Unassigned"
			new_card.employer_faction     = disp_net
			new_card.associated_account_number = dispense_acct
			new_card.update_name()
			if(istype(user, /mob/living/carbon/human))
				var/mob/living/carbon/human/H = user
				H.set_id_info(new_card)
			user.put_in_hands(new_card)
			// Register member record in DB and save account number for payroll
			SSpersistence.factionRegisterMember(user.ckey, user.real_name, disp_net)
			if(dispense_acct)
				SSpersistence.factionUpdateMemberAccount(user.ckey, disp_net, dispense_acct)
			if(acct_is_new && dispense_acct)
				// Walk the player through setting their PIN and safekeeping their account info
				tgui_alert(user,
					"A personal Idris bank account has been created.\n\nAccount Number: #[dispense_acct]\n\nYou will be asked to set a PIN next. Write this number down.",
					"Account Created", list("Set PIN"))

				var/chosen_pin = tgui_input_text(user,
					"Set a PIN for remote ATM access (4-8 digits).\nLeave blank to skip — a random PIN will be assigned.",
					"Set ATM PIN", "", max_length = 8)

				var/pin_display = "(random — set at ATM)"
				if(chosen_pin && length(chosen_pin) >= 4 && text2num(chosen_pin))
					if(user.mind?.initial_account)
						user.mind.initial_account.remote_access_pin = text2num(chosen_pin)
					pin_display = chosen_pin

				// Save account info persistently to ss13_crew_records
				var/acct_note = "Idris Account: #[dispense_acct] | PIN: [pin_display] | Use any Idris SelfServ Teller (insert ID, no PIN needed if card is present)."
				if(GLOB.config.sql_enabled && SSdbcore.Connect())
					var/datum/db_query/nq = SSdbcore.NewQuery(
						{"INSERT INTO ss13_crew_records (ckey, char_name, ccia_notes, saved_at)
						VALUES (:ckey, :name, :note, NOW())
						ON DUPLICATE KEY UPDATE ccia_notes = VALUES(ccia_notes), saved_at = NOW()"},
						list("ckey" = user.ckey, "name" = user.real_name, "note" = acct_note)
					)
					nq.Execute()
					qdel(nq)
				var/datum/record/general/R = SSrecords.find_record("name", user.real_name)
				if(istype(R))
					R.ccia_record = acct_note

				to_chat(usr, SPAN_GOOD("Welcome to [faction_name]."))
				to_chat(usr, SPAN_GOOD("[icon2html(new_card, usr)] KEEP SAFE — Account: #[dispense_acct] | PIN: [pin_display]"))
				to_chat(usr, SPAN_NOTICE("Saved in your crew record. Access at any Idris SelfServ Teller."))

			else if(already_member)
				to_chat(usr, SPAN_GOOD("Replacement [faction_name] ID dispensed. Bank account: #[dispense_acct || "none"]"))
			else
				to_chat(usr, SPAN_GOOD("You have been registered with [faction_name]. Bank account #[dispense_acct] linked to this ID."))

			var/area/dispense_area = get_area(computer)
			log_admin("[user.key] received a [disp_net] faction ID from [computer] at [dispense_area ? dispense_area.name : "unknown"].")
			. = TRUE

		// ── Faction job assign ────────────────────────────────────────────
		if("faction_assign")
			if(!computer || !can_run(user, 1) || !id_card || !computer.persistent_network)
				return
			var/assign_net = computer.persistent_network
			var/job_title = params["faction_job"]
			var/list/faction_jobs = get_faction_jobs(assign_net)
			var/list/job_data = null
			for(var/list/j in faction_jobs)
				if(j["title"] == job_title)
					job_data = j
					break
			if(!job_data)
				to_chat(usr, SPAN_WARNING("Faction job '[job_title]' not found."))
				return
			// Rank gate: operator must be officer+ and cannot assign equal/higher rank
			var/list/op_fm = get_faction_member(user.ckey, assign_net)
			var/op_rank = op_fm ? (op_fm["rank"] || 0) : 0
			var/fa_is_admin = check_rights(R_ADMIN, 0, user)
			var/assign_rank = job_data["rank"] || 0
			if(!fa_is_admin)
				if(op_rank < 1)
					to_chat(usr, SPAN_WARNING("You need officer access within [get_faction_name(assign_net)] to assign jobs."))
					return
				if(assign_rank >= op_rank)
					to_chat(usr, SPAN_WARNING("You cannot assign jobs at or above your own rank."))
					return
			remove_nt_access(id_card)
			if(islist(job_data["access"]))
				id_card.access |= job_data["access"]
			id_card.assignment = job_title
			id_card.rank       = job_title
			id_card.employer_faction = assign_net
			// Update member record with new job
			var/id_owner_ckey = null
			for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
				if(H.real_name == id_card.registered_name && H.ckey)
					id_owner_ckey = H.ckey
					break
			if(id_owner_ckey)
				SSpersistence.factionRegisterMember(id_owner_ckey, id_card.registered_name, assign_net, job_title, job_data["rank"] || 0)
				if(id_card.associated_account_number)
					SSpersistence.factionUpdateMemberAccount(id_owner_ckey, assign_net, id_card.associated_account_number)
			SSrecords.reset_manifest()
			. = TRUE

	if(id_card)
		id_card.update_name()
		. = TRUE

/datum/computer_file/program/card_mod/proc/remove_nt_access(var/obj/item/card/id/id_card)
	id_card.access -= get_access_ids(ACCESS_TYPE_STATION|ACCESS_TYPE_CENTCOM)

/datum/computer_file/program/card_mod/proc/apply_access(var/obj/item/card/id/id_card, var/list/accesses)
	id_card.access |= accesses

/datum/computer_file/program/card_mod/proc/do_print_replacement(mob/user)
	if(!computer || !can_run(user, 1))
		to_chat(user, SPAN_WARNING("You do not have access to this console."))
		return

	var/datum/record/general/R = SSrecords.find_record("name", user.real_name)
	if(!R)
		to_chat(user, SPAN_WARNING("No crew record found for [user.real_name]. Cannot print replacement."))
		return

	// Revoke existing cards
	for(var/obj/item/card/id/old_card in world)
		if(!old_card.revoked && old_card.registered_name == user.real_name)
			old_card.revoked = TRUE
			old_card.access = list()
			old_card.update_name()
			to_chat(user, SPAN_NOTICE("Previous ID ([old_card.assignment]) has been revoked."))

	// Create new card — no blank card required
	var/obj/item/card/id/new_card = new /obj/item/card/id(get_turf(computer))
	new_card.registered_name = user.real_name
	new_card.assignment = R.rank || "Civilian"
	new_card.rank = R.rank || "Civilian"
	if(computer && computer.persistent_network)
		new_card.employer_faction = computer.persistent_network
	new_card.update_name()

	var/datum/job/jobdatum
	for(var/jobtype in typesof(/datum/job))
		var/datum/job/J = new jobtype
		if(ckey(J.title) == ckey(new_card.assignment))
			jobdatum = J
			break
	if(jobdatum)
		apply_access(new_card, jobdatum.get_access(new_card.assignment))

	if(istype(user, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = user
		H.set_id_info(new_card)

	// Link existing bank account -- only mint a new one if the player has none anywhere
	var/verb_acct = 0
	var/list/verb_econ = GLOB.persistence_economy_cache["[user.ckey]|[user.real_name]"]
	if(islist(verb_econ))
		verb_acct = verb_econ["account_number"] || 0
	if(!verb_acct && user.mind && user.mind.initial_account)
		verb_acct = user.mind.initial_account.account_number
	if(!verb_acct)
		SSeconomy.create_and_assign_account(user)
		if(user.mind && user.mind.initial_account)
			verb_acct = user.mind.initial_account.account_number
	new_card.associated_account_number = verb_acct

	user.put_in_hands(new_card)
	to_chat(user, SPAN_GOOD("Replacement ID card printed. Previous card(s) revoked."))
	var/turf/ct = get_turf(computer)
	log_admin("[user.key] printed a replacement ID at [computer] ([ct?.x],[ct?.y],[ct?.z]).")

// Accessible directly without inserting a card first
/datum/computer_file/program/card_mod/verb/request_replacement_id()
	set name = "Print Replacement ID"
	set category = "IC"
	set desc = "Print a new ID card for yourself. Your old card will be revoked."
	set src in view(2)

	do_print_replacement(usr)
