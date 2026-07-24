@echo off
:: Launches the standalone Idris Stock Exchange daemon (stock_market_daemon.py).
:: Requires: pip install pymysql psutil rich
cd /d "%~dp0"
where py >nul 2>nul
if %ERRORLEVEL%==0 (
	py -3 stock_market_daemon.py
) else (
	python stock_market_daemon.py
)
pause
