# Passenger App TODO

## Goal
Prepare `passenger_app` for stable production-like booking flows and reliable synchronization with `operator_app`.

## Remaining Work

### P0: Release Blockers (Do First)
- [ ] Verify Android release config and signing settings.
- [ ] Verify iOS Firebase + Google Maps setup on physical device.

### P1: Stabilization and UX Recovery (Open)

#### Tracking and Recovery UX
- [x] Improve tracking screen resilience when booking doc is delayed or temporarily missing.
- [x] Improve error states when network disconnects during status transitions.
- [x] Add explicit messaging when operator assignment is delayed.
- [x] Add fallback actions in history/tracking for stale bookings.

#### Account and Data Lifecycle
- [x] Harden account deletion flow with reauthentication support.
- [x] Define policy for booking retention when user deletes account.
- [x] Ensure profile/account management screens handle partial Firestore data safely.

#### Validation and Test Expansion
- [x] Expand integration coverage for failure, retry, and reconciliation branches.

### P2: River Navigation Cross-App Roadmap (14 Jetties)

#### Phase A: Contract and Data Foundation (Blocking)
- [x] Define canonical Firestore corridor schema for one river route with ordered checkpoints (14 jetties), including sequence constraints and read-only client policy.
- [x] Extend shared booking/domain contracts with corridor metadata needed for operator navigation while preserving existing booking lifecycle compatibility.
- [x] Update and deploy Firestore rules and indexes for corridor reads and corridor-linked booking queries.
- [x] Keep this roadmap synchronized with operator TODO for shared milestone visibility.

#### Phase B: Operator Navigation Engine (Depends on Phase A)
- [x] Add operator corridor data access and origin/destination to checkpoint-sequence binding.
- [x] Implement navigation logic: nearest checkpoint resolution, progress detection, off-route tolerance, remaining distance, and speed-based ETA.
- [x] Integrate navigation lifecycle into operator home view model so it starts/stops with active bookings and respects existing refresh/reconnect behavior.
- [x] Add basic guidance UI in operator home (progress, next checkpoint, remaining distance, ETA) without turn-by-turn prompts.
- [x] Add lightweight checkpoint/off-route/resume event notifications via existing notification coordinator and channels.

#### Phase C: Cross-App Visibility and Resilience (Depends on Phase B)
- [x] Add passenger/shared tracking alignment notes and minimal passenger metadata handling where required.
- [ ] Implement graceful fallback when corridor config is unavailable so booking actions remain fully functional.
- [ ] Regression-check dispatch contention, cancellation, and reject/release reliability paths to ensure no behavior drift.
- [x] Ensure passenger can track operator approach to pickup after status becomes `on_the_way`.

#### Phase D: Verification and Rollout Hardening (Parallelizable After Core Integration)
- [ ] Add unit tests for corridor parsing, progression logic, off-route threshold behavior, and ETA calculations.
- [ ] Add view model/widget tests for guidance rendering and booking-state transitions.
- [ ] Add integration flow coverage: accept -> start -> checkpoint progression -> off-route/recover -> complete.
- [ ] Run Android/iOS smoke checks for map, permissions, overlay readability, and stream-refresh stability.

### P3: Future Backlog (Post-Stabilization)

#### Platform and Product
- [ ] Add configurable service window/cutoff rules (night closures, holidays, weather disruption mode).
- [ ] Add promo/referral and fare campaign support with server-authoritative validation.
- [ ] Add multilingual copy strategy and localization for BM/EN passenger-facing flows.

#### Booking and Payment Governance
- [ ] Add payment reconciliation dashboard for mismatches between booking status and provider status.
- [x] Add automatic stale-authorization cleanup report for long-running uncaptured payments.
- [ ] Add booking fraud/abuse heuristics (rapid repeat bookings, cancellation spikes).

#### Reliability and Operations
- [ ] Add app-level telemetry for booking lifecycle latency (pending -> accepted -> completed).
- [ ] Add offline-first retry queue for key passenger actions with dedupe tokens.
- [ ] Add runbook docs for incident handling (payment outage, push outage, rule regression).

## Completed Milestones

### Core Booking and Lifecycle
- [x] OTP resend flow fixed.
- [x] Booking persistence and live status streaming implemented.
- [x] Passenger cancellation flow implemented (`cancelled`).
- [x] Route validation and fare precheck before booking.
- [x] Active booking resume card and duplicate booking guard implemented.
- [x] Passenger lifecycle UX aligned for `accepted`, `on_the_way`, `completed`, and `rejected` handling.

### Firestore Contract and Payment Reliability
- [x] Booking schema aligned with operator dispatch fields.
- [x] Passenger writes validated against shared Firestore rules.
- [x] Firestore indexes verified for core passenger query paths.
- [x] Payment flow moved to real integration strategy with success/failure/cancel paths.
- [x] Retry and idempotent booking commit safeguards added.
- [x] Post-payment reconciliation implemented to avoid orphan bookings.

### Payment Progress Notes
- [x] Added gateway-ready payment abstraction (`PaymentGatewayService`).
- [x] Added temporary simulated adapter (`SimulatedExternalPaymentGatewayService`) while provider integration stabilized.
- [x] Added payment outcome test coverage for success/failure/cancel.
- [x] Switched to Stripe hold-first manual capture flow (`authorized -> paid`).
- [x] Added attempt-scoped idempotency keys to avoid stale PaymentIntent reuse.
- [x] Added backend release/refund triggers for cancelled and rejected bookings.
- [x] Added scheduled reconciliation (`reconcileStaleAuthorizedPayments`) every 30 minutes.

### Live Tracking and Map Enhancements
- [x] Live operator marker shown during `on_the_way` using booking-stream coordinates.
- [x] Firestore route polyline rendering implemented on tracking map.
- [x] Legacy polyline key compatibility implemented (`routeCoordinates`, `polylineCoordinates`, `routePoints`).
- [x] Tracking map auto-fit to route and operator recenter behavior added.
- [x] On-the-way location status notices added (locating operator / stale update guidance).
- [x] Firestore rules deployed with live location and route polyline compatibility updates.

### Testing and Quality
- [x] View model tests for home/payment/tracking/profile flows.
- [x] Widget tests for booking guards, active booking card, status rendering, and history filters.
- [x] Integration test for full lifecycle (book -> accept -> start -> complete).
- [x] Regression tests for cancellation edge cases.
- [x] Widget regression test for route polyline rendering and operator marker status gating.
- [x] Integration regression tests for operator location stream and legacy polyline key variants.

### Notifications and Docs
- [x] Foreground/background notifications implemented for booking events.
- [x] FCM token registration in both apps (`user_devices`, `operator_devices`).
- [x] Firestore-triggered backend push dispatch implemented.
- [x] Notification tap deep-link navigation to booking detail/tracking implemented.
- [x] README and functions README updated to reflect current architecture and backend triggers.

## Suggested Execution Order

1. Complete Android and iOS release hardening checks.
2. Finish passenger UX recovery work (delayed assignment, network interruption, stale booking actions).
3. Harden account lifecycle (reauth + retention policy).
4. Expand integration coverage for retry/reconciliation/error branches.
5. Add production alert routing and on-call runbook for payment failures.
