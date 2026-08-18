@echo off
:: Stops the Discord status bot, using the PID the bot recorded itself.
:: Invoked from SSpersistence.Shutdown() via world.shelleo() when the server is
:: genuinely closing (not on a soft round reboot -- see the hard-reset guard
:: there), so the bot does not outlive the server it reports on.
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
:: cleaned up after itself. It already deleted the PID file below the OLD way;
:: doing the lock file too closes the one file that was never actually anyone's
:: job before.
::
:: Pass "silent" as %1 (the game always does, via _discordBotCommand()) to
:: skip the trailing pause -- a human running this by hand gets to actually
:: read the output before the window disappears.

setlocal
set "ROOT=%~dp0.."
set "PIDFILE=%ROOT%\data\discord_status_bot.pid"
set "LOCKFILE=%ROOT%\data\discord_status_bot.lock"

if not exist "%PIDFILE%" (
    echo discord_bot_stop: no PID file -- nothing to stop.
    del /q "%LOCKFILE%" >nul 2>&1
    goto :end
)

set /p BOTPID=<"%PIDFILE%"
del /q "%PIDFILE%" >nul 2>&1

if not defined BOTPID (
    echo discord_bot_stop: empty PID file -- nothing to stop.
    del /q "%LOCKFILE%" >nul 2>&1
    goto :end
)

:: taskkill's own message is let through rather than swallowed -- "not found"
:: (stale PID, expected after a crash) and "Access is denied" (a REAL problem
:: worth seeing) previously both collapsed into the same generic "was not
:: running" line, which is indistinguishable from a genuine failure.
taskkill /F /PID %BOTPID%
if errorlevel 1 (
    echo discord_bot_stop: taskkill could not stop PID %BOTPID% -- see the message above ^(a stale/already-dead PID is normal; anything else is not^).
) else (
    echo discord_bot_stop: stopped PID %BOTPID%.
)
del /q "%LOCKFILE%" >nul 2>&1

:end
if /i not "%~1"=="silent" pause
exit /b 0