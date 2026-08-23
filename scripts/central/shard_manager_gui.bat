@echo off
:: Launches the standalone shard manager GUI (shard_manager_gui.py).
:: Requires: pip install pymysql
cd /d "%~dp0"
where py >nul 2>nul
if %ERRORLEVEL%==0 (
	py -3 shard_manager_gui.py
) else (
	python shard_manager_gui.py
)
pause
