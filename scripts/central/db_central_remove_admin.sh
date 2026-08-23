#!/bin/sh
# Remove one ckey from the central admin roster (ss13_central_admins). Once
# removed, that ckey is not an admin on ANY server with CENTRAL_SQL_ENABLED
# on -- takes effect on each server's next reboot (admin roster loads once
# at boot, same as the existing local system already works).
#
# Connects using config/central_dbconfig_admin.txt -- the ADMIN tier, same
# as db_central_add_admin.sh.
#
# Native translation of db_central_remove_admin.ps1 -- no PowerShell
# dependency.
#
# Usage:
#   db_central_remove_admin.sh --ckey someone
#   db_central_remove_admin.sh --ckey someone --whatif

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"

CKEY=""
WHATIF=0

while [ $# -gt 0 ]; do
	case "$1" in
		--ckey) CKEY="$2"; shift 2 ;;
		--whatif) WHATIF=1; shift ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$CKEY" ]; then
	echo "Usage: $0 --ckey <ckey> [--whatif]"
	exit 1
fi

CKEY=$(echo "$CKEY" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9@._-]//g')
if [ -z "$CKEY" ]; then
	echo "Ckey is empty after normalization."
	exit 1
fi

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

SQL="DELETE FROM \`ss13_central_admins\` WHERE ckey = '$CKEY';"

echo "Target: $ADDRESS:$PORT/$DATABASE via $CLIENT"
echo ""
echo "SQL to run:"
echo "  $SQL"
echo ""

if [ "$WHATIF" -eq 1 ]; then
	echo "--whatif: nothing removed."
	exit 0
fi

RESULT=$(printf '%s' "$SQL" | "$CLIENT" -h "$ADDRESS" -P "$PORT" -u "$LOGIN" "-p$PASSWORD" 2>&1)
STATUS=$?
if [ $STATUS -ne 0 ]; then
	echo "FAILED:"
	echo "  $RESULT"
	exit 1
fi

echo "'$CKEY' removed from the central admin roster."
echo "Takes effect on every centrally-enabled server's next reboot."
