#!/bin/sh
# Open the backups folder. Mirrors db_open_backups.bat, which uses Windows
# Explorer -- there's no universal Linux equivalent (a game server host is
# typically headless), so fall back to just printing the path.
DIR="$(cd "$(dirname "$0")/.." && pwd)/backups"
if command -v xdg-open >/dev/null 2>&1; then
	xdg-open "$DIR"
elif command -v open >/dev/null 2>&1; then
	open "$DIR"
else
	echo "$DIR"
fi
