@echo off
:: Launches the Discord status bot detached and returns immediately -- invoked
:: from SSpersistence.Initialize() via world.shelleo(), which blocks the whole
:: game world for however long the shelled-out command takes. The bot runs
:: forever, so waiting on it would hang the server permanently at startup.
:: Same backgrounding trick deploy_bg.bat uses for the same reason.
::
:: Kills any previously-recorded bot first, so the process that ends up running
:: always matches the current script -- including an orphan left behind by a
:: DreamDaemon that died without running Shutdown().
::
:: That kill is taskkill /F -- see discord_bot_stop.bat's header for why that
:: means the OLD bot's own .pid/.lock cleanup never runs, and why this script
:: (like that one) deletes both files itself rather than trusting it to.
::
:: Pass "silent" as %1 (the game always does, via _discordBotCommand()) to
:: skip the trailing pause -- a human running this by hand gets to actually
:: read the output before the window disappears.

setlocal
set "ROOT=%~dp0.."
set "PIDFILE=%ROOT%\data\discord_status_bot.pid"
set "LOCKFILE=%ROOT%\data\discord_status_bot.lock"
set "CONFIG=%ROOT%\config\discord_status_bot.json"
set "LOG=%ROOT%\data\discord_status_bot.log"

:: Refuse rather than spawn a process that would only exit again a second
:: later -- an unconfigured server should launch nothing at all.
if not exist "%CONFIG%" (
    echo discord_bot_start: no config at "%CONFIG%" -- not starting.
    if /i not "%~1"=="silent" pause
    exit /b 1
)

:: Stop whatever was running before. A stale PID (process already gone) is
:: normal and must not fail the start.
if exist "%PIDFILE%" (
    set /p OLDPID=<"%PIDFILE%"
    if defined OLDPID (
        taskkill /F /PID %OLDPID% >nul 2>&1
    )
    del /q "%PIDFILE%" >nul 2>&1
    del /q "%LOCKFILE%" >nul 2>&1
)

if not exist "%ROOT%\data" mkdir "%ROOT%\data"

:: pythonw so no console window appears. --managed is what makes the bot write
:: the PID file and enable its self-exit watchdog -- i.e. what marks it as
:: server-owned and therefore reapable. A bot started by hand (running the .py
:: directly, without this flag) writes no PID file and is never touched by the
:: server. The bot also refuses to start if another instance already holds the
:: lock, so this cannot double up on one you started yourself.
start "" /B pythonw "%ROOT%\scripts\discord_status_bot.py" --managed >> "%LOG%" 2>&1
echo discord_bot_start: launch requested. Check "%LOG%" for whether it actually connected.
if /i not "%~1"=="silent" pause
exit /b 0
