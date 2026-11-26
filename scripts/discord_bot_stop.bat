@echo off
:: Stops the Discord status bot. Invoked from SSpersistence.Shutdown() via
:: world.shelleo() when the server is genuinely closing (not on a soft round
:: reboot -- see the hard-reset guard there), so the bot does not outlive the
:: server it reports on.
::
:: Being asked to stop an already-stopped bot is a normal outcome, not an
:: error: exits 0 whether it killed anything or found nothing to kill.
::
:: taskkill /F is TerminateProcess() -- immediate, no chance for the target to
:: run its own cleanup code. pythonw has no window and no console, so there is
:: no gentler signal this script can send it that would actually be received;
:: /F is the only kill that works at all here. That means the bot's own
:: release_files() (its Python-side .pid/.lock cleanup, normally run from a
:: `finally` block) never executes on THIS path -- so this script deletes both
:: files itself instead of trusting the process it just force-killed to have
:: cleaned up after itself.
::
:: The PID file only exists for a bot launched with --managed
:: (discord_bot_start.bat) -- a bot started by hand writes none, and used to
:: be completely invisible to this script as a result: "no PID file --
:: nothing to stop" even while it kept running. That is a real gap (the
:: server's own shutdown should be able to actually stop every copy of this
:: bot, not just ones it personally launched), so this always ALSO sweeps for
:: any python/pythonw process actually running discord_status_bot.py by
:: command line, independent of the PID file entirely -- a self-reported PID
:: is not something this should have to trust to guarantee the bot is gone.
::
:: Pass "silent" as %1 (the game always does, via _discordBotCommand()) to
:: skip the trailing pause -- a human running this by hand gets to actually
:: read the output before the window disappears.

setlocal enabledelayedexpansion
set "ROOT=%~dp0.."
set "PIDFILE=%ROOT%\data\discord_status_bot.pid"
set "LOCKFILE=%ROOT%\data\discord_status_bot.lock"
set "STOPPED_ANY=0"

if exist "%PIDFILE%" (
    set /p BOTPID=<"%PIDFILE%"
    del /q "%PIDFILE%" >nul 2>&1
    if defined BOTPID (
        taskkill /F /PID %BOTPID% >nul 2>&1
        if not errorlevel 1 (
            echo discord_bot_stop: stopped PID %BOTPID% ^(from PID file^).
            set "STOPPED_ANY=1"
        )
    )
)
del /q "%LOCKFILE%" >nul 2>&1

:: Catch-all sweep -- finds the bot by command line regardless of whether it
:: was started with --managed, already handled above, or by hand. Filtered to
:: python.exe/pythonw.exe specifically so this can never match PowerShell's
:: own invocation (whose command line also contains the search text).
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'python.exe' -or $_.Name -eq 'pythonw.exe') -and $_.CommandLine -like '*discord_status_bot.py*' }).ProcessId" 2^>nul`) do (
    taskkill /F /PID %%P >nul 2>&1
    if not errorlevel 1 (
        echo discord_bot_stop: stopped PID %%P ^(found running, no/stale PID file^).
        set "STOPPED_ANY=1"
    )
)

if "%STOPPED_ANY%"=="0" (
    echo discord_bot_stop: nothing was running.
)

if /i not "%~1"=="silent" pause
exit /b 0
