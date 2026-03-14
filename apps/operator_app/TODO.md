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
- [x] Validate passenger tracking updates immediately for each operator action
- [x] Validate passenger booking history reflects final statuses correctly
- [x] Validate cancellation edge cases while operator is en-route

### P3: Testing + Quality
- [x] Add unit tests for status transition guards
- [x] Add widget tests for operator home queue and action buttons
- [x] Add integration test for full lifecycle:
  - [x] passenger books
  - [x] operator accepts
  - [x] operator starts trip
  - [x] operator completes
  - [x] passenger sees final state
- [x] Add dispatch contention integration tests (concurrent accept/reject and cancellation race)
- [x] Replace placeholder default test patterns

### P3: Observability + Ops
- [x] Add structured logs for booking transition failures
- [x] Add user-friendly error messages for rules/permission failures
- [x] Add optional admin/debug screen for active booking diagnostics (dev only)

## Suggested Next Delivery Order

1. Re-run end-to-end reliability validation under concurrent dispatch load.
2. Add production-safe admin operations path (server-authorized cleanup instead of client debug actions).
3. Add release diagnostics policy (what telemetry is kept, where it is surfaced, and who can access it).
4. Backfill additional integration scenarios for dispatch contention and intermittent network failures.

## Progress Notes

- [x] Concurrent dispatch load reliability validation baseline added via integration tests.
- [x] Optional Firestore Emulator contention suite added for transaction-realistic dispatch verification.
- [x] Optional emulator network-recovery scenario added (offline accept attempt, online retry success).
- [x] Client-side stale cleanup writes removed from Firestore rules; debug page now provides preview-only guidance for server-admin cleanup.

## Emulator Test Run (Optional)

- Start Firestore emulator in a separate shell:
  - `firebase emulators:start --only firestore --project melaka-water-taxi`
- Run contention tests against emulator:
  - `set FIREBASE_EMULATOR_TESTS=1 && flutter test test/integration/dispatch_contention_emulator_test.dart`
