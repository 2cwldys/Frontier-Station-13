@echo off
:: Thin launcher for cleanup_shelleo_zombies.ps1 -- lets it be double-clicked
:: or scheduled without anyone needing to remember PowerShell's execution
:: policy incantation. See that script's own header for what this actually
:: does and why it's needed (hung shelleo() child processes, code/__HELPERS/shell.dm).
::
:: Pass -WhatIf to preview without killing/deleting anything:
::   cleanup_shelleo_zombies.bat -WhatIf

setlocal
set "ROOT=%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup_shelleo_zombies.ps1" %*
echo.
pause
