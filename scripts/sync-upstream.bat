@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0sync-upstream.ps1" %*
pause
