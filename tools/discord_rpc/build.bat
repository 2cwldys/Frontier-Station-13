@echo off
REM Builds the single-file FrontierRPC.exe players are given.
REM
REM Output lands in dist\FrontierRPC.exe -- that one file is the whole
REM distributable. It needs no Python, no .env and no folder alongside it:
REM config.py carries built-in defaults for the public server, and a .env is
REM only read if one happens to sit next to the exe (hosts/testers).
REM
REM --noconsole keeps it silent in the background, which is the point -- a
REM player launches it once and never sees it again. Use build-debug.bat
REM behaviour (drop --noconsole) if you need to watch its log output.

title Build Frontier Station 13 Rich Presence
cd /d "%~dp0"

echo Installing/updating build dependencies...
python -m pip install -r requirements.txt pyinstaller
if errorlevel 1 goto :failed

REM The server address lives only in .env (gitignored, never committed), so it
REM has to be baked into the build or the shipped exe won't know where to
REM connect. A player's copy therefore needs no .env of its own.
if not exist ".env" (
    echo.
    echo ERROR: no .env found.
    echo Copy .env.example to .env and fill in SERVER_ADDR / SERVER_PORT first --
    echo the built exe needs them baked in, since they aren't stored in source.
    goto :failed
)

echo.
echo Building FrontierRPC.exe...
python -m PyInstaller ^
    --onefile ^
    --noconsole ^
    --name FrontierRPC ^
    --icon assets\app_icon.ico ^
    --add-data "assets;assets" ^
    --add-data ".env;." ^
    main.py
if errorlevel 1 goto :failed

echo.
echo Done. Distributable is: dist\FrontierRPC.exe
echo Hand players that single file -- nothing else is needed.
goto :end

:failed
echo.
echo BUILD FAILED -- see the error above.

:end
echo.
pause >nul
