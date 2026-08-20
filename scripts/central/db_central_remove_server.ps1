<#
.SYNOPSIS
    Revokes one server's access to the central (cross-server) database.

.DESCRIPTION
    The counterpart to db_central_add_server.ps1. Drops that server's login
    entirely -- since every authorized server has its OWN login (never a
    shared one), this affects only the named server; every other server's
    access, config, and credentials are completely untouched.

    That server's own config\central_dbconfig.txt still has the now-dead
    credentials on disk -- nothing here reaches out to change that, since
    this script has no way to touch another machine's files. Its
    SScentraldb connection will simply start failing auth and logging that,
    the same as any other bad-credentials case (see Connect(), centraldb.dm).

    Connects using config\central_dbconfig_admin.txt -- the ADMIN tier, same
    as db_central_add_server.ps1 and db_central_update.ps1.

.PARAMETER ServerId
    Identity of the server to revoke -- whatever was passed to
    db_central_add_server.ps1 when it was authorized.

.PARAMETER SourceIP
    Must match whatever -SourceIP the server was created with (default '%'
    if none was given). MariaDB treats 'user'@'host' as one combined
    identity -- 'name'@'203.0.113.7' and 'name'@'%' are two entirely
    different accounts, so dropping the wrong host pattern silently no-ops
    (IF EXISTS) and leaves the real account live. If you don't remember
    which SourceIP a server was created with, check with:
    SELECT host FROM mysql.user WHERE user = '<ServerId>';

.PARAMETER WhatIf
    Print what would run without actually dropping anything.

.EXAMPLE
    .\db_central_remove_server.ps1 -ServerId frontier-alpha
    .\db_central_remove_server.ps1 -ServerId frontier-beta -WhatIf
    .\db_central_remove_server.ps1 -ServerId frontier-gamma -SourceIP 203.0.113.7
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ServerId,

    [string]$SourceIP = '%',

    [switch]$WhatIf
)

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if ($ServerId -notmatch '^[A-Za-z0-9_-]+$') {
    Write-Host "ServerId must be letters, digits, hyphens, or underscores only -- got '$ServerId'." -ForegroundColor Yellow
    exit 1
}

if ($SourceIP -notmatch '^[A-Za-z0-9.:%-]+$') {
    Write-Host "SourceIP must be an IP, host pattern (e.g. 203.0.113.%), or '%' -- got '$SourceIP'." -ForegroundColor Yellow
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

# IF EXISTS: revoking a server that's already gone (or never existed) is a
# normal, expected outcome here, not an error -- same reasoning
# discord_bot_stop.bat already uses for "asked to stop something already
# stopped".
$sql = "DROP USER IF EXISTS '$ServerId'@'$SourceIP'; FLUSH PRIVILEGES;"

Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "SQL to run:" -ForegroundColor Cyan
Write-Host "  $sql" -ForegroundColor DarkGray
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing dropped." -ForegroundColor Cyan
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

Write-Host "Revoked '$ServerId'@'$SourceIP'. Every other authorized server is unaffected." -ForegroundColor Green
Write-Host "That server's own central_dbconfig.txt still has the now-dead credentials --" -ForegroundColor DarkGray
Write-Host "its SScentraldb connection will simply start failing auth from here." -ForegroundColor DarkGray
