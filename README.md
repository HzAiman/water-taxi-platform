# Water Taxi Platform

Water Taxi Platform is a Flutter workspace with two client applications backed by Firebase, plus a shared Dart package for booking schema and domain models:

- `apps/passenger_app`: passenger booking, payment handoff, live booking tracking, and booking history.
- `apps/operator_app`: operator authentication, availability, live booking queue handling, and trip status updates.
- `packages/water_taxi_shared`: shared constants, lifecycle enums, typed models, and operation result utilities.

The codebase is organized around one cross-app goal: keep passenger and operator flows aligned on a single Firestore lifecycle contract while allowing separate UX.

## Workspace Overview

```
water-taxi-platform/
|-- apps/
|   |-- passenger_app/
|   |   `-- functions/   # Cloud Functions backend (push notifications)
|   `-- operator_app/
|-- packages/
|   `-- water_taxi_shared/
`-- README.md
```

Each app is a standalone Flutter project with its own Firebase config and feature-based `lib/` structure. Shared schema and model types are centralized in `water_taxi_shared` to avoid drift.

## Current Product Scope

### Passenger app
- Phone number authentication with registration for new users.
- Jetty-to-jetty booking flow with fare precheck.
- Payment step that writes booking documents to Firestore.
- Live tracking screen that reacts to booking status updates.
- Current-booking resume card on the home screen.
- Booking history and account management in profile.
- Refactored UI logic into repositories + view models using Provider.
- Push notifications (FCM) for booking status changes (accepted, on the way, completed, cancelled).
- Background local notifications when the app is minimised.
- Notification tap deep-link navigation directly to the booking tracking screen.

### Operator app
- Email/password authentication.
- Operator profile bootstrap under `operators/{uid}`.
- Transactional operator ID uniqueness enforcement via `operator_id_claims/{operatorIdKey}`.
- Online/offline availability toggle.
- Booking workflow: reject, accept, start trip, complete trip.
- Operator map with current-location support.
- Profile management and shared top-card notifications.
- Refactored UI logic into repositories + view models using Provider.
- Push notifications (FCM) for incoming passenger bookings.
- Background local notifications and persistent online-status reminder.
- Notification tap deep-link navigation to the booking home tab.

## Booking Lifecycle

Both apps depend on the same booking status contract:

```text
pending -> accepted -> on_the_way -> completed
```

Passenger cancellation is also supported:

```text
pending/accepted/on_the_way -> cancelled
```

Reject and dispatch behavior are implemented using `pending + rejectedBy[]`: the booking stays `pending` when an operator rejects it so that another operator can claim it. The full `BookingStatus` enum also covers `rejected` and `unknown` for edge-case handling.

Remaining lifecycle hardening work is tracked in app TODO files:

- `apps/passenger_app/TODO.md`
- `apps/operator_app/TODO.md`

River navigation future planning (14 jetties corridor) is also tracked in both TODO files under "Cross-App Roadmap: River Navigation Delivery (14 Jetties)".

## Tech Stack

- Flutter and Dart
- Firebase Authentication
- Cloud Firestore
- Firebase Cloud Messaging (FCM)
- Cloud Functions for Firebase (Node.js 20, Gen 2, region `asia-southeast1`)
- `flutter_local_notifications` (in-app and OS-level notifications)
- Google Maps Flutter
- Geolocator / permission handling where needed
- Provider (state management)
- Shared pure Dart package for schema/models (`water_taxi_shared`)

## Setup

### Prerequisites
- Flutter SDK with Dart SDK matching the app constraints.
- A Firebase project configured for both apps.
- Android Studio or VS Code with Flutter tooling.
- Platform toolchains for the targets you plan to run.

### Firebase requirements
- Passenger app:
    - Phone Authentication enabled.
    - Firestore collections for users, bookings, fares, and jetties.
- Operator app:
    - Email/password Authentication enabled.
    - Firestore collection for operators.

### Firestore rules and indexes

The current Firestore configuration files live in `apps/passenger_app/`:

- `firestore.rules`
- `firestore.indexes.json`
- `firebase.json`

At the moment, that folder is the backend configuration source of truth for both apps because both clients point to the same Firebase project.

Current rules already enforce these core behaviors:

- users can only read and write their own `users/{uid}` document
- operators can only read and update their own `operators/{uid}` document
- operator profile writes must hold ownership of `operator_id_claims/{operatorIdKey}`
- signed-in users can read `jetties` and `fares`
- passengers can create their own `pending` bookings with `paymentStatus == authorized`
- passengers can cancel their own active bookings
- operators can transition bookings through `accepted`, `on_the_way`, and `completed`
- passengers can write their own FCM token to `user_devices/{uid}`
- operators can write their own FCM token to `operator_devices/{uid}`
- operators can read `operator_presence/{uid}` (used by Cloud Functions to target online operators)

The current index file only defines the fare lookup index for `origin + destination`. More booking and operator queue indexes are still tracked as open work.

To deploy the existing Firestore configuration:

```bash
cd apps/passenger_app
firebase deploy --only firestore:rules,firestore:indexes
```

### Install dependencies

```bash
cd apps/passenger_app
flutter pub get

cd ../operator_app
flutter pub get
```

### Google Maps

Both apps use Google Maps. Android builds expect a `MAPS_API_KEY` entry in each app's `android/local.properties`.

Example:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```

You also need the corresponding Android package/SHA restrictions configured in Google Cloud.

## Running the Apps

From each app directory:

```bash
flutter run
```

Common examples:

```bash
cd apps/passenger_app
flutter run -d android

cd ../operator_app
flutter run -d android
```

## Quality Checks

Run these from an app directory:

```bash
flutter analyze
flutter test
```

Recent verification highlights:

- Passenger view model tests added and passing.
- Operator view model tests added and passing.
- Operator home widget tests added for signed-out and signed-in action flows (including accept/start/complete delegation) and passing.

## Documentation Map

- `apps/passenger_app/README.md`: passenger app architecture, flows, and setup.
- `apps/operator_app/README.md`: operator app architecture, flows, and setup.
- `apps/passenger_app/functions/README.md`: Cloud Functions setup, triggers, and deployment.
- `apps/passenger_app/firestore.rules`: current shared Firestore access rules.
- `apps/passenger_app/firestore.indexes.json`: current Firestore indexes.
- `apps/passenger_app/TODO.md`: remaining passenger-side work.
- `apps/operator_app/TODO.md`: remaining operator-side work.

## Status

Core flows are implemented and refactored away from UI-embedded business logic. The full push notification pipeline is live: FCM token registration, two deployed Cloud Functions (Gen 2, `asia-southeast1`), in-app foreground alerts, background OS notifications, and notification tap deep-link navigation in both apps.

The workspace is still not production-ready. Main unfinished areas are payment reliability, operator ID governance monitoring, runtime/dependency upgrades for functions, and full end-to-end integration testing across both apps.

