# Passenger App Features

Last updated: 2026-06-02

Source: code inspection of `apps/passenger_app/lib`, shared booking/payment models, and existing project documentation.

This document explains every passenger-facing page currently implemented in the Flutter passenger app. It covers the visible UI, feature purpose, normal flow, alternative flow, exception flow, button input/output behavior, and the main Firestore/payment side effects.

## App Shell And Session Flow

### Entry Point: `PassengerApp` And `AuthWrapper`

Files:

- `apps/passenger_app/lib/app.dart`
- `apps/passenger_app/lib/routes/main_screen.dart`

Purpose:

- Decide whether the passenger sees the phone login flow or the authenticated app.
- Keep authenticated sessions alive through Firebase ID token changes.
- Recover stale sessions when the app returns from the background.
- Host the bottom navigation for Home and Profile.
- Handle FCM taps, local notification taps, and app links that target a booking.

UI:

- While Firebase auth is resolving, the app shows a centered loading spinner.
- If Firebase emits an authenticated user, the app opens `MainScreen`.
- If Firebase emits no user or an auth stream error, the app opens `PhoneLoginPage`.
- `MainScreen` has two bottom navigation items:
  - `Home`, with home outline and active home icons.
  - `Profile`, with profile outline and active profile icons.

Normal flow:

1. App starts.
2. `AuthWrapper` subscribes to `FirebaseAuth.instance.idTokenChanges()`.
3. If the stream returns an authenticated user, `MainScreen` is displayed.
4. `MainScreen` starts notification handling after the first frame:
   - Gets current user ID.
   - Creates `PassengerNotificationCoordinator`.
   - Starts passenger local notification monitoring.
   - Registers local notification tap handling.
   - Handles terminated-state FCM messages.
   - Handles terminated-state local-notification payloads.
   - Listens for background FCM taps.
   - Starts foreground push notification alerts.
5. Passenger uses bottom navigation to switch between Home and Profile.

Alternative flows:

- If the app is opened through a deep link with `bookingId` or `booking_id`, `MainScreen` opens `BookingTrackingScreen`.
- If the app is opened through a payment-return link with only `status`, `MainScreen` shows a top info alert: `Payment returned with status: ...`, then switches to Home.
- If an FCM message contains booking data, tapping it opens the related booking tracking page.
- If a local notification payload contains only a booking ID, tapping it opens tracking with fallback empty origin/destination and passenger count 1.
- If the passenger returns from the background after at least 5 minutes, `MainScreen` refreshes the Firebase ID token.

Exception flows:

- If session refresh fails with a token/auth error that requires login, the app shows `Session expired`, signs out, and lets the auth wrapper return to login.
- If session refresh fails for network/temporary reasons, the app shows `Session refresh delayed`.
- If app-links initialization fails, the app continues running and ignores deep link startup behavior.
- If notification startup has no user ID, notification setup is skipped.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| Bottom nav `Home` | Tap index 0 | Sets `_selectedIndex = 0`; Home page becomes body. |
| Bottom nav `Profile` | Tap index 1 | Sets `_selectedIndex = 1`; Profile page becomes body. |
| Notification/deep-link booking navigation | `bookingId`, optional `origin`, `destination`, `passengerCount` | Pushes `BookingTrackingScreen` with a `BookingTrackingViewModel`. |

## Authentication: Phone Login Page

File:

- `apps/passenger_app/lib/features/auth/presentation/pages/phone_login_page.dart`

Purpose:

- Let passengers authenticate with Firebase phone authentication.
- Support country code selection.
- Send OTP.
- Route existing users to the main app.
- Route new users to registration.
- Handle Firebase OTP throttling, server lockout, auto-retrieval, and friendly error messages.

UI:

- Country dropdown with these options:
  - Malaysia `+60`
  - Singapore `+65`
  - Indonesia `+62`
  - Thailand `+66`
  - Philippines `+63`
  - Vietnam `+84`
  - Cambodia `+855`
  - Laos `+856`
  - Myanmar `+95`
  - Brunei `+673`
- Phone number text field.
- Primary button labeled `Send OTP Code`.
- Loading state while Firebase is requesting an OTP.

Inputs:

- `selectedCountry`: one of the country dropdown labels.
- `phoneNumber`: trimmed text from the phone number field.
- Generated `fullPhoneNumber`: country code plus phone number.

Normal flow:

1. Passenger selects a country or keeps Malaysia as default.
2. Passenger enters a phone number.
3. Passenger taps `Send OTP Code`.
4. App validates that the phone number is not empty.
5. App checks `OtpRequestThrottle.remainingFor(fullPhoneNumber)`.
6. If not throttled, app calls `FirebaseAuth.instance.verifyPhoneNumber`.
7. When Firebase emits `codeSent`, app records a 60-second cooldown.
8. App pushes `OTPScreen` with:
   - `verificationId`
   - `phoneNumber`
   - `resendToken`
9. Passenger continues verification on the OTP page.

Alternative flows:

- Android auto-retrieval can call `verificationCompleted` before manual OTP entry. The app signs in with the credential, marks auto sign-in as completed, and routes after authentication.
- If code is sent but Firebase already has a current user due to auto sign-in, the app stops loading and does not push another OTP screen.
- If `codeAutoRetrievalTimeout` fires, the latest verification ID is retained for manual verification.

Exception flows:

- Empty phone number: top error `Please enter a phone number`; no Firebase call.
- Passenger requests another OTP too soon: top error `Please wait`; message includes remaining cooldown.
- Firebase rate limit/server block: app records a 5-minute lockout and shows a friendly OTP request failure.
- Firebase request failure: loading stops and top error `OTP request failed` appears.
- Generic request failure: loading stops and app shows a request failure message.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| Country dropdown | Country label | Updates `_selectedCountry`; changes phone prefix used for OTP. |
| Phone text field | User typed digits/text | Updates `_phoneController.text`; output is trimmed on submit. |
| `Send OTP Code` | Tap | Disabled while loading. On success pushes `OTPScreen`; on failure shows top alert. |

Data and external side effects:

- Firebase phone auth sends an SMS OTP.
- Auth timing is logged in debug output.
- Local throttle maps store next allowed OTP request times in memory.

## Authentication: OTP Screen

File:

- `apps/passenger_app/lib/features/auth/presentation/pages/phone_login_page.dart`

Purpose:

- Let passengers enter the 6-digit OTP.
- Verify the OTP with Firebase.
- Resend OTP after cooldown or session expiry.
- Route signed-in users to either registration or the main app.

UI:

- Back icon button.
- Title `Verify Code`.
- The phone number being verified.
- Six single-digit OTP text fields.
- Countdown or resend section:
  - Before resend is allowed: `Resend code in X seconds` or `Try again in X seconds`.
  - After resend is allowed: text button `Resend OTP Code`.
  - After OTP session expiry: text button `Request a new OTP`.
- Primary button `Verify & Log In`.
- Loading state while verifying or resending.

Inputs:

- `verificationId` from Firebase.
- `phoneNumber` from phone login.
- Optional `resendToken`.
- Six text boxes that form `_otpCode`.

Normal flow:

1. OTP screen starts with 60-second validity/cooldown timer.
2. Passenger enters one digit per box.
3. On each digit:
   - Non-digits are stripped.
   - If multiple digits are pasted, the app fills consecutive OTP boxes.
   - Focus moves forward as digits are entered.
4. Passenger taps `Verify & Log In` or submits the last OTP field.
5. App checks session expiry.
6. App checks that the OTP has exactly 6 digits.
7. App creates a `PhoneAuthProvider.credential`.
8. App signs in through `FirebaseAuth.instance.signInWithCredential`.
9. App calls `_routeAfterPhoneAuthentication`.
10. App reads `users/{uid}`.
11. If the user document exists, it clears navigation and opens `MainScreen`.
12. If the user document does not exist, it clears navigation and opens `RegistrationPage`.

Alternative flows:

- If Firebase auth state changes while OTP screen is open, the app can route after existing authentication.
- If auto-retrieval completes during resend, app signs in and routes without manual OTP input.
- If a resend succeeds, app updates `verificationId`, updates resend token, resets the OTP session, clears all OTP fields, restarts the timer, and shows `OTP code sent again`.
- If the first OTP session expires, resend is allowed immediately as `Request a new OTP`; the old fields are cleared.

Exception flows:

- Expired session: verification is blocked and top error says the code session expired; passenger must request a new OTP.
- Empty or non-6-digit OTP: top error `Please enter a valid 6-digit code`.
- Invalid code: top error `Verification failed`; message says the code is incorrect and passenger should check latest SMS.
- Session expired or invalid verification ID: app marks session expired, clears fields, and allows a new request.
- Firebase verification fails but `currentUser` is already available: app routes after existing authentication instead of trapping the user.
- Resend attempted during cooldown or server lockout: top error `Please wait`; message includes remaining time.
- Resend Firebase failure: app restarts timer and shows `OTP request failed`.
- Generic verify failure: app shows `Unable to verify the code right now. Please try again.`

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| Back icon | Tap | Calls `Navigator.maybePop()` unless verifying. |
| OTP boxes | One digit or pasted digits | Stores numeric digits, auto-advances focus, can fill multiple boxes from paste. |
| Last OTP field submit | Keyboard done | Calls `_verifyOTP()`. |
| `Verify & Log In` | Tap | Disabled while verifying. On success routes to Main or Registration; on failure shows top alert. |
| `Resend OTP Code` | Tap | Calls Firebase `verifyPhoneNumber` with optional resend token; updates OTP session on success. |
| `Request a new OTP` | Tap after session expiry | Requests a new OTP without relying on the old session. |

Data and external side effects:

- Signs in Firebase Auth user.
- Reads `users/{uid}` to decide whether profile registration is required.
- May request a new OTP SMS.

## Registration Page

File:

- `apps/passenger_app/lib/features/auth/presentation/pages/registration_page.dart`

Purpose:

- Collect profile data for a newly authenticated passenger.
- Create or merge `users/{uid}`.
- Route the passenger into the main app.

UI:

- App bar `Complete Registration`.
- Welcome icon.
- Title `Welcome to Melaka Water Taxi!`.
- Subtitle `Please complete your profile`.
- Read-only phone number display.
- Text field `Full Name`.
- Text field `Email Address`.
- Primary button `Complete Registration`.

Inputs:

- `phoneNumber` passed from OTP/auth flow.
- `name`: trimmed text.
- `email`: trimmed text.

Normal flow:

1. Passenger enters name and email.
2. Passenger taps `Complete Registration`.
3. App validates name and email.
4. App reads `FirebaseAuth.instance.currentUser`.
5. App writes `users/{uid}` with:
   - `uid`
   - `phoneNumber`
   - `name`
   - `email`
   - `createdAt`
   - `updatedAt`
6. App shows success alert `Registration completed successfully!`.
7. After a short delay, app clears navigation and opens `MainScreen`.

Alternative flows:

- Existing user fields are merged through Firestore `SetOptions(merge: true)`, so registration can update an existing partial document instead of replacing everything.

Exception flows:

- Empty name: top error `Please enter your name`.
- Name shorter than 2 characters: top error `Name must be at least 2 characters`.
- Empty email: top error `Please enter your email address`.
- Invalid email: top error `Please enter a valid email address`.
- Missing authenticated Firebase user: top error `User not authenticated. Please login again.`
- Missing phone number: top error `Phone number is missing`.
- Firestore/Firebase exception: top error `Firebase error: ...`.
- Generic exception: top error with the exception message.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| Full Name field | Text | Stored in `_nameController`; disabled while loading. |
| Email Address field | Text | Stored in `_emailController`; disabled while loading. |
| `Complete Registration` | Tap | Disabled while loading. Validates, writes Firestore profile, routes to Main on success. |

Data side effects:

- Writes or merges `users/{uid}`.
- Does not create any booking data.

## Main Home Page

File:

- `apps/passenger_app/lib/features/home/presentation/pages/home_screen.dart`
- `apps/passenger_app/lib/features/home/presentation/viewmodels/home_view_model.dart`

Purpose:

- Greet the passenger.
- Load available jetties.
- Let passenger choose pickup and drop-off locations.
- Let passenger choose adult and child counts.
- Prevent double booking when an active booking exists.
- Verify operator availability and fare before payment.
- Provide quick access to current active booking.

UI:

- Gradient header:
  - `Hello,`
  - passenger name or fallback `Passenger`
  - `Where would you like to go today?`
- Optional `Current Booking` card if an active booking exists:
  - status chip
  - route
  - adult/child count
  - operator summary
  - button `View Booking Status`
- `Pick-up Location` dropdown.
- `Drop-off Location` dropdown.
- Same-origin warning if pickup and drop-off are identical.
- Adult counter:
  - minus icon
  - count label
  - plus icon
  - helper `Age 13 and above`
- Child counter:
  - minus icon
  - count label
  - plus icon
  - helper `Age 12 and under`
- Primary button `Book Water Taxi`.
- Fare checking helper text while validating route fare.

Initialization:

1. Home listens for Firebase ID token user.
2. Home loads passenger profile name.
3. Home loads all jetties.
4. Home subscribes to the user's active booking stream.
5. On app resume, if jetties failed or initialization did not finish, Home attempts recovery at most every 6 seconds.

Inputs:

- Selected pickup jetty name.
- Selected drop-off jetty name.
- Adult count from 0 to 10, but UI starts at 1 and adult decrement is disabled below 1.
- Child count from 0 to 10.
- Firebase current user.

Normal booking flow:

1. Passenger opens Home.
2. Jetties load from Firestore.
3. Passenger chooses a pickup dropdown item.
4. App opens `JettyLocationScreen` for map confirmation.
5. Passenger confirms a pickup jetty.
6. Passenger chooses a drop-off dropdown item.
7. App opens `JettyLocationScreen` for map confirmation.
8. Passenger confirms a drop-off jetty.
9. Passenger adjusts adult/child passenger counts.
10. `Book Water Taxi` becomes enabled only when:
    - pickup is selected,
    - drop-off is selected,
    - pickup and drop-off differ,
    - passenger count is greater than 0,
    - no active booking exists,
    - fare check is not in progress.
11. Passenger taps `Book Water Taxi`.
12. App checks the current Firebase user.
13. App verifies at least one operator is online.
14. App fetches fare for the selected route using canonical jetty IDs.
15. If fare exists, app pushes `PaymentScreen` with origin, destination, adult count, and child count.

Alternative flows:

- If passenger selects a pickup that matches the current drop-off, Home resets the drop-off and shows `Drop-off location was reset. Please choose a different destination.`
- If the active booking stream returns an active booking, the `Current Booking` card appears and the booking button is disabled.
- Tapping `View Booking Status` opens `BookingTrackingScreen` for that booking.
- If loading user profile fails, Home still works with display name `Passenger`.
- If active booking stream errors, Home treats active booking as null.

Exception flows:

- No current Firebase user: top error `Please sign in to continue.`
- Missing pickup/drop-off: top error `Please select both pick-up and drop-off locations.`
- Same pickup/drop-off: top error `Pick-up and drop-off locations cannot be the same.`
- Invalid passenger count: top error `Please select at least one passenger.`
- Existing active booking: top error telling the passenger to view current booking status first.
- No online operators: top error `No operator is available right now. Please try again later.`
- No fare for route: top error `No fare is available for this route yet. Please select another route.`
- Operator/fare check throws: top error `Unable to verify operator availability or fare. Please try again.`
- Jetty loading fails: dropdown area shows `Failed to load jetties`.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| Pickup dropdown | Jetty name | Opens map confirmation. Confirmed result sets `selectedOrigin`; may reset matching destination. |
| Drop-off dropdown | Jetty name | Opens map confirmation. Confirmed result sets `selectedDestination` if different from origin. |
| Adult minus | Tap | If adult count > 1, decrements adults by 1. Disabled at 1. |
| Adult plus | Tap | If adult count < 10, increments adults by 1. Disabled at 10. |
| Child minus | Tap | If child count > 0, decrements children by 1. Disabled at 0. |
| Child plus | Tap | If child count < 10, increments children by 1. Disabled at 10. |
| `Book Water Taxi` | Tap | Runs auth/operator/fare checks. On success opens Payment. On failure shows top error. |
| `View Booking Status` | Tap from active booking card | Opens Booking Tracking for the active booking. |

Data side effects:

- Reads `users/{uid}`.
- Reads `jetties`.
- Reads `fares`.
- Reads `operator_presence` through booking repository availability check.
- Streams active `bookings` for the current passenger.

## Jetty Location Confirmation Page

File:

- `apps/passenger_app/lib/features/home/presentation/pages/jetty_location_screen.dart`

Purpose:

- Let passenger visually confirm a pickup or drop-off jetty on Google Maps.
- Allow changing the selected jetty from a bottom-card dropdown before returning to Home.

UI:

- App bar title:
  - `Confirm Pick-up` for pickup.
  - `Confirm Drop-off` for drop-off.
- Full-screen Google Map.
- Marker for the selected jetty.
- Floating my-location button.
- Bottom card with:
  - label `Pick-up Location` or `Drop-off Location`
  - jetty dropdown
  - primary button `Confirm Location`

Inputs:

- `initialJettyName`.
- `allJetties`: list of maps with `name`, `jettyId`, `lat`, `lng`.
- `isPickup`.
- Optional device location permission.

Normal flow:

1. Screen opens with the selected jetty.
2. App checks location service and permission.
3. Map centers on the selected jetty at zoom 18.
4. Marker displays the jetty name and ID.
5. Passenger can change the jetty from the dropdown.
6. Changing the dropdown updates the marker and animates camera to the new jetty.
7. Passenger taps `Confirm Location`.
8. Screen pops and returns the selected jetty name to Home.

Alternative flows:

- If location permission is granted, the user's current location layer is enabled.
- If passenger taps the my-location button, app obtains current device position and moves map camera to it.
- If initial jetty name is not found in the provided list, screen falls back to the first jetty.

Exception flows:

- Location service disabled: permission state remains false; map still works without my-location layer.
- Permission denied: my-location layer remains disabled.
- Permission denied forever: my-location layer remains disabled.
- `Geolocator.getCurrentPosition()` errors are not explicitly caught in this screen, so platform permission/location errors can surface through Flutter error handling.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| Jetty dropdown | Jetty name | Updates selected jetty, marker, and camera target. |
| My-location FAB | Tap | Gets current device position and animates map to it. |
| `Confirm Location` | Tap | Pops route with selected jetty name. |

Data side effects:

- No Firestore writes.
- Uses Google Maps and device geolocation APIs.

## Payment Page

Files:

- `apps/passenger_app/lib/features/home/presentation/pages/payment_screen.dart`
- `apps/passenger_app/lib/features/home/presentation/viewmodels/payment_view_model.dart`

Purpose:

- Display trip summary and fare details.
- Apply Stripe minimum charge adjustment when needed.
- Request a manual-capture payment authorization through the payment gateway.
- Create a booking document only after payment authorization succeeds.
- Navigate to booking tracking.

UI:

- App bar `Payment`.
- Loading state:
  - spinner
  - `Loading fare information...`
- Fare error state:
  - error icon
  - error text
  - button `Go Back`
- Successful fare state:
  - `Trip Summary`
  - pickup
  - drop-off
  - passenger summary
  - `Fare Details`
  - adult fare per person and subtotal when adult count > 0
  - child fare per person and subtotal when child count > 0
  - base fare and minimum payment adjustment when adjustment exists
  - total fare
  - primary button `Continue to Payment (RM X.XX)`

Inputs:

- `origin`
- `destination`
- `adultCount`
- `childCount`
- current Firebase user ID
- route fare from Firestore
- passenger user profile
- selected origin/destination jetty documents

Normal flow:

1. Payment screen initializes.
2. `PaymentViewModel.loadFare` resolves canonical origin and destination jetty IDs.
3. App fetches fare for the selected route.
4. App verifies fare has a snapshot ID.
5. App calculates:
   - adult subtotal
   - child subtotal
   - base total
   - minimum charge adjustment
   - payable total
6. Passenger reviews trip summary and fare details.
7. Passenger taps `Continue to Payment`.
8. App validates current Firebase user.
9. App loads user profile and both jetty documents.
10. App builds a payment attempt ID and idempotency key.
11. App reserves a unique order number in `order_number_index`.
12. App calls the payment gateway with:
    - user ID
    - amount
    - currency `MYR`
    - order number
    - payer name
    - payer email
    - payer phone
    - payment method `stripe_payment_sheet`
    - idempotency key
    - payment description
13. Stripe Payment Sheet authorizes or succeeds.
14. App creates `bookings/{bookingId}` with passenger, route, fare, payment, and route polyline data.
15. App shows top info `Payment Authorized`.
16. App clears back stack until the first route and pushes `BookingTrackingScreen`.

Alternative flows:

- If fare is below Stripe's minimum MYR charge, payment total includes `minimum payment adjustment`.
- If passenger profile name is blank, payer name falls back to `Passenger`.
- If passenger email is blank, payer email falls back to `passenger+{uid}@water-taxi.local`.
- Order number reservation retries up to 5 variants if a collision occurs.
- Payment gateway `success` is accepted the same as `authorized`.

Exception flows:

- User not authenticated: top error `User not authenticated.`
- Canonical jetty ID missing while loading fare: fare error `Canonical jetty ID missing for selected route`.
- Fare not found: fare error `Fare not found for this route`.
- Fare snapshot missing: fare error `Fare snapshot unavailable for this route`.
- Fare load exception: fare error `Failed to load fare information`.
- Origin jetty missing during payment: failure `Jetty "..." not found.`
- Destination jetty missing during payment: failure `Jetty "..." not found.`
- Canonical jetty missing during booking creation: failure `Canonical jetty ID is required for booking creation.`
- Payment cancelled by passenger: info alert `Payment cancelled`; no booking is created.
- Payment declined/failed: error alert `Payment failed`.
- Booking creation fails after payment authorization: app attempts to cancel the payment intent with reason `booking_creation_failed`, then reports `Could not complete booking: ...`.
- Order number collision after max attempts: payment flow fails with the thrown state error.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| `Go Back` | Tap in fare error state | Pops Payment and returns to Home. |
| `Continue to Payment (RM X.XX)` | Tap | Disabled while processing. Opens Stripe flow, creates booking on success, opens tracking. |

Data side effects:

- Reads `jetties`.
- Reads `fares`.
- Reads `users/{uid}`.
- Writes `order_number_index/{orderNumber}` reservation.
- Calls Stripe/payment Cloud Function through `PaymentGatewayService`.
- Writes `bookings/{bookingId}` after payment authorization.
- May call cancel-payment function if booking creation fails after authorization.

## Booking Tracking Page

Files:

- `apps/passenger_app/lib/features/home/presentation/pages/booking_tracking_screen.dart`
- `apps/passenger_app/lib/features/home/presentation/viewmodels/booking_tracking_view_model.dart`

Purpose:

- Stream one booking in real time.
- Merge booking and tracking data through the repository.
- Display route, markers, live operator location, status, payment, ETA, and operator contact details.
- Let passengers cancel cancellable bookings.
- Let passengers call an assigned operator when a phone number is available.

UI before booking loads:

- App bar `Booking Status`.
- Loading spinner.
- If loading takes more than 6 seconds:
  - message `Loading booking details is taking longer than expected.`
  - helper `You can retry now or keep waiting for sync.`
  - button `Retry Sync`
- If tracking stream errors:
  - wifi-off icon
  - error message
  - button `Retry`

UI after booking loads:

- Full-screen Google Map:
  - route polyline when available
  - fallback origin-destination route when needed
  - origin marker
  - destination marker
  - operator marker when operator location exists
  - camera auto-fits route and follows operator updates
- Draggable bottom sheet:
  - status ripple dot
  - status title and message
  - rejected payment notice when relevant
  - status timeline: `Request`, `Assigned`, `Trip`, `Done`
  - location status notice when operator is missing or stale
  - ETA card when ETA can be calculated
  - compact route card
  - passengers tile
  - payment method/status tile
  - assigned operator card when operator UID exists
  - state guidance message when pending/rejected
  - primary action button: `Cancel Booking`, `Book Again`, or `Close`

Status title and message outputs:

| Booking status | Title | Message | Primary action |
| --- | --- | --- | --- |
| `pending` | `Booking Request Pending` | Waiting for an operator to accept your booking request. | `Cancel Booking` if cancellable. |
| `accepted` | `Booking Confirmed` | An operator has accepted your booking. | Usually `Cancel Booking` if shared status extension allows it. |
| `on_the_way` | `Trip In Progress` | Your assigned operator is currently handling this trip. | Usually `Close` unless shared status says cancellable. |
| `completed` | `Trip Completed` | This booking has been completed successfully. | `Close`. |
| `cancelled` | `Booking Cancelled` | This booking was cancelled. | `Close`. |
| `rejected` | `Booking Rejected` | No operator is available right now. Please try again later. | `Book Again`, but implemented output is close current screen. |
| `unknown` | `Booking Updated` | This booking has been updated. | `Close`. |

Normal flow:

1. Screen opens with a booking ID.
2. `BookingTrackingViewModel.startTracking(bookingId)` subscribes to booking updates.
3. Repository streams the booking, including tracking/operator location when available.
4. Map renders route, origin, destination, and operator marker.
5. Bottom sheet renders current status, route, passenger count, payment method/status, and operator card.
6. If status and coordinates support ETA, app calculates and displays an ETA.
7. If booking remains active, the stream updates UI as status/location changes.

Alternative flows:

- If booking document has empty origin/destination, screen falls back to the route values passed in navigation.
- If booking passenger count is missing or zero, screen falls back to navigation passenger count.
- If route polyline is unavailable, map uses origin/destination points when valid.
- If operator location is present and recent, map follows the operator point at controlled intervals.
- If operator location exists but booking `updatedAt` is older than 35 seconds during `on_the_way`, screen shows delayed-location notice.
- If operator is `on_the_way` but no operator coordinates exist, screen shows `Locating operator. Live position will appear shortly.`
- If rejected payment status includes `refunded`, `cancelled`, `authorized`, or `paid`, the screen shows a specific payment outcome message.

Cancellation normal flow:

1. Passenger taps `Cancel Booking`.
2. App shows confirmation dialog.
3. Passenger taps dialog `Cancel Booking`.
4. View model checks that booking details are loaded.
5. View model checks `booking.status.canBeCancelledByPassenger`.
6. If transaction ID and order number exist, app calls payment gateway cancel with reason `passenger_cancelled_booking`.
7. If payment cancellation succeeds, app updates booking status through `BookingRepository.cancelBooking`.
8. App shows `Booking cancelled successfully.`
9. After 900 ms, screen closes.

Cancellation exception flows:

- Passenger taps dialog `Keep Booking`: dialog closes; booking remains active.
- Booking not loaded: info alert `Booking unavailable`.
- Status no longer cancellable: info alert `Cancellation unavailable`.
- Payment cancellation returns error other than `NOT_FOUND`: error alert `Refund failed`.
- Payment cancellation returns `NOT_FOUND`: app allows booking cancellation to proceed because payment may already be handled differently.
- Booking cancel write fails due to session/permission issue: error alert `Session needs refresh`.
- Booking cancel write fails generically: error alert `Cancel failed`.

Call operator flow:

1. Assigned operator card appears when `operatorUid` exists.
2. Card displays operator name or fallback `Operator`.
3. Card displays operator public ID or `Operator ID: Unavailable`.
4. Call icon is enabled only when `assignedOperatorPhone` is non-empty.
5. Passenger taps call icon.
6. App calls platform method channel `passenger_app/phone` method `dial` with `{ phone }`.
7. If platform opens dialer, no alert is shown.
8. If platform returns false or throws, app shows info alert telling the passenger to call manually.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| `Retry` | Tap during tracking error | Restarts tracking stream for last booking ID. |
| `Retry Sync` | Tap during slow load | Restarts tracking stream for last booking ID. |
| Bottom sheet drag handle | Drag | Expands/collapses tracking details between configured sheet sizes. |
| `Cancel Booking` primary button | Tap | Opens cancellation confirmation dialog. |
| Dialog `Keep Booking` | Tap | Closes dialog with false; no booking/payment change. |
| Dialog `Cancel Booking` | Tap | Cancels payment hold when possible, then writes cancelled booking status. |
| `Book Again` primary button | Tap for rejected status | Calls `_closeTrackingScreen`; returns to previous page to start a new booking manually. |
| `Close` primary button | Tap for non-cancellable statuses | Closes tracking page. |
| Operator call icon | Tap with phone | Opens native dialer or shows manual-call alert. |
| Operator call icon disabled | No phone | No action; tooltip says phone number unavailable. |

Data side effects:

- Streams `bookings/{bookingId}`.
- Reads/merges `tracking/{bookingId}` through repository.
- May call payment cancel Cloud Function.
- May update booking status to `cancelled`.
- May write status history/archive through repository/cloud behavior depending on backend implementation.

## Profile Main Page

Files:

- `apps/passenger_app/lib/features/profile/presentation/pages/profile_screen.dart`
- `apps/passenger_app/lib/features/profile/presentation/viewmodels/profile_view_model.dart`

Purpose:

- Show passenger profile summary.
- Navigate to account management.
- Navigate to booking history.
- Log out.

UI:

- Gradient header:
  - passenger name or fallback `Passenger`
  - phone number from Firebase Auth or user document
- Menu tile `Account Management`.
- Menu tile `Booking History`.
- Outlined red `Logout` button.
- Loading spinner while profile is loading and no user data is available.

Normal flow:

1. Profile page loads current Firebase UID.
2. `ProfileViewModel.loadProfile(uid)` reads `users/{uid}`.
3. Header displays profile name and phone number.
4. Passenger taps a menu item or logs out.

Alternative flows:

- If user document is missing or name is blank, header uses `Passenger`.
- Phone number falls back through test value, Firebase current user phone, user document phone, then empty string.

Exception flows:

- `loadProfile` has no explicit error output; loading stops in the view model's `finally`, and the page falls back to available data.
- If no Firebase user exists, profile loading is skipped.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| `Account Management` tile | Tap | Pushes account management route. |
| `Booking History` tile | Tap | Pushes booking history route. |
| `Logout` | Tap | Opens logout confirmation dialog. |
| Logout dialog `Cancel` | Tap | Closes dialog; remains signed in. |
| Logout dialog `Logout` | Tap | Signs out Firebase user, clears navigation, opens `PhoneLoginPage`. |

Data side effects:

- Reads `users/{uid}`.
- Logout signs out Firebase Auth.

## Account Management Page

Files:

- `apps/passenger_app/lib/features/profile/presentation/pages/profile_screen.dart`
- `apps/passenger_app/lib/features/profile/presentation/viewmodels/profile_view_model.dart`

Purpose:

- Display and update passenger name/email.
- Display immutable login phone number.
- Delete passenger account after confirmation and recent-login check.

UI:

- App bar `Account Management`.
- Form fields:
  - `Full Name`
  - `Email Address`
  - `Phone Number`
- Helper text: phone number is managed by login account and cannot be changed here.
- Initial button `Edit Profile`.
- Editing buttons:
  - `Save Changes`
  - `Cancel`
- Red outlined `Delete Account` button.
- Loading spinner while initial profile data is loading.

Inputs:

- Name text.
- Email text.
- Current Firebase user metadata.
- Current Firebase phone number.

Normal edit flow:

1. Page loads current Firebase user.
2. Phone field is filled from Firebase user phone number.
3. View model loads `users/{uid}`.
4. Name and email fields are filled from profile or Firebase email fallback.
5. Fields are read-only until passenger taps `Edit Profile`.
6. Passenger edits name/email.
7. Passenger taps `Save Changes`.
8. Form validates name and email.
9. View model updates `users/{uid}` with new name and email.
10. If email changed and is non-empty, app calls `currentUser.verifyBeforeUpdateEmail(nextEmail)`.
11. Editing ends.
12. App shows either:
    - `Profile updated. Check your email to confirm the new address.`
    - `Profile updated successfully.`

Alternative edit flows:

- Passenger taps `Cancel` while editing. App exits edit mode and resets fields from current view model/Firebase values.
- If profile data is unavailable, email may still fall back to Firebase email.
- If profile data saves but email verification cannot start, app shows info alert explaining that profile was saved but verification failed, then exits edit mode.

Edit exception flows:

- Name empty while editing: field error `Name cannot be empty`.
- Email empty while editing: field error `Email cannot be empty`.
- Invalid email: field error `Enter a valid email address`.
- No current Firebase user: top error `User not authenticated.`
- Repository update fails: top error `Update failed`; message includes failure reason.

Normal delete flow:

1. Passenger taps `Delete Account`.
2. App shows delete confirmation dialog.
3. Passenger taps dialog `Delete`.
4. App checks current Firebase user.
5. App checks whether last sign-in is within 5 minutes.
6. If recent enough, view model deletes `users/{uid}`.
7. App calls `currentUser.delete()` to delete Firebase Auth account.
8. App signs out.
9. App clears navigation and opens `PhoneLoginPage`.

Alternative delete flows:

- If last sign-in time is missing or older than 5 minutes, app shows reauthentication dialog.
- If passenger confirms re-login, app signs out and opens `PhoneLoginPage`.
- Booking records may remain for operational and financial auditing, as stated in the dialog.

Delete exception flows:

- Delete dialog `Cancel`: no data changes.
- No current Firebase user: top error `User not authenticated.`
- Profile delete fails: top error `Delete failed`.
- Firebase Auth delete requires recent login, user token expired, or invalid token: app prompts reauthentication.
- Firebase Auth delete other exception: top error `Error deleting account: ...`.

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| `Edit Profile` | Tap | Enables name/email editing and reveals save/cancel buttons. |
| Name field | Text | Updates pending name; validated on save. |
| Email field | Text | Updates pending email; validated on save. |
| Phone field | None | Always disabled; display only. |
| `Save Changes` | Tap | Validates and writes profile; may start Firebase email verification. |
| `Cancel` | Tap | Exits edit mode and restores form values. |
| `Delete Account` | Tap | Opens delete confirmation dialog. |
| Delete dialog `Cancel` | Tap | Closes dialog; no deletion. |
| Delete dialog `Delete` | Tap | Deletes profile/Auth account or prompts reauth. |
| Reauth dialog `Cancel` | Tap | Closes dialog; account remains. |
| Reauth dialog `Re-login` | Tap | Signs out and opens login page. |

Data side effects:

- Reads `users/{uid}`.
- Updates `users/{uid}` name/email.
- May trigger Firebase email verification before email update.
- Deletes `users/{uid}`.
- Deletes Firebase Auth user.
- Signs out Firebase Auth.

## Booking History Page

Files:

- `apps/passenger_app/lib/features/profile/presentation/pages/profile_screen.dart`
- `apps/passenger_app/lib/features/profile/presentation/viewmodels/profile_view_model.dart`

Purpose:

- Stream and display passenger booking history.
- Filter history by all, active, completed, or cancelled/rejected bookings.
- Surface payment outcome messages for cancelled/rejected bookings.

UI:

- App bar `Booking History`.
- If no user: `Please sign in to view your bookings.`
- Loading state card:
  - icon
  - `Syncing your bookings`
  - `Please wait while we load your latest booking history.`
- Error state card:
  - icon
  - `Unable to load booking history`
  - connection retry message
  - button `Retry`
- Empty state card:
  - `No bookings yet`
  - `Your completed and upcoming water taxi bookings will appear here.`
- Filter chips:
  - `All`
  - `Active`
  - `Completed`
  - `Cancelled`
- Booking cards:
  - route
  - status chip
  - passengers
  - operator summary
  - payment method/status
  - payment outcome message when applicable
  - booked timestamp
  - stale active booking notice when active and not updated for more than 5 minutes
  - total fare

Normal flow:

1. Page gets current user ID.
2. `ProfileViewModel.startBookingHistoryStream(uid)` starts a stream.
3. Repository streams booking history.
4. Loading state disappears when first list arrives.
5. Page shows filter chips and booking cards.
6. Passenger taps filters to narrow the list.

Filter behavior:

- `All`: every streamed booking.
- `Active`: bookings where `booking.status.isActive`.
- `Completed`: bookings with `BookingStatus.completed`.
- `Cancelled`: bookings with `BookingStatus.cancelled` or `BookingStatus.rejected`.

Alternative flows:

- If selected filter has no results, page shows `No {filter} bookings` and suggests trying a different filter.
- Long route/operator/payment text auto-scrolls horizontally in its row.
- Active stale bookings show a notice asking passenger to open live tracking to sync latest status. The current card does not include an open-tracking button.

Exception flows:

- Stream error: history error state appears with `Retry`.
- Missing created timestamp: card displays `Unavailable`.
- Missing origin/destination: route displays `Origin` or `Destination` fallback.
- Missing operator name/ID: operator row displays `Not assigned yet`.

Payment outcome messages:

- Rejected + refunded: `Payment refunded successfully for this rejected booking.`
- Rejected + cancelled: `Payment authorization released. No charge captured for this rejected booking.`
- Rejected + authorized: `Payment is authorized and pending release after rejection.`
- Rejected + paid: `Payment was captured. Refund is being processed after rejection.`
- Cancelled + refunded: `Payment refunded after cancellation.`
- Cancelled + cancelled: `Payment authorization released after cancellation.`

Button inputs and outputs:

| Control | Input | Output |
| --- | --- | --- |
| `All` chip | Tap | Sets filter to all bookings. |
| `Active` chip | Tap | Shows only active bookings. |
| `Completed` chip | Tap | Shows completed bookings. |
| `Cancelled` chip | Tap | Shows cancelled and rejected bookings. |
| `Retry` | Tap in error state | Restarts booking history stream for the last user ID. |

Data side effects:

- Streams booking history from active/archive booking sources through `BookingRepository`.
- No writes.

## Notifications And Booking Deep Links

Files:

- `apps/passenger_app/lib/routes/main_screen.dart`
- `apps/passenger_app/lib/services/notifications/*`

Purpose:

- Notify passengers about booking status changes.
- Show foreground notification messages as top alerts.
- Navigate passengers directly to booking tracking when they tap a notification or deep link.

Normal flow:

1. Authenticated passenger reaches `MainScreen`.
2. Notification coordinator starts for user ID.
3. Foreground booking messages appear as top info alerts.
4. FCM/local notification taps call `_navigateToBooking`.
5. Booking tracking screen opens for the related booking.

Inputs and outputs:

| Trigger | Input | Output |
| --- | --- | --- |
| Foreground local coordinator message | title/body | Top info alert. |
| Foreground FCM message | title/body | Top info alert. |
| FCM tap | data `bookingId`, optional route/passenger fields | Opens tracking page. |
| Local notification tap | payload booking ID | Opens tracking page with fallback route/passenger values. |
| App link with booking ID | query parameters | Opens tracking page. |
| App link with payment status only | query `status` | Shows payment status alert and returns to Home tab. |

Exception flows:

- Missing FCM `bookingId`: tap is ignored.
- Deep link without booking ID but with status: no tracking page opens.
- Deep link plugin error: ignored so app remains usable.

## End-To-End Passenger Booking Workflow

Normal end-to-end flow:

1. Passenger signs in by phone OTP.
2. If new, passenger completes registration.
3. Passenger lands on Home.
4. Passenger chooses pickup and confirms it on map.
5. Passenger chooses drop-off and confirms it on map.
6. Passenger selects adult/child counts.
7. Passenger taps `Book Water Taxi`.
8. App verifies no active booking blocks the request.
9. App verifies an operator is online.
10. App verifies fare exists.
11. Passenger reviews payment page.
12. Passenger authorizes payment through Stripe.
13. App creates booking with payment status `authorized`.
14. Passenger tracks booking in real time.
15. Operator accepts and progresses the trip.
16. Passenger sees status/location updates and may call operator when phone is available.
17. Booking completes, payment is captured by backend/operator lifecycle, and history displays the completed booking.

Alternative end-to-end flows:

- Passenger already has an active booking: Home shows current booking card and routes directly to tracking.
- Passenger cancels before booking becomes non-cancellable: payment authorization is released/cancelled where possible, booking becomes cancelled, and history records the cancellation.
- No operator accepts: booking can become rejected, tracking and history show rejection and payment release/refund messaging.
- Passenger opens app from notification: app bypasses Home and opens tracking directly.
- Passenger returns after a long idle period: session refresh runs before continuing.

Exception end-to-end flows:

- No jetties: Home cannot offer route choices and shows jetty loading error.
- No fare: passenger cannot proceed to payment for that route.
- No online operators: passenger cannot proceed to payment.
- Payment cancelled: no booking is created.
- Payment authorized but booking creation fails: app attempts to release/cancel the payment authorization.
- Auth/session expires: user is prompted to sign in again.

## Firestore And Payment Data Summary

Passenger-visible pages use these data areas:

- `users/{uid}`:
  - created during registration
  - read for greeting/profile/payment payer data
  - updated from account management
  - deleted during account deletion
- `jetties`:
  - read by Home and Payment
  - used for route labels and coordinates
- `fares`:
  - read before booking and payment
  - fare snapshot ID is required for booking creation
- `operator_presence`:
  - checked before payment to ensure at least one operator is online
- `order_number_index`:
  - reserves unique order numbers before payment
- `bookings`:
  - created after payment authorization
  - streamed for active booking card and booking tracking
  - updated to cancelled when passenger cancellation succeeds
- `tracking`:
  - read/merged into booking tracking for live operator coordinates
- `bookings_archive`:
  - consumed by history through repository behavior for terminal bookings
- Stripe/payment gateway:
  - authorizes payment before booking creation
  - cancels/releases payment authorization when booking creation or passenger cancellation requires it
  - captures payment later in the completed ride lifecycle

