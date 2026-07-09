@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0debug-compile.ps1" %*
pause
