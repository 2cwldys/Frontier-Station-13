@echo off
:: Backs up one shard's local database. See db_central_backup_shard.ps1 for
:: full docs. Forwards all arguments as-is,
:: e.g.: db_central_backup_shard.bat -ShardId frontier-shard-1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_central_backup_shard.ps1" %*
pause
