# Push Notifications Features

Last updated: 2026-06-02

This document explains the push-notification and local-notification behavior for both apps in the Water Taxi Platform.

The platform has two notification layers:

- **Server push notifications**: Cloud Functions send Firebase Cloud Messaging (FCM) messages to device tokens stored in Firestore.
- **Client local notifications and foreground alerts**: each app listens to booking streams and app lifecycle state, then shows either in-app top alerts or local OS notifications.

## Source Files

Backend:

- `apps/passenger_app/functions/index.js`

Passenger app:

- `apps/passenger_app/lib/main.dart`
- `apps/passenger_app/lib/routes/main_screen.dart`
- `apps/passenger_app/lib/services/notifications/push_notification_service.dart`
- `apps/passenger_app/lib/services/notifications/local_notification_service.dart`
- `apps/passenger_app/lib/services/notifications/passenger_notification_coordinator.dart`

Operator app:

- `apps/operator_app/lib/main.dart`
- `apps/operator_app/lib/routes/main_screen.dart`
- `apps/operator_app/lib/services/notifications/push_notification_service.dart`
- `apps/operator_app/lib/services/notifications/local_notification_service.dart`
- `apps/operator_app/lib/services/notifications/operator_notification_coordinator.dart`
- `apps/operator_app/lib/services/notifications/operator_navigation_alert_bus.dart`
- `apps/operator_app/lib/features/home/presentation/viewmodels/operator_home_view_model.dart`

## Firestore Collections

### `operator_devices`

Stores one push token document per operator UID.

Live-observed fields:

- `token`: FCM registration token.
- `platform`: `android`, `ios`, or `unknown`.
- `appRole`: expected value `operator`.
- `updatedAt`: server timestamp for the latest token write.

Used by:

- Operator app token registration.
- `notifyOperatorsOnIncomingBooking`.
- `notifyBookingStatusChanged` when the assigned operator should receive a status update.
- Invalid-token cleanup after FCM send failures.

### `user_devices`

Stores one push token document per passenger UID.

Live-observed fields:

- `token`: FCM registration token.
- `platform`: `android`, `ios`, or `unknown`.
- `appRole`: expected value `passenger`.
- `updatedAt`: server timestamp for the latest token write.

Used by:

- Passenger app token registration.
- `notifyBookingStatusChanged` when the passenger should receive a booking update.
- Invalid-token cleanup after FCM send failures.

### `operator_presence`

Controls which operators are eligible for incoming booking FCM broadcasts.

Relevant fields:

- `isOnline`: only operators with `isOnline == true` are included in incoming booking notifications.
- `updatedAt`: last presence update.

## Token Registration

### Passenger App Token Registration

Implemented in `Passenger PushNotificationService.startForPassenger`.

Trigger:

- `MainScreen` starts after the passenger is authenticated and has a Firebase UID.

Flow:

1. Request notification permission with alert, badge, and sound enabled.
2. Read current FCM token using `FirebaseMessaging.getToken()`.
3. If token exists, upsert `user_devices/{userId}`:
   - `token`
   - `platform`
   - `appRole: passenger`
   - `updatedAt: FieldValue.serverTimestamp()`
4. Listen to `FirebaseMessaging.onTokenRefresh`.
5. On every refreshed token, upsert the same `user_devices/{userId}` document.
6. Listen to foreground FCM messages through `FirebaseMessaging.onMessage`.

Foreground fallback text:

- Title fallback: `Booking update`
- Body fallback: `You have a new booking notification.`

### Operator App Token Registration

Implemented in `Operator PushNotificationService.startForOperator`.

Trigger:

- `MainScreen` starts after the operator is authenticated and has a Firebase UID.

Flow:

1. Request notification permission with alert, badge, and sound enabled.
2. Read current FCM token using `FirebaseMessaging.getToken()`.
3. If token exists, upsert `operator_devices/{operatorUid}`:
   - `token`
   - `platform`
   - `appRole: operator`
   - `updatedAt: FieldValue.serverTimestamp()`
4. Listen to `FirebaseMessaging.onTokenRefresh`.
5. On every refreshed token, upsert the same `operator_devices/{operatorUid}` document.
6. Listen to foreground FCM messages through `FirebaseMessaging.onMessage`.

Foreground fallback text:

- Title fallback: `Operator update`
- Body fallback: `You have a new notification.`

Important operator-specific behavior:

- Foreground FCM messages with `data.type == incoming_booking` are ignored by `PushNotificationService`.
- Incoming booking foreground behavior is handled by `OperatorNotificationCoordinator` through the live pending-booking stream, because that stream respects local online state and avoids duplicate foreground banners.

## Backend FCM Sending

Backend FCM sending is implemented with `messaging.sendEachForMulticast`.

Shared send options:

- Android priority: `high`
- APNs priority header: `10`
- Includes both `notification` and `data` payloads.

Invalid token cleanup:

- After a multicast send, each failed response is inspected.
- If the error code contains `registration-token-not-registered` or `invalid-registration-token`, the backend searches the target token collection for that token and deletes the matching device document.
- Cleanup collection depends on the send target:
  - Operator sends clean up `operator_devices`.
  - Passenger sends clean up `user_devices`.

Role validation before sending:

- Backend reads device token documents through `getDeviceToken(collection, documentId, expectedRole)`.
- If the document does not exist, no notification is sent.
- If `token` is missing, no notification is sent.
- If `appRole` does not match the expected role, no notification is sent.

## Backend FCM Notifications

### 1. Incoming Booking Request To Online Operators

Function:

- `notifyOperatorsOnIncomingBooking`

Firestore trigger:

- `onDocumentCreated("bookings/{bookingId}")`

Trigger condition:

- A new booking document is created.
- The new booking has `status == pending`.

Skip conditions:

- Booking data is missing.
- Booking status is not `pending`.
- No operator documents in `operator_presence` have `isOnline == true`.
- No valid operator tokens are found in `operator_devices` for online operators.

Recipient:

- Every online operator with a valid `operator_devices/{uid}` document and `appRole == operator`.

Notification title:

- `Incoming booking request`

Notification body:

- `${origin} to ${destination}`
- If fields are missing:
  - origin fallback: `Unknown origin`
  - destination fallback: `Unknown destination`

Data payload:

```text
type: incoming_booking
bookingId: <booking ID>
status: pending
```

Operator app behavior:

- If the OS delivers this while app is backgrounded or terminated, the notification can be displayed by the OS.
- If the operator taps it, `MainScreen` handles `bookingId` from FCM data and switches to the Home tab.
- If the app is foregrounded, `PushNotificationService` suppresses this FCM foreground banner because local pending-booking stream handling is responsible for incoming-booking UI alerts.

### 2. Passenger Booking Status Updated

Function:

- `notifyBookingStatusChanged`

Firestore trigger:

- `onDocumentUpdated("bookings/{bookingId}")`

Trigger condition:

- Existing booking document is updated.
- `before.status != after.status`.

Skip conditions:

- Before or after data is missing.
- Status did not change.
- Booking has no `userId`.
- Passenger has no valid `user_devices/{userId}` token.
- Device document `appRole` is not `passenger`.

Recipient:

- Passenger who owns the booking.

Notification title:

- `Booking status updated`

Data payload:

```text
type: booking_status
bookingId: <booking ID>
status: <new booking status>
origin: <origin or "Unknown origin">
destination: <destination or "Unknown destination">
passengerCount: <passenger count as string, fallback "1">
```

Passenger message bodies by status:

| New status | Body |
| --- | --- |
| `accepted` | `Your operator has accepted <origin> to <destination>.` |
| `on_the_way` | `Your operator is on the way for <origin> to <destination>.` |
| `completed` | `Your trip from <origin> to <destination> is complete.` |
| `cancelled` | `Your booking from <origin> to <destination> was cancelled.` |
| `rejected` | `No operator is available for <origin> to <destination> right now.` |
| any other status | `<origin> to <destination>: <status label>` |

Status-label fallback values:

| Status | Label |
| --- | --- |
| `pending` | `Waiting for operator` |
| `accepted` | `Accepted by operator` |
| `on_the_way` | `Operator is on the way` |
| `completed` | `Trip completed` |
| `cancelled` | `Booking cancelled` |
| `rejected` | `No operator available` |
| other | status text with underscores replaced by spaces |

Passenger app behavior:

- Foreground FCM messages appear as an in-app top info alert.
- Background or terminated taps navigate to `BookingTrackingScreen`.
- FCM tap navigation uses payload fields:
  - `bookingId`
  - `origin`
  - `destination`
  - `passengerCount`
- If `bookingId` is missing, the FCM tap is ignored.

### 3. Operator Booking Status Updated

Function:

- `notifyBookingStatusChanged`

Firestore trigger:

- `onDocumentUpdated("bookings/{bookingId}")`

Trigger condition:

- Existing booking document is updated.
- `before.status != after.status`.
- Updated booking has `operatorUid`, or fallback legacy `operatorId`.

Skip conditions:

- Before or after data is missing.
- Status did not change.
- Updated booking has no operator identity.
- Operator has no valid `operator_devices/{operatorUid}` token.
- Device document `appRole` is not `operator`.

Recipient:

- Assigned operator.

Notification title:

- `Booking status updated`

Data payload:

```text
type: booking_status
bookingId: <booking ID>
status: <new booking status>
```

Operator message bodies by status:

| New status | Body |
| --- | --- |
| `accepted` | `<origin> to <destination> was added to your queue.` |
| `on_the_way` | `<origin> to <destination> is now active.` |
| `completed` | `<origin> to <destination> has been completed.` |
| `cancelled` | `<origin> to <destination> was cancelled by the passenger.` |
| `rejected` | `<origin> to <destination> was declined.` |
| any other status | `<origin> to <destination>: <status label>` |

Operator app behavior:

- Foreground FCM messages appear as an in-app top info alert, except incoming booking FCM messages as noted above.
- Background or terminated FCM taps switch the operator app to the Home tab.
- Current implementation does not deep-open a specific booking card; the Home tab contains the booking queue and active trips.

## Passenger Local Notifications

Passenger local notifications are implemented by `PassengerNotificationCoordinator` and `LocalNotificationService`.

They are generated by the passenger app itself from booking-history stream changes. They do not come from Cloud Functions directly.

### Setup

Trigger:

- Passenger `MainScreen` starts after authentication.

Flow:

1. Create `LocalNotificationService`.
2. Read `getLaunchPayload()` before initialization to detect if a local notification launched the app from a terminated state.
3. Create `PassengerNotificationCoordinator`.
4. Initialize local notifications.
5. Listen to `streamUserBookingHistory(userId)`.
6. Register local notification tap handler.
7. Handle launch payload, if any.

Local channel:

- Channel ID: `passenger_booking_updates`
- Channel name: `Booking Updates`
- Channel description: `Booking status updates for passenger trips`
- Android importance: `Importance.max`
- Android priority: `Priority.high`

### Passenger Local Booking Status Updated

Trigger:

- `PassengerNotificationCoordinator` receives a user booking-history stream update.
- The coordinator has already seeded its initial known statuses.
- A booking's status changes from the last known status.

Skip conditions:

- Initial stream load only seeds state; it does not notify.
- Booking was not previously known.
- Status did not change.

Title:

- `Booking status updated`

Body:

```text
<origin> to <destination>: <local status label>
```

Local status labels:

| Booking status | Label |
| --- | --- |
| `pending` | `Waiting for operator` |
| `accepted` | `Accepted by operator` |
| `on_the_way` | `Operator is on the way` |
| `completed` | `Trip completed` |
| `cancelled` | `Booking cancelled` |
| `rejected` | `No operator available` |
| `unknown` | raw Firestore value |

Foreground behavior:

- If the passenger app is foregrounded, the coordinator calls the foreground notifier.
- `MainScreen` shows an in-app top info alert with the same title/body.

Background behavior:

- If the passenger app is not foregrounded, it calls `showBookingUpdate`.
- Payload is the booking ID only.

Tap behavior:

- Local notification tap calls `_handleNotificationTap`.
- The passenger app navigates to `BookingTrackingScreen`.
- Since local payload contains only the booking ID, route labels default to empty strings and passenger count defaults to `1`; the tracking view model then loads the live booking data.

## Operator Local Notifications

Operator local notifications are implemented by `OperatorNotificationCoordinator` and `LocalNotificationService`.

They are generated by the operator app itself from:

- pending booking stream changes,
- operator booking-history stream changes,
- operator navigation alert bus events,
- operator online/background lifecycle state.

### Setup

Trigger:

- Operator `MainScreen` starts after authentication.

Flow:

1. Create `LocalNotificationService`.
2. Read `getLaunchPayload()` before initialization to detect local-notification launch from terminated state.
3. Create `OperatorNotificationCoordinator`.
4. Initialize local notifications.
5. Listen to `streamOperator(operatorId)` for online/offline state.
6. Listen to `streamPendingBookings()` for queue changes.
7. Listen to `streamOperatorBookingHistory(operatorId)` for assigned-booking status changes.
8. Listen to `OperatorNavigationAlertBus.stream`.
9. Register local notification tap handler.
10. Handle launch payload, terminated-state FCM message, and background FCM taps.

Local channels:

| Channel ID | Name | Description | Use |
| --- | --- | --- | --- |
| `operator_booking_events` | `Booking Events` | `Notifications for incoming requests and booking updates` | Incoming queue, booking status, navigation alerts |
| `operator_online_reminder` | `Online Reminder` | `Persistent reminder when operator is online` | Persistent background online reminder |

Booking events channel:

- Android importance: `Importance.max`
- Android priority: `Priority.high`

Online reminder channel:

- Android importance: default
- Android priority: default
- Category: service
- Ongoing: true
- Auto cancel: false
- Sound: disabled
- Only alert once: true

### Operator Local Incoming Booking Request

Trigger:

- Pending booking stream emits after the initial seed.
- A booking appears whose booking ID was not in the previous pending set.
- Operator is currently online according to `operator_presence`.

Skip conditions:

- Initial stream load only seeds known pending IDs; it does not notify.
- Operator is offline.
- Booking was already known.
- Duplicate delivery occurs within the dedupe window.

Title:

- `Incoming booking request`

Body:

```text
<origin> to <destination>
```

Payload:

- Booking ID.

Foreground behavior:

- Shows an in-app top info alert.

Background behavior:

- Shows a local OS notification on `operator_booking_events`.

Tap behavior:

- Switches to the Home tab.

### Operator Local Booking Status Updated

Trigger:

- Operator booking-history stream emits after the initial seed.
- A booking's status changes from its previously known status.

Skip conditions:

- Initial stream load only seeds known assigned statuses; it does not notify.
- Booking was not previously known.
- Status did not change.
- Duplicate delivery occurs within the dedupe window.

Title:

- `Booking status updated`

Body by status:

| Booking status | Body |
| --- | --- |
| `pending` | `<origin> to <destination> is waiting for an operator.` |
| `accepted` | `<origin> to <destination> was added to your queue.` |
| `on_the_way` | `<origin> to <destination> is now active.` |
| `completed` | `<origin> to <destination> has been completed.` |
| `cancelled` | `<origin> to <destination> was cancelled by the passenger.` |
| `rejected` | `<origin> to <destination> was declined.` |
| `unknown` | `<origin> to <destination> status changed.` |

Foreground behavior:

- Suppressed by `_shouldShowForegroundMessage`.
- Reason: booking status updates are already visible in live cards and grouped pool updates could create banner spam.

Background behavior:

- Shows a local OS notification on `operator_booking_events`.

Tap behavior:

- Switches to the Home tab.

### Operator Route Progress Notification

Source:

- `OperatorHomeViewModel._emitNavigationAlerts`
- Delivered through `OperatorNavigationAlertBus`
- Displayed by `OperatorNotificationCoordinator`

Trigger:

- Operator has navigation guidance for an active `on_the_way` booking.
- Current nearest route marker is greater than the last alert route marker, or no previous alert route marker exists.

Title:

- `Route progress`

Body:

- `You are progressing along the planned river route.`

Payload:

- Booking ID.

Cooldown and dedupe:

- Navigation group cooldown: 2 minutes per booking/title group.
- Event dedupe window: 12 seconds.

Foreground behavior:

- Suppressed by `_shouldShowForegroundMessage`.
- Reason: route progress is already visible in navigation UI.

Background behavior:

- Shows a local OS notification on `operator_booking_events`.

Tap behavior:

- Switches to the Home tab.

### Operator Off-Route Detected Notification

Source:

- `OperatorHomeViewModel._emitNavigationAlerts`
- Delivered through `OperatorNavigationAlertBus`
- Displayed by `OperatorNotificationCoordinator`

Trigger:

- Operator has navigation guidance for an active `on_the_way` booking.
- Guidance changes into an off-route state.
- The booking has not already emitted an off-route alert in the current alert set.

Title:

- `Off-route detected`

Body:

```text
You are about <rounded off-route meters> m from the planned river route. Rejoin the highlighted route to resume guidance.
```

Payload:

- Booking ID.

Cooldown and dedupe:

- Navigation group cooldown: 2 minutes per booking/title group.
- Event dedupe window: 12 seconds.

Foreground behavior:

- Shows an in-app top info alert.

Background behavior:

- Shows a local OS notification on `operator_booking_events`.

Tap behavior:

- Switches to the Home tab.

### Operator Route Resumed Notification

Source:

- `OperatorHomeViewModel._emitNavigationAlerts`
- Delivered through `OperatorNavigationAlertBus`
- Displayed by `OperatorNotificationCoordinator`

Trigger:

- Operator was previously off-route.
- Current guidance is no longer off-route.

Title:

- `Route resumed`

Body:

- `You are back on the planned river route.`

Payload:

- Booking ID.

Cooldown and dedupe:

- Navigation group cooldown: 2 minutes per booking/title group.
- Event dedupe window: 12 seconds.

Foreground behavior:

- Shows an in-app top info alert.

Background behavior:

- Shows a local OS notification on `operator_booking_events`.

Tap behavior:

- Switches to the Home tab.

### Operator Persistent Online Reminder

Trigger:

- Operator presence stream says the operator is online.
- App lifecycle is not foregrounded.

Title:

- `You are online`

Body:

- `You can receive incoming booking requests.`

Behavior:

- Shows through `showOnlineReminder`.
- Notification ID is fixed at `1`.
- Ongoing notification.
- Does not auto-cancel while conditions remain true.
- Sound disabled.
- Only alerts once.

Sync loop:

- When online and backgrounded, a timer re-shows/syncs the reminder every 15 seconds.
- If the operator goes offline or app returns foreground, the reminder timer is cancelled and notification ID `1` is cancelled.

Tap behavior:

- Local notification payload is not used for the reminder.
- Current tap behavior depends on payload availability; event notification taps switch to Home.

## Foreground In-App Alerts

The apps use top alerts for foreground notification delivery instead of always showing OS notifications.

### Passenger Foreground Alerts

Sources:

- Foreground FCM messages from `PushNotificationService`.
- Passenger local booking status stream changes from `PassengerNotificationCoordinator`.

Display:

- `showTopInfo(context, title: ..., message: ...)`

Possible titles:

- `Booking update` fallback from FCM if notification title is missing.
- `Booking status updated` from backend FCM or local coordinator.

Possible bodies:

- Backend passenger status message.
- Local passenger status message.
- `You have a new booking notification.` fallback if foreground FCM body is missing.

### Operator Foreground Alerts

Sources:

- Foreground FCM messages from `PushNotificationService`, except incoming booking FCM is suppressed.
- Operator local pending-booking stream.
- Operator off-route and route-resumed navigation alerts.

Display:

- `showTopInfo(context, title: ..., message: ...)`

Possible titles:

- `Operator update` fallback from FCM if notification title is missing.
- `Incoming booking request`
- `Off-route detected`
- `Route resumed`

Suppressed foreground local titles:

- `Route progress`
- `Booking status updated`

Reason:

- These are already represented in the active UI and would create noisy banners.

## Background And Terminated Handling

### Background FCM Handler

Both apps register:

```text
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler)
```

The background handler:

- Ensures Firebase is initialized.
- Does not perform custom navigation or business logic.
- Lets the OS/FCM system handle notification display and app-launch delivery.

### Passenger FCM Tap Handling

Terminated app:

- `FirebaseMessaging.instance.getInitialMessage()`
- If present, `_handleFcmTap(initialMessage)`.

Background app:

- `FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap)`.

Tap data requirements:

- `bookingId` is required.
- `origin`, `destination`, and `passengerCount` are optional.

Result:

- Opens `BookingTrackingScreen`.

### Passenger Local Notification Tap Handling

Terminated app:

- `LocalNotificationService.getLaunchPayload()` is called before local notification initialization.
- If payload exists, `_handleNotificationTap(payload)`.

Background app:

- `LocalNotificationService.setOnTapHandler(_handleNotificationTap)`.

Payload:

- Booking ID only.

Result:

- Opens `BookingTrackingScreen`.

### Operator FCM Tap Handling

Terminated app:

- `FirebaseMessaging.instance.getInitialMessage()`
- Reads `message.data['bookingId']`, falling back to empty string.
- Calls `_handleNotificationTap`.

Background app:

- `FirebaseMessaging.onMessageOpenedApp.listen(...)`.
- Reads `msg.data['bookingId']`, falling back to empty string.
- Calls `_handleNotificationTap`.

Result:

- Switches to Home tab.

### Operator Local Notification Tap Handling

Terminated app:

- `LocalNotificationService.getLaunchPayload()` is called before local notification initialization.
- If payload exists, `_handleNotificationTap(payload)`.

Background app:

- `LocalNotificationService.setOnTapHandler(_handleNotificationTap)`.

Payload:

- Booking ID for event/navigation notifications.

Result:

- Switches to Home tab.

## Complete Notification Matrix

| App | Source | Notification | Trigger | Foreground behavior | Background/terminated behavior | Tap behavior |
| --- | --- | --- | --- | --- | --- | --- |
| Operator | Backend FCM | `Incoming booking request` | New `bookings/{bookingId}` created with `status == pending`; operator is online; valid token exists | Suppressed by operator push service; local pending stream handles foreground alert | OS FCM notification | Home tab |
| Operator | Local stream | `Incoming booking request` | New pending booking appears after pending stream seed; operator is online | Top info alert | Local OS notification | Home tab |
| Passenger | Backend FCM | `Booking status updated` | Booking status changes and passenger token exists | Top info alert | OS FCM notification | Booking tracking |
| Passenger | Local stream | `Booking status updated` | User booking-history stream sees known booking status change | Top info alert | Local OS notification | Booking tracking |
| Operator | Backend FCM | `Booking status updated` | Booking status changes and assigned operator token exists | Top info alert unless app logic suppresses matching local duplicate separately | OS FCM notification | Home tab |
| Operator | Local stream | `Booking status updated` | Operator booking-history stream sees known booking status change | Suppressed | Local OS notification | Home tab |
| Operator | Navigation alert bus | `Route progress` | Active navigation advances to a newer route marker | Suppressed | Local OS notification | Home tab |
| Operator | Navigation alert bus | `Off-route detected` | Active navigation changes into off-route state | Top info alert | Local OS notification | Home tab |
| Operator | Navigation alert bus | `Route resumed` | Active navigation recovers from off-route state | Top info alert | Local OS notification | Home tab |
| Operator | Local lifecycle/presence | `You are online` | Operator is online and app is backgrounded | Cancelled/not shown | Persistent local OS reminder | No booking-specific navigation |

## Backend Notification Trigger Details

### Incoming Booking Broadcast

The backend checks online operator supply at send time:

1. Query `operator_presence` where `isOnline == true`.
2. For each online operator ID, read `operator_devices/{operatorId}`.
3. Keep token only if `appRole == operator`.
4. Send a multicast notification to collected tokens.
5. Clean up invalid tokens.

This means an operator must satisfy all of these to receive the backend incoming booking push:

- Has authenticated previously and registered a token.
- Has a device token document under `operator_devices/{uid}`.
- Token document has `appRole: operator`.
- `operator_presence/{uid}.isOnline == true`.
- The booking is newly created with `status == pending`.

### Booking Status Change Push

The backend sends to two possible recipients on the same status transition:

- Passenger: `user_devices/{booking.userId}`
- Operator: `operator_devices/{booking.operatorUid || booking.operatorId}`

The backend does not restrict status notifications to a fixed status list. It sends for any status change, but message text has special cases for:

- `accepted`
- `on_the_way`
- `completed`
- `cancelled`
- `rejected`

Other statuses use the fallback label system.

## Dedupe And Noise Control

### Backend

Backend functions do not maintain a send-history dedupe table. They rely on Firestore trigger conditions:

- Incoming booking sends only on document creation and only if status is initially `pending`.
- Status update sends only when `before.status != after.status`.

### Passenger App

Passenger local notification coordinator:

- Seeds booking statuses on initial stream event.
- Only notifies when a known booking changes status.
- Does not currently apply an explicit time-based dedupe window.

### Operator App

Operator notification coordinator:

- Seeds pending booking IDs on initial pending stream event.
- Seeds assigned booking statuses on initial history stream event.
- Uses `_eventDedupeWindow = 12 seconds` per event ID.
- Removes event dedupe entries older than 5 minutes.
- Uses navigation cooldowns:
  - route progress: 2 minutes per booking/title group
  - off-route detected: 2 minutes per booking/title group
  - route resumed: 2 minutes per booking/title group
- Removes navigation group entries older than 10 minutes.

## Permission Behavior

Both apps request notification permissions when notification services start:

- alert: true
- badge: true
- sound: true

Local notification services also request platform-specific permissions:

- Android: `requestNotificationsPermission()`
- iOS: `requestPermissions(alert: true, badge: true, sound: true)`

If permission is denied:

- Token registration may still be attempted depending on FCM behavior.
- Foreground top alerts can still appear inside the app because they are not OS notifications.
- OS-level notification display may not appear.

## Known Behavior And Limitations

- Operator notification taps currently switch to the Home tab but do not deep-open or scroll to a specific booking card.
- Passenger local notification payloads contain only `bookingId`; FCM payloads include route/passenger fields.
- Operator foreground incoming booking FCM is deliberately suppressed because local stream handling already handles it.
- Operator foreground booking status and route progress local alerts are deliberately suppressed to avoid noisy banners.
- Token cleanup only removes tokens that FCM reports as not registered or invalid.
- Device token collections store one document per user/operator UID, so a new token write replaces or merges into the same document rather than storing multiple devices per user.
- Backend incoming booking notifications are tied to `operator_presence.isOnline`; if presence is stale, notification eligibility follows the stale value.
- Both apps initialize Firebase in the background FCM handler, but do not perform custom data processing there.
