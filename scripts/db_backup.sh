#!/bin/sh
# Dump the Aurora database to a timestamped SQL file in the backups/ directory.
# Keeps the 7 most recent backups and deletes older ones automatically.
# Native translation of db_backup.ps1 -- no PowerShell dependency.
#
# Run before stopping the server or before applying major changes.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT/backups"

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
OUT_FILE="$BACKUP_DIR/backup_$TIMESTAMP.sql"

echo "Backing up Aurora DB to $OUT_FILE ..."

# Two DIFFERENT things have to be ready, and `docker exec ... mysqldump`
# collapses both into one opaque exit code:
#
#  1. The Docker daemon itself has to be reachable. If it isn't (still
#     starting after a reboot, or the socket isn't up yet), EVERY `docker`
#     command fails the same way, including a ping -- so a ping check alone
#     can't tell this apart from case 2 below.
#  2. Even once the daemon answers and the container shows Running, MariaDB
#     INSIDE it may still be doing its own startup (InnoDB crash recovery is
#     the common cause after an unclean shutdown, e.g. a power outage) and
#     won't accept connections yet -- `docker exec` itself succeeds here,
#     it's the mysql client's connection that fails.
#
# Checked as two separate gates so a failure says which one it actually was,
# instead of both looking identical.
#
# Kept SHORT deliberately: world.shelleo() (the DM proc that runs this
# script) is a blocking OS call -- it freezes the ENTIRE game world, not
# just the backup, for as long as this script takes to return. Two gates at
# 60s each, doubled by persistence_backups.dm's own retry, could previously
# freeze the whole server for up to ~4 minutes on a bad night. The DM-side
# retry already waits a few seconds between attempts WITHOUT blocking the
# world (a real sleep(), not a shell() call) -- that's where "give it a
# moment and try again" belongs, not in here.
MAX_WAIT=10
POLL=2

WAITED=0
DAEMON_READY=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
	if docker info >/dev/null 2>&1; then
		DAEMON_READY=1
		break
	fi
	sleep "$POLL"
	WAITED=$((WAITED + POLL))
done
if [ "$DAEMON_READY" -ne 1 ]; then
	echo "Backup failed: Docker daemon did not respond within ${MAX_WAIT}s. Docker may still be starting (e.g. after a reboot) or may not be running at all." >&2
	exit 1
fi

WAITED=0
DB_READY=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
	if docker exec aurora-db mysqladmin ping -u aurora -paurora --silent >/dev/null 2>&1; then
		DB_READY=1
		break
	fi
	sleep "$POLL"
	WAITED=$((WAITED + POLL))
done
if [ "$DB_READY" -ne 1 ]; then
	echo "Backup failed: Docker is up but aurora-db didn't answer a ping within ${MAX_WAIT}s. MariaDB may still be recovering (e.g. after an unclean shutdown), or the container may be unhealthy -- check 'docker logs aurora-db'." >&2
	exit 1
fi

# --single-transaction: consistent InnoDB snapshot via MVCC instead of table
# read-locks, so a backup running mid-round doesn't block live game queries.
if ! docker exec aurora-db mysqldump --single-transaction -u aurora -paurora aurora_persist > "$OUT_FILE"; then
	echo "Backup failed. mysqldump exited non-zero even though aurora-db answered a ping -- check credentials/permissions." >&2
	rm -f "$OUT_FILE"
	exit 1
fi

SIZE_KB=$(( $(wc -c < "$OUT_FILE") / 1024 ))
echo "Backup complete: $OUT_FILE (${SIZE_KB} KB)"

# Rotate: keep only the 7 most recent backups.
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
echo "Backups retained: $RETAINED/7"
