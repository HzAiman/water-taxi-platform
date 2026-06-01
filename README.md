# Water Taxi Platform

Water Taxi Platform is a Flutter workspace with two client applications, a shared Dart package, and a Firebase backend. The system keeps passenger and operator flows aligned on a single Firestore lifecycle contract while allowing each app to evolve independently.

## Workspace layout

```
water-taxi-platform/
|-- apps/
|   |-- passenger_app/
|   |   `-- functions/   # Cloud Functions backend (payments, pooling, notifications)
|   `-- operator_app/
|-- packages/
|   `-- water_taxi_shared/
|-- docs/
`-- README.md
```

## Apps and packages

- apps/passenger_app: Phone auth, booking creation, hold-first Stripe payment, live tracking, FCM/local notifications, booking history.
- apps/operator_app: Operator auth, profile bootstrap, online availability, pooled queue handling, navigation guidance, live location sharing, FCM/local notifications, earnings summary.
- packages/water_taxi_shared: Firestore field constants, typed models, booking status enum, and shared operation result types.
- apps/passenger_app/functions: Gen 2 Cloud Functions for pooling/dispatch, payment lifecycle, and push notifications.

## Lifecycle contract

Booking status lifecycle (shared by both apps):

```
pending -> accepted -> on_the_way -> completed
pending/accepted/on_the_way -> cancelled
pending -> rejected
```

Payment lifecycle (manual capture):

```
authorized -> paid (capture on completed)
authorized -> cancelled/refunded (cancel/reject/reconcile)
```

Key rules:

- Rejections are tracked in rejectedBy[]; the booking remains pending until all online operators have declined it.
- Passenger name/phone are stored as immutable snapshots for receipts and historical integrity.
- High-frequency GPS updates live in tracking/{bookingId}; bookings store low-frequency snapshots.

## Real-time data flow

- bookings/{id} is the canonical lifecycle record (status, fare, assignment, pooling fields).
- tracking/{id} contains live operator coordinates while a trip is on_the_way.
- polylines/{id} stores route geometry; passengers embed a chosen route polyline at booking time.
- user_devices/{uid} and operator_devices/{uid} store FCM tokens; operator_presence/{uid} controls online dispatch eligibility.

Passenger tracking merges booking + tracking streams to show real-time operator movement and route geometry.

## Tech stack

- Flutter + Dart
- Firebase Auth, Firestore, FCM
- Cloud Functions (Node.js 22, Gen 2, region asia-southeast1)
- Stripe (manual capture PaymentIntent flow)
- Google Maps Flutter + Geolocator
- Provider state management

## Setup (condensed)

Prerequisites:

- Flutter SDK and Android/iOS toolchains.
- Firebase project with Auth, Firestore, FCM enabled.
- Stripe account with API keys.

Firestore rules and indexes live in apps/passenger_app. Deploy them from that folder:

```bash
cd apps/passenger_app
firebase deploy --only firestore:rules,firestore:indexes
```

Maps API key:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```

Stripe client config (passenger app uses dart-define values):

- STRIPE_PUBLISHABLE_KEY
- STRIPE_MERCHANT_IDENTIFIER (iOS)
- STRIPE_URL_SCHEME
- STRIPE_MERCHANT_DISPLAY_NAME
- STRIPE_RETURN_URL
- STRIPE_PAYMENT_INTENT_ENDPOINT

## Running

```bash
cd apps/passenger_app
flutter run

cd ../operator_app
flutter run
```

## Documentation map

- docs/drt_algorithm_reference.md: Pooling, route-aware sequencing, stop planning, and operator presence safety behavior.
- docs/firestore_schema_inventory.md: Firestore schema inventory refreshed from live observed samples only.
- docs/push_notifications_features.md: Passenger/operator push, local notification, foreground alert, tap handling, and trigger matrix.
- docs/passenger_app_features.md: Passenger-facing feature reference.
- docs/operator_app_features.md: Operator-facing feature reference.
- apps/passenger_app/README.md: Passenger app architecture + flows.
- apps/operator_app/README.md: Operator app architecture + flows.
- apps/passenger_app/functions/README.md: Cloud Functions details.

## Status

Core flows are implemented end-to-end: booking creation, manual-capture payment, pooled dispatch, operator navigation, and push notifications. Remaining work focuses on production hardening: monitoring/alerting, stricter Firestore rules/index coverage, and full E2E test automation.

