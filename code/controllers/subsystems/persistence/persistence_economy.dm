/*
 * Persistence - Economy
 * Saves and restores money accounts across server restarts via SQL.
 * Hooked into SSpersistence Initialize() and Shutdown().
 *
 * Player accounts keyed by (ckey, char_name).
 * Station account saved with sentinel ckey "_station_" / char_name "Station Account".
 * Department accounts saved with sentinel ckey "_dept_[dept]_" / char_name "[dept] Department".
 */

/// Cached account data loaded at round start, keyed by "[ckey]|[char_name]"
GLOBAL_LIST_EMPTY(persistence_economy_cache)

// ============================================================
// CENTRAL MONEY SYNC (CENTRAL_SYNC_MONEY)
// ============================================================
//
// Purely additive on top of the existing local save/restore machinery
// above and below -- economySaveAccountNow()/_economySaveOneAccount()/
// economyFinalize()/economyInitialize() are NOT modified by any of this,
// local behavior is unchanged. Two separate mechanisms, matching the two
// very different risk profiles found auditing this table:
//
// - `money` is real-time, SQL-side-delta-only (economyApplyMoneyDeltaCentral()),
//   called from adjust_money() (economy.dm) the moment a transaction
//   happens -- the same lost-update risk ss13_faction_accounts.balance had
//   (persistence_factions.dm), fixed the same way: never write an absolute
//   value centrally, only ever `money = money + :delta`, so two servers'
//   concurrent transactions on the same account both apply correctly
//   regardless of order or which server's cache was stale.
// - Everything else on the row (account_number, remote_access_pin,
//   public_account, suspended, security_level, transaction_log,
//   intro_shown) is low-stakes metadata, mutated by several scattered
//   setters (ATM.dm, card.dm, account_database.dm) rather than one
//   chokepoint -- instead of chasing each one individually, it's synced
//   centrally as a periodic last-write-wins upsert piggybacked on the
//   existing economyFinalize() sweep (one added call at the end of that
//   proc's own body, not a rewrite of it), the same acceptable-risk
//   reasoning faction metadata got: touched by whoever's actively
//   managing one account, not routine concurrent gameplay.
//
// Known, disclosed gap: `account_number` has no cross-server uniqueness
// guarantee (see V009__money_sync.sql's own header) -- not fixed here.

/// Shared gate, same shape as _centralCharacterSyncActive()/
/// _factionCentralSyncActive().
/proc/_economyCentralSyncActive()
	if(!GLOB.config.central_sql_enabled || !GLOB.config.central_sync_money)
		return FALSE
	return SSpersistence.centralDatabaseReachable()

/// Real-time central delta write for a transaction just applied to
/// account.money -- called from adjust_money() (economy.dm) right after
/// the local += already happened. Station/department accounts (no ckey)
/// stay local-only -- they're not tied to a character, so "follows the
/// player across servers" has no meaning for them.
///
/// The central row might not exist yet (this account's first-ever
/// transaction since CENTRAL_SYNC_MONEY was turned on) -- INSERT IGNORE
/// seeds it with this server's CURRENT balance minus this delta (i.e. the
/// balance as it stood immediately before this transaction), the best
/// available approximation of this account's prior history, rather than
/// starting central at 0 and silently discarding everything earned
/// before central sync existed for it. A no-op if the row already exists.
/proc/economyApplyMoneyDeltaCentral(datum/money_account/account, delta)
	if(!account || !account.ckey || !delta)
		return
	if(!_economyCentralSyncActive())
		return

	var/datum/db_query/seed = SScentraldb.NewQuery(
		"INSERT IGNORE INTO `ss13_money_accounts` (ckey, char_name, account_number, money) VALUES (:ckey, :char_name, :acct, :money)",
		list("ckey" = account.ckey, "char_name" = account.owner_name, "acct" = account.account_number, "money" = account.money - delta)
	)
	seed.Execute()
	qdel(seed)

	var/datum/db_query/q = SScentraldb.NewQuery(
		"UPDATE `ss13_money_accounts` SET money = money + :delta, saved_at = NOW() WHERE ckey = :ckey AND char_name = :char_name",
		list("ckey" = account.ckey, "char_name" = account.owner_name, "delta" = delta)
	)
	q.Execute()
	qdel(q)

/// Periodic metadata write-through -- called once at the end of
/// economyFinalize() (below), covering every account that proc already
/// iterates. Deliberately never includes `money` in its UPDATE clause
/// (only in the INSERT branch, for a brand new row) -- see this section's
/// own header comment for why money is real-time-delta-only, never
/// touched by this periodic absolute upsert.
/proc/_economyMetadataSyncCentralAll()
	if(!_economyCentralSyncActive())
		return

	for(var/account_key in SSeconomy.all_money_accounts)
		var/datum/money_account/account = SSeconomy.all_money_accounts[account_key]
		if(!account.ckey)
			continue
		_economyMetadataWriteThroughCentral(account, account.ckey, account.owner_name)

/proc/_economyMetadataWriteThroughCentral(datum/money_account/account, ckey_override, name_override)
	var/list/tx_list = list()
	for(var/datum/transaction/T in account.transactions)
		tx_list += list(list(
			"target_name"    = T.target_name,
			"purpose"        = T.purpose,
			"amount"         = T.amount,
			"date"           = T.date,
			"time"           = T.time,
			"source_terminal"= T.source_terminal
		))
	var/datum/db_query/q = SScentraldb.NewQuery(
		{"INSERT INTO `ss13_money_accounts`
		(ckey, char_name, account_number, money, remote_access_pin, public_account, suspended, security_level, transaction_log, intro_shown)
		VALUES (:ckey, :char_name, :account_number, :money, :pin, :public_account, :suspended, :security_level, :tx_log, :intro_shown)
		ON DUPLICATE KEY UPDATE
		account_number=VALUES(account_number), remote_access_pin=VALUES(remote_access_pin),
		public_account=VALUES(public_account), suspended=VALUES(suspended), security_level=VALUES(security_level),
		transaction_log=VALUES(transaction_log), intro_shown=VALUES(intro_shown), saved_at=NOW()"},
		list(
			"ckey"           = ckey_override,
			"char_name"      = name_override,
			"account_number" = account.account_number,
			"money"          = account.money,
			"pin"            = account.remote_access_pin,
			"public_account" = account.public_account ? 1 : 0,
			"suspended"      = account.suspended ? 1 : 0,
			"security_level" = account.security_level,
			"tx_log"         = json_encode(tx_list),
			"intro_shown"    = account.intro_shown ? 1 : 0
		)
	)
	q.Execute()
	qdel(q)

/// Read-through-on-miss for a character's money account -- called from
/// restoreAccountFromPersistence() (economy.dm) when the local cache has
/// nothing for this ckey|char_name. A hit populates the in-memory cache
/// AND writes the row into this server's own local table (self-heal),
/// same pattern as every other central read-through this session. Does
/// NOT create a live /datum/money_account -- restoreAccountFromPersistence()
/// itself does that from the cache entry this returns into, same as it
/// already does for a normal local cache hit.
/proc/_economyHydrateAccountFromCentral(ckey, char_name)
	if(!_economyCentralSyncActive())
		return FALSE

	var/datum/db_query/q = SScentraldb.NewQuery(
		{"SELECT account_number, money, remote_access_pin, public_account, suspended, security_level, transaction_log, intro_shown
		FROM `ss13_money_accounts` WHERE ckey = :ckey AND char_name = :char_name"},
		list("ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()
	if(!q.NextRow())
		qdel(q)
		return FALSE

	var/list/entry = list(
		"ckey"              = ckey,
		"char_name"         = char_name,
		"account_number"    = text2num(q.item[1]),
		"money"             = text2num(q.item[2]),
		"remote_access_pin" = q.item[3],
		"public_account"    = text2num(q.item[4]),
		"suspended"         = text2num(q.item[5]),
		"security_level"    = text2num(q.item[6]),
		"transaction_log"   = q.item[7],
		"intro_shown"       = text2num(q.item[8])
	)
	qdel(q)

	GLOB.persistence_economy_cache["[ckey]|[char_name]"] = entry

	// Self-heal -- write into this server's own local table too, same
	// reasoning as every other central read-through this session.
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/lq = SSdbcore.NewQuery(
			{"INSERT INTO ss13_money_accounts
			(ckey, char_name, account_number, money, remote_access_pin, public_account, suspended, security_level, transaction_log, intro_shown, saved_at)
			VALUES (:ckey, :char_name, :account_number, :money, :pin, :public_account, :suspended, :security_level, :tx_log, :intro_shown, NOW())
			ON DUPLICATE KEY UPDATE money = VALUES(money), account_number = VALUES(account_number)"},
			list(
				"ckey" = ckey, "char_name" = char_name, "account_number" = entry["account_number"], "money" = entry["money"],
				"pin" = entry["remote_access_pin"], "public_account" = entry["public_account"], "suspended" = entry["suspended"],
				"security_level" = entry["security_level"], "tx_log" = entry["transaction_log"], "intro_shown" = entry["intro_shown"]
			)
		)
		lq.Execute()
		qdel(lq)

	return TRUE

/**
 * Load saved money account data from the database into the in-memory cache.
 * Called from SSpersistence.Initialize() before characters spawn.
 */
/datum/controller/subsystem/persistence/proc/economyInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_economy_cache = list()

	if(!databaseCheckConnection("economyInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, account_number, money, remote_access_pin, public_account, suspended, security_level, transaction_log, intro_shown \
		 FROM ss13_money_accounts"
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "economyInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/list/entry = list(
			"ckey"              = query.item[1],
			"char_name"         = query.item[2],
			"account_number"    = text2num(query.item[3]),
			"money"             = text2num(query.item[4]),
			"remote_access_pin" = query.item[5],
			"public_account"    = text2num(query.item[6]),
			"suspended"         = text2num(query.item[7]),
			"security_level"    = text2num(query.item[8]),
			"transaction_log"   = query.item[9],
			"intro_shown"       = text2num(query.item[10])
		)
		var/cache_key = "[query.item[1]]|[query.item[2]]"
		GLOB.persistence_economy_cache[cache_key] = entry
		loaded++

	qdel(query)
	log_subsystem_persistence_info("Economy: Loaded [loaded] saved money accounts.")

	// Restore station account balance from DB (SSeconomy already created it with default 35000)
	var/list/station_saved = GLOB.persistence_economy_cache["_station_|Station Account"]
	if(station_saved && SSeconomy.station_account)
		SSeconomy.station_account.money = text2num(station_saved["money"]) || SSeconomy.station_account.money
		log_subsystem_persistence_info("Economy: Restored station account balance: [SSeconomy.station_account.money]")

	// Restore department account balances from DB
	for(var/dept in SSeconomy.department_accounts)
		var/list/dept_saved = GLOB.persistence_economy_cache["_dept_[dept]_|[dept] Department"]
		if(!dept_saved)
			continue
		var/datum/money_account/dept_acct = SSeconomy.department_accounts[dept]
		if(dept_acct)
			dept_acct.money = text2num(dept_saved["money"]) || dept_acct.money
	log_subsystem_persistence_info("Economy: Restored [length(SSeconomy.department_accounts)] department accounts.")

/**
 * Save all money accounts (player, station, department) to the database.
 * Called periodically by SSpersistence.fire() and on Shutdown().
 */
/datum/controller/subsystem/persistence/proc/economyFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("economyFinalize"))
		return

	var/saved = 0
	for(var/account_key in SSeconomy.all_money_accounts)
		CHECK_TICK
		var/datum/money_account/account = SSeconomy.all_money_accounts[account_key]
		if(!account.ckey)
			continue
		if(_economySaveOneAccount(account, account.ckey, account.owner_name))
			saved++

	// Save station and department accounts with sentinel ckeys
	if(SSeconomy.station_account)
		_economySaveOneAccount(SSeconomy.station_account, "_station_", "Station Account")

	for(var/dept in SSeconomy.department_accounts)
		CHECK_TICK
		var/datum/money_account/dept_acct = SSeconomy.department_accounts[dept]
		if(dept_acct)
			_economySaveOneAccount(dept_acct, "_dept_[dept]_", "[dept] Department")

	log_subsystem_persistence_info("Economy: Saved [saved] player accounts + station + [length(SSeconomy.department_accounts)] department accounts.")

	_economyMetadataSyncCentralAll()

/// Serialize and upsert a single money account. ckey_override and name_override allow
/// saving station/dept accounts with sentinel keys distinct from their runtime owner_name.
/datum/controller/subsystem/persistence/proc/_economySaveOneAccount(datum/money_account/account, ckey_override, name_override)
	PRIVATE_PROC(TRUE)
	var/list/tx_list = list()
	for(var/datum/transaction/T in account.transactions)
		tx_list += list(list(
			"target_name"    = T.target_name,
			"purpose"        = T.purpose,
			"amount"         = T.amount,
			"date"           = T.date,
			"time"           = T.time,
			"source_terminal"= T.source_terminal
		))
	var/datum/db_query/upsert = SSdbcore.NewQuery(
		"INSERT INTO ss13_money_accounts \
		 (ckey, char_name, account_number, money, remote_access_pin, public_account, suspended, security_level, transaction_log, intro_shown, saved_at) \
		 VALUES (:ckey, :char_name, :account_number, :money, :pin, :public_account, :suspended, :security_level, :tx_log, :intro_shown, NOW()) \
		 ON DUPLICATE KEY UPDATE \
		 account_number=VALUES(account_number), money=VALUES(money), remote_access_pin=VALUES(remote_access_pin), \
		 public_account=VALUES(public_account), suspended=VALUES(suspended), security_level=VALUES(security_level), \
		 transaction_log=VALUES(transaction_log), intro_shown=VALUES(intro_shown), saved_at=NOW()",
		list(
			"ckey"           = ckey_override,
			"char_name"      = name_override,
			"account_number" = account.account_number,
			"money"          = account.money,
			"pin"            = account.remote_access_pin,
			"public_account" = account.public_account ? 1 : 0,
			"suspended"      = account.suspended ? 1 : 0,
			"security_level" = account.security_level,
			"tx_log"         = json_encode(tx_list),
			"intro_shown"    = account.intro_shown ? 1 : 0
		)
	)
	upsert.Execute()
	var/ok = databaseCheckQueryResult(upsert, "economySaveOneAccount [ckey_override]/[name_override]")
	qdel(upsert)
	return ok

/// Immediately persists one account's current balance/transactions, instead of
/// waiting for the next economyFinalize() tick -- called right after any
/// balance-changing operation so a crash/early shutdown can't lose a
/// deduction whose purchase already happened in the live world.
/datum/controller/subsystem/persistence/proc/economySaveAccountNow(datum/money_account/account)
	if(!account || !databaseCheckConnection("economySaveAccountNow"))
		return
	if(account.ckey)
		_economySaveOneAccount(account, account.ckey, account.owner_name)
	else if(account == SSeconomy.station_account)
		_economySaveOneAccount(account, "_station_", "Station Account")
	else
		for(var/dept in SSeconomy.department_accounts)
			if(SSeconomy.department_accounts[dept] == account)
				_economySaveOneAccount(account, "_dept_[dept]_", "[dept] Department")
				return

/// Credits a ckey+char_name's account that may have no live /datum/money_account
/// object yet -- SSeconomy.get_account_by_ckey_and_name() only ever finds an
/// account once that specific character has actually spawned THIS boot
/// (restoreAccountFromPersistence() is spawn-triggered, nothing bulk-loads
/// every saved account into memory at round start), so a real, currently-
/// offline-this-session player would otherwise silently receive nothing --
/// confirmed as a real gap, e.g. a faction stock buyout paying out
/// shareholders who haven't logged in yet this round. Writes the DB row
/// directly AND the boot-time economy cache (persistence_economy_cache) --
/// the latter matters because restoreAccountFromPersistence() reads FROM
/// that cache (not a fresh DB query) if this same character spawns later
/// in the same round, so skipping it would let a late spawn silently
/// overwrite this credit with the stale pre-credit cached balance. Callers
/// should always try SSeconomy.get_account_by_ckey_and_name() first and
/// only fall back to this when it returns null.
/datum/controller/subsystem/persistence/proc/economyCreditOfflineAccount(ckey, char_name, amount)
	if(!ckey || !char_name || !amount)
		return FALSE
	if(!databaseCheckConnection("economyCreditOfflineAccount"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		"UPDATE ss13_money_accounts SET money = money + :amount WHERE ckey = :ckey AND char_name = :char_name",
		list("amount" = amount, "ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()
	var/ok = databaseCheckQueryResult(q, "economyCreditOfflineAccount")
	qdel(q)
	if(ok)
		var/list/cached = GLOB.persistence_economy_cache["[ckey]|[char_name]"]
		if(islist(cached))
			cached["money"] = (cached["money"] || 0) + amount
	return ok

/**
 * Attempt to restore a previously saved money account for the given mob.
 * Returns the restored account if found, null otherwise.
 * Called from SSeconomy.create_and_assign_account() before creating a fresh account.
 */
/datum/controller/subsystem/economy/proc/restoreAccountFromPersistence(var/mob/mob)
	if(!GLOB.config.sql_enabled || !GLOB.persistence_economy_cache)
		return null

	var/cache_key = "[mob.ckey]|[mob.real_name]"
	var/list/saved = GLOB.persistence_economy_cache[cache_key]
	if(!saved)
		// This server has never seen this character's account locally --
		// check centrally before giving up (CENTRAL_SYNC_MONEY).
		if(!_economyHydrateAccountFromCentral(mob.ckey, mob.real_name))
			return null
		saved = GLOB.persistence_economy_cache[cache_key]

	// Already materialized this session (e.g. rejoining the same round) --
	// return the live datum instead of overwriting it with stale cached data
	var/datum/money_account/existing = SSeconomy.all_money_accounts["[saved["account_number"]]"]
	if(existing)
		return existing

	var/datum/money_account/account = new()
	account.ckey             = mob.ckey
	account.owner_name       = mob.real_name
	account.account_number   = saved["account_number"] || SSeconomy.next_account_number
	account.money            = saved["money"] || 0
	account.remote_access_pin = saved["remote_access_pin"] || rand(1111, 111111)
	account.public_account   = saved["public_account"]
	account.suspended        = saved["suspended"]
	account.security_level   = saved["security_level"]
	account.intro_shown      = !!saved["intro_shown"]

	// Restore transaction log
	if(saved["transaction_log"])
		var/list/tx_list = json_decode(saved["transaction_log"])
		if(islist(tx_list))
			for(var/list/tx_entry in tx_list)
				var/datum/transaction/T = new()
				T.target_name     = tx_entry["target_name"] || ""
				T.purpose         = tx_entry["purpose"] || ""
				T.amount          = tx_entry["amount"] || 0
				T.date            = tx_entry["date"] || ""
				T.time            = tx_entry["time"] || ""
				T.source_terminal = tx_entry["source_terminal"] || ""
				account.transactions.Add(T)

	// Ensure account number doesn't collide
	if(account.account_number >= SSeconomy.next_account_number)
		SSeconomy.next_account_number = account.account_number + rand(1, 25)

	SSeconomy.all_money_accounts["[account.account_number]"] = account

	log_subsystem_persistence_info("Economy: Restored account for [mob.ckey] ([mob.real_name]), balance: [account.money]")
	return account
