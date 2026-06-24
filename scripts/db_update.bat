@echo off
:: Apply pending database schema updates.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_update.ps1"
pause
