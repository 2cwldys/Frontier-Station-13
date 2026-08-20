@echo off
:: Pauses a running shard. See db_central_stop_shard.ps1 for full docs.
:: Forwards all arguments as-is, e.g.: db_central_stop_shard.bat -ShardId frontier-shard-1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_stop_shard.ps1" %*
pause
