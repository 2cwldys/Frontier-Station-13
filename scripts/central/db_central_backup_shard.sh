#!/bin/sh
# Dumps a shard's LOCAL database to a timestamped, portable SQL file --
# same shape as scripts/db_backup.sh for the main server, just scoped to
# one shard's own aurora-shard-<ShardId>-db container. Keeps the 7 most
# recent backups per shard and deletes older ones automatically.
#
# The resulting .sql file is a plain mysqldump -- nothing shard-specific
# baked into it, so it can be handed to another server/shard and applied
# with a normal `docker exec -i <container> mariadb -u aurora -paurora
# aurora_persist < backup_....sql`. Central data (characters/admins/etc.)
# is never in this file -- it only ever touches the shard's LOCAL database.
#
# Native translation of db_central_backup_shard.ps1 -- no PowerShell
# dependency.
#
# Usage:
#   db_central_backup_shard.sh --shard-id frontier-shard-1

set -u

SHARD_ID=""
while [ $# -gt 0 ]; do
	case "$1" in
		--shard-id) SHARD_ID="$2"; shift 2 ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$SHARD_ID" ]; then
	echo "Usage: $0 --shard-id <name>"
	exit 1
fi
case "$SHARD_ID" in
	*[!A-Za-z0-9_-]*|"")
		echo "shard-id must be letters, digits, hyphens, or underscores only -- got '$SHARD_ID'."
		exit 1
		;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="$ROOT/backups/shards/$SHARD_ID"
mkdir -p "$BACKUP_DIR"

DB_CONTAINER="aurora-shard-$SHARD_ID-db"

if [ -z "$(docker ps -a --filter "name=^/${DB_CONTAINER}\$" --format '{{.Names}}')" ]; then
	echo "No such shard database container '$DB_CONTAINER' -- does shard '$SHARD_ID' exist? (db_central_list_shards.sh)"
	exit 1
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUT_FILE="$BACKUP_DIR/backup_$TIMESTAMP.sql"

echo "Backing up shard '$SHARD_ID' ($DB_CONTAINER) to $OUT_FILE ..."

MAX_WAIT=10
POLL=2

waited=0
daemon_ready=0
while [ $waited -lt $MAX_WAIT ]; do
	if docker info >/dev/null 2>&1; then
		daemon_ready=1
		break
	fi
	sleep $POLL
	waited=$((waited + POLL))
done
if [ "$daemon_ready" -ne 1 ]; then
	echo "Backup failed: Docker daemon did not respond within ${MAX_WAIT}s."
	exit 1
fi

waited=0
db_ready=0
while [ $waited -lt $MAX_WAIT ]; do
	if docker exec "$DB_CONTAINER" mysqladmin ping -u aurora -paurora --silent >/dev/null 2>&1; then
		db_ready=1
		break
	fi
	sleep $POLL
	waited=$((waited + POLL))
done
if [ "$db_ready" -ne 1 ]; then
	echo "Backup failed: $DB_CONTAINER didn't answer a ping within ${MAX_WAIT}s -- check 'docker logs $DB_CONTAINER'."
	exit 1
fi

docker exec "$DB_CONTAINER" mysqldump --single-transaction -u aurora -paurora aurora_persist > "$OUT_FILE"
if [ $? -ne 0 ]; then
	echo "Backup failed. mysqldump exited non-zero even though $DB_CONTAINER answered a ping."
	rm -f "$OUT_FILE"
	exit 1
fi

SIZE_KB=$(du -k "$OUT_FILE" | cut -f1)
echo "Backup complete: $OUT_FILE (${SIZE_KB} KB)"

# Rotate: keep only the 7 most recent backups for this shard.
COUNT=0
ls -1t "$BACKUP_DIR"/backup_*.sql 2>/dev/null | while read -r f; do
	COUNT=$((COUNT + 1))
	if [ $COUNT -gt 7 ]; then
		rm -f "$f"
		echo "Removed old backup: $(basename "$f")"
	fi
done

REMAINING=$(ls -1 "$BACKUP_DIR"/backup_*.sql 2>/dev/null | wc -l | tr -d ' ')
echo "Backups retained for '$SHARD_ID': $REMAINING/7"
