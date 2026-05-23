# Firestore Schema Inventory (Code-Derived)

Last updated: 2026-05-23
Source: code inspection of shared constants, repositories, and Cloud Functions

This inventory is derived from code usage, not a live snapshot. Fields marked as legacy or optional may not exist on every document.

## Top-level collections

- bookings
- bookings_archive
- fares
- jetties
- operator_devices
- operator_presence
- operator_id_index
- operators
- order_number_index
- payment_webhooks
- polylines
- tracking
- user_devices
- users
- webhook_events

## Relationships

- bookings.userId -> users/{uid}
- bookings.operatorUid -> operators/{uid}
- bookings.originJettyId -> jetties/{jettyId}
- bookings.destinationJettyId -> jetties/{jettyId}
- bookings.fareSnapshotId -> fares/{fareDocId}
- bookings.routePolylineId -> polylines/{routeId}
- tracking/{bookingId}.operatorUid -> operators/{uid}
- operator_presence/{uid} is the online state companion to operators/{uid}
- operator_id_index/{operatorId} reserves unique operator display IDs

## bookings

Purpose: Active booking lifecycle records used by both apps.

Core identity and passenger snapshot:

- bookingId (string)
- userId (string)
- userName (string)
- userPhone (string)
- origin, destination (string)
- originJettyId, destinationJettyId (string)

Route geometry:

- originCoords, destinationCoords (GeoPoint)
- routePolylineId (string)
- routePolyline (array of {lat,lng} or GeoPoint-like values)
- routeToOriginPolyline, routeToDestinationPolyline (phase-specific arrays)

Fare and payment:

- adultCount, childCount, passengerCount
- totalFare
- fareSnapshotId
- paymentMethod, paymentStatus
- orderNumber, transactionId

Assignment and status:

- status (pending, accepted, on_the_way, completed, cancelled, rejected)
- operatorUid
- operatorId (legacy alias)
- assignedOperatorName, assignedOperatorDisplayId, assignedOperatorPhone
- rejectedBy (array of operator UIDs)

Pooling and DRT fields:

- pooled, poolGroupId, poolSequence, poolCriteriaVersion, poolMax
- routeDirection (forward/reverse)
- poolEligibilityScore, poolEtaSnapshot
- poolStatus (accepted, in_progress, completed)
- poolStopPlan (array; see below)
- currentStopIndex, currentStopId, currentPoolStopId
- poolPickupStopId, poolDropoffStopId
- poolPhase (waiting_pickup, onboard, dropped_off)
- passengerPickedUpAt, pickedUpAt, droppedOffAt, completedAt
- onboard (bool)
- poolDeferredForOperatorUid, poolDeferredRouteDirection
- poolDeferredPoolGroupId, poolDeferredReason
- poolDeferredUntil, poolDeferredAt

Location snapshots:

- operatorLat, operatorLng

Timestamps:

- createdAt, updatedAt, cancelledAt

Stop plan item shape (poolStopPlan array):

- stopId, stopIndex
- stopType (pickup/dropoff)
- jettyId, jettyName, stopName
- lat, lng
- routePositionMeters, distanceFromRouteMeters
- bookingIds (array)
- status (pending/active/completed/skipped)
- etaToStopMinutes
- reachedAt, completedAt

Subcollections:

- bookings/{bookingId}/statusHistory (from/to/changedBy/source/timestamp)

## bookings_archive

Purpose: Terminal-state booking mirror for history and retention.

- All booking fields copied at archive time
- archivedAt
- archivedStatus

## tracking

Purpose: High-frequency operator location updates for active bookings.

- bookingId (doc id)
- operatorUid
- operatorLat, operatorLng
- updatedAt

## users

- name, email, phoneNumber
- createdAt, updatedAt

## operators

- operatorId (display ID)
- name, email, phoneNumber
- createdAt, updatedAt

Note: isOnline is deprecated on operators. Online state lives in operator_presence.

## operator_presence

- isOnline
- updatedAt

## operator_devices / user_devices

- token
- platform (android/ios/unknown)
- appRole (operator/passenger)
- updatedAt

## operator_id_index

Purpose: Enforce unique operator display IDs.

- uid
- operatorId
- createdAt, updatedAt

## order_number_index

Purpose: Reserve unique order numbers for payment flows.

- orderNumber
- userId
- reservedAt
- expiresAt

## fares

- originJettyId, destinationJettyId
- adultFare, childFare
- origin, destination (optional legacy labels)

## jetties

- name
- lat, lng

Note: document ID is the canonical jettyId used by runtime code.

## polylines

- path (GeoPoint array)
- coordinates/polyline/geometry (legacy variants)
- properties (may include originJettyId and destinationJettyId)

## payment_webhooks

Purpose: Stripe webhook audit log.

- provider
- eventId, eventType
- paymentIntentId, status
- orderNumber
- payload
- receivedAt

## webhook_events

Purpose: Stripe webhook idempotency tracker.

- processedAt
