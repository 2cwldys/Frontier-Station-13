param([switch]$DryRun)

$configFile = Join-Path $PSScriptRoot "sync-config.ini"
if (-not (Test-Path $configFile)) {
    Write-Host "ERROR: sync-config.ini not found at $configFile" -ForegroundColor Red
    Write-Host "Create it with keys: aurora3, repo" -ForegroundColor Red
    exit 1
}
$config = @{}
foreach ($line in (Get-Content $configFile)) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -match '^\s*(.+?)\s*=\s*(.+?)\s*$') {
        $config[$Matches[1]] = $Matches[2]
    }
}
$aurora3 = $config["aurora3"]
$repo    = $config["repo"]
if (-not $aurora3 -or -not $repo) {
    Write-Host "ERROR: sync-config.ini is missing one or more required keys: aurora3, repo" -ForegroundColor Red
    exit 1
}
$logFile  = "$repo\scripts\upstream-conflicts.log"
$syncFile = "$repo\scripts\.last-sync-commit"

# Files we've modified in the repo -- diff these, don't auto-overwrite
# aurorastation.dme is handled separately via DME merge below
$conflictFiles = @(
    "code\game\objects\structures.dm",
    "code\game\objects\structures\_machinery.dm",
    "code\modules\mob\abstract\new_player\new_player.dm"
)

# Our persistence #include lines to inject into aurorastation.dme
$persistenceIncludes1 = @(
    '#include "code\controllers\subsystems\persistence\persistence_atmos.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_closets.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_floor_items.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_decals.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_economy.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_factions.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_mobs.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_cryo.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_world_ready.dm"'
)
$persistenceIncludes2 = @(
    '#include "code\controllers\subsystems\persistence\persistence_records.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_shuttles.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_research.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_templates.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_turfs.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_removed_structures.dm"',
    '#include "code\controllers\subsystems\persistence\persistence_worldstate.dm"'
)

# After cryopod.dm: inject faction_beacon machinery
$machineryIncludes = @(
    '#include "code\game\objects\structures\machinery\faction_beacon.dm"'
)

# After modular_computer\damage.dm: inject faction shackling verbs
$modularComputerIncludes = @(
    '#include "code\modules\modular_computers\computers\modular_computer\faction.dm"'
)

# After new_player.dm: inject persistent menu
$newPlayerIncludes = @(
    '#include "code\modules\mob\abstract\new_player\persistent_menu.dm"'
)

# After shuttle_supply.dm: inject player-built shuttle core
$shuttleCoreIncludes = @(
    '#include "code\modules\shuttles\shuttle_core.dm"'
)

# After command\card.dm: inject faction management program
$modularProgramIncludes = @(
    '#include "code\modules\modular_computers\file_system\programs\command\faction_manage.dm"'
)

# After civilian\cargo_control.dm: inject cargo exports program
$cargoExportsIncludes = @(
    '#include "code\modules\modular_computers\file_system\programs\civilian\cargo_exports.dm"'
)

function IsConflict($rel) {
    foreach ($c in $conflictFiles) {
        if ($rel -eq $c) { return $true }
    }
    if ($rel -match "^SQL[/\\]") { return $true }
    return $false
}

# --- 1. Pull Aurora.3 ---
Write-Host "Pulling Aurora.3 master..." -ForegroundColor Cyan
Push-Location $aurora3
git pull origin master
$upstreamCommit = git rev-parse --short HEAD
Pop-Location

# --- 2. Get last sync point ---
$lastSync = if (Test-Path $syncFile) { Get-Content $syncFile } else { $null }
if ($lastSync) {
    Write-Host "Last sync: $lastSync" -ForegroundColor Gray
} else {
    Write-Host "First sync -- will diff all SQL and conflict files." -ForegroundColor Yellow
}

# If already synced to this commit, skip unnecessary work
if ($lastSync -and $lastSync.Trim() -eq $upstreamCommit.Trim()) {
    Write-Host ""
    Write-Host "Already up to date with Aurora.3 @ $upstreamCommit -- nothing to sync." -ForegroundColor Green
    Write-Host ""
    $answer = Read-Host "Would you like to attempt to compile anyway? (Y/N)"
    if ($answer -match "^[Yy]") {
        $isUnix = $IsLinux -or $IsMacOS
        $buildFilter = if ($isUnix) { "build.sh" } else { "build.bat" }
        $buildFile = Get-ChildItem -Path $repo -Recurse -Filter $buildFilter -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($buildFile) {
            Write-Host "Launching build in a new window..." -ForegroundColor Cyan
            if ($isUnix) {
                Start-Process "bash" -ArgumentList "`"$($buildFile.FullName)`"" -WorkingDirectory $buildFile.DirectoryName
            } else {
                Start-Process "cmd.exe" -ArgumentList "/c `"$($buildFile.FullName)`"" -WorkingDirectory $buildFile.DirectoryName
            }
        } else {
            Write-Host "$buildFilter not found anywhere in the repo." -ForegroundColor Red
        }
    }
    exit 0
}

# --- 3. Copy Aurora.3 safe files into repo ---
Write-Host "Copying Aurora.3 safe files into repo..." -ForegroundColor Cyan
$autoCount = 0

Push-Location $aurora3
$allFiles = (git ls-files) -split "`n"
Pop-Location

foreach ($rel in $allFiles) {
    $rel = $rel.Trim()
    if (-not $rel) { continue }
    if (IsConflict $rel) { continue }

    $src  = Join-Path $aurora3 $rel
    $dest = Join-Path $repo ($rel -replace '/','\\')
    if (-not (Test-Path $src)) { continue }

    if (-not $DryRun) {
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force $destDir | Out-Null }
        Copy-Item $src $dest -Force
    }
    $autoCount++
}

# --- 4. Merge aurorastation.dme: Aurora.3 base + our persistence includes ---
Write-Host "Merging aurorastation.dme..." -ForegroundColor Cyan
$dmeSrc  = Join-Path $aurora3 "aurorastation.dme"
$dmeDest = Join-Path $repo "aurorastation.dme"
if (Test-Path $dmeSrc) {
    $merged = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content $dmeSrc)) {
        $merged.Add($line)
        $trimmed = $line.Trim()
        if ($trimmed -eq '#include "code\controllers\subsystems\persistence\persistence.dm"') {
            foreach ($inc in $persistenceIncludes1) { $merged.Add($inc) }
        }
        if ($trimmed -eq '#include "code\controllers\subsystems\persistence\persistence_objects_sql.dm"') {
            foreach ($inc in $persistenceIncludes2) { $merged.Add($inc) }
        }
        if ($trimmed -eq '#include "code\game\objects\structures\machinery\cryopod.dm"') {
            foreach ($inc in $machineryIncludes) { $merged.Add($inc) }
        }
        if ($trimmed -eq '#include "code\modules\modular_computers\computers\modular_computer\damage.dm"') {
            foreach ($inc in $modularComputerIncludes) { $merged.Add($inc) }
        }
        if ($trimmed -eq '#include "code\modules\mob\abstract\new_player\new_player.dm"') {
            foreach ($inc in $newPlayerIncludes) { $merged.Add($inc) }
        }
        if ($trimmed -eq '#include "code\modules\shuttles\shuttle_supply.dm"') {
            foreach ($inc in $shuttleCoreIncludes) { $merged.Add($inc) }
        }
        if ($trimmed -eq '#include "code\modules\modular_computers\file_system\programs\command\card.dm"') {
            foreach ($inc in $modularProgramIncludes) { $merged.Add($inc) }
        }
        if ($trimmed -eq '#include "code\modules\modular_computers\file_system\programs\civilian\cargo_control.dm"') {
            foreach ($inc in $cargoExportsIncludes) { $merged.Add($inc) }
        }
    }
    if (-not $DryRun) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllLines($dmeDest, $merged, $utf8NoBom)
    }
    Write-Host "  aurorastation.dme merged with persistence includes." -ForegroundColor Green
}

# --- 5. Generate conflict log: diff Aurora.3 vs repo's current versions ---
Write-Host "Generating conflict log..." -ForegroundColor Cyan
$reviewTargets = New-Object System.Collections.Generic.List[string]
foreach ($f in $conflictFiles) { $reviewTargets.Add($f) }

Push-Location $aurora3
$sqlFiles = (git ls-files "SQL/") -split "`n"
Pop-Location
foreach ($s in $sqlFiles) {
    $s = $s.Trim()
    if ($s) { $reviewTargets.Add($s) }
}

$log = @()
$log += "# Upstream Conflict Log -- Aurora.3 @ $upstreamCommit"
$log += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$log += "#"
$log += "# Paste this file into Claude and say:"
$log += "# 'Apply these upstream diffs to our repo versions, keeping persistence additions.'"
$log += ""

$conflictCount = 0

foreach ($rel in $reviewTargets) {
    $aurora3File = Join-Path $aurora3 ($rel -replace '/','\\')
    $repoFile    = Join-Path $repo    ($rel -replace '/','\\')

    $log += ("=" * 70)
    $log += "FILE: $rel"
    $log += ("=" * 70)
    $log += ""

    Push-Location $aurora3
    $diff = $null
    if ($lastSync) {
        $diff = git diff $lastSync HEAD -- $rel 2>$null
    } else {
        if (Test-Path $aurora3File) {
            $tmpA = [System.IO.Path]::GetTempFileName()
            $tmpB = [System.IO.Path]::GetTempFileName()
            git show "HEAD:$($rel -replace '\\','/')" 2>$null | Set-Content $tmpA
            if (Test-Path $repoFile) {
                Copy-Item $repoFile $tmpB -Force
            } else {
                "" | Set-Content $tmpB
            }
            $diff = git diff --no-index $tmpA $tmpB 2>$null
            Remove-Item $tmpA,$tmpB -Force -ErrorAction SilentlyContinue
        }
    }
    Pop-Location

    if ($diff) {
        $log += $diff
        $conflictCount++
    } else {
        $log += "(no changes)"
    }
    $log += ""
}

if (-not $DryRun) {
    $log | Out-File $logFile -Encoding UTF8
    $upstreamCommit | Set-Content $syncFile
}

# --- 6. Report ---
Write-Host ""
Write-Host "Auto-copied from Aurora.3 : $autoCount files" -ForegroundColor Green
Write-Host "DME merged                 : persistence includes injected" -ForegroundColor Green
Write-Host "Conflict log written to    : $logFile" -ForegroundColor Yellow
Write-Host "Files needing review       : $conflictCount" -ForegroundColor Yellow
Write-Host ""
Write-Host "Open scripts\upstream-conflicts.log and paste into Claude." -ForegroundColor Cyan
Write-Host "Then test the build and commit when ready." -ForegroundColor Cyan
Write-Host ""
$answer = Read-Host "Would you like to attempt to compile? (Y/N)"
if ($answer -match "^[Yy]") {
    $isUnix = $IsLinux -or $IsMacOS
    $buildFilter = if ($isUnix) { "build.sh" } else { "build.bat" }
    $buildFile = Get-ChildItem -Path $repo -Recurse -Filter $buildFilter -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($buildFile) {
        Write-Host "Launching build in a new window..." -ForegroundColor Cyan
        if ($isUnix) {
            Start-Process "bash" -ArgumentList "`"$($buildFile.FullName)`"" -WorkingDirectory $buildFile.DirectoryName
        } else {
            Start-Process "cmd.exe" -ArgumentList "/c `"$($buildFile.FullName)`"" -WorkingDirectory $buildFile.DirectoryName
        }
    } else {
        Write-Host "$buildFilter not found anywhere in the repo." -ForegroundColor Red
    }
} else {
    Write-Host "Skipping compile." -ForegroundColor Gray
}
