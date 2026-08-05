@echo off
:: Enable the daily auto-backup scheduled task for an already-set-up DB.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_schedule_backups.ps1"
pause
