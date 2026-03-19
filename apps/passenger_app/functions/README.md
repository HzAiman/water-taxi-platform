# Firebase Functions (Payments + Notifications)

This module contains the Cloud Functions backend for payment lifecycle, payment reconciliation, and FCM push notifications. Functions run as Gen 2 Cloud Functions in region `asia-southeast1` using Node.js 22.

## Implemented Functions

### Payments

#### `createStripePaymentIntent` (callable)
- **Purpose:** Create a Stripe PaymentIntent with manual capture (hold-first flow).
- **Security:** requires Firebase Auth and App Check (`enforceAppCheck: true`).

#### `createStripePaymentIntentHttp` (HTTP)
- **Purpose:** HTTP variant for payment intent initialization from the mobile app flow.
- **Security:** verifies Firebase ID token from `Authorization: Bearer ...` header.

#### `stripeWebhook` (HTTP)
- **Purpose:** Process Stripe events and sync booking payment status.
- **Requirement:** `STRIPE_WEBHOOK_SECRET` must be configured; unsigned events are rejected.

#### `capturePaymentIntent` (callable)
- **Purpose:** Capture an authorized hold when booking/trip is completed.

#### `cancelPaymentIntent` (callable)
- **Purpose:** Cancel or refund payment intent depending on current Stripe status.

#### `releasePaymentOnBookingRejected`
- **Trigger:** `bookings/{bookingId}` on update
- **Condition:** status transition to `rejected`
- **Action:** release/refund payment and update booking payment state.

#### `releasePaymentOnBookingCancelled`
- **Trigger:** `bookings/{bookingId}` on update
- **Condition:** status transition to `cancelled`
- **Action:** release/refund payment and update booking payment state.

#### `capturePaymentOnBookingCompleted`
- **Trigger:** `bookings/{bookingId}` on update
- **Condition:** status transition to `completed`
- **Action:** capture hold (or mark paid if already captured).

#### `reconcileStaleAuthorizedPayments` (scheduled)
- **Schedule:** every 30 minutes (`Asia/Kuala_Lumpur`)
- **Purpose:** reconcile stale `authorized` bookings for terminal statuses to avoid stuck uncaptured holds.
- **Summary log fields:** `scanned`, `released`, `captured`, `skipped`, `failed`.

### Notifications

### `notifyOperatorsOnIncomingBooking`
- **Trigger:** `bookings/{bookingId}` on create
- **Condition:** booking status is `pending`
- **Action:** query `operator_presence` for operators where `isOnline == true`, fetch their FCM tokens from `operator_devices/{operatorUid}`, and send a push notification to each.

### `notifyBookingStatusChanged`
- **Trigger:** `bookings/{bookingId}` on update
- **Condition:** booking `status` field changed
- **Action:**
  - Send FCM to the passenger token in `user_devices/{userId}` with a data payload that includes `bookingId`, `status`, `origin`, `destination`, and `passengerCount` to support deep-link navigation.
  - Send FCM to the assigned operator token in `operator_devices/{operatorUid}` if an `operatorId` is present on the booking.

Assignment note:

- Booking assignment now relies on `operatorId` only; legacy `driverId` is no longer used in function logic.

Schema compatibility note:

- Booking documents may now include live tracking fields (`operatorLat`, `operatorLng`) and route polyline fields (`routePolyline` or legacy aliases). These are consumed by clients for map rendering and do not change existing payment trigger conditions.

## Observability Signals

Error logs include alert tags to support logs-based metrics and alerting:

- `PAYMENT_RELEASE_FAILED`
- `PAYMENT_CAPTURE_FAILED`
- `PAYMENT_RECONCILE_FAILED`

## Required Firestore collections

| Collection | Document key | Required fields |
|---|---|---|
| `user_devices` | `{userId}` | `token`, `platform`, `appRole`, `updatedAt` |
| `operator_devices` | `{operatorUid}` | `token`, `platform`, `appRole`, `updatedAt` |
| `operator_presence` | `{operatorUid}` | `isOnline` |

## Local setup

```bash
cd apps/passenger_app/functions
npm install
```

To run with local emulators:

```bash
cd apps/passenger_app
firebase emulators:start --only functions,firestore
```

## Deploy

Deploy functions only:

```bash
cd apps/passenger_app
firebase deploy --only functions
```

Deploy functions together with Firestore rules and indexes:

```bash
firebase deploy --only firestore:rules,firestore:indexes,functions
```

## Notes

- The functions are deployed to `asia-southeast1` to match the Firebase project region (`melaka-water-taxi`).
- This project uses Node.js 22 as specified in `functions/package.json`.
- Cloud artifact cleanup is set to 7 days to avoid stale build artifacts accumulating in Artifact Registry.

Documentation sync: March 2026.

