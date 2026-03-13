# Passenger App

`passenger_app` is the customer-facing Flutter app for creating and tracking water taxi bookings. It handles phone authentication, passenger registration, route selection, fare validation, booking creation, live booking tracking, and profile/history management.

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
- Create booking documents in Firestore during the payment flow.

### Tracking and recovery
- Reopen the active booking directly from the home screen.
- Stream booking status updates from Firestore in real time.
- Support passenger cancellation for active bookings.
- Show booking history with live updates and filters.

### Profile
- View and update account details.
- Access booking history from the profile area.
- Sign out from the app.

## Architecture

The app was reorganized from a flat `lib/` layout into feature-based modules.

```
lib/
├── app.dart
├── main.dart
├── firebase_options.dart
├── core/
│   ├── constants/
│   ├── theme/
│   ├── utils/
│   └── widgets/
├── features/
│   ├── auth/presentation/pages/
│   ├── home/presentation/pages/
│   └── profile/presentation/pages/
├── routes/
│   ├── app_routes.dart
│   └── main_screen.dart
└── services/
    └── firebase/
```

Key screens:

- `features/auth/presentation/pages/phone_login_page.dart`
- `features/auth/presentation/pages/registration_page.dart`
- `features/home/presentation/pages/home_screen.dart`
- `features/home/presentation/pages/payment_screen.dart`
- `features/home/presentation/pages/booking_tracking_screen.dart`
- `features/profile/presentation/pages/profile_screen.dart`

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
driverId
createdAt
updatedAt
```

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
- Firebase Storage

Additional packages used:

- `google_maps_flutter`
- `geolocator`

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
- owner-only create and update for `operators/{uid}`
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

- `main.dart` initializes Firebase and enables Firestore offline persistence.
- `app.dart` routes authenticated users to the main shell and unauthenticated users to phone login.
- Home screen booking is gated by route validity, passenger count, fare existence, and active-booking checks.
- Top-of-screen in-app notifications are centralized in `core/widgets/top_alert.dart`.
- Firestore rules in this folder are shared backend infrastructure for both apps at the moment.

## Useful Commands

```bash
flutter analyze
flutter test
```

## Known Gaps

This app is not production-ready yet. Remaining work includes:

- payment reliability and idempotency hardening
- final handling for operator rejection or reassignment
- stricter Firestore rules and indexes
- broader widget and integration test coverage

The live task tracker is in `TODO.md`.
