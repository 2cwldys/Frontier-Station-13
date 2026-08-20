<#
.SYNOPSIS
    Lists everyone currently in the central admin roster
    (ss13_central_admins) -- the shared list every server with
    CENTRAL_SQL_ENABLED on treats as its ENTIRE admin roster (see
    load_admins_from_central_database(), auth.dm).

.DESCRIPTION
    Read-only. Connects using config\central_dbconfig_admin.txt -- the ADMIN
    tier, same as db_central_add_admin.ps1/db_central_remove_admin.ps1.

.EXAMPLE
    .\db_central_list_admins.ps1
#>

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if (-not (Test-Path $configPath)) {
    Write-Host "config\central_dbconfig_admin.txt not found -- run db_central_setup.ps1, or copy it from config\example\central_dbconfig_admin.txt and fill in the central database's admin credentials yourself." -ForegroundColor Yellow
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
    if ($dbConfig.ContainsKey($key)) {
        $dbConfig[$key] = $parts[1]
    }
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

Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray
Write-Host ""

$sql = "SELECT ckey, ``rank``, flags, added_by, added_at FROM ``ss13_central_admins`` ORDER BY ckey;"
$result = $sql | & $client.Source `
    -h $dbConfig.address -P $dbConfig.port `
    -u $dbConfig.login "-p$($dbConfig.password)" `
    --table 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED:" -ForegroundColor Red
    Write-Host "  $result" -ForegroundColor DarkRed
    exit 1
}

Write-Host $result
Write-Host ""
Write-Host "Add/update: db_central_add_admin.ps1 -Ckey <ckey> -Rank <label> -Flags <int>"
Write-Host "Remove:     db_central_remove_admin.ps1 -Ckey <ckey>"
