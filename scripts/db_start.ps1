<#
.SYNOPSIS
    Start the Aurora MariaDB container.
    Run db_setup.ps1 first if this is a fresh install.
#>

$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

Write-Host "Starting Aurora DB..." -ForegroundColor Cyan
docker compose up -d db

if ($LASTEXITCODE -eq 0) {
    Write-Host "Aurora DB is running on localhost:3306" -ForegroundColor Green
} else {
    Write-Error "Failed to start container. Is Docker Desktop running?"
}
