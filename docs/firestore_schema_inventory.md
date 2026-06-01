# Firestore Schema Inventory

Last updated: 2026-06-02

Source:

- Live Firestore inspection of project `melaka-water-taxi`, database `(default)`, at `2026-06-01T22:56:26Z`.
- Inspection sampled up to 25 documents per top-level collection and up to 25 `bookings/*/statusHistory` documents through a collection-group query.

This inventory is intentionally live-observed only. Collections and fields that were not present in the live sample are not listed here.

## Top-Level Collections

Live-observed collections:

- `bookings`
- `bookings_archive`
- `fares`
- `jetties`
- `operator_devices`
- `operator_id_index`
- `operator_presence`
- `operators`
- `polylines`
- `tracking`
- `user_devices`
- `users`

## Relationships

- `bookings.userId` -> `users/{uid}`
- `bookings.operatorUid` -> `operators/{uid}`
- `bookings.originJettyId` -> `jetties/{jettyId}`
- `bookings.destinationJettyId` -> `jetties/{jettyId}`
- `bookings.fareSnapshotId` -> `fares/{fareDocId}`
- `bookings.routePolylineId` -> `polylines/{routeId}`
- `bookings/{bookingId}/statusHistory` -> status audit entries for `bookings/{bookingId}`
- `bookings_archive/{bookingId}` mirrors terminal-state `bookings/{bookingId}` records
- `tracking/{bookingId}.bookingId` -> `bookings/{bookingId}`
- `tracking/{bookingId}.operatorUid` -> `operators/{uid}`
- `operator_presence/{uid}` is the online state companion to `operators/{uid}`
- `operator_devices/{uid}` stores operator push-device metadata
- `user_devices/{uid}` stores passenger push-device metadata
- `operator_id_index/{operatorId}` reserves unique public operator display IDs

## Collection Functionality Summary

| Collection | Live sample | Functionality |
| --- | ---: | --- |
| `bookings` | 25 | Active booking lifecycle, pending dispatch queue, operator assignment, DRT/pooling state, payment state, route snapshots, and operator location snapshots. |
| `bookings/{bookingId}/statusHistory` | 25 | Per-booking status transition audit trail. |
| `bookings_archive` | 25 | Terminal booking mirror for completed, cancelled, or rejected booking history and retention. |
| `fares` | 25 | Fare lookup records between origin and destination jetties. |
| `jetties` | 14 | Canonical water taxi stops, labels, and coordinates. |
| `operator_devices` | 1 | Operator FCM token metadata for push notifications. |
| `operator_id_index` | 1 | Unique index for public operator display IDs. |
| `operator_presence` | 1 | Canonical operator online/offline availability state. |
| `operators` | 1 | Operator profile and contact metadata. |
| `polylines` | 1 | Route geometry used by maps, route snapshots, pooling, and navigation guidance. |
| `tracking` | 25 | Live operator coordinate records for active or recently active bookings. |
| `user_devices` | 9 | Passenger FCM token metadata for booking status notifications. |
| `users` | 7 | Passenger profile and contact metadata. |

## bookings

Purpose: active booking lifecycle records used by passenger dispatch, operator assignment, DRT pooling, payment state, and route/location snapshots.

Live sample: 25 documents.

Live-observed fields:

- `adultCount`: integer; observed on 25/25 sampled docs
- `assignedOperatorDisplayId`: string; observed on 19/25 sampled docs
- `assignedOperatorName`: string; observed on 19/25 sampled docs
- `assignedOperatorPhone`: string; observed on 19/25 sampled docs
- `bookingId`: string; observed on 25/25 sampled docs
- `cancelledAt`: timestamp; observed on 16/25 sampled docs
- `childCount`: integer; observed on 25/25 sampled docs
- `createdAt`: timestamp; observed on 25/25 sampled docs
- `currentPoolStopId`: string or null; observed on 19/25 sampled docs
- `currentStopId`: string or null; observed on 19/25 sampled docs
- `currentStopIndex`: integer; observed on 19/25 sampled docs
- `destination`: string; observed on 25/25 sampled docs
- `destinationCoords`: GeoPoint; observed on 25/25 sampled docs
- `destinationJettyId`: string; observed on 25/25 sampled docs
- `droppedOffAt`: timestamp; observed on 7/25 sampled docs
- `fareSnapshotId`: string; observed on 25/25 sampled docs
- `onboard`: boolean; observed on 19/25 sampled docs
- `operatorLat`: double; observed on 14/25 sampled docs
- `operatorLng`: double; observed on 14/25 sampled docs
- `operatorUid`: string or null; observed on 25/25 sampled docs
- `orderNumber`: string; observed on 25/25 sampled docs
- `origin`: string; observed on 25/25 sampled docs
- `originCoords`: GeoPoint; observed on 25/25 sampled docs
- `originJettyId`: string; observed on 25/25 sampled docs
- `passengerCount`: integer; observed on 25/25 sampled docs
- `passengerPickedUpAt`: timestamp; observed on 7/25 sampled docs
- `paymentMethod`: string; observed on 25/25 sampled docs
- `paymentStatus`: string; observed on 25/25 sampled docs
- `pickedUpAt`: timestamp; observed on 7/25 sampled docs
- `poolCriteriaVersion`: string; observed on 19/25 sampled docs
- `poolDropoffStopId`: string; observed on 19/25 sampled docs
- `pooled`: boolean; observed on 19/25 sampled docs
- `poolEligibilityScore`: double; observed on 19/25 sampled docs
- `poolEtaSnapshot`: map; observed on 19/25 sampled docs
- `poolGroupId`: string; observed on 19/25 sampled docs
- `poolMax`: integer; observed on 19/25 sampled docs
- `poolPhase`: string; observed on 19/25 sampled docs
- `poolPickupStopId`: string; observed on 19/25 sampled docs
- `poolSequence`: integer; observed on 19/25 sampled docs
- `poolStatus`: string; observed on 19/25 sampled docs
- `poolStopPlan`: array; observed on 19/25 sampled docs
- `rejectedBy`: array; observed on 6/25 sampled docs
- `routeDirection`: string; observed on 19/25 sampled docs
- `routePolyline`: array; observed on 24/25 sampled docs
- `routePolylineId`: string; observed on 25/25 sampled docs
- `status`: string; observed on 25/25 sampled docs
- `totalFare`: double; observed on 25/25 sampled docs
- `transactionId`: string; observed on 25/25 sampled docs
- `updatedAt`: timestamp; observed on 25/25 sampled docs
- `userId`: string; observed on 25/25 sampled docs
- `userName`: string; observed on 25/25 sampled docs
- `userPhone`: string; observed on 25/25 sampled docs

### bookings.poolEtaSnapshot

Live-observed nested keys:

- `activeDistanceMeters`: integer; observed on 19 sampled maps
- `addedDistanceMeters`: integer; observed on 19 sampled maps
- `addedEtaLimitMinutes`: integer; observed on 19 sampled maps
- `addedEtaMinutes`: double or integer; observed on 19 sampled maps
- `destinationDeviationMeters`: integer; observed on 19 sampled maps
- `evaluatedAt`: string; observed on 19 sampled maps
- `maxPerRiderAddedDistanceMeters`: integer; observed on 19 sampled maps
- `maxPerRiderAddedEtaMinutes`: double or integer; observed on 19 sampled maps
- `maxPickupDistanceMeters`: integer; observed on 19 sampled maps
- `maxRouteDeviationMeters`: integer; observed on 19 sampled maps
- `originDeviationMeters`: integer; observed on 19 sampled maps
- `pickupDistanceMeters`: integer; observed on 19 sampled maps
- `pickupWindowMinutes`: integer; observed on 19 sampled maps
- `pooledDistanceMeters`: integer; observed on 19 sampled maps

### bookings.poolStopPlan Item Shape

Live-observed nested keys from sampled stop-plan items:

- `adultCount`: integer; observed on 5 sampled stop-plan items
- `bookingIds`: array; observed on 19 sampled stop-plan items
- `childCount`: integer; observed on 5 sampled stop-plan items
- `completedAt`: string or null; observed on 19 sampled stop-plan items
- `jettyId`: string; observed on 19 sampled stop-plan items
- `jettyName`: string; observed on 19 sampled stop-plan items
- `lat`: double; observed on 19 sampled stop-plan items
- `lng`: double; observed on 19 sampled stop-plan items
- `passengerCount`: integer; observed on 5 sampled stop-plan items
- `reachedAt`: string or null; observed on 19 sampled stop-plan items
- `routePositionMeters`: double or integer; observed on 19 sampled stop-plan items
- `status`: string; observed on 19 sampled stop-plan items
- `stopId`: string; observed on 19 sampled stop-plan items
- `stopIndex`: integer; observed on 19 sampled stop-plan items
- `stopName`: string; observed on 19 sampled stop-plan items
- `stopType`: string; observed on 19 sampled stop-plan items

### bookings.routePolyline Item Shape

Live-observed nested keys from sampled route point items:

- `lat`: double; observed on 24 sampled route point arrays
- `lng`: double; observed on 24 sampled route point arrays

### bookings/{bookingId}/statusHistory

Purpose: status transition audit records stored below individual booking documents.

Live-observed through collection-group query.

Live sample: 25 documents.

Live-observed fields:

- `changedBy`: string; observed on 25/25 sampled docs
- `from`: string; observed on 25/25 sampled docs
- `source`: string; observed on 25/25 sampled docs
- `timestamp`: timestamp; observed on 25/25 sampled docs
- `to`: string; observed on 25/25 sampled docs

## bookings_archive

Purpose: terminal-state booking mirror for historical display and retention.

Live sample: 25 documents.

Live-observed fields:

- `adultCount`: integer; observed on 25/25 sampled docs
- `archivedAt`: timestamp; observed on 25/25 sampled docs
- `archivedStatus`: string; observed on 25/25 sampled docs
- `assignedOperatorDisplayId`: string; observed on 21/25 sampled docs
- `assignedOperatorName`: string; observed on 21/25 sampled docs
- `assignedOperatorPhone`: string; observed on 21/25 sampled docs
- `bookingId`: string; observed on 25/25 sampled docs
- `cancelledAt`: timestamp; observed on 18/25 sampled docs
- `childCount`: integer; observed on 25/25 sampled docs
- `createdAt`: timestamp; observed on 25/25 sampled docs
- `currentPoolStopId`: string or null; observed on 21/25 sampled docs
- `currentStopId`: string or null; observed on 21/25 sampled docs
- `currentStopIndex`: integer; observed on 21/25 sampled docs
- `destination`: string; observed on 25/25 sampled docs
- `destinationCoords`: GeoPoint; observed on 25/25 sampled docs
- `destinationJettyId`: string; observed on 25/25 sampled docs
- `droppedOffAt`: timestamp; observed on 7/25 sampled docs
- `fareSnapshotId`: string; observed on 25/25 sampled docs
- `onboard`: boolean; observed on 21/25 sampled docs
- `operatorLat`: double; observed on 16/25 sampled docs
- `operatorLng`: double; observed on 16/25 sampled docs
- `operatorUid`: string or null; observed on 25/25 sampled docs
- `orderNumber`: string; observed on 25/25 sampled docs
- `origin`: string; observed on 25/25 sampled docs
- `originCoords`: GeoPoint; observed on 25/25 sampled docs
- `originJettyId`: string; observed on 25/25 sampled docs
- `passengerCount`: integer; observed on 25/25 sampled docs
- `passengerPickedUpAt`: timestamp; observed on 7/25 sampled docs
- `paymentMethod`: string; observed on 25/25 sampled docs
- `paymentStatus`: string; observed on 25/25 sampled docs
- `pickedUpAt`: timestamp; observed on 7/25 sampled docs
- `poolCriteriaVersion`: string; observed on 21/25 sampled docs
- `poolDropoffStopId`: string; observed on 21/25 sampled docs
- `pooled`: boolean; observed on 21/25 sampled docs
- `poolEligibilityScore`: double; observed on 21/25 sampled docs
- `poolEtaSnapshot`: map; observed on 21/25 sampled docs
- `poolGroupId`: string; observed on 21/25 sampled docs
- `poolMax`: integer; observed on 21/25 sampled docs
- `poolPhase`: string; observed on 21/25 sampled docs
- `poolPickupStopId`: string; observed on 21/25 sampled docs
- `poolSequence`: integer; observed on 21/25 sampled docs
- `poolStatus`: string; observed on 21/25 sampled docs
- `poolStopPlan`: array; observed on 21/25 sampled docs
- `rejectedBy`: array; observed on 4/25 sampled docs
- `routeDirection`: string; observed on 21/25 sampled docs
- `routePolyline`: array; observed on 24/25 sampled docs
- `routePolylineId`: string; observed on 25/25 sampled docs
- `status`: string; observed on 25/25 sampled docs
- `totalFare`: double or integer; observed on 25/25 sampled docs
- `transactionId`: string; observed on 25/25 sampled docs
- `updatedAt`: timestamp; observed on 25/25 sampled docs
- `userId`: string; observed on 25/25 sampled docs
- `userName`: string; observed on 25/25 sampled docs
- `userPhone`: string; observed on 25/25 sampled docs

### bookings_archive.poolEtaSnapshot

Live-observed nested keys:

- `activeDistanceMeters`: integer; observed on 21 sampled maps
- `addedDistanceMeters`: integer; observed on 21 sampled maps
- `addedEtaLimitMinutes`: integer; observed on 21 sampled maps
- `addedEtaMinutes`: double or integer; observed on 21 sampled maps
- `destinationDeviationMeters`: integer; observed on 21 sampled maps
- `evaluatedAt`: string; observed on 21 sampled maps
- `maxPerRiderAddedDistanceMeters`: integer; observed on 21 sampled maps
- `maxPerRiderAddedEtaMinutes`: double or integer; observed on 21 sampled maps
- `maxPickupDistanceMeters`: integer; observed on 21 sampled maps
- `maxRouteDeviationMeters`: integer; observed on 21 sampled maps
- `originDeviationMeters`: integer; observed on 21 sampled maps
- `pickupDistanceMeters`: integer; observed on 21 sampled maps
- `pickupWindowMinutes`: integer; observed on 21 sampled maps
- `pooledDistanceMeters`: integer; observed on 21 sampled maps

### bookings_archive.poolStopPlan Item Shape

Live-observed nested keys from sampled stop-plan items:

- `adultCount`: integer; observed on 5 sampled stop-plan items
- `bookingIds`: array; observed on 21 sampled stop-plan items
- `childCount`: integer; observed on 5 sampled stop-plan items
- `completedAt`: string or null; observed on 21 sampled stop-plan items
- `jettyId`: string; observed on 21 sampled stop-plan items
- `jettyName`: string; observed on 21 sampled stop-plan items
- `lat`: double; observed on 21 sampled stop-plan items
- `lng`: double; observed on 21 sampled stop-plan items
- `passengerCount`: integer; observed on 5 sampled stop-plan items
- `reachedAt`: string or null; observed on 21 sampled stop-plan items
- `routePositionMeters`: double or integer; observed on 21 sampled stop-plan items
- `status`: string; observed on 21 sampled stop-plan items
- `stopId`: string; observed on 21 sampled stop-plan items
- `stopIndex`: integer; observed on 21 sampled stop-plan items
- `stopName`: string; observed on 21 sampled stop-plan items
- `stopType`: string; observed on 21 sampled stop-plan items

### bookings_archive.routePolyline Item Shape

Live-observed nested keys from sampled route point items:

- `lat`: double; observed on 24 sampled route point arrays
- `lng`: double; observed on 24 sampled route point arrays

## fares

Purpose: fare records between origin and destination jetties. Fare values are snapshotted onto booking documents at creation time.

Live sample: 25 documents.

Live-observed fields:

- `adultFare`: double; observed on 25/25 sampled docs
- `childFare`: double or integer; observed on 25/25 sampled docs
- `destinationJettyId`: string; observed on 25/25 sampled docs
- `originJettyId`: string; observed on 25/25 sampled docs

## jetties

Purpose: canonical water taxi stop records used for passenger selection, route endpoints, fare keys, and stop-plan jetty identity.

Live sample: 14 documents.

Live-observed fields:

- `lat`: double; observed on 14/14 sampled docs
- `lng`: double; observed on 14/14 sampled docs
- `name`: string; observed on 14/14 sampled docs

Note: the document ID is the canonical live-observed `jettyId`.

## operator_devices

Purpose: operator push notification device records.

Live sample: 1 document.

Live-observed fields:

- `appRole`: string; observed on 1/1 sampled docs
- `platform`: string; observed on 1/1 sampled docs
- `token`: string; observed on 1/1 sampled docs
- `updatedAt`: timestamp; observed on 1/1 sampled docs

## operator_id_index

Purpose: unique index for public operator display IDs.

Live sample: 1 document.

Live-observed fields:

- `createdAt`: timestamp; observed on 1/1 sampled docs
- `operatorId`: string; observed on 1/1 sampled docs
- `uid`: string; observed on 1/1 sampled docs
- `updatedAt`: timestamp; observed on 1/1 sampled docs

## operator_presence

Purpose: canonical operator online availability records used by dispatch, notifications, passenger availability checks, and no-operator cleanup.

Live sample: 1 document.

Live-observed fields:

- `isOnline`: boolean; observed on 1/1 sampled docs
- `updatedAt`: timestamp; observed on 1/1 sampled docs

## operators

Purpose: operator profile records. Online state is stored in `operator_presence`, not in the sampled `operators` document.

Live sample: 1 document.

Live-observed fields:

- `createdAt`: timestamp; observed on 1/1 sampled docs
- `email`: string; observed on 1/1 sampled docs
- `name`: string; observed on 1/1 sampled docs
- `operatorId`: string; observed on 1/1 sampled docs
- `phoneNumber`: string; observed on 1/1 sampled docs
- `updatedAt`: timestamp; observed on 1/1 sampled docs

## polylines

Purpose: route geometry records used by route rendering, route snapshots, DRT pooling calculations, and navigation guidance.

Live sample: 1 document.

Live-observed fields:

- `path`: array; observed on 1/1 sampled docs
- `properties`: map; observed on 1/1 sampled docs
- `type`: string; observed on 1/1 sampled docs
- `uploadedAt`: timestamp; observed on 1/1 sampled docs

### polylines.properties

Live-observed nested keys:

- `city`: string; observed on 1 sampled map
- `route_name`: string; observed on 1 sampled map

## tracking

Purpose: operator location records keyed by booking ID.

Live sample: 25 documents.

Live-observed fields:

- `bookingId`: string; observed on 25/25 sampled docs
- `operatorLat`: double; observed on 25/25 sampled docs
- `operatorLng`: double; observed on 25/25 sampled docs
- `operatorUid`: string; observed on 25/25 sampled docs
- `updatedAt`: timestamp; observed on 25/25 sampled docs

## user_devices

Purpose: passenger push notification device records.

Live sample: 9 documents.

Live-observed fields:

- `appRole`: string; observed on 9/9 sampled docs
- `platform`: string; observed on 9/9 sampled docs
- `token`: string; observed on 9/9 sampled docs
- `updatedAt`: timestamp; observed on 9/9 sampled docs

## users

Purpose: passenger profile records used to snapshot passenger identity and contact details onto bookings.

Live sample: 7 documents.

Live-observed fields:

- `createdAt`: timestamp; observed on 7/7 sampled docs
- `email`: string; observed on 7/7 sampled docs
- `name`: string; observed on 7/7 sampled docs
- `phoneNumber`: string; observed on 7/7 sampled docs
- `uid`: string; observed on 6/7 sampled docs
- `updatedAt`: timestamp; observed on 7/7 sampled docs

## Notes For Future Schema Audits

- This document is sample-based. A field absent from this document is not guaranteed absent from Firestore.
- Keep this file live-observed only. Do not add collections or fields unless they appear in a fresh live sample.
- Re-run the live inspection after major DRT field migrations, payment flow changes, or archive cleanup changes.
