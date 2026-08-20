<#
.SYNOPSIS
    Creates a new local game-server "shard" -- a second, independent
    DreamDaemon instance on THIS machine, sharing the same central database
    as the main server, but starting with completely fresh local data
    (turfs/objects/machinery/local DB). See docs/cross_server_persistence.md.

.DESCRIPTION
    Two new Docker containers, never touching the existing aurora-db/
    aurora-central-db containers:
      - aurora-shard-<ShardId>-db      local MariaDB, fresh schema, NOT
                                        published to the host -- only the
                                        shard's own server container can
                                        reach it, over a dedicated Docker
                                        network (aurora-shards-net).
      - aurora-shard-<ShardId>-server  the game server itself, built from
                                        docker/shard.Dockerfile (a slim
                                        BYOND-runtime-only image -- no
                                        compiler). The repo is bind-mounted
                                        in READ-ONLY; only this shard's own
                                        config/data directories (shards/
                                        <ShardId>/) and its own backup
                                        output directory (backups/shards/
                                        <ShardId>/) are writable, so this
                                        can never touch your working
                                        directory otherwise. Published on
                                        -Port.

    Provisions this shard its own central-DB login (same DML-only, no-
    schema-access grant every other server gets -- see
    db_central_add_server.ps1) rather than reusing the host server's own
    credentials, and registers it in ss13_shards so it's addressable and
    resumable afterward via db_central_start_shard.ps1/db_central_stop_shard.ps1
    -- NOT disposable. A stopped shard's local data is untouched until
    db_central_remove_shard.ps1 is run explicitly.

    Builds the aurora-shard-runtime Docker image automatically on first use
    if it doesn't exist yet (docker/shard.Dockerfile).

.PARAMETER ShardId
    Name for the new shard. Also becomes its CENTRAL_SERVER_ID. Letters,
    digits, hyphens, underscores only.

.PARAMETER Port
    Host port this shard's DreamDaemon listens on. Must not already be
    registered in ss13_shards or bound on this host.

.PARAMETER WhatIf
    Print what would happen without creating anything.

.EXAMPLE
    .\db_central_add_shard.ps1 -ShardId frontier-shard-1 -Port <port>
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ShardId,

    [Parameter(Mandatory = $true)]
    [int]$Port,

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if ($ShardId -notmatch '^[A-Za-z0-9_-]+$') {
    Write-Host "ShardId must be letters, digits, hyphens, or underscores only -- got '$ShardId'." -ForegroundColor Yellow
    exit 1
}
if ($Port -lt 1024 -or $Port -gt 65535) {
    Write-Host "Port must be between 1024 and 65535 -- got '$Port'." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Host "config\central_dbconfig_admin.txt not found -- run db_central_setup.ps1 first." -ForegroundColor Yellow
    exit 1
}

$dbConfig = @{
    address  = "localhost"
    port     = "3306"
    database = "aurora_central"
    login    = ""
    password = ""
}
foreach ($line in Get-Content $configPath) {
    $t = $line.Trim()
    if ($t.Length -eq 0 -or $t.StartsWith("#")) { continue }
    $parts = $t -split '\s+', 2
    if ($parts.Count -lt 2) { continue }
    $key = $parts[0].ToLower()
    if ($dbConfig.ContainsKey($key)) { $dbConfig[$key] = $parts[1] }
}
if (-not $dbConfig.login -or -not $dbConfig.password) {
    Write-Host "config\central_dbconfig_admin.txt is missing LOGIN/PASSWORD -- fill those in first." -ForegroundColor Yellow
    exit 1
}

$client = Get-Command mariadb -ErrorAction SilentlyContinue
if (-not $client) { $client = Get-Command mysql -ErrorAction SilentlyContinue }
if (-not $client) {
    Write-Host "No 'mariadb' or 'mysql' client found on PATH." -ForegroundColor Yellow
    exit 1
}

# ── Uniqueness checks -- fail loudly, never half-create a shard ─────────────

$existingSql = "SELECT shard_id FROM ``ss13_shards`` WHERE shard_id = '$ShardId' OR port = $Port;"
$existingResult = $existingSql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" -N 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to check ss13_shards for conflicts:" -ForegroundColor Red
    Write-Host "  $existingResult" -ForegroundColor DarkRed
    exit 1
}
if ($existingResult -and ($existingResult -join "").Trim().Length -gt 0) {
    Write-Host "ShardId '$ShardId' or port $Port is already registered in ss13_shards." -ForegroundColor Yellow
    exit 1
}

$dbContainer = "aurora-shard-$ShardId-db"
$serverContainer = "aurora-shard-$ShardId-server"
foreach ($name in @($dbContainer, $serverContainer)) {
    $found = docker ps -a --filter "name=^/$name`$" --format "{{.Names}}" 2>&1
    if ($found -eq $name) {
        Write-Host "A container named '$name' already exists. Remove it first (db_central_remove_shard.ps1) or pick a different ShardId." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Creating shard '$ShardId' on port $Port..." -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "-WhatIf: would create containers '$dbContainer' and '$serverContainer', provision a central DB login named '$ShardId', and register it in ss13_shards." -ForegroundColor Cyan
    exit 0
}

# ── Docker network -- dedicated to shards, never the compose-managed default ─

docker network inspect aurora-shards-net *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating aurora-shards-net Docker network..." -ForegroundColor Cyan
    docker network create aurora-shards-net | Out-Null
}

# ── Runtime image -- built once, reused by every shard ──────────────────────

$imageExists = docker images -q aurora-shard-runtime:latest 2>&1
if (-not $imageExists) {
    Write-Host "Building aurora-shard-runtime image (first shard only, this takes a while)..." -ForegroundColor Cyan
    docker build -t aurora-shard-runtime:latest -f (Join-Path $Root "docker\shard.Dockerfile") $Root
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Image build failed." -ForegroundColor Red
        exit 1
    }
}

# ── Central DB login for this shard -- same DML-only grant every server gets ─
# Inlined rather than calling db_central_add_server.ps1 as a subprocess: that
# script's output is human-readable text, not structured data, so there's no
# clean way to capture the generated password back into this script. Same SQL
# shape, kept in sync by hand -- see that script if this ever needs to change.

$chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$shardCentralPassword = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })

$tableListSql = "SELECT table_name FROM information_schema.tables WHERE table_schema = '$($dbConfig.database)' AND table_name != 'ss13_central_admins';"
$tableListResult = $tableListSql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" -N 2>&1
$tables = @($tableListResult -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$grantLines = @(
    "CREATE USER IF NOT EXISTS '$ShardId'@'%' IDENTIFIED BY '$shardCentralPassword';",
    "GRANT SELECT ON ``$($dbConfig.database)``.* TO '$ShardId'@'%';"
)
foreach ($table in $tables) {
    $grantLines += "GRANT INSERT, UPDATE, DELETE ON ``$($dbConfig.database)``.``$table`` TO '$ShardId'@'%';"
}
$grantLines += "FLUSH PRIVILEGES;"
$grantSql = $grantLines -join "`n"
$grantResult = $grantSql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to provision this shard's central DB login:" -ForegroundColor Red
    Write-Host "  $grantResult" -ForegroundColor DarkRed
    exit 1
}

# ── Shard-local config/data directories ──────────────────────────────────────

$shardDir = Join-Path $Root "shards\$ShardId"
$shardConfigDir = Join-Path $shardDir "config"
$shardDataDir = Join-Path $shardDir "data"
New-Item -ItemType Directory -Force -Path $shardConfigDir, $shardDataDir | Out-Null

# Local DB creds for the shard's OWN isolated local database -- fixed simple
# creds are fine here, same as db_setup.ps1's own local defaults: this
# container is never published to the host, only reachable from the shard's
# own server container over aurora-shards-net.
$localDbPassword = "aurora"

$localDbConfigLines = @(
    "# MySQL Connection Configuration -- generated by db_central_add_shard.ps1",
    "",
    "ADDRESS $dbContainer",
    "PORT 3306",
    "DATABASE aurora_persist",
    "LOGIN aurora",
    "PASSWORD $localDbPassword"
)
Set-Content (Join-Path $shardConfigDir "dbconfig.txt") -Value $localDbConfigLines -Encoding UTF8

# The admin config's ADDRESS is written for reaching central-db from THIS
# HOST (typically "localhost", since central-db is published to the host
# on its own port) -- but the shard's server container is not the host.
# "localhost" inside that container means the container itself, not
# central-db, which would silently break central connectivity entirely.
# host.docker.internal is Docker Desktop's own route back to the host, so
# the container reaches central-db the same way the host does: via its
# published port. Anything OTHER than localhost/127.0.0.1 (a real external
# hostname/IP for a genuinely remote central DB) is left unchanged -- that
# kind of address already resolves identically from inside a container.
$centralAddressForShard = $dbConfig.address
if ($centralAddressForShard -eq "localhost" -or $centralAddressForShard -eq "127.0.0.1") {
    $centralAddressForShard = "host.docker.internal"
}

$centralDbConfigLines = @(
    "# Central MySQL Connection Configuration -- generated by db_central_add_shard.ps1",
    "",
    "ADDRESS $centralAddressForShard",
    "PORT $($dbConfig.port)",
    "DATABASE $($dbConfig.database)",
    "LOGIN $ShardId",
    "PASSWORD $shardCentralPassword"
)
Set-Content (Join-Path $shardConfigDir "central_dbconfig.txt") -Value $centralDbConfigLines -Encoding UTF8

# config.txt: start from the host's own, force SQL_ENABLED/CENTRAL_SQL_ENABLED
# on, and set this shard's own unique CENTRAL_SERVER_ID plus SHARD_ID (the
# latter is what lets the in-game backup verb/auto-toggle detect they're
# running inside a shard and refuse cleanly -- see persistence_backups.dm).
$configTxt = Get-Content (Join-Path $Root "config\config.txt") -Raw
$configTxt = $configTxt -replace '(?m)^#+\s*SQL_ENABLED', 'SQL_ENABLED'
$configTxt = $configTxt -replace '(?m)^#+\s*CENTRAL_SQL_ENABLED', 'CENTRAL_SQL_ENABLED'
if ($configTxt -match '(?m)^#*\s*CENTRAL_SERVER_ID.*$') {
    $configTxt = $configTxt -replace '(?m)^#*\s*CENTRAL_SERVER_ID.*$', "CENTRAL_SERVER_ID $ShardId"
} else {
    $configTxt += "`nCENTRAL_SERVER_ID $ShardId`n"
}
if ($configTxt -match '(?m)^#*\s*SHARD_ID.*$') {
    $configTxt = $configTxt -replace '(?m)^#*\s*SHARD_ID.*$', "SHARD_ID $ShardId"
} else {
    $configTxt += "`nSHARD_ID $ShardId`n"
}
# The host's own SERVER_ROOT_PATH (config.txt) is an absolute path on the
# HOST's filesystem (e.g. a Windows dev machine's D:\...) -- meaningless,
# and actively wrong, inside this shard's own Linux container, where the
# repo is always mounted at /aurora (matching the Dockerfile's WORKDIR and
# the docker run -v below). Without this override, every world.shelleo()
# call made from inside the shard (backups included) would try to `cd` into
# a path that doesn't exist in the container and fail.
if ($configTxt -match '(?m)^#*\s*SERVER_ROOT_PATH.*$') {
    $configTxt = $configTxt -replace '(?m)^#*\s*SERVER_ROOT_PATH.*$', 'SERVER_ROOT_PATH /aurora'
} else {
    $configTxt += "`nSERVER_ROOT_PATH /aurora`n"
}
Set-Content (Join-Path $shardConfigDir "config.txt") -Value $configTxt -Encoding UTF8

# ── Local DB container ───────────────────────────────────────────────────────

Write-Host "Starting $dbContainer..." -ForegroundColor Cyan
docker run -d --name $dbContainer --network aurora-shards-net --restart unless-stopped `
    -e MARIADB_ROOT_PASSWORD=$localDbPassword `
    -e MARIADB_DATABASE=aurora_persist `
    -e MARIADB_USER=aurora `
    -e MARIADB_PASSWORD=$localDbPassword `
    mariadb:10.11 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start $dbContainer." -ForegroundColor Red
    exit 1
}

Write-Host "Waiting for $dbContainer to be ready..." -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    docker exec $dbContainer mariadb-admin ping -u root "-p$localDbPassword" *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
}
if (-not $ready) {
    Write-Host "$dbContainer did not become ready within 60 seconds." -ForegroundColor Red
    exit 1
}

Write-Host "Applying local schema to $dbContainer..." -ForegroundColor Cyan
$sqlDir = Join-Path $Root "SQL\migrate-2023"
foreach ($f in (Get-ChildItem -Path $sqlDir -Filter "V*.sql" | Sort-Object Name)) {
    Get-Content $f.FullName -Raw | docker exec -i $dbContainer mariadb -u root "-p$localDbPassword" --force aurora_persist 2>&1 | Out-Null
}

# ── API token, scoped ONLY to force_persistence_save -- for
# shard_watchdog.py, which has no in-game admin mob to trigger a save with.
# Written straight into ss13_api_commands/ss13_api_tokens/
# ss13_api_token_command (code/modules/world_api/api_command.dm's own auth
# tables) rather than waiting for the game to register the command itself
# (update_command_database is itself a Topic command -- chicken and egg),
# and scoped to exactly one command, not "_ANY", so a leaked token can
# never do more than trigger a save.
$apiTokenChars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
$apiTokenBytes = New-Object byte[] 40
[System.Security.Cryptography.RandomNumberGenerator]::Fill($apiTokenBytes)
$shardApiToken = -join ($apiTokenBytes | ForEach-Object { $apiTokenChars[$_ % $apiTokenChars.Length] })

$tokenSql = @"
INSERT INTO ``ss13_api_commands`` (command, description) VALUES ('force_persistence_save', 'Shard watchdog auto-save') ON DUPLICATE KEY UPDATE description = VALUES(description);
INSERT INTO ``ss13_api_tokens`` (token, creator, description) VALUES ('$shardApiToken', 'db_central_add_shard', 'Shard watchdog auto-save token');
INSERT INTO ``ss13_api_token_command`` (token_id, command_id)
  SELECT t.id, c.id FROM ``ss13_api_tokens`` t, ``ss13_api_commands`` c
  WHERE t.token = '$shardApiToken' AND c.command = 'force_persistence_save';
"@
$tokenSql | docker exec -i $dbContainer mariadb -u root "-p$localDbPassword" aurora_persist 2>&1 | Out-Null

# Saved here too, not just the DB -- otherwise the only way to ever see
# this again is a raw SQL SELECT against the central DB with admin creds.
Set-Content (Join-Path $shardConfigDir "api_token.txt") -Value $shardApiToken -Encoding UTF8

# ── Game server container ────────────────────────────────────────────────────

$shardBackupDir = Join-Path $Root "backups\shards\$ShardId"
New-Item -ItemType Directory -Force -Path $shardBackupDir | Out-Null

Write-Host "Starting $serverContainer on port $Port..." -ForegroundColor Cyan
# --add-host is a no-op on Docker Desktop (host.docker.internal already
# resolves there) but required for the same hostname to work on native
# Linux Docker Engine -- see the central_dbconfig.txt comment above.
# SHARD_ID env var + the backups/shards/<ShardId> mount are what let
# scripts/central/shard_backup_self.sh (run from inside this container by
# the in-game backup verb/auto-toggle, persistence_backups.dm) know its own
# identity and have somewhere writable to put the result -- everything else
# under /aurora is read-only.
docker run -d --name $serverContainer --network aurora-shards-net --restart unless-stopped `
    --add-host=host.docker.internal:host-gateway `
    -e "SHARD_ID=$ShardId" `
    -p "${Port}:${Port}" `
    -v "${Root}:/aurora:ro" `
    -v "${shardConfigDir}:/aurora/config:rw" `
    -v "${shardDataDir}:/aurora/data:rw" `
    -v "${shardBackupDir}:/aurora/backups/shards/${ShardId}:rw" `
    aurora-shard-runtime:latest aurorastation.dmb $Port -trusted | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start $serverContainer." -ForegroundColor Red
    exit 1
}

# ── Register ──────────────────────────────────────────────────────────────────

$registerSql = "INSERT INTO ``ss13_shards`` (shard_id, port, api_token, status, started_at) VALUES ('$ShardId', $Port, '$shardApiToken', 'running', NOW());"
$registerResult = $registerSql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Containers started, but failed to register in ss13_shards:" -ForegroundColor Red
    Write-Host "  $registerResult" -ForegroundColor DarkRed
    Write-Host "Register it manually or re-run once the DB issue is fixed." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Shard '$ShardId' is up on port $Port." -ForegroundColor Green
Write-Host "Join: byond://<this host>:$Port"
Write-Host "Manage: db_central_start_shard.ps1 / db_central_stop_shard.ps1 / db_central_remove_shard.ps1 -ShardId $ShardId"
Write-Host "API token (force_persistence_save): $shardApiToken"
Write-Host "  saved to shards\$ShardId\config\api_token.txt"
