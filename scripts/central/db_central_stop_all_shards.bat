@echo off
:: Stops every currently-running shard. See db_central_stop_all_shards.ps1
:: for full docs.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_stop_all_shards.ps1"
pause
