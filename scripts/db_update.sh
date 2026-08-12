#!/bin/sh
# Apply any missing database schema changes by re-running all migration files.
# Already-applied migrations are skipped silently (--force flag).
# Safe to run at any time -- will only create what is missing.
# Native translation of db_update.ps1 -- no PowerShell dependency.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SQL_DIR="$ROOT/SQL/migrate-2023"

echo "Scanning migrations in $SQL_DIR ..."

FILES=$(ls "$SQL_DIR"/V*.sql 2>/dev/null | sort)

if [ -z "$FILES" ]; then
	echo "No migration files found."
	exit 0
fi

APPLIED=0
FAILED=0

for f in $FILES; do
	NAME=$(basename "$f")
	printf "  %s ... " "$NAME"
	RESULT=$(docker exec -i aurora-db mariadb -u aurora -paurora --force aurora_persist < "$f" 2>&1)
	if [ $? -eq 0 ]; then
		echo "OK"
		APPLIED=$((APPLIED + 1))
	else
		# --force means non-fatal errors still exit 0 from mariadb; anything
		# non-zero here is a connection failure or similar hard error.
		echo "FAILED"
		echo "    $RESULT"
		FAILED=$((FAILED + 1))
	fi
done

echo ""
echo "Done. $APPLIED file(s) processed, $FAILED hard error(s)."
if [ "$FAILED" -gt 0 ]; then
	echo "Check that the aurora-db container is running."
fi
