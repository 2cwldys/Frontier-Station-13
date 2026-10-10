<#
.SYNOPSIS
    All-in-one health check for the Aurora persistence database: periodic-save
    freshness, persistent-object expiration, and JSON blob integrity, all from
    one command instead of a pile of manual queries.

.DESCRIPTION
    Runs four independent checks against the live database:

    1. SAVE FRESHNESS -- how long ago each Finalize()-backed table was last
       written. fire() -> forceSaveAll() is supposed to touch every one of
       these every ~30 minutes (persistence.dm). If forceSaveAll() stops
       being invoked for any reason (an admin pause left on, an auto-pause
       stuck, an exception early in the chain, etc.), every table it drives
       goes stale together, silently, with nothing else in the game
       signaling it. This section catches that on the first run rather than
       days later.

    2. PERSISTENT-OBJECT EXPIRATION -- ss13_persistent_objects rows whose
       expires_at has already passed. These are excluded from loading by
       objectsDatabaseGetActiveEntries() (persistence_objects_sql.dm) even
       though the row is still sitting there intact. This is the only table
       in the persistence codebase shaped this way (a load query gating rows
       on NOW() vs a stored timestamp) -- if a future feature adds another
       one, add it to the $ExpiringTables list below and this check covers
       it automatically.

    3. JSON BLOB VALIDITY -- every known JSON/text blob column, checked with
       JSON_VALID() and scanned for the U+FFFD replacement-character
       fingerprint (the signature of a lossy charset reinterpretation, e.g.
       from an ill-considered column type change). Add new columns to
       $JsonColumns as they're introduced.

    4. ROW COUNT SNAPSHOT -- quick per-table counts, so a sudden drop is
       visible to the eye on the next run even without a prior baseline
       saved anywhere.

    Exit code is non-zero if anything reaches CRITICAL, so this can be wired
    into a scheduled task/health monitor, not just run by hand.

.PARAMETER StaleWarningMinutes
    Minutes since last save before a table is flagged STALE (yellow).
    Defaults to 45 (1.5x the normal 30-minute autosave interval).

.PARAMETER StaleCriticalMinutes
    Minutes since last save before a table is flagged CRITICAL (red).
    Defaults to 360 (6 hours -- twelve missed autosaves in a row is well
    past "had a rough tick," and into "the timer isn't firing at all").

.EXAMPLE
    .\db_diagnostics.ps1
    .\db_diagnostics.ps1 -StaleWarningMinutes 60 -StaleCriticalMinutes 180
#>

param(
    [int]$StaleWarningMinutes = 45,
    [int]$StaleCriticalMinutes = 360
)

$ErrorActionPreference = 'Stop'
$WarnCount = 0
$CritCount = 0

function Write-Section($title) {
    Write-Output ""
    Write-Output "=== $title ==="
}

function Write-Status($level, $text) {
    switch ($level) {
        'OK'   { Write-Output "  [OK]       $text" }
        'WARN' { Write-Output "  [WARN]     $text"; $script:WarnCount++ }
        'CRIT' { Write-Output "  [CRITICAL] $text"; $script:CritCount++ }
        default { Write-Output "  $text" }
    }
}

function Invoke-Sql($sql) {
    # -N: skip the column-header row, so callers can split raw value lines
    # directly instead of discarding a header first.
    docker exec aurora-db mariadb -N -u aurora -paurora aurora_persist -e $sql
}

function Invoke-SqlTable($sql) {
    # Keeps headers -- for output meant to be read as-is, not parsed.
    docker exec aurora-db mariadb -u aurora -paurora aurora_persist -e $sql
}

# --- Connectivity (same two-gate pattern as db_backup.ps1/db_restore.ps1) ---
$MaxWaitSeconds = 10
$PollSeconds = 2

$Waited = 0
$DaemonReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $DaemonReady = $true; break }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DaemonReady) {
    Write-Error "Docker daemon did not respond within ${MaxWaitSeconds}s."
    exit 2
}

$Waited = 0
$DbReady = $false
while ($Waited -lt $MaxWaitSeconds) {
    docker exec aurora-db mysqladmin ping -u aurora -paurora --silent 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $DbReady = $true; break }
    Start-Sleep -Seconds $PollSeconds
    $Waited += $PollSeconds
}
if (-not $DbReady) {
    Write-Error "aurora-db didn't answer a ping within ${MaxWaitSeconds}s."
    exit 2
}

Write-Output "Aurora DB Diagnostics -- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# =============================================================================
# 1. SAVE FRESHNESS -- tables driven by the periodic forceSaveAll() sweep.
#    Add a row here whenever a new Finalize() proc starts writing its own
#    saved_at/created_at-style column, so future stalls show up the same way.
# =============================================================================
Write-Section "1. Save freshness (periodic autosave health)"

$FreshnessTables = @(
    @{ Table = "ss13_worldstate_objects"; Column = "saved_at";  Label = "World-state (machinery/airlock state)" },
    @{ Table = "ss13_char_health";        Column = "saved_at";  Label = "Character health" },
    @{ Table = "ss13_char_inventory";     Column = "saved_at";  Label = "Character inventory" },
    @{ Table = "ss13_char_skills";        Column = "saved_at";  Label = "Character skills" },
    @{ Table = "ss13_char_identity";      Column = "saved_at";  Label = "Character identity" },
    @{ Table = "ss13_char_lace_dna";      Column = "saved_at";  Label = "Neural lace DNA" }
)

foreach ($t in $FreshnessTables) {
    $Raw = Invoke-Sql "SELECT TIMESTAMPDIFF(MINUTE, MAX($($t.Column)), NOW()) FROM $($t.Table);"
    $Minutes = $Raw.Trim()
    if ($Minutes -eq '' -or $Minutes -eq 'NULL') {
        Write-Status 'WARN' "$($t.Label) ($($t.Table)): table is empty -- nothing to compare."
        continue
    }
    $MinutesInt = [int]$Minutes
    $Age = if ($MinutesInt -ge 1440) { "$([math]::Round($MinutesInt/1440,1))d ago" }
           elseif ($MinutesInt -ge 60) { "$([math]::Round($MinutesInt/60,1))h ago" }
           else { "${MinutesInt}m ago" }

    if ($MinutesInt -ge $StaleCriticalMinutes) {
        Write-Status 'CRIT' "$($t.Label) ($($t.Table)): last write was $Age -- forceSaveAll() has very likely stopped firing entirely. Check the F5 admin stat panel's Persistence line (PAUSED vs active) and server logs for 'Periodic save' entries."
    } elseif ($MinutesInt -ge $StaleWarningMinutes) {
        Write-Status 'WARN' "$($t.Label) ($($t.Table)): last write was $Age -- one or more autosave cycles were likely missed."
    } else {
        Write-Status 'OK' "$($t.Label) ($($t.Table)): last write $Age."
    }
}
Write-Output "  Note: ss13_floor_items has no per-row timestamp of its own -- it's rewritten"
Write-Output "  in the same forceSaveAll() pass as ss13_worldstate_objects, so that row above"
Write-Output "  is also floor_items' own freshness by proxy."

# =============================================================================
# 2. PERSISTENT-OBJECT EXPIRATION
# =============================================================================
Write-Section "2. Persistent-object expiration (ss13_persistent_objects)"

$ExpiringTables = @(
    @{ Table = "ss13_persistent_objects"; ExpiresColumn = "expires_at" }
    # Add another entry here if a future table ever gates loading on NOW() vs
    # a stored expiry column -- confirmed via grep (see script header) to be
    # the only one that does today.
)

foreach ($t in $ExpiringTables) {
    $Raw = Invoke-Sql "SELECT COUNT(*), SUM(CASE WHEN $($t.ExpiresColumn) <= NOW() THEN 1 ELSE 0 END), MIN(CASE WHEN $($t.ExpiresColumn) <= NOW() THEN $($t.ExpiresColumn) END) FROM $($t.Table);"
    $Parts = $Raw -split "\s+"
    $Total = $Parts[0]
    $Expired = if ($Parts[1] -and $Parts[1] -ne 'NULL') { [int]$Parts[1] } else { 0 }
    $OldestExpiry = if ($Parts.Count -gt 2 -and $Parts[2] -ne 'NULL') { "$($Parts[2]) $($Parts[3])" } else { $null }

    if ($Total -eq '0') {
        Write-Status 'OK' "$($t.Table): empty table."
        continue
    }

    $Pct = [math]::Round(($Expired / [int]$Total) * 100, 1)
    if ($Expired -eq 0) {
        Write-Status 'OK' "$($t.Table): 0/$Total expired."
    } elseif ($Pct -ge 25) {
        Write-Status 'CRIT' "$($t.Table): $Expired/$Total ($Pct%) expired, oldest since $OldestExpiry -- run db_fix_expired_objects.ps1."
    } else {
        Write-Status 'WARN' "$($t.Table): $Expired/$Total ($Pct%) expired, oldest since $OldestExpiry -- run db_fix_expired_objects.ps1 -WhatIf to review."
    }
}

if ($CritCount -gt 0 -or $WarnCount -gt 0) {
    Write-Output ""
    Write-Output "  Top expired types:"
    Invoke-SqlTable "SELECT type, COUNT(*) AS expired FROM ss13_persistent_objects WHERE expires_at <= NOW() GROUP BY type ORDER BY expired DESC LIMIT 10;" | ForEach-Object { Write-Output "  $_" }
}

# =============================================================================
# 3. JSON BLOB VALIDITY
# =============================================================================
Write-Section "3. JSON blob validity"

$JsonColumns = @(
    @{ Table = "ss13_char_health";        Column = "organ_damage_json" },
    @{ Table = "ss13_char_inventory";     Column = "inventory_json" },
    @{ Table = "ss13_char_skills";        Column = "skills_json" },
    @{ Table = "ss13_char_identity";      Column = "flavor_texts" },
    @{ Table = "ss13_char_identity";      Column = "languages_json" },
    @{ Table = "ss13_char_lace_dna";      Column = "dna_json" },
    @{ Table = "ss13_worldstate_objects"; Column = "content" },
    @{ Table = "ss13_persistent_objects"; Column = "content" },
    @{ Table = "ss13_floor_items";        Column = "extra" }
)

foreach ($c in $JsonColumns) {
    $Raw = Invoke-Sql "SELECT
        SUM(CASE WHEN $($c.Column) IS NOT NULL AND $($c.Column) != '' AND JSON_VALID($($c.Column)) = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN $($c.Column) LIKE CONCAT('%', UNHEX('EFBFBD'), '%') THEN 1 ELSE 0 END)
        FROM $($c.Table);"
    $Parts = $Raw -split "\s+"
    $Invalid = if ($Parts[0] -and $Parts[0] -ne 'NULL') { [int]$Parts[0] } else { 0 }
    $Mangled = if ($Parts.Count -gt 1 -and $Parts[1] -ne 'NULL') { [int]$Parts[1] } else { 0 }

    if ($Invalid -eq 0 -and $Mangled -eq 0) {
        Write-Status 'OK' "$($c.Table).$($c.Column): clean."
    } else {
        Write-Status 'CRIT' "$($c.Table).$($c.Column): $Invalid invalid-JSON row(s), $Mangled with a replacement-character fingerprint (likely charset/encoding damage)."
    }
}

# =============================================================================
# 4. ROW COUNT SNAPSHOT
# =============================================================================
Write-Section "4. Row count snapshot"

$SnapshotTables = @(
    "ss13_char_health", "ss13_char_inventory", "ss13_char_skills",
    "ss13_char_identity", "ss13_char_lace_dna",
    "ss13_worldstate_objects", "ss13_persistent_objects", "ss13_floor_items"
)
$UnionSql = ($SnapshotTables | ForEach-Object { "SELECT '$_' AS tbl, COUNT(*) AS row_count FROM $_" }) -join "`nUNION ALL`n"
Invoke-SqlTable "$UnionSql;" | ForEach-Object { Write-Output "  $_" }

# =============================================================================
# Summary
# =============================================================================
Write-Section "Summary"
if ($CritCount -gt 0) {
    Write-Output "  $CritCount critical issue(s), $WarnCount warning(s). See above."
    exit 1
} elseif ($WarnCount -gt 0) {
    Write-Output "  $WarnCount warning(s), no critical issues."
    exit 0
} else {
    Write-Output "  All checks passed clean."
    exit 0
}
