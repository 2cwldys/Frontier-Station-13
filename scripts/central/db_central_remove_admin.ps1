<#
.SYNOPSIS
    Removes one ckey from the central admin roster (ss13_central_admins).

.DESCRIPTION
    The counterpart to db_central_add_admin.ps1. Once removed, that ckey is
    not an admin on ANY server with CENTRAL_SQL_ENABLED on -- takes effect
    on each server's next reboot (admin roster loads once at boot, same as
    the existing local system already works).

    Connects using config\central_dbconfig_admin.txt -- the ADMIN tier, same
    as db_central_add_admin.ps1.

.PARAMETER Ckey
    The ckey to remove. Normalized to lowercase.

.PARAMETER WhatIf
    Print the SQL without actually running it.

.EXAMPLE
    .\db_central_remove_admin.ps1 -Ckey someadmin
    .\db_central_remove_admin.ps1 -Ckey someadmin -WhatIf
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Ckey,

    [switch]$WhatIf
)

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

$Ckey = $Ckey.ToLower() -replace '[^a-z0-9@._-]', ''
if (-not $Ckey) {
    Write-Host "Ckey is empty after normalization." -ForegroundColor Yellow
    exit 1
}

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

$sql = "DELETE FROM ``ss13_central_admins`` WHERE ckey = '$Ckey';"

Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "SQL to run:" -ForegroundColor Cyan
Write-Host "  $sql" -ForegroundColor DarkGray
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing removed." -ForegroundColor Cyan
    exit 0
}

$result = $sql | & $client.Source `
    -h $dbConfig.address -P $dbConfig.port `
    -u $dbConfig.login "-p$($dbConfig.password)" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED:" -ForegroundColor Red
    Write-Host "  $result" -ForegroundColor DarkRed
    exit 1
}

Write-Host "'$Ckey' removed from the central admin roster." -ForegroundColor Green
Write-Host "Takes effect on every centrally-enabled server's next reboot." -ForegroundColor DarkGray
