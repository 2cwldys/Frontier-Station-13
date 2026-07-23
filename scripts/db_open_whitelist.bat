@echo off
:: Open the join whitelist (ss13_join_whitelist) from the database --
:: shows current entries, then drops into a live session to view or edit it.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_open_whitelist.ps1"
pause
