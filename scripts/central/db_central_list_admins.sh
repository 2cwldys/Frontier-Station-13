#!/bin/sh
# Lists everyone currently in the central admin roster (ss13_central_admins)
# -- the shared list every server with CENTRAL_SQL_ENABLED on treats as its
# ENTIRE admin roster (see load_admins_from_central_database(), auth.dm).
#
# Read-only. Connects using config/central_dbconfig_admin.txt -- the ADMIN
# tier, same as db_central_add_admin.sh/db_central_remove_admin.sh.
#
# Native translation of db_central_list_admins.ps1 -- no PowerShell
# dependency.
#
# Usage:
#   db_central_list_admins.sh

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"

if [ ! -f "$CONFIG_PATH" ]; then
	echo "config/central_dbconfig_admin.txt not found -- run db_central_setup, or copy it from config/example/central_dbconfig_admin.txt and fill in the central database's admin credentials yourself."
	exit 1
fi

ADDRESS="localhost"
PORT="3306"
DATABASE="aurora_central"
LOGIN=""
PASSWORD=""
while IFS= read -r line || [ -n "$line" ]; do
	t=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	[ -z "$t" ] && continue
	case "$t" in \#*) continue ;; esac
	key=$(printf '%s' "$t" | cut -d' ' -f1 | tr 'A-Z' 'a-z')
	value=$(printf '%s' "$t" | cut -s -d' ' -f2-)
	case "$key" in
		address) ADDRESS="$value" ;;
		port) PORT="$value" ;;
		database) DATABASE="$value" ;;
		login) LOGIN="$value" ;;
		password) PASSWORD="$value" ;;
	esac
done < "$CONFIG_PATH"

if [ -z "$LOGIN" ] || [ -z "$PASSWORD" ]; then
	echo "config/central_dbconfig_admin.txt is missing LOGIN/PASSWORD -- fill those in first."
	exit 1
fi

CLIENT=$(command -v mariadb || command -v mysql || true)
if [ -z "$CLIENT" ]; then
	echo "No 'mariadb' or 'mysql' client found on PATH."
	exit 1
fi

echo "Target: $ADDRESS:$PORT/$DATABASE via $CLIENT"
echo ""

SQL="SELECT ckey, \`rank\`, flags, added_by, added_at FROM \`ss13_central_admins\` ORDER BY ckey;"
RESULT=$(printf '%s' "$SQL" | "$CLIENT" -h "$ADDRESS" -P "$PORT" -u "$LOGIN" "-p$PASSWORD" --table 2>&1)
STATUS=$?
if [ $STATUS -ne 0 ]; then
	echo "FAILED:"
	echo "  $RESULT"
	exit 1
fi

echo "$RESULT"
echo ""
echo "Add/update: db_central_add_admin.sh --ckey <ckey> --rank <label> --flags <int>"
echo "Remove:     db_central_remove_admin.sh --ckey <ckey>"
