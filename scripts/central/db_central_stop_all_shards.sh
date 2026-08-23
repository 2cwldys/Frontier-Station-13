#!/bin/sh
# Stops every currently-running shard -- convenience wrapper around
# db_central_stop_shard.sh, looping over ss13_shards. Useful before a host
# reboot/maintenance without needing to stop each shard by hand. Does not
# touch aurora-db/aurora-central-db.
#
# Native translation of db_central_stop_all_shards.ps1 -- no PowerShell
# dependency.
#
# Usage:
#   db_central_stop_all_shards.sh

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

SHARD_IDS=$(printf '%s' "SELECT shard_id FROM \`ss13_shards\` WHERE status = 'running';" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" -N 2>&1)
if [ $? -ne 0 ]; then
	echo "Failed to list running shards:"
	echo "  $SHARD_IDS"
	exit 1
fi

if [ -z "$(printf '%s' "$SHARD_IDS" | tr -d '[:space:]')" ]; then
	echo "No running shards."
	exit 0
fi

echo "Stopping shards: $SHARD_IDS"
for shard_id in $SHARD_IDS; do
	sh "$SCRIPT_DIR/db_central_stop_shard.sh" --shard-id "$shard_id"
done

echo "Done."
