#!/bin/sh
# Backs up THIS shard's own local database from INSIDE its own container --
# run by DreamDaemon itself (world.shelleo(), persistence_backups.dm's
# run_database_backup()) when GLOB.config.shard_id is set, i.e. this
# server IS a shard. Never intended to be run by hand.
#
# Unlike scripts/central/db_central_backup_shard.sh (which runs on the HOST
# and reaches a shard's DB via `docker exec`), a shard's own container has
# no Docker CLI and no socket access at all -- by design, so a shard can
# never reach outside its own sandbox. Instead this connects straight over
# the network to its sibling DB container, using the exact same credentials
# (config/dbconfig.txt) the game itself already uses to talk to its own
# local database -- no docker exec needed, same as any normal remote
# mysqldump.
#
# SHARD_ID and the container path this runs from are both fixed by
# db_central_add_shard.sh at creation (env var, and the /aurora WORKDIR +
# writable backups bind mount, respectively) -- nothing here takes
# arguments.

set -u

if [ -z "${SHARD_ID:-}" ]; then
	echo "Backup failed: SHARD_ID is not set -- this script only runs inside a shard container (set by db_central_add_shard.sh)."
	exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DBCONFIG="$ROOT/config/dbconfig.txt"
if [ ! -f "$DBCONFIG" ]; then
	echo "Backup failed: $DBCONFIG not found."
	exit 1
fi

# config/dbconfig.txt is "KEY value" per line, same file format the game
# itself parses -- pull out just the four fields this needs.
DB_ADDRESS=$(awk '$1=="ADDRESS"{print $2}' "$DBCONFIG")
DB_PORT=$(awk '$1=="PORT"{print $2}' "$DBCONFIG")
DB_NAME=$(awk '$1=="DATABASE"{print $2}' "$DBCONFIG")
DB_LOGIN=$(awk '$1=="LOGIN"{print $2}' "$DBCONFIG")
DB_PASSWORD=$(awk '$1=="PASSWORD"{print $2}' "$DBCONFIG")

if [ -z "$DB_ADDRESS" ] || [ -z "$DB_PORT" ] || [ -z "$DB_NAME" ] || [ -z "$DB_LOGIN" ]; then
	echo "Backup failed: could not parse ADDRESS/PORT/DATABASE/LOGIN out of $DBCONFIG."
	exit 1
fi

BACKUP_DIR="$ROOT/backups/shards/$SHARD_ID"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUT_FILE="$BACKUP_DIR/backup_$TIMESTAMP.sql"

echo "Backing up shard '$SHARD_ID' ($DB_ADDRESS:$DB_PORT) to $OUT_FILE ..."

# Only one readiness gate needed here (unlike db_backup.sh's two) -- there's
# no local Docker daemon inside this container to wait on, just the DB
# itself possibly still starting.
MAX_WAIT=10
POLL=2

waited=0
db_ready=0
while [ $waited -lt $MAX_WAIT ]; do
	if mysqladmin ping -h "$DB_ADDRESS" -P "$DB_PORT" -u "$DB_LOGIN" -p"$DB_PASSWORD" --silent >/dev/null 2>&1; then
		db_ready=1
		break
	fi
	sleep $POLL
	waited=$((waited + POLL))
done
if [ "$db_ready" -ne 1 ]; then
	echo "Backup failed: $DB_ADDRESS:$DB_PORT didn't answer a ping within ${MAX_WAIT}s."
	exit 1
fi

mysqldump --single-transaction -h "$DB_ADDRESS" -P "$DB_PORT" -u "$DB_LOGIN" -p"$DB_PASSWORD" "$DB_NAME" > "$OUT_FILE"
if [ $? -ne 0 ]; then
	echo "Backup failed. mysqldump exited non-zero even though $DB_ADDRESS:$DB_PORT answered a ping."
	rm -f "$OUT_FILE"
	exit 1
fi

SIZE_KB=$(( $(wc -c < "$OUT_FILE") / 1024 ))
echo "Backup complete: $OUT_FILE (${SIZE_KB} KB)"

# Rotate: keep only the 7 most recent backups for this shard.
COUNT=0
for f in $(ls -t "$BACKUP_DIR"/backup_*.sql 2>/dev/null); do
	COUNT=$((COUNT + 1))
	if [ "$COUNT" -gt 7 ]; then
		rm -f "$f"
		echo "Removed old backup: $(basename "$f")"
	fi
done

RETAINED=$COUNT
if [ "$RETAINED" -gt 7 ]; then
	RETAINED=7
fi
echo "Backups retained for '$SHARD_ID': $RETAINED/7"
