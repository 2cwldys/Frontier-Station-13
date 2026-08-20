@echo off
:: Creates a new local game-server shard. See db_central_add_shard.ps1 for
:: full docs. Forwards all arguments as-is,
:: e.g.: db_central_add_shard.bat -ShardId frontier-shard-1 -Port <port>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_add_shard.ps1" %*
pause
