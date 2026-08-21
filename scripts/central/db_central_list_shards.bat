@echo off
:: Lists every registered shard alongside its live Docker status. See
:: db_central_list_shards.ps1 for full docs.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_list_shards.ps1"
pause
