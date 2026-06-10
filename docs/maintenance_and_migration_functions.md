# Maintenance And Migration Functions

Last updated: 2026-06-02.

This document explains backend jobs and admin migration endpoints that keep Firestore clean, repair stale lifecycle states, and migrate legacy data.

Related documents:

- `docs/cloud_functions_api_contracts.md`
- `docs/stripe_payment_backend_lifecycle.md`
- `docs/firestore_schema_inventory.md`
- `docs/drt_algorithm_reference.md`

## Purpose

Maintenance functions handle cases that normal user flows do not cover:

- abandoned order number reservations
- stale accepted pooled bookings
- pending bookings left behind when no operators are online
- old archive retention
- stale authorized payments
- legacy schema cleanup
- jetty ID backfills

These functions are safety nets. They reduce the chance that a passenger booking, operator queue, payment hold, or archive collection remains in an inconsistent state indefinitely.

## Scheduled Functions

### `rejectStalePendingBookingsWithoutOnlineOperators`

Schedule: every minute.

Timezone: `Asia/Kuala_Lumpur`.

Region: `asia-southeast1`.

Purpose: rejects stale unassigned pending bookings when no operators are online.

Why it exists:

- A passenger may create a pending booking while operators go offline.
- If no operators are online, the booking should not wait forever.
- Rejection also triggers payment release through `releasePaymentOnBookingRejected`.

High-level behavior:

1. Checks online operators in `operator_presence`.
2. If any operator is online, cleanup skips.
3. If no operators are online, scans pending unassigned bookings that are old enough for cleanup.
4. Marks eligible bookings as `rejected`.
5. Writes status history with a system source.
6. Logs cleanup summary.

Important policy values:

- The function uses `PENDING_NO_OPERATOR_POLICY`.
- It has a batch limit.
- It records summary fields such as scanned/rejected/skipped and whether more eligible docs may remain.

Side effects:

- updates `bookings/{bookingId}.status`
- updates `updatedAt`
- appends `bookings/{bookingId}/statusHistory`
- payment release trigger may run after the status changes to `rejected`
- push notification trigger may notify passenger/operator status changes

### `releaseStaleAcceptedPooledBookings`

Schedule: every 5 minutes.

Timezone: `Asia/Kuala_Lumpur`.

Region: `asia-southeast1`.

Purpose: releases accepted pooled bookings that were not started within the stale accepted window.

Why it exists:

- An operator can accept a booking and then stop interacting.
- If the booking remains `accepted`, other operators cannot claim it.
- This cleanup returns stale accepted pooled bookings to `pending`.

Eligibility:

- `status == accepted`
- `pooled == true`
- `updatedAt < cutoff`
- cutoff is based on `POOLING_POLICY.staleAcceptedMinutes`
- current configured stale accepted minutes in code: `12`

Batch limit:

- scans up to 100 bookings per run

Side effects:

For each stale accepted booking, it:

- sets `status = pending`
- sets `operatorUid = null`
- deletes assigned operator display fields
- sets `pooled = false`
- deletes pool group, sequence, criteria, max, eligibility score, and ETA snapshot fields
- updates `updatedAt`
- appends status history from `accepted` to `pending`

Important limitation:

- This cleanup removes several pool metadata fields but does not clear every possible DRT field in the broader schema. Remaining fields should be interpreted by app logic together with `status`, `operatorUid`, and `pooled`.

### `cleanupExpiredBookingArchive`

Schedule: every day at 02:00.

Timezone: `Asia/Kuala_Lumpur`.

Region: `asia-southeast1`.

Purpose: deletes old documents in `bookings_archive`.

Retention configuration:

- `BOOKING_ARCHIVE_RETENTION_DAYS`
- default: `400`
- non-positive or invalid values fall back to default

Eligibility:

- `archivedAt < cutoff`

Batch limit:

- deletes up to 300 archive docs per run

Side effects:

- deletes `bookings_archive/{bookingId}` documents

Log summary:

- retentionDays
- cutoff
- scanned
- deleted
- hasMoreEligibleDocs

### `cleanupExpiredOrderNumberReservations`

Schedule: every 30 minutes.

Timezone: `Asia/Kuala_Lumpur`.

Region: `asia-southeast1`.

Purpose: deletes stale abandoned order-number reservations.

Why it exists:

- Passenger booking flow reserves an order number before booking creation.
- If payment is abandoned, the reservation may remain without a booking.
- Expiry cleanup prevents the index from growing forever and frees old reservations from abandoned flows.

Eligibility:

- `order_number_index/{orderNumber}.expiresAt < now`

Batch limit:

- deletes up to 300 reservation docs per run

Side effects:

- deletes expired `order_number_index` docs

### `reconcileStaleAuthorizedPayments`

Schedule: every 30 minutes.

Timezone: `Asia/Kuala_Lumpur`.

Region: `asia-southeast1`.

Secret: `STRIPE_SECRET_KEY`.

Purpose: repairs stale payment holds after booking terminal transitions.

See `docs/stripe_payment_backend_lifecycle.md` for full payment detail.

Eligibility:

- booking has `paymentStatus == authorized`
- booking has `transactionId`
- booking has `orderNumber`
- booking `updatedAt` is missing or at least 30 minutes old

Actions:

| Booking Status | Action |
| --- | --- |
| `completed` | capture or mark paid |
| `cancelled` | cancel/refund |
| `rejected` | cancel/refund |
| other | skip |

Log summary:

- scanned
- released
- captured
- skipped
- failed

## Firestore Trigger Maintenance Functions

### `cleanupOrderNumberIndexOnTerminalBooking`

Trigger: `bookings/{bookingId}` update.

Purpose: deletes an order number reservation when the booking reaches terminal status.

Terminal statuses:

- `completed`
- `cancelled`
- `rejected`

Behavior:

1. Reads before and after status.
2. Skips when status did not change.
3. Skips when new status is not terminal.
4. Reads `orderNumber` from the booking.
5. Deletes `order_number_index/{orderNumber}` if it exists.
6. Logs whether cleanup removed anything.

Why it matters:

- Prevents terminal bookings from leaving permanent reservation docs.
- Complements scheduled expiry cleanup.

### `replanPoolSequenceOnBookingExit`

Trigger: `bookings/{bookingId}` update.

Purpose: replans an operator's remaining pool when one booking exits the accepted/on-the-way pool.

Runs when:

- before status was `accepted` or `on_the_way`
- after status is no longer in the same active pool for the same operator
- before booking had an operator UID

Behavior:

- calls route-aware replanning for the previous operator
- uses the exiting booking as an anchor context
- preserves completed stops when possible
- updates remaining bookings with new pool sequence and stop-plan state

See `docs/drt_algorithm_reference.md` for the route-aware replanning algorithm.

### Payment Release/Capture Triggers

These are maintenance-like safety functions even though they respond to booking lifecycle events:

| Function | Trigger | Purpose |
| --- | --- | --- |
| `capturePaymentOnBookingCompleted` | booking status changes to `completed` | captures manual-hold payment |
| `releasePaymentOnBookingCancelled` | booking status changes to `cancelled` | cancels/refunds payment |
| `releasePaymentOnBookingRejected` | booking status changes to `rejected` | cancels/refunds payment |

See `docs/stripe_payment_backend_lifecycle.md`.

## Admin Migration Endpoints

Migration endpoints are HTTP functions. They are protected by Firebase ID token verification and the `MIGRATION_ADMIN_UIDS` allowlist.

### Common Authorization

The backend parses `MIGRATION_ADMIN_UIDS` as a comma-separated allowlist.

Request must include:

```text
Authorization: Bearer <FIREBASE_ID_TOKEN>
```

The decoded token UID must be included in `MIGRATION_ADMIN_UIDS`.

If auth fails:

- invalid/missing token returns unauthorized response
- UID not in allowlist returns forbidden response

### Common Request Fields

| Field | Default | Description |
| --- | --- | --- |
| `dryRun` | `true` | If true, reports changes without writing them. |
| `limit` | `200` | Page size. Clamped from 1 to 500. |
| `startAfter` | empty | Document ID cursor for paging. |

### `backfillJettyIds`

Purpose: fills missing `originJettyId` and/or `destinationJettyId` on fares and bookings by matching text jetty names against `jetties`.

Allowed collections:

- `fares`
- `bookings`

Request body:

```json
{
  "dryRun": true,
  "limit": 200,
  "startAfter": "",
  "collections": ["fares", "bookings"]
}
```

`collections` can be:

- omitted: defaults to both
- array
- comma-separated string

Behavior:

1. Builds a normalized jetty-name map from `jetties`.
2. Pages through each requested collection.
3. For each doc:
   - if `originJettyId` is missing, resolves from normalized `origin`
   - if `destinationJettyId` is missing, resolves from normalized `destination`
4. In dry run, returns proposed patches and warnings.
5. In write mode, applies patches in a batch.

Normalization:

- trims whitespace
- lowercases
- compresses repeated whitespace

Response includes:

- per-collection result
- updated/proposed counts
- unresolved document IDs or warnings
- pagination cursor/hasMore information where applicable

Operational guidance:

- Run dry-run first.
- Apply collection by collection if the dataset is large.
- Continue with `startAfter` until no more documents are eligible.
- Confirm downstream app behavior with `docs/firestore_schema_inventory.md`.

### `cleanupLegacyOperatorOnlineField`

Purpose: removes deprecated `isOnline` from `operators/{uid}` documents.

Why it exists:

- Current online/offline state belongs in `operator_presence/{uid}.isOnline`.
- Older operator docs may still contain `operators.isOnline`.
- Keeping both fields can confuse audits and stale assumptions.

Request body:

```json
{
  "dryRun": true,
  "limit": 200,
  "startAfter": ""
}
```

Behavior:

1. Pages through `operators`.
2. Finds docs with legacy `isOnline`.
3. In dry run, reports what would be removed.
4. In write mode, deletes the `isOnline` field using `FieldValue.delete()`.

Operational guidance:

- Run only after operator app and functions are using `operator_presence`.
- Use dry-run output to estimate blast radius.
- Keep `operator_presence` populated before cleanup.

## Maintenance Function Interaction Map

### Pending Booking With No Operators

1. Passenger creates `bookings/{id}` with `status = pending`.
2. No operators remain online.
3. `rejectStalePendingBookingsWithoutOnlineOperators` marks old pending booking `rejected`.
4. `releasePaymentOnBookingRejected` releases/refunds payment.
5. `notifyBookingStatusChanged` notifies passenger.
6. `cleanupOrderNumberIndexOnTerminalBooking` deletes order reservation.

### Accepted Booking Abandoned By Operator

1. Operator accepts booking.
2. Booking remains `accepted` and pooled beyond stale window.
3. `releaseStaleAcceptedPooledBookings` returns it to `pending`.
4. Status history records system release.
5. Booking can be accepted by another operator later.

### Completed Booking With Missed Capture

1. Booking becomes `completed`.
2. Capture trigger fails or Stripe call fails.
3. Booking remains `paymentStatus = authorized`.
4. `reconcileStaleAuthorizedPayments` retries capture after stale cutoff.

### Cancelled Booking With Missed Release

1. Booking becomes `cancelled`.
2. Release trigger fails or Stripe call fails.
3. Booking remains `paymentStatus = authorized`.
4. `reconcileStaleAuthorizedPayments` retries release after stale cutoff.

### Old Archive Data

1. Completed/cancelled bookings create archive records.
2. Archive records age past retention.
3. `cleanupExpiredBookingArchive` deletes them.

## Monitoring Signals

Watch Cloud Functions logs for:

| Log/Alert Type | Meaning |
| --- | --- |
| `PAYMENT_CAPTURE_FAILED` | Capture failed after completed booking. |
| `PAYMENT_RELEASE_FAILED` | Cancel/refund failed after cancelled/rejected booking. |
| `PAYMENT_RECONCILE_FAILED` | Scheduled reconciliation could not repair a payment. |
| `Pending no-operator cleanup completed` | No-operator cleanup ran. |
| `Stale pooled accepted cleanup completed` | Stale accepted cleanup ran. |
| `Archive retention cleanup completed` | Archive cleanup ran. |
| `Order reservation cleanup completed` | Order reservation cleanup ran. |

## Known Boundaries

- Scheduled cleanup jobs use batch limits. A large backlog may need multiple runs.
- Migration endpoints are not public admin dashboards; they are HTTP tools protected by Firebase Auth and allowlist.
- Archive retention deletes historical archive documents permanently.
- Stale accepted cleanup currently targets pooled accepted bookings.
- Payment reconciliation only scans authorized payment state.
- Admin SDK writes bypass Firestore security rules.
