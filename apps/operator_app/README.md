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

- FCM tokens stored in operator_devices/{uid}.
- Cloud Functions send incoming booking notifications to online operators.
- OperatorNotificationCoordinator emits local OS notifications for queue changes and status updates.
- LocalNotificationService manages a persistent online reminder when the app is backgrounded.

### Earnings summaries

- OperatorTransactionSummaryViewModel streams booking history and builds PDF statements.
- Statements are stored locally and tracked in shared preferences.

## Firestore model highlights

Operators collection:

- operatorId, name, email, phoneNumber
- createdAt, updatedAt

Presence collection:

- operator_presence/{uid}.isOnline, updatedAt

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

Documentation sync: May 2026 (code-aligned update).

