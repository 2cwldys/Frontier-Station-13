<#
.SYNOPSIS
    Lists every registered shard (ss13_shards) alongside its live Docker
    status, so "what shards exist and are they up" is one command.

.EXAMPLE
    .\db_central_list_shards.ps1
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

$sql = "SELECT shard_id, port, status, created_at, started_at FROM ``ss13_shards`` ORDER BY shard_id;"
$result = $sql | & $client.Source -h $dbConfig.address -P $dbConfig.port -u $dbConfig.login "-p$($dbConfig.password)" --table 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED:" -ForegroundColor Red
    Write-Host "  $result" -ForegroundColor DarkRed
    exit 1
}

Write-Host "Registered shards:" -ForegroundColor Cyan
Write-Host $result
Write-Host ""
Write-Host "Live Docker status:" -ForegroundColor Cyan
docker ps -a --filter "name=aurora-shard-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
