# Firebase Functions (Payments + Pooling + Notifications)

This module contains the Cloud Functions backend for payment lifecycle, pooled dispatch, and FCM notifications. Functions run as Gen 2 Cloud Functions in region asia-southeast1 using Node.js 22.

## Environment parameters

- STRIPE_SECRET_KEY
- STRIPE_WEBHOOK_SECRET
- STRIPE_CURRENCY (default myr)
- MIGRATION_ADMIN_UIDS
- BOOKING_ARCHIVE_RETENTION_DAYS

## Core functions

### Operator profile

- saveOperatorProfile (callable): Creates/updates operators/{uid}, claims operator_id_index/{operatorId}, and syncs operator_presence.

### Pooling and DRT

- acceptPooledBooking (callable): Validates eligibility, assigns poolGroupId/sequence/stop plan.
- rejectPooledBooking (callable): Rejects a pending booking for the current operator, including while mid-trip.
- startPooledBooking (callable): Starts the first current pool-stop booking, returns startedBookingId, and enforces one on_the_way booking.
- markPoolStopReached (callable): Completes pool pickup/dropoff stops, updates poolStopPlan and booking status.
- completePooledBooking (callable): Completes an on_the_way booking and archives it.
- replanPoolSequenceOnBookingExit (on update): Reorders pooled bookings after a booking leaves the pool.

### Payments

- createStripePaymentIntent (callable, App Check enforced): Creates a manual-capture PaymentIntent.
- createStripePaymentIntentHttp (HTTP): Same as above but verifies Firebase ID token in Authorization header.
- stripeWebhook (HTTP): Validates Stripe signature, writes payment_webhooks, and updates payment status.
- capturePaymentIntent (callable): Manually captures a PaymentIntent.
- cancelPaymentIntent (callable): Cancels an uncaptured intent or refunds a captured one.
- releasePaymentOnBookingRejected (on update): Cancels/refunds on rejected bookings.
- releasePaymentOnBookingCancelled (on update): Cancels/refunds on cancelled bookings.
- capturePaymentOnBookingCompleted (on update): Captures manual-hold payments.
- reconcileStaleAuthorizedPayments (scheduled): Reconciles stale authorized payments.

### Notifications

- notifyOperatorsOnIncomingBooking (on create): Sends FCM to online operators for pending bookings.
- notifyBookingStatusChanged (on update): Sends FCM to passenger and assigned operator when status changes.

### Maintenance

- cleanupOrderNumberIndexOnTerminalBooking (on update): Deletes order_number_index reservation.
- cleanupExpiredOrderNumberReservations (scheduled): Deletes expired order_number_index docs.
- cleanupExpiredBookingArchive (scheduled): Deletes bookings_archive past retention.
- rejectStalePendingBookingsWithoutOnlineOperators (scheduled): Rejects stale pending bookings when no operators are online.
- releaseStaleAcceptedPooledBookings (scheduled): Releases accepted pooled bookings after staleAcceptedMinutes.

### Migrations

- backfillJettyIds (HTTP): Backfills originJettyId/destinationJettyId on fares and bookings.
- cleanupLegacyOperatorOnlineField (HTTP): Removes deprecated operators.isOnline field.

## Collections used

- bookings, bookings_archive, tracking, operator_presence, operator_devices, user_devices
- order_number_index, operator_id_index
- fares, jetties, operators, polylines, users
- payment_webhooks (Stripe audit log)
- webhook_events (Stripe idempotency tracker)

## Local setup

```bash
cd apps/passenger_app/functions
npm install
```

Emulator run:

```bash
cd apps/passenger_app
firebase emulators:start --only functions,firestore
```

Rules tests:

```bash
cd apps/passenger_app
firebase emulators:exec --only firestore "npm --prefix functions run test:rules"
```

## Deploy

```bash
cd apps/passenger_app
firebase deploy --only functions
```

## Migration invocation (HTTP)

```bash
curl -X POST "https://asia-southeast1-<project-id>.cloudfunctions.net/backfillJettyIds" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"dryRun":true,"limit":200,"collections":["fares","bookings"]}'

curl -X POST "https://asia-southeast1-<project-id>.cloudfunctions.net/cleanupLegacyOperatorOnlineField" \
  -H "Authorization: Bearer <FIREBASE_ID_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"dryRun":true,"limit":200}'
```

Documentation sync: May 2026 (code-aligned update).

