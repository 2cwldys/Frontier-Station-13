/*
 * Persistence - Faction Shareholders
 * Percentage-of-company equity against a faction's own stock listing (see
 * persistence_stock_market.dm's stockMarketListFaction()) -- distinct from
 * the per-share "stockholders" traded on the open exchange
 * (ss13_stock_holdings). A stake is granted by redeeming a printed Share
 * Certificate (code/modules/paperwork/share_certificate.dm, printed via
 * faction_manage.dm's "print_share_certificate" action) and pays out via
 * "Pay Dividends" (faction_manage.dm) by raw percent, keyed by
 * (faction_uid, ckey, char_name) -- same per-character identity pairing
 * ss13_money_accounts/ss13_stock_holdings already use, so a second character
 * on the same ckey holds an independent stake.
 *
 * Listing a faction seeds whoever performed the listing at 100% (see
 * "list_on_exchange", faction_manage.dm) -- every grant after that
 * proportionally dilutes the existing cap table (factionGrantShareholder()),
 * so percent always sums to exactly 100 for a listed faction.
 */

/// faction_uid -> list of list("ckey"=, "char_name"=, "percent"=), loaded in
/// bulk at boot (factionShareholdersInitialize()).
GLOBAL_LIST_EMPTY(persistence_faction_shareholders_cache)

/datum/controller/subsystem/persistence/proc/factionShareholdersInitialize()
	if(!databaseCheckConnection("factionShareholdersInitialize"))
		return
	var/list/loaded = list()
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT faction_uid, ckey, char_name, percent FROM ss13_faction_shareholders", list())
	q.Execute()
	if(databaseCheckQueryResult(q, "factionShareholdersInitialize"))
		while(q.NextRow())
			var/fuid = q.item[1]
			LAZYADD(loaded[fuid], list(list("ckey" = q.item[2], "char_name" = q.item[3], "percent" = text2num(q.item[4]))))
		GLOB.persistence_faction_shareholders_cache = loaded
	qdel(q)

/// Sum of every granted percent for faction_uid -- 0 for a faction that
/// hasn't been listed/seeded yet, always exactly 100 afterward (each grant
/// dilutes the existing cap table rather than adding on top of it -- see
/// factionGrantShareholder()).
/proc/faction_shareholder_total_percent(faction_uid)
	var/list/held = GLOB.persistence_faction_shareholders_cache[faction_uid]
	var/total = 0
	if(islist(held))
		for(var/list/h in held)
			total += h["percent"]
	return total

/**
 * Wipes every equity shareholder stake for faction_uid -- called by
 * stockMarketRevokeFaction() (persistence_stock_market.dm) when a faction's
 * stock exchange listing is revoked. Previously only the tradable
 * ss13_stock_holdings were cleared on revoke; this separate equity cap table
 * (seeded 100% to whoever listed the faction, diluted by share certificates)
 * was left untouched, so is_faction_ceo() kept finding the old majority
 * holder and "(CEO)" kept showing in Faction Management after a revoke --
 * contradicting this file's own is_faction_ceo() doc comment, which already
 * assumed FALSE "if this faction has no shareholders yet (never listed, or
 * delisted/dissolved)".
 */
/datum/controller/subsystem/persistence/proc/factionClearShareholders(faction_uid)
	GLOB.persistence_faction_shareholders_cache -= faction_uid
	if(!databaseCheckConnection("factionClearShareholders"))
		return
	var/datum/db_query/q = SSdbcore.NewQuery(
		"DELETE FROM ss13_faction_shareholders WHERE faction_uid = :uid",
		list("uid" = faction_uid)
	)
	q.Execute()
	databaseCheckQueryResult(q, "factionClearShareholders")
	qdel(q)

/// This (ckey, char_name)'s existing stake in faction_uid, or null.
/proc/faction_shareholder_get(faction_uid, ckey, char_name)
	var/list/held = GLOB.persistence_faction_shareholders_cache[faction_uid]
	if(!islist(held))
		return null
	for(var/list/h in held)
		if(h["ckey"] == ckey && h["char_name"] == char_name)
			return h
	return null

/// TRUE if (ckey, char_name) currently holds the single highest -- or is
/// tied for the highest -- granted shareholder percentage in faction_uid.
/// Multiple shareholders tied for the top spot are ALL CEO simultaneously
/// (co-CEOs, confirmed with the user). FALSE if this faction has no
/// shareholders yet (never listed, or delisted/dissolved).
/proc/is_faction_ceo(faction_uid, ckey, char_name)
	var/list/held = GLOB.persistence_faction_shareholders_cache[faction_uid]
	if(!islist(held) || !length(held))
		return FALSE
	var/highest = 0
	var/mine = 0
	var/found = FALSE
	for(var/list/h in held)
		if(h["percent"] > highest)
			highest = h["percent"]
		if(h["ckey"] == ckey && h["char_name"] == char_name)
			mine = h["percent"]
			found = TRUE
	return found && mine > 0 && mine == highest

/// Grants (or, for every grant after the first, proportionally dilutes the
/// existing cap table to make room for) a shareholder stake. The FIRST grant
/// for a faction (current total 0 -- i.e. the "list_on_exchange" 100% seed)
/// is inserted directly, nothing to dilute yet. Every grant after that
/// shrinks every existing holder's percent by the same factor so the total
/// allocated never changes, then adds the new percent on top of the
/// recipient's own (possibly pre-existing) stake -- the standard real-world
/// equivalent of a company issuing new shares. Returns null on success, or a
/// user-facing refusal reason.
/datum/controller/subsystem/persistence/proc/factionGrantShareholder(faction_uid, ckey, char_name, percent, granted_by, certificate_id)
	if(percent <= 0)
		return "Invalid percentage."
	if(!databaseCheckConnection("factionGrantShareholder"))
		return "Database connection failed."

	var/list/held = GLOB.persistence_faction_shareholders_cache[faction_uid]
	var/current_total = 0
	if(islist(held))
		for(var/list/h in held)
			current_total += h["percent"]

	if(current_total > 0)
		if(percent >= current_total)
			return "Cannot issue that much -- only [current_total]% of the company is currently allocated to dilute from."
		var/scale = (current_total - percent) / current_total
		for(var/list/h in held)
			var/diluted = round(h["percent"] * scale, 0.01)
			h["percent"] = diluted
			var/datum/db_query/dq = SSdbcore.NewQuery(
				"UPDATE ss13_faction_shareholders SET percent = :pct WHERE faction_uid = :uid AND ckey = :ckey AND char_name = :name",
				list("pct" = diluted, "uid" = faction_uid, "ckey" = h["ckey"], "name" = h["char_name"])
			)
			dq.Execute()
			databaseCheckQueryResult(dq, "factionGrantShareholder dilute")
			qdel(dq)

	var/list/existing = faction_shareholder_get(faction_uid, ckey, char_name)
	var/new_percent = (existing ? existing["percent"] : 0) + percent
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_faction_shareholders (faction_uid, ckey, char_name, percent, granted_by, certificate_id)
		VALUES (:uid, :ckey, :name, :pct, :by, :cert)
		ON DUPLICATE KEY UPDATE percent = VALUES(percent), granted_by = VALUES(granted_by), certificate_id = VALUES(certificate_id)"},
		list("uid" = faction_uid, "ckey" = ckey, "name" = char_name, "pct" = new_percent, "by" = granted_by, "cert" = certificate_id)
	)
	q.Execute()
	if(!databaseCheckQueryResult(q, "factionGrantShareholder grant"))
		qdel(q)
		return "Database write failed."
	qdel(q)

	if(existing)
		existing["percent"] = new_percent
	else
		LAZYADD(GLOB.persistence_faction_shareholders_cache[faction_uid], list(list("ckey" = ckey, "char_name" = char_name, "percent" = new_percent)))
	return null
