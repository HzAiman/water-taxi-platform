# Passenger App TODO

## Confirmed Gaps

### P0
- Fix OTP resend flow in phone_login_page.dart. The resend callback receives a new verification ID, but the screen still verifies against the original ID, so resent codes can fail.
- Implement real booking creation in payment_screen.dart. The current flow only loads fare data, waits 2 seconds, and navigates forward. No booking document is created, no booking ID is generated, and no payment result is stored.
- Replace the static booking status screen in booking_tracking_screen.dart with a Firestore-backed booking tracker. It currently shows a hardcoded pending state and the cancel button only returns to the previous screen.

### P1
- Add booking history to profile_screen.dart. The README promises booking history, but the profile screen only supports viewing and editing profile data, logout, and account deletion.
- Prevent invalid route submissions in home_screen.dart. The current form allows the same jetty for pickup and drop-off and relies on exact text matches for fare lookup.
- Decide and implement a real payment strategy. The current payment method selection is UI only and does not integrate with a gateway, validate payment completion, or handle failures and retries.
- Handle booking cancellation in the backend. Cancellation should update booking status in Firestore instead of only popping the screen.

### P2
- Clean up account deletion. The current delete flow removes the user document and auth user only; it does not handle related bookings or recent-login reauthentication requirements.
- Add loading, empty, and error states for profile and booking-related data flows beyond the initial happy path.
- Reconcile README claims with the actual implementation until the missing features are completed.

### P3
- Add automated tests. No test files are currently present under the passenger_app test folder.
- Replace placeholder Android production settings. android/app/build.gradle.kts still uses the example application ID and debug signing for release builds.
- Verify iOS production setup for Firebase and Google Maps on a real device build, not just Android debug configuration.

## Suggested Delivery Order

1. Fix OTP resend so authentication is reliable.
2. Persist bookings in Firestore from the payment flow and generate booking IDs.
3. Refactor booking_tracking_screen.dart to read and update a real booking document.
4. Add cancellation status updates and booking history queries.
5. Tighten booking validation in home_screen.dart and payment failure handling.
6. Add tests for auth, booking creation, and profile flows.
7. Update README once the implemented scope matches the documented scope.

## Notes From Current Code Review

- README.md claims real-time tracking, booking history, booking confirmation IDs, and bookings saved to Firestore, but those behaviors are not implemented yet.
- A search of the passenger app code does not show any bookings collection reads or writes.
- The project currently passes analyzer checks, so the main issues are missing behavior and mismatched product scope rather than syntax errors.