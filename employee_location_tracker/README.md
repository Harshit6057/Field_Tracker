# Office Employee Location Tracker (Flutter)

Professional mobile app for employee attendance and route tracking with separate employee/admin workflows.

## Key Features

- Employee check-in and check-out flow
- Live employee location updates
- Full in-shift route polyline on map
- Admin dashboard with all employees and status badges
- Online/offline visibility for each employee
- Android and iOS support

## Tech Stack

- Flutter (Android + iOS)
- Riverpod state management
- Geolocator + Connectivity Plus
- Google Maps Flutter
- Optional Firebase dependencies included for production integration

## Demo Credentials (Mock Mode)

- Admin passcode: `admin123`
- Sample employee IDs: `EMP001`, `EMP002`
- Any employee name can be used at login

## Setup

1. Install dependencies:

	```bash
	flutter pub get
	```

2. Add Google Maps API key:

	- Android: update `android/app/src/main/AndroidManifest.xml`
	- iOS: update `ios/Runner/Info.plist` key `GoogleMapsApiKey`

3. Run the app:

	```bash
	flutter run
	```

## Production Notes

- `lib/core/app_config.dart` uses `useMockBackend = true` for demo mode.
- Switch to `false` and replace repository wiring in `lib/providers/tracking_provider.dart` with your Firebase implementation.
- Firebase packages are already added in `pubspec.yaml` for production expansion.

## Required Mobile Permissions

- Android: fine/coarse/background location + foreground service
- iOS: when-in-use and always location usage descriptions + background location mode
