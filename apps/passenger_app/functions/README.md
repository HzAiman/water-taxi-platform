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

#### `cleanupOrderNumberIndexOnTerminalBooking`
- **Trigger:** `bookings/{bookingId}` on update
- **Condition:** status transition into terminal state (`completed`, `cancelled`, `rejected`)
- **Action:** delete `order_number_index/{orderNumber}` when present to prevent stale reservation buildup.

#### `cleanupExpiredBookingArchive` (scheduled)
- **Schedule:** daily at 02:00 (`Asia/Kuala_Lumpur`)
- **Purpose:** enforce `bookings_archive` retention by deleting docs with `archivedAt` older than configured cutoff.
- **Config:** `BOOKING_ARCHIVE_RETENTION_DAYS` (default `180` if unset/invalid).
- **Batch size:** up to 300 docs per run.

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

### Data Migration

#### `backfillJettyIds` (HTTP)
- **Purpose:** Backfill canonical `originJettyId` and `destinationJettyId` in existing `fares` and `bookings` documents.
- **Security:** verifies Firebase ID token from `Authorization: Bearer ...` and allows only UIDs in `MIGRATION_ADMIN_UIDS`.
- **Safety:** supports `dryRun` mode, pagination (`startAfter`), and bounded page size (`limit`, max 500).

Request body:

```json
{
  "dryRun": true,
  "limit": 200,
  "startAfter": "",
  "collections": ["fares", "bookings"]
}
```

Response payload includes per-collection stats (`scanned`, `updated`, `unresolved`, `nextCursor`, `done`) so you can run the migration iteratively.

#### `cleanupLegacyOperatorOnlineField` (HTTP)
- **Purpose:** Remove legacy `operators.isOnline` from stored operator profile documents.
- **Security:** verifies Firebase ID token from `Authorization: Bearer ...` and allows only UIDs in `MIGRATION_ADMIN_UIDS`.
- **Safety:** supports `dryRun` mode, pagination (`startAfter`), and bounded page size (`limit`, max 500).

Request body:

```json
{
  "dryRun": true,
  "limit": 200,
  "startAfter": ""
}
```

## Observability Signals

Error logs include alert tags to support logs-based metrics and alerting:

- `PAYMENT_RELEASE_FAILED`
- `PAYMENT_CAPTURE_FAILED`
- `PAYMENT_RECONCILE_FAILED`
- `ORDER_INDEX_CLEANUP_FAILED`

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

Run Firestore Security Rules tests (emulator-backed):

```bash
cd apps/passenger_app
firebase emulators:exec --only firestore "npm --prefix functions run test:rules"
```

## Deploy

Deploy functions only:

```bash
cd apps/passenger_app
firebase deploy --only functions
```

Set migration admin allowlist before running backfill:

```bash
cd apps/passenger_app
firebase functions:params:set MIGRATION_ADMIN_UIDS="uid_1,uid_2"
firebase functions:params:set BOOKING_ARCHIVE_RETENTION_DAYS="180"
firebase deploy --only functions
```

Invoke migration (dry-run first):

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

Alternative execution path (admin CLI runner):

```bash
cd apps/passenger_app/functions
npm run migrate:schema:dry-run
npm run migrate:schema:apply
```

For production project execution:

```bash
cd apps/passenger_app/functions
npm run migrate:schema:dry-run:prod
npm run migrate:schema:apply:prod
```

Credential requirement for CLI runner:
- The runner uses Firebase Admin SDK Application Default Credentials.
- Before running against production, authenticate ADC (for example with `gcloud auth application-default login`) or set `GOOGLE_APPLICATION_CREDENTIALS` to a service-account key.

Optional scope control:

```bash
node ./scripts/execute_schema_backfills.js --dry-run true --collections operators
node ./scripts/execute_schema_backfills.js --dry-run true --collections operator_id_claims
node ./scripts/execute_schema_backfills.js --dry-run true --collections jetties,fares,bookings --page-size 200
node ./scripts/execute_schema_backfills.js --dry-run true --collections fares,bookings --page-size 200
```

`jetties` collection mode behavior:
- Re-keys documents to canonical `jetties/{jettyId}` when legacy doc IDs differ.
- Removes redundant embedded `jettyId` / `id` fields from stored jetty docs.
- Remaps `originJettyId` and `destinationJettyId` references in `fares` and `bookings` when IDs changed.
- Stops with a collision report if multiple source docs resolve to the same target `jettyId`.

Deploy functions together with Firestore rules and indexes:

```bash
firebase deploy --only firestore:rules,firestore:indexes,functions
```

## Notes

- The functions are deployed to `asia-southeast1` to match the Firebase project region (`melaka-water-taxi`).
- This project uses Node.js 22 as specified in `functions/package.json`.
- Cloud artifact cleanup is set to 7 days to avoid stale build artifacts accumulating in Artifact Registry.

Documentation sync: March 2026.

