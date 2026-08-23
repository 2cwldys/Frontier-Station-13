#!/bin/sh
# Lists every registered shard (ss13_shards) alongside its live Docker
# status, so "what shards exist and are they up" is one command.
#
# Native translation of db_central_list_shards.ps1 -- no PowerShell
# dependency.
#
# Usage:
#   db_central_list_shards.sh

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"

if [ ! -f "$CONFIG_PATH" ]; then
	echo "config/central_dbconfig_admin.txt not found -- run db_central_setup first."
	exit 1
fi

ADDRESS="localhost"; PORT_DB="3306"; DATABASE="aurora_central"; LOGIN=""; PASSWORD=""
while IFS= read -r line || [ -n "$line" ]; do
	t=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	[ -z "$t" ] && continue
	case "$t" in \#*) continue ;; esac
	key=$(printf '%s' "$t" | cut -d' ' -f1 | tr 'A-Z' 'a-z')
	value=$(printf '%s' "$t" | cut -s -d' ' -f2-)
	case "$key" in
		address) ADDRESS="$value" ;;
		port) PORT_DB="$value" ;;
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

RESULT=$(printf '%s' "SELECT shard_id, port, status, created_at, started_at FROM \`ss13_shards\` ORDER BY shard_id;" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" --table 2>&1)
if [ $? -ne 0 ]; then
	echo "FAILED:"
	echo "  $RESULT"
	exit 1
fi

echo "Registered shards:"
echo "$RESULT"
echo ""
echo "Live Docker status:"
docker ps -a --filter "name=aurora-shard-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
