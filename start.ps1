# ============================================================
# SmartMeter ZW - Auto Startup Script
# Detects current IP, updates app config, starts Flask server
# ============================================================

$dartFile = "C:\SmartMeterZW\smartmeter_zw\lib\main.dart"
$htmlFile = "C:\SmartMeterZW\meter.html"
$serverFile = "C:\SmartMeterZW\server.py"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   SmartMeter ZW - Auto Startup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# -- Step 1: Detect current IP --------------------------------
Write-Host "[1/4] Detecting network IP address..." -ForegroundColor Yellow

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -notmatch "^127\." | Where-Object IPAddress -notmatch "^169\." | Select-Object -First 1).IPAddress

if (-not $ip) {
    Write-Host "  ERROR: No network IP found. Make sure you are connected to a network!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "  Found IP: $ip" -ForegroundColor Green

# -- Step 2: Update main.dart ---------------------------------
Write-Host ""
Write-Host "[2/4] Updating Flutter app BASE_URL..." -ForegroundColor Yellow

$dartContent = Get-Content $dartFile -Raw
$updatedDart = $dartContent -replace "const String BASE_URL = 'http://[^']+';", "const String BASE_URL = 'http://${ip}:5000';"

if ($dartContent -eq $updatedDart) {
    Write-Host "  WARNING: BASE_URL pattern not found in main.dart" -ForegroundColor DarkYellow
}
else {
    Set-Content $dartFile $updatedDart -NoNewline
    Write-Host "  main.dart updated -> http://${ip}:5000" -ForegroundColor Green
}

# -- Step 3: Update meter.html --------------------------------
Write-Host ""
Write-Host "[3/4] Updating meter.html BASE_URL..." -ForegroundColor Yellow

$htmlContent = Get-Content $htmlFile -Raw
$updatedHtml = $htmlContent -replace "const BASE_URL = 'http://[^']+';", "const BASE_URL = 'http://${ip}:5000';"

if ($htmlContent -eq $updatedHtml) {
    Write-Host "  WARNING: BASE_URL pattern not found in meter.html" -ForegroundColor DarkYellow
}
else {
    Set-Content $htmlFile $updatedHtml -NoNewline
    Write-Host "  meter.html updated -> http://${ip}:5000" -ForegroundColor Green
}

# -- Step 4: Start Flask server -------------------------------
Write-Host ""
Write-Host "[4/4] Starting Flask server on http://${ip}:5000 ..." -ForegroundColor Yellow
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Server IP    : $ip" -ForegroundColor White
Write-Host "  Flask URL    : http://${ip}:5000" -ForegroundColor White
Write-Host "  App file     : main.dart  [UPDATED]" -ForegroundColor White
Write-Host "  Simulator    : meter.html [UPDATED]" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "   1. Open meter.html in your browser" -ForegroundColor White
Write-Host "   2. In a NEW terminal, run:" -ForegroundColor White
Write-Host "      flutter run -d RZCY71PWM4K" -ForegroundColor Magenta
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Launch Flask (this blocks - keep this terminal open)
python $serverFile
