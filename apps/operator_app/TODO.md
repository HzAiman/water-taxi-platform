# Operator App TODO

## Goal
Prepare `operator_app` for reliable end-to-end booking lifecycle with `passenger_app`.

## Remaining Work

### P0: Release Blockers (Do First)
- [ ] Verify Android release config and signing settings.

### P1: Stabilization and Operations (Open)
- [ ] Re-run end-to-end reliability validation under concurrent dispatch load and payment reconciliation paths.
- [ ] Add production-safe admin operations path (server-authorized cleanup instead of client debug actions).
- [ ] Add release diagnostics policy (telemetry scope, visibility, and access controls).
- [ ] Backfill additional integration scenarios for dispatch contention and intermittent network failures.

### P2: Cross-App Roadmap - River Navigation (14 Jetties)

#### Phase A: Contract and Data Foundation (Blocking)
- [x] Define canonical Firestore route polyline schema for one river route (14 jetties coverage) with read-only client policy.
- [x] Extend shared booking/domain contracts with route polyline metadata needed for operator navigation while preserving existing booking lifecycle compatibility.
- [x] Update and deploy Firestore rules and indexes for polyline reads and booking queries.
- [x] Keep this roadmap synchronized with passenger TODO for shared milestone visibility.

#### Phase B: Operator Navigation Engine (Depends on Phase A)
- [x] Add operator polyline route access and origin/destination route-segment binding.
- [x] Implement navigation logic: nearest route marker resolution, progress detection, off-route tolerance, remaining distance, and speed-based ETA.
- [x] Integrate navigation lifecycle into operator home view model so it starts/stops with active bookings and respects existing refresh/reconnect behavior.
- [x] Add basic guidance UI in operator home (progress, next route marker, remaining distance, ETA) without turn-by-turn prompts.
- [x] Add lightweight route-marker/off-route/resume event notifications via existing notification coordinator and channels.

#### Phase C: Cross-App Visibility and Resilience (Depends on Phase B)
- [x] Add passenger/shared tracking alignment notes and minimal passenger metadata handling where required.
- [x] Implement graceful fallback when route polyline config is unavailable so booking actions remain fully functional.
- [x] Regression-check dispatch contention, cancellation, and reject/release reliability paths to ensure no behavior drift.
- [x] Ensure passenger can track operator approach to pickup after status becomes `on_the_way`.

#### Phase D: Verification and Rollout Hardening (Parallelizable After Core Integration)
- [x] Add unit tests for route polyline parsing, progression logic, off-route threshold behavior, and ETA calculations.
- [x] Add view model/widget tests for guidance rendering and booking-state transitions.
- [x] Add integration flow coverage: accept -> start -> route progression -> off-route/recover -> complete.
- [x] Run Android/iOS smoke checks for map, permissions, overlay readability, and stream-refresh stability.
  - [x] Android smoke launch verified on device `CLK NX1` (19 Mar 2026, debug no-resident run for `operator_app` and `passenger_app`).
  - [x] iOS smoke check deferred (out of current scope: Android-first release).

## Completed Milestones

### Core Workflow and Contracts
- [x] Operator authentication and profile setup (`operators/{uid}`).
- [x] Online/offline availability toggle.
- [x] Booking workflow actions implemented: accept, start trip, complete trip.
- [x] Explicit reject flow implemented using `pending + rejectedBy[]` dispatch model.
- [x] Booking race-condition guard implemented (transactional claim of `pending` booking).
- [x] Shared state machine and ownership/permission model aligned across apps.

### Home UX and Reliability
- [x] Active vs pending queue separation on home screen.
- [x] Queue stats, booking card details, and empty states implemented.
- [x] Pull-to-refresh fallback, retry handling, and stale accepted booking release strategy implemented.

### Passenger Sync and Tracking Support
- [x] Passenger tracking and history sync validation completed across operator actions.
- [x] Live operator location publishing after `on_the_way` transition validated.
- [x] Firestore-backed route polyline compatibility validated for passenger tracking map.

### Testing and Quality
- [x] Unit tests for status-transition guards and location publish throttling (time/distance guard).
- [x] Widget tests for operator home queue and action buttons.
- [x] Integration tests for full lifecycle and dispatch contention scenarios.

### Notifications and Ops
- [x] Foreground/background notification delivery and persistent online reminder.
- [x] FCM token registration in `operator_devices`.
- [x] Firestore-triggered push dispatch and notification deep-link to booking home tab.
- [x] Structured logging and user-friendly permission/rules failure messages.
- [x] Optional diagnostics page for active booking checks (dev only).

### Documentation and Recent Cross-App Progress
- [x] README updated to reflect current architecture and behavior.
- [x] Node.js 22 and latest Firebase Functions/Admin SDK track adopted.
- [x] Stripe cancellation-reason compatibility fixes applied.
- [x] Operator publishes throttled live coordinates (`operatorLat`, `operatorLng`) after `startTrip` and stops on terminal/offline states.
- [x] Shared booking model and Firestore rules updated for route polyline and operator location compatibility.
- [x] Passenger map now renders Firestore route polyline and live operator marker during `on_the_way`.

## Optional Emulator Validation

- Start Firestore emulator:
  - `firebase emulators:start --only firestore --project melaka-water-taxi`
- Run contention test suite:
  - `set FIREBASE_EMULATOR_TESTS=1 && flutter test test/integration/dispatch_contention_emulator_test.dart`

