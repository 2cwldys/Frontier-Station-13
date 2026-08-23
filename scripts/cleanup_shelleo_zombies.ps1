<#
.SYNOPSIS
    Finds and kills leftover shelleo() OS processes tied to THIS repo, and
    sweeps their stale scratch files out of data/.

.DESCRIPTION
    world.shelleo() (code/__HELPERS/shell.dm) shells out via
    "wscript ... scripts\hidden_run.vbs" -> a hidden "cmd /c" running a
    generated wrapper .bat under data\. If that chain ever hits something
    that blocks on stdin -- an interactive `pause`, most concretely -- with no
    real console attached to answer it, the process never exits. BYOND's own
    shell() call for it is left hanging (or the world moves on regardless, per
    whatever timeout/behavior applies), but the OS process itself just sits
    there, holding its "> data\shelleo...out" redirect handle open forever.

    This is exactly what produced this repo's own worst instance of the bug:
    a zombie cmd.exe from 01:10 AM was still alive at 07:28 AM and its
    still-open output file got read back by an unrelated "Trigger Database
    Backup" run as if it were the backup's own result. shell.dm's out/err
    filenames are now qualified with GLOB.round_id + an ever-incrementing
    counter specifically so a NEW boot can no longer collide with an OLD
    zombie's file -- but that only stops the SYMPTOM (misattributed output).
    It does not stop a hung child process from existing, consuming a
    process slot and a stdin wait forever, or its file from cluttering data\.
    Run this whenever that is suspected, or on a schedule, to actually clear
    the zombies out.

.PARAMETER WhatIf
    List what would be killed/deleted without touching anything.

.NOTES
    Safe to run at any time, including while the game server is up -- it only
    ever targets processes whose command line names THIS repo's own
    hidden_run.vbs or a data\shelleo*.bat wrapper, so a live, healthy shelleo()
    call in progress (which normally completes in well under a second) is
    exceedingly unlikely to be caught mid-flight, and even if one is, it is
    just one shelled command that would need to be retried -- not a
    destructive action against game state.
#>

param(
    [switch]$WhatIf
)

$Root = Split-Path $PSScriptRoot -Parent
$DataDir = Join-Path $Root "data"

Write-Host "Scanning for shelleo processes tied to $Root ..." -ForegroundColor Cyan

# Match on command line, not process name -- "cmd.exe" and "wscript.exe" alone
# are far too common (build tooling, other repos, unrelated automation) to
# kill on name. Every real shelleo() invocation's command line contains
# either hidden_run.vbs or one of the generated data\shelleo*.bat wrappers,
# and both are unique enough substrings to be a safe, specific match.
$RootEscaped = [regex]::Escape($Root)
$Pattern = "(hidden_run\.vbs|shelleo_cd.*\.bat|shelleo\.[^""]*\.(out|err))"

$Victims = Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -and
        $_.CommandLine -match $Pattern -and
        ($_.CommandLine -match $RootEscaped -or $_.ExecutablePath -like "$Root*")
    }

if (-not $Victims) {
    Write-Host "No stuck shelleo processes found." -ForegroundColor Green
} else {
    foreach ($proc in $Victims) {
        $age = (Get-Date) - $proc.CreationDate
        Write-Host ""
        Write-Host "PID $($proc.ProcessId)  $($proc.Name)  alive for $([int]$age.TotalMinutes) min" -ForegroundColor Yellow
        Write-Host "  $($proc.CommandLine)" -ForegroundColor DarkGray
        if ($WhatIf) {
            Write-Host "  -> would kill (WhatIf)" -ForegroundColor DarkYellow
        } else {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                Write-Host "  -> killed" -ForegroundColor Red
            } catch {
                Write-Host "  -> failed to kill: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "Scanning for stale shelleo scratch files in $DataDir ..." -ForegroundColor Cyan

# Both naming eras: the current data\shelleo_<round_id>_<n>.(out|err) /
# data\shelleo_cd_<round_id>_<n>.bat, and pre-fix leftovers that predate
# round-id qualification (data\shelleo.<n>.(out|err), data\shelleo_cd.bat,
# data\shelleo_cd_<n>.bat with no round id) -- a server that has been running
# since before both fixes landed can still have either kind lying around.
$StalePatterns = @(
    "shelleo.*.out", "shelleo.*.err", "shelleo_cd*.bat"
)

$StaleFiles = foreach ($pat in $StalePatterns) {
    Get-ChildItem -Path $DataDir -Filter $pat -File -ErrorAction SilentlyContinue
}
$StaleFiles = $StaleFiles | Sort-Object FullName -Unique

if (-not $StaleFiles) {
    Write-Host "No stale scratch files found." -ForegroundColor Green
} else {
    foreach ($f in $StaleFiles) {
        Write-Host "  $($f.Name)  ($($f.Length) bytes, $($f.LastWriteTime))" -ForegroundColor DarkGray
        if ($WhatIf) {
            Write-Host "    -> would delete (WhatIf)" -ForegroundColor DarkYellow
        } else {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "    -> deleted" -ForegroundColor Red
        }
    }
}

Write-Host ""
if ($WhatIf) {
    Write-Host "WhatIf run -- nothing was actually killed or deleted." -ForegroundColor Cyan
} else {
    Write-Host "Done." -ForegroundColor Green
}
