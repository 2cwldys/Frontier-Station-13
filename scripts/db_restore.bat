@echo off
:: Restore the Aurora database from a selected backup.
:: Lists available backups by timestamp and prompts for selection.
:: STOP the game server before running this.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_restore.ps1"
