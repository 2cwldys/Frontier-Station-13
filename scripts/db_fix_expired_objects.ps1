<#
.SYNOPSIS
    Reports on (and optionally fixes) persistent-object rows in
    ss13_persistent_objects whose expires_at has already passed.

.DESCRIPTION
    ss13_persistent_objects tracks dynamically-placed/modified structures --
    pipes, cables, girders, doors, windows, inflatables, and similar. Each
    row's expires_at is meant to be pushed forward by the periodic autosave
    (fire() -> forceSaveAll() -> objectsFinalize(), persistence.dm /
    persistence_objects.dm) for as long as the object still exists in the
    live world. If that periodic save stops running for any reason, nothing
    renews expires_at, and rows silently age past it. The load query
    (objectsDatabaseGetActiveEntries(), persistence_objects_sql.dm)
    deliberately excludes anything past its own expiry -- so real, still-
    standing structures stop being restored on boot even though the
    underlying saved data is still completely intact.

    Run this with no arguments first to see the scope of the problem. It
    only changes anything when passed -Apply, and only ever extends
    expires_at (an UPDATE) -- it never deletes or recreates rows. It does
    NOT fix why the periodic save stopped running; it only recovers rows
    that are still sitting in the table, not yet purged by
    objectsDatabaseCleanEntries()'s own cleanup grace period.

    Reviving every expired row is deliberately blunt, and that has a real
    side effect: some of those rows were expired correctly, on purpose --
    an object was torn down and replaced, the old row aged out exactly as
    designed, and a new row already exists for whatever replaced it at the
    same spot. Blanket-reviving the old one too puts two active rows at one
    (type, x, y, z) location, and both get spawned on load -- stacked
    duplicates (multiple air canisters/crates/cable segments on top of each
    other). So -Apply always runs a second pass after extending expiry:
    for every (type, x, y, z, map_path) with more than one ACTIVE row, it
    keeps only the highest id (id is unique and strictly reflects creation
    order, unlike created_at which can tie at one-second resolution) and
    re-expires the rest -- same soft, reversible re-expire as the main fix,
    never a delete.

.PARAMETER ExtendDays
    How many days to push expires_at forward (from right now) for every
    currently-expired row. Defaults to 30.

.PARAMETER Apply
    Actually perform the update. Without this, the script only reports
    what it would change.

.EXAMPLE
    .\db_fix_expired_objects.ps1
    .\db_fix_expired_objects.ps1 -Apply
    .\db_fix_expired_objects.ps1 -Apply -ExtendDays 60
#>

param(
    [int]$ExtendDays = 30,
    [switch]$Apply
)

# Same two-gate readiness check as db_backup.ps1/db_restore.ps1 -- see those
# scripts' own comments for why this is split into daemon-ready vs
# DB-ready rather than one combined check.
$MaxWaitSeconds = 10
$PollSeconds = 2

$Waited = 0
$DaemonReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $DaemonReady = $true
        break
    }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DaemonReady) {
    Write-Error "Docker daemon did not respond within ${MaxWaitSeconds}s."
    exit 1
}

$Waited = 0
$DbReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker exec aurora-db mysqladmin ping -u aurora -paurora --silent 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $DbReady = $true
        break
    }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DbReady) {
    Write-Error "aurora-db didn't answer a ping within ${MaxWaitSeconds}s."
    exit 1
}

Write-Output "=== Expired persistent-object rows, by type ==="
docker exec aurora-db mariadb -u aurora -paurora aurora_persist -e "
SELECT type, COUNT(*) AS expired_count
FROM ss13_persistent_objects
WHERE expires_at <= NOW()
GROUP BY type
ORDER BY expired_count DESC
LIMIT 25;
"

$TotalsRaw = docker exec aurora-db mariadb -N -u aurora -paurora aurora_persist -e "
SELECT COUNT(*),
       SUM(CASE WHEN expires_at <= NOW() THEN 1 ELSE 0 END)
FROM ss13_persistent_objects;
"
$Parts = $TotalsRaw -split "\s+"
$Total = $Parts[0]
$Expired = if ($Parts[1] -and $Parts[1] -ne 'NULL') { $Parts[1] } else { 0 }

Write-Output ""
Write-Output "Total rows: $Total -- currently expired: $Expired"

if ($Expired -eq 0) {
    Write-Output "Nothing to fix."
    exit 0
}

if (-not $Apply) {
    Write-Output ""
    Write-Output "This was a report only -- no changes made."
    Write-Output "Re-run with -Apply to extend expires_at by $ExtendDays day(s) on the $Expired row(s) above."
    exit 0
}

Write-Output ""
Write-Output "Extending expires_at by $ExtendDays day(s) on $Expired row(s)..."
docker exec aurora-db mariadb -u aurora -paurora aurora_persist -e "
UPDATE ss13_persistent_objects
SET expires_at = DATE_ADD(NOW(), INTERVAL $ExtendDays DAY)
WHERE expires_at <= NOW();
"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Update failed -- check credentials/permissions."
    exit 1
}

Write-Output ""
Write-Output "Checking for duplicate active rows this revival may have created..."
$DupeRaw = docker exec aurora-db mariadb -N -u aurora -paurora aurora_persist -e "
SELECT COUNT(*) FROM (
  SELECT type, x, y, z, map_path FROM ss13_persistent_objects
  WHERE expires_at > NOW()
  GROUP BY type, x, y, z, map_path HAVING COUNT(*) > 1
) t;
"
$DupeGroups = $DupeRaw.Trim()

if ($DupeGroups -ne '0') {
    Write-Output "Found $DupeGroups location(s) with more than one active row -- re-expiring all but the most recently created at each."
    docker exec aurora-db mariadb -u aurora -paurora aurora_persist -e "
UPDATE ss13_persistent_objects p
JOIN (
    SELECT type, x, y, z, map_path, MAX(id) AS keep_id
    FROM ss13_persistent_objects
    WHERE expires_at > NOW()
    GROUP BY type, x, y, z, map_path
    HAVING COUNT(*) > 1
) latest
  ON p.type = latest.type AND p.x = latest.x AND p.y = latest.y AND p.z = latest.z AND p.map_path = latest.map_path
SET p.expires_at = DATE_SUB(NOW(), INTERVAL 1 DAY)
WHERE p.id != latest.keep_id AND p.expires_at > NOW();
"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Deduplication update failed -- check credentials/permissions. The expiry extension above already applied; re-run this script to retry deduplication alone."
        exit 1
    }
} else {
    Write-Output "None found -- no duplicate locations among active rows."
}

$AfterRaw = docker exec aurora-db mariadb -N -u aurora -paurora aurora_persist -e "
SELECT COUNT(*), SUM(CASE WHEN expires_at > NOW() THEN 1 ELSE 0 END) FROM ss13_persistent_objects;
"
$AfterParts = $AfterRaw -split "\s+"
Write-Output ""
Write-Output "Done. $($AfterParts[1])/$($AfterParts[0]) rows now active, zero duplicate locations among them."
Write-Output "These will load back in on the next server restart."
Write-Output ""
Write-Output "Note: this fixes the symptom, not the cause -- if the periodic"
Write-Output "autosave (forceSaveAll) is still not running, these rows will"
Write-Output "start expiring again over time."
