# Passenger App

`passenger_app` is the customer-facing Flutter app for creating and tracking water taxi bookings. It handles phone authentication, passenger registration, route selection, fare validation, booking creation, live booking tracking, and profile/history management.

The app is now refactored to repository + view model layers with Provider, and uses shared schema/models from `packages/water_taxi_shared`.

## Current Capabilities

### Authentication
- Firebase phone number sign-in with OTP verification.
- Registration flow for first-time users.
- Session-based routing through the auth wrapper.

### Booking flow
- Select pick-up and drop-off jetties from Firestore.
- Choose adult and child passenger counts.
- Validate route and fare availability before payment.
- Prevent duplicate bookings when the user already has an active booking.
- Authorize payment hold first, then create booking documents in Firestore.
- Use attempt-scoped idempotency keys to avoid stale PaymentIntent reuse on retries.
- Keep booking schema aligned with operator app via shared constants/models.

### Tracking and recovery
- Reopen the active booking directly from the home screen.
- Stream booking status updates from Firestore in real time.
- Support passenger cancellation for active bookings.
- Trigger backend release/refund path for cancelled and rejected bookings.
- Show booking history with live updates and filters.

### Notifications
- FCM token is registered at sign-in to `user_devices/{uid}` in Firestore.
- Cloud Functions push an FCM message to the passenger whenever the booking status changes.
- `PassengerNotificationCoordinator` streams booking status events and delivers local OS notifications when the app is in the background.
- Foreground booking events are shown as in-app alert cards via `LocalNotificationService`.
- Tapping an OS notification or FCM message navigates directly to the booking tracking screen for the relevant booking (deep-link tap navigation).

### Profile
- View and update account details.
- Access booking history from the profile area.
- Sign out from the app.

## Architecture

The app was reorganized from a flat `lib/` layout into feature-based modules.

```
lib/
|-- app.dart
|-- main.dart
|-- firebase_options.dart
|-- core/
|   |-- constants/
|   |-- theme/
|   |-- utils/
|   `-- widgets/
|-- features/
|   |-- auth/presentation/pages/
|   |-- home/presentation/pages/
|   `-- profile/presentation/pages/
|-- routes/
|   |-- app_routes.dart
|   `-- main_screen.dart
`-- services/
    |-- firebase/
    `-- notifications/
        |-- local_notification_service.dart
        `-- passenger_notification_coordinator.dart
```

The `functions/` folder at the root of this app contains the Cloud Functions backend for payment lifecycle, reconciliation, and FCM push notifications.

Key screens:

- `features/auth/presentation/pages/phone_login_page.dart`
- `features/auth/presentation/pages/registration_page.dart`
- `features/home/presentation/pages/home_screen.dart`
- `features/home/presentation/pages/payment_screen.dart`
- `features/home/presentation/pages/booking_tracking_screen.dart`
- `features/profile/presentation/pages/profile_screen.dart`

Key logic layers:

- `data/repositories/booking_repository.dart`
- `data/repositories/fare_repository.dart`
- `data/repositories/jetty_repository.dart`
- `data/repositories/user_repository.dart`
- `features/home/presentation/viewmodels/*.dart`
- `features/profile/presentation/viewmodels/profile_view_model.dart`

## Booking Data Model

The payment flow currently writes booking documents with fields used by both apps, including:

```text
bookingId
userId
userName
userPhone
origin
destination
originCoords
destinationCoords
adultCount
childCount
passengerCount
adultFare
childFare
adultSubtotal
childSubtotal
fare
totalFare
paymentMethod
paymentStatus
status
operatorId
createdAt
updatedAt
```

Notes:

- `operatorId` is the only assignment field used for booking ownership.
- `routeKey` is deprecated and no longer written by passenger booking creation.
- Booking creation expects hold-first payment state (`paymentStatus = authorized`).
- Backend reconciles stale `authorized` bookings on schedule to release or capture terminal bookings safely.

Current lifecycle states already handled in the passenger UI:

```text
pending
accepted
on_the_way
completed
cancelled
```

## Requirements

- Flutter SDK with Dart SDK `^3.8.1`.
- Firebase project configured for this app.
- Google Maps API key for the target platform.

Firebase services used:

- Firebase Core
- Firebase Authentication
- Cloud Firestore
- Firebase Cloud Messaging (FCM)
- Firebase Storage

Additional packages used:

- `firebase_messaging`
- `flutter_local_notifications`
- `google_maps_flutter`
- `geolocator`
- `provider`
- `water_taxi_shared` (local package)

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Configure Firebase

Required backend pieces:

- Phone Authentication enabled.
- Firestore collections for `users`, `bookings`, `fares`, and `jetties`.
- Valid generated `firebase_options.dart` and native Firebase config files.

This app also contains the current Firestore backend config files used by the workspace:

- `firestore.rules`
- `firestore.indexes.json`
- `firebase.json`

If you need to push the current rules and indexes to Firebase, run:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

The existing rules currently cover:

- owner-only access for `users/{uid}`
- owner-only create and update for `operators/{uid}` with `operator_id_claims/{operatorIdKey}` ownership checks
- signed-in read access for `jetties` and `fares`
- passenger booking creation restricted to the signed-in user with `status == pending`
- passenger cancellation for active bookings
- operator status transitions for `pending -> accepted -> on_the_way -> completed`

The current index file includes the fare lookup index used by route pricing queries. Additional booking-history and operator-queue indexes are still pending.

### 3. Configure Google Maps

For Android, set `MAPS_API_KEY` in `android/local.properties`:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```

Make sure the key restrictions match the Android package and SHA fingerprints used by your build.

### 4. Run the app

```bash
flutter run
```

## Development Notes

- `main.dart` initializes Firebase, enables Firestore offline persistence, and registers the FCM background message handler.
- `app.dart` routes authenticated users to the main shell and unauthenticated users to phone login.
- Home/payment/tracking/profile screens now delegate business logic to view models and repositories.
- Home screen booking is gated by route validity, passenger count, fare existence, and active-booking checks.
- Payment idempotency keys are attempt-scoped and amount-aware to reduce duplicate/invalid reuse errors.
- Top-of-screen in-app notifications are centralized in `core/widgets/top_alert.dart`.
- `LocalNotificationService` manages OS-level notifications and exposes a tap handler for deep-link routing.
- `PassengerNotificationCoordinator` seeds from the current booking snapshot and then diffs subsequent stream events to decide when to fire a notification.
- `main_screen.dart` handles all four FCM/local tap entry points (app terminated via FCM, app background via FCM, app terminated via local, app background via local) and navigates to the correct booking tracking screen.
- Firestore rules in this folder are shared backend infrastructure for both apps at the moment.

## Test Coverage Snapshot

Current automated coverage includes passenger view model tests for:

- home initialization and fare checks
- payment fare breakdown and booking commit params
- tracking stream updates and cancellation
- profile load/update and booking history streaming

Run from this folder:

```bash
flutter test test/viewmodels/passenger_viewmodels_test.dart
```

## Useful Commands

```bash
flutter analyze
flutter test
```

## Known Gaps

This app is not production-ready yet. Remaining work includes:

- payment observability dashboard and alert policy finalization
- richer passenger UX for reject/requeue/assignment delay scenarios
- stricter Firestore rules and indexes
- broader widget and integration test coverage (beyond current view model suite)
- Android and iOS release signing and build config verification

The live task tracker is in `TODO.md`.

## Future Planning: River Navigation Delivery (14 Jetties)

- Phased delivery is planned in `TODO.md` under "Cross-App Roadmap: River Navigation Delivery (14 Jetties)".
- Corridor data will be Firestore-backed with ordered checkpoints and read-only client policy.
- Operator MVP guidance target: progress, next checkpoint, remaining distance, and speed-based ETA.
- Passenger tracking requirement: after booking status becomes `on_the_way`, passenger should be able to track operator approach to pickup.

