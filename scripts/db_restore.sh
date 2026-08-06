#!/bin/sh
# Restore the Aurora database from a backup file.
# Lists available backups sorted by timestamp and lets you pick one.
# Native translation of db_restore.ps1 -- no PowerShell dependency.
#
# STOP the game server before restoring.
# The restore overwrites the current aurora_persist database entirely.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT/backups"

echo ""
echo "=== AURORA DATABASE RESTORE ==="
echo ""

if [ ! -d "$BACKUP_DIR" ]; then
	echo "No backups folder found at: $BACKUP_DIR" >&2
	echo "Run db_backup.sh first to create a backup." >&2
	exit 1
fi

# List backups newest first (mtime).
set +e
BACKUPS=$(ls -t "$BACKUP_DIR"/backup_*.sql 2>/dev/null)
set -e

if [ -z "$BACKUPS" ]; then
	echo "No backup files found in: $BACKUP_DIR" >&2
	echo "Run db_backup.sh first to create a backup." >&2
	exit 1
fi

echo "Available backups (newest first):"
echo ""

i=0
# Build a numbered index (POSIX sh has no arrays -- use a temp file).
INDEX_FILE=$(mktemp)
trap 'rm -f "$INDEX_FILE"' EXIT

for f in $BACKUPS; do
	i=$((i + 1))
	echo "$i	$f" >> "$INDEX_FILE"
	SIZE_KB=$(( $(wc -c < "$f") / 1024 ))
	MTIME=$(date -r "$f" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -d. -f1)
	printf "  [%2d]  %s   %8s KB\n" "$i" "$MTIME" "$SIZE_KB"
done

echo ""
printf "Enter number to restore (or press Enter to cancel): "
read -r CHOICE

if [ -z "$CHOICE" ]; then
	echo "Cancelled."
	exit 0
fi

case "$CHOICE" in
	''|*[!0-9]*)
		echo "Invalid selection." >&2
		exit 1
		;;
esac

SELECTED=$(awk -v n="$CHOICE" -F'\t' '$1 == n { print $2 }' "$INDEX_FILE")
if [ -z "$SELECTED" ]; then
	echo "Invalid selection." >&2
	exit 1
fi

echo ""
echo "Selected: $(basename "$SELECTED")"
echo ""
echo "WARNING: This will OVERWRITE the current aurora_persist database." >&2
echo "Make sure the game server is stopped before proceeding." >&2
echo ""

printf "Type 'RESTORE' to confirm: "
read -r CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
	echo "Cancelled."
	exit 0
fi

echo ""
echo "Restoring from: $(basename "$SELECTED") ..."

if ! docker exec -i aurora-db mariadb -u aurora -paurora aurora_persist < "$SELECTED"; then
	echo "" >&2
	echo "Restore FAILED. Is the aurora-db container running?" >&2
	exit 1
fi

echo ""
echo "Restore complete from: $(basename "$SELECTED")"
echo "Restart the game server to load the restored state."
