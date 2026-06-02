# Shared Package And Model API

Last updated: 2026-06-02.

This document explains the shared Dart package at `packages/water_taxi_shared`. The package centralizes Firestore constants, common models, booking status normalization, payment method labels, and operation result types used by both Flutter apps.

Related documents:

- `docs/firestore_schema_inventory.md`
- `docs/passenger_app_features.md`
- `docs/operator_app_features.md`
- `docs/drt_algorithm_reference.md`

## Package Purpose

`water_taxi_shared` prevents the passenger and operator apps from drifting apart on:

- Firestore collection names
- Firestore field names
- canonical booking status values
- typed booking/fare/jetty/user/operator models
- operation result shape used by view models

The shared package does not talk to Firestore directly. Repositories in each app read Firestore, convert platform-specific values like `GeoPoint` and `Timestamp`, and then construct shared models.

## Public Exports

File: `packages/water_taxi_shared/lib/water_taxi_shared.dart`

Exports:

### Constants

- `BookingStatus`
- `FirestoreCollections`
- `BookingFields`
- `BookingSubcollections`
- `BookingStatusHistoryFields`
- `UserFields`
- `OperatorFields`
- `OperatorPresenceFields`
- `DeviceTokenFields`
- `JettyFields`
- `FareFields`
- `TrackingFields`
- `PaymentMethods`

### Models

- `BookingModel`
- `BookingRoutePoint`
- `PoolStopPlanItem`
- `UserModel`
- `OperatorModel`
- `JettyModel`
- `FareModel`

### Utilities

- `OperationResult`
- `OperationSuccess`
- `OperationFailure`

## Firestore Collection Constants

Class: `FirestoreCollections`.

| Constant | Value | Purpose |
| --- | --- | --- |
| `bookings` | `bookings` | Canonical active booking lifecycle records. |
| `bookingsArchive` | `bookings_archive` | Immutable/historical terminal booking records. |
| `tracking` | `tracking` | Live operator location updates by booking. |
| `orderNumberIndex` | `order_number_index` | Order-number reservations. |
| `users` | `users` | Passenger profiles. |
| `operators` | `operators` | Operator profiles. |
| `operatorPresence` | `operator_presence` | Operator online/offline state. |
| `userDevices` | `user_devices` | Passenger FCM token docs. |
| `operatorDevices` | `operator_devices` | Operator FCM token docs. |
| `jetties` | `jetties` | Jetty configuration. |
| `polylines` | `polylines` | Route geometry. |
| `fares` | `fares` | Fare configuration. |

## Booking Field Constants

Class: `BookingFields`.

These constants mirror fields used by `bookings` and `bookings_archive`.

### Identity And Passenger Snapshot

| Constant | Value |
| --- | --- |
| `bookingId` | `bookingId` |
| `userId` | `userId` |
| `userName` | `userName` |
| `userPhone` | `userPhone` |

Passenger name and phone are copied into bookings for receipt/history stability.

### Route And Location

| Constant | Value |
| --- | --- |
| `origin` | `origin` |
| `destination` | `destination` |
| `originJettyId` | `originJettyId` |
| `destinationJettyId` | `destinationJettyId` |
| `routeKey` | `routeKey` deprecated |
| `originCoords` | `originCoords` |
| `destinationCoords` | `destinationCoords` |
| `routePolylineId` | `routePolylineId` |
| `routePolyline` | `routePolyline` |
| `routeToOriginPolyline` | `routeToOriginPolyline` |
| `routeToDestinationPolyline` | `routeToDestinationPolyline` |

### Passenger Counts And Fare

| Constant | Value |
| --- | --- |
| `adultCount` | `adultCount` |
| `childCount` | `childCount` |
| `passengerCount` | `passengerCount` |
| `adultFare` | `adultFare` |
| `childFare` | `childFare` |
| `adultSubtotal` | `adultSubtotal` |
| `childSubtotal` | `childSubtotal` |
| `fare` | `fare` |
| `totalFare` | `totalFare` |
| `fareSnapshotId` | `fareSnapshotId` |

### Payment

| Constant | Value |
| --- | --- |
| `paymentMethod` | `paymentMethod` |
| `paymentStatus` | `paymentStatus` |
| `orderNumber` | `orderNumber` |
| `transactionId` | `transactionId` |

### Lifecycle And Assignment

| Constant | Value |
| --- | --- |
| `status` | `status` |
| `operatorUid` | `operatorUid` |
| `operatorId` | `operatorId` |
| `assignedOperatorName` | `assignedOperatorName` |
| `assignedOperatorDisplayId` | `assignedOperatorDisplayId` |
| `assignedOperatorPhone` | `assignedOperatorPhone` |
| `operatorLat` | `operatorLat` |
| `operatorLng` | `operatorLng` |
| `rejectedBy` | `rejectedBy` |

`operatorId` is retained for compatibility. New assignment should prefer `operatorUid`.

### Pooling And DRT

| Constant | Value |
| --- | --- |
| `pooled` | `pooled` |
| `poolGroupId` | `poolGroupId` |
| `routeDirection` | `routeDirection` |
| `poolSequence` | `poolSequence` |
| `poolCriteriaVersion` | `poolCriteriaVersion` |
| `poolMax` | `poolMax` |
| `poolEligibilityScore` | `poolEligibilityScore` |
| `poolEtaSnapshot` | `poolEtaSnapshot` |
| `poolStopPlan` | `poolStopPlan` |
| `currentStopIndex` | `currentStopIndex` |
| `currentStopId` | `currentStopId` |
| `currentPoolStopId` | `currentPoolStopId` |
| `poolStatus` | `poolStatus` |
| `poolPickupStopId` | `poolPickupStopId` |
| `poolDropoffStopId` | `poolDropoffStopId` |
| `poolPhase` | `poolPhase` |
| `onboard` | `onboard` |

### Current-Sweep Deferral

| Constant | Value |
| --- | --- |
| `poolDeferredForOperatorUid` | `poolDeferredForOperatorUid` |
| `poolDeferredRouteDirection` | `poolDeferredRouteDirection` |
| `poolDeferredPoolGroupId` | `poolDeferredPoolGroupId` |
| `poolDeferredReason` | `poolDeferredReason` |
| `poolDeferredUntil` | `poolDeferredUntil` |
| `poolDeferredAt` | `poolDeferredAt` |

### Timestamps

| Constant | Value |
| --- | --- |
| `createdAt` | `createdAt` |
| `updatedAt` | `updatedAt` |
| `cancelledAt` | `cancelledAt` |
| `passengerPickedUpAt` | `passengerPickedUpAt` |
| `pickedUpAt` | `pickedUpAt` |
| `droppedOffAt` | `droppedOffAt` |
| `completedAt` | `completedAt` |

## Booking Status API

Enum: `BookingStatus`.

Canonical values:

- `pending`
- `accepted`
- `onTheWay`
- `completed`
- `cancelled`
- `rejected`
- `unknown`

### `BookingStatus.fromString(String value)`

Parses canonical and legacy Firestore status strings.

| Input | Output |
| --- | --- |
| `pending` | `BookingStatus.pending` |
| `accepted` | `BookingStatus.accepted` |
| `confirmed` | `BookingStatus.accepted` |
| `on_the_way` | `BookingStatus.onTheWay` |
| `in_progress` | `BookingStatus.onTheWay` |
| `ongoing` | `BookingStatus.onTheWay` |
| `completed` | `BookingStatus.completed` |
| `cancelled` | `BookingStatus.cancelled` |
| `rejected` | `BookingStatus.rejected` |
| anything else | `BookingStatus.unknown` |

### `firestoreValue`

Returns canonical write value:

| Enum | Firestore Value |
| --- | --- |
| `pending` | `pending` |
| `accepted` | `accepted` |
| `onTheWay` | `on_the_way` |
| `completed` | `completed` |
| `cancelled` | `cancelled` |
| `rejected` | `rejected` |
| `unknown` | `unknown` |

### Convenience Getters

| Getter | True For |
| --- | --- |
| `isActive` | `pending`, `accepted`, `onTheWay` |
| `isTerminal` | `completed`, `cancelled`, `rejected` |
| `canBeCancelledByPassenger` | `pending`, `accepted`, `onTheWay` |

## BookingModel

Class: `BookingModel`.

Represents a booking document after repository conversion.

Important design detail: repositories must convert Firestore-specific types before constructing the model:

- `GeoPoint` becomes separate latitude/longitude doubles
- `Timestamp` becomes `DateTime?`

### Core Constructor Fields

Required:

- booking identity: `bookingId`
- passenger identity snapshot: `userId`, `userName`, `userPhone`
- route names: `origin`, `destination`
- route coordinates: `originLat`, `originLng`, `destinationLat`, `destinationLng`
- passenger counts: `adultCount`, `childCount`, `passengerCount`
- fare/payment: `totalFare`, `paymentMethod`, `paymentStatus`
- lifecycle: `status`
- rejection list: `rejectedBy`

Optional:

- jetty IDs
- route polyline IDs and route point lists
- assigned operator details
- pooling fields
- deferral fields
- operator location
- order and transaction IDs
- lifecycle timestamps

### Operator UID Compatibility

Constructor accepts:

- `operatorUid`
- deprecated `operatorId`

Internally:

```dart
operatorUid = operatorUid ?? operatorId
```

The `operatorId` getter returns `operatorUid` for compatibility.

### `currentPoolStop`

Resolves the current stop from `poolStopPlan` using this priority:

1. stop whose `stopId == currentStopId`
2. first stop whose `status == active`
3. stop at `currentStopIndex`
4. first stop in plan
5. `null` if there is no stop plan

This keeps operator UI stable when different backend versions provide slightly different current-stop metadata.

### `BookingModel.fromMap`

Inputs:

- raw data map
- converted origin/destination coordinates
- optional converted timestamps

It parses:

- status through `BookingStatus.fromString`
- route polylines through route point helper methods
- phase-specific polylines from multiple alias field names
- pool stop plan items
- numeric fields through tolerant numeric parsing
- boolean values from bool, number, or string-like inputs
- date fields from DateTime, epoch milliseconds, numeric values, or parseable strings

### Route Polyline Aliases

Base route polyline accepts:

- `routePolyline`
- `routeCoordinates`
- `polylineCoordinates`
- `routePoints`

Route-to-origin aliases include:

- `routeToOriginPolyline`
- `operatorToOriginPolyline`
- `toOriginPolyline`
- `routeToOrigin`
- `pickupPolyline`
- `routeToPickupPolyline`
- `operatorToPickupPolyline`
- `pickupRoutePolyline`
- `pickupRoute`
- `pickupPath`
- `toOriginPath`
- `operatorToPickupPath`
- `operatorToOriginCoordinates`
- `pickupPathCoordinates`

Route-to-destination aliases include:

- `routeToDestinationPolyline`
- `originToDestinationPolyline`
- `toDestinationPolyline`
- `routeToDestination`
- `dropoffPolyline`
- `dropoffRoutePolyline`
- `dropoffRoute`
- `destinationRoutePolyline`
- `toDestinationPath`
- `pickupToDestinationPath`
- `originToDestinationCoordinates`
- `dropoffPathCoordinates`

This compatibility layer allows the apps to read older route field formats.

### `copyWith`

Returns a new immutable `BookingModel` with selected values replaced.

Common uses:

- merge `tracking/{bookingId}` operator location into a booking model
- locally advance UI state after stop actions
- normalize archive/history variants

## BookingRoutePoint

Class: `BookingRoutePoint`.

Fields:

- `lat`
- `lng`

Parser: `BookingRoutePoint.tryParse(dynamic raw)`.

Accepted map keys:

- `lat`
- `latitude`
- `_latitude`
- `lng`
- `longitude`
- `lon`
- `_longitude`

Accepted list format:

```dart
[lat, lng]
```

Invalid entries return `null`.

## PoolStopPlanItem

Class: `PoolStopPlanItem`.

Represents one stop in a backend-generated pool stop plan.

Fields:

| Field | Meaning |
| --- | --- |
| `stopId` | Stable stop identifier. |
| `index` | Stop order. |
| `stopType` | `pickup` or `dropoff`. |
| `stopJettyId` | Jetty ID. |
| `stopName` | Human-readable stop/jetty name. |
| `lat` / `lng` | Stop coordinates. |
| `routePositionMeters` | Position along route. |
| `distanceFromRouteMeters` | Deviation from route. |
| `bookingIds` | Bookings served by this stop. |
| `passengerCount` | Stop-level passenger total. |
| `adultCount` | Stop-level adult total. |
| `childCount` | Stop-level child total. |
| `status` | Stop status; defaults to `pending`. |
| `etaToStopMinutes` | ETA to stop if present. |
| `reachedAt` | Stop reached timestamp. |
| `completedAt` | Stop completed timestamp. |

Getters:

- `isPickup`
- `isDropoff`

Parser aliases:

- index reads `stopIndex` or `index`
- stop jetty reads `jettyId` or `stopJettyId`
- stop name reads `jettyName` or `stopName`
- ETA reads `etaToStop`

## FareModel

Class: `FareModel`.

Represents `fares/{id}`.

Fields:

- `snapshotId`
- `origin`
- `destination`
- `originJettyId`
- `destinationJettyId`
- `adultFare`
- `childFare`

Parser:

- string fields are converted with `toString`
- missing optional jetty IDs become `null`
- numeric fare values accept `double`, `num`, or parseable string
- invalid numeric values become `0.0`

## JettyModel

Class: `JettyModel`.

Represents `jetties/{id}`.

Fields:

- `jettyId`
- `name`
- `lat`
- `lng`

The model uses the Firestore document ID as `jettyId`.

Numeric parsing accepts `double`, `num`, or parseable string. Invalid values become `0.0`.

## OperatorModel

Class: `OperatorModel`.

Represents `operators/{uid}`.

Fields:

- `uid`
- `operatorId`
- `name`
- `email`
- `isOnline`
- `phoneNumber`
- `createdAt`
- `updatedAt`

Important current behavior:

- `isOnline` is parsed from `operators.isOnline`.
- The current app architecture stores online state in `operator_presence`, so repository/view-model code should avoid treating `OperatorModel.isOnline` as the authoritative live presence source unless it was deliberately hydrated.

Methods:

- `copyWith`
- `toMap`

`toMap` writes:

- `operatorId`
- `name`
- `email`
- `phoneNumber`

## UserModel

Class: `UserModel`.

Represents `users/{uid}`.

Fields:

- `uid`
- `name`
- `email`
- `phoneNumber`
- `createdAt`
- `updatedAt`

Methods:

- `copyWith`
- `toMap`

`toMap` writes:

- `uid`
- `name`
- `email`
- `phoneNumber`

## OperationResult

Sealed class used by ViewModel action methods.

Purpose:

- keep business/action result semantics in the ViewModel
- let widgets display success/error/info UI consistently

### `OperationSuccess`

Fields:

- `message`
- `data`

Used when an operation completed successfully.

### `OperationFailure`

Fields:

- `title`
- `message`
- `isInfo`

`isInfo` is true for soft failures where a neutral info alert is better than a red error, for example when a booking was already accepted by someone else.

## Repository Responsibilities Outside Shared Package

The shared package does not:

- query Firestore
- write Firestore
- convert `GeoPoint`
- convert `Timestamp`
- call Cloud Functions
- know about Provider or widget state

Those responsibilities live in app-specific repositories and services:

Passenger:

- `UserRepository`
- `JettyRepository`
- `FareRepository`
- `BookingRepository`

Operator:

- `OperatorRepository`
- `BookingRepository`

This split keeps shared models dependency-light and reusable.

## Compatibility Notes

- `BookingStatus.fromString` accepts legacy status aliases but `firestoreValue` writes canonical strings.
- `BookingModel` accepts both `operatorUid` and deprecated `operatorId`.
- Route parsing accepts several historic field names.
- Route point parsing accepts Firestore exported `_latitude` and `_longitude` keys.
- Pool stop parsing accepts both `jettyId` and `stopJettyId`.

## Known Boundaries

- Models are not generated with Freezed or JSON serialization.
- Parsing is intentionally forgiving and may coerce invalid numeric data to zero.
- `BookingModel.fromMap` expects repositories to pre-convert Firestore coordinate/timestamp types.
- The shared package is not a full domain service layer; it is a constants/models/result package.
