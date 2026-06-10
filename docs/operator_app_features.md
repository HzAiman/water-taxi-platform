# Operator App Features, Workflows, and UI

This document describes the operator-facing Flutter application as implemented in `apps/operator_app`. It focuses on every page and major feature surface, including the normal flow, alternative flow, exceptions, user inputs, button outputs, and backend effects.

Source areas used:

- `apps/operator_app/lib/app.dart`
- `apps/operator_app/lib/routes/main_screen.dart`
- `apps/operator_app/lib/features/auth/presentation`
- `apps/operator_app/lib/features/home/presentation`
- `apps/operator_app/lib/features/profile/presentation`
- `apps/operator_app/lib/data/repositories`
- `apps/operator_app/lib/services/notifications`

## App Purpose

The operator app is the supply-side application for Melaka Water Taxi operators. It lets an operator sign in, complete or maintain their operator profile, go online or offline, receive and manage passenger bookings, start pooled routes, complete pickup and dropoff stops, share live location during trips, receive foreground/background alerts, and review/export ride and income summaries.

The app is built with Flutter, Firebase Authentication, Cloud Firestore, Cloud Functions, Firebase Messaging, Google Maps, Provider-based view models, and shared booking/operator models from `packages/water_taxi_shared`.

## Global App Shell and Routing

### AuthWrapper

The app starts at `OperatorApp`, which builds a `MaterialApp` with `AuthWrapper` as the home widget.

The wrapper listens to `FirebaseAuth.instance.idTokenChanges()`.

Normal flow:

1. App launches.
2. `AuthWrapper` waits for the authentication stream.
3. If no Firebase user exists, the operator sees the login page.
4. If a user exists, the wrapper listens to `operators/{uid}`.
5. If the operator document exists, the operator enters the main app.
6. If the operator document does not exist, the operator is sent to first-time profile setup.

Alternative flow:

- If authentication state is still loading, a centered `CircularProgressIndicator` is shown.
- If the operator document is still loading, another centered `CircularProgressIndicator` is shown.
- If auth has a user but `operators/{uid}` is missing, this is treated as a first-time setup state.

Exception flow:

- If the auth stream errors, the app falls back to the login page.
- If the operator document stream errors, the app falls back to the login page.

Output:

- `OperatorLoginPage` when signed out or auth/doc lookup fails.
- `OperatorProfileSetupPage` when signed in but profile is missing.
- `MainScreen` when signed in and profile exists.

### MainScreen

`MainScreen` contains two bottom navigation tabs:

- Home
- Profile

The body is an `IndexedStack`, so both tab pages keep state while the selected tab changes.

Buttons and inputs:

| UI control | Input | Output |
| --- | --- | --- |
| Bottom nav: Home | Tap index `0` | Shows `OperatorHomeScreen`; keeps `OperatorProfilePage` alive in the stack. |
| Bottom nav: Profile | Tap index `1` | Shows `OperatorProfilePage`; keeps `OperatorHomeScreen` alive in the stack. |
| Notification tap | Local notification payload or FCM data `bookingId` | Switches to Home tab. The current implementation does not deep-open a specific booking card; it simply returns to Home. |

Background/session workflow:

1. On startup after the first frame, the screen creates notification services for the signed-in operator.
2. It starts booking/notification coordination and push notification token registration.
3. It listens for navigation alerts and forwards them to local notifications.
4. It handles FCM and local notification launches from terminated/background state.
5. On foreground resume, if the app has been idle long enough, it refreshes the Firebase ID token.

Exception flow:

- If token refresh indicates the session has expired, a top error says `Session expired`, then the app signs out.
- If token refresh fails due to unstable connection, a top info alert says `Session refresh delayed`.

## Authentication: Operator Login Page

File: `operator_login_page.dart` and `operator_login_form.dart`

### UI Layout

The login page uses a full-screen operator brand gradient. The form contains:

- App icon.
- Title: `Melaka Water Taxi`.
- Subtitle: `Operator Login`.
- Email text field.
- Password text field.
- Password visibility toggle icon.
- `Login` button.
- Information panel: `Only registered operators can sign in. Contact the administrator if you need access.`

### Inputs

Email field:

- Keyboard type: email.
- Autocorrect disabled.
- Disabled while login is loading.
- Validation:
  - Empty value -> `Please enter your email`.
  - Missing `@` -> `Please enter a valid email`.

Password field:

- Obscured by default.
- Disabled while login is loading.
- Validation:
  - Empty value -> `Please enter your password`.
  - Length less than 6 -> `Password must be at least 6 characters`.

### Buttons

| Button | Input | Normal output | Alternative output | Exception output |
| --- | --- | --- | --- | --- |
| Password visibility icon | Tap | Toggles password between hidden and visible. | None. | None. |
| Login | Tap after valid form | Calls Firebase email/password sign-in, then reads `operators/{uid}`. | If profile is missing, navigates to first-time setup. If profile exists, auth wrapper naturally moves to main app. | Shows top error for known auth failures or unknown errors. |

### Normal Login Flow

1. Operator enters email and password.
2. Operator taps `Login`.
3. Form validation runs.
4. `_isLoading` becomes true.
5. Firebase Auth signs in using `signInWithEmailAndPassword`.
6. Firestore reads `operators/{uid}`.
7. If the operator document exists, the page allows `AuthWrapper` to route to `MainScreen`.
8. `_isLoading` returns false.

Button output during loading:

- Login button is disabled.
- Login button content changes to a white circular progress indicator.
- Text fields are disabled.

### First-Time Profile Alternative Flow

If authentication succeeds but `operators/{uid}` does not exist:

1. The login page navigates with `pushReplacement` to `OperatorProfileSetupPage`.
2. The setup page receives the authenticated user UID and email.

### Login Exception Flow

Firebase Auth exceptions are mapped to friendly top alerts:

- `user-not-found` -> `No operator found with this email`
- `wrong-password` -> `Incorrect password`
- `invalid-email` -> `Invalid email address`
- `user-disabled` -> `This account has been disabled`
- `too-many-requests` -> `Too many failed attempts. Please try again later`
- Any other Firebase Auth error -> `Login failed: {message}`

General exceptions show:

- Title: `Login failed`
- Message: `An error occurred: {error}`

## First-Time Profile Setup Page

File: `operator_profile_setup_page.dart` and `operator_profile_setup_form.dart`

This page appears when a Firebase user exists but no operator profile document exists.

### UI Layout

The page uses a gradient app bar titled `Complete Your Profile`.

The form contains:

- Badge-style auth hero icon.
- Heading: `First-time setup`.
- Instruction text.
- Full Name text field.
- Operator ID text field.
- Phone Number text field with Malaysia country code prefix.
- Disabled Email field.
- `Save and Continue` button.

### Inputs

Full Name:

- Text capitalization: words.
- Disabled while saving.
- Validation: empty or whitespace-only -> `Please enter your name`.

Operator ID:

- Text capitalization: characters.
- Uses `UpperCaseTextFormatter`.
- Example hint: `OP-001`.
- Disabled while saving.
- Validation: empty or whitespace-only -> `Please enter your operator ID`.
- Before save, the value is normalized with `normalizeOperatorId`.

Phone Number:

- Keyboard type: phone.
- Prefix text: Malaysia country code from `operatorMalaysiaCountryCode`.
- Disabled while saving.
- Validation: empty or whitespace-only -> `Please enter your phone number`.
- Before save, the value is formatted with `formatOperatorMalaysiaPhoneNumber`.

Email:

- Disabled.
- Uses the authenticated account email.
- Not editable on this page.

### Buttons

| Button | Input | Normal output | Alternative output | Exception output |
| --- | --- | --- | --- | --- |
| Save and Continue | Tap after valid form | Calls `OperatorRepository.saveProfile`; creates/merges operator profile, claims unique operator ID, creates/syncs presence. Auth wrapper then moves to main app. | Disabled while saving; shows loading indicator. | Top error with backend or validation failure. |

### Normal Setup Flow

1. Operator signs in for the first time.
2. App detects missing `operators/{uid}`.
3. Operator fills name, operator ID, and phone number.
4. Operator taps `Save and Continue`.
5. Form validation runs.
6. `_isSaving` becomes true.
7. Repository saves:
   - `operators/{uid}` with name, email, operator ID, phone number, timestamps.
   - `operator_id_index/{operatorId}` to reserve the operator ID.
   - `operator_presence/{uid}` with online status.
8. Once the profile document exists, `AuthWrapper` routes to `MainScreen`.

### Alternative Flow

If the backend callable `saveOperatorProfile` is used, it enforces uniqueness and writes the profile server-side.

If direct Firestore mode is used, a transaction claims `operator_id_index/{operatorId}` and removes the old index record if the operator ID changes.

### Exception Flow

Known repository `StateError` messages are shown in a top error with title `Profile setup failed`. Possible examples:

- Missing required fields.
- Operator ID already used.
- Profile backend not deployed.
- Permission denied.
- Backend request failed.

Unknown exceptions show:

- Title: `Profile setup failed`
- Message: `Failed to save profile: {error}`

## Home Page

File: `operator_home_screen.dart`, `operator_booking_panels.dart`, `operator_home_view_model.dart`, `booking_repository.dart`

The Home page is the main operations page. It combines:

- Google Map.
- Operator online/offline state.
- Pending booking queue.
- Active trip panel.
- Pooled route controls.
- Navigation guidance.
- Live location sharing.
- Customer calling.
- Refresh and recovery tools.

### UI Layout

The page is a full-screen map with overlays:

- Google Map in the background.
- Status-bar scrim.
- Top booking/action card area.
- Bottom center `Go Online` or `Go Offline` button.
- Floating camera buttons on the right.
- Loading spinner when the view model is initializing.

If no operator is signed in, the body shows `Not signed in`.

### Initial Runtime Checks

On first load, Home does the following:

1. Shows a welcome top card with the operator label.
2. Checks if Google Maps API key is injected into the Android manifest.
3. Bootstraps current location.
4. Initializes `OperatorHomeViewModel`.
5. Starts active and pending booking streams.
6. Syncs operator presence from Firestore.

Exception outputs:

- Missing Maps key -> top error:
  - Title: `Google Maps key not injected`
  - Message asks to check `android/local.properties` and API key restrictions.
- Location services off -> top info:
  - Title: `Location services off`
  - Message: `Enable location services to show your position.`
  - Action: `Open Settings`
- Location permission permanently denied -> top info:
  - Title: `Permission required`
  - Action: `Open Settings`
- Location lookup error -> top error:
  - Title: `Location error`
  - Message: `Unable to get current location: {error}`
- View model initialization failure -> top error:
  - Title: `Unable to load operator state`
  - Message: raw error text.

### Online and Offline State

When offline:

- The top overlay shows an info card:
  - Title: `You are offline`
  - Subtitle: `Go online to view active trips and pending booking queue.`
- Bottom button is green and labeled `Go Online`.

When online:

- The booking stats card appears.
- Pending and active sections can be expanded.
- Bottom button is red and labeled `Go Offline`.

### Go Online Button

Button:

- Label when offline: `Go Online`
- Icon: power icon
- Disabled when:
  - online/offline toggle is in progress
  - view model is initializing

Normal flow:

1. Operator taps `Go Online`.
2. View model sets local `_isOnline = true` immediately for responsive UI.
3. `OperatorRepository.setOnlineStatus(uid, isOnline: true)` writes `operator_presence/{uid}`.
4. Navigation lifecycle is synced.
5. Top success: `You are now online.`

Exception flow:

- If operator ID is unavailable:
  - Title: `Not initialised`
  - Message: `Operator ID is not available.`
- If status update times out:
  - Title: `Timeout`
  - Message: `Updating status timed out. Check your network.`
  - Local online state rolls back to false.
- If write fails:
  - Title: `Status update failed`
  - Message: raw error text.
  - Local online state rolls back to false.

### Go Offline Button

Button:

- Label when online: `Go Offline`
- Icon: power icon
- Disabled when toggle is in progress or view model is initializing.

Normal flow with no active trip:

1. Operator taps `Go Offline`.
2. If there are accepted but not started bookings, a confirmation dialog appears.
3. If confirmed, or if no accepted bookings exist, the view model calls `goOfflineSafely`.
4. The view model refuses to go offline if any booking is `on_the_way`.
5. Accepted bookings are released back to the queue.
6. Live location sharing stops.
7. `operator_presence/{uid}` is set offline.
8. Success alert is shown.

Confirmation dialog when accepted bookings exist:

- Title: `Go offline?`
- Content: `{count} accepted booking(s) will be released back to the queue.`
- Button: `Cancel`
  - Output: closes dialog, no state change.
- Button: `Go Offline`
  - Output: releases accepted bookings and continues offline workflow.

Possible success outputs:

- If bookings were released:
  - `{count} accepted booking(s) released. You are now offline.`
- If no bookings were released:
  - `You are now offline.`
- If called during logout:
  - `You are now offline and ready to logout.`

Exception and alternative outputs:

- If a trip is already `on_the_way`:
  - Title: `Active trip in progress`
  - Message: `Complete this trip before going offline.`
  - Type: info alert, not hard error.
- If accepted bookings were released but the final online status write timed out:
  - Title: `Offline sync pending`
  - Message explains accepted bookings were released but online status timed out and the app will retry in the background.
- If accepted bookings were released but online status write failed:
  - Title: `Offline sync pending`
  - Message explains accepted bookings were released but online status failed and the app will retry in the background.
- If status write fails before any release:
  - Title: `Status update failed`
  - Local online state returns to previous value.

### Booking Stats Card

Visible only while online.

The stats card shows:

- `Pending Queue` count.
- `Active Trip` count.
- Refresh icon.

Controls:

| Control | Input | Output |
| --- | --- | --- |
| Pending Queue tile | Tap | Expands/collapses the pending queue section. Also collapses Active Trip section. |
| Active Trip tile | Tap | Expands/collapses the active trip section. Also collapses Pending Queue section. |
| Refresh icon | Tap | Calls `refresh(operatorId)`, restarts active/pending streams, increments stream version, then shows top info `Bookings refreshed`. |

Refresh alternative and exception behavior:

- While refreshing, the icon becomes a circular progress indicator.
- While refreshing, the refresh button is disabled.
- The view model keeps existing streams alive until it restarts them.
- Any stream-level data errors are handled by stream listeners and logged; the UI remains driven by last known state.

### Pending Queue Section

Visible when:

- Operator is online.
- `Pending Queue` tile is expanded.

If there is no visible pending booking, the app shows:

- Title: `No pending bookings`
- Subtitle: `You are online. Waiting for passengers...`

Visible pending bookings are filtered:

- Booking must have `status = pending`.
- Booking must not already be assigned to an operator.
- Booking must not include the current operator in `rejectedBy`.
- Booking must not be deferred for the current pool sweep.

The UI shows only the top pending booking card, but the count badge can show multiple bookings in queue.

Pending booking card displays:

- Route: `{origin} -> {destination}`.
- Badge: `Pending` or `{count} in queue`.
- Passenger name, or `Pending Booking` if empty.
- Passenger count.
- Fare, or `Fare N/A`.
- `Call` button (IconButton, filled orange).
- `Reject` button.
- `Accept Booking` button.

#### Accept Booking Button

Normal flow:

1. Operator taps `Accept Booking`.
2. Button becomes disabled and can show a progress indicator.
3. View model attempts to get current operator GPS position.
4. If fresh GPS is unavailable, it falls back to latest known operator position.
5. Repository calls backend callable `acceptPooledBooking`.
6. Backend accepts or defers the booking.
7. On success, the booking is locally promoted into active bookings for quick UI response.
8. Streams refresh.
9. Top success or info alert is shown.

Input sent to backend:

- `bookingId`
- optional `operatorLat`
- optional `operatorLng`
- optional `locationUpdatedAt`
- optional `routeDirection` when supplied by repository caller

Normal success output:

- Message from backend if provided.
- Otherwise: `Booking accepted successfully.`

Alternative output:

- If backend returns status `deferred`:
  - Title: `Queued for later route`
  - Message from backend or `This request is queued for a later route sweep.`
  - Type: info alert.
  - Booking is removed locally from the visible pending card and streams refresh.

Exception outputs:

- Backend `failed-precondition`, `unimplemented`, `not-found`, or `unavailable` are treated as info-level failures.
- Timeout:
  - Title: `Connection is slow`
  - Message: `Accepting this booking is taking too long. Refresh and try again.`
- Unknown error:
  - Title: `Accept failed`
  - Message: `Could not accept booking: {error}`
- If another booking operation is already in progress:
  - Title: `Busy`
  - Message: `Another operation is in progress.`

#### Reject Button

Normal flow:

1. Operator taps `Reject`.
2. Button disables during operation.
3. Repository calls backend callable `rejectPooledBooking`.
4. The booking remains pending globally for other operators.
5. Current operator is excluded from seeing it again.
6. The booking is removed locally.
7. Streams refresh.

Normal success output:

- Backend message if provided.
- Otherwise: `Booking rejected. It stays pending for other operators.`

Exception outputs:

- Backend failure:
  - Title: `Unable to reject booking`
  - Message from backend or `Could not reject this booking.`
- Timeout:
  - Title: `Connection is slow`
  - Message: `Rejecting this booking is taking too long. Refresh and try again.`
- Unknown error:
  - Title: `Reject failed`
  - Message: `Could not reject booking: {error}`
- Busy operation:
  - Title: `Busy`
  - Message: `Another operation is in progress.`

### Active Trip Section

Visible when:

- Operator is online.
- `Active Trip` tile is expanded.

If there is no active booking:

- Title: `No active trip`
- Subtitle: `Accept a booking from the queue to start operating.`

Active bookings include:

- `accepted`
- `on_the_way`

They are sorted so `on_the_way` comes first, then by `poolSequence`, then by updated time.

The active card can represent a single booking or a pooled group.

Active card display:

- Header:
  - `Ready To Start` for accepted bookings.
  - `Trip Route` for on-the-way bookings.
- Direction badge:
  - `Forward`
  - `Reverse`
  - fallback label when route direction is absent.
- Current stop summary.
- Next stop preview.
- Stale accepted booking warning if accepted for 5 minutes or more.
- Collapsible `View route order`.
- Collapsible `Active booking list`.
- Optional `Active pool` preview for multiple bookings.
- `Release` and `Start Route` buttons when accepted.

#### View Route Order Expand/Collapse

Input:

- Tap row labeled `View route order`.

Output:

- Toggles a compact route timeline.
- Shows each stop, its action, stop name, current/completed state, and pickup/dropoff icon.
- No backend call.

#### Active Booking List Expand/Collapse

Input:

- Tap row labeled `Active booking list`.

Output:

- Toggles a scrollable list of active pool bookings.
- Each row shows passenger name, route, and call button.
- No backend call until a call icon is tapped.

#### Call Customer Button

Location:

- Inside `Active booking list` rows.
- Inside Pending booking cards (`Pending Queue Section`).

Normal flow:

1. Operator taps call icon for a passenger.
2. App reads `booking.userPhone`.
3. If phone exists, method channel `operator_app/phone` invokes `dial`.
4. Native dialer opens with the number.

Alternative and exception outputs:

- If no phone exists:
  - Title: `No phone number`
  - Message: `This booking does not include a customer phone number.`
- If the native dialer cannot open or the method channel throws:
  - Title: `Unable to open dialer`
  - Message: `Please call the customer manually: {phone}`

#### Release Button

Visible only when booking status is `accepted`.

Normal flow:

1. Operator taps `Release`.
2. Repository runs a Firestore transaction.
3. Transaction checks the booking exists.
4. Transaction checks status is `accepted`.
5. Transaction checks the booking belongs to the current operator.
6. Booking is set back to `pending`.
7. `operatorUid` is cleared.
8. Current operator ID is added to `rejectedBy`.
9. Status history is appended.
10. Top success is shown.

Normal success output:

- `Booking released back to the queue.`

Exception outputs:

- Booking no longer exists:
  - Title: `Unable to release booking`
  - Message: `This booking no longer exists.`
- Booking is not accepted or belongs to another operator:
  - Title: `Unable to release booking`
  - Message: `Only your accepted booking can be released.`
- Unknown failure:
  - Title: `Release failed`
  - Message: `Could not release booking: {error}`

#### Start Route Button

Visible only when booking status is `accepted`.

Normal flow:

1. Operator taps `Start Route`.
2. The app resolves which booking should start for the current pool stop.
3. View model attempts to get current position.
4. Repository calls backend callable `startPooledBooking`.
5. Backend moves route/booking to `on_the_way`.
6. View model starts location sharing for the returned tracking booking.
7. Streams refresh.
8. Active section collapses.
9. Navigation card appears.

Input sent to backend:

- `bookingId`
- optional `operatorLat`
- optional `operatorLng`

Normal success output:

- If backend starts a different first booking in the pool:
  - `Route started at the first pool stop.`
- Otherwise:
  - `Route started successfully.`

Exception outputs:

- Backend failure:
  - Title: `Unable to start trip`
  - Message from backend or `Backend trip sequencing is unavailable. Please refresh and try again.`
- Timeout:
  - Title: `Connection is slow`
  - Message: `Starting this route is taking too long. Refresh and try again.`
- Unknown error:
  - Title: `Start failed`
  - Message: `Could not start trip: {error}`

### Navigation Card

Visible when:

- There is an active booking.
- Booking status is `on_the_way`.

Card title:

- `Now Navigating`

The card can display:

- Current stop action and stop name.
- Remaining distance.
- ETA.
- Route warning.
- Primary action button.

Remaining distance logic:

- If live location is stale -> `Waiting for live location`.
- If navigation guidance indicates progress should pause -> `Rejoin river route`.
- If guidance is unavailable -> `N/A`.
- Otherwise -> formatted meters or kilometers.

ETA logic:

- If live location is stale -> `N/A`.
- If guidance says ETA should pause -> `N/A`.
- If ETA is low-confidence -> prefixed with `~`.
- Otherwise -> minutes/hours formatted from guidance.

Route warning outputs:

- Live location stale -> `Waiting for fresh GPS.`
- Missed stop -> `Missed stop. Return to {stopName}.`
- Slight overshoot -> `Passed stop slightly. Return safely.`
- Severe off-route -> `Too far from river route. Move closer to the river before trusting guidance.`

Primary action label depends on stop state:

- No current stop and passenger not picked up -> `Passenger Picked Up`
- No current stop and passenger picked up -> `Complete Trip`
- Single pickup stop -> `Mark Picked Up`
- Single dropoff stop -> `Complete Trip`
- Grouped pickup stop -> `Complete Pickup Stop`
- Grouped dropoff stop -> `Complete Dropoff Stop`

#### Navigation Primary Action Button

Normal pickup flow:

1. Operator reaches a pickup stop.
2. Operator taps `Mark Picked Up` or `Complete Pickup Stop`.
3. Repository calls backend callable `markPoolStopReached`.
4. Stop is completed server-side.
5. View model marks pickup locally for responsiveness.
6. Streams refresh.
7. Top success says:
   - `Picked up 1 booking at {stopName}.`
   - or `Picked up {count} bookings at {stopName}.`

Normal dropoff/final flow:

1. Operator reaches a dropoff stop.
2. Operator taps `Complete Trip` or `Complete Dropoff Stop`.
3. Repository calls backend callable `markPoolStopReached`.
4. Stop or trip is completed server-side.
5. View model marks completion locally.
6. Streams refresh.
7. App recenters user location without feedback when completion succeeds.
8. Top success says:
   - `Dropped off 1 booking at {stopName}.`
   - or `Dropped off {count} bookings at {stopName}.`

Generic backend success messages:

- Pickup repository default: `Pool stop completed.`
- Complete repository default: `Pool stop completed successfully.`

Alternative flow:

- If marking passenger picked up fails because Firestore rules block custom marker fields, the view model marks pickup locally and returns:
  - `Passenger marked as picked up.`

Exception outputs:

- Backend failure:
  - Title: `Unable to complete stop`
  - Message from backend or `Backend pool stop validation is unavailable. Please refresh and try again.`
- Timeout:
  - Title: `Connection is slow`
  - Message: `Completing this stop is taking too long. Refresh and try again.`
- Unknown pickup failure:
  - Title: `Update failed`
  - Message: `Could not complete stop: {error}`
- Unknown complete failure:
  - Title: `Complete failed`
  - Message: `Could not complete trip: {error}`
- Busy operation:
  - Title: `Busy`
  - Message: `Another operation is in progress.`

### Live Location Sharing

Live location sharing starts when a trip starts and there is an `on_the_way` booking.

Normal flow:

1. Operator taps `Start Route`.
2. Current position is read.
3. Location stream starts.
4. Operator position is published to active booking documents.
5. Tracking document `tracking/{bookingId}` is updated for high-frequency reads.
6. A refresh timer polls location if GPS callbacks stall.
7. Navigation guidance updates with route progress, ETA, heading, off-route state, and stop overshoot state.

Publish throttling:

- Minimum interval: 6 seconds.
- Minimum movement: 20 meters.
- First publish is always allowed when there is no previous publish.

Alternative flow:

- If GPS position is unavailable at accept/start time, the app can use the last known position.
- If tracking booking changes, location sharing restarts for the new booking.
- If the app detects stale live location after 45 seconds, the navigation card displays stale-location text.

Exception flow:

- Location publish failures are normalized through operation results and debug logs.
- Permission-denied/session errors are converted to:
  - Title: `Permission denied`
  - Message: `Your sign-in session could not be refreshed. Please sign in again if this continues.`

### Map Controls

#### 2D/3D Button

Location:

- Right floating button stack.

Input:

- Tap button labeled `2D` or `3D`.

Output:

- Calls `OperatorMapControllerService.toggleMapTilt()`.
- If currently tilted in navigation mode, label shows `2D`.
- If currently flat, label shows `3D`.
- No backend call.

#### Recenter / Resume Navigation Button

There are two near-me button modes:

1. While active navigation is running and the user has moved the map manually, a magenta near-me button resumes route-following camera mode.
2. While not actively navigating, a white near-me button centers on the operator's current location.

Normal center-on-user flow:

1. Operator taps near-me.
2. App checks if the map is ready.
3. App checks/resolves location permission.
4. App gets current position.
5. Camera animates to current position at zoom 16.

Exception and alternative outputs:

- If map is still loading:
  - Title: `Please wait`
  - Message: `Map is still loading.`
- If location services are off:
  - Title: `Location services off`
  - Action: `Open Settings`
- If permission permanently denied:
  - Title: `Permission required`
  - Action: `Open Settings`
- If location lookup fails:
  - Title: `Location error`
  - Message: `Unable to get location: {error}`

### Navigation Alerts and Notifications

Foreground:

- Booking and FCM foreground messages can display top info alerts.
- Navigation alert bus events are delivered to the notification coordinator.

Background:

- Local notifications can be delivered for queue changes, booking status updates, route progress, off-route detection, route resumed, and persistent online reminder behavior.
- Tapping a local or push notification returns the app to the Home tab.

Navigation alert examples:

- Route progress:
  - Title: `Route progress`
  - Body: `You are progressing along the planned river route.`
- Off-route:
  - Title: `Off-route detected`
  - Body includes approximate meters away from planned river route.
- Route resumed:
  - Title: `Route resumed`
  - Body: `You are back on the planned river route.`

## Profile Page

File: `operator_profile_page.dart`, `operator_profile_header.dart`, `operator_profile_menu.dart`

The Profile tab shows operator identity details and menu actions.

### UI Layout

When loading:

- Centered `CircularProgressIndicator`.

When loaded:

- Profile header:
  - Operator name or `Operator`.
  - Email.
  - Operator ID as `ID: {id}` or `ID: N/A`.
  - Phone number or `Phone: Not set`.
- Menu:
  - `Account Management`
  - `Ride / Transaction Summary`
  - `Logout`

### Initial Load Flow

1. Page reads `FirebaseAuth.instance.currentUser`.
2. If there is no user, loading ends and the page stays with fallback text values.
3. If user exists, repository reads `operators/{uid}` and `operator_presence/{uid}`.
4. Controllers and display variables are populated.

Exception flow:

- If profile load fails:
  - Title: `Profile error`
  - Message: `Failed to load profile`

### Account Management Menu Item

Input:

- Tap `Account Management`.

Output:

- Pushes `OperatorAccountManagementPage`.

No backend write occurs on tap.

### Ride / Transaction Summary Menu Item

Input:

- Tap `Ride / Transaction Summary`.

Normal output:

- Creates `OperatorTransactionSummaryViewModel`.
- Passes:
  - booking repository
  - current user UID
  - operator display name
  - operator display ID
- Pushes `OperatorTransactionSummaryPage`.

Exception output:

- If no Firebase user is signed in:
  - Title: `Not signed in`
  - Message: `Sign in again to view transaction summary.`

### Logout Button

Input:

- Tap `Logout`.

Confirmation dialog:

- Title: `Logout`
- Content: `Logging out will set you offline and release accepted bookings back to the queue. Active trips must be completed first.`
- Button: `Cancel`
  - Output: closes dialog; no logout.
- Button: `Logout`
  - Output: proceeds with safe logout.

Normal logout flow:

1. Operator taps `Logout`.
2. Confirmation dialog appears.
3. Operator confirms.
4. `_isLoggingOut` becomes true.
5. If user exists, home view model initializes for that UID.
6. App calls `goOfflineSafely(reason: logout)`.
7. Accepted bookings are released.
8. Presence is set offline.
9. Firebase signs out.
10. Navigation pops to the first route.
11. Auth wrapper shows login.

Alternative flow:

- If there is no user, the app skips the offline call and signs out.

Exception flow:

- If an active trip is in progress, `goOfflineSafely` returns:
  - Title: `Active trip in progress`
  - Message: `Complete this trip before going offline.`
  - Logout stops and `_isLoggingOut` resets.
- If offline status update times out after releasing bookings, logout stops with `Offline sync pending`.
- If any unexpected error occurs:
  - Title: `Logout failed`
  - Message: raw error text.

## Account Management Page

File: `operator_account_management_page.dart`, `operator_account_form.dart`

This page lets an operator view and edit profile fields except email.

### UI Layout

The page has a gradient app bar titled `Account Management`.

The form contains:

- Full Name field.
- Operator ID field.
- Phone Number field with Malaysia country code prefix.
- Email Address field.
- Helper text: `Email is managed by your login account and cannot be changed here.`
- Action area:
  - `Edit Profile` when not editing.
  - `Save Changes` and `Cancel` when editing.

### Inputs

Full Name:

- Disabled until edit mode.
- Validation in edit mode: empty -> `Name cannot be empty`.

Operator ID:

- Disabled until edit mode.
- Uppercase formatter.
- Validation in edit mode: empty -> `Operator ID cannot be empty`.
- Normalized before save.

Phone Number:

- Disabled until edit mode.
- Keyboard type: phone.
- Validation in edit mode: empty -> `Phone number cannot be empty`.
- Local part is shown in the input.
- Full Malaysian format is saved.

Email:

- Always disabled.
- Comes from Firebase Auth email or operator document email.
- Cannot be changed here.

### Buttons

| Button | Input | Normal output | Alternative output | Exception output |
| --- | --- | --- | --- | --- |
| Edit Profile | Tap | Sets `_isEditing = true`; enables editable fields; swaps action area to Save/Cancel. | None. | None. |
| Save Changes | Tap after valid form | Calls `OperatorRepository.saveProfile`; saves name, normalized operator ID, formatted phone, email; exits edit mode; shows success. | Disabled while saving. | Top error with repository or unknown error. |
| Cancel | Tap while editing | Exits edit mode and reloads profile from backend, discarding unsaved local changes. | Disabled while saving. | If reload fails internally, no explicit top alert in this page's reload method. |

### Normal Edit Flow

1. Operator opens Account Management.
2. Page loads current profile.
3. Fields are read-only.
4. Operator taps `Edit Profile`.
5. Name, operator ID, and phone become editable.
6. Operator changes values.
7. Operator taps `Save Changes`.
8. Validation runs.
9. Repository saves profile with operator ID uniqueness handling.
10. Page exits edit mode.
11. Top success: `Profile updated successfully`.

### Cancel Flow

1. Operator taps `Cancel`.
2. Page exits edit mode.
3. `_loadProfile()` runs.
4. Backend values overwrite unsaved field changes.

### Exception Flow

Repository `StateError`:

- Title: `Profile update failed`
- Message: repository message, such as duplicate operator ID or backend deployment issue.

Unknown exception:

- Title: `Profile update failed`
- Message: `Failed to update profile: {error}`

If no Firebase user exists:

- Save returns without doing anything.
- Load returns without doing anything.

## Ride / Transaction Summary Page

File: `operator_transaction_summary_page.dart`, `operator_transaction_summary_view_model.dart`, `operator_transaction_summary_widgets.dart`

This page lets operators inspect period earnings summaries, a quick 3-ride preview, saved PDF statements, and navigate to a detailed full-screen ride history log.

### UI Layout

The page has a gradient app bar titled `Ride / Transaction Summary`.

Loading state:

- Centered `CircularProgressIndicator`.

Error state:

- Centered text with the error message.

Loaded sections:

1. `Completed Rides`
2. `Summary by Period`
3. `Detailed Ride History`
4. `Income Documents / Statements`

### Data Loading Flow

1. Page initializes the summary view model.
2. View model loads saved statement records from `SharedPreferences`.
3. View model subscribes to `streamOperatorBookingHistory(operatorId)`.
4. Booking history streams from Firestore where `operatorUid == operatorId`, limited to 500 docs.
5. History is sorted newest first by `updatedAt` or `createdAt`.

Exception flow:

- If booking stream errors:
  - `_error = Failed to load ride history: {error}`
  - Page displays the error text.
- If saved statements JSON is invalid:
  - Statement list becomes empty.

### Completed Rides Section

Displays metric chips:

- `Today`
- `This Week`
- `This Month`

Counting logic:

- Counts only bookings with status `completed`.
- Uses `updatedAt` or `createdAt`.
- Today starts at local midnight.
- Week starts on Monday.
- Month starts on the first day of the month.

No buttons in this section.

### Summary by Period Section

Controls:

- Period choice chips:
  - `Daily`
  - `Weekly`
  - `Monthly`
  - `Yearly`
  - `Custom`
- Date range display.
- Summary rows:
  - `Total Earnings`
  - `Pending or Active Rides`
  - `Cancelled Rides`
- Export PDF button.

#### Period Choice Chips

Daily:

- Input: tap `Daily`.
- Output: selects today's start/end.

Weekly:

- Input: tap `Weekly`.
- Output: selects Monday through Sunday of current week.

Monthly:

- Input: tap `Monthly`.
- Output: selects first through last day of current month.

Yearly:

- Input: tap `Yearly`.
- Output: selects January 1 through December 31 of current year.

Custom:

- Input: tap `Custom`.
- Output: opens `showDateRangePicker`.
- Date picker first date: 5 years before current year.
- Date picker last date: December 31 of next year.
- If previous custom range exists, it is used as initial range.
- Otherwise, today is used as initial range.

Custom date alternative flows:

- If user cancels picker, selected period remains unchanged.
- If user picks a reversed range, the view model normalizes start/end.
- Custom start is normalized to start of day.
- Custom end is normalized to end of day.

### Export Statement PDF Button

Button label:

- Normal: `Export {selected period} Statement (PDF)`
- Loading: `Generating Statement...`

Normal export flow:

1. Operator taps export.
2. View model checks if an export is already in progress.
3. `_isExporting` becomes true.
4. History for the selected period is used.
5. PDF bytes are generated.
6. PDF includes:
   - Melaka Water Taxi heading.
   - Operator name.
   - Operator ID.
   - Statement period.
   - Generated timestamp.
   - Completed rides count.
   - Cancelled rides count.
   - Total earnings.
   - Completed trip table with route, passengers, adults, children, fare, trip date, booking time.
7. PDF is saved under app documents directory in `operator_statements`.
8. A `StatementRecord` is added to local statement history.
9. Statement records are saved to `SharedPreferences`.
10. `Printing.layoutPdf` immediately opens the interactive PDF preview layout for viewing and printing.
11. Top success: `Statement generated, saved, and ready to view or print.`

File naming:

- `operator_statement_{period}_{timestamp}.pdf`

Exception and alternative outputs:

- If export is already in progress:
  - Title: `Export in progress`
  - Message: `Please wait for the current export to finish.`
- If PDF generation, file writing, preferences, or sharing fails:
  - Title: `Statement export failed`
  - Message: `Could not generate PDF statement: {error}`

### Detailed Ride History Section

On the main Transaction Summary page, the operator is presented with a **quick preview** showing up to the **3 most recent rides** for the selected statement period.

Beneath the preview, an outlined button **`See All History ({count})`** transitions the operator to a dedicated, full-screen **`OperatorDetailedRideHistoryPage`**.

#### Detailed Ride History Screen Controls

Inside the dedicated history page, the operator has access to the following:

- **History filter chips** (All, Completed, Cancelled, Active) to filter records in memory.
- **Search field** (Search by route, status, passenger name, or phone number) with a clear button.
- **Scrollable ride history list** of `RideHistoryTile`s with bouncing physics.

#### History Filter Chips

All:

- Shows all bookings in selected period that match search query.

Completed:

- Shows only `completed` bookings.

Cancelled:

- Shows only `cancelled` bookings.

Active:

- Shows bookings with status:
  - `pending`
  - `accepted`
  - `on_the_way`

Output:

- Updates list immediately in memory.
- No backend call.

#### Search Field

Input:

- Free text.

Search matches against:

- Booking ID.
- Passenger name.
- Passenger phone.
- Origin.
- Destination.
- Booking status Firestore value.

Output:

- Query is trimmed and lowercased.
- Ride history list updates immediately.
- Empty query matches all bookings for the selected period/filter.

#### Ride History Tile Output

Each tile shows:

- Route `{origin} -> {destination}` with fallback `Pickup`/`Dropoff`.
- Status badge.
- Passenger name or `Passenger`.
- Phone number or `No phone number`.
- Passenger count group:
  - Total
  - Adults
  - Children
- Payment method label.
- Payment status label.
- Booked timestamp or `Unknown`.

Empty state:

- `No rides found for selected filters.`

### Income Documents / Statements Section

If no statements are saved:

- Text: `No saved statements yet.`

If statements exist, each statement tile shows:

- File name.
- Period label and date range.
- Generated timestamp.
- Completed rides.
- Earnings.
- `View` button.
- `Share` button.
- `Delete` button.

#### View Statement Button

Normal flow:

1. Operator taps `View`.
2. App checks if the PDF file exists under `operator_statements/{fileName}.pdf`.
3. If file exists, layout is parsed and PDF viewer opens directly.

Exception output:

- If file is missing:
  - Title: `Statement missing`
  - Message: `The saved statement file was not found on this device.`
- If open fails:
  - Title: `Open failed`
  - Message: `Could not open statement: {error}`

#### Share Statement Button

Normal flow:

1. Operator taps `Share`.
2. View model checks if the PDF file exists at the stored path.
3. File bytes are read.
4. `Printing.sharePdf` opens the native share sheet.
5. Top success: `Statement shared successfully.`

Exception flow:

- If file does not exist:
  - Title: `Statement missing`
  - Message: `The saved statement file was not found on this device.`
- If read/share fails:
  - Title: `Share failed`
  - Message: `Could not share statement: {error}`

#### Delete Statement Button

Normal flow:

1. Operator taps `Delete`.
2. View model checks if file exists.
3. If file exists, it is deleted.
4. Statement record is removed from memory.
5. Updated statement records are saved to `SharedPreferences`.
6. UI refreshes.
7. Top success: `Statement removed.`

Alternative flow:

- If file is already missing, the record is still removed from statement history.

Exception flow:

- Title: `Delete failed`
- Message: `Could not delete statement: {error}`

## Backend Data and Side Effects by Feature

### Operator Profile

Collections/documents:

- `operators/{uid}`
- `operator_id_index/{operatorId}`
- `operator_presence/{uid}`

Fields written include:

- name
- email
- operatorId
- phoneNumber
- createdAt
- updatedAt
- isOnline in presence

### Presence

Collection:

- `operator_presence/{uid}`

Online/offline writes:

- `isOnline`
- `updatedAt`

### Booking Queue

Collection:

- `bookings`

Pending stream:

- `status == pending`
- ordered by `createdAt`
- filtered client-side to unassigned bookings.

Active stream:

- `operatorUid == operatorId`
- client-side filtered to `accepted` and `on_the_way`.

### Booking Actions

Callable functions:

- `acceptPooledBooking`
- `rejectPooledBooking`
- `startPooledBooking`
- `markPoolStopReached`

Direct Firestore/transaction paths also exist for repository test or non-callable mode.

### Location Tracking

Booking fields updated:

- `operatorLat`
- `operatorLng`
- location updated timestamp fields from shared schema.

Tracking documents:

- `tracking/{bookingId}`

### Statements

Local storage:

- App documents directory: `operator_statements/{fileName}.pdf`
- SharedPreferences key prefix: `operator_statement_records_v1_{operatorId}`

## Important Exception Patterns

### Busy State

Only one booking operation is allowed at a time.

If another operation is already running:

- Title: `Busy`
- Message: `Another operation is in progress.`

### Permission / Session Errors

If an operation fails with Firestore permission/session text, the app normalizes it to:

- Title: `Permission denied`
- Message: `Your sign-in session could not be refreshed. Please sign in again if this continues.`

### Slow Connection

Callable booking actions have timeouts. The UI shows info-level failures for slow calls and suggests refresh/retry.

### Active Trip Safety

The app prevents these unsafe exits:

- Going offline while a trip is `on_the_way`.
- Logging out while a trip is `on_the_way`.

Accepted but not-started bookings can be released back to queue when going offline or logging out.

## Complete Button Inventory

| Page | Button/control | Input | Output |
| --- | --- | --- | --- |
| Login | Password visibility | Tap | Toggles password visible/hidden. |
| Login | Login | Tap | Validates form, signs in, routes to setup or main app, or shows error. |
| Profile Setup | Save and Continue | Tap | Validates and saves operator profile; auth wrapper routes to main app. |
| Main Shell | Home tab | Tap | Shows Home tab. |
| Main Shell | Profile tab | Tap | Shows Profile tab. |
| Home | Go Online | Tap | Sets presence online, shows success or error. |
| Home | Go Offline | Tap | May confirm release of accepted bookings, sets presence offline, shows success/info/error. |
| Home | Go offline dialog Cancel | Tap | Closes dialog, no state change. |
| Home | Go offline dialog Go Offline | Tap | Releases accepted bookings and attempts offline presence write. |
| Home | Pending Queue tile | Tap | Expands/collapses pending queue section. |
| Home | Active Trip tile | Tap | Expands/collapses active trip section. |
| Home | Refresh bookings | Tap | Restarts streams and shows `Bookings refreshed`. |
| Home | Accept Booking | Tap | Accepts or defers pending booking; updates UI and alerts. |
| Home | Reject | Tap | Rejects booking for this operator; removes from visible queue. |
| Home | Release | Tap | Releases accepted booking back to pending queue. |
| Home | Start Route | Tap | Starts pooled route, begins location sharing, shows navigation. |
| Home | View route order | Tap | Expands/collapses route stop timeline. |
| Home | Active booking list | Tap | Expands/collapses passenger booking list. |
| Home | Call icon | Tap | Opens dialer or shows manual-call/no-phone alert. |
| Home | Navigation primary action | Tap | Completes pickup/dropoff stop or trip, updates route state. |
| Home | 2D/3D | Tap | Toggles map tilt. |
| Home | Near-me center | Tap | Centers map on operator location. |
| Home | Near-me resume navigation | Tap | Restores navigation-follow camera mode. |
| Profile | Account Management | Tap | Opens account management page. |
| Profile | Ride / Transaction Summary | Tap | Opens transaction summary or shows not-signed-in alert. |
| Profile | Logout | Tap | Opens logout confirmation. |
| Profile | Logout dialog Cancel | Tap | Closes dialog. |
| Profile | Logout dialog Logout | Tap | Goes offline safely, releases accepted bookings, signs out. |
| Account Management | Edit Profile | Tap | Enables editable profile fields. |
| Account Management | Save Changes | Tap | Validates and saves profile, exits edit mode, shows success/error. |
| Account Management | Cancel | Tap | Discards unsaved edits and reloads backend profile. |
| Transaction Summary | Daily chip | Tap | Selects daily period. |
| Transaction Summary | Weekly chip | Tap | Selects weekly period. |
| Transaction Summary | Monthly chip | Tap | Selects monthly period. |
| Transaction Summary | Yearly chip | Tap | Selects yearly period. |
| Transaction Summary | Custom chip | Tap | Opens date range picker and applies custom range if selected. |
| Transaction Summary | Export PDF | Tap | Generates, saves, records, and opens the PDF statement preview. |
| Transaction Summary | See All History | Tap | Opens the dedicated, full-screen Detailed Ride History screen. |
| Transaction Summary | Statement View | Tap | Opens the saved PDF locally using printing layout viewer. |
| Transaction Summary | Statement Share | Tap | Shares saved PDF or shows missing/share error. |
| Transaction Summary | Statement Delete | Tap | Deletes local file/record and updates UI. |
| Detailed Ride History | History filter chips | Tap | Filters ride list in memory. |
| Detailed Ride History | Search field | Text input | Filters ride list by booking, passenger, route, phone, or status. |

