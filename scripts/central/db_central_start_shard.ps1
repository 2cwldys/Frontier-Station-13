<#
.SYNOPSIS
    Resumes an existing, stopped shard -- starts its two containers as-is.
    Does NOT recreate anything; local data (turfs/objects/machinery) from
    before it was stopped is untouched. See db_central_add_shard.ps1 to
    create a new shard instead.

.PARAMETER ShardId
    The shard to resume.

.EXAMPLE
    .\db_central_start_shard.ps1 -ShardId frontier-shard-1
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
    Write-Host "-WhatIf: would start '$dbContainer' then '$serverContainer', and mark '$ShardId' running in ss13_shards." -ForegroundColor Cyan
    exit 0
}

Write-Host "Starting $dbContainer..." -ForegroundColor Cyan
docker start $dbContainer | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start $dbContainer -- does shard '$ShardId' exist? (db_central_list_shards.ps1)" -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 3

Write-Host "Starting $serverContainer..." -ForegroundColor Cyan
docker start $serverContainer | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to start $serverContainer." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Host "$dbContainer/$serverContainer started, but config\central_dbconfig_admin.txt is missing -- couldn't update ss13_shards status." -ForegroundColor Yellow
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
    $sql = "UPDATE ``ss13_shards`` SET status = 'running', started_at = NOW() WHERE shard_id = '$ShardId';"
    $sql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" 2>&1 | Out-Null
}

Write-Host "Shard '$ShardId' resumed." -ForegroundColor Green
