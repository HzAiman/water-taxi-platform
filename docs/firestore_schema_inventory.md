# Firestore Schema Inventory (Live Collections)

Last updated: 2026-04-12
Project: melaka-water-taxi
Database: (default)
Source: live Firestore introspection via scripts/introspect_firestore_schema.js

## Collection Inventory (Live)

Top-level collections currently present in Firebase:
- bookings
- bookings_archive
- fares
- jetties
- operator_devices
- operator_presence
- operators
- order_number_index
- polylines
- user_devices
- users

## Entity Relationships

Primary document identities:
- users/{uid}
- operators/{uid}
- operator_presence/{uid}
- user_devices/{uid}
- operator_devices/{uid}
- bookings/{bookingId}
- bookings_archive/{bookingId}
- jetties/{jettyId}
- fares/{fareDocId}
- order_number_index/{orderNumber}
- polylines/{routeId}

Logical relationships:
- bookings.userId -> users document id
- bookings.operatorUid -> operators document id
- bookings.operatorId -> mirrors operator uid for compatibility in current runtime
- bookings.originJettyId -> jetties document id
- bookings.destinationJettyId -> jetties document id
- bookings.fareSnapshotId -> fares document id used at booking time
- bookings.routePolylineId -> polylines document id
- bookings.orderNumber -> order_number_index document id
- bookings_archive is a terminal-state mirror of bookings for completed/cancelled lifecycle records
- operator_presence/{uid} is the online-state companion document for operators/{uid}

## Collection Structures And Field Functions

## 1) bookings

Purpose:
- Active booking lifecycle records used by passenger and operator apps.

Live fields:
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
- orderNumber: payment/order reference that maps to order_number_index.
- transactionId: gateway transaction or payment intent id.
- status: booking lifecycle status (pending, accepted, on_the_way, completed, cancelled, rejected).
- operatorUid: assigned operator uid (null while unassigned).
- operatorId: compatibility mirror of operator uid in current write paths.
- operatorLat: last known operator latitude during active tracking.
- operatorLng: last known operator longitude during active tracking.
- rejectedBy: list of operator uids that rejected the pending booking.
- createdAt: server timestamp at booking creation.
- updatedAt: server timestamp for latest mutation.
- cancelledAt: timestamp when booking moved to cancelled status.

## 2) bookings_archive

Purpose:
- Terminal-state booking mirror for retention and historical reads.

Live fields:
- Includes booking fields from source booking at archive time.
- archivedAt: timestamp when record was archived.
- archivedStatus: terminal status captured during archive write.

Behavior:
- Created when booking becomes terminal (completed/cancelled in current runtime paths).
- Read-only in client rules; used for historical views and retention jobs.

## 3) fares

Purpose:
- Fare matrix keyed by route pair for booking pricing.

Live fields:
- originJettyId: canonical origin jetty reference.
- destinationJettyId: canonical destination jetty reference.
- adultFare: per-adult fare amount.
- childFare: per-child fare amount.

Behavior:
- Passenger app performs strict id-based fare lookups using originJettyId + destinationJettyId.

## 4) jetties

Purpose:
- Canonical jetty catalog for routing, pricing references, and map display.

Live fields:
- name: display name of jetty.
- lat: latitude coordinate.
- lng: longitude coordinate.
- jettyId: legacy embedded id still present in live docs.

Identity note:
- Document id is already the canonical jetty key used by runtime code.
- Embedded jettyId remains in live data as migration residue and can be removed later.

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

Relationship:
- operator_presence/{uid} pairs one-to-one with operators/{uid}.

## 7) operator_devices

Purpose:
- Operator FCM device token registry for push notifications.

Live fields:
- token: FCM registration token.
- platform: device platform (android/ios/web).
- appRole: role discriminator, expected operator.
- updatedAt: last token refresh timestamp.

## 8) users

Purpose:
- Passenger profile keyed by Firebase Auth uid.

Live fields:
- name: passenger display name.
- email: passenger email.
- phoneNumber: passenger contact number.
- createdAt: profile creation timestamp.
- updatedAt: profile update timestamp.

Live note:
- No redundant uid field is currently present in sampled users docs.

## 9) user_devices

Purpose:
- Passenger FCM device token registry for push notifications.

Live fields:
- token: FCM registration token.
- platform: device platform.
- appRole: role discriminator, expected passenger.
- updatedAt: last token refresh timestamp.

## 10) order_number_index

Purpose:
- Reservation ledger to enforce unique order numbers before payment/booking writes.

Live fields:
- orderNumber: reserved order number (mirrors document id).
- userId: uid that reserved the order number.
- reservedAt: reservation timestamp.

Relationship:
- bookings.orderNumber should match an existing order_number_index document id.

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
- status ASC, operatorId ASC, createdAt ASC
- operatorId ASC, status ASC, updatedAt DESC
- userId ASC, createdAt DESC
- userId ASC, status ASC, updatedAt DESC

Collection group fares:
- origin ASC, destination ASC
- originJettyId ASC, destinationJettyId ASC

fieldOverrides:
- none
