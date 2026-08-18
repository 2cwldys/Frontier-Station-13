@echo off
:: Stops the Discord status bot, using the PID the bot recorded itself.
:: Invoked from SSpersistence.Shutdown() via world.shelleo() when the server is
:: genuinely closing (not on a soft round reboot -- see the hard-reset guard
:: there), so the bot does not outlive the server it reports on.
::
:: Being asked to stop an already-stopped bot is a normal outcome, not an
:: error: exits 0 whether it killed anything or found nothing to kill.

setlocal
set "ROOT=%~dp0.."
set "PIDFILE=%ROOT%\data\discord_status_bot.pid"

if not exist "%PIDFILE%" (
    echo discord_bot_stop: no PID file -- nothing to stop.
    exit /b 0
)

set /p BOTPID=<"%PIDFILE%"
del /q "%PIDFILE%" >nul 2>&1

if not defined BOTPID (
    echo discord_bot_stop: empty PID file -- nothing to stop.
    exit /b 0
)

:: A stale PID whose process is already gone is expected after a crash --
:: swallow taskkill's complaint rather than reporting a failure.
taskkill /F /PID %BOTPID% >nul 2>&1
if errorlevel 1 (
    echo discord_bot_stop: PID %BOTPID% was not running.
) else (
    echo discord_bot_stop: stopped PID %BOTPID%.
)
exit /b 0
