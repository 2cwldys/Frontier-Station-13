<#
.SYNOPSIS
    Stop the Aurora MariaDB container.
    Data is preserved in the Docker volume — start again with db_start.ps1.
    Optionally runs a backup before stopping.
#>

$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$backup = Read-Host "Run a backup before stopping? (Y/n)"
if ($backup -notmatch '^[Nn]') {
    & "$PSScriptRoot\db_backup.ps1"
}

Write-Host "Stopping Aurora DB..." -ForegroundColor Cyan
docker compose stop db

if ($LASTEXITCODE -eq 0) {
    Write-Host "Aurora DB stopped. Data is preserved." -ForegroundColor Green
    Write-Host "Restart with: scripts\db_start.ps1"
} else {
    Write-Error "Failed to stop container."
}
