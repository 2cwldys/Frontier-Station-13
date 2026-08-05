@echo off
:: Launches deploy.ps1 detached in the background and returns immediately --
:: invoked by the in-game "Sync Deployment Branch" admin verb via
:: world.shelleo(), which blocks the whole game world for however long the
:: shelled-out command takes. A full recompile can take minutes, so this
:: only backgrounds the launch itself instead of waiting on it.
start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" >> "%~dp0deploy.log" 2>&1
