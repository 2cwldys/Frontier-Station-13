@echo off
:: First-time database setup — installs migrations and configures config files.
:: Requires Docker Desktop to be running.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0db_setup.ps1"
pause
