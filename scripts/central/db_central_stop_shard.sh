#!/bin/sh
# Pauses a running shard -- stops its two containers without removing them.
# Local data is preserved; resume later with db_central_start_shard.sh. For
# permanent teardown, use db_central_remove_shard.sh instead.
#
# Native translation of db_central_stop_shard.ps1 -- no PowerShell
# dependency.
#
# Usage:
#   db_central_stop_shard.sh --shard-id frontier-shard-1

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"

SHARD_ID=""
WHATIF=0

while [ $# -gt 0 ]; do
	case "$1" in
		--shard-id) SHARD_ID="$2"; shift 2 ;;
		--whatif) WHATIF=1; shift ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$SHARD_ID" ]; then
	echo "Usage: $0 --shard-id <name> [--whatif]"
	exit 1
fi
case "$SHARD_ID" in
	*[!A-Za-z0-9_-]*|"")
		echo "shard-id must be letters, digits, hyphens, or underscores only -- got '$SHARD_ID'."
		exit 1
		;;
esac

DB_CONTAINER="aurora-shard-$SHARD_ID-db"
SERVER_CONTAINER="aurora-shard-$SHARD_ID-server"

if [ "$WHATIF" -eq 1 ]; then
	echo "--whatif: would stop '$SERVER_CONTAINER' then '$DB_CONTAINER', and mark '$SHARD_ID' stopped in ss13_shards. Data is preserved."
	exit 0
fi

echo "Stopping $SERVER_CONTAINER..."
if ! docker stop "$SERVER_CONTAINER" >/dev/null; then
	echo "Failed to stop $SERVER_CONTAINER -- does shard '$SHARD_ID' exist? (db_central_list_shards.sh)"
	exit 1
fi

echo "Stopping $DB_CONTAINER..."
if ! docker stop "$DB_CONTAINER" >/dev/null; then
	echo "Failed to stop $DB_CONTAINER."
	exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
	echo "$SERVER_CONTAINER/$DB_CONTAINER stopped, but config/central_dbconfig_admin.txt is missing -- couldn't update ss13_shards status."
	exit 0
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

CLIENT=$(command -v mariadb || command -v mysql || true)
if [ -n "$CLIENT" ] && [ -n "$LOGIN" ] && [ -n "$PASSWORD" ]; then
	printf '%s' "UPDATE \`ss13_shards\` SET status = 'stopped' WHERE shard_id = '$SHARD_ID';" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" >/dev/null 2>&1
fi

echo "Shard '$SHARD_ID' stopped. Data preserved -- resume with db_central_start_shard.sh."
