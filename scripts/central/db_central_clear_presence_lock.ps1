<#
.SYNOPSIS
    Disaster-recovery escape hatch for a stuck cross-server presence lock
    (ss13_presence_lock) -- the standalone-script version of the in-game
    "Force-Clear Presence Lock" admin verb (force_clear_presence_lock(),
    admin_verbs.dm), for when the server/shard holding the lock is
    permanently gone and nobody can run the verb from it anymore.

.DESCRIPTION
    Same underlying operation as presenceLockForceRelease() (persistence_cryo.dm):
    an unconditional DELETE from ss13_presence_lock by (subject_type, subject_id),
    NOT scoped to server_id the way presenceLockRelease() is by design -- that's
    exactly why this is a break-glass tool and not just "run the verb instead".

    Only "character" locks exist in practice today (subject_id =
    "[ckey]|[char_name]", the same composite persistence_position_cache and
    friends already key by) -- ss13_presence_lock's subject_type ENUM also
    allows 'ship', but nothing in the codebase acquires a ship-type lock yet,
    so this script (like the admin verb it mirrors) only handles characters.

    Connects using config\central_dbconfig_admin.txt -- the ADMIN tier, same
    as every other scripts\central\db_central_*.ps1 tool. This is meant to be
    run by whoever administers the central database directly, not by a game
    server.

    WARNING: this bypasses the same-server-only release rule entirely. If the
    holding server is actually still up (just unreachable from here right
    now) and that character is being actively played there, clearing the lock
    lets the same character be played in two places at once. Only use this
    once you've confirmed the holding server/shard is permanently gone (e.g.
    after db_central_remove_shard.ps1).

.PARAMETER Ckey
    The locked character's ckey. Normalized to lowercase.

.PARAMETER CharName
    The locked character's exact, case-sensitive character name.

.PARAMETER Force
    Skip the typed confirmation prompt.

.PARAMETER WhatIf
    Print the SQL without actually running it.

.EXAMPLE
    .\db_central_clear_presence_lock.ps1 -Ckey someplayer -CharName "John Doe" -WhatIf
    .\db_central_clear_presence_lock.ps1 -Ckey someplayer -CharName "John Doe"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Ckey,

    [Parameter(Mandatory = $true)]
    [string]$CharName,

    [switch]$Force,

    [switch]$WhatIf
)

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

$Ckey = $Ckey.ToLower() -replace '[^a-z0-9@._-]', ''
if (-not $Ckey) {
    Write-Host "Ckey is empty after normalization." -ForegroundColor Yellow
    exit 1
}
if (-not $CharName.Trim()) {
    Write-Host "CharName is empty." -ForegroundColor Yellow
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

$charNameEscaped = $CharName -replace "'", "''"
$subjectIdEscaped = "$Ckey|$charNameEscaped"

Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray
Write-Host ""

$lookupSql = "SELECT server_id, locked_at FROM ``ss13_presence_lock`` WHERE subject_type = 'character' AND subject_id = '$subjectIdEscaped';"
$lookupResult = $lookupSql | & $client.Source `
    -h $dbConfig.address -P $dbConfig.port `
    -u $dbConfig.login "-p$($dbConfig.password)" --skip-column-names 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED to look up the lock:" -ForegroundColor Red
    Write-Host "  $lookupResult" -ForegroundColor DarkRed
    exit 1
}

$lookupLine = ($lookupResult | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
if (-not $lookupLine) {
    Write-Host "No presence lock held for '$CharName' ($Ckey) -- nothing to clear." -ForegroundColor Cyan
    exit 0
}

$lockFields = $lookupLine -split "`t"
$heldByServer = $lockFields[0]
$lockedAt = $lockFields[1]

Write-Host "Found a presence lock:" -ForegroundColor Cyan
Write-Host "  Character:   $CharName ($Ckey)"
Write-Host "  Held by:     $heldByServer"
Write-Host "  Locked at:   $lockedAt"
Write-Host ""
Write-Host "This bypasses the same-server-only release rule entirely. If '$heldByServer' is" -ForegroundColor Yellow
Write-Host "actually still up (just unreachable from here right now) and this character is" -ForegroundColor Yellow
Write-Host "being actively played there, clearing this lock lets it be played in two places" -ForegroundColor Yellow
Write-Host "at once. Only proceed if you've confirmed '$heldByServer' is permanently gone." -ForegroundColor Yellow
Write-Host ""

$deleteSql = "DELETE FROM ``ss13_presence_lock`` WHERE subject_type = 'character' AND subject_id = '$subjectIdEscaped';"
Write-Host "SQL to run:" -ForegroundColor Cyan
Write-Host "  $deleteSql" -ForegroundColor DarkGray
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing cleared." -ForegroundColor Cyan
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Type the ckey to confirm ('$Ckey')"
    if ($confirm -ne $Ckey) {
        Write-Host "Confirmation did not match -- cancelled." -ForegroundColor Yellow
        exit 1
    }
}

$result = $deleteSql | & $client.Source `
    -h $dbConfig.address -P $dbConfig.port `
    -u $dbConfig.login "-p$($dbConfig.password)" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAILED:" -ForegroundColor Red
    Write-Host "  $result" -ForegroundColor DarkRed
    exit 1
}

Write-Host "Presence lock for '$CharName' ($Ckey) cleared (was held by '$heldByServer')." -ForegroundColor Green
