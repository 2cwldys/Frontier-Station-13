<#
.SYNOPSIS
    Open the join whitelist (ss13_join_whitelist) straight from the database --
    prints the current rows, then drops you into a live MariaDB prompt already
    pointed at aurora_persist so you can view or edit it further.

.NOTES
    This is the table the in-game "Whitelist Players" admin verb manages
    (who's allowed to connect/play at all) -- not the species/donator
    whitelist, which isn't SQL-backed in this server's current config.
#>

Write-Host ""
Write-Host "=== JOIN WHITELIST (ss13_join_whitelist) ===" -ForegroundColor Cyan
Write-Host ""

docker exec -i aurora-db mariadb -u aurora -paurora aurora_persist -e "SELECT ckey, added_by, added_at FROM ss13_join_whitelist ORDER BY added_at;" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Could not connect to aurora-db container." -ForegroundColor Red
    Write-Host "Is the aurora-db container running?" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Dropping into an interactive session -- edit ss13_join_whitelist directly," -ForegroundColor Cyan
Write-Host "or run any other query. Type 'exit' or Ctrl+D to leave." -ForegroundColor DarkGray
Write-Host ""

docker exec -it aurora-db mariadb -u aurora -paurora aurora_persist
