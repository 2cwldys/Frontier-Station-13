<#
.SYNOPSIS
    Permanently removes a shard -- both containers, their volumes, its
    config/data directories, its central DB login, and its ss13_shards
    row. Unlike db_central_stop_shard.ps1, this is NOT resumable
    afterward. Confirms before doing anything unless -Force is passed.

.PARAMETER ShardId
    The shard to remove.

.PARAMETER Force
    Skip the confirmation prompt.

.PARAMETER WhatIf
    Print what would be removed without removing anything.

.EXAMPLE
    .\db_central_remove_shard.ps1 -ShardId frontier-shard-1 -WhatIf
    .\db_central_remove_shard.ps1 -ShardId frontier-shard-1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ShardId,

    [switch]$Force,

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
$shardDir = Join-Path $Root "shards\$ShardId"

Write-Host "This will PERMANENTLY delete shard '$ShardId': both containers, their data, and its central DB login." -ForegroundColor Yellow
Write-Host "  Containers: $serverContainer, $dbContainer"
Write-Host "  Directory:  $shardDir"

if ($WhatIf) {
    Write-Host "-WhatIf: nothing removed." -ForegroundColor Cyan
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Type the shard id to confirm ('$ShardId')"
    if ($confirm -ne $ShardId) {
        Write-Host "Confirmation did not match -- cancelled." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Removing $serverContainer..." -ForegroundColor Cyan
docker rm -f $serverContainer *> $null

Write-Host "Removing $dbContainer..." -ForegroundColor Cyan
docker rm -f -v $dbContainer *> $null

if (Test-Path $shardDir) {
    Write-Host "Removing $shardDir..." -ForegroundColor Cyan
    Remove-Item -Recurse -Force $shardDir
}

if (Test-Path $configPath) {
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
        Write-Host "Revoking central DB login and unregistering..." -ForegroundColor Cyan
        $sql = "DROP USER IF EXISTS '$ShardId'@'%'; DELETE FROM ``ss13_shards`` WHERE shard_id = '$ShardId'; FLUSH PRIVILEGES;"
        $sql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" 2>&1 | Out-Null
    }
}

Write-Host "Shard '$ShardId' fully removed." -ForegroundColor Green
