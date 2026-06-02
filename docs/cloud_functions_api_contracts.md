# Cloud Functions API Contracts

Last updated: 2026-06-02.

This document describes the callable, HTTP, Firestore-triggered, and scheduled Cloud Functions currently implemented in `apps/passenger_app/functions/index.js`.

Related documents:

- `docs/drt_algorithm_reference.md`
- `docs/stripe_payment_backend_lifecycle.md`
- `docs/push_notifications_features.md`
- `docs/maintenance_and_migration_functions.md`
- `apps/passenger_app/functions/README.md`

## Global Function Defaults

Most functions run in:

- Region: `asia-southeast1`
- Runtime: Gen 2 Cloud Functions
- Node.js: configured by the functions package

The functions module uses:

- Firebase Admin Auth for ID token verification in HTTP endpoints.
- Firebase Admin Firestore for transactional booking, pool, migration, and cleanup writes.
- Firebase Admin Messaging for FCM notifications.
- Stripe SDK for payment lifecycle operations.

## Function Categories

| Category | Functions |
| --- | --- |
| Operator profile | `saveOperatorProfile` |
| Pooling and DRT | `acceptPooledBooking`, `rejectPooledBooking`, `startPooledBooking`, `markPoolStopReached`, `completePooledBooking`, `replanPoolSequenceOnBookingExit` |
| Payments | `createStripePaymentIntent`, `createStripePaymentIntentHttp`, `stripeWebhook`, `capturePaymentIntent`, `cancelPaymentIntent`, payment status triggers, payment reconciliation |
| Notifications | `notifyOperatorsOnIncomingBooking`, `notifyBookingStatusChanged` |
| Maintenance | stale pending rejection, stale accepted release, archive cleanup, order-number cleanup |
| Migrations | `backfillJettyIds`, `cleanupLegacyOperatorOnlineField` |

## Callable Functions

Callable functions require Firebase client SDK callable invocation. Unless noted otherwise, they require `request.auth`.

### `saveOperatorProfile`

Purpose: creates or updates an operator profile, claims a unique operator display ID, and synchronizes the operator presence document.

Region: `asia-southeast1`.

Auth: required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `name` | Yes | Operator display name. |
| `email` | Yes | Operator email. |
| `operatorId` | Yes | Human-facing operator ID. Normalized to uppercase. |
| `phoneNumber` | Yes | Operator phone number. |

Validation:

- all four fields must be non-empty
- `operatorId` must not already be used by another operator
- `operator_id_index/{operatorId}` must be empty or already claimed by the same UID

Firestore reads:

- `operators/{uid}`
- `operator_presence/{uid}`
- `operator_id_index/{operatorId}`
- `operators` query by `operatorId`

Firestore writes:

- upserts `operators/{uid}`
- upserts `operator_id_index/{operatorId}`
- deletes previous `operator_id_index/{previousOperatorId}` if operator ID changed
- upserts `operator_presence/{uid}` with the existing online state or `false`

Response:

```json
{
  "status": "saved",
  "operatorId": "OPERATOR_ID"
}
```

Errors:

| Code | Meaning |
| --- | --- |
| `unauthenticated` | User is not signed in. |
| `invalid-argument` | Required profile field is missing. |
| `already-exists` | Operator ID is already used by another UID. |

### `createStripePaymentIntent`

Purpose: creates a manual-capture Stripe PaymentIntent for passenger booking payment authorization.

Region: `asia-southeast1`.

Auth: required.

App Check: enforced.

Secret: `STRIPE_SECRET_KEY`.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `amount` | Yes | Major currency unit amount. |
| `currency` | Optional | Defaults to `STRIPE_CURRENCY`, then `myr`. |
| `orderNumber` | Yes | Stable order number. |
| `payerName` | Yes | Passenger payer name. |
| `payerEmail` | Yes | Passenger payer email. |
| `payerTelephoneNumber` | Optional | Passenger phone. |
| `idempotencyKey` | Yes | Stripe idempotency key. |
| `description` | Optional | Stripe PaymentIntent description. |

Response:

```json
{
  "status": "ready",
  "paymentIntentId": "pi_...",
  "clientSecret": "pi_..._secret_..."
}
```

See `docs/stripe_payment_backend_lifecycle.md` for the complete payment contract.

### `capturePaymentIntent`

Purpose: manually captures or marks a Stripe PaymentIntent as paid.

Region: `asia-southeast1`.

Auth: required.

App Check: enforced.

Secret: `STRIPE_SECRET_KEY`.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `paymentIntentId` | Yes | Stripe PaymentIntent ID. |
| `orderNumber` | Optional | Booking order number for Firestore update. |

Response:

```json
{
  "status": "captured",
  "paymentIntentId": "pi_..."
}
```

Errors:

- `unauthenticated`
- `invalid-argument`
- `failed-precondition`
- `internal`

### `cancelPaymentIntent`

Purpose: cancels an uncaptured PaymentIntent or refunds a captured one.

Region: `asia-southeast1`.

Auth: required.

App Check: enforced.

Secret: `STRIPE_SECRET_KEY`.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `paymentIntentId` | Yes | Stripe PaymentIntent ID. |
| `orderNumber` | Optional | Booking order number for Firestore update. |
| `reason` | Optional | Cancellation reason. |

Response for uncaptured/cancelled payments:

```json
{
  "status": "cancelled",
  "paymentIntentId": "pi_..."
}
```

Response for captured/refunded payments:

```json
{
  "status": "refunded",
  "paymentIntentId": "pi_...",
  "refundId": "re_...",
  "refundStatus": "..."
}
```

### `acceptPooledBooking`

Purpose: accepts an unassigned pending booking into the authenticated operator's route-aware pool.

Region: `asia-southeast1`.

Auth: required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `bookingId` | Yes | Booking to accept. |
| `operatorLat` | Optional | Current operator latitude used for route eligibility. |
| `operatorLng` | Optional | Current operator longitude used for route eligibility. |
| `routeDirection` | Optional | Requested route direction hint. |

Key validation:

- operator profile must exist
- booking must exist
- booking status must be `pending`
- booking must be unassigned
- operator must not already be in `rejectedBy`
- booking must be inside pickup window
- active pool must not exceed max concurrent booking limit
- operator must not have more than one `on_the_way` booking
- candidate must pass route-aware pooling eligibility

Firestore side effects:

- assigns `status = accepted`
- assigns `operatorUid`
- writes assigned operator display fields
- sets pooling fields such as `pooled`, `poolGroupId`, `poolSequence`, `poolStopPlan`, `poolStatus`, route direction, and ETA snapshot
- clears current-sweep deferral fields
- updates active pool members with shared stop plan and pool metadata
- appends `statusHistory` from `pending` to `accepted`

Response:

```json
{
  "status": "accepted",
  "poolGroupId": "...",
  "poolStatus": "accepted",
  "poolSequence": 1,
  "poolMax": 3,
  "criteriaVersion": "...",
  "sequenceStrategy": "route_aware_completion_cost",
  "eligibilityScore": 0.0,
  "addedEtaMinutes": 0.0
}
```

If the candidate is not currently eligible but should be retried in a later route sweep, the function can return a deferral result instead of throwing. See `docs/drt_algorithm_reference.md`.

Common errors:

| Code | Meaning |
| --- | --- |
| `unauthenticated` | User not signed in. |
| `invalid-argument` | Missing `bookingId`. |
| `permission-denied` | Operator profile missing. |
| `not-found` | Booking missing. |
| `failed-precondition` | Booking not pending, already assigned, too old, pool full, duplicate rejection, invalid route, or operator state violation. |

### `rejectPooledBooking`

Purpose: records that the authenticated operator rejected an unassigned pending booking.

Region: `asia-southeast1`.

Auth: required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `bookingId` | Yes | Booking to reject. |

Behavior:

- reads currently online operators from `operator_presence`
- appends operator UID to `rejectedBy`
- if every online operator has rejected, sets `status = rejected`
- otherwise leaves `status = pending`
- clears current-sweep deferral fields
- appends status history only if status changes

Response:

```json
{
  "status": "pending",
  "bookingId": "...",
  "rejectedBy": ["operatorUid"],
  "fullyRejected": false,
  "message": "Booking rejected. It stays pending for other operators."
}
```

or:

```json
{
  "status": "rejected",
  "bookingId": "...",
  "rejectedBy": ["operatorA", "operatorB"],
  "fullyRejected": true,
  "message": "All online operators declined this request; the passenger will see it as rejected."
}
```

### `startPooledBooking`

Purpose: starts the backend-approved current pool stop booking and enforces the one-active-on-the-way gate.

Region: `asia-southeast1`.

Auth: required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `bookingId` | Yes | Booking the operator is attempting to start. |
| `operatorLat` | Optional | Current operator latitude. |
| `operatorLng` | Optional | Current operator longitude. |

Key behavior:

- validates booking ownership and accepted state
- queries active operator pool
- prevents multiple on-the-way bookings except grouped/onboard stop-plan cases controlled by pool logic
- computes or refreshes route-aware sequence and stop plan
- starts the booking allowed by the current pool stop
- writes `status = on_the_way`, route state, current stop state, and operator location snapshots
- appends status history to `on_the_way`

Response includes started booking details such as `startedBookingId` and pool stop state. See `docs/drt_algorithm_reference.md` for the complete route/stop algorithm.

### `markPoolStopReached`

Purpose: completes the current pickup or dropoff stop in a pooled route.

Region: `asia-southeast1`.

Auth: required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `bookingId` | Yes | Booking used as the handle for the current stop. |
| `operatorLat` | Optional | Current operator latitude. |
| `operatorLng` | Optional | Current operator longitude. |

Behavior:

- validates operator ownership
- resolves current stop from `poolStopPlan`
- validates requested booking is allowed to complete the current stop
- marks pickup stops as picked up/onboard
- marks dropoff stops completed
- archives completed bookings into `bookings_archive`
- advances `currentStopIndex`, `currentStopId`, `currentPoolStopId`, and `poolStatus`
- replans remaining pool state
- appends status history when statuses change

Pickup stop:

- can mark one or multiple booking IDs as onboard if grouped at the same pickup stop
- writes pickup timestamps

Dropoff stop:

- can complete one or multiple booking IDs if grouped at the same dropoff stop
- writes archive docs for completed bookings

### `completePooledBooking`

Purpose: completes an on-the-way booking and writes an archive document.

Region: `asia-southeast1`.

Auth: required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `bookingId` | Yes | Booking to complete. |
| `operatorLat` | Optional | Final operator latitude. |
| `operatorLng` | Optional | Final operator longitude. |

Behavior:

- validates ownership and `on_the_way` status
- writes `status = completed`
- writes `completedAt`, `updatedAt`, optional operator location
- writes `bookings_archive/{bookingId}`
- appends status history
- may replan remaining accepted pool bookings

## HTTP Functions

### `createStripePaymentIntentHttp`

Purpose: HTTP variant of PaymentIntent creation.

Method: POST only.

Auth: Firebase ID token in `Authorization: Bearer <ID_TOKEN>`.

Request body: same logical fields as `createStripePaymentIntent`.

Success:

```json
{
  "status": "ready",
  "paymentIntentId": "pi_...",
  "clientSecret": "pi_..._secret_..."
}
```

Failure:

| HTTP Status | Meaning |
| --- | --- |
| `405` | Non-POST method. |
| `401` | Missing/invalid auth token. |
| `400` | Validation error. |
| `500` | Stripe secret missing or payment creation failed. |

### `stripeWebhook`

Purpose: Stripe webhook receiver.

Method: POST only.

Auth: Stripe signature verification through `STRIPE_WEBHOOK_SECRET`.

Supported event effects:

| Event | Effect |
| --- | --- |
| `payment_intent.succeeded` | Updates matching booking payment status to `paid`. |
| `payment_intent.amount.capturably_held` | Updates matching booking payment status to `authorized`. |

All accepted events are written to `payment_webhooks`; event IDs are tracked in `webhook_events`.

### `backfillJettyIds`

Purpose: admin migration endpoint that backfills `originJettyId` and `destinationJettyId` on fares and bookings.

Method: POST.

Auth: Firebase ID token, UID must be in `MIGRATION_ADMIN_UIDS`.

Request body:

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `dryRun` | No | `true` | If true, returns proposed changes without writing. |
| `limit` | No | `200` | Page size, clamped between 1 and 500. |
| `startAfter` | No | empty | Document ID cursor. |
| `collections` | No | `["fares", "bookings"]` | Allowed collections are `fares` and `bookings`. Can be array or comma-separated string. |

### `cleanupLegacyOperatorOnlineField`

Purpose: admin migration endpoint that removes deprecated `operators.isOnline`.

Method: POST.

Auth: Firebase ID token, UID must be in `MIGRATION_ADMIN_UIDS`.

Request body:

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `dryRun` | No | `true` | If true, reports changes without writing. |
| `limit` | No | `200` | Page size, clamped between 1 and 500. |
| `startAfter` | No | empty | Document ID cursor. |

## Firestore Trigger Functions

### `replanPoolSequenceOnBookingExit`

Trigger: `bookings/{bookingId}` update.

Purpose: replans an operator's remaining accepted/on-the-way pool after a booking leaves the pool.

Runs when:

- previous status was `accepted` or `on_the_way`
- new status is not still in the same pool for the same operator
- previous booking had an operator UID

Effect:

- calls route-aware replanning for the previous operator
- preserves completed stops where possible
- updates sequence and stop-plan metadata for remaining pool bookings

### `notifyOperatorsOnIncomingBooking`

Trigger: `bookings/{bookingId}` create.

Purpose: sends incoming booking FCM to online operators.

Runs when:

- new booking data exists
- `status == pending`

Reads:

- `operator_presence` where `isOnline == true`
- `operator_devices/{operatorUid}`

Sends:

```json
{
  "type": "incoming_booking",
  "bookingId": "...",
  "status": "pending"
}
```

See `docs/push_notifications_features.md`.

### `notifyBookingStatusChanged`

Trigger: `bookings/{bookingId}` update.

Purpose: sends booking status FCM to passenger and assigned operator.

Runs when:

- before and after data exist
- `status` changed

Passenger data payload:

```json
{
  "type": "booking_status",
  "bookingId": "...",
  "status": "...",
  "origin": "...",
  "destination": "...",
  "passengerCount": "1"
}
```

Operator data payload:

```json
{
  "type": "booking_status",
  "bookingId": "...",
  "status": "..."
}
```

Invalid FCM tokens are removed from `user_devices` or `operator_devices`.

### Payment Status Triggers

| Function | Trigger | Purpose |
| --- | --- | --- |
| `releasePaymentOnBookingRejected` | booking update to `rejected` | Cancels/refunds Stripe payment. |
| `releasePaymentOnBookingCancelled` | booking update to `cancelled` | Cancels/refunds Stripe payment. |
| `capturePaymentOnBookingCompleted` | booking update to `completed` | Captures Stripe payment or marks already paid. |
| `cleanupOrderNumberIndexOnTerminalBooking` | booking update to terminal status | Deletes `order_number_index/{orderNumber}`. |

See `docs/stripe_payment_backend_lifecycle.md`.

## Scheduled Functions

| Function | Schedule | Purpose |
| --- | --- | --- |
| `reconcileStaleAuthorizedPayments` | every 30 minutes | Captures completed authorized bookings and releases cancelled/rejected authorized bookings. |
| `rejectStalePendingBookingsWithoutOnlineOperators` | every minute | Rejects stale unassigned pending bookings when no operators are online. |
| `releaseStaleAcceptedPooledBookings` | every 5 minutes | Releases stale accepted pooled bookings that were never started. |
| `cleanupExpiredBookingArchive` | every day 02:00 | Deletes old archive docs past retention. |
| `cleanupExpiredOrderNumberReservations` | every 30 minutes | Deletes expired abandoned order-number reservations. |

See `docs/maintenance_and_migration_functions.md`.

## Common Error Semantics

Callable functions mostly use:

| Code | Meaning |
| --- | --- |
| `unauthenticated` | User must sign in. |
| `invalid-argument` | Required payload field missing or malformed. |
| `permission-denied` | Signed-in user lacks required profile/role. |
| `not-found` | Target booking/profile/document missing. |
| `failed-precondition` | The requested state transition is not valid now. |
| `already-exists` | Unique identifier collision. |
| `internal` | Backend or third-party operation failed. |

## Authorization Model

Callable functions rely on Firebase Auth and, for some functions, profile existence:

- Operator-only lifecycle functions require `request.auth` and usually verify `operators/{uid}`.
- Payment functions require `request.auth`; callable payment functions also enforce App Check.
- Migration HTTP functions require a valid ID token and membership in `MIGRATION_ADMIN_UIDS`.
- Firestore triggers and schedules run as backend service code and are not restricted by Firestore security rules.

## Contract Boundaries

- Cloud Functions are the source of truth for backend-owned pooling and payment transitions.
- Firestore rules still permit some client-side compatibility transitions, but the intended app flow increasingly uses callable functions for route-aware safety.
- Function responses are intentionally compact; clients mostly re-read Firestore streams after actions.
- Payment and DRT contracts are documented separately because their internal algorithms are larger than this API surface.
