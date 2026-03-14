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
- [x] Implement explicit **Reject Booking** action in operator flow
- [x] Define reject behavior contract:
  - [x] Option A adopted: keep status `pending` and mark operator rejection in `rejectedBy`
  - [x] Option B not adopted for current dispatch model
- [x] Prevent booking race conditions when multiple operators tap Accept simultaneously
  - [x] Use transaction/atomic guard to ensure only one operator can claim `pending`
- [x] Add clear “My Active Booking” vs “Available Booking Queue” sections

### P1: Firestore Contract + Rules (Critical)
- [x] Finalize shared booking state machine used by both apps:
  - [x] `pending -> accepted -> on_the_way -> completed`
  - [x] `pending/accepted/on_the_way -> cancelled` (passenger policy)
  - [x] `pending -> rejected` not used; replaced by `pending + rejectedBy[]`
- [x] Confirm ownership/permission model for each transition
- [x] Extend Firestore rules safely for any new fields used by reject/dispatch flow
- [x] Add indexes for production queries used by operator queue (status + driverId + createdAt)

### P1: Operator Home UX for Operations
- [x] Show live queue stats (pending count, active trip count)
- [x] Show key booking info in cards:
  - [x] Booking ID
  - [x] Pickup and destination
  - [x] Passenger count
  - [x] Fare summary
  - [x] Booking created time
- [x] Add empty states for:
  - [x] online but no pending bookings
  - [x] offline state
  - [x] no active trip

### P2: Reliability + Recovery
- [x] Handle stale bookings where assigned operator goes offline/disconnects
- [x] Add timeout/release strategy for unstarted accepted bookings
- [x] Add pull-to-refresh fallback if stream stalls
- [x] Add retry handling for failed status updates

### P2: Passenger-Operator Sync Validation
- [ ] Validate passenger tracking updates immediately for each operator action
- [ ] Validate passenger booking history reflects final statuses correctly
- [ ] Validate cancellation edge cases while operator is en-route

### P3: Testing + Quality
- [x] Add unit tests for status transition guards
- [x] Add widget tests for operator home queue and action buttons
- [ ] Add integration test for full lifecycle:
  - [ ] passenger books
  - [ ] operator accepts
  - [ ] operator starts trip
  - [ ] operator completes
  - [ ] passenger sees final state
- [x] Replace placeholder default test patterns

### P3: Observability + Ops
- [ ] Add structured logs for booking transition failures
- [ ] Add user-friendly error messages for rules/permission failures
- [ ] Add optional admin/debug screen for active booking diagnostics (dev only)

## Suggested Next Delivery Order

1. Build integration tests for cross-app lifecycle verification.
2. Expand passenger/operator sync validation coverage and cancellation edge cases.
3. Add structured observability for transition failures.
4. Add optional diagnostics/admin tooling for operations debugging.
5. Re-run end-to-end reliability validation under concurrent dispatch load.
