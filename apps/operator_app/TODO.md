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
- [x] Add clear â€œMy Active Bookingâ€ vs â€œAvailable Booking Queueâ€ sections

### P1: Firestore Contract + Rules (Critical)
- [x] Finalize shared booking state machine used by both apps:
  - [x] `pending -> accepted -> on_the_way -> completed`
  - [x] `pending/accepted/on_the_way -> cancelled` (passenger policy)
  - [x] `pending -> rejected` not used; replaced by `pending + rejectedBy[]`
- [x] Confirm ownership/permission model for each transition
- [x] Extend Firestore rules safely for any new fields used by reject/dispatch flow
- [x] Add indexes for production queries used by operator queue (status + operatorId + createdAt)

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

### P3: Notification Delivery (Cross-App)
- [x] Foreground in-app notifications for operator booking events
- [x] Background local notifications when app is minimized
- [x] Persistent online-status reminder notification (cleared on go-offline)
- [x] FCM token registration in operator app (`operator_devices`)
- [x] Firestore-triggered backend push dispatch for incoming bookings and status changes
- [x] Add notification tap deep-link navigation to booking home tab

### P3: Production Readiness
- [ ] Verify Android release config and signing settings
- [ ] Verify iOS Firebase + Google Maps setup on physical device
- [x] Update README to reflect actual architecture and current feature behavior

## Suggested Next Delivery Order

1. Re-run end-to-end reliability validation under concurrent dispatch load.
2. Add production-safe admin operations path (server-authorized cleanup instead of client debug actions).
3. Add release diagnostics policy (what telemetry is kept, where it is surfaced, and who can access it).
4. Backfill additional integration scenarios for dispatch contention and intermittent network failures.

## Cross-App Roadmap: River Navigation Delivery (14 Jetties)

Plan: implement river navigation as a cross-app roadmap with Firestore-backed corridor data from day one. Operator MVP guidance stays intentionally simple (checkpoint progress, next jetty, remaining distance, speed-based ETA). Delivery is phased so shared contracts and backend policy are stable before deeper UX integration.

### Phase A: Contract and data foundation (blocking)
- [ ] Define canonical Firestore corridor schema for one river route with ordered checkpoints (14 jetties), including sequence constraints and read-only client policy.
- [ ] Extend shared booking/domain contracts with corridor metadata needed for operator navigation while preserving existing booking lifecycle compatibility.
- [ ] Update and deploy Firestore rules and indexes for corridor reads and corridor-linked booking queries.
- [ ] Keep this roadmap synchronized with passenger TODO for shared milestone visibility.

### Phase B: Operator navigation engine (depends on Phase A)
- [ ] Add operator corridor data access and origin/destination to checkpoint-sequence binding.
- [ ] Implement navigation logic: nearest checkpoint resolution, progress detection, off-route tolerance, remaining distance, and speed-based ETA.
- [ ] Integrate navigation lifecycle into operator home view model so it starts/stops with active bookings and respects existing refresh/reconnect behavior.
- [ ] Add basic guidance UI in operator home (progress, next checkpoint, remaining distance, ETA) without turn-by-turn prompts.
- [ ] Add lightweight checkpoint/off-route/resume event notifications via existing notification coordinator and channels.

### Phase C: Cross-app visibility and resilience (depends on Phase B)
- [ ] Add passenger/shared tracking alignment notes and minimal passenger metadata handling where required.
- [ ] Implement graceful fallback when corridor config is unavailable so booking actions remain fully functional.
- [ ] Regression-check dispatch contention, cancellation, and reject/release reliability paths to ensure no behavior drift.
- [ ] Ensure passenger can track operator approach to pickup after status becomes `on_the_way`.

### Phase D: Verification and rollout hardening (parallelizable after core integration)
- [ ] Add unit tests for corridor parsing, progression logic, off-route threshold behavior, and ETA calculations.
- [ ] Add view model/widget tests for guidance rendering and booking-state transitions.
- [ ] Add integration flow coverage: accept -> start -> checkpoint progression -> off-route/recover -> complete.
- [ ] Run Android/iOS smoke checks for map, permissions, overlay readability, and stream-refresh stability.

## Progress Notes

- [x] Concurrent dispatch load reliability validation baseline added via integration tests.
- [x] Optional Firestore Emulator contention suite added for transaction-realistic dispatch verification.
- [x] Optional emulator network-recovery scenario added (offline accept attempt, online retry success).
- [x] Client-side stale cleanup writes removed from Firestore rules; debug page now provides preview-only guidance for server-admin cleanup.
- [x] Operator Ride / Transaction Summary added with period metrics, searchable/filterable history, and saved statement management.
- [x] Income statement export is PDF-only.

## Emulator Test Run (Optional)

- Start Firestore emulator in a separate shell:
  - `firebase emulators:start --only firestore --project melaka-water-taxi`
- Run contention tests against emulator:
  - `set FIREBASE_EMULATOR_TESTS=1 && flutter test test/integration/dispatch_contention_emulator_test.dart`

## Future Backlog (Post-Stabilization)

### Operator Identity and Security
- [ ] Add admin review tool for operator ID claim conflicts and manual reassignment approvals
- [ ] Add signed audit trail for profile identity changes (`operatorId`, `name`, `email`)
- [ ] Add optional stronger auth policy for sensitive profile edits (recent-login or second factor)

### Dispatch and Fleet Operations
- [ ] Add fairness strategy for queue distribution under heavy demand (round-robin/score-based)
- [ ] Add operator performance analytics (accept latency, completion rate, cancellation ratio)
- [ ] Add configurable auto-pause policy after repeated reject/no-start behavior

### Reliability and Production Ops
- [ ] Add Cloud Function/runtime dependency upgrade plan (Node runtime and firebase-functions latest)
- [ ] Add synthetic monitoring for push delivery and booking transition SLA breaches
- [ ] Add incident dashboard for live queue health, stuck bookings, and retry outcomes

