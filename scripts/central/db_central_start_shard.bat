@echo off
:: Resumes an existing, stopped shard. See db_central_start_shard.ps1 for
:: full docs. Forwards all arguments as-is,
:: e.g.: db_central_start_shard.bat -ShardId frontier-shard-1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_start_shard.ps1" %*
pause
