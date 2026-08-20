@echo off
:: List everyone currently in the central admin roster (ss13_central_admins).
:: Read-only. See db_central_list_admins.ps1 for full docs.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_list_admins.ps1"
pause
