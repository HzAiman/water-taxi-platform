# Operator App TODO

## Goal
Prepare `operator_app` for reliable end-to-end booking lifecycle with `passenger_app`.

## Current Baseline

### Already in place
- [x] Operator authentication and profile setup (`operators/{uid}`)
- [x] Online/offline availability toggle
- [x] Basic booking workflow actions on home screen
  - [x] Accept booking (`pending -> accepted`)
  - [x] Start trip (`accepted -> on_the_way`)
  - [x] Complete trip (`on_the_way -> completed`)
- [x] Shared in-app notification card system across operator screens
- [x] Profile UI structure aligned with passenger app style

## Remaining Work

### P1: Booking Dispatch + Decision Flow (Critical)
- [ ] Implement explicit **Reject Booking** action in operator flow
- [ ] Define reject behavior contract:
  - [ ] Option A: keep status `pending` and mark operator rejection separately (recommended for multi-operator dispatch)
  - [ ] Option B: set status `rejected` (only if dispatch model supports reassignment)
- [ ] Prevent booking race conditions when multiple operators tap Accept simultaneously
  - [ ] Use transaction/atomic guard to ensure only one operator can claim `pending`
- [ ] Add clear “My Active Booking” vs “Available Booking Queue” sections

### P1: Firestore Contract + Rules (Critical)
- [ ] Finalize shared booking state machine used by both apps:
  - [ ] `pending -> accepted -> on_the_way -> completed`
  - [ ] `pending/accepted/on_the_way -> cancelled` (passenger policy)
  - [ ] `pending -> rejected` (if adopted)
- [ ] Confirm ownership/permission model for each transition
- [ ] Extend Firestore rules safely for any new fields used by reject/dispatch flow
- [ ] Add indexes for production queries used by operator queue (status + driverId + createdAt)

### P1: Operator Home UX for Operations
- [ ] Show live queue stats (pending count, active trip count)
- [ ] Show key booking info in cards:
  - [ ] Booking ID
  - [ ] Pickup and destination
  - [ ] Passenger count
  - [ ] Fare summary
  - [ ] Booking created time
- [ ] Add empty states for:
  - [ ] online but no pending bookings
  - [ ] offline state
  - [ ] no active trip

### P2: Reliability + Recovery
- [ ] Handle stale bookings where assigned operator goes offline/disconnects
- [ ] Add timeout/release strategy for unstarted accepted bookings
- [ ] Add pull-to-refresh fallback if stream stalls
- [ ] Add retry handling for failed status updates

### P2: Passenger-Operator Sync Validation
- [ ] Validate passenger tracking updates immediately for each operator action
- [ ] Validate passenger booking history reflects final statuses correctly
- [ ] Validate cancellation edge cases while operator is en-route

### P3: Testing + Quality
- [ ] Add unit tests for status transition guards
- [ ] Add widget tests for operator home queue and action buttons
- [ ] Add integration test for full lifecycle:
  - [ ] passenger books
  - [ ] operator accepts
  - [ ] operator starts trip
  - [ ] operator completes
  - [ ] passenger sees final state
- [ ] Replace placeholder default test patterns

### P3: Observability + Ops
- [ ] Add structured logs for booking transition failures
- [ ] Add user-friendly error messages for rules/permission failures
- [ ] Add optional admin/debug screen for active booking diagnostics (dev only)

## Suggested Next Delivery Order

1. Implement reject flow + atomic accept transaction.
2. Finalize Firestore contract/rules/indexes for dispatch safety.
3. Upgrade operator home queue UX and statuses.
4. Run end-to-end sync validation with passenger flows.
5. Add tests for lifecycle and edge cases.
