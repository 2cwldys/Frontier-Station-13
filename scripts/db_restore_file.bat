@echo off
:: Restore the Aurora database from a SPECIFIC .sql file, rather than from the
:: backups\ rotation that db_restore.bat lists. Use this for an archived dump,
:: a copy pulled aside before a risky test, or anything recovered from
:: elsewhere.
::
:: Drag a .sql file onto this script, or pass the path as an argument, or run it
:: with no arguments and it will ask.
::
:: STOP the game server before running this. The restore overwrites the current
:: aurora_persist database entirely.

setlocal

set "SQLPATH=%~1"

if "%SQLPATH%"=="" (
	echo.
	echo === AURORA DATABASE RESTORE ^(from file^) ===
	echo.
	echo Drop a .sql file onto this script, or type its full path below.
	echo.
	set /p "SQLPATH=Path to .sql file: "
)

:: Strip any surrounding quotes the shell or a drag-and-drop may have added --
:: the path is re-quoted on the way out, so a doubled pair would break it.
set "SQLPATH=%SQLPATH:"=%"

if "%SQLPATH%"=="" (
	echo No path given. Cancelled.
	pause
	exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_restore.ps1" -Path "%SQLPATH%"

endlocal
