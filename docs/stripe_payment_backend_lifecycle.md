# Stripe Payment Backend Lifecycle

Last updated: 2026-06-02.

This document explains the current Stripe payment backend used by the passenger booking flow. It focuses on the Cloud Functions implementation in `apps/passenger_app/functions/index.js`, the passenger app payment/booking repositories, and the Firestore fields that record payment state.

Related documents:

- `docs/passenger_app_features.md`
- `docs/firestore_schema_inventory.md`
- `docs/cloud_functions_api_contracts.md`
- `docs/maintenance_and_migration_functions.md`

## Purpose

The payment system uses a hold-first lifecycle:

1. Passenger selects a route and confirms the fare.
2. Backend creates a Stripe PaymentIntent with `capture_method: "manual"`.
3. Passenger completes the Stripe Payment Sheet.
4. Booking is written with `paymentStatus = authorized`.
5. If the ride completes, backend captures the PaymentIntent and marks the booking paid.
6. If the booking is cancelled or rejected, backend cancels the uncaptured PaymentIntent or refunds a captured one.
7. Scheduled reconciliation handles stale authorized payments if a trigger is missed.

This design protects passengers from paying for trips that never happen while still confirming that payment can be captured before the operator is dispatched.

## Source Files

### Backend

- `apps/passenger_app/functions/index.js`
  - `createStripePaymentIntent`
  - `createStripePaymentIntentHttp`
  - `stripeWebhook`
  - `capturePaymentOnBookingCompleted`
  - `releasePaymentOnBookingCancelled`
  - `releasePaymentOnBookingRejected`
  - `capturePaymentIntent`
  - `cancelPaymentIntent`
  - `reconcileStaleAuthorizedPayments`
  - helper functions such as `createPaymentIntentCore`, `validatePaymentIntentParams`, `captureOrMarkPaidPaymentIntent`, `cancelOrRefundPaymentIntent`, and `updateBookingPaymentState`

### Passenger App

- `apps/passenger_app/lib/services/payment/payment_gateway_service.dart`
- `apps/passenger_app/lib/features/home/presentation/viewmodels/payment_view_model.dart`
- `apps/passenger_app/lib/data/repositories/booking_repository.dart`

### Shared Model Layer

- `packages/water_taxi_shared/lib/src/constants/firestore_fields.dart`
- `packages/water_taxi_shared/lib/src/models/booking_model.dart`

## Environment And Secrets

The functions module uses these Firebase parameters/secrets:

| Name | Type | Used By | Purpose |
| --- | --- | --- | --- |
| `STRIPE_SECRET_KEY` | secret | Payment creation, capture, cancel, refund, reconciliation, webhook | Authenticates backend Stripe API calls. |
| `STRIPE_WEBHOOK_SECRET` | secret | `stripeWebhook` | Verifies Stripe webhook signatures. |
| `STRIPE_CURRENCY` | string | Payment creation | Default currency. Falls back to `myr`. |

The passenger app uses dart-define configuration for the client-side Stripe flow:

| Name | Purpose |
| --- | --- |
| `STRIPE_PUBLISHABLE_KEY` | Initializes Stripe SDK on the client. |
| `STRIPE_MERCHANT_IDENTIFIER` | iOS Apple Pay merchant identifier. |
| `STRIPE_URL_SCHEME` | Stripe return/deep link scheme. |
| `STRIPE_MERCHANT_DISPLAY_NAME` | Merchant display name shown by payment UI. |
| `STRIPE_RETURN_URL` | Return URL used after payment confirmation. |
| `STRIPE_PAYMENT_INTENT_ENDPOINT` | HTTP endpoint for `createStripePaymentIntentHttp`. |

## Firestore Payment Fields

Payment state is stored on `bookings/{bookingId}`.

| Field | Meaning |
| --- | --- |
| `paymentMethod` | Current client value such as `card`. |
| `paymentStatus` | Backend/client payment state. Main values are `authorized`, `paid`, `cancelled`, and `refunded`. |
| `orderNumber` | Passenger-facing order identifier and backend lookup key for payment updates. |
| `transactionId` | Stripe PaymentIntent ID. |
| `totalFare` | Fare charged to Stripe after passenger/adult/child fare calculations. |
| `fareSnapshotId` | Fare document used for the booking. |
| `updatedAt` | Updated when payment status is changed by webhook, capture, cancel, refund, or reconciliation. |

Payment audit and idempotency collections:

| Collection | Purpose |
| --- | --- |
| `payment_webhooks` | Stores Stripe webhook event snapshots for audit. |
| `webhook_events` | Stores processed Stripe event IDs to avoid duplicate processing. |
| `order_number_index` | Reserves order numbers before booking creation so abandoned/retried payment flows do not duplicate order numbers. |

`payment_webhooks` and `webhook_events` may be absent from a live-only Firestore sample if no webhook has been received. They are still backend-supported collections.

## PaymentIntent Creation

PaymentIntent creation is exposed in two forms.

### `createStripePaymentIntent`

Type: callable function.

Region: `asia-southeast1`.

App Check: enforced.

Auth: Firebase Auth required.

This callable is the preferred backend API when the client can satisfy callable/App Check requirements.

### `createStripePaymentIntentHttp`

Type: HTTP function.

Region: `asia-southeast1`.

Auth: verifies Firebase ID token from the `Authorization: Bearer <ID_TOKEN>` header.

This endpoint exists as a fallback for clients that use a plain HTTP payment endpoint. The passenger app README currently describes this as the default endpoint.

### Request Fields

Both creation paths normalize and validate the same logical payload:

| Field | Required | Description |
| --- | --- | --- |
| `amount` | Yes | Major currency unit amount, for example MYR as decimal value. Backend converts to minor units with `Math.round(amount * 100)`. |
| `currency` | Optional | Defaults to `STRIPE_CURRENCY`, then `myr`. Normalized to lowercase. |
| `orderNumber` | Yes | Booking order identifier. Stored in PaymentIntent metadata and used to locate the booking later. |
| `payerName` | Yes | Stored in PaymentIntent metadata. |
| `payerEmail` | Yes | Used as `receipt_email`. |
| `payerTelephoneNumber` | Optional | Stored in PaymentIntent metadata. |
| `idempotencyKey` | Yes | Passed to Stripe as the PaymentIntent creation idempotency key. |
| `description` | Optional | Stripe PaymentIntent description. Defaults to `Water taxi booking <orderNumber>`. |

Validation rejects:

- `amount <= 0`
- missing/non-string `currency`
- amount below the currency minimum in `MINIMUM_STRIPE_CHARGE_BY_CURRENCY`
- missing/non-string `orderNumber`
- missing/non-string `payerName`
- missing/non-string `payerEmail`
- missing/non-string `idempotencyKey`
- missing `STRIPE_SECRET_KEY`

### Stripe Request Shape

The backend creates:

```js
stripe.paymentIntents.create({
  amount: amountInMinorUnit,
  currency,
  capture_method: "manual",
  receipt_email: payerEmail,
  description,
  automatic_payment_methods: { enabled: true },
  metadata: {
    userId,
    orderNumber,
    payerName,
    payerTelephoneNumber,
    idempotencyKey,
  },
}, {
  idempotencyKey,
});
```

The important part is `capture_method: "manual"`. This means the passenger authorizes a payment hold first; money is captured later when the booking completes.

### Success Response

Callable response:

```json
{
  "status": "ready",
  "paymentIntentId": "pi_...",
  "clientSecret": "pi_..._secret_..."
}
```

HTTP response is the same JSON shape with HTTP status `200`.

### Failure Responses

Callable failures use Firebase callable errors:

| Code | Meaning |
| --- | --- |
| `unauthenticated` | No Firebase Auth user. |
| `invalid-argument` | Payload validation failed. |
| `failed-precondition` | `STRIPE_SECRET_KEY` is not configured. |
| `internal` | Stripe creation failed. |

HTTP failures use HTTP statuses:

| HTTP Status | Meaning |
| --- | --- |
| `405` | Method is not POST. |
| `401` | Missing/invalid Firebase ID token. |
| `400` | Payload validation failed. |
| `500` | Stripe secret missing or Stripe creation failed. |

## Passenger Booking Creation Coupling

The Passenger app does not write a booking before payment authorization succeeds. The normal flow is:

1. Generate or reserve an order number.
2. Create a manual-capture PaymentIntent.
3. Present Stripe Payment Sheet with the returned `clientSecret`.
4. After successful payment authorization, create `bookings/{bookingId}`.
5. Booking write includes:
   - `paymentStatus: authorized`
   - `transactionId: <PaymentIntent ID>`
   - `orderNumber`
   - `status: pending`

This means operators should only see pending bookings whose payment has already been authorized.

## Webhook Lifecycle

Function: `stripeWebhook`.

Type: HTTP function.

Region: `asia-southeast1`.

Secrets:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`

### Webhook Verification

The function requires:

- POST method
- configured Stripe secret key
- configured webhook secret
- valid Stripe signature from the `stripe-signature` header

It calls:

```js
stripe.webhooks.constructEvent(req.rawBody, signature, webhookSecret)
```

If verification fails, it returns HTTP `400`.

### Idempotency

Before processing the event, the function checks `webhook_events/{eventId}`:

- If the event ID already exists, the event is skipped and the function returns `{ ok: true }`.
- If not, it writes `{ processedAt: new Date() }` and continues.

This prevents duplicate Stripe webhook delivery from applying duplicate updates.

### Audit Write

Every accepted new webhook is written to `payment_webhooks` with:

| Field | Description |
| --- | --- |
| `provider` | `stripe` |
| `eventId` | Stripe event ID |
| `eventType` | Stripe event type |
| `paymentIntentId` | PaymentIntent ID from payload object |
| `status` | Stripe object status |
| `orderNumber` | PaymentIntent metadata order number |
| `payload` | Full event object |
| `receivedAt` | Server-side Date object |

### Webhook Event Handling

Current event-specific behavior:

| Stripe Event | Condition | Booking Update |
| --- | --- | --- |
| `payment_intent.succeeded` | `metadata.orderNumber` exists and booking is found | `paymentStatus = paid`, `transactionId = paymentIntentId`, `updatedAt = new Date()` |
| `payment_intent.amount.capturably_held` | `metadata.orderNumber` exists and booking is found | `paymentStatus = authorized`, `transactionId = paymentIntentId`, `updatedAt = new Date()` |

Other event types are audited but do not currently change bookings.

## Capture On Trip Completion

Function: `capturePaymentOnBookingCompleted`.

Type: Firestore `onDocumentUpdated`.

Trigger: `bookings/{bookingId}`.

Region: `asia-southeast1`.

Secret: `STRIPE_SECRET_KEY`.

The trigger runs when:

- before and after booking data both exist
- status changed
- new status is `completed`
- `transactionId` and `orderNumber` are present

It calls `captureOrMarkPaidPaymentIntent`.

### `captureOrMarkPaidPaymentIntent` Behavior

The helper retrieves the PaymentIntent from Stripe and acts based on its current status.

| Stripe PaymentIntent Status | Backend Behavior | Booking Payment Status |
| --- | --- | --- |
| `requires_capture` | Calls `stripe.paymentIntents.capture(paymentIntentId)` | `paid` |
| `succeeded` | Does not capture again; treats as already paid | `paid` |
| other status | Throws unsupported-status error | unchanged unless another path handles it |

This makes completion idempotent for already-captured payments.

### Failure Behavior

If capture fails, the function logs:

- `alertType: PAYMENT_CAPTURE_FAILED`
- `bookingId`
- `paymentIntentId`
- `orderNumber`
- error message

The function does not revert the booking status. Reconciliation can later pick up stale authorized completed bookings.

## Release On Passenger Cancellation

Function: `releasePaymentOnBookingCancelled`.

Type: Firestore `onDocumentUpdated`.

Trigger: `bookings/{bookingId}`.

Runs when booking status changes to `cancelled`.

If `transactionId` or `orderNumber` is missing, it logs a warning and returns.

It calls `cancelOrRefundPaymentIntent` with reason `passenger_cancelled_booking`.

## Release On Operator Rejection

Function: `releasePaymentOnBookingRejected`.

Type: Firestore `onDocumentUpdated`.

Trigger: `bookings/{bookingId}`.

Runs when booking status changes to `rejected`.

This status usually means all currently online operators declined the request or a no-operator cleanup rejected the pending booking.

It calls `cancelOrRefundPaymentIntent` with reason `all_operators_rejected`.

## Cancel Or Refund Logic

Helper: `cancelOrRefundPaymentIntent`.

This function retrieves the PaymentIntent first, then chooses between a true refund and an uncaptured authorization release.

| Stripe PaymentIntent Status | Backend Action | Booking Payment Status |
| --- | --- | --- |
| `succeeded` | Creates a Stripe Refund | `refunded` |
| `requires_capture` | Cancels PaymentIntent | `cancelled` |
| `requires_payment_method` | Cancels PaymentIntent | `cancelled` |
| `requires_confirmation` | Cancels PaymentIntent | `cancelled` |
| `requires_action` | Cancels PaymentIntent | `cancelled` |
| `processing` | Cancels PaymentIntent | `cancelled` |
| `canceled` | Marks booking cancelled | `cancelled` |
| other status | Throws unsupported-status error | unchanged |

### Refund Path

For already-captured `succeeded` payments, the backend creates:

```js
stripe.refunds.create({
  payment_intent: intent.id,
  reason: "requested_by_customer",
  metadata: {
    orderNumber,
    cancellationReason: reason || "requested_by_customer",
  },
});
```

Then it updates the booking:

- `paymentStatus = refunded`
- `transactionId = intent.id`
- `refundedAt = new Date()`
- `refundId = refund.id`

### Authorization Release Path

For uncaptured/authorized payments, the backend cancels the PaymentIntent:

```js
stripe.paymentIntents.cancel(intent.id, {
  cancellation_reason: stripeCancellationReason,
});
```

Then it updates the booking:

- `paymentStatus = cancelled`
- `transactionId = cancelledIntent.id`

The `reason` value is normalized to one of Stripe's accepted cancellation reasons:

- `duplicate`
- `fraudulent`
- `requested_by_customer`
- `abandoned`

Unknown reasons fall back to `requested_by_customer`.

## Manual Payment Operations

These callable functions exist as operational controls and fallback paths.

### `capturePaymentIntent`

Type: callable.

App Check: enforced.

Auth: Firebase Auth required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `paymentIntentId` | Yes | Stripe PaymentIntent ID. |
| `orderNumber` | Optional but important | Used to update the matching booking. |

Success response:

```json
{
  "status": "captured",
  "paymentIntentId": "pi_..."
}
```

### `cancelPaymentIntent`

Type: callable.

App Check: enforced.

Auth: Firebase Auth required.

Request:

| Field | Required | Description |
| --- | --- | --- |
| `paymentIntentId` | Yes | Stripe PaymentIntent ID. |
| `orderNumber` | Optional but important | Used to update the matching booking. |
| `reason` | Optional | Cancellation/refund reason. |

Success response depends on Stripe state:

```json
{
  "status": "cancelled",
  "paymentIntentId": "pi_..."
}
```

or:

```json
{
  "status": "refunded",
  "paymentIntentId": "pi_...",
  "refundId": "re_...",
  "refundStatus": "succeeded"
}
```

## Scheduled Reconciliation

Function: `reconcileStaleAuthorizedPayments`.

Schedule: every 30 minutes.

Timezone: `Asia/Kuala_Lumpur`.

Region: `asia-southeast1`.

Secret: `STRIPE_SECRET_KEY`.

The function scans up to 200 bookings where:

- `paymentStatus == authorized`

For each booking, it skips if:

- `transactionId` is missing
- `orderNumber` is missing
- `updatedAt` is present and newer than 30 minutes ago

For stale authorized bookings:

| Booking Status | Reconciliation Action |
| --- | --- |
| `cancelled` | cancel/refund PaymentIntent |
| `rejected` | cancel/refund PaymentIntent |
| `completed` | capture or mark paid |
| anything else | skip |

It logs a summary:

- scanned
- released
- captured
- skipped
- failed

This is the safety net for missed triggers, function failures, or race conditions.

## Order Number Reservation Lifecycle

Order numbers are reserved in `order_number_index/{orderNumber}` by the passenger app before booking creation.

Fields:

| Field | Description |
| --- | --- |
| `orderNumber` | Document ID and reserved order number. |
| `userId` | Passenger UID that reserved it. |
| `reservedAt` | Reservation time. |
| `expiresAt` | Reservation expiry, currently 24 hours from reservation. |

The reservation prevents duplicate order numbers during retries or abandoned payment flows.

Cleanup paths:

- `cleanupOrderNumberIndexOnTerminalBooking` deletes a reservation when a booking reaches terminal status.
- `cleanupExpiredOrderNumberReservations` deletes reservations whose `expiresAt` is in the past.

## Normal End-To-End Payment Timeline

### Successful Trip

1. Passenger selects route and fare.
2. Passenger app reserves order number.
3. Passenger app calls payment intent endpoint.
4. Backend creates Stripe PaymentIntent with manual capture.
5. Stripe Payment Sheet authorizes payment.
6. Passenger app creates booking with:
   - `status = pending`
   - `paymentStatus = authorized`
   - `transactionId = pi_...`
   - `orderNumber = ...`
7. Operator accepts, starts, and completes trip.
8. Booking status changes to `completed`.
9. `capturePaymentOnBookingCompleted` captures PaymentIntent.
10. Booking payment status becomes `paid`.

### Passenger Cancellation Before Capture

1. Booking exists with `paymentStatus = authorized`.
2. Passenger cancels booking.
3. Booking status changes to `cancelled`.
4. `releasePaymentOnBookingCancelled` retrieves PaymentIntent.
5. If PaymentIntent is uncaptured, backend cancels it.
6. Booking payment status becomes `cancelled`.

### Rejection By Operators

1. Booking exists with `paymentStatus = authorized`.
2. Operators reject or backend no-operator cleanup rejects.
3. Booking status changes to `rejected`.
4. `releasePaymentOnBookingRejected` retrieves PaymentIntent.
5. Backend cancels uncaptured payment or refunds captured payment.
6. Booking payment status becomes `cancelled` or `refunded`.

### Capture Trigger Missed

1. Booking is `completed`.
2. Booking remains `paymentStatus = authorized`.
3. After at least 30 minutes, scheduled reconciliation scans it.
4. Reconciliation captures or marks paid.

### Release Trigger Missed

1. Booking is `cancelled` or `rejected`.
2. Booking remains `paymentStatus = authorized`.
3. After at least 30 minutes, scheduled reconciliation scans it.
4. Reconciliation cancels/refunds.

## Important Failure Modes

### Booking Missing Payment Metadata

If a terminal booking lacks `transactionId` or `orderNumber`, payment release/capture triggers log and skip. Reconciliation also skips these bookings.

Impact: human/admin investigation is needed because the backend cannot locate the Stripe PaymentIntent.

### Stripe Secret Missing

If `STRIPE_SECRET_KEY` is missing:

- Payment creation fails.
- Capture/release triggers log and return.
- Reconciliation logs `PAYMENT_RECONCILE_FAILED`.

Impact: passenger payments cannot be initialized, and existing authorized payments may need manual Stripe dashboard action.

### Webhook Secret Missing

If `STRIPE_WEBHOOK_SECRET` is missing, `stripeWebhook` returns server error and does not process events.

Impact: webhook audit and event-driven payment status updates stop, but booking status triggers and reconciliation can still update payment state if they have Stripe secret access.

### Duplicate Webhooks

Duplicate Stripe webhook events are skipped using `webhook_events/{eventId}`.

Impact: safe and expected.

### Capture Failure After Booking Completion

Booking can remain completed while payment is still authorized. Reconciliation attempts repair later. Logs include `PAYMENT_CAPTURE_FAILED`.

### Release Failure After Cancellation/Rejection

Booking can remain cancelled/rejected while payment is still authorized. Reconciliation attempts repair later. Logs include `PAYMENT_RELEASE_FAILED`.

## Operational Notes

- Monitor logs for `PAYMENT_CAPTURE_FAILED`, `PAYMENT_RELEASE_FAILED`, and `PAYMENT_RECONCILE_FAILED`.
- Stripe dashboard should be checked for PaymentIntent status when Firestore and Stripe disagree.
- `payment_webhooks` is an audit trail, not the source of truth for booking status.
- `webhook_events` is an idempotency set and should not be manually deleted unless replay behavior is intentionally desired.
- The current backend uses `new Date()` in some payment updates and `FieldValue.serverTimestamp()` in booking lifecycle updates. Both are server-side values from Cloud Functions, but they are not identical types at write construction time.

## Known Boundaries

- The backend does not currently write a separate payment ledger collection.
- The operator app does not manage Stripe capture directly.
- The scheduled reconciliation only scans `paymentStatus == authorized`.
- Webhook handling currently updates booking payment status for held and succeeded events only.
- `orderNumber` is the primary lookup key for payment state updates; if it is missing or duplicated, payment repair becomes harder.
