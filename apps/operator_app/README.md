# Operator App

`operator_app` is the operator-facing Flutter app for handling the supply side of the water taxi platform. It manages operator authentication, profile bootstrap, online availability, current-location map behavior, and booking lifecycle transitions.

The app is now refactored to a repository + view model architecture with Provider, and uses shared domain/types from `packages/water_taxi_shared`.

## Current Capabilities

### Authentication and profile
- Firebase email/password sign-in.
- Operator profile bootstrap in Firestore under `operators/{uid}`.
- Profile edit flow for operator name and operator ID.

### Operations dashboard
- Online/offline toggle synced to Firestore.
- Google Map with current-location bootstrap and recenter behavior.
- Booking action flow for:
  - `pending -> pending` (reject via `rejectedBy[]`)
  - `pending -> accepted`
  - `accepted -> on_the_way`
  - `on_the_way -> completed`
- Shared top-card notifications for welcome, info, success, offline, and error states.

### Operator workflow status
- Shows active assigned booking when one exists.
- Falls back to the pending booking queue when the operator has no active booking.
- Reacts to Firestore updates in real time.

## Architecture

The app now mirrors the passenger app structure.

```
lib/
├── app.dart
├── main.dart
├── firebase_options.dart
├── core/
│   ├── constants/
│   ├── theme/
│   └── widgets/
├── features/
│   ├── auth/presentation/pages/
│   ├── home/presentation/pages/
│   └── profile/presentation/pages/
└── routes/
    ├── app_routes.dart
    └── main_screen.dart
```

Key screens:

- `features/auth/presentation/pages/operator_login_page.dart`
- `features/auth/presentation/pages/operator_profile_setup_page.dart`
- `features/home/presentation/pages/operator_home_screen.dart`
- `features/profile/presentation/pages/operator_profile_page.dart`

Key logic layers:

- `data/repositories/booking_repository.dart`
- `data/repositories/operator_repository.dart`
- `features/home/presentation/viewmodels/operator_home_view_model.dart`

## Firestore Data Expectations

### Operators collection

```text
operators/{uid}
name
operatorId
email
isOnline
createdAt
updatedAt
```

### Bookings collection usage

This app reads shared booking documents created by the passenger app and currently depends on:

```text
status
driverId
origin
destination
passengerCount
fare or totalFare
createdAt
updatedAt
```

## Requirements

- Flutter SDK with Dart SDK `^3.8.1`.
- Firebase project configured for operator auth and Firestore.
- Android Maps API key and valid package/SHA restrictions.
- Device or emulator with location services enabled for map features.

Packages used in this app include:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `google_maps_flutter`
- `geolocator`
- `permission_handler`
- `provider`
- `water_taxi_shared` (local package)

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Configure Firebase

Required backend pieces:

- Email/password Authentication enabled.
- Firestore collection for `operators`.
- Native Firebase config files for the target platform.

This app shares the same Firebase project as `passenger_app`. The current Firestore rules and indexes are stored and deployed from `../passenger_app/`:

- `../passenger_app/firestore.rules`
- `../passenger_app/firestore.indexes.json`
- `../passenger_app/firebase.json`

That means operator booking permissions currently come from the shared rules defined there, not from a separate operator-specific Firestore config file.

The current rules already allow operators to:

- read bookings
- accept an unclaimed pending booking
- start a trip on their assigned booking
- complete a trip on their assigned booking

To deploy the shared Firestore config used by this app:

```bash
cd ../passenger_app
firebase deploy --only firestore:rules,firestore:indexes
```

### 3. Configure Google Maps on Android

Set `MAPS_API_KEY` in `android/local.properties`:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```

The Android build injects this key into the manifest. If map tiles do not load, verify:

- the key exists in `android/local.properties`
- the Android package name matches the API key restrictions
- the SHA fingerprints used by the running build are registered in Google Cloud and Firebase

### 4. Run the app

```bash
flutter run
```

## Development Notes

- `app.dart` routes signed-out users to login, new users to profile setup, and ready operators to the main shell.
- `operator_home_screen.dart` is UI-focused and delegates lifecycle actions/state to `OperatorHomeViewModel`.
- A small Android method channel is present to help diagnose whether the Maps API key was injected into the manifest at runtime.
- Shared in-app notification cards live in `core/widgets/top_alert.dart`.
- The home screen includes small test hooks (`testOperatorId`, `testOperatorEmail`, map builder override, runtime-check skip) used by widget tests to avoid platform-view instability.

## Test Coverage Snapshot

Current automated coverage includes:

- View model tests for initialization, filters, busy guard, timeout rollback, refresh, and helper formatting.
- Widget tests for:
  - signed-out fallback
  - signed-in offline/online state
  - pending queue expansion + accept action
  - active trip expansion + start/complete action delegation

Run from this folder:

```bash
flutter test test/viewmodels/operator_home_view_model_test.dart test/features/home/operator_home_screen_test.dart
```

## Useful Commands

```bash
flutter analyze
flutter test
```

## Known Gaps

This app is functionally stable for core operator flow but not production-ready. Open work includes:

- cross-app integration/E2E lifecycle tests with passenger app
- stronger observability/logging for transition failures
- hardened Firestore rule/index validation in production-like environments
- queue UX polish under heavy concurrent demand

The current task tracker is in `TODO.md`.
