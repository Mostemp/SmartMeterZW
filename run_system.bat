@echo off
title SmartMeter ZW Runner
echo ====================================================
echo Starting SmartMeter ZW Environment in D:\SmartMeterZW
echo ====================================================

cd /d "%~dp0"

echo [1/2] Checking Python and starting Flask backend...
start "SmartMeter Flask Server" cmd /k "python server.py"

echo [2/2] Opening meter simulation page...
start "" "http://localhost:5000"

echo.
echo ====================================================
echo Server started!
echo If you want to run the Flutter mobile app, run:
echo   cd /d D:\SmartMeterZW\smartmeter_zw
echo   flutter run
echo ====================================================
pause
