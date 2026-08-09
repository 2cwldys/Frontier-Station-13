/datum/computer_file/program/card_mod
	filename = "cardmod"
	filedesc = "ID Card Modification Program"
	program_icon_state = "id"
	program_key_icon_state = "lightblue_key"
	extended_desc = "Program for programming employee ID cards to access parts of the station."
	// Anyone may OPEN the program (self-service replacement ID printing);
	// every card-modification action is individually gated on
	// can_run(user, 1, ACCESS_CHANGE_IDS) in ui_act -- the explicit access
	// arg matters: with required_access_run null, a bare can_run() passes
	// for everyone.
	required_access_run = null
	required_access_download = ACCESS_CHANGE_IDS
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 8
	color = LIGHT_COLOR_BLUE
	tgui_id = "IDCardModification"
	var/is_centcom = FALSE
	var/show_assignments = FALSE

/// world.time of each ckey's last MANUAL clock in/out ("toggle_clock" below
/// only) -- keyed "[ckey]|[faction_uid]", not persisted (resets each server
/// session, same as e.g. travel_pad's last_used_by_ckey). Automatic
/// clock-outs (entering cryo, being imprisoned -- persistStoreCharacter(),
/// persistence_cryo.dm) always bypass this -- they call
/// factionSetClockedIn() directly, never through this action.
GLOBAL_LIST_EMPTY(faction_clock_toggle_cooldown)
#define FACTION_CLOCK_TOGGLE_COOLDOWN (5 MINUTES)

/// world.time of each ckey's last hub law book print, keyed by ckey -- not
/// persisted (resets each server session, same as faction_clock_toggle_cooldown
/// above).
GLOBAL_LIST_EMPTY(hub_law_book_print_cooldown)
#define HUB_LAW_BOOK_PRINT_COOLDOWN (10 HOURS)

/datum/computer_file/program/card_mod/ui_data(mob/user)
	var/list/data = initial_data()

	data["station_name"] = station_name()
	data["assignments"] = show_assignments
	data["have_id_slot"] = !!computer.card_slot
	data["have_printer"] = !!computer.nano_printer
	data["authenticated"] = can_run(user, FALSE, ACCESS_CHANGE_IDS)
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

	// Faction membership state -- deliberately in ui_data(), NOT
	// ui_static_data() below, even though it's keyed off the same
	// computer.persistent_network as the faction_jobs block there. These
	// three flip the instant a player uses Dispense/Leave/Clock In-Out, and
	// static data is a send-once-then-cached channel in this tgui framework
	// (see ui_static_data()'s own doc comment, code/modules/tgui/external.dm)
	// -- putting live-changing booleans there means the client never learns
	// they changed until the program is fully closed and reopened.
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : ""
	if(net)
		var/already_member = user.ckey ? !!get_faction_member(user.ckey, net) : FALSE
		data["can_dispense_faction_id"] = !already_member
		data["can_leave_faction"] = already_member
		var/list/clock_fmember = already_member ? get_faction_member(user.ckey, net) : null
		data["clocked_in"] = clock_fmember ? !!clock_fmember["clocked_in"] : FALSE
	else
		data["can_dispense_faction_id"] = FALSE
		data["can_leave_faction"] = FALSE
		data["clocked_in"] = FALSE

	var/hub_cooldown_last = user.ckey ? GLOB.hub_law_book_print_cooldown[user.ckey] : 0
	var/hub_cooldown_remaining = hub_cooldown_last ? (HUB_LAW_BOOK_PRINT_COOLDOWN - (world.time - hub_cooldown_last)) : 0
	data["can_print_hub_laws"] = hub_cooldown_remaining <= 0
	data["hub_law_cooldown_text"] = hub_cooldown_remaining > 0 ? DisplayTimeText(hub_cooldown_remaining) : null

	return data

/datum/computer_file/program/card_mod/ui_static_data(mob/user)
	var/list/data = list()
	// Faction jobs — populated when this console is networked to a faction
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : ""
	if(net)
		var/list/faction_jobs_formatted = list()
		for(var/list/j in get_faction_jobs(net))
			faction_jobs_formatted += list(list(
				"job"      = j["title"],
				"rank"     = j["rank"] || 0,
				"pay_rate" = j["pay_rate"] || 0
			))
		data["faction_jobs"]    = faction_jobs_formatted
		data["faction_network"] = net
		data["faction_name"]    = get_faction_name(net)
		// Officer field: rank >= 1 in this faction, or admin -- gates job assignment UI
		var/mob/ui_user = usr
		var/list/op_fmember = (ui_user && ui_user.ckey) ? get_faction_member(ui_user.ckey, net) : null
		data["faction_officer"] = (op_fmember && (op_fmember["rank"] || 0) >= 1) || check_rights(R_ADMIN, 0, ui_user)
	else
		data["faction_jobs"]    = list()
		data["faction_network"] = null
		data["faction_name"]    = null
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
			if(computer?.nano_printer && can_run(user, 1, ACCESS_CHANGE_IDS)) //This option should never be called if there is no printer
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
			if(computer && can_run(user, 1, ACCESS_CHANGE_IDS))
				id_card.assignment = "Suspended"
				remove_nt_access(id_card)
				callHook("suspend_employee", list(id_card))
				. = TRUE

		if("edit")
			if(computer && can_run(user, 1, ACCESS_CHANGE_IDS))
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
			if(computer && can_run(user, 1, ACCESS_CHANGE_IDS) && id_card)
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
				var/assign_id_net = computer ? normalize_faction_uid(computer.persistent_network) : ""
				if(assign_id_net)
					id_card.employer_faction = assign_id_net
					// See print_replacement/do_print_replacement's identical fix --
					// this action only stamped employer_faction, it never
					// registered the person as an actual faction member, so
					// GetFactionAccess()/can_configure_faction_shackle() (both
					// ckey-based) always saw them as a non-member no matter how
					// much generic access the card had. Skip if already a member
					// so a routine job reassignment never resets an existing
					// officer/command rank back to 0.
					var/assign_owner_ckey = null
					for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
						if(H.real_name == id_card.registered_name && H.ckey)
							assign_owner_ckey = H.ckey
							break
					if(assign_owner_ckey && !get_faction_member(assign_owner_ckey, assign_id_net))
						SSpersistence.factionRegisterMember(assign_owner_ckey, id_card.registered_name, assign_id_net, id_card.assignment, 0)

				SSrecords.reset_manifest()
				callHook("reassign_employee", list(id_card))
				. = TRUE

		if("access")
			if(isnum(params["allowed"]) && computer && can_run(user, 1, ACCESS_CHANGE_IDS))
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

			// Refuse outright (before anything is revoked) if this would join
			// them to a DIFFERENT faction than the one they already belong to
			// -- single-faction membership. Reprinting for your OWN faction's
			// console is unaffected (get_faction_member() already matches).
			var/repl_net = computer ? normalize_faction_uid(computer.persistent_network) : ""
			if(repl_net && !get_faction_member(user.ckey, repl_net))
				var/repl_existing_faction = persistence_get_player_faction(user.ckey)
				if(repl_existing_faction && normalize_faction_uid(repl_existing_faction) != repl_net)
					to_chat(usr, SPAN_WARNING("You are already a part of a faction, leave that one first before you can join this one!"))
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
			if(repl_net)
				new_card.employer_faction = repl_net
				// A replacement card only STAMPS employer_faction -- it never
				// registered the person as an actual faction member, so
				// GetFactionAccess()/can_configure_faction_shackle() (both
				// resolved by ckey, not anything on the card) always saw them
				// as a non-member and refused faction-tagged doors/the beacon
				// no matter how much generic access the card had. Register
				// them now if they aren't already a member -- skip entirely
				// if they are, so an existing officer/command rank is never
				// silently reset back to 0 by a routine card reprint.
				if(!get_faction_member(user.ckey, repl_net))
					SSpersistence.factionRegisterMember(user.ckey, user.real_name, repl_net, new_card.assignment, 0)
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
				// The console's faction (set by the faction tagger / beacon) IS
				// this ID's employer, so make it the holder's employer too.
				// set_id_info() below copies the human's employer_faction onto
				// the card -- as do its ~15 other callers -- so syncing the mob
				// here is what keeps card, mob and crew records agreeing,
				// instead of the card being silently stamped back to the
				// character's prefs faction on the next call.
				if(repl_net)
					H.employer_faction = repl_net
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
			// 3. Only if still nothing, create a brand-new account -- capture the
			// return value directly (see dispense_faction_id's identical fix
			// above) instead of re-deriving via user.mind.initial_account,
			// which silently left the card's associated_account_number at 0
			// whenever user.mind was null at this exact moment.
			if(!rep_acct)
				var/datum/money_account/new_acct = SSeconomy.create_and_assign_account(user)
				if(new_acct)
					rep_acct = new_acct.account_number
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

			// Resolve the live account datum regardless of which step above found
			// it -- the cache-lookup path (step 1) never touches
			// user.mind.initial_account, so that var can't be trusted as "the
			// account we just resolved" the way the fresh-create path could.
			var/datum/money_account/rep_account = rep_acct ? SSeconomy.get_account(rep_acct) : null
			// Fires the first time EVER a player sees this popup, not just when
			// the account itself happens to be brand new -- most accounts are
			// actually minted silently at roundstart (job.dm's setup_account()),
			// so gating this on rep_is_new alone almost never actually showed it.
			var/rep_show_intro = rep_account && !rep_account.intro_shown
			if(rep_show_intro)
				rep_account.intro_shown = TRUE
				tgui_alert(user, "[rep_is_new ? "A new personal Idris bank account has been created for you." : "This ID has been linked to your existing personal Idris bank account."]\n\nAccount Number: #[rep_acct]\n\nYou will be asked to set a PIN next. Write this number down.", "Idris Bank Account", list("Set PIN"))
				var/rep_pin = tgui_input_text(user, "Set a PIN for ATM access (4-8 digits). Leave blank to skip.", "Set ATM PIN", "", max_length = 8)
				var/pin_display = "(random -- set at ATM)"
				if(rep_pin && length(rep_pin) >= 4 && text2num(rep_pin))
					rep_account.remote_access_pin = text2num(rep_pin)
					pin_display = rep_pin
				SSpersistence.economySaveAccountNow(rep_account)
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
			var/disp_net = normalize_faction_uid(computer.persistent_network)
			var/faction_name = get_faction_name(disp_net)
			// If already a member, reprint instead
			var/already_member = !!get_faction_member(user.ckey, disp_net)
			// Refuse joining a DIFFERENT faction than the one already belonged
			// to -- single-faction membership, same guard as print_replacement.
			if(!already_member)
				var/disp_existing_faction = persistence_get_player_faction(user.ckey)
				if(disp_existing_faction && normalize_faction_uid(disp_existing_faction) != disp_net)
					to_chat(user, SPAN_WARNING("You are already a part of a faction, leave that one first before you can join this one!"))
					return
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
				// Not in cache — create a fresh unique account and save to DB via
				// economy persistence. Capture the return value directly instead
				// of re-deriving it via user.mind.initial_account -- that assign
				// only happens inside create_and_assign_account()'s own
				// `if(mob.mind)` guard, so a null mind at this exact moment used
				// to leave the card stamped with associated_account_number = 0
				// (a real account existed, just never linked to the card) --
				// silently dead for any future payment, including vending.
				var/datum/money_account/new_acct = SSeconomy.create_and_assign_account(user)
				if(new_acct)
					dispense_acct = new_acct.account_number
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
				// See print_replacement above -- the console's faction is the
				// employer, so sync the mob before set_id_info() copies it.
				if(disp_net)
					H.employer_faction = disp_net
				H.set_id_info(new_card)
			user.put_in_hands(new_card)
			// Register member record in DB and save account number for payroll
			SSpersistence.factionRegisterMember(user.ckey, user.real_name, disp_net)
			if(dispense_acct)
				SSpersistence.factionUpdateMemberAccount(user.ckey, disp_net, dispense_acct)
			// Resolve the live account datum regardless of which step above found
			// it -- the cache-lookup path (step 1) never touches
			// user.mind.initial_account, so that var can't be trusted as "the
			// account we just resolved" the way the fresh-create path could.
			var/datum/money_account/acct = dispense_acct ? SSeconomy.get_account(dispense_acct) : null
			// Fires the first time EVER a player sees this popup, not just when
			// the account itself happens to be brand new -- most accounts are
			// actually minted silently at roundstart (job.dm's setup_account()),
			// so gating this on acct_is_new alone almost never actually showed it.
			var/show_intro = acct && !acct.intro_shown
			if(show_intro)
				acct.intro_shown = TRUE
				// Walk the player through setting their PIN and safekeeping their account info
				tgui_alert(user,
					"[acct_is_new ? "A new personal Idris bank account has been created for you." : "This ID has been linked to your existing personal Idris bank account."]\n\nAccount Number: #[dispense_acct]\n\nYou will be asked to set a PIN next. Write this number down.",
					"Idris Bank Account", list("Set PIN"))

				var/chosen_pin = tgui_input_text(user,
					"Set a PIN for remote ATM access (4-8 digits).\nLeave blank to skip — a random PIN will be assigned.",
					"Set ATM PIN", "", max_length = 8)

				var/pin_display = "(random — set at ATM)"
				if(chosen_pin && length(chosen_pin) >= 4 && text2num(chosen_pin))
					acct.remote_access_pin = text2num(chosen_pin)
					pin_display = chosen_pin
				SSpersistence.economySaveAccountNow(acct)

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

		// ── Leave faction (self-service, direct inverse of dispense above) ──
		// Revokes the user's own live faction ID(s) and erases their
		// membership record -- no rank restriction, anyone can leave their
		// own faction. Notifies the rest of the faction the same way an
		// alliance event does (notify_faction_members(), persistence_factions.dm).
		if("leave_faction")
			if(!computer || !computer.persistent_network)
				return
			var/leave_net = normalize_faction_uid(computer.persistent_network)
			if(!user.ckey || !user.real_name)
				return
			if(!get_faction_member(user.ckey, leave_net))
				to_chat(user, SPAN_WARNING("You aren't a member of [get_faction_name(leave_net)]."))
				return

			var/leave_confirm = tgui_alert(user, "Leave [get_faction_name(leave_net)]? Your faction ID access will be revoked and your membership record erased. You would need to be re-issued an ID to rejoin.", "Leave Faction", list("Leave", "Cancel"))
			if(leave_confirm != "Leave") return

			if(!SSpersistence.factionRemoveMember(user.ckey, leave_net))
				to_chat(user, SPAN_WARNING("Failed to leave -- database error. Your ID access is unchanged. Try again shortly."))
				return

			for(var/obj/item/card/id/old_card in world)
				if(!old_card.revoked && old_card.registered_name == user.real_name && normalize_faction_uid(old_card.employer_faction) == leave_net)
					old_card.revoked = TRUE
					old_card.access = list()
					old_card.update_name()
			notify_faction_members(leave_net, SPAN_WARNING("[user.real_name] has left [get_faction_name(leave_net)]."))

			to_chat(user, SPAN_GOOD("You have left [get_faction_name(leave_net)]."))
			log_game("[key_name(user)] left faction '[leave_net]' via ID Card Modification.")
			. = TRUE

		// ── Clock in / out (gates factionPayroll(), persistence_factions.dm) ──
		// No confirm dialog -- fully reversible, routine action, unlike
		// Leave Faction above. Broadcasts to the rest of the faction the same
		// way an alliance event does; the automatic clock-out on entering
		// cryo (persistStoreCharacter(), persistence_cryo.dm) deliberately
		// stays silent since that's a system side-effect, not a deliberate
		// clock-out.
		if("toggle_clock")
			if(!computer || !computer.persistent_network)
				return
			var/clock_net = normalize_faction_uid(computer.persistent_network)
			var/list/clock_member = user.ckey ? get_faction_member(user.ckey, clock_net) : null
			if(!clock_member)
				to_chat(user, SPAN_WARNING("You aren't a member of [get_faction_name(clock_net)]."))
				return
			var/clock_cooldown_key = "[user.ckey]|[clock_net]"
			var/clock_last_toggle = GLOB.faction_clock_toggle_cooldown[clock_cooldown_key]
			if(clock_last_toggle && (world.time - clock_last_toggle < FACTION_CLOCK_TOGGLE_COOLDOWN))
				to_chat(user, SPAN_WARNING("You can't clock [clock_member["clocked_in"] ? "out" : "in"] again so soon -- try again in [DisplayTimeText(FACTION_CLOCK_TOGGLE_COOLDOWN - (world.time - clock_last_toggle))]."))
				return
			var/new_clock_state = !clock_member["clocked_in"]
			if(!SSpersistence.factionSetClockedIn(user.ckey, clock_net, new_clock_state))
				to_chat(user, SPAN_WARNING("Failed to clock [new_clock_state ? "in" : "out"] -- database error. Try again shortly."))
				return
			// Cooldown only actually starts on a confirmed success -- a failed
			// attempt above shouldn't cost the player 5 minutes for nothing.
			GLOB.faction_clock_toggle_cooldown[clock_cooldown_key] = world.time
			notify_faction_members(clock_net, SPAN_NOTICE("[user.real_name] has clocked [new_clock_state ? "in" : "out"] with [get_faction_name(clock_net)]."))
			to_chat(user, SPAN_GOOD(new_clock_state ? "You clock in with [get_faction_name(clock_net)]." : "You clock out from [get_faction_name(clock_net)]."))
			log_game("[key_name(user)] clocked [new_clock_state ? "in" : "out"] with faction '[clock_net]' via ID Card Modification.")
			. = TRUE

		// ── Print hub law book (self-service, 1 per 10 hours) ─────────────
		if("print_hub_laws")
			if(!computer || !user.ckey)
				return
			var/hub_cooldown_last = GLOB.hub_law_book_print_cooldown[user.ckey]
			if(hub_cooldown_last && (world.time - hub_cooldown_last < HUB_LAW_BOOK_PRINT_COOLDOWN))
				to_chat(user, SPAN_WARNING("You can't print another hub law book yet -- try again in [DisplayTimeText(HUB_LAW_BOOK_PRINT_COOLDOWN - (world.time - hub_cooldown_last))]."))
				return
			GLOB.hub_law_book_print_cooldown[user.ckey] = world.time
			var/obj/item/book/hub_laws/new_book = new(get_turf(computer))
			user.put_in_hands(new_book)
			to_chat(user, SPAN_GOOD("You print a hub law book."))
			log_game("[key_name(user)] printed a hub law book via [computer].")
			. = TRUE

		// ── Faction job assign ────────────────────────────────────────────
		if("faction_assign")
			if(!computer || !can_run(user, 1, ACCESS_CHANGE_IDS) || !id_card || !computer.persistent_network)
				return
			var/assign_net = normalize_faction_uid(computer.persistent_network)
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
	// Self-service: no access requirement -- identity is verified against
	// the crew record below, same as the tgui print_replacement action.
	if(!computer)
		return

	var/datum/record/general/R = SSrecords.find_record("name", user.real_name)
	if(!R)
		to_chat(user, SPAN_WARNING("No crew record found for [user.real_name]. Cannot print replacement."))
		return

	// Refuse outright (before anything is revoked) if this would join them
	// to a DIFFERENT faction than the one they already belong to -- see
	// print_replacement's identical guard above.
	var/verb_repl_net = computer ? normalize_faction_uid(computer.persistent_network) : ""
	if(verb_repl_net && !get_faction_member(user.ckey, verb_repl_net))
		var/verb_existing_faction = persistence_get_player_faction(user.ckey)
		if(verb_existing_faction && normalize_faction_uid(verb_existing_faction) != verb_repl_net)
			to_chat(user, SPAN_WARNING("You are already a part of a faction, leave that one first before you can join this one!"))
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
	if(verb_repl_net)
		new_card.employer_faction = verb_repl_net
		// See print_replacement's identical fix -- a replacement card only
		// stamps employer_faction, it never registered the person as an
		// actual faction member, so GetFactionAccess()/
		// can_configure_faction_shackle() (both ckey-based) always saw them
		// as a non-member. Skip if already a member so a routine reprint
		// never resets an existing officer/command rank back to 0.
		if(!get_faction_member(user.ckey, verb_repl_net))
			SSpersistence.factionRegisterMember(user.ckey, user.real_name, verb_repl_net, new_card.assignment, 0)
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
		// See print_replacement above -- the console's faction is the employer,
		// so sync the mob before set_id_info() copies it.
		if(verb_repl_net)
			H.employer_faction = verb_repl_net
		H.set_id_info(new_card)

	// Link existing bank account -- only mint a new one if the player has none anywhere
	var/verb_acct = 0
	var/verb_is_new = FALSE
	var/list/verb_econ = GLOB.persistence_economy_cache["[user.ckey]|[user.real_name]"]
	if(islist(verb_econ))
		verb_acct = verb_econ["account_number"] || 0
	if(!verb_acct && user.mind && user.mind.initial_account)
		verb_acct = user.mind.initial_account.account_number
	if(!verb_acct)
		// Capture the return value directly (see dispense_faction_id's
		// identical fix) instead of re-deriving via user.mind.initial_account,
		// which silently left associated_account_number at 0 whenever
		// user.mind was null at this exact moment.
		var/datum/money_account/new_acct = SSeconomy.create_and_assign_account(user)
		if(new_acct)
			verb_acct = new_acct.account_number
			verb_is_new = TRUE
	new_card.associated_account_number = verb_acct

	// Resolve the live account datum regardless of which step above found it,
	// and show the same one-time account-info/PIN-setup popup the tgui
	// print_replacement action has -- this verb is just another entry point
	// to the same self-service replacement flow, so it should onboard a
	// player exactly the same way (most accounts are actually minted
	// silently at roundstart, job.dm's setup_account(), so this can't be
	// gated on verb_is_new alone or it'll almost never show).
	var/datum/money_account/verb_account = verb_acct ? SSeconomy.get_account(verb_acct) : null
	if(verb_account && !verb_account.intro_shown)
		verb_account.intro_shown = TRUE
		tgui_alert(user, "[verb_is_new ? "A new personal Idris bank account has been created for you." : "This ID has been linked to your existing personal Idris bank account."]\n\nAccount Number: #[verb_acct]\n\nYou will be asked to set a PIN next. Write this number down.", "Idris Bank Account", list("Set PIN"))
		var/verb_pin = tgui_input_text(user, "Set a PIN for ATM access (4-8 digits). Leave blank to skip.", "Set ATM PIN", "", max_length = 8)
		var/verb_pin_display = "(random -- set at ATM)"
		if(verb_pin && length(verb_pin) >= 4 && text2num(verb_pin))
			verb_account.remote_access_pin = text2num(verb_pin)
			verb_pin_display = verb_pin
		SSpersistence.economySaveAccountNow(verb_account)
		var/verb_note = "Idris Account: #[verb_acct] | PIN: [verb_pin_display] | Insert ID at any Idris ATM."
		if(GLOB.config.sql_enabled && SSdbcore.Connect())
			var/datum/db_query/vn_q = SSdbcore.NewQuery(
				{"INSERT INTO ss13_crew_records (ckey, char_name, ccia_notes, saved_at)
				VALUES (:ckey, :name, :note, NOW())
				ON DUPLICATE KEY UPDATE ccia_notes = VALUES(ccia_notes), saved_at = NOW()"},
				list("ckey" = user.ckey, "name" = user.real_name, "note" = verb_note)
			)
			vn_q.Execute()
			qdel(vn_q)
		R.ccia_record = verb_note
		to_chat(user, SPAN_GOOD("[icon2html(new_card, user)] KEEP SAFE -- Account: #[verb_acct] | PIN: [verb_pin_display]"))
		to_chat(user, SPAN_NOTICE("Saved in your crew record. Access at any Idris SelfServ Teller."))
	else if(verb_acct)
		to_chat(user, SPAN_NOTICE("Existing bank account #[verb_acct] linked to this ID."))

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

/*
 * Hub Law Book -- printed via the ID Card Modification program's own Hub
 * Laws category (print_hub_laws above), 1 per ckey every
 * HUB_LAW_BOOK_PRINT_COOLDOWN. Read-only (unique = TRUE blocks the base
 * /obj/item/book's own pen-edit action) and always shows the CURRENT
 * GLOB.hub_law_text (persistence.dm), not whatever it was at print time --
 * every copy in circulation reflects the same live, admin-edited text.
 */
/obj/item/book/hub_laws
	name = "hub law book"
	desc = "A slim, blue-bound book listing the laws and regulations of the Hub."
	color = "#2255aa"
	unique = TRUE
	title = "Hub Laws"
	author = "The Hub Authority"
	// Every copy in circulation shows the same live GLOB.hub_law_text, not
	// content actually stored on this instance -- wearing/breaking it (or
	// needing repair) would mean nothing anyway, so don't bother tracking it.
	degrades_with_use = FALSE

	// Mirrors /obj/effect/decal/cleanable's own claim-tracking vars, same as
	// every other cleanbot litter type (shards.dm, cigs_lighters.dm,
	// ammunition.dm) -- /obj/item has neither var declared generically, so
	// without these, cleanbot.dm's I.vars["clean_marked"]/["being_cleaned"]
	// writes silently no-op (you can't set an undeclared var through the
	// vars[] accessor), every read back comes back null, and
	// handle_target()'s very first check reads that null as "claimed by
	// something else" and immediately abandons the target -- every time,
	// before ever pathing to or cleaning one.
	var/being_cleaned = FALSE
	var/datum/weakref/clean_marked = null

/obj/item/book/hub_laws/attack_self(mob/user)
	if(!GLOB.hub_law_text)
		to_chat(user, "This book is completely blank!")
		return
	// nl2br() (__HELPERS/text.dm) -- raw \n does nothing in HTML, it just
	// collapses to whitespace, so admin-typed line breaks (modify_hub_laws(),
	// persistence_factions.dm) were silently lost the instant this got
	// dropped into the book's browse() window.
	user << browse(HTML_SKELETON("<TT><I>Penned by [author].</I></TT> <BR>" + nl2br(GLOB.hub_law_text)), "window=book")
	user.visible_message("[user] opens a book titled \"[title]\" and begins reading intently.")
	playsound(loc, 'sound/items/bureaucracy/bookopen.ogg', 50, TRUE)
	onclose(user, "book")
