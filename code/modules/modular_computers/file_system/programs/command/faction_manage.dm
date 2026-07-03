/*
 * Faction Management Terminal
 * Command-rank faction members manage jobs, pay, access codes, and faction account.
 * Officers can view. Regular members and non-members are denied data.
 * Reads computer.persistent_network for the faction context -- no per-program var.
 */

/datum/computer_file/program/faction_manage
	filename = "faction_manage"
	filedesc = "Faction Management Terminal"
	program_icon_state = "generic"
	program_key_icon_state = "blue_key"
	extended_desc = "Manage faction jobs, pay rates, and account balance."
	required_access_run = ACCESS_HEADS
	required_access_download = ACCESS_HEADS
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP
	requires_ntnet = FALSE
	size = 4
	color = LIGHT_COLOR_BLUE
	tgui_id = "FactionManagement"

/datum/computer_file/program/faction_manage/ui_data(mob/user)
	var/list/data = initial_data()
	// Normalize defensively: consoles shackled before uid normalization carry
	// raw display names in their saved worldstate
	var/net = normalize_faction_uid(computer.persistent_network)

	data["faction_uid"]        = net
	data["faction_name"]       = net ? get_faction_name(net) : null
	var/faction_registered = net && islist(GLOB.persistence_faction_cache) && (net in GLOB.persistence_faction_cache)
	data["faction_registered"] = faction_registered

	if(!net)
		data["op_rank"]        = -2  // -2 = not linked
		data["balance"]        = null
		data["jobs"]           = list()
		data["known_factions"] = list()
		return data

	var/list/op_member = user.ckey ? get_faction_member(user.ckey, net) : null
	var/op_rank = op_member ? (isnull(op_member["rank"]) ? 0 : (op_member["rank"] + 0)) : -1
	if(check_rights(R_ADMIN, 0, user))
		op_rank = 99
	data["op_rank"] = op_rank  // -1 = non-member, 0+ = member rank, 99 = admin

	if(op_rank >= 1)
		var/raw_balance = get_faction_account_balance(net)
		data["balance"] = isnull(raw_balance) ? 0 : raw_balance

		var/list/jobs_out = list()
		for(var/list/j in get_faction_jobs(net))
			var/list/acc_descs = list()
			if(islist(j["access"]))
				for(var/acc in j["access"])
					acc_descs += get_access_desc(acc)
			jobs_out += list(list(
				"title"        = j["title"],
				"rank"         = isnull(j["rank"]) ? 0 : (j["rank"] + 0),
				"pay_rate"     = isnull(j["pay_rate"]) ? 0 : (j["pay_rate"] + 0),
				"access_descs" = acc_descs
			))
		data["jobs"] = jobs_out

		var/list/factions_out = list()
		if(islist(GLOB.persistence_faction_cache))
			for(var/fuid in GLOB.persistence_faction_cache)
				if(fuid != net)
					factions_out += list(list("uid" = fuid, "name" = get_faction_name(fuid)))
		data["known_factions"] = factions_out

		// Payroll info — send elapsed deciseconds since last payroll (0 = not yet this session)
		var/list/fp_cache = GLOB.persistence_faction_cache[net]
		var/last_pay_tick = fp_cache ? (fp_cache["last_payroll_at"] || 0) : 0
		data["last_payroll"] = last_pay_tick > 0 ? max(0, world.time - last_pay_tick) : 0

		// Transaction history (last 20)
		var/list/tx_out = list()
		if(GLOB.config.sql_enabled && SSdbcore.Connect())
			var/datum/db_query/txq = SSdbcore.NewQuery(
				{"SELECT amount, reason, created_at FROM ss13_faction_transactions
				WHERE faction_uid = :uid ORDER BY id DESC LIMIT 20"},
				list("uid" = net)
			)
			txq.Execute()
			while(txq.NextRow())
				tx_out += list(list(
					"amount" = text2num(txq.item[1]) || 0,
					"reason" = txq.item[2],
					"when"   = txq.item[3]
				))
			qdel(txq)
		data["transactions"] = tx_out

		// Member roster -- used by the revoke-ID / member management panel.
		// Full roster only shown to officers+; rank-2-only actions are still
		// separately gated in ui_act regardless of what the client sends.
		var/list/members_out = list()
		if(GLOB.config.sql_enabled && SSdbcore.Connect())
			var/datum/db_query/mq = SSdbcore.NewQuery(
				"SELECT ckey, real_name, job_title, rank FROM ss13_faction_members WHERE faction_uid = :uid ORDER BY rank DESC, real_name ASC",
				list("uid" = net)
			)
			mq.Execute()
			while(mq.NextRow())
				members_out += list(list(
					"ckey"      = mq.item[1],
					"real_name" = mq.item[2],
					"job_title" = mq.item[3],
					"rank"      = text2num(mq.item[4]) || 0
				))
			qdel(mq)
		data["members"] = members_out
		data["cards_epoch"] = get_faction_cards_epoch(net)
	else
		data["balance"]        = null
		data["jobs"]           = list()
		data["known_factions"] = list()
		data["last_payroll"]   = 0
		data["members"]        = list()
		data["cards_epoch"]    = 0

	return data

/datum/computer_file/program/faction_manage/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/user = usr
	var/net = normalize_faction_uid(computer.persistent_network)
	if(!net) return

	var/list/op_member = user.ckey ? get_faction_member(user.ckey, net) : null
	var/op_rank = op_member ? (isnull(op_member["rank"]) ? 0 : (op_member["rank"] + 0)) : -1
	if(check_rights(R_ADMIN, 0, user))
		op_rank = 99

	switch(action)
		// ---- Create Faction -------------------------------------------------
		if("create_faction")
			if(op_rank < 2) return
			// Faction UID is computer.persistent_network (already set via shackling)
			var/cf_name = tgui_input_text(user, "Full faction name (e.g. 'Hub Enterprises'):", "Create Faction", max_length = 64)
			if(!cf_name) return
			var/cf_abbr = tgui_input_text(user, "Abbreviation (2-4 letters, e.g. 'HUB'):", "Create Faction", max_length = 8)
			if(!cf_abbr) return
			var/cf_balance = tgui_input_number(user, "Starting balance (credits):", "Create Faction", 0, 10000000, 0)
			if(isnull(cf_balance)) return

			if(!SSpersistence.databaseCheckConnection("faction_manage create_faction"))
				to_chat(user, SPAN_WARNING("Database connection failed."))
				return

			var/datum/db_query/cf_q1 = SSdbcore.NewQuery(
				"INSERT INTO ss13_factions (uid, name, abbreviation, is_lore) VALUES (:uid, :name, :abbr, 0)",
				list("uid" = net, "name" = cf_name, "abbr" = cf_abbr)
			)
			cf_q1.Execute()
			SSpersistence.databaseCheckQueryResult(cf_q1, "faction_manage create_faction insert")
			qdel(cf_q1)

			var/datum/db_query/cf_q2 = SSdbcore.NewQuery(
				{"INSERT INTO ss13_faction_accounts (faction_uid, balance) VALUES (:uid, :balance)
				ON DUPLICATE KEY UPDATE balance = VALUES(balance), saved_at = NOW()"},
				list("uid" = net, "balance" = cf_balance)
			)
			cf_q2.Execute()
			SSpersistence.databaseCheckQueryResult(cf_q2, "faction_manage create_faction account")
			qdel(cf_q2)

			// Update in-memory cache
			if(!islist(GLOB.persistence_faction_cache))
				GLOB.persistence_faction_cache = list()
			GLOB.persistence_faction_cache[net] = list("name" = cf_name, "abbreviation" = cf_abbr, "balance" = cf_balance)
			if(!islist(GLOB.persistence_faction_jobs_cache))
				GLOB.persistence_faction_jobs_cache = list()
			GLOB.persistence_faction_jobs_cache[net] = list()

			to_chat(user, SPAN_GOOD("Faction '[cf_name]' ([net]) created and registered."))
			log_game("[key_name(user)] created faction '[net]' ([cf_name]) via faction_manage.")

			// Register creator as a command-rank member
			SSpersistence.factionRegisterMember(user.ckey, user.real_name, net, null, 2)
			. = TRUE

		// ---- Add Job --------------------------------------------------------
		if("add_job")
			if(op_rank < 2) return
			var/fm_title = tgui_input_text(user, "Job title:", "Add Faction Job", max_length = 64)
			if(!fm_title) return
			var/fm_pay = tgui_input_number(user, "Pay rate (credits/cycle):", "Add Faction Job", 500, 50000, 0)
			if(isnull(fm_pay)) return
			var/fm_rank = tgui_input_number(user, "Rank (0=crew, 1=officer, 2=command):", "Add Faction Job", 0, 2, 0)
			if(isnull(fm_rank)) return

			// Access code loop
			var/list/fm_access = list()
			while(TRUE)
				var/fm_acc_summary = length(fm_access) ? "[length(fm_access)] codes set" : "none"
				var/fm_sub = tgui_input_list(user, "Job: [fm_title] -- Access: [fm_acc_summary]", "Set Job Access", list("Add Access Code", "Add by Region", "Remove Access Code", "Done"))
				if(!fm_sub || fm_sub == "Done") break
				if(fm_sub == "Add Access Code")
					var/list/fm_all = get_all_station_access()
					var/list/fm_addable = list()
					for(var/fma in fm_all)
						if(!(fma in fm_access))
							fm_addable["[get_access_desc(fma)] ([fma])"] = fma
					if(!length(fm_addable)) continue
					var/fm_add_pick = tgui_input_list(user, "Select access to add:", "Add Access Code", fm_addable)
					if(!fm_add_pick) continue
					fm_access += fm_addable[fm_add_pick]
				else if(fm_sub == "Add by Region")
					var/list/fm_regions = list()
					for(var/ri = 1; ri <= 7; ri++)
						fm_regions[get_region_accesses_name(ri)] = ri
					var/fm_reg_pick = tgui_input_list(user, "Select a region to add all its access codes:", "Add by Region", fm_regions)
					if(!fm_reg_pick) continue
					var/list/fm_reg_acc = get_region_accesses(fm_regions[fm_reg_pick])
					for(var/racc in fm_reg_acc)
						if(!(racc in fm_access))
							fm_access += racc
				else if(fm_sub == "Remove Access Code")
					if(!length(fm_access)) continue
					var/list/fm_removable = list()
					for(var/fmr in fm_access)
						fm_removable["[get_access_desc(fmr)] ([fmr])"] = fmr
					var/fm_rem_pick = tgui_input_list(user, "Select access to remove:", "Remove Access Code", fm_removable)
					if(!fm_rem_pick) continue
					fm_access -= fm_removable[fm_rem_pick]

			if(!SSpersistence.databaseCheckConnection("faction_manage add_job"))
				to_chat(user, SPAN_WARNING("Database connection failed."))
				return
			var/fm_access_json = length(fm_access) ? json_encode(fm_access) : null
			var/datum/db_query/fm_q = SSdbcore.NewQuery(
				{"INSERT INTO ss13_faction_jobs (faction_uid, title, access_json, pay_rate, rank)
				VALUES (:uid, :title, :access, :pay, :rank)
				ON DUPLICATE KEY UPDATE pay_rate = VALUES(pay_rate), rank = VALUES(rank), access_json = VALUES(access_json)"},
				list("uid" = net, "title" = fm_title, "access" = fm_access_json, "pay" = fm_pay, "rank" = fm_rank)
			)
			fm_q.Execute()
			SSpersistence.databaseCheckQueryResult(fm_q, "faction_manage add_job")
			qdel(fm_q)

			if(!(net in GLOB.persistence_faction_jobs_cache))
				GLOB.persistence_faction_jobs_cache[net] = list()
			GLOB.persistence_faction_jobs_cache[net] += list(list("title"=fm_title,"access"=fm_access,"pay_rate"=fm_pay,"rank"=fm_rank))
			log_game("[key_name(user)] added faction job '[fm_title]' to [net] via faction_manage.")
			. = TRUE

		// ---- Edit Job -------------------------------------------------------
		if("edit_job")
			if(op_rank < 2) return
			var/ej_title = params["job_title"]
			if(!ej_title) return

			var/list/ej_jobs = get_faction_jobs(net)
			var/list/ej_data = null
			for(var/list/ej in ej_jobs)
				if(ej["title"] == ej_title)
					ej_data = ej
					break
			if(!ej_data) return

			var/ej_sub = tgui_input_list(user, "Edit '[ej_title]':", "Edit Faction Job", list("Change Title", "Change Pay Rate", "Change Rank", "Edit Access Codes", "Cancel"))
			if(!ej_sub || ej_sub == "Cancel") return

			if(ej_sub == "Change Title")
				var/new_title = tgui_input_text(user, "New job title:", "Change Job Title", ej_title, max_length = 64)
				if(!new_title || new_title == ej_title) return

				if(!SSpersistence.databaseCheckConnection("faction_manage rename_job_title"))
					to_chat(user, SPAN_WARNING("Database connection failed."))
					return

				// Rename in ss13_faction_jobs
				var/datum/db_query/tj_q = SSdbcore.NewQuery(
					"UPDATE ss13_faction_jobs SET title = :new WHERE faction_uid = :uid AND title = :old",
					list("new" = new_title, "uid" = net, "old" = ej_title)
				)
				tj_q.Execute()
				SSpersistence.databaseCheckQueryResult(tj_q, "faction_manage rename job")
				qdel(tj_q)

				// Update any members holding the old job_title
				var/datum/db_query/tm_q = SSdbcore.NewQuery(
					"UPDATE ss13_faction_members SET job_title = :new WHERE faction_uid = :uid AND job_title = :old",
					list("new" = new_title, "uid" = net, "old" = ej_title)
				)
				tm_q.Execute()
				qdel(tm_q)

				// Update in-memory cache — rename the job entry
				ej_data["title"] = new_title
				// Update member cache entries that reference the old title
				for(var/mkey in GLOB.persistence_faction_members_cache)
					if(!findtext(mkey, "|[net]")) continue
					var/list/mdata = GLOB.persistence_faction_members_cache[mkey]
					if(mdata["job_title"] == ej_title)
						mdata["job_title"] = new_title

				to_chat(user, SPAN_GOOD("Job title changed: '[ej_title]' → '[new_title]'."))
				log_game("[key_name(user)] renamed faction job '[ej_title]' to '[new_title]' in [net] via faction_manage.")
				. = TRUE

			if(ej_sub == "Change Pay Rate")
				var/new_pay = tgui_input_number(user, "New pay rate (credits/cycle):", "Change Pay Rate", ej_data["pay_rate"] || 0, 50000, 0)
				if(isnull(new_pay)) return
				if(!SSpersistence.databaseCheckConnection("faction_manage edit_job pay"))
					to_chat(user, SPAN_WARNING("Database connection failed."))
					return
				var/datum/db_query/ep_q = SSdbcore.NewQuery(
					"UPDATE ss13_faction_jobs SET pay_rate = :pay WHERE faction_uid = :uid AND title = :title",
					list("pay" = new_pay, "uid" = net, "title" = ej_title)
				)
				ep_q.Execute()
				SSpersistence.databaseCheckQueryResult(ep_q, "faction_manage edit pay")
				qdel(ep_q)
				ej_data["pay_rate"] = new_pay
				to_chat(user, SPAN_GOOD("Pay rate for '[ej_title]' updated to [new_pay] cr/cycle."))

			else if(ej_sub == "Change Rank")
				var/new_rank = tgui_input_number(user, "New rank (0=crew, 1=officer, 2=command):", "Change Rank", ej_data["rank"] || 0, 2, 0)
				if(isnull(new_rank)) return
				if(!SSpersistence.databaseCheckConnection("faction_manage edit_job rank"))
					to_chat(user, SPAN_WARNING("Database connection failed."))
					return
				var/datum/db_query/er_q = SSdbcore.NewQuery(
					"UPDATE ss13_faction_jobs SET rank = :rank WHERE faction_uid = :uid AND title = :title",
					list("rank" = new_rank, "uid" = net, "title" = ej_title)
				)
				er_q.Execute()
				SSpersistence.databaseCheckQueryResult(er_q, "faction_manage edit rank")
				qdel(er_q)
				ej_data["rank"] = new_rank
				to_chat(user, SPAN_GOOD("Rank for '[ej_title]' updated to [new_rank]."))

			else if(ej_sub == "Edit Access Codes")
				var/list/ea_access = islist(ej_data["access"]) ? ej_data["access"].Copy() : list()
				while(TRUE)
					var/ea_summary = length(ea_access) ? "[length(ea_access)] codes set" : "none"
					var/ea_sub = tgui_input_list(user, "Job: [ej_title] -- Access: [ea_summary]", "Edit Access Codes", list("Add Access Code", "Add by Region", "Remove Access Code", "Save and Done", "Cancel"))
					if(!ea_sub || ea_sub == "Cancel") return
					if(ea_sub == "Save and Done") break
					if(ea_sub == "Add Access Code")
						var/list/ea_all = get_all_station_access()
						var/list/ea_addable = list()
						for(var/eaa in ea_all)
							if(!(eaa in ea_access))
								ea_addable["[get_access_desc(eaa)] ([eaa])"] = eaa
						if(!length(ea_addable)) continue
						var/ea_add_pick = tgui_input_list(user, "Select access to add:", "Add Access Code", ea_addable)
						if(!ea_add_pick) continue
						ea_access += ea_addable[ea_add_pick]
					else if(ea_sub == "Add by Region")
						var/list/ea_regions = list()
						for(var/ri2 = 1; ri2 <= 7; ri2++)
							ea_regions[get_region_accesses_name(ri2)] = ri2
						var/ea_reg_pick = tgui_input_list(user, "Select a region:", "Add by Region", ea_regions)
						if(!ea_reg_pick) continue
						var/list/ea_reg_acc = get_region_accesses(ea_regions[ea_reg_pick])
						for(var/eracc in ea_reg_acc)
							if(!(eracc in ea_access))
								ea_access += eracc
					else if(ea_sub == "Remove Access Code")
						if(!length(ea_access)) continue
						var/list/ea_removable = list()
						for(var/ear in ea_access)
							ea_removable["[get_access_desc(ear)] ([ear])"] = ear
						var/ea_rem_pick = tgui_input_list(user, "Select access to remove:", "Remove Access Code", ea_removable)
						if(!ea_rem_pick) continue
						ea_access -= ea_removable[ea_rem_pick]

				if(!SSpersistence.databaseCheckConnection("faction_manage edit_job access"))
					to_chat(user, SPAN_WARNING("Database connection failed."))
					return
				var/ea_json = length(ea_access) ? json_encode(ea_access) : null
				var/datum/db_query/ea_q = SSdbcore.NewQuery(
					"UPDATE ss13_faction_jobs SET access_json = :json WHERE faction_uid = :uid AND title = :title",
					list("json" = ea_json, "uid" = net, "title" = ej_title)
				)
				ea_q.Execute()
				SSpersistence.databaseCheckQueryResult(ea_q, "faction_manage edit access")
				qdel(ea_q)
				ej_data["access"] = ea_access
				to_chat(user, SPAN_GOOD("Access codes for '[ej_title]' updated ([length(ea_access)] codes)."))

			log_game("[key_name(user)] edited faction job '[ej_title]' in [net] via faction_manage.")
			. = TRUE

		// ---- Remove Job -----------------------------------------------------
		if("remove_job")
			if(op_rank < 2) return
			var/rj_title = params["job_title"]
			if(!rj_title) return
			var/rj_confirm = tgui_alert(user, "Remove job '[rj_title]' from [get_faction_name(net)]?", "Remove Job", list("Remove", "Cancel"))
			if(rj_confirm != "Remove") return
			if(!SSpersistence.databaseCheckConnection("faction_manage remove_job"))
				to_chat(user, SPAN_WARNING("Database connection failed."))
				return
			var/datum/db_query/rj_q = SSdbcore.NewQuery(
				"DELETE FROM ss13_faction_jobs WHERE faction_uid = :uid AND title = :title",
				list("uid" = net, "title" = rj_title)
			)
			rj_q.Execute()
			SSpersistence.databaseCheckQueryResult(rj_q, "faction_manage remove_job")
			qdel(rj_q)
			var/list/rj_cached = GLOB.persistence_faction_jobs_cache[net]
			if(islist(rj_cached))
				var/list/rj_new = list()
				for(var/list/rjj in rj_cached)
					if(rjj["title"] != rj_title)
						rj_new += list(rjj)
				GLOB.persistence_faction_jobs_cache[net] = rj_new
			log_game("[key_name(user)] removed faction job '[rj_title]' from [net] via faction_manage.")
			. = TRUE

		// ---- Transfer Credits (faction-to-faction) --------------------------
		if("transfer_credits")
			if(op_rank < 2) return
			var/tc_target = params["target_uid"]
			var/tc_amount = text2num(params["amount"])
			if(!tc_target || !tc_amount || tc_amount <= 0) return
			if(!(tc_target in GLOB.persistence_faction_cache))
				to_chat(user, SPAN_WARNING("Target faction '[tc_target]' not found."))
				return
			if(!faction_debit(net, tc_amount, "Transfer to [tc_target] by [user.ckey]"))
				to_chat(user, SPAN_WARNING("Insufficient funds or transfer failed."))
				return
			faction_credit(tc_target, tc_amount, "Transfer from [net] by [user.ckey]")
			to_chat(user, SPAN_GOOD("Transferred [tc_amount] credits to [get_faction_name(tc_target)]."))
			log_game("[key_name(user)] transferred [tc_amount] cr from [net] to [tc_target] via faction_manage.")
			. = TRUE

		// ---- Transfer Credits to Player ------------------------------------
		if("transfer_player")
			if(op_rank < 2) return
			var/tp_ckey = tgui_input_text(user, "Enter player ckey:", "Pay Player", max_length = 32)
			if(!tp_ckey) return
			tp_ckey = ckey(tp_ckey)
			var/tp_amount = tgui_input_number(user, "Amount to pay:", "Pay Player", 0, 1000000, 0)
			if(isnull(tp_amount) || tp_amount <= 0) return

			// Look up account number: check member cache first, then DB
			var/tp_acct = 0
			var/list/tp_member = get_faction_member(tp_ckey, net)
			if(tp_member)
				tp_acct = tp_member["account_number"] || 0
			if(!tp_acct && SSpersistence.databaseCheckConnection("transfer_player lookup"))
				var/datum/db_query/la_q = SSdbcore.NewQuery(
					"SELECT account_number FROM ss13_money_accounts WHERE ckey = :ckey ORDER BY id DESC LIMIT 1",
					list("ckey" = tp_ckey)
				)
				la_q.Execute()
				if(la_q.NextRow())
					tp_acct = text2num(la_q.item[1]) || 0
				qdel(la_q)
			if(!tp_acct)
				to_chat(user, SPAN_WARNING("No bank account found for '[tp_ckey]'. They may not have played yet."))
				return
			if(!faction_debit(net, tp_amount, "Payment to [tp_ckey] by [user.ckey]"))
				to_chat(user, SPAN_WARNING("Insufficient funds."))
				return
			SSeconomy.charge_to_account(tp_acct, "Faction Payment", "Payment from [get_faction_name(net)]", null, tp_amount)
			to_chat(user, SPAN_GOOD("Paid [tp_amount] credits to [tp_ckey]."))
			log_game("[key_name(user)] paid [tp_amount] cr from [net] to ckey '[tp_ckey]' (acct [tp_acct]) via faction_manage.")
			. = TRUE

		// ---- Manual Payroll -------------------------------------------------
		if("pay_now")
			if(op_rank < 2) return
			SSpersistence.factionPayroll(net)
			to_chat(user, SPAN_GOOD("Payroll triggered for [get_faction_name(net)]."))
			. = TRUE

		// ---- Print Faction Charge Card --------------------------------------
		if("print_charge_card")
			if(op_rank < 2) return
			var/confirm = tgui_alert(user, "Print a charge card that draws directly on [get_faction_name(net)]'s bank account? Anyone holding it can spend faction funds.", "Print Charge Card", list("Print", "Cancel"))
			if(confirm != "Print") return
			var/obj/item/spacecash/ewallet/faction_charge_card/FC = new(get_turf(computer))
			FC.faction_uid = net
			FC.name = "[get_faction_name(net)] charge card"
			FC.owner_name = get_faction_name(net)
			FC.issued_epoch = get_faction_cards_epoch(net)
			user.put_in_hands(FC)
			to_chat(user, SPAN_GOOD("Printed \a [FC]."))
			log_game("[key_name(user)] printed a faction charge card for '[net]' via faction_manage.")
			. = TRUE

		// ---- Invalidate All Charge Cards -------------------------------------
		// Bumps the faction's card epoch -- every charge card printed before
		// this moment (online, offline in someone's cryo inventory, or on the
		// floor) fails validity checks from now on. New prints pick up the
		// new epoch and work normally.
		if("invalidate_charge_cards")
			if(op_rank < 2) return
			var/confirm = tgui_alert(user, "Invalidate every charge card ever printed for [get_faction_name(net)]? This cannot be undone -- everyone holding one will need a replacement.", "Invalidate All Charge Cards", list("Invalidate", "Cancel"))
			if(confirm != "Invalidate") return
			invalidate_faction_charge_cards(net)
			to_chat(user, SPAN_GOOD("All existing [get_faction_name(net)] charge cards have been voided."))
			log_game("[key_name(user)] invalidated all charge cards for faction '[net]' via faction_manage.")
			. = TRUE

		// ---- Revoke Member ID -------------------------------------------------
		// Immediately revokes any of the target's faction ID cards currently
		// in the world, and stages a pending revoke in SQL so that if the
		// target (or their stored ID) is offline right now, the revoke still
		// applies the moment they -- or that ID -- next comes back into play.
		// See PersistentAutoSpawn() for where pending revokes get consumed.
		if("revoke_member_id")
			if(op_rank < 2) return
			var/target_ckey = ckey(params["target_ckey"])
			if(!target_ckey) return
			if(target_ckey == user.ckey)
				to_chat(user, SPAN_WARNING("You cannot revoke your own ID."))
				return
			var/list/target_member = get_faction_member(target_ckey, net)
			if(!target_member)
				to_chat(user, SPAN_WARNING("That ckey is not a member of [get_faction_name(net)]."))
				return
			var/target_name = target_member["real_name"]

			var/confirm = tgui_alert(user, "Revoke [target_name]'s [get_faction_name(net)] ID? This applies immediately if they're in the world, and will apply automatically the next time they (or their ID) show up otherwise.", "Revoke Member ID", list("Revoke", "Cancel"))
			if(confirm != "Revoke") return

			var/revoked_now = 0
			for(var/obj/item/card/id/old_card in world)
				if(!old_card.revoked && old_card.registered_name == target_name && normalize_faction_uid(old_card.employer_faction) == net)
					old_card.revoked = TRUE
					old_card.access = list()
					old_card.update_name()
					revoked_now++

			if(GLOB.config.sql_enabled && SSdbcore.Connect())
				var/datum/db_query/rq = SSdbcore.NewQuery(
					{"INSERT INTO ss13_faction_pending_revokes (faction_uid, target_ckey, target_name, issued_by_ckey)
					VALUES (:uid, :ckey, :name, :issuer)"},
					list("uid" = net, "ckey" = target_ckey, "name" = target_name, "issuer" = user.ckey)
				)
				rq.Execute()
				qdel(rq)

			to_chat(user, SPAN_GOOD("Revoked [revoked_now] live ID card[revoked_now == 1 ? "" : "s"] for [target_name]. Any offline copies will be revoked automatically when [target_name] is next restored."))
			log_game("[key_name(user)] revoked faction ID access for '[target_name]' (ckey: [target_ckey]) in faction '[net]' via faction_manage ([revoked_now] live cards caught).")
			. = TRUE
