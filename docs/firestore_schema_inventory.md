# Firestore Schema Inventory (Live Collections)

Last updated: 2026-04-08
Project: melaka-water-taxi
Database: (default)

## Collection Inventory

Top-level collections:
- bookings
- bookings_archive
- fares
- jetties
- order_number_index
- operator_devices
- operator_presence
- operators
- polylines
- user_devices
- users

## Schema Review Notes

Priority migration items identified during review:

1. Booking fare denormalization
- New bookings now store `totalFare` and `fareSnapshotId` only.
- `adultFare`, `childFare`, `adultSubtotal`, `childSubtotal`, and `fare` are legacy fields that may still exist on historical documents, but they are no longer written by the apps.
- If subtotals are needed for display, derive them from the referenced fare snapshot instead of storing multiple copies on the booking.

2. Operator online state duplication
- `operator_presence.isOnline` is the authoritative online state.
- `operators.isOnline` is legacy data only and should not be written or read by runtime code.
- Remaining cleanup: purge any stored legacy `operators.isOnline` values from existing operator documents.
- `operator_presence` is the better fit for high-frequency presence writes.

3. Legacy booking polyline fields
- `routeCoordinates`, `polylineCoordinates`, and `routePoints` are legacy compatibility fields alongside `routePolyline`.
- New bookings now also persist `routePolylineId` as the canonical `polylines` document reference.
- Recommended direction: keep `routePolyline` only as compatibility data until all readers can rely on `routePolylineId`.
- Keep legacy reads during migration, but stop writing the older variants for new bookings.

4. Booking status history
- `bookings/{id}/statusHistory` is now present for status transitions handled by the app repositories.
- Keep this as the canonical audit trail for lifecycle changes.

5. Rejection tracking
- `rejectedBy` stores operator UIDs that have already rejected the booking.
- It is used to keep the booking in `pending` until a non-rejecting operator claims it; if you need a richer audit trail, add a per-booking subcollection rather than overloading the field.

6. Passenger snapshot fields
- `userName` and `userPhone` on bookings are immutable receipt snapshots captured at booking creation.
- They are not backfilled from later profile edits; if the passenger changes their profile, historical bookings keep the original values.

7. Booking archival
- Completed and cancelled bookings will grow without bound.
- Completed and cancelled bookings are mirrored into `bookings_archive` at the point they become terminal.
- Remaining direction: define time-based retention for `bookings_archive` (for example, export to BigQuery after N days).
- Add `order_number_index` cleanup when bookings become terminal so orphaned index docs do not accumulate.

8. Order number uniqueness
- `orderNumber` is not protected by a Firestore unique constraint.
- Recommended direction: enforce uniqueness in application code with a transaction-backed order index or counter collection.

9. Jetty reference integrity
- `fares.origin` and `fares.destination` are string-based and currently depend on mutable jetty names.
- `bookings.origin` and `bookings.destination` are also string labels and can drift from canonical jetty identity.
- Recommended direction: add canonical `originJettyId` and `destinationJettyId` references, then treat name fields as display snapshots.

10. Jetty key canonicalization
- `jetties` should use the Firestore document ID as the canonical key.
- Remove legacy embedded `id` and `jettyId` fields from stored jetty docs; the document ID is the only canonical key.

11. Security Rules documentation and enforcement
- Schema-level access boundaries are not documented in this inventory.
- Recommended direction: add Firestore Security Rules coverage for passengers, operators, presence, bookings, and archive collections, then link rule tests to this document.

Quick wins that can be applied with low risk:
- Drop `isOnline` from `operators` and keep presence state in `operator_presence` only.
- Add canonical jetty ID references (`originJettyId`, `destinationJettyId`) to fares and bookings.
- Add Security Rules documentation and baseline rule tests.

## Implementation Checklist (Post-Review)

Completed:
- Booking writes use `totalFare` and `fareSnapshotId` (legacy fare fields are read-only compatibility).
- Booking status transitions append `bookings/{id}/statusHistory` entries.
- New bookings persist canonical `routePolylineId` and read paths hydrate route geometry from canonical sources with legacy fallback.
- Terminal bookings are mirrored into `bookings_archive`.
- `rejectedBy` semantics are documented as operator UID tracking for pending dispatch.
- `userName` and `userPhone` are documented as immutable booking snapshots.
- Application-level uniqueness guard exists via `order_number_index` reservation.
- Remove `operators.isOnline` read-time fallback assumptions and use `operator_presence` as authoritative online state.
- Booking writes now include canonical `originJettyId` and `destinationJettyId` when jetty metadata is available.
- Backend migration endpoint exists (`backfillJettyIds`) with dry-run, paging, and admin allowlist controls for jetty ID backfill.
- Terminal booking transitions now clean up `order_number_index/{orderNumber}` reservations.
- `bookings_archive` retention cleanup is scheduled with configurable retention days (`BOOKING_ARCHIVE_RETENTION_DAYS`).
- Backend migration endpoint exists (`cleanupLegacyOperatorOnlineField`) to remove stored `operators.isOnline` data with dry-run and paging.
- Firestore Security Rules were updated for canonical booking fields and archive/status-history access boundaries, with automated emulator-backed rules tests.
- Canonical jetty identity strategy is now standardized on `jetties` Firestore document ID for booking/fare references (`originJettyId`, `destinationJettyId`).
- Fare reads are now strict ID-based (`originJettyId` + `destinationJettyId`) with no name-based fallback.
- New booking writes now require `originJettyId` and `destinationJettyId` in every write path.
- Firestore index includes canonical fare lookup on `fares(originJettyId, destinationJettyId)`.
- `statusHistory` entries now include `source` metadata (`passenger_app` / `operator_app`) for transition provenance.
- Booking-history reads are separated by collection; no application query spans both `bookings` and `bookings_archive`.

Incomplete:
- Execute stored `operators.isOnline` cleanup migration on existing operator documents (migration endpoint is ready).
- Execute canonical `originJettyId` and `destinationJettyId` backfill for existing `fares` documents (migration endpoint is ready).
- Execute canonical `originJettyId` and `destinationJettyId` backfill for existing `bookings` documents (migration endpoint is ready).
- Execute one-time physical `jetties/{jettyId}` document-ID migration and remove redundant embedded `jettyId`/`id` fields from stored jetty docs (CLI tooling is ready).
- Remove legacy `operator_id_claims` documents after operator profiles have been re-saved under `operators/{uid}`.

## 1) bookings

Purpose:
- Main booking and trip lifecycle record shared by passenger and operator apps.

Core fields:
- bookingId
- userId, userName, userPhone
- origin, destination (display snapshots)
- originJettyId, destinationJettyId (canonical refs for new writes)
- originCoords, destinationCoords
- routePolylineId
- routePolyline (legacy compatibility)
- routeCoordinates, polylineCoordinates, routePoints (legacy compatibility)
- adultCount, childCount, passengerCount
- totalFare
- fareSnapshotId
- adultFare, childFare, adultSubtotal, childSubtotal, fare (legacy historical only)
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
- origin, destination (legacy name-based lookup)
- originJettyId, destinationJettyId (canonical lookup when populated)
- adultFare
- childFare

## 3) order_number_index

Purpose:
- Application-level uniqueness ledger for payment order numbers.

Fields:
- orderNumber (document id)
- userId
- reservedAt

## 4) jetties

Purpose:
- Canonical jetty reference collection used for route endpoints and fare routing.
- App-level canonical identity for references is the Firestore document ID.

Fields:
- name
- lat
- lng

Migration note:
- Existing stored docs may still contain embedded legacy `id` or `jettyId` fields until the re-key migration is executed.
- After migration, the Firestore document ID is the only canonical jetty identifier.

## 5) operator_devices

Purpose:
- Operator FCM registration/token docs.

Fields:
- token
- platform
- appRole
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
- name
- email
- createdAt
- updatedAt

## 8) polylines

Purpose:
- River route geometry collection used for map path representation.

Fields:
- path
- type
- properties
- uploadedAt

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
- originJettyId ASC, destinationJettyId ASC

fieldOverrides:
- none
