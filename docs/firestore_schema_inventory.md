# Firestore Schema Inventory (Live Collections)

Last updated: 2026-04-12
Project: melaka-water-taxi
Database: (default)
Source: live Firestore introspection via apps/passenger_app/functions/scripts/introspect_firestore_schema.js

## Collection Inventory (Live)

Top-level collections currently present in Firebase:
- bookings
- bookings_archive
- fares     
- jetties
- operator_devices
- operator_presence
- operators
- polylines
- tracking
- user_devices
- users

Note:
- `order_number_index` is not currently present as a top-level collection in this live snapshot.
- This inventory is sample-based (up to 5 docs per collection), so sparse/rare fields may not appear if absent in sampled docs.

## Entity Relationships

Primary document identities:
- users/{uid}
- operators/{uid}
- operator_presence/{uid}
- user_devices/{uid}
- operator_devices/{uid}
- bookings/{bookingId}
- bookings_archive/{bookingId}
- tracking/{bookingId}
- jetties/{jettyId}
- fares/{fareDocId}
- polylines/{routeId}

Logical relationships:
- bookings.userId -> users document id
- bookings.operatorUid -> operators document id
- bookings.originJettyId -> jetties document id
- bookings.destinationJettyId -> jetties document id
- bookings.fareSnapshotId -> fares document id used at booking time
- bookings.routePolylineId -> polylines document id
- tracking.bookingId -> bookings document id
- tracking.operatorUid -> operators document id
- bookings_archive is a terminal-state mirror of bookings for completed/cancelled lifecycle records
- operator_presence/{uid} is the online-state companion document for operators/{uid}

Decision notes:
- `bookings.operatorLat` / `bookings.operatorLng` are snapshot fields written at booking status transitions such as accept, start trip, release, and complete. Live GPS pings belong in `tracking/{bookingId}` and should not be copied back into the booking document on every update.
- `order_number_index` is still the active order-number reservation ledger in code, backed by transaction-based reservation writes plus Stripe idempotency keys. It was empty in the latest live snapshot, so it no longer appears in the top-level collection list, but it has not been replaced by a different uniqueness mechanism.
- `bookings.rejectedBy` remains part of the live dispatch contract because the current model is still broadcast-style: operators can reject a pending booking, and the field tracks who has already declined it.

## Collection Structures And Field Functions

## 1) bookings

Purpose:
- Active booking lifecycle records used by passenger and operator apps.

Live fields (sampled):
- bookingId: immutable booking identifier; expected to match document id.
- userId: owner uid of the passenger who created the booking.
- userName: immutable passenger snapshot used for receipts and operator display.
- userPhone: immutable passenger contact snapshot for trip execution.
- origin: human-readable origin jetty name snapshot.
- destination: human-readable destination jetty name snapshot.
- originJettyId: canonical origin reference to jetties/{jettyId}.
- destinationJettyId: canonical destination reference to jetties/{jettyId}.
- originCoords: GeoPoint for origin map marker and route calculations.
- destinationCoords: GeoPoint for destination map marker and route calculations.
- routePolylineId: canonical route reference to polylines/{routeId}.
- adultCount: number of adult passengers.
- childCount: number of child passengers.
- passengerCount: computed total passengers for display and validation.
- totalFare: final booking fare total used for charging and reconciliation.
- fareSnapshotId: fare document reference used when booking was created.
- paymentMethod: gateway/type metadata (for example, stripe_payment_sheet).
- paymentStatus: payment lifecycle state (authorized, cancelled, etc.).
- orderNumber: payment/order reference.
- transactionId: gateway transaction or payment intent id.
- status: booking lifecycle status.
- operatorUid: assigned operator uid.
- operatorLat: last known operator latitude snapshot on booking doc.
- operatorLng: last known operator longitude snapshot on booking doc.
- rejectedBy: operators that have already declined the pending booking.
- createdAt: server timestamp at booking creation.
- updatedAt: server timestamp for latest mutation.
- cancelledAt: timestamp when booking moved to cancelled status.

## 2) bookings_archive

Purpose:
- Terminal-state booking mirror for retention and historical reads.

Live fields (sampled):
- Includes sampled booking fields from source booking at archive time.
- archivedAt: timestamp when record was archived.
- archivedStatus: terminal status captured during archive write.

Behavior:
- Created when booking becomes terminal.
- Read-only in client rules; used for historical views and retention jobs.

## 3) fares

Purpose:
- Fare matrix keyed by route pair for booking pricing.

Live fields:
- originJettyId: canonical origin jetty reference.
- destinationJettyId: canonical destination jetty reference.
- adultFare: per-adult fare amount.
- childFare: per-child fare amount.

## 4) jetties

Purpose:
- Canonical jetty catalog for routing, pricing references, and map display.

Live fields:
- name: display name of jetty.
- lat: latitude coordinate.
- lng: longitude coordinate.

Live note:
- The embedded `jettyId` field has been removed from live jetties documents.
- Document id is the canonical jetty key used by runtime code.

## 5) operators

Purpose:
- Operator profile keyed by Firebase Auth uid.

Live fields:
- operatorId: business/display identifier (for example, MWT-1).
- name: operator display name.
- email: operator account email.
- createdAt: profile creation timestamp.
- updatedAt: profile update timestamp.

## 6) operator_presence

Purpose:
- Real-time online/offline state for operators.

Live fields:
- isOnline: authoritative availability state.
- updatedAt: latest presence heartbeat/update timestamp.

## 7) operator_devices

Purpose:
- Operator FCM device token registry for push notifications.

Live fields:
- token: FCM registration token.
- platform: device platform (android/ios/web).
- appRole: role discriminator, expected operator.
- updatedAt: last token refresh timestamp.

## 8) tracking

Purpose:
- High-frequency operator location updates for active bookings.

Live fields:
- bookingId: booking reference; expected to match document id.
- operatorUid: assigned operator uid.
- operatorLat: current operator latitude.
- operatorLng: current operator longitude.
- updatedAt: latest tracking update timestamp.

## 9) users

Purpose:
- Passenger profile keyed by Firebase Auth uid.

Live fields:
- name: passenger display name.
- email: passenger email.
- phoneNumber: passenger contact number.
- createdAt: profile creation timestamp.
- updatedAt: profile update timestamp.

## 10) user_devices

Purpose:
- Passenger FCM device token registry for push notifications.

Live fields:
- token: FCM registration token.
- platform: device platform.
- appRole: role discriminator, expected passenger.
- updatedAt: last token refresh timestamp.

## 11) polylines

Purpose:
- River route geometry used for map rendering and route reference.

Live fields:
- path: ordered GeoPoint array for route line geometry.
- type: geometry type (LineString).
- properties: metadata bag (route_name, city, etc.).
- uploadedAt: route upload timestamp.

Relationship:
- bookings.routePolylineId points to polylines/{routeId}.

## Live Composite Indexes

Collection group bookings:
- status ASC, operatorUid ASC, createdAt ASC
- operatorUid ASC, status ASC, updatedAt DESC
- userId ASC, createdAt DESC
- userId ASC, status ASC, updatedAt DESC

Collection group fares:
- originJettyId ASC, destinationJettyId ASC

fieldOverrides:
- none
