<#
.SYNOPSIS
    Self-fixing build loop for Aurora-Persistence.

.DESCRIPTION
    Builds the game via the Juke build chain (same as tools\build\build.bat,
    minus the interactive pause). On compile errors, spawns a one-shot headless
    Claude agent to fix them, then rebuilds -- repeating until the build is
    clean or -MaxIterations is reached. Each fix agent exits when its pass
    completes; nothing is left running.

.PARAMETER MaxIterations
    Maximum build+fix cycles before giving up. Default 5.

.PARAMETER ReportOnly
    Build once and print the structured error summary without fixing anything.
    Use when a supervising agent wants to address the errors itself.

.EXAMPLE
    .\debug-compile.ps1
    .\debug-compile.ps1 -ReportOnly
    .\debug-compile.ps1 -MaxIterations 3
#>
param(
    [int]$MaxIterations = 5,
    [switch]$ReportOnly
)

$ErrorActionPreference = 'Continue'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LogFile  = Join-Path $PSScriptRoot 'debug-compile.log'
$MaxErrorLines = 200

function Invoke-Build {
    # Runs the Juke build chain, teeing output to console + log.
    # Returns a hashtable: ExitCode, ErrorLines
    Push-Location $RepoRoot
    try {
        $output = New-Object System.Collections.Generic.List[string]
        # javascript.bat bootstraps bun/node and runs build.ts (BuildTarget: tgui + DM)
        & cmd /c "call `"tools\bootstrap\javascript.bat`" `"tools\build\build.ts`" 2>&1" | ForEach-Object {
            $line = "$_"
            Write-Host $line
            $output.Add($line)
        }
        $exitCode = $LASTEXITCODE
        $output | Add-Content -Path $LogFile

        # DM compile errors: path\file.dm:LINE:error: message
        # Also catch generic "error:" lines so tgui/juke failures surface too.
        $errors = $output | Where-Object {
            $_ -match '\.dm:\d+:\s*error' -or $_ -match '(?i)\berror(:|\s+TS\d+)'
        } | Where-Object {
            # Filter obvious non-error chatter that happens to contain the word
            $_ -notmatch '(?i)0 errors'
        } | Select-Object -Unique

        return @{ ExitCode = $exitCode; ErrorLines = @($errors) }
    }
    finally {
        Pop-Location
    }
}

function Write-Summary {
    param([array]$Errors, [int]$Iteration)
    $shown = $Errors | Select-Object -First $MaxErrorLines
    Write-Host ''
    Write-Host '===== DEBUG-COMPILE SUMMARY ====='
    if ($Errors.Count -eq 0) {
        Write-Host 'RESULT: CLEAN'
    } else {
        Write-Host "RESULT: FAILED ($($Errors.Count) errors) [iteration $Iteration/$MaxIterations]"
        $shown | ForEach-Object { Write-Host $_ }
        if ($Errors.Count -gt $MaxErrorLines) {
            Write-Host "... and $($Errors.Count - $MaxErrorLines) more (see log)"
        }
    }
    Write-Host "Full log: $LogFile"
    Write-Host '================================='
    Write-Host ''
}

function Invoke-FixAgent {
    param([array]$Errors)
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) {
        Write-Host 'ERROR: `claude` CLI not found on PATH. Install Claude Code (https://claude.com/claude-code) or run with -ReportOnly.'
        exit 2
    }

    $errorBlock = ($Errors | Select-Object -First $MaxErrorLines) -join "`n"
    $prompt = @"
You are a compile-error fix agent for the Aurora-Persistence BYOND codebase (working directory is the repo root).
Fix ONLY the compile errors listed below. Rules:
- Minimal changes; no scope creep, no refactoring, no drive-by cleanups.
- ASCII only in .dm files: never use em dashes or any Unicode. Use -- instead.
- Do not run the build yourself; the caller rebuilds after you exit.
- If an error's fix is ambiguous, choose the smallest change that preserves existing behavior.

COMPILE ERRORS:
$errorBlock
"@

    Write-Host ">>> Spawning fix agent for $($Errors.Count) errors..."
    Push-Location $RepoRoot
    try {
        & claude -p $prompt --dangerously-skip-permissions 2>&1 | ForEach-Object {
            Write-Host "[fix-agent] $_"
            "[fix-agent] $_" | Add-Content -Path $LogFile
        }
        Write-Host '>>> Fix agent finished.'
    }
    finally {
        Pop-Location
    }
}

# ---- main ----
Set-Content -Path $LogFile -Value "debug-compile started $(Get-Date -Format o)`n"

for ($i = 1; $i -le $MaxIterations; $i++) {
    Write-Host ">>> Build iteration $i/$MaxIterations..."
    $result = Invoke-Build

    if ($result.ExitCode -eq 0 -and $result.ErrorLines.Count -eq 0) {
        Write-Summary -Errors @() -Iteration $i
        exit 0
    }

    # Build failed but nothing matched the error patterns -- surface the tail of
    # the log instead of looping blind.
    if ($result.ErrorLines.Count -eq 0) {
        Write-Host 'Build failed but no error lines matched known patterns. Log tail:'
        Get-Content $LogFile -Tail 40 | ForEach-Object { Write-Host $_ }
        exit 1
    }

    Write-Summary -Errors $result.ErrorLines -Iteration $i

    if ($ReportOnly) {
        exit 1
    }
    if ($i -eq $MaxIterations) {
        Write-Host ">>> Still failing after $MaxIterations iterations. Giving up."
        exit 1
    }

    Invoke-FixAgent -Errors $result.ErrorLines
}
