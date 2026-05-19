# Repository Guidelines

## Project Overview

SmartMeter ZW is a Flutter mobile app for monitoring a smart electricity prepaid meter, targeting Zimbabwe. The system has three components that work together:

- **`smartmeter_zw/`** — Flutter app (Android/iOS/desktop)
- **`server.py`** — Python Flask backend that simulates a real smart meter
- **`meter.html`** — Standalone HTML page that simulates the physical meter display (polls the Flask server every 5 s)

## Project Structure & Module Organization

The entire Flutter app lives in a single file: `smartmeter_zw/lib/main.dart` (~3000 lines). Screens are defined top-to-bottom in this order:

| Class | Role |
|---|---|
| `MeterStatus`, `AppNotification` | Data models |
| `SmartMeterApp` | App root / MaterialApp |
| `LoginScreen` | PIN entry (hardcoded PIN: `1234`) |
| `MainScreen` | Bottom-nav shell; owns the polling `Timer` |
| `DashboardPage` | Live status — balance, kW, voltage, tamper |
| `HistoryPage` | 7-day usage bar chart |
| `TopUpPage` | Recharge in USD or ZiG (Zimbabwe Gold) |
| `NotificationsPage` | In-memory notification log |
| `MeterDetailsPage` | Static meter info |
| `ChatbotPage` | Offline rule-based chatbot |
| `SettingsPage` | App preferences |

Global notification state is held in the top-level `List<AppNotification> globalNotifications`.

**Critical constant** — `BASE_URL` on line 12 of `main.dart` must match the Flask server's LAN IP:

```dart
const String BASE_URL = 'http://<HOST_IP>:5000';
```

`meter.html` contains a matching `const BASE_URL` that must also point to the same server.

## Build, Test, and Development Commands

### Startup (run once per session)

```powershell
powershell -ExecutionPolicy Bypass -File C:\SmartMeterZW\start.ps1
```

This script auto-detects the current LAN IP, patches `BASE_URL` in both `main.dart` and `meter.html`, then launches the Flask server. After it completes, open `meter.html` in a browser.

### Flutter app

```bash
flutter pub get                          # install dependencies
flutter run -d RZCY71PWM4K              # run on connected Android device
flutter run -d chrome                    # run as web app
flutter build apk                        # release APK
flutter analyze                          # static analysis / lint
flutter test                             # run tests
```

### Flask server (manual)

```bash
pip install flask flask-cors
python C:\SmartMeterZW\server.py        # starts on 0.0.0.0:5000
```

## API Contract

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/status` | Balance, consumption kW, voltage, tamper flag, status |
| GET | `/api/history` | 7-day usage array |
| POST | `/api/topup/<amount>` | Top up in USD (`1 unit = $0.35`) |
| POST | `/api/topup_zig/<amount>` | Top up in ZiG (`1 unit = 8.75 ZiG`) |
| POST | `/api/tamper` | Trigger tamper alert (visible for 8 s) |

## Coding Style & Naming Conventions

- Linter: `flutter_lints` (`package:flutter_lints/flutter.yaml`) via `analysis_options.yaml`; run with `flutter analyze`
- Dart SDK constraint: `^3.11.5`
- Global color constants defined at the top of `main.dart`: `kGreen`, `kBg`, `kCard`, `kEcoGreen`
- `StatefulWidget` / `State` pairs follow the `_WidgetNameState` naming convention
- No separate state-management library — state is local (`setState`) with a shared global list for notifications

## Testing Guidelines

- Framework: `flutter_test` (built-in)
- Test file: `smartmeter_zw/test/widget_test.dart`
- Run: `flutter test`
- Note: the existing widget test references `MyApp` (a placeholder) and will fail; write tests against the actual `SmartMeterApp` entry point.
