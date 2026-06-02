# Security Rules And Access Control

Last updated: 2026-06-02.

This document explains the current Firestore security rules in `apps/passenger_app/firestore.rules`. It describes who can read and write each collection, what data shape is allowed, and where backend Cloud Functions bypass client rules.

Related documents:

- `docs/firestore_schema_inventory.md`
- `docs/cloud_functions_api_contracts.md`
- `docs/passenger_app_features.md`
- `docs/operator_app_features.md`

## Core Rule Helpers

The rules define a small set of reusable helpers.

### `isSignedIn()`

Returns true when `request.auth != null`.

Used for:

- read access to public-but-authenticated data such as jetties, fares, polylines, and operator presence
- order number existence checks
- status history creation

### `isOwner(userId)`

Returns true when signed in and `request.auth.uid == userId`.

Used for:

- passenger profile ownership
- operator profile ownership
- device token document ownership
- passenger booking ownership

### `isOperator()`

Returns true when signed in and `operators/{request.auth.uid}` exists.

This means operator role is document-based, not a custom claim. A user becomes an operator when the `operators/{uid}` profile exists.

### `bookingOperatorUid(data)`

Returns `data.operatorUid` when present, otherwise `data.operatorId`.

This maintains compatibility with older bookings that used `operatorId` instead of `operatorUid`.

### `isAssignedOperator()`

Returns true when the signed-in user is an operator and either:

- booking operator UID equals the signed-in UID
- booking operator field equals the `operatorId` stored on `operators/{uid}`

This supports both current UID-based assignment and legacy display-ID assignment.

## User Profiles: `users/{userId}`

### Read

Allowed only for the owner:

```text
request.auth.uid == userId
```

### Create And Update

Allowed only for the owner.

Allowed keys:

- `uid`
- `name`
- `email`
- `phoneNumber`
- `createdAt`
- `updatedAt`

If `uid` is present, it must equal `request.auth.uid`.

### Delete

Allowed for the owner.

### Security Intent

Passengers can manage only their own profile. Operators cannot read arbitrary passenger profiles; passenger details needed for trips are copied into booking snapshots.

## Operator Profiles: `operators/{operatorUid}`

### Read

Allowed only for the owner.

### Create

Allowed only for the owner when the profile is valid.

Required fields:

- `name`
- `operatorId`
- `email`

`operatorId` must be a non-empty string.

Allowed keys:

- `name`
- `operatorId`
- `email`
- `phoneNumber`
- `createdAt`
- `updatedAt`
- `operatorIdKey` legacy compatibility
- `isOnline` legacy compatibility

### Update

Allowed only for the owner when:

- profile remains valid
- allowed keys are respected
- changed keys are only:
  - `name`
  - `operatorId`
  - `email`
  - `phoneNumber`
  - `updatedAt`

### Delete

Denied.

### Security Intent

Operator profile deletion is blocked from the client. Online/offline state should live in `operator_presence`, not in `operators.isOnline`.

## Operator ID Index: `operator_id_index/{operatorId}`

### Read

Allowed for any signed-in user.

This is needed for uniqueness checks.

### Create

Allowed for signed-in users when:

- the index doc does not already exist
- allowed keys are only `uid`, `operatorId`, `createdAt`, `updatedAt`
- `uid == request.auth.uid`
- `operatorId == document ID`

### Update

Allowed when:

- current doc is owned by `request.auth.uid`
- new doc keeps `uid == request.auth.uid`
- `operatorId == document ID`
- allowed keys are respected

### Delete

Allowed when current doc is owned by `request.auth.uid`.

### Security Intent

The index lets each operator claim and maintain a unique operator display ID. The backend `saveOperatorProfile` callable is the safer canonical path because it updates profile, index, and presence in one transaction.

## Operator Presence: `operator_presence/{operatorUid}`

### Read

Allowed for any signed-in user.

Passenger/backend/operator workflows need to know whether operators are online.

### Create And Update

Allowed only for the owner.

Allowed keys:

- `isOnline`
- `updatedAt`

### Delete

Denied.

### Security Intent

Operators can control their own online status. They cannot edit another operator's presence. Presence docs are not deleted by clients.

## Device Tokens

### Passenger Device Tokens: `user_devices/{userId}`

Read: owner only.

Create/update: owner only, with allowed keys:

- `token`
- `platform`
- `appRole`
- `updatedAt`

`appRole` must be `passenger`.

Delete: owner only.

### Operator Device Tokens: `operator_devices/{operatorUid}`

Read: owner only.

Create/update: owner only, with allowed keys:

- `token`
- `platform`
- `appRole`
- `updatedAt`

`appRole` must be `operator`.

Delete: owner only.

### Security Intent

Users can only manage their own FCM token document and cannot impersonate another app role.

## Order Number Reservations: `order_number_index/{orderNumber}`

### Read

Allowed for signed-in users.

The passenger booking flow performs a transaction read to check whether an order number already exists.

### Create

Allowed for signed-in users when:

- allowed keys are only `orderNumber`, `userId`, `reservedAt`, `expiresAt`
- `orderNumber == document ID`
- `userId == request.auth.uid`

### Update And Delete

Denied to clients.

### Security Intent

Passengers can reserve their own order numbers but cannot alter or delete reservations after creation. Cleanup is backend-owned.

## Tracking: `tracking/{bookingId}`

### Read

Allowed for signed-in users when:

- `bookings/{bookingId}` exists
- signed-in user is the passenger owner, or
- signed-in user is the assigned operator

### Create And Update

Allowed for operators when:

- `bookings/{bookingId}` exists
- allowed keys are only:
  - `bookingId`
  - `operatorUid`
  - `operatorLat`
  - `operatorLng`
  - `updatedAt`
- `bookingId == document ID`
- `operatorUid == request.auth.uid`
- booking is assigned to the authenticated operator

### Delete

Denied.

### Security Intent

Only assigned operators can write live location updates, and only trip participants can read them.

## Static Route/Fare Data

### `jetties/{jettyId}`

Read: signed-in users.

Write: denied.

### `fares/{fareId}`

Read: signed-in users.

Write: denied.

### `polylines/{polylineId}`

Read: signed-in users.

Write: denied.

### Security Intent

The app treats jetties, fares, and polylines as admin-managed configuration data. Client apps can read but not mutate them.

## Bookings: `bookings/{bookingId}`

Bookings have the most complex access rules.

### Read

Passengers can read bookings they own:

```text
resource.data.userId == request.auth.uid
```

Operators can read:

- any pending booking
- bookings assigned to their UID

This lets online operators see the dispatch queue while protecting non-pending assigned trips from unrelated operators.

### Create

Only signed-in passengers can create their own pending booking.

Required checks:

- `request.resource.data.userId == request.auth.uid`
- `bookingId == document ID`
- `status == pending`
- `paymentStatus == authorized`
- booking create field allowlist passes
- `originJettyId`, `destinationJettyId`, and `fareSnapshotId` exist and are strings

Allowed create keys include passenger snapshot fields, route fields, fare fields, payment metadata, pending status, assignment placeholders, and timestamps.

### Passenger Cancellation Update

Passenger owner can update a booking only to cancel it.

Rules require:

- booking still belongs to same user
- booking ID is unchanged
- changed keys only:
  - `status`
  - `updatedAt`
  - `cancelledAt`
- current status is one of:
  - `pending`
  - `accepted`
  - `on_the_way`
- next status is `cancelled`
- booking update field allowlist passes

### Operator Updates

Operators can perform limited client-compatible updates. Important rule gates:

- user ID and booking ID cannot change
- client cannot directly transition from non-`on_the_way` into `on_the_way`
- update must match one of the allowed transition shapes
- update field allowlist must pass

Allowed operator update shapes:

1. Pending to accepted:
   - changed keys only status, updatedAt, operator assignment/display fields
   - resource status is `pending`
   - next status is `accepted`
   - booking was unassigned
   - operator has not already rejected

2. Accepted release back to pending:
   - changed keys include status, updatedAt, operator fields, rejectedBy
   - resource status is `accepted`
   - next status is `pending`
   - authenticated operator is assigned
   - operator is added to `rejectedBy`

3. Location snapshot update:
   - changed keys only updatedAt, operatorLat, operatorLng
   - resource status is `on_the_way`
   - booking remains assigned to same operator

4. Pending rejection without terminal rejection:
   - changed keys only rejectedBy, updatedAt
   - status remains `pending`
   - booking remains unassigned
   - operator is newly added to `rejectedBy`

5. Pending rejection to terminal rejected:
   - changed keys status, rejectedBy, updatedAt
   - status changes from `pending` to `rejected`
   - booking remains unassigned
   - operator is newly added to `rejectedBy`

### Delete

Denied.

### Security Intent

Passengers can create and cancel their own bookings. Operators can read the pending queue and perform narrow legacy-compatible booking actions. Backend callable functions are the intended authority for advanced pooled booking state.

## Booking Status History: `bookings/{bookingId}/statusHistory/{statusHistoryId}`

### Read

Allowed for:

- passenger owner of the parent booking
- assigned operator of the parent booking

### Create

Allowed for signed-in users when:

- allowed keys are only `from`, `to`, `changedBy`, `source`, `timestamp`
- `changedBy == request.auth.uid`
- `source` is either `passenger_app` or `operator_app`
- signed-in user is passenger owner or an operator

### Update And Delete

Denied.

### Security Intent

Status history is append-only from the client perspective. Backend functions also append status history during callable lifecycle transitions.

## Booking Archive: `bookings_archive/{bookingId}`

### Create

Allowed for signed-in users when:

- required keys include:
  - `bookingId`
  - `userId`
  - `status`
  - `archivedAt`
  - `archivedStatus`
- `bookingId == document ID`
- signer is passenger owner or assigned operator

### Read

Allowed for:

- passenger owner
- assigned operator

### Update And Delete

Denied.

### Security Intent

Archives are immutable from the client perspective after creation. Cleanup is backend-owned through retention maintenance.

## Backend Bypass

Cloud Functions use Firebase Admin SDK. Admin SDK bypasses Firestore security rules.

This matters for:

- payment capture/release updates
- route-aware pooling writes
- migration writes
- stale booking cleanup
- notification token cleanup
- archive retention deletion
- order-number cleanup

Security rules protect direct client access. They do not restrict trusted backend service code.

## Access Matrix

| Collection | Passenger Owner | Operator Owner | Other Signed-In Passenger | Other Operator | Backend |
| --- | --- | --- | --- | --- | --- |
| `users/{uid}` | read/write/delete own | no unless own user doc | no | no | yes |
| `operators/{uid}` | no unless own operator doc | read/write own | no | no | yes |
| `operator_id_index` | read/create own claim | read/create/update/delete own claim | read | read | yes |
| `operator_presence` | read all | read all/write own | read all | read all/write own | yes |
| `user_devices/{uid}` | read/write/delete own | no unless own user device doc | no | no | yes |
| `operator_devices/{uid}` | no unless own operator device doc | read/write/delete own | no | no | yes |
| `order_number_index` | read/create own reservation | read/create own reservation | read | read | yes |
| `tracking/{bookingId}` | read own booking tracking | write/read assigned tracking | no | assigned only | yes |
| `jetties` | read | read | read | read | yes |
| `fares` | read | read | read | read | yes |
| `polylines` | read | read | read | read | yes |
| `bookings` | create/read/cancel own | read pending/read assigned/write narrow transitions | no | read pending only unless assigned | yes |
| `statusHistory` | read/create own booking history | read/create assigned booking history | no | assigned only | yes |
| `bookings_archive` | read/create own archive | read/create assigned archive | no | assigned only | yes |

## Important Security Assumptions

- Operator role is determined by existence of `operators/{uid}`.
- Static configuration data is admin-managed outside client rules.
- Payment state is protected mainly by allowed booking field shapes and backend-owned status transitions.
- Advanced DRT writes are trusted backend writes.
- Client-side accepted/rejected compatibility remains allowed, but backend callable paths should be preferred for production DRT correctness.
- Pending bookings are visible to all operators with an operator profile.

## Known Boundaries

- Rules do not validate numeric ranges for every booking field.
- Rules do not validate route polyline geometry.
- Rules do not require App Check; App Check is enforced on selected Cloud Functions, not Firestore rules.
- Admin SDK writes bypass rules.
- Migration/admin access is controlled in HTTP functions by `MIGRATION_ADMIN_UIDS`, not by Firestore rules.
