@echo off
:: Disable the daily auto-backup scheduled task (existing backups are kept).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_unschedule_backups.ps1"
pause
