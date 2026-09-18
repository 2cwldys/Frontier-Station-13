/*
 * 18+ Age Verification
 * Gated entirely behind GLOB.config.intimate_interactions_allowed -- when
 * that's off, none of this runs at all (see new_player/login.dm's
 * LateLogin()). ss13_age_verification is a small, dedicated, ckey-only table
 * (not a bit in ss13_player_preferences.toggles_secondary) since this flag
 * carries real policy/audit weight, not just a UI preference.
 */

/// TRUE if this ckey has already confirmed 18+. Direct indexed SELECT, no
/// caching -- this only runs once per connecting client, not a hot path.
/// Fails open (returns TRUE, i.e. skip the gate) if the DB is unreachable,
/// matching this codebase's convention of never blocking play on an
/// infrastructure hiccup.
/proc/age_verification_check(ckey)
	if(!establish_db_connection(GLOB.dbcon))
		return TRUE
	var/DBQuery/query = GLOB.dbcon.NewQuery("SELECT ckey FROM ss13_age_verification WHERE ckey = '[ckey(ckey)]'")
	query.Execute()
	return query.NextRow()

/// Records a ckey's "Yes" answer. Upsert -- a brand new connection's
/// ss13_player row isn't guaranteed to exist yet, so a plain INSERT with no
/// FK dependency is what's safe here (PK is ckey alone).
/proc/age_verification_set(ckey)
	if(!establish_db_connection(GLOB.dbcon))
		return
	var/DBQuery/query = GLOB.dbcon.NewQuery("INSERT INTO ss13_age_verification (ckey, verified_at) VALUES ('[ckey(ckey)]', Now()) ON DUPLICATE KEY UPDATE verified_at = verified_at")
	query.Execute()
