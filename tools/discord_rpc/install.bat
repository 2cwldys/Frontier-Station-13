@echo off
title Frontier Station 13 Rich Presence - Install/Update
cd /d "%~dp0"
echo Installing/updating dependencies...
echo.

python -m pip install --upgrade -r requirements.txt

if errorlevel 1 (
    echo.
    echo Something went wrong. Make sure Python is installed and on PATH,
    echo then check the error above.
    pause
    exit /b 1
)

echo.
echo Done. Run run.bat to start it.
pause
