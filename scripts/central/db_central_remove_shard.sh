#!/bin/sh
# Permanently removes a shard -- both containers, their volumes, its
# config/data directories, its central DB login, and its ss13_shards row.
# Unlike db_central_stop_shard.sh, this is NOT resumable afterward.
# Confirms before doing anything unless --force is passed.
#
# Native translation of db_central_remove_shard.ps1 -- no PowerShell
# dependency.
#
# Usage:
#   db_central_remove_shard.sh --shard-id frontier-shard-1 --whatif
#   db_central_remove_shard.sh --shard-id frontier-shard-1
#   db_central_remove_shard.sh --shard-id frontier-shard-1 --force

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"

SHARD_ID=""
FORCE=0
WHATIF=0

while [ $# -gt 0 ]; do
	case "$1" in
		--shard-id) SHARD_ID="$2"; shift 2 ;;
		--force) FORCE=1; shift ;;
		--whatif) WHATIF=1; shift ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$SHARD_ID" ]; then
	echo "Usage: $0 --shard-id <name> [--force] [--whatif]"
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
SHARD_DIR="$ROOT/shards/$SHARD_ID"

echo "This will PERMANENTLY delete shard '$SHARD_ID': both containers, their data, and its central DB login."
echo "  Containers: $SERVER_CONTAINER, $DB_CONTAINER"
echo "  Directory:  $SHARD_DIR"

if [ "$WHATIF" -eq 1 ]; then
	echo "--whatif: nothing removed."
	exit 0
fi

if [ "$FORCE" -ne 1 ]; then
	printf "Type the shard id to confirm ('%s'): " "$SHARD_ID"
	read -r CONFIRM
	if [ "$CONFIRM" != "$SHARD_ID" ]; then
		echo "Confirmation did not match -- cancelled."
		exit 1
	fi
fi

echo "Removing $SERVER_CONTAINER..."
docker rm -f "$SERVER_CONTAINER" >/dev/null 2>&1

echo "Removing $DB_CONTAINER..."
docker rm -f -v "$DB_CONTAINER" >/dev/null 2>&1

if [ -d "$SHARD_DIR" ]; then
	echo "Removing $SHARD_DIR..."
	rm -rf "$SHARD_DIR"
fi

if [ -f "$CONFIG_PATH" ]; then
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
		echo "Revoking central DB login and unregistering..."
		printf '%s' "DROP USER IF EXISTS '$SHARD_ID'@'%'; DELETE FROM \`ss13_shards\` WHERE shard_id = '$SHARD_ID'; FLUSH PRIVILEGES;" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" >/dev/null 2>&1
	fi
fi

echo "Shard '$SHARD_ID' fully removed."
