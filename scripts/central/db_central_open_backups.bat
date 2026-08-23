@echo off
:: Open a shard's backups folder in Windows Explorer (backups\shards\<ShardId>).
:: With no argument, opens backups\shards -- every shard's backups at once.
:: Usage: db_central_open_backups.bat [ShardId]
if "%~1"=="" (
	explorer "%~dp0..\..\backups\shards"
) else (
	explorer "%~dp0..\..\backups\shards\%~1"
)
