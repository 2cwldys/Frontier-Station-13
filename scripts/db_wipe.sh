#!/bin/sh
# Wipe all persistent character and world data from the database.
# The schema (tables, migrations) is preserved -- only row data is deleted.
# Native translation of db_wipe.ps1 -- no PowerShell dependency.

set -eu

echo ""
echo "=== PERSISTENCE DATA WIPE ==="
echo "This will DELETE all saved character and world state data:"
echo "  - Character health, inventory, identity, position"
echo "  - Floor items, worldstate machines, turfs, atmos zones"
echo "  - Economy (player accounts, station/dept balances)"
echo "  - Crew records, R&D research state"
echo "  - World templates"
echo "  - Character slot overrides"
echo ""
echo "The database schema and migrations table are NOT touched."
echo ""

printf "Type 'WIPE' to confirm: "
read -r CONFIRM
if [ "$CONFIRM" != "WIPE" ]; then
	echo "Cancelled."
	exit 0
fi

echo ""
echo "Wiping persistence data..."

if ! docker exec -i aurora-db mariadb -u aurora -paurora --force aurora_persist <<'SQL'
DELETE FROM ss13_char_health;
DELETE FROM ss13_char_inventory;
DELETE FROM ss13_char_identity;
DELETE FROM ss13_mob_position;
DELETE FROM ss13_floor_items;
DELETE FROM ss13_worldstate_objects;
DELETE FROM ss13_worldstate_turfs;
DELETE FROM ss13_atmos_zones;
DELETE FROM ss13_money_accounts;
DELETE FROM ss13_crew_records;
DELETE FROM ss13_research_state;
DELETE FROM ss13_world_templates;
DELETE FROM ss13_template_turfs;
DELETE FROM ss13_template_worldstate;
DELETE FROM ss13_template_pending;
DELETE FROM ss13_persistent_objects;
DELETE FROM ss13_character_slots;
SQL
then
	echo "ERROR: Could not connect to aurora-db container." >&2
	echo "Is the aurora-db container running?" >&2
	exit 1
fi

echo ""
echo "All persistence data wiped."
echo "Restart the server to begin with a clean slate."
