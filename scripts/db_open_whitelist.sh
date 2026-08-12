#!/bin/sh
# Open the join whitelist (ss13_join_whitelist) straight from the database --
# prints the current rows, then drops you into a live MariaDB prompt already
# pointed at aurora_persist so you can view or edit it further.
#
# This is the table the in-game "Whitelist Players" admin verb manages
# (who's allowed to connect/play at all) -- not the species/donator
# whitelist, which isn't SQL-backed in this server's current config.
#
# Native translation of db_open_whitelist.ps1 -- no PowerShell dependency.

set -eu

echo ""
echo "=== JOIN WHITELIST (ss13_join_whitelist) ==="
echo ""

if ! docker exec -i aurora-db mariadb -u aurora -paurora aurora_persist \
	-e "SELECT ckey, added_by, added_at FROM ss13_join_whitelist ORDER BY added_at;"
then
	echo "" >&2
	echo "ERROR: Could not connect to aurora-db container." >&2
	echo "Is the aurora-db container running?" >&2
	exit 1
fi

echo ""
echo "Dropping into an interactive session -- edit ss13_join_whitelist directly,"
echo "or run any other query. Type 'exit' or Ctrl+D to leave."
echo ""

docker exec -it aurora-db mariadb -u aurora -paurora aurora_persist
