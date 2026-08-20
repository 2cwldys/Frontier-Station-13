#!/bin/sh
# Open a shard's backups folder (backups/shards/<ShardId>). With no
# argument, opens backups/shards -- every shard's backups at once. Mirrors
# db_central_open_backups.bat -- same headless-host fallback as
# db_open_backups.sh (there's no universal Linux equivalent of Explorer).
#
# Usage: db_central_open_backups.sh [shard-id]

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -n "${1:-}" ]; then
	DIR="$ROOT/backups/shards/$1"
else
	DIR="$ROOT/backups/shards"
fi

if command -v xdg-open >/dev/null 2>&1; then
	xdg-open "$DIR"
elif command -v open >/dev/null 2>&1; then
	open "$DIR"
else
	echo "$DIR"
fi
