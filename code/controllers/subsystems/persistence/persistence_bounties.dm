/*
 * Persistence - Bounties
 * Player-posted cash bounties on a specific character. Anyone can accept an
 * open bounty; if they land the killing blow, they're paid the reward to
 * their personal account and the bounty is marked claimed. Reward is
 * escrowed from the poster's account immediately on posting (post_bounty()),
 * refunded if the bounty is cancelled unclaimed (cancel_bounty()).
 * DB-backed (ss13_bounties, V087) with an in-memory cache of open/pending
 * rows so accepting/claiming never has to wait on a query.
 * Single-accepter-at-a-time: once a bounty is 'pending', no one else can
 * also accept it.
 */

/// Cached open/pending bounty rows: list of list(id, poster_ckey,
/// poster_account_number, target_ckey, target_name, reward, status,
/// accepter_ckey). Target is identified by (target_ckey, target_name)
/// together -- one ckey can play several different characters over time
/// (never simultaneously), so the pair is what actually pins down which
/// specific character is being bountied. Claimed/cancelled rows drop out of
/// the cache once resolved.
GLOBAL_LIST_EMPTY(active_bounties)

/**
 * Load open/pending bounties into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/bountiesInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.active_bounties = list()

	if(!databaseCheckConnection("bountiesInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT id, poster_ckey, poster_account_number, target_ckey, target_name, reward, status, accepter_ckey FROM ss13_bounties WHERE map_path = :mp AND status IN ('open', 'pending')",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "bountiesInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.active_bounties += list(list(
			"id"                  = text2num(query.item[1]),
			"poster_ckey"         = query.item[2],
			"poster_account_number" = text2num(query.item[3]),
			"target_ckey"         = query.item[4],
			"target_name"         = query.item[5],
			"reward"              = text2num(query.item[6]),
			"status"              = query.item[7],
			"accepter_ckey"       = query.item[8]
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
		"accepter_ckey" = null
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
 * Accepts an open bounty, locking it to accepter_ckey. Returns TRUE on
 * success, FALSE if the bounty doesn't exist or isn't open.
 */
/proc/accept_bounty(bounty_id, accepter_ckey)
	var/list/row = get_bounty_by_id(bounty_id)
	if(!row || row["status"] != "open")
		return FALSE
	if(!SSpersistence.databaseCheckConnection("accept_bounty"))
		return FALSE

	row["status"] = "pending"
	row["accepter_ckey"] = accepter_ckey

	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_bounties SET status = 'pending', accepter_ckey = :ak WHERE id = :id",
		list("ak" = accepter_ckey, "id" = bounty_id)
	)
	q.Execute()
	SSpersistence.databaseCheckQueryResult(q, "accept_bounty")
	qdel(q)
	return TRUE

/**
 * Cancels an open/pending bounty and refunds the poster. Returns TRUE on
 * success, FALSE if the bounty doesn't exist or is already claimed/cancelled.
 */
/proc/cancel_bounty(bounty_id)
	var/list/row = get_bounty_by_id(bounty_id)
	if(!row || !(row["status"] in list("open", "pending")))
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
 * Called from /mob/living/carbon/human/death() -- pays out any pending
 * bounty on victim (matched by ckey + character name together, since one
 * ckey can play several different characters over time) if killer is the
 * one who accepted it.
 */
/proc/check_bounty_kill(mob/living/carbon/human/victim, mob/killer)
	if(!victim || !victim.ckey || !victim.real_name || !killer || !killer.ckey)
		return
	for(var/list/row in GLOB.active_bounties)
		if(row["status"] != "pending")
			continue
		if(row["target_ckey"] != victim.ckey || row["target_name"] != victim.real_name)
			continue
		if(row["accepter_ckey"] != killer.ckey)
			continue
		if(!SSpersistence.databaseCheckConnection("check_bounty_kill"))
			return

		var/datum/money_account/killer_account = SSeconomy.get_account_by_ckey(killer.ckey)
		if(killer_account)
			killer_account.adjust_money(row["reward"])
			to_chat(killer, SPAN_GOOD("You've collected the [row["reward"]] cr bounty on [row["target_name"]]."))

		var/datum/db_query/q = SSdbcore.NewQuery(
			"UPDATE ss13_bounties SET status = 'claimed', claimed_at = NOW() WHERE id = :id",
			list("id" = row["id"])
		)
		q.Execute()
		SSpersistence.databaseCheckQueryResult(q, "check_bounty_kill")
		qdel(q)

		var/client/poster_client = GLOB.directory[row["poster_ckey"]]
		if(poster_client?.mob)
			to_chat(poster_client.mob, SPAN_NOTICE("Your bounty on [row["target_name"]] has been claimed by [killer.name]."))

		GLOB.active_bounties -= list(row)
		return
