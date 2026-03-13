# Passenger App TODO

## Completed

### Core booking flow
- [x] Fix OTP resend flow in phone_login_page.dart
- [x] Persist bookings from payment_screen.dart to Firestore
- [x] Generate and pass bookingId into tracking flow
- [x] Replace static booking tracking with Firestore-backed status view
- [x] Implement cancellation by updating bookings/{bookingId}.status to cancelled
- [x] Add booking history in profile_screen.dart from current user's bookings
- [x] Prevent invalid route submissions (same origin and destination)
- [x] Add route-level fare precheck in home_screen.dart before navigating to payment

### Project docs
- [x] Add implementation tracker in TODO.md

## Remaining

### P1
- [ ] Decide and implement a real payment integration strategy (gateway, failure states, retries, reconciliation)

### P2
- [ ] Clean up account deletion to handle related booking data and reauthentication requirements
- [ ] Reconcile README claims with current implementation

### P3
- [ ] Add automated tests for auth, booking creation, tracking, cancellation, and profile history
- [ ] Replace placeholder Android production settings in android/app/build.gradle.kts
- [ ] Verify iOS Firebase and Google Maps production configuration on device build

## Suggested Next Delivery Order

1. Implement real payment integration and failure handling.
2. Add integration and widget tests for the new booking lifecycle.
3. Harden account deletion flow and associated booking cleanup policy.
4. Finalize platform production configs (Android and iOS).
5. Update README to match shipped behavior.