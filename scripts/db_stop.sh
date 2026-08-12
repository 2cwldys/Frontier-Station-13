#!/bin/sh
# Stop the Aurora MariaDB container.
# Data is preserved in the Docker volume -- start again with db_start.sh.
# Optionally runs a backup before stopping.
# Native translation of db_stop.ps1 -- no PowerShell dependency.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

printf "Run a backup before stopping? (Y/n): "
read -r BACKUP
case "$BACKUP" in
	[Nn]*) ;;
	*) "$(dirname "$0")/db_backup.sh" ;;
esac

echo "Stopping Aurora DB..."
docker compose stop db

echo "Aurora DB stopped. Data is preserved."
echo "Restart with: scripts/db_start.sh"
