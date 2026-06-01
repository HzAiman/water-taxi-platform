# Operator App

operator_app is the operator-facing Flutter app for handling supply-side workflows: operator authentication, profile bootstrap, online availability, pooled booking queue management, navigation guidance, and earnings statements.

The app uses repository + view model layers (Provider) and shared schema/models from packages/water_taxi_shared.

## Architecture

```
lib/
|-- app.dart
|-- main.dart
|-- firebase_options.dart
|-- core/
|   |-- constants/
|   |-- theme/
|   `-- widgets/
|-- data/repositories/
|-- features/
|   |-- auth/presentation/pages/
|   |-- home/presentation/
|   `-- profile/presentation/
|-- routes/
|   |-- app_routes.dart
|   `-- main_screen.dart
`-- services/
    `-- notifications/
```

Key view models:

- OperatorHomeViewModel: online state, booking streams, lifecycle actions, location sharing.
- OperatorTransactionSummaryViewModel: earnings summaries and PDF statements.

## Core flows

### Authentication and profile

- Email/password sign-in.
- AuthWrapper waits for operators/{uid}. If missing, routes to profile setup.
- saveOperatorProfile callable enforces unique operatorId via operator_id_index.
- Operator presence is stored in operator_presence/{uid}.
- When the operator releases active work to go offline, the app retries a failed offline presence write and cancels that retry if the operator intentionally goes online again.

### Booking lifecycle

OperatorHomeViewModel manages two streams:

- Active bookings (accepted/on_the_way) ordered by poolSequence.
- Pending bookings (status=pending) filtered by rejectedBy and deferral status.

Actions:

- acceptBooking -> acceptPooledBooking (callable)
- rejectBooking -> transaction updates rejectedBy
- releaseBooking -> transaction returns accepted booking to pending
- startTrip -> startPooledBooking (callable)
- markPassengerPickedUp -> markPoolStopReached (callable)
- completeTrip -> markPoolStopReached (callable)

Pooling deferrals:

- The backend may defer a booking for a later route sweep. The UI hides deferred bookings until the sweep changes.

### Live location sharing

- Geolocator streams operator positions while a booking is on_the_way.
- Updates are throttled (min 6s interval, min 20m movement) before writing.
- Booking snapshots are updated, and tracking/{bookingId} is written for high-frequency reads.
- A heartbeat poll refreshes location when GPS callbacks stall.

### Navigation and route rendering

- OperatorMapLayers resolves route geometry in priority order:
  - routeToOriginPolyline / routeToDestinationPolyline
  - shared routePolyline (pool corridor)
  - straight-line fallback
- OperatorMapControllerService manages overview vs tracking camera modes, tilt toggles, and recenter logic.
- OperatorNavigationGuidanceService computes route progress, ETA, off-route severity, and stop overshoot.
- Navigation alerts are published via OperatorNavigationAlertBus and shown as notifications when backgrounded.

### Notifications

- FCM tokens are stored in operator_devices/{uid} and refreshed on token rotation.
- notifyOperatorsOnIncomingBooking sends incoming-booking FCM notifications to operators currently online in operator_presence.
- Foreground incoming-booking FCM messages are suppressed because the live booking stream already shows the request.
- OperatorNotificationCoordinator emits local OS notifications for queue changes and status updates while backgrounded.
- Navigation alerts are surfaced locally for route progress, off-route warnings, route recovery, and stop completion context.
- LocalNotificationService manages a persistent online reminder when the app is backgrounded.
- Full trigger coverage is documented in ../../docs/push_notifications_features.md.

### Earnings summaries

- OperatorTransactionSummaryViewModel streams booking history and builds PDF statements.
- Statements are stored locally and tracked in shared preferences.

## Firestore model highlights

Operators collection:

- operatorId, name, email, phoneNumber
- createdAt, updatedAt

Presence collection:

- operator_presence/{uid}.isOnline, updatedAt

Device token collection:

- operator_devices/{uid}.tokens

Bookings used by operator app:

- status, operatorUid
- poolSequence, poolStopPlan, routeDirection
- routePolyline and phase-specific routes
- passengerCount, totalFare, fareSnapshotId
- operatorLat/operatorLng snapshots

## Setup

```bash
flutter pub get
flutter run
```

Google Maps key:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_API_KEY
```

## Testing

```bash
flutter analyze
flutter test
```

## Related documentation

- ../../docs/operator_app_features.md
- ../../docs/push_notifications_features.md
- ../../docs/firestore_schema_inventory.md
- ../../docs/drt_algorithm_reference.md

Documentation sync: June 2026 (code-aligned update).

