/*
 * Persistence - Personal Cargo Specialization
 * FACTION_CARGO_SPECIALIZATION's personal-console equivalent
 * (code/_compile_options.dm) -- an individual player, not acting through a
 * faction, ordering from a PERSONALLY-tagged cargo console/PDA
 * (personal_ckey/personal_char_name, modular_computer/variables.dm) is
 * limited to ordering from ONE cargo category, chosen once and then locked
 * for 30 real days before it can change. Mirrors persistence_factions.dm's
 * own get/set_faction_allowed_cargo_category() shape, keyed by (ckey,
 * char_name) instead of faction_uid -- the same composite key
 * ss13_char_identity/ss13_mob_position already use for per-character state.
 *
 * No in-memory cache (unlike the small, bounded faction set) -- always
 * queried live against SQL, matching persistence_mobs.dm's imprisonment-
 * expiry precedent (real calendar time, not world.time -- must survive
 * reboots).
 *
 * Consumed by: code/modules/modular_computers/file_system/programs/civilian/cargo_order.dm
 */

/// The ONE cargo order category (or null, "hasn't chosen one yet") this
/// (ckey, char_name) is currently allowed to order from on a personally-
/// tagged console.
/proc/get_personal_cargo_category(ckey, char_name)
	if(!ckey || !char_name)
		return null
	if(!SSpersistence.databaseCheckConnection("get_personal_cargo_category"))
		return null
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT allowed_cargo_category FROM ss13_personal_cargo_category WHERE ckey = :ckey AND char_name = :char_name",
		list("ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()
	. = null
	if(SSpersistence.databaseCheckQueryResult(q, "get_personal_cargo_category") && q.NextRow())
		. = q.item[1]
	qdel(q)

/// Seconds remaining before this (ckey, char_name)'s personal cargo category
/// can next be changed, 0 if clear/never-set (the very first choice is
/// always free, same guard the faction version uses).
/proc/get_personal_cargo_category_cooldown_remaining(ckey, char_name)
	if(!ckey || !char_name)
		return 0
	if(!SSpersistence.databaseCheckConnection("get_personal_cargo_category_cooldown_remaining"))
		return 0
	var/datum/db_query/q = SSdbcore.NewQuery(
		"SELECT TIMESTAMPDIFF(SECOND, NOW(), DATE_ADD(cargo_category_changed_at, INTERVAL 30 DAY)) FROM ss13_personal_cargo_category WHERE ckey = :ckey AND char_name = :char_name AND cargo_category_changed_at IS NOT NULL",
		list("ckey" = ckey, "char_name" = char_name)
	)
	q.Execute()
	. = 0
	if(SSpersistence.databaseCheckQueryResult(q, "get_personal_cargo_category_cooldown_remaining") && q.NextRow())
		. = max(0, text2num(q.item[1]) || 0)
	qdel(q)

/// Sets this (ckey, char_name)'s single allowed personal cargo category.
/// Refuses (returns FALSE) if the 30-day real-world cooldown since the last
/// change hasn't elapsed yet, unless bypass_cooldown is set.
/proc/set_personal_cargo_category(ckey, char_name, category, bypass_cooldown = FALSE)
	if(!ckey || !char_name || !category)
		return FALSE
	if(!bypass_cooldown && get_personal_cargo_category_cooldown_remaining(ckey, char_name) > 0)
		return FALSE
	if(!SSpersistence.databaseCheckConnection("set_personal_cargo_category"))
		return FALSE
	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_personal_cargo_category (ckey, char_name, allowed_cargo_category, cargo_category_changed_at)
		VALUES (:ckey, :char_name, :cat, NOW())
		ON DUPLICATE KEY UPDATE allowed_cargo_category = :cat, cargo_category_changed_at = NOW()"},
		list("ckey" = ckey, "char_name" = char_name, "cat" = category)
	)
	q.Execute()
	. = SSpersistence.databaseCheckQueryResult(q, "set_personal_cargo_category")
	qdel(q)
