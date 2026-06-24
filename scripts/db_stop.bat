@echo off
:: Stop the Aurora MariaDB container (data is preserved).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_stop.ps1"
pause
