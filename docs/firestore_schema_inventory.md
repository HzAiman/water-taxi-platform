# Firestore Schema Inventory

Last updated: 2026-05-24

Source:

- Live Firestore inspection of project `melaka-water-taxi`, database `(default)`, at `2026-05-24T04:35:25Z`.
- Code inspection of shared models, app repositories, and Cloud Functions.

Live inspection sampled up to 25 documents per top-level collection and up to 25 `statusHistory` documents through a collection-group query. Field presence counts below are sample counts, not total document counts.

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

Code-supported collections not present in the live sample at inspection time:

- `order_number_index`
- `payment_webhooks`
- `webhook_events`

## Relationships

- `bookings.userId` -> `users/{uid}`
- `bookings.operatorUid` -> `operators/{uid}`
- `bookings.originJettyId` -> `jetties/{jettyId}`
- `bookings.destinationJettyId` -> `jetties/{jettyId}`
- `bookings.fareSnapshotId` -> `fares/{fareDocId}`
- `bookings.routePolylineId` -> `polylines/{routeId}`
- `tracking/{bookingId}.bookingId` -> `bookings/{bookingId}`
- `tracking/{bookingId}.operatorUid` -> `operators/{uid}`
- `operator_presence/{uid}` is the online state companion to `operators/{uid}`
- `operator_id_index/{operatorId}` reserves unique public operator display IDs
- `order_number_index/{orderNumber}` reserves unique payment order numbers

## bookings

Purpose: active booking lifecycle records used by both apps.

Live sample: 25 documents.

Live-observed core fields:

- `bookingId`: string
- `userId`: string
- `userName`: string
- `userPhone`: string
- `origin`: string
- `destination`: string
- `originJettyId`: string
- `destinationJettyId`: string

Live-observed route fields:

- `originCoords`: GeoPoint
- `destinationCoords`: GeoPoint
- `routePolylineId`: string
- `routePolyline`: array of maps `{lat,lng}`

Code-supported route fields not observed in the top-level live sample:

- `routeToOriginPolyline`
- `routeToDestinationPolyline`

Live-observed fare and payment fields:

- `adultCount`: integer
- `childCount`: integer
- `passengerCount`: integer
- `totalFare`: double
- `fareSnapshotId`: string
- `paymentMethod`: string
- `paymentStatus`: string
- `orderNumber`: string
- `transactionId`: string

Live-observed assignment and status fields:

- `status`: string; expected values include `pending`, `accepted`, `on_the_way`, `completed`, `cancelled`, `rejected`
- `operatorUid`: string or null
- `assignedOperatorName`: string; observed on 19/25 sampled docs
- `assignedOperatorDisplayId`: string; observed on 19/25 sampled docs
- `assignedOperatorPhone`: string; observed on 19/25 sampled docs
- `rejectedBy`: array of strings; observed on 6/25 sampled docs

Code-supported legacy alias:

- `operatorId`: legacy alias for assigned operator identity; runtime should prefer `operatorUid`

Live-observed DRT and pooling fields:

- `pooled`: boolean; observed on 19/25 sampled docs
- `poolGroupId`: string
- `poolSequence`: integer
- `poolCriteriaVersion`: string
- `poolMax`: integer
- `routeDirection`: string; expected values `forward` or `reverse`
- `poolEligibilityScore`: double
- `poolEtaSnapshot`: map with route/ETA diagnostics
- `poolStatus`: string; expected values include `accepted`, `in_progress`, `completed`
- `poolStopPlan`: array of stop maps
- `currentStopIndex`: integer
- `currentStopId`: string or null
- `currentPoolStopId`: string or null
- `poolPickupStopId`: string
- `poolDropoffStopId`: string
- `poolPhase`: string; expected values include `waiting_pickup`, `onboard`, `dropped_off`
- `onboard`: boolean
- `passengerPickedUpAt`: timestamp; observed on 4/25 sampled docs
- `pickedUpAt`: timestamp; observed on 4/25 sampled docs
- `droppedOffAt`: timestamp; observed on 3/25 sampled docs

Code-supported pooling fields not observed in the current top-level sample:

- `poolDeferredForOperatorUid`
- `poolDeferredRouteDirection`
- `poolDeferredPoolGroupId`
- `poolDeferredReason`
- `poolDeferredUntil`
- `poolDeferredAt`
- `completedAt`

Live-observed operator location snapshots:

- `operatorLat`: double; observed on 14/25 sampled docs
- `operatorLng`: double; observed on 14/25 sampled docs

Live-observed timestamps:

- `createdAt`: timestamp
- `updatedAt`: timestamp
- `cancelledAt`: timestamp; observed on 20/25 sampled docs

### poolEtaSnapshot

Live-observed map keys:

- `activeDistanceMeters`
- `addedDistanceMeters`
- `addedEtaLimitMinutes`
- `addedEtaMinutes`
- `destinationDeviationMeters`
- `evaluatedAt`
- `maxPerRiderAddedDistanceMeters`
- `maxPerRiderAddedEtaMinutes`
- `maxPickupDistanceMeters`
- `maxRouteDeviationMeters`
- `originDeviationMeters`
- `pickupDistanceMeters`
- `pickupWindowMinutes`
- `pooledDistanceMeters`

### poolStopPlan Item Shape

Live-observed stop item keys:

- `stopId`
- `stopIndex`
- `stopType`: `pickup` or `dropoff`
- `jettyId`
- `jettyName`
- `stopName`
- `lat`
- `lng`
- `routePositionMeters`
- `bookingIds`: array
- `status`: `pending`, `active`, `completed`, or `skipped`
- `reachedAt`
- `completedAt`

Code-supported stop item keys not observed in the current sample:

- `distanceFromRouteMeters`
- `etaToStopMinutes`

### bookings/{bookingId}/statusHistory

Live-observed through collection-group query.

Live sample: 25 documents.

- `from`: string
- `to`: string
- `changedBy`: string
- `source`: string
- `timestamp`: timestamp

## bookings_archive

Purpose: terminal-state booking mirror for history and retention.

Live sample: 25 documents.

Live-observed fields mostly mirror `bookings`, with archive metadata:

- `archivedAt`: timestamp
- `archivedStatus`: string

Live-observed differences from active `bookings`:

- `totalFare` appears as double or integer in the archive sample.
- `bookings_archive` had no sampled subcollections.

## tracking

Purpose: high-frequency operator location updates for active bookings.

Live sample: 18 documents.

- `bookingId`: string
- `operatorUid`: string
- `operatorLat`: double
- `operatorLng`: double
- `updatedAt`: timestamp

## users

Live sample: 3 documents.

- `uid`: string; observed on 2/3 sampled docs
- `name`: string
- `email`: string
- `phoneNumber`: string
- `createdAt`: timestamp
- `updatedAt`: timestamp

## operators

Live sample: 1 document.

- `operatorId`: string public/display ID
- `name`: string
- `email`: string
- `phoneNumber`: string
- `createdAt`: timestamp
- `updatedAt`: timestamp

Note: `isOnline` is deprecated on `operators`. Online state lives in `operator_presence`.

## operator_presence

Live sample: 1 document.

- `isOnline`: boolean
- `updatedAt`: timestamp

## operator_devices

Live sample: 1 document.

- `token`: string
- `platform`: string
- `appRole`: string; expected `operator`
- `updatedAt`: timestamp

## user_devices

Live sample: 4 documents.

- `token`: string
- `platform`: string
- `appRole`: string; expected `passenger`
- `updatedAt`: timestamp

## operator_id_index

Purpose: enforce unique operator display IDs.

Live sample: 1 document.

- `uid`: string
- `operatorId`: string
- `createdAt`: timestamp
- `updatedAt`: timestamp

## order_number_index

Purpose: reserve unique order numbers for payment flows.

Code-supported, not live-observed during this inspection.

- `orderNumber`: string
- `userId`: string
- `reservedAt`: timestamp
- `expiresAt`: timestamp

## fares

Live sample: 25 documents.

- `originJettyId`: string
- `destinationJettyId`: string
- `adultFare`: double
- `childFare`: double or integer

Code-supported optional labels:

- `origin`
- `destination`

## jetties

Live sample: 14 documents.

- `name`: string
- `lat`: double
- `lng`: double

Note: document ID is the canonical `jettyId` used by runtime code.

## polylines

Live sample: 1 document.

- `type`: string
- `path`: array of GeoPoints
- `properties`: map; live sample included `city` and `route_name`
- `uploadedAt`: timestamp

Code-supported legacy variants:

- `coordinates`
- `polyline`
- `geometry`
- `properties.originJettyId`
- `properties.destinationJettyId`

## payment_webhooks

Purpose: Stripe webhook audit log.

Code-supported, not live-observed during this inspection.

- `provider`
- `eventId`
- `eventType`
- `paymentIntentId`
- `status`
- `orderNumber`
- `payload`
- `receivedAt`

## webhook_events

Purpose: Stripe webhook idempotency tracker.

Code-supported, not live-observed during this inspection.

- `processedAt`

## Notes For Future Schema Audits

- Live inspection is sample-based. A field absent from this document is not guaranteed absent from Firestore.
- Code-supported fields are included when models/functions read or write them, even if the live sample did not contain them.
- Re-run the live inspection after major DRT field migrations, payment flow changes, or archive cleanup changes.
