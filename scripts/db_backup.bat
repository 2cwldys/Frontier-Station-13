@echo off
:: Dump the Aurora database to backups\ (keeps last 7).
:: No pause at the end -- this is invoked non-interactively from the game
:: server (persistence_backups.dm's trigger_database_backup() admin verb,
:: via world.shelleo()), which can never satisfy a "press any key" prompt --
:: it would just hang the shell() call forever and never report a result.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_backup.ps1"
