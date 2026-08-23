<#
.SYNOPSIS
    Stops every currently-running shard -- convenience wrapper around
    db_central_stop_shard.ps1, looping over ss13_shards. Useful before a
    host reboot/maintenance without needing to stop each shard by hand.
    Does not touch aurora-db/aurora-central-db.

.EXAMPLE
    .\db_central_stop_all_shards.ps1
#>

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if (-not (Test-Path $configPath)) {
    Write-Host "config\central_dbconfig_admin.txt not found -- run db_central_setup.ps1 first." -ForegroundColor Yellow
    exit 1
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

$sql = "SELECT shard_id FROM ``ss13_shards`` WHERE status = 'running';"
$result = $sql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" -N 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to list running shards:" -ForegroundColor Red
    Write-Host "  $result" -ForegroundColor DarkRed
    exit 1
}

$shardIds = @($result -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($shardIds.Count -eq 0) {
    Write-Host "No running shards." -ForegroundColor Cyan
    exit 0
}

Write-Host "Stopping $($shardIds.Count) shard(s): $($shardIds -join ', ')" -ForegroundColor Cyan
foreach ($shardId in $shardIds) {
    & "$PSScriptRoot\db_central_stop_shard.ps1" -ShardId $shardId
}

Write-Host "Done." -ForegroundColor Green
