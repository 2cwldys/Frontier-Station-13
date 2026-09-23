#!/bin/sh
# All-in-one health check for the Aurora persistence database: periodic-save
# freshness, persistent-object expiration, and JSON blob integrity, all from
# one command instead of a pile of manual queries.
# Native translation of db_diagnostics.ps1 -- no PowerShell dependency. See
# that script's own header comment for the full rationale behind each check.
#
# Usage: db_diagnostics.sh [stale_warning_minutes] [stale_critical_minutes]
#   Defaults: 45 (warning), 360 (critical)

set -u

STALE_WARN="${1:-45}"
STALE_CRIT="${2:-360}"

WARN_COUNT=0
CRIT_COUNT=0

sql() {
	# -N: skip the header row, for output meant to be parsed.
	docker exec aurora-db mariadb -N -u aurora -paurora aurora_persist -e "$1"
}

sql_table() {
	# Keeps headers -- for output meant to be read as-is.
	docker exec aurora-db mariadb -u aurora -paurora aurora_persist -e "$1"
}

status() {
	# $1 = level (OK/WARN/CRIT), $2 = message
	case "$1" in
		OK)   echo "  [OK]       $2" ;;
		WARN) echo "  [WARN]     $2"; WARN_COUNT=$((WARN_COUNT + 1)) ;;
		CRIT) echo "  [CRITICAL] $2"; CRIT_COUNT=$((CRIT_COUNT + 1)) ;;
	esac
}

# --- Connectivity (same two-gate pattern as db_backup.sh/db_restore.sh) ----
MAX_WAIT=10
POLL=2

WAITED=0
DAEMON_READY=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
	if docker info >/dev/null 2>&1; then DAEMON_READY=1; break; fi
	sleep "$POLL"
	WAITED=$((WAITED + POLL))
done
if [ "$DAEMON_READY" -ne 1 ]; then
	echo "Docker daemon did not respond within ${MAX_WAIT}s." >&2
	exit 2
fi

WAITED=0
DB_READY=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
	if docker exec aurora-db mysqladmin ping -u aurora -paurora --silent >/dev/null 2>&1; then DB_READY=1; break; fi
	sleep "$POLL"
	WAITED=$((WAITED + POLL))
done
if [ "$DB_READY" -ne 1 ]; then
	echo "aurora-db didn't answer a ping within ${MAX_WAIT}s." >&2
	exit 2
fi

echo "Aurora DB Diagnostics -- $(date '+%Y-%m-%d %H:%M:%S')"

# ============================================================================
# 1. SAVE FRESHNESS
# ============================================================================
echo ""
echo "=== 1. Save freshness (periodic autosave health) ==="

check_freshness() {
	# $1 = table, $2 = column, $3 = label
	MINUTES=$(sql "SELECT TIMESTAMPDIFF(MINUTE, MAX($2), NOW()) FROM $1;" | tr -d '[:space:]')
	if [ -z "$MINUTES" ] || [ "$MINUTES" = "NULL" ]; then
		status WARN "$3 ($1): table is empty -- nothing to compare."
		return
	fi
	if [ "$MINUTES" -ge 1440 ]; then
		AGE="$((MINUTES / 1440))d $((MINUTES % 1440 / 60))h ago"
	elif [ "$MINUTES" -ge 60 ]; then
		AGE="$((MINUTES / 60))h $((MINUTES % 60))m ago"
	else
		AGE="${MINUTES}m ago"
	fi

	if [ "$MINUTES" -ge "$STALE_CRIT" ]; then
		status CRIT "$3 ($1): last write was $AGE -- forceSaveAll() has very likely stopped firing entirely. Check the F5 admin stat panel's Persistence line (PAUSED vs active) and server logs for 'Periodic save' entries."
	elif [ "$MINUTES" -ge "$STALE_WARN" ]; then
		status WARN "$3 ($1): last write was $AGE -- one or more autosave cycles were likely missed."
	else
		status OK "$3 ($1): last write $AGE."
	fi
}

check_freshness ss13_worldstate_objects saved_at "World-state (machinery/airlock state)"
check_freshness ss13_char_health        saved_at "Character health"
check_freshness ss13_char_inventory     saved_at "Character inventory"
check_freshness ss13_char_skills        saved_at "Character skills"
check_freshness ss13_char_identity      saved_at "Character identity"
check_freshness ss13_char_lace_dna      saved_at "Neural lace DNA"

echo "  Note: ss13_floor_items has no per-row timestamp of its own -- it's rewritten"
echo "  in the same forceSaveAll() pass as ss13_worldstate_objects, so that row above"
echo "  is also floor_items' own freshness by proxy."

# ============================================================================
# 2. PERSISTENT-OBJECT EXPIRATION
# ============================================================================
echo ""
echo "=== 2. Persistent-object expiration (ss13_persistent_objects) ==="

RESULT=$(sql "SELECT COUNT(*), SUM(CASE WHEN expires_at <= NOW() THEN 1 ELSE 0 END), MIN(CASE WHEN expires_at <= NOW() THEN expires_at END) FROM ss13_persistent_objects;")
TOTAL=$(echo "$RESULT" | awk '{print $1}')
EXPIRED=$(echo "$RESULT" | awk '{print $2}')
OLDEST=$(echo "$RESULT" | cut -f3)
[ "$EXPIRED" = "NULL" ] && EXPIRED=0

if [ "$TOTAL" = "0" ]; then
	status OK "ss13_persistent_objects: empty table."
elif [ "$EXPIRED" = "0" ]; then
	status OK "ss13_persistent_objects: 0/$TOTAL expired."
else
	PCT=$(( EXPIRED * 100 / TOTAL ))
	if [ "$PCT" -ge 25 ]; then
		status CRIT "ss13_persistent_objects: $EXPIRED/$TOTAL (${PCT}%) expired, oldest since $OLDEST -- run db_fix_expired_objects.sh."
	else
		status WARN "ss13_persistent_objects: $EXPIRED/$TOTAL (${PCT}%) expired, oldest since $OLDEST -- review before fixing."
	fi
	echo ""
	echo "  Top expired types:"
	sql_table "SELECT type, COUNT(*) AS expired FROM ss13_persistent_objects WHERE expires_at <= NOW() GROUP BY type ORDER BY expired DESC LIMIT 10;" | sed 's/^/  /'
fi

# ============================================================================
# 3. JSON BLOB VALIDITY
# ============================================================================
echo ""
echo "=== 3. JSON blob validity ==="

check_json() {
	# $1 = table, $2 = column
	RESULT=$(sql "SELECT
		SUM(CASE WHEN $2 IS NOT NULL AND $2 != '' AND JSON_VALID($2) = 0 THEN 1 ELSE 0 END),
		SUM(CASE WHEN $2 LIKE CONCAT('%', UNHEX('EFBFBD'), '%') THEN 1 ELSE 0 END)
		FROM $1;")
	INVALID=$(echo "$RESULT" | awk '{print $1}')
	MANGLED=$(echo "$RESULT" | awk '{print $2}')
	[ "$INVALID" = "NULL" ] && INVALID=0
	[ "$MANGLED" = "NULL" ] && MANGLED=0

	if [ "$INVALID" = "0" ] && [ "$MANGLED" = "0" ]; then
		status OK "$1.$2: clean."
	else
		status CRIT "$1.$2: $INVALID invalid-JSON row(s), $MANGLED with a replacement-character fingerprint (likely charset/encoding damage)."
	fi
}

check_json ss13_char_health        organ_damage_json
check_json ss13_char_inventory     inventory_json
check_json ss13_char_skills        skills_json
check_json ss13_char_identity      flavor_texts
check_json ss13_char_identity      languages_json
check_json ss13_char_lace_dna      dna_json
check_json ss13_worldstate_objects content
check_json ss13_persistent_objects content
check_json ss13_floor_items        extra

# ============================================================================
# 4. ROW COUNT SNAPSHOT
# ============================================================================
echo ""
echo "=== 4. Row count snapshot ==="
sql_table "
SELECT 'ss13_char_health' AS tbl, COUNT(*) AS row_count FROM ss13_char_health
UNION ALL SELECT 'ss13_char_inventory', COUNT(*) FROM ss13_char_inventory
UNION ALL SELECT 'ss13_char_skills', COUNT(*) FROM ss13_char_skills
UNION ALL SELECT 'ss13_char_identity', COUNT(*) FROM ss13_char_identity
UNION ALL SELECT 'ss13_char_lace_dna', COUNT(*) FROM ss13_char_lace_dna
UNION ALL SELECT 'ss13_worldstate_objects', COUNT(*) FROM ss13_worldstate_objects
UNION ALL SELECT 'ss13_persistent_objects', COUNT(*) FROM ss13_persistent_objects
UNION ALL SELECT 'ss13_floor_items', COUNT(*) FROM ss13_floor_items;
" | sed 's/^/  /'

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=== Summary ==="
if [ "$CRIT_COUNT" -gt 0 ]; then
	echo "  $CRIT_COUNT critical issue(s), $WARN_COUNT warning(s). See above."
	exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
	echo "  $WARN_COUNT warning(s), no critical issues."
	exit 0
else
	echo "  All checks passed clean."
	exit 0
fi
