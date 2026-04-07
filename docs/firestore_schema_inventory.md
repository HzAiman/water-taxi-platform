# Firestore Schema Inventory (Live Collections)

Last updated: 2026-04-07
Project: melaka-water-taxi
Database: (default)

## Collection Inventory

Top-level collections:
- bookings
- fares
- jetties
- operator_devices
- operator_id_claims
- operator_presence
- operators
- polylines
- user_devices
- users

## Schema Review Notes

Priority migration items identified during review:

1. Booking fare denormalization
- Current bookings store `adultFare`, `childFare`, `adultSubtotal`, `childSubtotal`, `fare`, and `totalFare`.
- Recommended direction: keep only the final booking total plus a `fareSnapshotId` that points to the fare document used at booking time.
- If subtotals are needed for display, derive them from the snapshot instead of storing multiple copies on the booking.

2. Operator online state duplication
- `operator_presence.isOnline` and `operators.isOnline` currently duplicate the same state.
- Recommended direction: keep online state only in `operator_presence` and remove `isOnline` from `operators`.
- `operator_presence` is the better fit for high-frequency presence writes.

3. Legacy booking polyline fields
- `routeCoordinates`, `polylineCoordinates`, and `routePoints` are legacy compatibility fields alongside `routePolyline`.
- Recommended direction: consolidate booking route storage to one canonical reference, ideally a `polylines` document id instead of embedding geometry in every booking.
- Keep legacy reads during migration, but stop writing the older variants for new bookings.

4. Booking status history
- Current bookings do not retain an audit trail for status transitions.
- Recommended direction: add a `bookings/{id}/statusHistory` subcollection with records shaped like `{ from, to, changedBy, timestamp }`.
- This would provide a durable dispute timeline without changing the main booking document.

5. Rejection tracking
- `rejectedBy` is currently a booking field, but its query semantics are not documented.
- Recommended direction: clarify whether it stores operator UIDs, or move rejection events into a per-booking subcollection if you need efficient operator-based queries.

6. Passenger snapshot fields
- `userName` and `userPhone` on bookings may intentionally act as a receipt snapshot, but that intent is not documented.
- Recommended direction: document snapshot semantics explicitly, or add a backfill path if booking records must always mirror the latest profile data.

7. Booking archival
- Completed and cancelled bookings will grow without bound.
- Recommended direction: define an archival policy, such as moving old bookings to `bookings_archive` or exporting them to BigQuery after N days.

8. Order number uniqueness
- `orderNumber` is not protected by a Firestore unique constraint.
- Recommended direction: enforce uniqueness in application code with a transaction-backed order index or counter collection.

Quick wins that can be applied with low risk:
- Drop `isOnline` from `operators` and keep presence state in `operator_presence` only.
- Stop writing the legacy booking polyline fields on new writes, while continuing to read them until migration completes.
- Add the `statusHistory` subcollection as an additive audit trail.

## Migration Plan

Phase 1: Stop the drift sources
- Remove `operators.isOnline` from new writes and treat `operator_presence.isOnline` as the single source of truth.
- Stop writing `routeCoordinates`, `polylineCoordinates`, and `routePoints` on new bookings.
- Add `bookings/{id}/statusHistory` for all future status changes.

Phase 2: Tighten booking snapshots
- Replace the repeated fare fields on bookings with a single `totalFare` plus `fareSnapshotId`.
- Document whether `userName` and `userPhone` are immutable booking snapshots or should be backfilled.
- Clarify `rejectedBy` semantics and decide whether it should remain a field or move into a subcollection.

Phase 3: Normalize route storage
- Move booking route references from embedded geometry to a canonical `polylines` document reference.
- Keep legacy read paths in place until older booking records are migrated or expired.

Phase 4: Lifecycle and retention
- Define a booking archival policy for completed and cancelled records.
- Add an application-level uniqueness strategy for `orderNumber` using a transactional index or counter collection.

Suggested acceptance criteria:
- No new booking writes include the deprecated polyline fields.
- No new operator profile writes set `isOnline`.
- Status changes append a `statusHistory` event.
- Booking reads still tolerate legacy polyline documents until migration is complete.

## 1) bookings

Purpose:
- Main booking and trip lifecycle record shared by passenger and operator apps.

Core fields:
- bookingId
- userId, userName, userPhone
- origin, destination
- originCoords, destinationCoords
- routePolyline
- routeCoordinates, polylineCoordinates, routePoints (legacy compatibility)
- adultCount, childCount, passengerCount
- adultFare, childFare, adultSubtotal, childSubtotal, fare, totalFare
- paymentMethod, paymentStatus, orderNumber, transactionId
- status
- operatorUid, operatorId
- operatorLat, operatorLng
- rejectedBy
- createdAt, updatedAt, cancelledAt

Allowed statuses:
- pending
- accepted
- on_the_way
- completed
- cancelled
- rejected

## 2) fares

Purpose:
- Read-only fare matrix used for booking fare calculation.

Fields:
- origin
- destination
- adultFare
- childFare

## 3) jetties

Purpose:
- Canonical jetty reference collection used for route endpoints and fare routing.

Fields:
- id (document id)
- jettyId
- name
- lat
- lng

Provided live sample data:

```js
[
  {
    id: '1cQd9jEgT6bZ5xjEjST6',
    lat: 2.204444,
    lng: 102.251111,
    jettyId: 17,
    name: 'Kampung Morten'
  },
  {
    id: '8dLpTjjE8y27oHtP1n2A',
    lat: 2.194722,
    lng: 102.249167,
    jettyId: 24,
    name: 'Stadthuys'
  },
  {
    id: 'JULNcZwJD335p9G6eCgx',
    lat: 2.201111,
    lng: 102.248333,
    jettyId: 19,
    name: 'Hang Tuah'
  },
  {
    id: 'P5lCnwtLXK3UCdELx1JV',
    lat: 2.197222,
    lng: 102.249722,
    jettyId: 22,
    name: 'Kampung Jawa'
  },
  {
    id: 'XKtzPUWWHnPReaWxE40G',
    lat: 2.1925,
    lng: 102.246111,
    jettyId: 27,
    name: 'Samudera'
  },
  {
    id: 'XXJxO2q7VQiQ114T6Y0K',
    lat: 2.193056,
    lng: 102.246111,
    jettyId: 28,
    name: 'Casa Del Rio'
  },
  {
    id: 'c5APELyNgUYNLJIhaiH1',
    lat: 2.197222,
    lng: 102.249722,
    jettyId: 23,
    name: 'RC Hotel'
  },
  {
    id: 'dhF203XK3FH4eGPoAcAq',
    lat: 2.207222,
    lng: 102.251389,
    jettyId: 15,
    name: 'Taman Rempah'
  },
  {
    id: 'gK74ihhwwrjEpxc7nGBh',
    lat: 2.205278,
    lng: 102.251111,
    jettyId: 16,
    name: 'The Pines'
  },
  {
    id: 'ijuQjIA2BSWeaCbpc3YH',
    lat: 2.199167,
    lng: 102.248056,
    jettyId: 21,
    name: 'Kampung Hulu'
  },
  {
    id: 'im4IQfbaOHIVbpGHDge1',
    lat: 2.193056,
    lng: 102.246944,
    jettyId: 26,
    name: 'Quayside'
  },
  {
    id: 'qufstm9BaDtyaZ2Qrl5v',
    lat: 2.201667,
    lng: 102.249444,
    jettyId: 18,
    name: 'The Shore'
  },
  {
    id: 'sHsgrz2A7ObJ4hYmhfID',
    lat: 2.199444,
    lng: 102.248333,
    jettyId: 20,
    name: 'Tun Fatimah'
  },
  {
    id: 'va6Fovlb3abJ19jFwROG',
    lat: 2.194722,
    lng: 102.248889,
    jettyId: 25,
    name: 'Hard Rock'
  }
]
```

## 4) operator_devices

Purpose:
- Operator FCM registration/token docs.

Fields:
- token
- platform
- appRole
- updatedAt

## 5) operator_id_claims

Purpose:
- Ownership mapping for operator IDs.

Fields:
- uid
- operatorId
- operatorIdKey
- createdAt
- updatedAt

## 6) operator_presence

Purpose:
- Online/offline signal for operators.

Fields:
- isOnline
- updatedAt

## 7) operators

Purpose:
- Operator profile document keyed by auth uid.

Fields:
- operatorId
- operatorIdKey
- name
- email
- isOnline
- createdAt
- updatedAt

## 8) polylines

Purpose:
- River route geometry collection used for map path representation.

Fields:
- id (document id)
- path
- type
- properties
- uploadedAt

Provided live sample data:

```js
[
  {
    id: 'route_1',
    path: [
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint], [GeoPoint], [GeoPoint],
      [GeoPoint]
    ],
    type: 'LineString',
    properties: { route_name: 'Melaka River Path', city: 'Melaka' },
    uploadedAt: Timestamp { _seconds: 1775497683, _nanoseconds: 380000000 }
  }
]
```

## 9) user_devices

Purpose:
- Passenger FCM registration/token docs.

Fields:
- token
- platform
- appRole
- updatedAt

## 10) users

Purpose:
- Passenger profile document keyed by auth uid.

Fields:
- uid
- name
- email
- phoneNumber
- createdAt
- updatedAt

## Live Composite Indexes Retrieved

Collection group bookings:
- status ASC, operatorId ASC, createdAt ASC
- operatorId ASC, status ASC, updatedAt DESC
- userId ASC, createdAt DESC
- userId ASC, status ASC, updatedAt DESC

Collection group fares:
- origin ASC, destination ASC

fieldOverrides:
- none
