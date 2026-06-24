@echo off
:: Start the Aurora MariaDB container.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_start.ps1"
pause
