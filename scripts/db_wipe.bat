@echo off
:: Wipe all persistence data (character saves, world state, economy, etc.)
:: The schema is preserved -- only row data is deleted.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_wipe.ps1"
pause
