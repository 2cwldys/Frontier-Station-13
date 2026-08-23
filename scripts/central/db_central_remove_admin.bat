@echo off
:: Remove one ckey from the central admin roster (ss13_central_admins).
:: See db_central_remove_admin.ps1 for full docs. Forwards all arguments as-is,
:: e.g.: db_central_remove_admin.bat -Ckey someone
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_remove_admin.ps1" %*
pause
