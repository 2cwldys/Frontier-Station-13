/*
 * Persistence - Hub Law Book Print Cooldown
 * Keyed by ckey alone (one book per ckey per HUB_LAW_BOOK_PRINT_COOLDOWN,
 * card.dm), same (ckey)-keyed real-calendar-time shape as
 * persistence_personal_cargo_category.dm -- no in-memory cache, always
 * queried live against SQL so the cooldown survives a reboot.
 *
 * Consumed by: code/modules/modular_computers/file_system/programs/command/card.dm
 */

/// Remaining cooldown, in deciseconds (BYOND world.time units -- callers
/// compare this straight against the decisecond HUB_LAW_BOOK_PRINT_COOLDOWN
/// macro and feed it into DisplayTimeText()). 0 if never printed, or if the
/// DB is unavailable (fail open).
/proc/get_hub_law_book_cooldown_remaining(ckey)
	if(!ckey)
		return 0
	if(!SSpersistence.databaseCheckConnection("get_hub_law_book_cooldown_remaining"))
		return 0
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT TIMESTAMPDIFF(SECOND, NOW(), DATE_ADD(last_printed_at, INTERVAL [HUB_LAW_BOOK_PRINT_COOLDOWN / 10] SECOND)) FROM ss13_hub_law_book_cooldown WHERE ckey = :ckey",
		list("ckey" = ckey)
	)
	q.Execute()
	. = 0
	if(SSpersistence.databaseCheckQueryResult(q, "get_hub_law_book_cooldown_remaining") && q.NextRow())
		. = max(0, (text2num(q.item[1]) || 0) * 10)
	qdel(q)

/// Records a hub law book print at NOW() for this ckey.
/proc/set_hub_law_book_print_time(ckey)
	if(!ckey)
		return FALSE
	if(!SSpersistence.databaseCheckConnection("set_hub_law_book_print_time"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_hub_law_book_cooldown (ckey, last_printed_at)
		VALUES (:ckey, NOW())
		ON DUPLICATE KEY UPDATE last_printed_at = NOW()"},
		list("ckey" = ckey)
	)
	q.Execute()
	. = SSpersistence.databaseCheckQueryResult(q, "set_hub_law_book_print_time")
	qdel(q)
