# Operator App TODO

## Goal
Prepare `operator_app` for reliable end-to-end booking lifecycle with `passenger_app`.

## Remaining Work

### P0: Release Blockers (Do First)
- [ ] Verify Android release config and signing settings.
- [ ] Verify iOS Firebase + Google Maps setup on physical device.

### P1: Stabilization and Operations (Open)
- [ ] Re-run end-to-end reliability validation under concurrent dispatch load and payment reconciliation paths.
- [ ] Add production-safe admin operations path (server-authorized cleanup instead of client debug actions).
- [ ] Add release diagnostics policy (telemetry scope, visibility, and access controls).
- [ ] Backfill additional integration scenarios for dispatch contention and intermittent network failures.

### P2: Cross-App Roadmap - River Navigation (14 Jetties)

#### Phase A: Contract and Data Foundation (Blocking)
- [x] Define canonical Firestore corridor schema for one river route with ordered checkpoints (14 jetties), including sequence constraints and read-only client policy.
- [x] Extend shared booking/domain contracts with corridor metadata needed for operator navigation while preserving existing booking lifecycle compatibility.
- [x] Update and deploy Firestore rules and indexes for corridor reads and corridor-linked booking queries.
- [x] Keep this roadmap synchronized with passenger TODO for shared milestone visibility.

#### Phase B: Operator Navigation Engine (Depends on Phase A)
- [x] Add operator corridor data access and origin/destination to checkpoint-sequence binding.
- [x] Implement navigation logic: nearest checkpoint resolution, progress detection, off-route tolerance, remaining distance, and speed-based ETA.
- [x] Integrate navigation lifecycle into operator home view model so it starts/stops with active bookings and respects existing refresh/reconnect behavior.
- [x] Add basic guidance UI in operator home (progress, next checkpoint, remaining distance, ETA) without turn-by-turn prompts.
- [x] Add lightweight checkpoint/off-route/resume event notifications via existing notification coordinator and channels.

#### Phase C: Cross-App Visibility and Resilience (Depends on Phase B)
- [ ] Add passenger/shared tracking alignment notes and minimal passenger metadata handling where required.
- [ ] Implement graceful fallback when corridor config is unavailable so booking actions remain fully functional.
- [ ] Regression-check dispatch contention, cancellation, and reject/release reliability paths to ensure no behavior drift.
- [x] Ensure passenger can track operator approach to pickup after status becomes `on_the_way`.

#### Phase D: Verification and Rollout Hardening (Parallelizable After Core Integration)
- [ ] Add unit tests for corridor parsing, progression logic, off-route threshold behavior, and ETA calculations.
- [ ] Add view model/widget tests for guidance rendering and booking-state transitions.
- [ ] Add integration flow coverage: accept -> start -> checkpoint progression -> off-route/recover -> complete.
- [ ] Run Android/iOS smoke checks for map, permissions, overlay readability, and stream-refresh stability.

### P3: Future Backlog (Post-Stabilization)

#### Operator Identity and Security
- [ ] Add admin review tool for operator ID claim conflicts and manual reassignment approvals.
- [ ] Add signed audit trail for profile identity changes (`operatorId`, `name`, `email`).
- [ ] Add optional stronger auth policy for sensitive profile edits (recent-login or second factor).

#### Dispatch and Fleet Operations
- [ ] Add fairness strategy for queue distribution under heavy demand (round-robin/score-based).
- [ ] Add operator performance analytics (accept latency, completion rate, cancellation ratio).
- [ ] Add configurable auto-pause policy after repeated reject/no-start behavior.

#### Reliability and Production Ops
- [x] Add Cloud Function/runtime dependency upgrade plan (Node runtime and firebase-functions latest).
- [ ] Add synthetic monitoring for push delivery and booking transition SLA breaches.
- [ ] Add incident dashboard for live queue health, stuck bookings, and retry outcomes.

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

