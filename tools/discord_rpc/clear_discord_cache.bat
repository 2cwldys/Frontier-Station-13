@echo off
title Frontier Station 13 Rich Presence - Clear Discord Cache
echo This will:
echo   1. Close Discord (if running)
echo   2. Clear its local image/asset cache folders
echo   3. Reopen Discord
echo.
echo Your login, settings, servers, and messages are untouched -- only
echo cached images/assets get cleared. Discord rebuilds these
echo automatically on next launch. This is the same fix Discord's own
echo support recommends for "an image/icon isn't updating" issues.
echo.
pause

echo.
echo Closing Discord...
taskkill /IM Discord.exe /F >nul 2>&1
timeout /t 2 /nobreak >nul

set "DISCORD_DIR=%APPDATA%\discord"

if not exist "%DISCORD_DIR%" (
    echo Could not find %DISCORD_DIR% -- is Discord installed for this user account?
    pause
    exit /b 1
)

if exist "%DISCORD_DIR%\Cache" (
    echo Clearing Cache...
    rmdir /S /Q "%DISCORD_DIR%\Cache"
)
if exist "%DISCORD_DIR%\Code Cache" (
    echo Clearing Code Cache...
    rmdir /S /Q "%DISCORD_DIR%\Code Cache"
)
if exist "%DISCORD_DIR%\GPUCache" (
    echo Clearing GPUCache...
    rmdir /S /Q "%DISCORD_DIR%\GPUCache"
)
if exist "%DISCORD_DIR%\DawnCache" (
    echo Clearing DawnCache...
    rmdir /S /Q "%DISCORD_DIR%\DawnCache"
)

echo.
echo Reopening Discord...
start "" "%LOCALAPPDATA%\Discord\Update.exe" --processStart Discord.exe

echo.
echo Done. Give Discord a moment to fully restart before checking Rich Presence again.
pause
