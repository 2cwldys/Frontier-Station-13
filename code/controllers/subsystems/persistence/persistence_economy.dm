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
		"SELECT ckey, char_name, account_number, money, remote_access_pin, public_account, suspended, security_level, transaction_log \
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
			"transaction_log"   = query.item[9]
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
		 (ckey, char_name, account_number, money, remote_access_pin, public_account, suspended, security_level, transaction_log, saved_at) \
		 VALUES (:ckey, :char_name, :account_number, :money, :pin, :public_account, :suspended, :security_level, :tx_log, NOW()) \
		 ON DUPLICATE KEY UPDATE \
		 account_number=VALUES(account_number), money=VALUES(money), remote_access_pin=VALUES(remote_access_pin), \
		 public_account=VALUES(public_account), suspended=VALUES(suspended), security_level=VALUES(security_level), \
		 transaction_log=VALUES(transaction_log), saved_at=NOW()",
		list(
			"ckey"           = ckey_override,
			"char_name"      = name_override,
			"account_number" = account.account_number,
			"money"          = account.money,
			"pin"            = account.remote_access_pin,
			"public_account" = account.public_account ? 1 : 0,
			"suspended"      = account.suspended ? 1 : 0,
			"security_level" = account.security_level,
			"tx_log"         = json_encode(tx_list)
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
		return null

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
