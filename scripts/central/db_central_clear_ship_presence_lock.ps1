<#
.SYNOPSIS
    Ship-lock counterpart to db_central_clear_presence_lock.ps1 -- disaster-
    recovery escape hatch for an ss13_presence_lock row with
    subject_type = 'ship'.

.DESCRIPTION
    NOTE: as of this writing, nothing in the codebase actually acquires a
    'ship' presence lock -- every presenceLockAcquire()/presenceLockRelease()
    call site (persistence_cryo.dm, new_player.dm) only ever uses
    subject_type = 'character'. Cross-server ship safety currently comes
    from ownership/existence sync instead (CENTRAL_SYNC_SHIPS,
    persistence_shuttles.dm), not this table. 'ship' is a reserved ENUM
    value (SQL\migrate-central\V001__presence_lock.sql) for if/when ship
    presence-locking is actually implemented. This script exists so that
    day doesn't also require writing this tool from scratch -- until then,
    it will always report "nothing to clear".

    Keyed by global_ship_id ("[origin server_id]:[shuttle_id]",
    V154__drydock_global_ship_id.sql / persistence_shuttles.dm), NOT a bare
    shuttle_id -- shuttle_id alone is a per-server AUTO_INCREMENT with no
    cross-server meaning (two different servers can mint the same value for
    two different ships), which is exactly the ambiguity global_ship_id was
    introduced to solve for CENTRAL_SYNC_SHIPS. Using a bare shuttle_id here
    would reintroduce that same ambiguity into presence-lock lookups.

    Connects using config\central_dbconfig_admin.txt -- the ADMIN tier, same
    as every other scripts\central\db_central_*.ps1 tool.

    WARNING: this bypasses the same-server-only release rule entirely. If the
    holding server is actually still up (just unreachable from here right
    now), clearing the lock could let the same ship be retrieved/played in
    two places at once. Only use this once you've confirmed the holding
    server/shard is permanently gone (e.g. after db_central_remove_shard.ps1).

.PARAMETER OriginServerId
    The central_server_id of the server that originally locked this ship
    (the part before the ':' in global_ship_id).

.PARAMETER ShuttleId
    The ship's local shuttle_id on that origin server (the part after the
    ':' in global_ship_id).

.PARAMETER Force
    Skip the typed confirmation prompt.

.PARAMETER WhatIf
    Print the SQL without actually running it.

.EXAMPLE
    .\db_central_clear_ship_presence_lock.ps1 -OriginServerId frontier-1 -ShuttleId 42 -WhatIf
    .\db_central_clear_ship_presence_lock.ps1 -OriginServerId frontier-1 -ShuttleId 42
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OriginServerId,

    [Parameter(Mandatory = $true)]
    [int]$ShuttleId,

    [switch]$Force,

    [switch]$WhatIf
)

$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $Root "config\central_dbconfig_admin.txt"

if ($OriginServerId -notmatch '^[A-Za-z0-9_-]+$') {
    Write-Host "OriginServerId must be letters, digits, hyphens, or underscores only -- got '$OriginServerId'." -ForegroundColor Yellow
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

$globalShipId = "${OriginServerId}:${ShuttleId}"

Write-Host "Target: $($dbConfig.address):$($dbConfig.port)/$($dbConfig.database) via $($client.Name)" -ForegroundColor DarkGray
Write-Host ""

$lookupSql = "SELECT server_id, locked_at FROM ``ss13_presence_lock`` WHERE subject_type = 'ship' AND subject_id = '$globalShipId';"
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
    Write-Host "No presence lock held for ship '$globalShipId' -- nothing to clear." -ForegroundColor Cyan
    Write-Host "(Expected today -- nothing in the codebase acquires a 'ship' presence lock yet. See this script's own .DESCRIPTION.)" -ForegroundColor DarkGray
    exit 0
}

$lockFields = $lookupLine -split "`t"
$heldByServer = $lockFields[0]
$lockedAt = $lockFields[1]

Write-Host "Found a presence lock:" -ForegroundColor Cyan
Write-Host "  Ship (global_ship_id): $globalShipId"
Write-Host "  Held by:               $heldByServer"
Write-Host "  Locked at:             $lockedAt"
Write-Host ""
Write-Host "This bypasses the same-server-only release rule entirely. If '$heldByServer' is" -ForegroundColor Yellow
Write-Host "actually still up (just unreachable from here right now), clearing this lock" -ForegroundColor Yellow
Write-Host "could let this ship be retrieved/played in two places at once. Only proceed if" -ForegroundColor Yellow
Write-Host "you've confirmed '$heldByServer' is permanently gone." -ForegroundColor Yellow
Write-Host ""

$deleteSql = "DELETE FROM ``ss13_presence_lock`` WHERE subject_type = 'ship' AND subject_id = '$globalShipId';"
Write-Host "SQL to run:" -ForegroundColor Cyan
Write-Host "  $deleteSql" -ForegroundColor DarkGray
Write-Host ""

if ($WhatIf) {
    Write-Host "-WhatIf: nothing cleared." -ForegroundColor Cyan
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Type the global_ship_id to confirm ('$globalShipId')"
    if ($confirm -ne $globalShipId) {
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

Write-Host "Presence lock for ship '$globalShipId' cleared (was held by '$heldByServer')." -ForegroundColor Green
