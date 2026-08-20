<#
.SYNOPSIS
    Force-recreates the Aurora MariaDB container. Data is preserved (the
    named volume aurora_db_data isn't touched by recreation).

.DESCRIPTION
    Different from db_stop.ps1 + db_start.ps1: those just stop/start the
    EXISTING container, which does not re-apply docker-compose.yml's port
    mapping if it's already running with a stale one. This does a full
    recreate, which does.

    Fixes the specific case where 'docker ps' shows the container Up, but
    its published port isn't actually reachable on the host -- most often
    seen after Docker Desktop itself was restarted (a known Docker Desktop
    for Windows/WSL2 quirk: existing containers can resume without their
    host port forwarding actually coming back, even though the container's
    own config is correct). If the local game server's SQL connection is
    failing/crashing right after a Docker Desktop restart, this is the fix.

    Also the right way to switch an existing setup to a different DB_PORT
    (.env) -- recreating is the only way an already-running container picks
    up a changed port mapping; a plain 'docker compose up -d db' with no
    config change is a no-op, and db_update.ps1 is unrelated (SQL schema
    migrations only, no Docker involvement). This also rewrites
    config/dbconfig.txt's PORT line to match, so the two never drift.
#>

$ErrorActionPreference = "Stop"

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

Write-Host "Force-recreating Aurora DB container (data is preserved)..." -ForegroundColor Cyan
docker compose up -d --force-recreate db

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to recreate container. Is Docker Desktop running?"
    exit 1
}

Write-Host "Waiting for MariaDB to be ready..." -ForegroundColor Cyan
$attempts = 0
$ready    = $false
while ($attempts -lt 30) {
    Start-Sleep -Seconds 2
    try {
        docker exec aurora-db mariadb-admin ping -u aurora -paurora 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
    } catch {
        # Server not ready yet -- keep waiting
    }
    $attempts++
    Write-Host "  ...still waiting ($($attempts * 2)s)" -ForegroundColor DarkGray
}

if (-not $ready) {
    Write-Error "MariaDB did not become ready within 60 seconds. Check 'docker logs aurora-db'."
    exit 1
}

# Keep config/dbconfig.txt's PORT in sync -- the container can be on a new
# DB_PORT after this recreate, and that file is what the game server itself
# actually connects with (not docker-compose.yml or .env, which it never
# reads). Only touches the PORT line; LOGIN/PASSWORD/etc are left as-is.
$dbconfigPath = Join-Path $Root "config\dbconfig.txt"
if (Test-Path $dbconfigPath) {
    $content = Get-Content $dbconfigPath -Raw
    $updated = $content -replace '(?m)^PORT\s+\S+', "PORT $dbPort"
    if ($updated -ne $content) {
        Set-Content $dbconfigPath $updated -Encoding UTF8
        Write-Host "config\dbconfig.txt PORT updated to $dbPort." -ForegroundColor Green
    }
} else {
    Write-Host "config\dbconfig.txt not found -- run db_setup.ps1 first if this is a fresh install." -ForegroundColor Yellow
}

Write-Host "Aurora DB recreated and ready on localhost:$dbPort" -ForegroundColor Green
