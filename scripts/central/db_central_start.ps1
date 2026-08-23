<#
.SYNOPSIS
    Start the central (cross-server) database container.
    Run db_central_setup.ps1 first if this is a fresh install.
#>

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $Root

Write-Host "Starting central database..." -ForegroundColor Cyan
docker compose up -d central-db

if ($LASTEXITCODE -eq 0) {
    Write-Host "Central database is running on localhost:13306" -ForegroundColor Green
} else {
    Write-Error "Failed to start container. Is Docker Desktop running?"
}
