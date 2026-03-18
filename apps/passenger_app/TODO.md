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
- [x] Finalize passenger behavior for operator-driven status updates
	- [x] Ensure UX for `accepted`, `on_the_way`, `completed` is clear and distinct
	- [x] Show explicit status timeline messaging in tracking screen
- [x] Define and implement passenger-facing handling when operator **rejects** booking
	- [x] Decide whether booking remains `pending` or moves to a user-visible rejected/re-queued state
	- [x] Add user guidance for what to do next (wait/rebook/cancel)
- [x] Align passenger screens with final shared booking state machine contract

### P1: Firestore Contract + Data Integrity (Critical)
- [x] Verify booking schema is fully aligned with operator dispatch fields
- [x] Add any missing immutable/derived fields needed for robust history and reconciliation
- [x] Confirm all passenger-side writes are compatible with tightened Firestore security rules
- [x] Add/verify Firestore indexes for passenger queries (`userId`, `status`, `createdAt`, `updatedAt`)

### P1: Payment and Booking Commit Reliability
- [x] Replace simulated payment completion with real payment integration strategy
	- [x] Success/failure/cancel states
	- [x] Retry and idempotency handling
	- [x] Post-payment reconciliation to avoid orphan bookings
- [x] Prevent duplicate booking document creation on repeated taps/network retries

Progress notes:
- [x] Added gateway-ready payment abstraction (`PaymentGatewayService`) and wired it into `PaymentViewModel` before booking creation.
- [x] Added temporary simulated external adapter (`SimulatedExternalPaymentGatewayService`) for current flows while real provider API/SDK is pending.
- [x] Added payment outcome coverage in tests (success/failure/cancel) with booking-creation guard when payment is not successful.
- [x] Switched to Stripe hold-first/manual capture flow (`authorized -> paid` on completion).
- [x] Added attempt-scoped idempotency keys to avoid stale PaymentIntent reuse on retries.
- [x] Added backend release/refund triggers for cancelled and rejected bookings.
- [x] Added scheduled reconciliation (`reconcileStaleAuthorizedPayments`) every 30 minutes.

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
- [x] Update functions/README.md to reflect deployed triggers, region, and payload fields

### P3: Notification Delivery (Cross-App)
- [x] Foreground in-app notifications for operator/passenger booking events
- [x] Background local notifications when app is minimized
- [x] FCM token registration in both apps (`user_devices`, `operator_devices`)
- [x] Firestore-triggered backend push dispatch for incoming booking and status changes
- [x] Add notification tap deep-link navigation to booking detail/tracking screen

## Suggested Next Delivery Order

1. Expand integration coverage for failure/retry and reconciliation branches.
2. Complete release hardening for Android/iOS production builds.
3. Harden account lifecycle handling (reauth + retention policy).
4. Improve recovery UX for delayed assignment and transient network failures.
5. Add production alert routing and on-call runbook for payment failures.

## Cross-App Roadmap: River Navigation Delivery (14 Jetties)

Plan: implement river navigation as a cross-app roadmap with Firestore-backed corridor data from day one. Operator MVP guidance stays intentionally simple (checkpoint progress, next jetty, remaining distance, speed-based ETA). Delivery is phased so shared contracts and backend policy are stable before deeper UX integration.

### Phase A: Contract and data foundation (blocking)
- [ ] Define canonical Firestore corridor schema for one river route with ordered checkpoints (14 jetties), including sequence constraints and read-only client policy.
- [ ] Extend shared booking/domain contracts with corridor metadata needed for operator navigation while preserving existing booking lifecycle compatibility.
- [ ] Update and deploy Firestore rules and indexes for corridor reads and corridor-linked booking queries.
- [ ] Keep this roadmap synchronized with operator TODO for shared milestone visibility.

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

## Future Backlog (Post-Stabilization)

### Platform and Product
- [ ] Add configurable service window/cutoff rules (night closures, holidays, weather disruption mode)
- [ ] Add promo/referral and fare campaign support with server-authoritative validation
- [ ] Add multilingual copy strategy and localization for BM/EN passenger-facing flows

### Booking and Payment Governance
- [ ] Add payment reconciliation dashboard for mismatches between booking status and provider status
- [x] Add automatic stale-authorization cleanup report for long-running uncaptured payments
- [ ] Add booking fraud/abuse heuristics (rapid repeat bookings, cancellation spikes)

### Reliability and Operations
- [ ] Add app-level telemetry for booking lifecycle latency (pending -> accepted -> completed)
- [ ] Add offline-first retry queue for key passenger actions with dedupe tokens
- [ ] Add runbook docs for incident handling (payment outage, push outage, rule regression)
