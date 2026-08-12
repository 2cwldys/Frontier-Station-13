#!/bin/sh
# Restore the Aurora database from a backup file.
#
# With no arguments, lists the backups/ rotation sorted by timestamp and lets
# you pick one. With -p/--path FILE, restores from any .sql you point it at --
# an archived dump, a copy pulled aside before a risky test, anything that is
# not part of the 7-deep rotation.
#
# Native translation of db_restore.ps1 -- no PowerShell dependency.
#
# STOP the game server before restoring.
# The restore overwrites the current aurora_persist database entirely.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$ROOT/backups"
SQLPATH=""

while [ $# -gt 0 ]; do
	case "$1" in
		-p|--path)
			shift
			[ $# -gt 0 ] || { echo "--path requires a file argument." >&2; exit 1; }
			SQLPATH="$1"
			;;
		-h|--help)
			echo "Usage: $0 [-p|--path FILE.sql]"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			echo "Usage: $0 [-p|--path FILE.sql]" >&2
			exit 1
			;;
	esac
	shift
done

echo ""
echo "=== AURORA DATABASE RESTORE ==="
echo ""

# SELECTED is whatever we end up restoring from, however it was chosen. Both
# routes converge on it so the confirmation and the restore itself exist once.
SELECTED=""

if [ -n "$SQLPATH" ]; then
	if [ ! -f "$SQLPATH" ]; then
		echo "File not found (or not a regular file): $SQLPATH" >&2
		exit 1
	fi
	if [ ! -s "$SQLPATH" ]; then
		# Piping an empty file into mariadb succeeds and changes nothing, which
		# reads as "restore complete" -- refuse instead.
		echo "File is empty (0 bytes): $SQLPATH" >&2
		echo "Refusing to restore -- this would appear to succeed while doing nothing." >&2
		exit 1
	fi
	SELECTED="$SQLPATH"
fi

if [ -z "$SELECTED" ] && [ ! -d "$BACKUP_DIR" ]; then
	echo "No backups folder found at: $BACKUP_DIR" >&2
	echo "Run db_backup.sh first to create a backup." >&2
	echo "To restore a file from elsewhere, use: $0 --path <file.sql>" >&2
	exit 1
fi

if [ -n "$SELECTED" ]; then
	# Skip the listing entirely -- jump to the shared confirm/restore tail.
	:
else

	# List backups newest first (mtime).
	set +e
	BACKUPS=$(ls -t "$BACKUP_DIR"/backup_*.sql 2>/dev/null)
	set -e

	if [ -z "$BACKUPS" ]; then
		echo "No backup files found in: $BACKUP_DIR" >&2
		echo "Run db_backup.sh first to create a backup." >&2
		echo "To restore a file from elsewhere, use: $0 --path <file.sql>" >&2
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
	echo "  (or re-run with --path <file.sql> to restore a file from elsewhere)"
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
