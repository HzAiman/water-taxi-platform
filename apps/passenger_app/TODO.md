# Passenger App TODO

## Goal
Prepare `passenger_app` for stable production-like booking flows and reliable synchronization with `operator_app`.

## Current Baseline

### Already in place
- [x] OTP resend flow is fixed
- [x] Booking persistence to Firestore from payment flow
- [x] Booking tracking screen streams live Firestore status
- [x] Passenger cancellation updates booking status to `cancelled`
- [x] Booking history exists with filter chips and live updates
- [x] Route validation and fare precheck before booking
- [x] Active-booking card on home to reopen current tracking
- [x] Duplicate booking guard while active booking exists
- [x] Shared top notification card system in app

## Remaining Work

### P1: Passenger-Operator Lifecycle Integration (Critical)
- [ ] Finalize passenger behavior for operator-driven status updates
	- [ ] Ensure UX for `accepted`, `on_the_way`, `completed` is clear and distinct
	- [ ] Show explicit status timeline messaging in tracking screen
- [ ] Define and implement passenger-facing handling when operator **rejects** booking
	- [ ] Decide whether booking remains `pending` or moves to a user-visible rejected/re-queued state
	- [ ] Add user guidance for what to do next (wait/rebook/cancel)
- [ ] Align passenger screens with final shared booking state machine contract

### P1: Firestore Contract + Data Integrity (Critical)
- [ ] Verify booking schema is fully aligned with operator dispatch fields
- [ ] Add any missing immutable/derived fields needed for robust history and reconciliation
- [ ] Confirm all passenger-side writes are compatible with tightened Firestore security rules
- [ ] Add/verify Firestore indexes for passenger queries (`userId`, `status`, `createdAt`, `updatedAt`)

### P1: Payment and Booking Commit Reliability
- [ ] Replace simulated payment completion with real payment integration strategy
	- [ ] Success/failure/cancel states
	- [ ] Retry and idempotency handling
	- [ ] Post-payment reconciliation to avoid orphan bookings
- [ ] Prevent duplicate booking document creation on repeated taps/network retries

### P2: UX + Recovery Quality
- [ ] Improve tracking screen resilience when booking doc is delayed/missing
- [ ] Improve error states when network disconnects during status transitions
- [ ] Add explicit messaging when driver assignment is delayed
- [ ] Add fallback actions in history/tracking for stale bookings

### P2: Account and Data Lifecycle
- [ ] Harden account deletion flow with reauthentication support
- [ ] Define policy for booking retention when user deletes account
- [ ] Ensure profile/account management screens handle partial Firestore data safely

### P3: Testing + Validation
- [x] Add view model tests for home/payment/tracking/profile flows
- [x] Add widget tests for:
	- [x] booking creation guards
	- [x] active booking card behavior
	- [x] tracking status rendering
	- [x] booking history filters
- [x] Add integration test for full flow:
	- [x] book -> operator accepts -> start -> complete -> history reflects final status
- [x] Add regression tests for cancellation edge cases

### P3: Production Readiness
- [ ] Verify Android release config and signing settings
- [ ] Verify iOS Firebase + Google Maps setup on physical device
- [x] Update README to reflect actual architecture and current feature behavior

## Suggested Next Delivery Order

1. Finalize shared booking state contract with operator reject/dispatch behavior.
2. Complete passenger UX for all operator-driven status transitions.
3. Implement payment reliability and idempotent booking commit safeguards.
4. Expand integration coverage for failure/retry branches.
5. Harden cancellation policy enforcement for terminal bookings.