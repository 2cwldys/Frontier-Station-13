/*
 * Persistence - Bounties
 * Player-posted cash bounties on a specific character. Anyone can accept an
 * open bounty -- any number of people simultaneously, like a real contract --
 * and whichever accepter actually lands the killing blow first is paid the
 * reward to their personal account; the bounty is then marked claimed for
 * everyone. Reward is escrowed from the poster's account immediately on
 * posting (post_bounty()), refunded if the bounty is cancelled unclaimed
 * (cancel_bounty()).
 * DB-backed (ss13_bounties, V087) with an in-memory cache of open rows so
 * accepting/claiming never has to wait on a query.
 */

/// Cached open bounty rows: list of list(id, poster_ckey,
/// poster_account_number, target_ckey, target_name, reward, status,
/// accepters (list of ckeys)). Target is identified by (target_ckey,
/// target_name) together -- one ckey can play several different characters
/// over time (never simultaneously), so the pair is what actually pins down
/// which specific character is being bountied. Claimed/cancelled rows drop
/// out of the cache once resolved.
GLOBAL_LIST_EMPTY(active_bounties)

/// Finds a modular computer M is currently carrying (active/inactive hand,
/// pockets, suit storage, belt, back) that's powered on and has the named
/// program installed -- there's no dedicated PDA slot in this codebase, so
/// this mirrors the same hand/worn-slot scan GetIdCard()/get_radio() already
/// use for their own carried-item lookups.
/proc/find_powered_program_computer(mob/living/carbon/human/M, filename)
	if(!istype(M))
		return null
	var/list/candidates = list(M.get_active_hand(), M.get_inactive_hand(), M.l_store, M.r_store, M.s_store, M.belt, M.back)
	for(var/obj/item/modular_computer/C in candidates)
		if(!C.enabled)
			continue
		if(C.hard_drive?.find_file_by_name(filename))
			return C
	return null

/// Pings ckey's carried device with a beep + notification (get_notification(),
/// the same convention used elsewhere e.g. for incoming faxes) instead of a
/// disembodied to_chat() -- no ping at all if they aren't carrying a powered
/// device with Bounties installed, same as owning no PDA/radio means missing
/// any other device-mediated alert.
/proc/ping_bounties_program(ckey, message)
	var/client/C = GLOB.directory[ckey]
	if(!istype(C?.mob, /mob/living/carbon/human))
		return
	var/obj/item/modular_computer/device = find_powered_program_computer(C.mob, "bounties")
	if(!device)
		return
	device.get_notification(message, 1, "Bounties Board")

/**
 * Load open bounties into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/bountiesInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.active_bounties = list()

	if(!databaseCheckConnection("bountiesInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT id, poster_ckey, poster_account_number, target_ckey, target_name, reward, status, accepters FROM ss13_bounties WHERE map_path = :mp AND status = 'open'",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "bountiesInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		var/list/accepters = query.item[8] ? json_decode(query.item[8]) : list()
		GLOB.active_bounties += list(list(
			"id"                  = text2num(query.item[1]),
			"poster_ckey"         = query.item[2],
			"poster_account_number" = text2num(query.item[3]),
			"target_ckey"         = query.item[4],
			"target_name"         = query.item[5],
			"reward"              = text2num(query.item[6]),
			"status"              = query.item[7],
			"accepters"           = accepters
		))
	qdel(query)
	log_subsystem_persistence_info("Bounties: loaded [length(GLOB.active_bounties)] active bounty/bounties.")

/**
 * Posts a new bounty on the character identified by (target_ckey,
 * target_name), escrowing reward from the poster's personal account.
 * Returns the new bounty's list on success, or null if the poster has no
 * linked account or insufficient funds.
 */
/proc/post_bounty(mob/living/carbon/human/poster, target_ckey, target_name, reward)
	if(!poster || !target_ckey || !target_name || !reward || reward <= 0)
		return null
	var/obj/item/card/id/id_card = poster.GetIdCard()
	if(!id_card || !id_card.associated_account_number)
		return null
	var/datum/money_account/poster_account = SSeconomy.get_account(id_card.associated_account_number)
	if(!poster_account || poster_account.money < reward)
		return null
	if(!SSpersistence.databaseCheckConnection("post_bounty"))
		return null

	poster_account.adjust_money(-reward)

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_bounties (map_path, poster_ckey, poster_account_number, target_ckey, target_name, reward, status)
		VALUES (:mp, :pk, :pan, :tck, :tn, :reward, 'open')"},
		list(
			"mp"   = "[SSatlas.current_map.path]",
			"pk"   = poster.ckey,
			"pan"  = poster_account.account_number,
			"tck"  = target_ckey,
			"tn"   = target_name,
			"reward" = reward
		)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "post_bounty")
	var/new_id = text2num(q.last_insert_id)
	qdel(q)

	var/list/row = list(
		"id" = new_id,
		"poster_ckey" = poster.ckey,
		"poster_account_number" = poster_account.account_number,
		"target_ckey" = target_ckey,
		"target_name" = target_name,
		"reward" = reward,
		"status" = "open",
		"accepters" = list()
	)
	GLOB.active_bounties += list(row)
	return row

/// Finds a cached bounty row by id, or null.
/proc/get_bounty_by_id(bounty_id)
	for(var/list/row in GLOB.active_bounties)
		if(row["id"] == bounty_id)
			return row
	return null

/**
 * Accepts an open bounty -- adds accepter_ckey to its accepters list. Any
 * number of people can accept the same bounty; whoever lands the kill first
 * wins the payout. Returns TRUE on success, FALSE if the bounty doesn't
 * exist, isn't open, or accepter_ckey has already accepted it.
 */
/proc/accept_bounty(bounty_id, accepter_ckey)
	var/list/row = get_bounty_by_id(bounty_id)
	if(!row || row["status"] != "open" || (accepter_ckey in row["accepters"]))
		return FALSE
	if(!SSpersistence.databaseCheckConnection("accept_bounty"))
		return FALSE

	row["accepters"] += accepter_ckey

	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_bounties SET accepters = :ak WHERE id = :id",
		list("ak" = json_encode(row["accepters"]), "id" = bounty_id)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "accept_bounty")
	qdel(q)
	return TRUE

/**
 * Cancels an open bounty (regardless of how many have accepted it) and
 * refunds the poster. Returns TRUE on success, FALSE if the bounty doesn't
 * exist or is already claimed/cancelled.
 */
/proc/cancel_bounty(bounty_id)
	var/list/row = get_bounty_by_id(bounty_id)
	if(!row || row["status"] != "open")
		return FALSE
	if(!SSpersistence.databaseCheckConnection("cancel_bounty"))
		return FALSE

	var/datum/money_account/poster_account = SSeconomy.get_account(row["poster_account_number"])
	if(poster_account)
		poster_account.adjust_money(row["reward"])

	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_bounties SET status = 'cancelled' WHERE id = :id",
		list("id" = bounty_id)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "cancel_bounty")
	qdel(q)

	GLOB.active_bounties -= list(row)
	return TRUE

/**
 * Called from /mob/living/carbon/human/death() -- pays out any open bounty
 * on victim (matched by ckey + character name together, since one ckey can
 * play several different characters over time) if killer is ANY of its
 * accepters -- first accepter to land the kill wins the payout, whether or
 * not others also accepted it.
 */
/proc/check_bounty_kill(mob/living/carbon/human/victim, mob/killer)
	if(!victim || !victim.ckey || !victim.real_name || !killer || !killer.ckey)
		return
	for(var/list/row in GLOB.active_bounties)
		if(row["status"] != "open")
			continue
		if(row["target_ckey"] != victim.ckey || row["target_name"] != victim.real_name)
			continue
		if(!(killer.ckey in row["accepters"]))
			continue
		if(!SSpersistence.databaseCheckConnection("check_bounty_kill"))
			return

		var/datum/money_account/killer_account = SSeconomy.get_account_by_ckey(killer.ckey)
		if(killer_account)
			killer_account.adjust_money(row["reward"])
			ping_bounties_program(killer.ckey, "Bounty collected -- [row["reward"]] cr for [row["target_name"]].")

		var/datum/db_query/q = SSdbcore.NewQuery(
			"UPDATE ss13_bounties SET status = 'claimed', claimed_by_ckey = :ck, claimed_at = NOW() WHERE id = :id",
			list("ck" = killer.ckey, "id" = row["id"])
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "check_bounty_kill")
		qdel(q)

		ping_bounties_program(row["poster_ckey"], "Your bounty on [row["target_name"]] has been claimed by [killer.name].")

		GLOB.active_bounties -= list(row)
		return
