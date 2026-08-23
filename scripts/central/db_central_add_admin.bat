@echo off
:: Add/update one ckey in the central admin roster (ss13_central_admins).
:: See db_central_add_admin.ps1 for full docs. Forwards all arguments as-is,
:: e.g.: db_central_add_admin.bat -Ckey someone -Rank "Head Admin" -Flags 32767
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_add_admin.ps1" %*
pause
