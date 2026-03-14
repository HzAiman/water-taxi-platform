# Firebase Functions (Push Notifications)

This module contains the Cloud Functions backend that sends FCM push notifications for booking events. Functions run as Gen 2 Cloud Functions in region `asia-southeast1` using Node.js 20.

## Implemented triggers

### `notifyOperatorsOnIncomingBooking`
- **Trigger:** `bookings/{bookingId}` on create
- **Condition:** booking status is `pending`
- **Action:** query `operator_presence` for operators where `isOnline == true`, fetch their FCM tokens from `operator_devices/{operatorUid}`, and send a push notification to each.

### `notifyBookingStatusChanged`
- **Trigger:** `bookings/{bookingId}` on update
- **Condition:** booking `status` field changed
- **Action:**
  - Send FCM to the passenger token in `user_devices/{userId}` with a data payload that includes `bookingId`, `status`, `origin`, `destination`, and `passengerCount` to support deep-link navigation.
  - Send FCM to the assigned operator token in `operator_devices/{operatorUid}` if a `driverId` is present on the booking.

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
- Node.js 18 reached end-of-life in April 2025; this project uses Node.js 20 as specified in `functions/package.json`.
- Cloud artifact cleanup is set to 7 days to avoid stale build artifacts accumulating in Artifact Registry.
