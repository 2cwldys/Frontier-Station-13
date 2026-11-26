@echo off
:: Syncs this fork with upstream Aurorastation/Aurora.3 via a real git merge
:: (sync-upstream.sh) -- replaces the old PowerShell file-copy version, which
:: blindly overwrote any fork file not on its hardcoded 3-file list.
::
:: Thin wrapper only -- same convention as discord_bot_start.bat/discord_bot_stop.bat.
:: Needs Git Bash (ships with Git for Windows) on PATH.

setlocal
set "ROOT=%~dp0.."
bash "%ROOT%\scripts\sync-upstream.sh"
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (
    echo sync-upstream: done -- see scripts\.sync-summary.md for the full report.
) else if "%RC%"=="2" (
    echo sync-upstream: merged with unresolved conflicts that need your attention -- see above.
) else (
    echo sync-upstream: failed ^(exit %RC%^) -- see output above.
)
pause
exit /b %RC%
