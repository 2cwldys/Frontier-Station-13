#!/bin/sh
# Restore the Aurora database from a SPECIFIC .sql file, rather than from the
# backups/ rotation that db_restore.sh lists. Use this for an archived dump, a
# copy pulled aside before a risky test, or anything recovered from elsewhere.
#
# Pass the path as an argument, or run with no arguments and it will ask.
# Native twin of db_restore_file.bat.
#
# STOP the game server before running this. The restore overwrites the current
# aurora_persist database entirely.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQLPATH="${1:-}"

if [ -z "$SQLPATH" ]; then
	echo ""
	echo "=== AURORA DATABASE RESTORE (from file) ==="
	echo ""
	echo "Type the full path to a .sql file."
	echo ""
	printf "Path to .sql file: "
	read -r SQLPATH
fi

if [ -z "$SQLPATH" ]; then
	echo "No path given. Cancelled." >&2
	exit 1
fi

# Strip one surrounding pair of quotes, which a paste or a file-manager
# "copy as path" commonly adds -- the path is re-quoted on the way out.
case "$SQLPATH" in
	\"*\") SQLPATH=$(printf '%s' "$SQLPATH" | sed 's/^"//; s/"$//') ;;
	\'*\') SQLPATH=$(printf '%s' "$SQLPATH" | sed "s/^'//; s/'$//") ;;
esac

exec "$SCRIPT_DIR/db_restore.sh" --path "$SQLPATH"
