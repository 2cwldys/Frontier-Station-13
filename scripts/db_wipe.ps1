<#
.SYNOPSIS
    Wipe all persistent character and world data from the database.
    The schema (tables, migrations) is preserved — only row data is deleted.
    Use this to start completely fresh after testing or when data is corrupted.
#>

Write-Host ""
Write-Host "=== PERSISTENCE DATA WIPE ===" -ForegroundColor Red
Write-Host "This will DELETE all saved character and world state data:" -ForegroundColor Yellow
Write-Host "  - Character health, inventory, identity, position" -ForegroundColor Yellow
Write-Host "  - Floor items, worldstate machines, turfs, atmos zones" -ForegroundColor Yellow
Write-Host "  - Economy (player accounts, station/dept balances)" -ForegroundColor Yellow
Write-Host "  - Crew records, R&D research state" -ForegroundColor Yellow
Write-Host "  - World templates" -ForegroundColor Yellow
Write-Host "  - Character slot overrides" -ForegroundColor Yellow
Write-Host ""
Write-Host "The database schema and migrations table are NOT touched." -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Type 'WIPE' to confirm"
if ($confirm -ne "WIPE") {
    Write-Host "Cancelled." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Wiping persistence data..." -ForegroundColor Cyan

$sql = @'
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
'@

$result = $sql | docker exec -i aurora-db mariadb -u aurora -paurora --force aurora_persist 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Could not connect to aurora-db container." -ForegroundColor Red
    Write-Host "Is the aurora-db container running?" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "All persistence data wiped." -ForegroundColor Green
Write-Host "Restart the server to begin with a clean slate." -ForegroundColor Cyan
