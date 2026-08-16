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

# --single-transaction: consistent InnoDB snapshot via MVCC instead of table
# read-locks, so a backup running mid-round doesn't block live game queries.
if ! docker exec aurora-db mysqldump --single-transaction -u aurora -paurora aurora_persist > "$OUT_FILE"; then
	echo "Backup failed. Is the aurora-db container running?" >&2
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
