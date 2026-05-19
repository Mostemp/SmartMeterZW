@echo off 
echo Starting SmartMeter ZW... 
netsh advfirewall set privateprofile state off 
netsh advfirewall set publicprofile state off 
start "" python C:\SmartMeterZW\server.py 
echo Server started at 192.168.137.1:5000 
pause 
