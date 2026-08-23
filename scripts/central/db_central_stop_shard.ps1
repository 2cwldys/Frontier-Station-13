<#
.SYNOPSIS
    Pauses a running shard -- stops its two containers without removing
    them. Local data (turfs/objects/machinery) is preserved untouched;
    resume later with db_central_start_shard.ps1. For permanent teardown,
    use db_central_remove_shard.ps1 instead.

.PARAMETER ShardId
    The shard to stop.

.EXAMPLE
    .\db_central_stop_shard.ps1 -ShardId frontier-shard-1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ShardId,

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if ($ShardId -notmatch '^[A-Za-z0-9_-]+$') {
    Write-Host "ShardId must be letters, digits, hyphens, or underscores only -- got '$ShardId'." -ForegroundColor Yellow
    exit 1
}

$dbContainer = "aurora-shard-$ShardId-db"
$serverContainer = "aurora-shard-$ShardId-server"

if ($WhatIf) {
    Write-Host "-WhatIf: would stop '$serverContainer' then '$dbContainer', and mark '$ShardId' stopped in ss13_shards. Data is preserved." -ForegroundColor Cyan
    exit 0
}

# Server first, then its DB -- so DreamDaemon isn't left trying to reach a
# database that just vanished underneath it.
Write-Host "Stopping $serverContainer..." -ForegroundColor Cyan
docker stop $serverContainer | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to stop $serverContainer -- does shard '$ShardId' exist? (db_central_list_shards.ps1)" -ForegroundColor Red
    exit 1
}

Write-Host "Stopping $dbContainer..." -ForegroundColor Cyan
docker stop $dbContainer | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to stop $dbContainer." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Host "$serverContainer/$dbContainer stopped, but config\central_dbconfig_admin.txt is missing -- couldn't update ss13_shards status." -ForegroundColor Yellow
    exit 0
}

$dbConfig = @{ address = "localhost"; port = "3306"; database = "aurora_central"; login = ""; password = "" }
foreach ($line in Get-Content $configPath) {
    $t = $line.Trim()
    if ($t.Length -eq 0 -or $t.StartsWith("#")) { continue }
    $parts = $t -split '\s+', 2
    if ($parts.Count -lt 2) { continue }
    $key = $parts[0].ToLower()
    if ($dbConfig.ContainsKey($key)) { $dbConfig[$key] = $parts[1] }
}

$client = Get-Command mariadb -ErrorAction SilentlyContinue
if (-not $client) { $client = Get-Command mysql -ErrorAction SilentlyContinue }
if ($client -and $dbConfig.login -and $dbConfig.password) {
    $sql = "UPDATE ``ss13_shards`` SET status = 'stopped' WHERE shard_id = '$ShardId';"
    $sql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" 2>&1 | Out-Null
}

Write-Host "Shard '$ShardId' stopped. Data preserved -- resume with db_central_start_shard.ps1." -ForegroundColor Green
