<#
.SYNOPSIS
    Adds (or updates) one ckey in the central admin roster
    (ss13_central_admins) -- the shared list every server with
    CENTRAL_SQL_ENABLED on treats as its ENTIRE admin roster (see
    load_admins_from_central_database(), auth.dm). A ckey not in this table
    is not an admin on ANY centrally-enabled server, no matter what that
    server's own local admins.txt/ss13_admins says.

.DESCRIPTION
    Connects using config\central_dbconfig_admin.txt -- the ADMIN tier, same
    as db_central_add_server.ps1/db_central_update.ps1. Deliberately NOT the
    per-server runtime tier: that login is intentionally restricted (see
    db_central_add_server.ps1) to read-only access on this specific table,
    even though it has read/write on every other central table -- a
    compromised or buggy game server must never be able to grant itself
    admin by writing to ss13_central_admins directly.

    `rank` is a display label only (shown in admin chat/logs) -- it is NOT
    resolved against any server's own config\admin_ranks.json the way the
    legacy admins.txt system works. `flags` is the actual enforced R_*
    rights bitmask, stored and used as-is (same shape the existing local
    ss13_admins table already uses -- see load_admins_from_database(),
    auth.dm). This means one row means the same thing on every server
    regardless of that server's own admin_ranks.json.

    Common flag values (code/__DEFINES/admin.dm) -- combine with bitwise OR
    if composing your own set, or just use R_ALL for full admin:
      R_ALL          = 32767 (0x7FFF) -- every right
      R_ADMIN        = 1
      R_BAN          = 2
      R_PERMISSIONS  = 32

.PARAMETER Ckey
    The ckey to authorize. Normalized to lowercase.

.PARAMETER Rank
    Display label only -- e.g. "Head Admin". Does not affect rights.

.PARAMETER Flags
    Raw R_* rights bitmask (integer). See .DESCRIPTION for common values.

.PARAMETER WhatIf
    Print the SQL without actually running it.

.EXAMPLE
    .\db_central_add_admin.ps1 -Ckey someadmin -Rank "Head Admin" -Flags 32767
    .\db_central_add_admin.ps1 -Ckey someadmin -Rank "Moderator" -Flags 35 -WhatIf
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Ckey,

    [Parameter(Mandatory = $true)]
    [string]$Rank,

    [Parameter(Mandatory = $true)]
    [int]$Flags,

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

# Same tiny "KEY value" format GetDBConfig() (centraldb.dm) reads at runtime,
# re-parsed here since this is a standalone script with no access to the DM
# config loader -- same approach every other db_central_*.ps1 script uses.
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

# Rank is free text (a display label) -- escape single quotes so it can't
# break out of the SQL string. Ckey was already normalized to a safe
# charset above; Flags is a PowerShell [int], so it can't carry SQL either.
$rankEscaped = $Rank -replace "'", "''"

$sql = @"
INSERT INTO ``ss13_central_admins`` (ckey, ``rank``, flags, added_by)
VALUES ('$Ckey', '$rankEscaped', $Flags, '$($dbConfig.login)')
ON DUPLICATE KEY UPDATE ``rank`` = VALUES(``rank``), flags = VALUES(flags);
"@

Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "SQL to run:" -ForegroundColor Cyan
Write-Host $sql -ForegroundColor DarkGray
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing changed." -ForegroundColor Cyan
} else {
    $result = $sql | & $client.Source `
        -h $dbConfig.address -P $dbConfig.port `
        -u $dbConfig.login "-p$($dbConfig.password)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED:" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor DarkRed
        exit 1
    }
    Write-Host "'$Ckey' is now in the central admin roster as '$Rank' (flags $Flags)." -ForegroundColor Green
    Write-Host "Takes effect on every centrally-enabled server's next reboot (admin roster loads once at boot)." -ForegroundColor DarkGray
}
