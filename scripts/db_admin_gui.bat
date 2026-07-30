@echo off
:: Launches the standalone DB admin GUI (db_admin_gui.py).
:: Requires: pip install pymysql psutil
cd /d "%~dp0"
where py >nul 2>nul
if %ERRORLEVEL%==0 (
	py -3 db_admin_gui.py
) else (
	python db_admin_gui.py
)
pause
