<#
.SYNOPSIS
    Stop the central (cross-server) database container.
    Data is preserved in the Docker volume -- start again with
    db_central_start.ps1. This ONLY ever touches the central container
    (aurora-central-db) -- your own local database (aurora-db) is untouched.

.NOTES
    Unlike db_stop.ps1, this does not offer to run a backup first -- there is
    no central-database backup script yet. If you're hosting a real central
    database, back it up (e.g. mysqldump against aurora-central-db) before
    stopping it the same way you would any other production database.
#>

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $Root

Write-Host "Stopping central database..." -ForegroundColor Cyan
docker compose stop central-db

if ($LASTEXITCODE -eq 0) {
    Write-Host "Central database stopped. Data is preserved." -ForegroundColor Green
    Write-Host "Restart with: scripts\central\db_central_start.ps1"
} else {
    Write-Error "Failed to stop container."
}
