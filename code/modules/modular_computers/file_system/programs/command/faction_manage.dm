/*
 * Faction Management Terminal
 * Command-rank faction members manage jobs, pay, access codes, and faction account.
 * Officers can view. Regular members and non-members are denied data.
 * Reads computer.persistent_network for the faction context -- no per-program var.
 *
 * Two actions are open to anyone regardless of membership: "start_founding"
 * and "support_founding" -- self-service faction founding, in one of two
 * tiers (params["tier"] == "company" or "full"). Founding is a global
 * program feature, independent of the current console's own
 * shackle/registration state -- it's visible and usable from ANY console
 * (see ui_data()'s "petitions" list), not just one shackled to a brand-new
 * unregistered UID. Starting a petition costs nothing up front; it takes
 * that tier's required supporter count (see faction_founding_required_
 * supporters(), persistence_factions.dm) of other distinct players
 * consenting (tap with a handheld running this program, or self-consent at
 * an open terminal) before it actually creates the faction, at which point
 * that tier's cost (faction_founding_cost()) is charged to the founder and
 * becomes the new faction's starting balance, and a bearer faction master
 * card (cards_ids.dm) is printed. The ONLY other difference between tiers:
 * a full-tier faction gets unrestricted cargo ordering across every
 * category (FACTION_CARGO_CATEGORY_ALL) on success, permanently -- a
 * Company stays limited to the single category it picks during founding,
 * same as every faction already works under FACTION_CARGO_SPECIALIZATION.
 */

// FACTION_CREATION_COST/FACTION_FOUNDING_REQUIRED_SUPPORTERS (full tier) and
// FACTION_CREATION_COST_COMPANY/FACTION_FOUNDING_REQUIRED_SUPPORTERS_COMPANY
// (company tier) are declared in code/__DEFINES/misc.dm --
// persistence_factions.dm (which also needs them, for the founding sweep)
// is #included earlier in the .dme than this file.

/// "Pay Dividends" can never distribute more than this fraction of the
/// treasury's current balance -- always leaves at least 1% behind so a
/// dividend payout can never itself re-bankrupt the company (confirmed with
/// the user -- simpler than a fixed-credit reserve and scales with any
/// faction's actual wealth).
#define FACTION_DIVIDEND_MAX_FRACTION 0.99

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
	// Without this, "List on Stock Exchange" (and the Pay Dividends/Print
	// Share Certificate buttons that replace it) can go stale: if the
	// faction gets listed via a different session/console while this one's
	// already open, this window keeps showing the old button, clickable,
	// until something else forces a refresh -- server-side list_on_exchange
	// already refuses a double-listing, but the button itself should reflect
	// reality promptly instead of looking usable when it isn't. Same fix,
	// same reasoning as cargo_exports.dm's own ui_auto_update.
	ui_auto_update = TRUE

	/// Which founding petition tap_consent() canvasses for -- set via the
	/// "select_tap_target" action, since founding is no longer tied to this
	/// console's own persistent_network.
	var/tap_target_uid = null

/datum/computer_file/program/faction_manage/ui_data(mob/user)
	var/list/data = initial_data()
	// Normalize defensively: consoles shackled before uid normalization carry
	// raw display names in their saved worldstate
	var/net = normalize_faction_uid(computer.persistent_network)

	data["faction_uid"]        = net
	data["faction_name"]       = net ? get_faction_name(net) : null
	var/faction_registered = net && islist(GLOB.persistence_faction_cache) && (net in GLOB.persistence_faction_cache)
	data["faction_registered"] = faction_registered

	// Founding is a global program feature, independent of this console's
	// own shackle/registration state -- computed and returned unconditionally
	// so it's visible from ANY console, including an already-registered one
	// (e.g. Hub), not just a console shackled to a brand-new unregistered UID.
	data["faction_creation_enabled"] = GLOB.faction_creation_enabled
	data["founding_required"] = FACTION_FOUNDING_REQUIRED_SUPPORTERS
	data["founding_required_company"] = FACTION_FOUNDING_REQUIRED_SUPPORTERS_COMPANY
	data["petitions"] = list()
	if(islist(GLOB.persistence_faction_founding_petitions))
		for(var/target_uid in GLOB.persistence_faction_founding_petitions)
			var/list/p = GLOB.persistence_faction_founding_petitions[target_uid]
			data["petitions"] += list(list(
				"target_uid"        = target_uid,
				"founder_name"      = p["founder_name"],
				"faction_name"      = p["faction_name"],
				"abbreviation"      = p["abbreviation"],
				"supporter_count"   = length(p["supporters"]),
				"is_founder"        = (user.ckey == p["founder_ckey"]),
				"already_supported" = (user.ckey in p["supporters"]),
				"is_company"        = p["is_company"],
				"required_supporters" = faction_founding_required_supporters(p["is_company"])
			))
			// Opportunistic retry -- if the threshold was already met but a
			// prior finalize attempt failed (founder was broke/offline),
			// retry on every poll from the founder. Piggybacks on
			// ui_auto_update instead of needing a dedicated "Finalize" button.
			// The real safety net is SSpersistence's periodic founding sweep
			// (persistence_factions.dm, forceSaveAll()) -- this just makes it
			// instant while the founder happens to be looking at the screen.
			if(user.ckey == p["founder_ckey"] && length(p["supporters"]) >= faction_founding_required_supporters(p["is_company"]))
				SSpersistence.tryFinalizeFounding(target_uid)

	if(!net)
		data["op_rank"]        = -2  // -2 = not linked
		data["balance"]        = null
		data["jobs"]           = list()
		data["known_factions"] = list()
		return data

	var/op_rank = get_effective_faction_rank(user, net)
	// Whoever holds the single highest (or tied-highest) granted shareholder
	// percentage is this faction's "owner and CEO" -- full command-rank
	// access, computed live every call, never persisted as an actual job/
	// rank row. Never downgrades an existing rank-2 job holder or admin, and
	// doesn't require the CEO to already be a registered member.
	var/is_ceo = is_faction_ceo(net, user.ckey, user.real_name)
	if(op_rank < 2 && is_ceo)
		op_rank = 2
	data["op_rank"] = op_rank  // -1 = non-member, 0+ = member rank, 99 = admin
	data["is_ceo"] = is_ceo

	if(op_rank >= 1)
		var/raw_balance = get_faction_account_balance(net)
		data["balance"] = isnull(raw_balance) ? 0 : raw_balance

#ifdef FACTION_CARGO_SPECIALIZATION
		var/allowed_category = get_faction_allowed_cargo_category(net)
		if(allowed_category == FACTION_CARGO_CATEGORY_ALL)
			data["allowed_cargo_category"] = "All Categories"
		else
			var/singleton/cargo_category/allowed_cc = allowed_category ? SScargo.cargo_categories[allowed_category] : null
			data["allowed_cargo_category"] = allowed_cc ? allowed_cc.display_name : null
		var/list/cargo_category_options = list()
		for(var/cat_name in SScargo.cargo_categories)
			var/singleton/cargo_category/cc = SScargo.cargo_categories[cat_name]
			cargo_category_options += cc.display_name
		data["cargo_category_options"] = cargo_category_options
		data["cargo_category_cooldown_remaining"] = get_faction_cargo_category_cooldown_remaining(net)
#endif //FACTION_CARGO_SPECIALIZATION

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

#ifdef FACTION_ALLIANCES
		var/list/allies_out = list()
		if(islist(GLOB.persistence_faction_alliances[net]))
			for(var/allied_uid in GLOB.persistence_faction_alliances[net])
				allies_out += list(list("uid" = allied_uid, "name" = get_faction_name(allied_uid)))
		data["allies"] = allies_out

		var/list/incoming_out = list()
		var/list/outgoing_out = list()
		if(islist(GLOB.persistence_faction_alliance_requests))
			for(var/list/req in GLOB.persistence_faction_alliance_requests)
				if(req["target"] == net)
					incoming_out += list(list("uid" = req["proposer"], "name" = get_faction_name(req["proposer"])))
				else if(req["proposer"] == net)
					outgoing_out += list(list("uid" = req["target"], "name" = get_faction_name(req["target"])))
		data["incoming_alliance_requests"] = incoming_out
		data["outgoing_alliance_requests"] = outgoing_out

		// Propose-target picker -- known_factions minus already-allied and
		// already-pending-either-direction.
		var/list/alliance_targets = list()
		for(var/list/kf in factions_out)
			var/kf_uid = kf["uid"]
			if(factions_are_allied(net, kf_uid))
				continue
			var/already_pending = FALSE
			if(islist(GLOB.persistence_faction_alliance_requests))
				for(var/list/req2 in GLOB.persistence_faction_alliance_requests)
					if((req2["proposer"] == net && req2["target"] == kf_uid) || (req2["proposer"] == kf_uid && req2["target"] == net))
						already_pending = TRUE
						break
			if(already_pending)
				continue
			alliance_targets += list(kf)
		data["alliance_targets"] = alliance_targets
#endif //FACTION_ALLIANCES

		// Payroll info — send elapsed deciseconds since last payroll (0 = not yet this session)
		var/list/fp_cache = GLOB.persistence_faction_cache[net]
		var/last_pay_tick = fp_cache ? (fp_cache["last_payroll_at"] || 0) : 0
		data["last_payroll"] = last_pay_tick > 0 ? max(0, world.time - last_pay_tick) : 0
		data["auto_payroll"] = get_faction_auto_payroll(net)

		// Stock exchange listing status -- gates "List on Stock Exchange"
		// (hidden/disabled once already listed) and "Pay Dividends" (only
		// shown once listed) in the TGUI. See get_faction_stock_company()
		// (persistence_stock_market.dm).
		var/datum/stock_company/fm_stock = get_faction_stock_company(net)
		data["stock_listed"] = !isnull(fm_stock)
		data["stock_ticker"] = fm_stock ? fm_stock.ticker : null
		data["stock_player_shares"] = fm_stock ? stock_market_total_player_shares(fm_stock.company_id) : 0

		// Shareholders -- percentage-of-company equity, distinct from the
		// stockholders above. Only ever non-empty once listed (see
		// "list_on_exchange"'s 100%-seed and "print_share_certificate").
		var/list/shareholders_out = list()
		var/list/fm_shareholders = GLOB.persistence_faction_shareholders_cache[net]
		if(islist(fm_shareholders))
			for(var/list/sh in fm_shareholders)
				shareholders_out += list(list("char_name" = sh["char_name"], "percent" = sh["percent"]))
		data["shareholders"] = shareholders_out
		data["shareholder_total_percent"] = faction_shareholder_total_percent(net)

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
				"SELECT ckey, real_name, job_title, rank, clocked_in FROM ss13_faction_members WHERE faction_uid = :uid ORDER BY rank DESC, real_name ASC",
				list("uid" = net)
			)
			mq.Execute()
			while(mq.NextRow())
				members_out += list(list(
					"ckey"       = mq.item[1],
					"real_name"  = mq.item[2],
					"job_title"  = mq.item[3],
					"rank"       = text2num(mq.item[4]) || 0,
					"clocked_in" = !!text2num(mq.item[5])
				))
			qdel(mq)
		data["members"] = members_out
		data["cards_epoch"] = get_faction_cards_epoch(net)
		data["is_founder"] = (user.ckey == get_faction_founder_ckey(net))
		data["master_card_lost"] = get_faction_master_card_lost(net)
		// Mirrors print_master_card's ui_act() gate exactly, computed
		// server-side so the TGUI doesn't need to re-derive the four-way
		// identity OR plus the "lost, or never printed yet" check in JS.
		data["can_print_master_card"] = (op_rank == 99 || user.ckey == get_faction_founder_ckey(net) || is_faction_ceo(net, user.ckey, user.real_name) || is_faction_designated_leader(net, user.ckey, user.real_name)) && (get_faction_master_card_lost(net) || !has_live_faction_master_card(net))
		// Same four-way top-authority bar as Print Master Card, minus the
		// master-card-lost condition (irrelevant here) -- disbanding is at
		// least as consequential, so it gets the strict bar rather than the
		// usual op_rank >= 2 officer gate. Visible (and usable) to nobody
		// else.
		data["can_disband_faction"] = (op_rank == 99 || user.ckey == get_faction_founder_ckey(net) || is_faction_ceo(net, user.ckey, user.real_name) || is_faction_designated_leader(net, user.ckey, user.real_name))
		data["color"] = get_faction_color(net)

		// Panic Purge audit trail -- officer+-visible record of who purged
		// IDs and when, distinct from log_game()/message_admins() (admin-only).
		var/list/purges_out = list()
		if(GLOB.config.sql_enabled && SSdbcore.Connect())
			var/datum/db_query/pq = SSdbcore.NewQuery(
				{"SELECT issued_by_name, revoked_count, member_count, created_at FROM ss13_faction_id_purges
				WHERE faction_uid = :uid ORDER BY id DESC LIMIT 20"},
				list("uid" = net)
			)
			pq.Execute()
			while(pq.NextRow())
				purges_out += list(list(
					"issued_by"     = pq.item[1],
					"revoked_count" = text2num(pq.item[2]) || 0,
					"member_count"  = text2num(pq.item[3]) || 0,
					"when"          = pq.item[4]
				))
			qdel(pq)
		data["id_purges"] = purges_out
	else
		data["balance"]        = null
		data["jobs"]           = list()
		data["known_factions"] = list()
		data["last_payroll"]   = 0
		data["auto_payroll"]   = TRUE
		data["members"]        = list()
		data["cards_epoch"]    = 0
		data["id_purges"]      = list()
		data["is_founder"]        = FALSE
		data["master_card_lost"]  = FALSE
		data["can_print_master_card"] = FALSE
		data["can_disband_faction"] = FALSE
		data["color"]             = null
		data["stock_listed"]        = FALSE
		data["stock_ticker"]        = null
		data["stock_player_shares"] = 0
		data["shareholders"]              = list()
		data["shareholder_total_percent"] = 0

	return data

/// Shared by revoke_member_id (one target) and panic_purge_ids (every member).
/// Live-sweeps the world for this target's unrevoked faction ID(s), revokes
/// them immediately, and stages a pending revoke so an offline copy (or the
/// target themselves, if not currently in the round) is caught automatically
/// on next restore -- see applyPendingFactionRevokes(), persistence_factions.dm.
/// That consumption only ever fires once per staged row (processed flag), so
/// a card reprinted after the revoke is never retroactively caught.
/datum/computer_file/program/faction_manage/proc/_revoke_member_id_now(net, target_ckey, target_name, issuer_ckey)
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
			list("uid" = net, "ckey" = target_ckey, "name" = target_name, "issuer" = issuer_ckey)
		)
		rq.Execute()
		qdel(rq)

	return revoked_now

/datum/computer_file/program/faction_manage/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/user = usr
	var/net = normalize_faction_uid(computer.persistent_network)
	// No blanket "if(!net) return" here -- start_founding/support_founding/
	// select_tap_target are global program features, independent of this
	// console's own shackle state. Every other action below re-derives its
	// own permission from op_rank, which safely evaluates to -1 (refused)
	// when net is null (get_effective_faction_rank() itself guards on
	// !faction_uid), so nothing downstream needs its own null-net guard.
	var/op_rank = get_effective_faction_rank(user, net)
	// Shareholder-majority CEO -- see the matching bump in ui_data() for the
	// full rationale. Recomputed live every action, never persisted.
	if(op_rank < 2 && is_faction_ceo(net, user.ckey, user.real_name))
		op_rank = 2

	switch(action)
		// ---- Start Founding Petition ------------------------------------------
		// Open to anyone -- no op_rank check, no dependency on this
		// console's own net. Prompts for the TARGET faction UID directly
		// (not tied to computer.persistent_network) so founding works from
		// any console, including an already-registered one. Starts a
		// petition -- it does NOT create the faction or touch the founder's
		// balance yet; see tryFinalizeFounding().
		if("start_founding")
			if(!GLOB.faction_creation_enabled)
				to_chat(user, SPAN_WARNING("Faction founding is currently disabled by administrators."))
				return
			if(!user.ckey || !user.real_name)
				return
			// Tier is chosen by which of the two TSX buttons was clicked --
			// resolved up front since it drives the cost check immediately
			// below. Unrecognized/missing tier defaults to the full faction
			// tier (matches the button's own default act() call shape).
			var/cf_is_company = (params["tier"] == "company")
			var/cf_cost = faction_founding_cost(cf_is_company)
			var/cf_required = faction_founding_required_supporters(cf_is_company)
			var/obj/item/card/id/cf_id = user.GetIdCard()
			if(!cf_id || !cf_id.associated_account_number)
				to_chat(user, SPAN_WARNING("No linked bank account."))
				return
			var/datum/money_account/cf_acc = SSeconomy.get_account(cf_id.associated_account_number)
			if(!cf_acc || cf_acc.money < cf_cost)
				to_chat(user, SPAN_WARNING("Insufficient funds -- founding a [cf_is_company ? "company" : "new faction"] costs [cf_cost] credits, charged once the petition succeeds."))
				return

			var/cf_uid_raw = tgui_input_text(user, "Faction network UID (lowercase, underscores for spaces):", "Start Founding Petition", max_length = 64)
			if(!cf_uid_raw) return
			var/cf_uid = normalize_faction_uid(cf_uid_raw)
			if(!cf_uid) return

			if(islist(GLOB.persistence_faction_cache) && (cf_uid in GLOB.persistence_faction_cache))
				to_chat(user, SPAN_WARNING("This network is already registered to a faction."))
				return
			if(islist(GLOB.persistence_faction_founding_petitions) && (cf_uid in GLOB.persistence_faction_founding_petitions))
				to_chat(user, SPAN_WARNING("A founding petition is already underway for this network."))
				return

			var/cf_name = tgui_input_text(user, "Full faction name (e.g. 'Hub Enterprises'):", "Start Founding Petition", max_length = 64)
			if(!cf_name) return
			cf_name = lowertext(cf_name)

			if(islist(GLOB.persistence_faction_cache))
				for(var/existing_uid in GLOB.persistence_faction_cache)
					var/list/existing = GLOB.persistence_faction_cache[existing_uid]
					if(lowertext(existing["name"]) == cf_name)
						to_chat(user, SPAN_WARNING("A faction named '[cf_name]' already exists."))
						return

			var/cf_abbr = tgui_input_text(user, "Abbreviation (2-4 letters, e.g. 'HUB'):", "Start Founding Petition", max_length = 8)
			if(!cf_abbr) return

			var/cf_category = null
#ifdef FACTION_CARGO_SPECIALIZATION
			// Full-tier founders skip this entirely -- they get unrestricted
			// access to every category automatically on success (see
			// tryFinalizeFounding()), so there's nothing to pick.
			if(cf_is_company)
				var/list/cf_category_options = list()
				for(var/cat_name in SScargo.cargo_categories)
					var/singleton/cargo_category/cf_cc = SScargo.cargo_categories[cat_name]
					cf_category_options[cf_cc.display_name] = cf_cc.name
				var/cf_category_pick = tgui_input_list(user, "Cargo order specialization -- the ONE category your company will be able to order from cargo. Changeable later, locked for 1 month after each change:", "Start Founding Petition", cf_category_options)
				if(!cf_category_pick) return
				cf_category = cf_category_options[cf_category_pick]
#endif //FACTION_CARGO_SPECIALIZATION

			// Re-validate after the async prompts -- registration state and
			// the player's balance could both have changed while typing.
			if(islist(GLOB.persistence_faction_cache) && (cf_uid in GLOB.persistence_faction_cache))
				to_chat(user, SPAN_WARNING("This network was registered by someone else while you were typing."))
				return
			if(islist(GLOB.persistence_faction_founding_petitions) && (cf_uid in GLOB.persistence_faction_founding_petitions))
				to_chat(user, SPAN_WARNING("Someone else started a founding petition for this network while you were typing."))
				return
			if(!cf_acc || cf_acc.money < cf_cost)
				to_chat(user, SPAN_WARNING("Insufficient funds."))
				return

			if(!SSpersistence.databaseCheckConnection("faction_manage start_founding"))
				to_chat(user, SPAN_WARNING("Database connection failed."))
				return

			if(!SSpersistence.startFoundingPetition(cf_uid, user.ckey, user.real_name, cf_name, cf_abbr, cf_category, cf_is_company))
				to_chat(user, SPAN_WARNING("Failed to start the founding petition -- database error. Try again shortly."))
				return
			to_chat(user, SPAN_GOOD("Founding petition started for '[cf_name]'. Gather [cf_required] other players' support -- tap them with a device running Faction Management, or have them visit this terminal directly."))
			log_game("[key_name(user)] started a [cf_is_company ? "Company" : "Full Faction"] founding petition for '[cf_uid]' ([cf_name]).")
			. = TRUE

		// ---- Support Founding ---------------------------------------------------
		// Terminal-based self-consent -- any player at ANY console can
		// support any active petition, identified by target_uid (no longer
		// tied to this console's own network). Tap-based consent is the
		// other always-available method (see tap_consent() below);
		// _try_add_supporter() is the shared dedup chokepoint for both.
		if("support_founding")
			var/support_uid = normalize_faction_uid(params["target_uid"])
			if(!support_uid) return
			_try_add_supporter(support_uid, user.ckey, user.real_name, user)
			. = TRUE

		// ---- Select Tap Target --------------------------------------------------
		// Picks which active petition tap_consent() (below) canvasses for
		// when this program's handheld is used to tap another player.
		if("select_tap_target")
			var/new_target = normalize_faction_uid(params["target_uid"])
			if(!islist(GLOB.persistence_faction_founding_petitions) || !(new_target in GLOB.persistence_faction_founding_petitions))
				to_chat(user, SPAN_WARNING("That founding petition is no longer active."))
				return
			tap_target_uid = new_target
			to_chat(user, SPAN_NOTICE("Tapping a player will now canvass support for '[GLOB.persistence_faction_founding_petitions[new_target]["faction_name"]]'."))
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

		// ---- Payroll Mode (Automatic/Manual) ---------------------------------
		if("toggle_auto_payroll")
			if(op_rank < 2) return
			var/new_state = !get_faction_auto_payroll(net)
			set_faction_auto_payroll(net, new_state)
			to_chat(user, SPAN_GOOD("Payroll mode set to [new_state ? "Automatic" : "Manual"] for [get_faction_name(net)]."))
			. = TRUE

#ifdef FACTION_CARGO_SPECIALIZATION
		// ---- Cargo Specialization ---------------------------------------------
		if("set_cargo_category")
			if(op_rank < 2) return
			// Full-tier (100K) founding grants permanent unrestricted access --
			// officers can't self-service it back down to a single category
			// (accidentally or otherwise). Admin override (Manage Faction
			// Account -> Set Cargo Category) is untouched by this check.
			if(faction_cargo_unrestricted(net))
				to_chat(user, SPAN_WARNING("[get_faction_name(net)] has unrestricted cargo access from its founding tier -- this can't be changed to a single category."))
				return
			// Pirate factions never get self-service cargo access -- imports
			// come from theft, not legitimate supply lines. Admin override
			// (Manage Faction Account -> Set Cargo Category) is untouched.
			if(is_pirate_faction(net))
				to_chat(user, SPAN_WARNING("[get_faction_name(net)] is a pirate faction -- it has no legitimate supply lines to order from."))
				return
			var/picked_display_name = params["category"]
			var/resolved_category
			for(var/cat_name in SScargo.cargo_categories)
				var/singleton/cargo_category/cc = SScargo.cargo_categories[cat_name]
				if(cc.display_name == picked_display_name)
					resolved_category = cc.name
					break
			if(!resolved_category)
				return
			if(!set_faction_allowed_cargo_category(net, resolved_category))
				var/remaining = get_faction_cargo_category_cooldown_remaining(net)
				to_chat(user, SPAN_WARNING("Cargo specialization can't be changed yet -- [DisplayTimeText(remaining SECONDS)] remaining."))
				return
			to_chat(user, SPAN_GOOD("[get_faction_name(net)]'s cargo specialization set to '[picked_display_name]'."))
			. = TRUE
#endif //FACTION_CARGO_SPECIALIZATION

#ifdef FACTION_ALLIANCES
		// ---- Alliances ----------------------------------------------------------
		if("propose_alliance")
			if(op_rank < 2) return
			var/target_uid = params["uid"]
			if(!target_uid || !(target_uid in GLOB.persistence_faction_cache)) return
			var/result = propose_faction_alliance(net, target_uid)
			if(result == "allied")
				to_chat(user, SPAN_GOOD("[get_faction_name(net)] and [get_faction_name(target_uid)] are now allied -- [get_faction_name(target_uid)] had already proposed to you."))
				notify_faction_members(target_uid, SPAN_GOOD("[get_faction_name(net)] has accepted your alliance proposal -- your factions are now allied."))
			else if(result == "proposed")
				to_chat(user, SPAN_GOOD("Alliance proposed to [get_faction_name(target_uid)] -- awaiting their acceptance."))
				notify_faction_members(target_uid, SPAN_NOTICE("[get_faction_name(net)] has proposed an alliance with your faction. Visit Faction Management to respond."))
			else
				to_chat(user, SPAN_WARNING("Unable to propose an alliance right now."))
			. = TRUE

		if("accept_alliance")
			if(op_rank < 2) return
			var/proposer_uid = params["uid"]
			if(!proposer_uid) return
			if(!accept_faction_alliance(net, proposer_uid))
				to_chat(user, SPAN_WARNING("Unable to accept -- that request no longer exists."))
				return
			to_chat(user, SPAN_GOOD("[get_faction_name(net)] and [get_faction_name(proposer_uid)] are now allied."))
			notify_faction_members(proposer_uid, SPAN_GOOD("[get_faction_name(net)] has accepted your alliance proposal -- your factions are now allied."))
			. = TRUE

		if("decline_alliance")
			if(op_rank < 2) return
			var/proposer_uid = params["uid"]
			if(!proposer_uid) return
			cancel_faction_alliance_request(proposer_uid, net)
			to_chat(user, SPAN_NOTICE("Alliance request from [get_faction_name(proposer_uid)] declined."))
			notify_faction_members(proposer_uid, SPAN_WARNING("[get_faction_name(net)] has declined your alliance proposal."))
			. = TRUE

		if("withdraw_alliance")
			if(op_rank < 2) return
			var/target_uid = params["uid"]
			if(!target_uid) return
			cancel_faction_alliance_request(net, target_uid)
			to_chat(user, SPAN_NOTICE("Alliance proposal to [get_faction_name(target_uid)] withdrawn."))
			notify_faction_members(target_uid, SPAN_WARNING("[get_faction_name(net)] has withdrawn its alliance proposal to your faction."))
			. = TRUE

		if("break_alliance")
			if(op_rank < 2) return
			var/ally_uid = params["uid"]
			if(!ally_uid) return
			break_faction_alliance(net, ally_uid)
			notify_faction_members(ally_uid, SPAN_WARNING("[get_faction_name(net)] has broken its alliance with your faction."))
			to_chat(user, SPAN_NOTICE("Alliance with [get_faction_name(ally_uid)] broken."))
			. = TRUE
#endif //FACTION_ALLIANCES

		// ---- List on Stock Exchange -------------------------------------------
		// Opens this faction's own real stock listing -- distinct from the
		// AI-simulated companies (stock_market.dm/persistence_stock_market.dm):
		// price tracks the faction's OWN treasury balance per share, trades
		// move real credits into/out of that treasury, and a bankrupt
		// (balance <= 0) listing auto-revokes (stockMarketRevokeFaction(),
		// force-liquidating every holder, and powering down this faction's
		// beacons -- see _power_down_faction_beacons_on_bankruptcy(),
		// faction_beacon.dm) even if nobody's watching. There is no
		// self-service unlist once listed -- only an admin can revoke it from
		// here on (the Stock Market program's "Revoke Faction Business Status").
		if("list_on_exchange")
			if(op_rank < 2) return
			if(get_faction_stock_company(net))
				to_chat(user, SPAN_WARNING("[get_faction_name(net)] is already listed on the exchange."))
				return
			var/confirm = tgui_alert(user, "List [get_faction_name(net)] on the Idris stock exchange? Real players will be able to buy/sell stock tied directly to the faction's own treasury -- trades move real credits in and out, and the treasury running dry force-liquidates every stockholder AND powers down every faction beacon (and dissolves the faction entirely). This cannot be undone by faction command -- only an admin can revoke the listing afterward. You'll also become the company's first shareholder, holding 100%.", "List on Stock Exchange", list("List", "Cancel"))
			if(confirm != "List") return
			var/refusal = SSpersistence.stockMarketListFaction(net, user)
			if(refusal)
				to_chat(user, SPAN_WARNING(refusal))
				return
			// Seeds the acting user as the company's first shareholder at
			// 100% -- see persistence_faction_shareholders.dm. Every
			// certificate issued from here on proportionally dilutes this
			// (and every other current) stake rather than adding on top of
			// an "unallocated" pool -- the cap table always sums to 100%.
			SSpersistence.factionGrantShareholder(net, user.ckey, user.real_name, 100, "Faction Listing", null)
			to_chat(user, SPAN_GOOD("[get_faction_name(net)] is now listed on the Idris stock exchange. You are its first shareholder, holding 100%."))
			log_game("[key_name(user)] listed faction '[net]' on the stock exchange via faction_manage, seeded as its 100% shareholder.")
			. = TRUE

			// ---- Print Share Certificate --------------------------------------------
			// Prints a physical /obj/item/paper/share_certificate (share_certificate.dm)
			// offering a set percentage of the faction's equity, optionally for a
			// price -- swiping an ID card against it (try_redeem()) grants the
			// stake, proportionally diluting every existing shareholder
			// (factionGrantShareholder(), persistence_faction_shareholders.dm).
			// Dilution/validity is only actually checked and applied at
			// redemption time -- printing itself commits nothing.
			if("print_share_certificate")
				if(op_rank < 2) return
				if(!get_faction_stock_company(net))
					to_chat(user, SPAN_WARNING("[get_faction_name(net)] must be listed on the stock exchange before you can offer shares."))
					return
				var/available = faction_shareholder_total_percent(net)
				if(available <= 0)
					to_chat(user, SPAN_WARNING("[get_faction_name(net)] has no allocated equity to offer shares from yet."))
					return
				var/sc_percent = tgui_input_number(user, "Percentage of the company to offer (this will proportionally dilute every current shareholder, including you) -- currently allocated: [available]%:", "Print Share Certificate", min(5, available - 0.01), available - 0.01, 0.01, round_value = FALSE)
				if(isnull(sc_percent) || sc_percent <= 0) return
				var/sc_price = tgui_input_number(user, "Credits the recipient must pay to accept this stake (0 for a free grant):", "Print Share Certificate", 0, 1000000, 0)
				if(isnull(sc_price)) return
				var/obj/item/paper/share_certificate/SC = new(get_turf(computer))
				SC.faction_uid = net
				SC.percent = sc_percent
				SC.price = sc_price
				SC.issued_by_name = user.real_name || key_name(user)
				user.put_in_hands(SC)
				to_chat(user, SPAN_GOOD("Printed a [sc_percent]% share certificate[sc_price > 0 ? " (price: [sc_price] cr)" : " (free grant)"] for [get_faction_name(net)]."))
				log_game("[key_name(user)] printed a [sc_percent]% share certificate (price [sc_price]) for faction '[net]' via faction_manage.")
				. = TRUE

		// ---- Pay Dividends -----------------------------------------------------
		// Distributes credits straight out of the faction treasury to every
		// current SHAREHOLDER (persistence_faction_shareholders.dm) of this
		// faction's OWN stock listing, split by their raw percent -- the
		// payout counterpart to the treasury-backed pricing model
		// (sync_price_to_treasury(), stock_market.dm) that already makes the
		// share price itself track the faction's success. Distinct from the
		// per-share "stockholders" traded on the open exchange, which this no
		// longer pays. Strict percentage (confirmed with the user): each
		// shareholder gets exactly dividend_pool * percent / 100 -- computed
		// from live holdings first, then debited once for exactly the sum
		// actually paid out, rather than debiting the requested amount up
		// front and risking rounding leakage no one actually received.
		if("pay_dividends")
			if(op_rank < 2) return
			var/datum/stock_company/div_company = get_faction_stock_company(net)
			if(!div_company)
				to_chat(user, SPAN_WARNING("[get_faction_name(net)] isn't listed on the stock exchange."))
				return
			var/list/div_shareholders = GLOB.persistence_faction_shareholders_cache[net]
			if(!islist(div_shareholders) || !length(div_shareholders))
				to_chat(user, SPAN_WARNING("[get_faction_name(net)] has no shareholders to pay out to."))
				return
			var/div_balance = get_faction_account_balance(net) || 0
			if(div_balance <= 0)
				to_chat(user, SPAN_WARNING("[get_faction_name(net)]'s treasury is empty."))
				return
			// A dividend can never drain more than FACTION_DIVIDEND_MAX_FRACTION
			// of the treasury -- at least 1% always survives the payout, so
			// dividends alone can never re-bankrupt the company.
			var/div_max = round(div_balance * FACTION_DIVIDEND_MAX_FRACTION)
			if(div_max <= 0)
				to_chat(user, SPAN_WARNING("[get_faction_name(net)]'s treasury is too low to pay a dividend right now."))
				return
			var/div_amount = tgui_input_number(user, "Dividend pool to distribute -- each shareholder receives exactly their own percent of this amount. (Treasury: [div_balance] cr, at least 1% must remain)", "Pay Dividends", min(1000, div_max), div_max, 1)
			if(isnull(div_amount) || div_amount <= 0)
				return

			var/list/div_payouts = list()
			var/div_paid_total = 0
			for(var/list/sh in div_shareholders)
				var/h_payout = round(div_amount * sh["percent"] / 100)
				if(h_payout <= 0)
					continue
				div_payouts += list(list("ckey" = sh["ckey"], "char_name" = sh["char_name"], "amount" = h_payout, "percent" = sh["percent"]))
				div_paid_total += h_payout

			if(div_paid_total <= 0)
				to_chat(user, SPAN_WARNING("That amount is too small to distribute across current shareholder percentages."))
				return
			// Re-check against a fresh balance -- some time (the tgui_input_number
			// prompt) has passed since div_balance was read above.
			if(div_paid_total > round((get_faction_account_balance(net) || 0) * FACTION_DIVIDEND_MAX_FRACTION))
				to_chat(user, SPAN_WARNING("The treasury balance changed -- that would leave less than 1% in reserve. Try a smaller amount."))
				return
			if(!faction_debit(net, div_paid_total, "Dividend payout by [key_name(user)]"))
				to_chat(user, SPAN_WARNING("Insufficient funds -- the treasury balance changed. Try a smaller amount."))
				return

			var/div_paid_holders = 0
			for(var/list/p in div_payouts)
				var/datum/money_account/h_acc = SSeconomy.get_account_by_ckey_and_name(p["ckey"], p["char_name"])
				if(h_acc)
					h_acc.adjust_money(p["amount"])
				div_paid_holders++
				var/client/h_client = GLOB.directory[p["ckey"]]
				if(h_client)
					to_chat(h_client, SPAN_GOOD("You received a dividend payout of [p["amount"]] credits ([p["percent"]]% stake) from [get_faction_name(net)]."))

			div_company.sync_price_to_treasury()

			to_chat(user, SPAN_GOOD("Paid out [div_paid_total] credits in dividends to [div_paid_holders] shareholder(s)."))
			log_and_message_admins("[key_name(user)] paid out [div_paid_total] cr in dividends to [div_paid_holders] shareholder(s) of [get_faction_name(net)]'s stock listing.", user)
			. = TRUE

		// ---- Set Faction Color -----------------------------------------------
		// Tints any clothing/equipment currently tagged to this faction with
		// the faction tagger, immediately and everywhere (worn, stored, on the
		// floor) -- see set_faction_color() (persistence_factions.dm).
		if("set_faction_color")
			if(op_rank < 2) return
			var/new_color = params["color"]
			var/static/regex/hex_color_check = regex(@"^#[0-9A-Fa-f]{6}$")
			if(!new_color || !hex_color_check.Find(new_color))
				to_chat(user, SPAN_WARNING("Invalid color."))
				return
			set_faction_color(net, new_color)
			to_chat(user, SPAN_GOOD("[get_faction_name(net)]'s color updated -- tagged equipment refreshed immediately."))
			log_game("[key_name(user)] set faction '[net]' color to [new_color] via faction_manage.")
			. = TRUE

		// ---- Print Faction Charge Card --------------------------------------
		if("print_charge_card")
			if(op_rank < 2) return
			var/confirm = tgui_alert(user, "Print a charge card loaded with funds withdrawn from [get_faction_name(net)]'s bank account?", "Print Charge Card", list("Print", "Cancel"))
			if(confirm != "Print") return
			var/balance = get_faction_account_balance(net) || 0
			if(balance <= 0)
				to_chat(user, SPAN_WARNING("[get_faction_name(net)] has no funds to load onto a card."))
				return
			var/amount = tgui_input_number(user, "How many credits to withdraw from [get_faction_name(net)]'s account and store on this card? (Available: [balance])", "Print Charge Card", min(1000, balance), balance, 1)
			if(isnull(amount) || amount <= 0)
				return
			if(!faction_debit(net, amount, "Charge card printed by [user.real_name || key_name(user)]"))
				to_chat(user, SPAN_WARNING("Withdrawal failed -- the faction account balance changed. Try again."))
				return
			var/obj/item/spacecash/ewallet/faction_charge_card/FC = new(get_turf(computer))
			FC.faction_uid = net
			FC.name = "[get_faction_name(net)] charge card"
			FC.owner_name = get_faction_name(net)
			FC.issued_epoch = get_faction_cards_epoch(net)
			FC.worth = amount
			user.put_in_hands(FC)
			to_chat(user, SPAN_GOOD("Printed \a [FC] loaded with [amount] credits."))
			log_game("[key_name(user)] printed a faction charge card for '[net]' loaded with [amount] credits via faction_manage.")
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

			var/revoked_now = _revoke_member_id_now(net, target_ckey, target_name, user.ckey)

			to_chat(user, SPAN_GOOD("Revoked [revoked_now] live ID card[revoked_now == 1 ? "" : "s"] for [target_name]. Any offline copies will be revoked automatically when [target_name] is next restored."))
			log_game("[key_name(user)] revoked faction ID access for '[target_name]' (ckey: [target_ckey]) in faction '[net]' via faction_manage ([revoked_now] live cards caught).")
			. = TRUE

		// ---- Remove Member: revoke ID AND erase the membership record -----
		// Unlike revoke_member_id above, this actually removes them from
		// ss13_faction_members -- get_faction_member()/get_effective_faction_rank()
		// stop seeing them as a member at all, and a future replacement ID
		// re-registers them fresh rather than just reprinting. A fellow
		// command-rank (2+) member can't be removed this way -- only an
		// admin can; self-removal is refused outright, pointed at Leave
		// Faction (card.dm) instead.
		if("remove_member")
			if(op_rank < 2) return
			var/remove_target_ckey = ckey(params["target_ckey"])
			if(!remove_target_ckey) return
			if(remove_target_ckey == user.ckey)
				to_chat(user, SPAN_WARNING("You can't remove yourself this way -- leave the faction from your ID card instead."))
				return
			var/list/remove_target_member = get_faction_member(remove_target_ckey, net)
			if(!remove_target_member)
				to_chat(user, SPAN_WARNING("That ckey is not a member of [get_faction_name(net)]."))
				return
			var/remove_target_name = remove_target_member["real_name"]
			if((remove_target_member["rank"] || 0) >= 2 && op_rank != 99)
				to_chat(user, SPAN_WARNING("[remove_target_name] holds command rank -- only an admin can remove a fellow command-rank member."))
				return

			var/remove_confirm = tgui_alert(user, "Remove [remove_target_name] from [get_faction_name(net)] entirely? This revokes their ID access and erases their membership record -- they would need to be issued a new ID to rejoin.", "Remove Member", list("Remove", "Cancel"))
			if(remove_confirm != "Remove") return

			if(!SSpersistence.factionRemoveMember(remove_target_ckey, net))
				to_chat(user, SPAN_WARNING("Failed to remove [remove_target_name] -- database error. Try again shortly."))
				return
			_revoke_member_id_now(net, remove_target_ckey, remove_target_name, user.ckey)

			to_chat(user, SPAN_GOOD("Removed [remove_target_name] from [get_faction_name(net)]."))
			log_game("[key_name(user)] removed '[remove_target_name]' (ckey: [remove_target_ckey]) from faction '[net]' via faction_manage.")
			message_admins("[key_name_admin(user)] removed '[remove_target_name]' from faction '[net]'.")
			. = TRUE

		// ---- Force Clock Out (command rank -- see toggle_clock, card.dm, for
		// the self-service equivalent) ---------------------------------------
		// No confirm dialog and no command-rank-vs-command-rank restriction
		// like Remove Member above -- unlike removal this is trivially
		// self-reversible (the target just clocks back in) and not a
		// destructive action, so the bar is just op_rank >= 2. Doesn't go
		// through the 5-minute manual-toggle cooldown -- that's specifically
		// an anti-spam measure on the self-service action, not something a
		// legitimate command override should be throttled by.
		if("force_clock_out")
			if(op_rank < 2) return
			var/clockout_target_ckey = ckey(params["target_ckey"])
			if(!clockout_target_ckey) return
			var/list/clockout_target_member = get_faction_member(clockout_target_ckey, net)
			if(!clockout_target_member)
				to_chat(user, SPAN_WARNING("That ckey is not a member of [get_faction_name(net)]."))
				return
			var/clockout_target_name = clockout_target_member["real_name"]
			if(!clockout_target_member["clocked_in"])
				to_chat(user, SPAN_WARNING("[clockout_target_name] isn't clocked in."))
				return

			if(!SSpersistence.factionSetClockedIn(clockout_target_ckey, net, FALSE))
				to_chat(user, SPAN_WARNING("Failed to clock out [clockout_target_name] -- database error. Try again shortly."))
				return
			notify_faction_members(net, SPAN_NOTICE("[clockout_target_name] has been clocked out of [get_faction_name(net)] by [user.real_name]."))
			to_chat(user, SPAN_GOOD("Clocked out [clockout_target_name]."))
			log_game("[key_name(user)] force-clocked out '[clockout_target_name]' (ckey: [clockout_target_ckey]) from faction '[net]' via faction_manage.")
			. = TRUE

		// ---- Panic Purge: revoke every ID this faction has ever issued -----
		// Exempts the issuer's own card (matching revoke_member_id's own
		// self-protection) -- an officer triggering this shouldn't lock
		// themselves out mid-response. Recorded to ss13_faction_id_purges
		// regardless, so officers+ have a visible audit trail in the TGUI
		// itself (see ui_data()), not just admin-only log_game()/message_admins().
		if("panic_purge_ids")
			if(op_rank < 2) return
			var/confirm2 = tgui_alert(user, "PANIC PURGE: revoke every [get_faction_name(net)] ID card except your own? Everyone else -- online or not -- will need to print a new one. This cannot be undone.", "Panic Purge IDs", list("Purge", "Cancel"))
			if(confirm2 != "Purge") return

			if(!SSpersistence.databaseCheckConnection("faction_manage panic_purge_ids"))
				to_chat(user, SPAN_WARNING("Database connection failed -- no members could be looked up."))
				return

			var/list/roster = list()
			var/datum/db_query/rosterq = SSdbcore.NewQuery(
				"SELECT ckey, real_name FROM ss13_faction_members WHERE faction_uid = :uid",
				list("uid" = net)
			)
			rosterq.Execute()
			if(SSpersistence.databaseCheckQueryResult(rosterq, "faction_manage panic_purge_ids roster"))
				while(rosterq.NextRow())
					if(rosterq.item[1] == user.ckey)
						continue
					roster += list(list("ckey" = rosterq.item[1], "real_name" = rosterq.item[2]))
			qdel(rosterq)

			var/total_live = 0
			for(var/list/member in roster)
				total_live += _revoke_member_id_now(net, member["ckey"], member["real_name"], user.ckey)

			// Master card is always included -- no exemption, even if the
			// triggering officer's own rank-2 access came from holding it
			// themselves. It's a bearer card, not tied to any one ckey, so
			// there's no "own card" to protect the way the member sweep
			// protects the issuer's personal ID above. The founder-gated
			// Print Master Card action (below) is the intended recovery path.
			for(var/obj/item/card/id/faction_master/old_master in world)
				if(!old_master.revoked && normalize_faction_uid(old_master.employer_faction) == net)
					old_master.revoked = TRUE
					old_master.access = list()
					old_master.update_name()
			set_faction_master_card_lost(net, TRUE)

			var/datum/db_query/auditq = SSdbcore.NewQuery(
				{"INSERT INTO ss13_faction_id_purges (faction_uid, issued_by_ckey, issued_by_name, revoked_count, member_count)
				VALUES (:uid, :ckey, :name, :revoked, :members)"},
				list("uid" = net, "ckey" = user.ckey, "name" = user.real_name || key_name(user), "revoked" = total_live, "members" = length(roster))
			)
			auditq.Execute()
			SSpersistence.databaseCheckQueryResult(auditq, "faction_manage panic_purge_ids audit")
			qdel(auditq)

			to_chat(user, SPAN_GOOD("Panic purge complete: [total_live] live ID card[total_live == 1 ? "" : "s"] revoked across [length(roster)] member[length(roster) == 1 ? "" : "s"] (your own ID was not touched), and the faction master card has been revoked. Offline members will be caught automatically when next restored. Only [get_faction_name(net)]'s original founder, its majority shareholder, its designated leader, or an admin can print a replacement master card."))
			log_game("[key_name(user)] PANIC PURGED all faction IDs for '[net]' via faction_manage -- [total_live] live cards revoked across [length(roster)] members (issuer exempted), master card revoked.")
			message_admins("[key_name_admin(user)] triggered a panic ID purge for faction '[net]' -- [total_live] live cards revoked across [length(roster)] members, master card revoked.")
			. = TRUE

		// ---- Print Master Card ------------------------------------------------
		// Founder-gated (not the usual op_rank >= 2), so the founder can
		// always recover from a lost/compromised master card even if Panic
		// Purge (above) cost them their own rank-2 access (a rank-2 job
		// title is independent of this and unaffected either way). Admins
		// (op_rank == 99) bypass the founder check too -- the master card is
		// a bearer item with no identity check on it at all, so admin
		// recourse matters when the founder's gone, banned, or otherwise
		// unreachable. The majority shareholder (is_faction_ceo()) and any
		// admin-designated leader (is_faction_designated_leader() -- the
		// recourse for factions made via the admin "create faction" verb,
		// which have no organic founder to fall back on) can print it too.
		// master_card_lost still has to be true, UNLESS no live master card
		// exists for this faction at all yet (true for every admin-made
		// faction until its first print) -- nobody can mint a second valid
		// card while the current one is still out there and unrevoked, but
		// a faction that never had one printed shouldn't be stuck waiting on
		// a Panic Purge that has nothing to purge.
		if("print_master_card")
			if(op_rank != 99 && user.ckey != get_faction_founder_ckey(net) && !is_faction_ceo(net, user.ckey, user.real_name) && !is_faction_designated_leader(net, user.ckey, user.real_name))
				to_chat(user, SPAN_WARNING("Only [get_faction_name(net)]'s original founder, its majority shareholder, its designated leader, or an admin can print a replacement master card."))
				return
			if(!get_faction_master_card_lost(net) && has_live_faction_master_card(net))
				to_chat(user, SPAN_WARNING("The current master card hasn't been reported lost -- use Panic Purge first if it's been compromised."))
				return
			var/turf/spawn_turf = get_turf(computer) || get_turf(user)
			if(!spawn_turf)
				return
			var/obj/item/card/id/faction_master/new_master = new(spawn_turf)
			new_master.employer_faction = net
			new_master.update_name()
			set_faction_master_card_lost(net, FALSE)
			user.put_in_hands(new_master)
			to_chat(user, SPAN_GOOD("Printed a new master card for [get_faction_name(net)]."))
			log_game("[key_name(user)] printed a replacement faction master card for '[net]' via faction_manage.")
			message_admins("[key_name_admin(user)] printed a replacement master card for faction '[net]'.")
			. = TRUE

		// ---- Disband Faction ---------------------------------------------------
		// Same four-way top-authority bar as Print Master Card -- founder,
		// majority shareholder, admin-designated leader, or an admin. Never
		// trust the client-side can_disband_faction flag; re-check here.
		// Permanently deletes the faction via the same removeFactionCompletely()
		// the admin "Remove Faction" verb already uses (treasury/stock listing
		// buyout, drydock ship release, every tagged machine released, DB row
		// gone) -- there is no undo.
		if("disband_faction")
			if(op_rank != 99 && user.ckey != get_faction_founder_ckey(net) && !is_faction_ceo(net, user.ckey, user.real_name) && !is_faction_designated_leader(net, user.ckey, user.real_name))
				return
			var/fname_confirm = get_faction_name(net)
			var/confirm = tgui_alert(user, "Permanently disband [fname_confirm]? This deletes its treasury, jobs, beacon claims, drydock ship ownership, and stock listing -- EVERYTHING. This cannot be undone.", "Disband Faction", list("Disband", "Cancel"))
			if(confirm != "Disband") return
			// Re-validate after the async alert -- the faction (or this user's
			// standing in it) could have changed while the dialog was open.
			if(!islist(GLOB.persistence_faction_cache) || !(net in GLOB.persistence_faction_cache))
				to_chat(user, SPAN_WARNING("This faction no longer exists."))
				return
			if(op_rank != 99 && user.ckey != get_faction_founder_ckey(net) && !is_faction_ceo(net, user.ckey, user.real_name) && !is_faction_designated_leader(net, user.ckey, user.real_name))
				return
			if(!SSpersistence.removeFactionCompletely(net, user))
				to_chat(user, SPAN_WARNING("Failed to disband -- database error."))
				return
			to_chat(user, SPAN_GOOD("[fname_confirm] has been disbanded."))
			log_game("[key_name(user)] disbanded faction '[net]' ([fname_confirm]) via Faction Management.")
			message_admins("[key_name_admin(user)] disbanded faction '[net]' ([fname_confirm]) via Faction Management.")
			. = TRUE

/// Tapping a mob with a handheld running Faction Management while a
/// petition is selected (tap_target_uid, set via "select_tap_target")
/// prompts them to consent -- the "tap" half of the two always-available
/// consent methods (the other is "support_founding" above, for terminal
/// self-consent). Delegated from /obj/item/modular_computer/attack()
/// (interaction.dm), same pattern First Responder's toggle_prisoner_tag()
/// already uses.
/datum/computer_file/program/faction_manage/proc/tap_consent(mob/living/target, mob/user)
	if(!istype(target) || !target.ckey || !target.client)
		to_chat(user, SPAN_WARNING("[target] has no active session to prompt."))
		return
	if(target == user)
		to_chat(user, SPAN_WARNING("You can't tap yourself -- use the terminal's own Support Founding option instead."))
		return
	var/list/petition = tap_target_uid && islist(GLOB.persistence_faction_founding_petitions) ? GLOB.persistence_faction_founding_petitions[tap_target_uid] : null
	if(!petition)
		to_chat(user, SPAN_WARNING("Select a founding petition to canvass for first (Faction Management -> Found a New Faction)."))
		return
	if(target.ckey == petition["founder_ckey"] || (target.ckey in petition["supporters"]))
		to_chat(user, SPAN_WARNING("[target] has already been accounted for."))
		return
	user.visible_message(SPAN_NOTICE("[user] holds \the [computer] up to [target]..."))
	var/confirm = tgui_alert(target, "[user] wants you to support founding the faction '[petition["faction_name"]]'. Do you consent?", "Faction Founding", list("Yes", "No"))
	if(confirm != "Yes")
		to_chat(user, SPAN_WARNING("[target] declined."))
		return
	_try_add_supporter(tap_target_uid, target.ckey, target.real_name, target)

/// Shared dedup chokepoint for both consent methods (tap_consent() above,
/// "support_founding" in ui_act()). Rejects the founder's own ckey and
/// repeat supporters, then hands off to SSpersistence for the actual
/// insert/cache mutation. Auto-finalizes once the threshold is reached.
/datum/computer_file/program/faction_manage/proc/_try_add_supporter(faction_uid, ckey, real_name, mob/notify_target)
	var/list/petition = islist(GLOB.persistence_faction_founding_petitions) ? GLOB.persistence_faction_founding_petitions[faction_uid] : null
	if(!petition)
		if(notify_target)
			to_chat(notify_target, SPAN_WARNING("There is no active founding petition here."))
		return FALSE
	var/required_supporters = faction_founding_required_supporters(petition["is_company"])
	if(ckey == petition["founder_ckey"])
		if(notify_target)
			to_chat(notify_target, SPAN_WARNING("You started this petition -- it needs [required_supporters] OTHER supporters."))
		return FALSE
	if(ckey in petition["supporters"])
		if(notify_target)
			to_chat(notify_target, SPAN_NOTICE("You've already supported this petition."))
		return FALSE
	if(!SSpersistence.addFoundingSupporter(faction_uid, ckey))
		return FALSE
	if(notify_target)
		to_chat(notify_target, SPAN_GOOD("You support the founding of '[petition["faction_name"]]'. ([length(petition["supporters"])]/[required_supporters])"))
	if(length(petition["supporters"]) >= required_supporters)
		SSpersistence.tryFinalizeFounding(faction_uid)
	return TRUE
