<#
.SYNOPSIS
    Start the Aurora MariaDB container.
    Run db_setup.ps1 first if this is a fresh install.
#>

$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

# DB_PORT (.env, repo root) -- see db_setup.ps1's copy of this for why.
$dbPort = "3306"
$envPath = Join-Path $Root ".env"
if (Test-Path $envPath) {
    foreach ($line in Get-Content $envPath) {
        if ($line -match '^\s*DB_PORT\s*=\s*(\S+)') {
            $dbPort = $Matches[1]
        }
    }
}

Write-Host "Starting Aurora DB..." -ForegroundColor Cyan
docker compose up -d db

if ($LASTEXITCODE -eq 0) {
    Write-Host "Aurora DB is running on localhost:$dbPort" -ForegroundColor Green
} else {
    Write-Error "Failed to start container. Is Docker Desktop running?"
}
