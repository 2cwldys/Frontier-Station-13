@echo off
:: Dump the Aurora database to backups\ (keeps last 7).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_backup.ps1"
pause
