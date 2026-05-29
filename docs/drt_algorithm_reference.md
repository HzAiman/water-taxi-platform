# DRT Algorithm Reference

This document explains the demand-responsive transport (DRT), pooling, sequencing, stop-planning, and live-navigation algorithms currently implemented in the Water Taxi Platform.

The focus is the actual system behavior in this repository, especially:

- Backend pooling and route-aware dispatch in `apps/passenger_app/functions/index.js`
- Shared booking/route/stop fields in `packages/water_taxi_shared/lib/src/models/booking_model.dart`
- Operator route rendering in `apps/operator_app/lib/features/home/presentation/map/operator_map_layers.dart`
- Operator live guidance in `apps/operator_app/lib/features/home/presentation/services/operator_navigation_guidance_service.dart`

## 1. Conceptual Model

The system implements a small-capacity DRT pool for water-taxi bookings. A pool is a set of bookings assigned to the same operator that can be served together if they satisfy temporal, spatial, direction, capacity, and rider-delay constraints.

The current DRT model is closer to "route-aware fixed-corridor pooling" than a full dynamic vehicle routing problem. The system does not solve a global optimization problem across all operators. Instead, it evaluates whether a pending booking can join one operator's current active pool, then assigns a route-aware sequence and stop plan for that operator.

Core ideas:

- A booking has an origin jetty, destination jetty, coordinates, optional route polyline, and lifecycle status.
- An operator can hold multiple active/accepted pooled bookings up to `POOLING_POLICY.maxConcurrent`.
- A pool follows a route corridor derived from an active `on_the_way` booking when present, otherwise from the first active booking or the candidate booking.
- Candidate bookings are accepted only when they fit the current corridor and current sweep direction.
- A route direction is stored as `forward` or `reverse`.
- A pool stop plan groups pickups/dropoffs at the same jetty/route position.
- Grouped stops carry stop-level passenger totals so the operator UI can show "Pick up 2 passengers" even if only one booking document is currently selected/rendered.
- Completed stops are preserved across replans so the route does not resurrect already-served stops.
- The operator app uses the pool stop plan and route polyline to render navigation to the current stop.

## 2. Important Files

Backend dispatch and pooling:

- `apps/passenger_app/functions/index.js`
- Main functions: `acceptPooledBooking`, `rejectPooledBooking`, `startPooledBooking`, `markPoolStopReached`, `completePooledBooking`, `replanPoolSequenceOnBookingExit`
- Main helpers: `evaluatePoolingEligibility`, `choosePoolCorridor`, `routeMetricsForBooking`, `planRouteAwarePoolSequence`, `buildPoolStopPlan`

Shared data model:

- `packages/water_taxi_shared/lib/src/models/booking_model.dart`
- Main classes: `BookingModel`, `BookingRoutePoint`, `PoolStopPlanItem`

Operator app:

- `apps/operator_app/lib/data/repositories/booking_repository.dart`
- `apps/operator_app/lib/features/home/presentation/viewmodels/operator_home_view_model.dart`
- `apps/operator_app/lib/features/home/presentation/map/operator_map_layers.dart`
- `apps/operator_app/lib/features/home/presentation/services/operator_navigation_guidance_service.dart`
- `apps/operator_app/lib/features/home/presentation/pages/operator_home_screen.dart`

Tests:

- `apps/passenger_app/functions/rules-tests/pooling.stop-plan.test.js`
- `apps/operator_app/test/features/home/operator_map_layers_test.dart`
- `apps/operator_app/test/features/home/operator_map_controller_service_test.dart`
- `apps/operator_app/test/viewmodels/operator_home_view_model_test.dart`

## 3. Main Firestore Fields

The backend defines booking field names in `BOOKING_FIELDS` in `index.js`.

### Assignment and status fields

- `status`: booking lifecycle status, for example `pending`, `accepted`, `on_the_way`, `completed`
- `operatorUid`: Firebase UID of the assigned operator
- `operatorId`: deprecated/legacy operator identifier
- `assignedOperatorName`: operator display name copied at assignment time
- `assignedOperatorDisplayId`: operator display ID copied at assignment time
- `assignedOperatorPhone`: operator phone copied at assignment time
- `updatedAt`: server timestamp for latest booking mutation

### Route and pooling fields

- `pooled`: whether the booking is participating in pooling
- `poolGroupId`: logical group ID for a pool
- `poolSequence`: booking-level queue order within the operator's pool
- `poolCriteriaVersion`: current algorithm/policy version string
- `poolMax`: maximum concurrent pool size applied to this booking
- `poolEligibilityScore`: numeric score used for diagnostics/ranking
- `poolEtaSnapshot`: diagnostic object capturing ETA/distance calculations at acceptance time
- `routePolyline`: route geometry used as a corridor/polyline
- `routeDirection`: `forward` or `reverse`
- `poolStatus`: pool-level state, such as `accepted`, `in_progress`, or `completed`

### Stop-plan fields

- `poolStopPlan`: list of planned pool stops
- `currentStopIndex`: index of current active stop in `poolStopPlan`
- `currentStopId`: ID of current active stop
- `currentPoolStopId`: alias for current active pool stop
- `poolPickupStopId`: stop ID containing this booking's pickup
- `poolDropoffStopId`: stop ID containing this booking's dropoff
- `poolPhase`: rider-level pool phase, such as `waiting_pickup`, `onboard`, `dropped_off`
- `pickedUpAt`: timestamp when rider was picked up
- `droppedOffAt`: timestamp when rider was dropped off
- `passengerPickedUpAt`: passenger pickup timestamp used by app logic
- `onboard`: boolean rider onboard flag

Each object in `poolStopPlan` may contain:

- `stopId`, `stopIndex`, `stopType`, `jettyId`, `jettyName`, `stopName`
- `lat`, `lng`, `routePositionMeters`
- `bookingIds`: booking IDs served by this stop
- `passengerCount`: total passengers served by this stop
- `adultCount`: total adults served by this stop
- `childCount`: total children served by this stop
- `status`, `reachedAt`, `completedAt`

The stop-level passenger totals are additive fields. Older stop plans may not have them, so clients still fall back to summing loaded bookings or using `bookingIds.length`.

### Current-sweep deferral fields

These prevent repeatedly showing a booking that is not suitable for the current route sweep:

- `poolDeferredForOperatorUid`
- `poolDeferredRouteDirection`
- `poolDeferredPoolGroupId`
- `poolDeferredReason`
- `poolDeferredUntil`
- `poolDeferredAt`

## 4. Pooling Policy Constants

Defined in `POOLING_POLICY` in `index.js`.

```js
const POOLING_POLICY = {
  maxConcurrent: 3,
  pickupWindowMinutes: 15,
  addedEtaLimitMinutes: 8,
  staleAcceptedMinutes: 12,
  criteriaVersion: "v2_distance_deviation_eta",
  maxPickupDistanceMeters: 1000,
  maxRouteDeviationMeters: 1200,
  maxRouteOvershootRatio: 1.05,
  speedMetersPerSecond: 5.5,
  nextSweepDeferMinutes: 20,
  stopArrivalRadiusMeters: 30,
};
```

Meaning:

- `maxConcurrent`: maximum bookings in a pool, currently 3.
- `pickupWindowMinutes`: candidate request freshness window. It always rejects stale pending requests relative to `now`, but the comparison against existing pool booking creation times is only enforced before a trip starts. Mid-trip acceptance uses route-position eligibility instead.
- `addedEtaLimitMinutes`: maximum allowed added ETA impact.
- `staleAcceptedMinutes`: accepted bookings can be considered stale after this many minutes.
- `criteriaVersion`: written to booking documents to track algorithm version.
- `maxPickupDistanceMeters`: candidate pickup must be close enough to the active pool's pickup/operator reference.
- `maxRouteDeviationMeters`: candidate origin/destination must not be too far from the corridor.
- `maxRouteOvershootRatio`: candidate points may slightly overshoot the corridor end, up to this ratio.
- `speedMetersPerSecond`: assumed water-taxi speed for ETA calculations.
- `nextSweepDeferMinutes`: how long to defer a booking that belongs to a future route sweep.
- `stopArrivalRadiusMeters`: operator must be within this distance to mark a stop reached.

## 5. Geometry Utilities

The backend uses lightweight geometry rather than a routing engine.

### Point parsing

`asGeoPoint(value)` accepts Firestore-like points:

- `{ latitude, longitude }`
- `{ _latitude, _longitude }`

`normalizeRoutePoint(entry)` additionally accepts:

- `{ lat, lng }`
- `{ lat, lon }`
- `{ latitude, longitude }`
- Firestore internal coordinate shapes

`isValidPoint(point)` rejects:

- Missing/non-finite coordinates
- Latitude outside `[-90, 90]`
- Longitude outside `[-180, 180]`
- `(0, 0)` placeholder coordinates

### Distance

`haversineDistanceMeters(a, b)` calculates spherical distance using an earth radius of `6371000` meters.

### Local projection

`toXY(point, refLat)` converts latitude/longitude to approximate planar meters around a reference latitude.

`lineMetricsMeters(origin, destination, point)` projects a point onto a direct origin-destination line and returns:

- `deviationMeters`: perpendicular distance from the line
- `alongTrackRatio`: projection position where `0` means origin and `1` means destination

### Corridor projection

`projectPointToCorridor(corridor, point)` projects a point onto a polyline corridor.

For each segment of the corridor:

1. Convert the segment and point into local XY meters.
2. Project the point onto the segment.
3. Clamp projection parameter `t` to `[0, 1]`.
4. Measure perpendicular deviation.
5. Compute cumulative distance along the route.
6. Keep the segment with the smallest deviation.

Returned fields:

- `deviationMeters`
- `alongMeters`
- `alongTrackRatio`

This projection is the foundation for route direction, stop ordering, candidate rejection, and stop-plan route positions.

## 6. Corridor Construction

`buildCorridorFromBooking(booking)` creates a route corridor from a booking.

Inputs used:

- `originCoords`
- `destinationCoords`
- `routePolyline`

Behavior:

- If `routePolyline` has at least two valid points, it becomes the corridor.
- Otherwise, the corridor falls back to `[origin, destination]`.
- The function calculates cumulative segment distances and total route length.

`choosePoolCorridor(activeBookings, candidateBooking)` chooses which booking defines the corridor:

1. Prefer an active booking whose status is `on_the_way`.
2. Otherwise use the first active/accepted booking.
3. Otherwise use the candidate booking.

This is important: once a trip is underway, the system treats the current active route as the route corridor that new bookings must fit.

## 7. Booking Route Metrics

`routeMetricsForBooking(corridor, booking)` projects a booking's origin and destination onto the corridor.

It returns:

- `endpoints.origin`
- `endpoints.destination`
- `originDeviationMeters`
- `destinationDeviationMeters`
- `originAlongTrackRatio`
- `destinationAlongTrackRatio`
- `originAlongMeters`
- `destinationAlongMeters`
- `pickupDistanceMeters`

These metrics answer:

- How far is pickup from the corridor?
- How far is dropoff from the corridor?
- Where does pickup occur along the corridor?
- Where does dropoff occur along the corridor?
- Does the booking move with or against the current sweep?

## 8. Route Direction

Route direction is represented as:

- `forward`
- `reverse`
- empty string when unknown

`routeDirectionForMetrics(metrics)` returns:

- `forward` if `destinationAlongMeters >= originAlongMeters`
- `reverse` otherwise

`isBookingDirectionValidForPool(metrics, routeDirection)` enforces the sweep direction:

- For `reverse`, destination must be before origin on the corridor.
- For `forward`, destination must be after origin on the corridor.

This is why a candidate that travels from Jetty 16 to Jetty 12 during a forward sweep is rejected as `reverse_direction`.

`currentSweepDirection(activeBookings)` returns the first explicit `routeDirection` from active bookings.

## 9. Candidate Eligibility Algorithm

Implemented by `evaluatePoolingEligibility(activeBookings, candidateBooking, options)`.

Inputs:

- Existing active/accepted bookings for an operator
- Candidate booking
- Optional live operator point
- Optional requested route direction

Output:

- `eligible: true/false`
- `reason`
- `corridor`
- `routeDirection`
- Diagnostic metrics and score when applicable

### Step 1: Choose corridor

The function calls `choosePoolCorridor`.

If no corridor can be built, reject:

```text
reason = missing_coordinates
```

### Step 2: Compute metrics

Metrics are computed for all bookings:

```js
const allBookings = [...activeBookings, candidateBooking];
const metrics = allBookings.map((booking) =>
  routeMetricsForBooking(corridor, booking)
);
const candidateMetrics = routeMetricsForBooking(corridor, candidateBooking);
```

### Step 3: Resolve route direction

Priority:

1. Existing active sweep direction
2. Requested route direction from client
3. Candidate's own inferred direction

If active sweep direction and requested direction conflict:

```text
reason = mixed_route_direction_not_allowed
```

### Step 4: Reject reverse-direction mismatch

If candidate origin/destination order does not match the current sweep:

```text
reason = reverse_direction
```

This reason is also considered deferrable for a future sweep.

### Step 5: Reject outside corridor

`isBookingWithinCorridor(metrics)` requires:

- Maximum deviation <= `maxRouteDeviationMeters`
- Minimum along-track ratio >= `-0.05`
- Maximum along-track ratio <= `maxRouteOvershootRatio`

If any active or candidate booking fails:

```text
reason = outside_route_corridor
```

### Step 6: Reject pickup behind current operator

If the operator has a live location, project the operator onto the corridor.

For forward direction:

- candidate pickup is behind if `candidate.originAlongMeters <= operator.alongMeters`

For reverse direction:

- candidate pickup is behind if `candidate.originAlongMeters >= operator.alongMeters`

If behind:

```text
reason = pickup_behind_operator
```

This is a current-sweep rejection, not necessarily a permanent rejection.

Important mid-trip behavior:

- A candidate with a second pickup ahead of the boat and the same dropoff as an onboard rider is valid when it fits direction, corridor, pool size, and ETA limits.
- Example: active `A -> C`, candidate `B -> C`, route order `A < B < C`. If the operator is between A and B, the candidate should remain eligible. If the operator has already passed B, the expected reason is `pickup_behind_operator`.
- Same-pickup projection jitter is softened when the active pool still has an uncompleted pickup at the candidate's pickup jetty, so a booking at the current pickup is not incorrectly deferred just because live projection is slightly ahead of the marker.

### Step 7: Reject max pool size

If active booking count is already at `maxConcurrent`:

```text
reason = max_pool_reached
```

### Step 8: Estimate added distance and ETA

`estimateOrderedRouteDistanceMeters(anchor, corridor, bookings)` estimates travel along the corridor by:

1. Creating pickup and dropoff stops for each booking.
2. Sorting stops by `alongMeters`.
3. Starting from an anchor point.
4. Adding absolute movement along the route plus deviation to each stop.

For candidate evaluation:

- `activeDistance`: estimated distance for existing active bookings
- `pooledDistance`: estimated distance with candidate added
- `addedDistanceMeters = max(0, pooledDistance - activeDistance)`
- `addedEtaMinutes = addedDistanceMeters / speedMetersPerSecond / 60`

### Step 9: Estimate per-rider impact

`estimatePerBookingAddedEta(anchor, corridor, activeBookings, allBookings)` calculates arrival distances to dropoff for each booking in:

- baseline active-only plan
- candidate-only baseline for candidate
- pooled plan

It returns:

- `maxAddedEtaMinutes`
- `maxAddedDistanceMeters`
- per-booking details

If `maxAddedEtaMinutes > addedEtaLimitMinutes`:

```text
reason = added_eta_exceeded
```

### Step 10: Reject pickup too far from pool

`nearestActivePickupDistanceMeters(activeBookings, candidateMetrics)` compares candidate pickup against:

- live operator points from active bookings
- active booking origins

If nearest distance exceeds `maxPickupDistanceMeters`:

```text
reason = pickup_distance_exceeded
```

### Step 11: Score accepted candidate

Score formula:

```text
raw = (
  originDeviationMeters +
  destinationDeviationMeters +
  pickupDistanceToPoolMeters +
  addedDistanceMeters
) / 1000

score = clamp(1 / (1 + raw), 0, 1)
```

Higher score means a better fit.

If all checks pass:

```text
reason = eligible
```

### Candidate age versus active pool age

`acceptPooledBooking` applies two different time checks:

- Candidate freshness: the pending request's `createdAt` must be within `pickupWindowMinutes` of `now`.
- Pre-start pool batching: if the operator only has `accepted` bookings and no `on_the_way` booking, the candidate `createdAt` must also be within `pickupWindowMinutes` of the earliest active pool booking.

The second check is intentionally skipped once a boat is already `on_the_way`. This allows a new mid-trip request, such as `Kampung Jawa -> Samudera`, to join an older pool if the boat has not passed Kampung Jawa yet. In that case, `evaluatePoolingEligibility` decides using route geometry and live operator position. If the boat has already passed the pickup, the expected rejection is `pickup_behind_operator`, not a pickup-window error.

## 10. Current-Sweep Deferral

Some rejection reasons mean "not suitable for this current route sweep" rather than "invalid forever".

`isCurrentSweepDeferralReason(reason)` includes:

- `pickup_behind_operator`
- `reverse_direction`
- `mixed_route_direction_not_allowed`
- `route_ahead_distance_exceeded`
- `pickup_distance_exceeded`

When `acceptPooledBooking` receives one of these reasons, it calls `deferBookingForCurrentSweep`.

The booking receives:

- operator UID that deferred it
- route direction of current sweep
- pool group ID
- deferral reason
- deferral expiration time

The operator app filters these bookings from the visible queue while the current sweep still applies.

## 11. Pool Sequence Algorithm

Implemented by `planRouteAwarePoolSequence({ items, corridor, anchor })`.

Inputs:

- `items`: booking docs with `id`, `ref`, and `data`
- `corridor`
- `anchor`: current position or destination anchor

Behavior:

1. Split items into:
   - `activeItems`: status `on_the_way`
   - `acceptedItems`: status `accepted`
2. Project anchor onto the corridor.
3. Preserve the first `on_the_way` item as first in sequence.
4. Sort accepted items by route-aware completion cost.
5. Assign `poolSequence = index + 1`.

### Completion cost

`estimateBookingCompletionCost(anchorAlongMeters, corridor, booking)`:

```text
cost =
  abs(originAlongMeters - anchorAlongMeters) +
  max(0, destinationAlongMeters - originAlongMeters) +
  originDeviationMeters +
  destinationDeviationMeters
```

Tie-breakers in `routeAwareBookingSort`:

1. Lower completion cost.
2. Earlier destination along the route.
3. Earlier `createdAt`.

### Important limitation

The sequence algorithm orders bookings, not every pickup/dropoff independently. Stop-level ordering is handled separately by `buildPoolStopPlan`.

## 12. Pool Stop Plan Algorithm

Implemented by `buildPoolStopPlan({ items, corridor, previousItems, routeDirection })`.

Purpose:

- Build a shared list of pickup/dropoff stops for the pool.
- Group multiple bookings at the same stop.
- Preserve already completed/skipped stops during replanning.

### Completed stop preservation

`completedStopKeysFromPreviousItems(previousItems)` scans previous stop plans and records completed/skipped stop keys:

```text
stopType|bookingId
```

`completedStopsFromPreviousItems(previousItems, activeIds)` carries completed/skipped stop objects forward only if their booking IDs still belong to currently active items.

This prevents completed pickup/dropoff stops from returning as pending after a replan.

Completed/skipped stops also preserve or recompute `passengerCount`, `adultCount`, and `childCount` for their remaining active booking IDs. This keeps route-order labels stable after replans and avoids completed grouped stops losing their passenger totals.

### Pending stop generation

For each booking item:

1. Compute route metrics.
2. Build two stops:
   - pickup at origin
   - dropoff at destination
3. Skip stop if `completedKeys` already contains `stopType|bookingId`.
4. Group stop by:

```text
stopType|jettyId-or-stopName|roundedRoutePositionMeters
```

This lets multiple passengers share one pickup/dropoff stop when they are at the same jetty/position.

For each grouped stop, the backend accumulates:

- `passengerCount`: sum of `booking.passengerCount` for all grouped booking IDs
- `adultCount`: sum of `booking.adultCount`
- `childCount`: sum of `booking.childCount`

If a booking lacks `passengerCount`, the backend falls back to `adultCount + childCount`; if that is also unavailable, it uses `1`. This is primarily for legacy booking compatibility.

### Stop ordering

Pending stops are sorted by `routePositionMeters`.

- `forward`: ascending route position
- `reverse`: descending route position

Tie-breakers:

1. Pickup before dropoff.
2. Stop name alphabetical.

### Stop output fields

Each stop receives:

- `stopId`
- `stopIndex`
- `stopType`
- `jettyId`
- `jettyName`
- `stopName`
- `lat`
- `lng`
- `routePositionMeters`
- `bookingIds`
- `passengerCount`
- `adultCount`
- `childCount`
- `status`
- `reachedAt`
- `completedAt`

Operator UI labels prefer these stop-level totals. If they are missing, the UI falls back to summing currently loaded `poolBookings`, then to `bookingIds.length`. This prevents grouped stops from displaying a single passenger just because the selected active booking card only has one booking loaded at that moment.

## 13. Current Stop State

`resolveCurrentStopIndex(stopPlan)` returns the first stop that is not `completed` and not `skipped`.

`applyCurrentStopState(stopPlan, currentStopIndex)`:

- Leaves completed/skipped stops unchanged.
- Marks the current stop `active`.
- Marks other incomplete stops `pending`.

`currentStopFromPlan(stopPlan)` returns:

1. Explicit active stop if present.
2. First incomplete stop.
3. `null` if none exists.

`poolStopStatePayload(stopPlan, poolStatus)` returns:

- `plannedStops`
- `currentStopIndex`
- `currentStopId`
- `poolStatus`

## 14. Accept Pooled Booking Flow

Implemented by callable Cloud Function `acceptPooledBooking`.

High-level flow:

1. Require authenticated operator.
2. Load operator profile and candidate booking in a transaction.
3. Ensure candidate exists and is still `pending`.
4. Ensure candidate is not already assigned.
5. Ensure operator did not previously reject it.
6. Check booking age against pickup window.
7. Load operator's active bookings with status in `accepted` or `on_the_way`.
8. Enforce no more than one existing `on_the_way` booking.
9. Check the active pool pickup window only for pre-start batching.
10. Reject if active pool is already full.
11. Run `evaluatePoolingEligibility`.
12. If current-sweep deferrable, defer the booking instead of hard failing.
13. Resolve or create `poolGroupId`.
14. Build accepted candidate data.
15. Plan route-aware sequence.
16. Build stop plan.
17. Update existing accepted bookings and stop metadata.
18. Update candidate booking as `accepted`.
19. Write status history and return diagnostics.

Important behavior after the recent fix:

- A newly accepted booking always remains `accepted`.
- Only `startPooledBooking` or a pickup stop transition should promote a booking to `on_the_way`.
- If a trip is already active, `poolStatus` may be `in_progress`, but the new booking's own `status` remains `accepted`.
- Existing `on_the_way` documents are not unnecessarily rewritten with a new `poolSequence`.
- A pending request must still be fresh relative to `now`, but once the boat is already `on_the_way`, the candidate is no longer rejected just because the original pool booking was created more than `pickupWindowMinutes` earlier.
- During an active trip, route geometry decides whether the candidate can join: the pickup must still be ahead of the boat, match the current direction, fit the corridor, and satisfy ETA/distance limits.

## 15. Start Pooled Booking Flow

Implemented by `startPooledBooking`.

Purpose:

- Treat `Start Route` as a pool-level action.
- Promote the booking that belongs to the first current pool stop to `on_the_way`.
- Initialize stop-plan state for the pool.
- Preserve API compatibility with the existing `bookingId` parameter.

Flow:

1. Require authenticated operator.
2. Load requested booking.
3. Ensure requested booking belongs to operator and is accepted.
4. Query all active bookings for operator.
5. Reject if any booking is already `on_the_way`.
6. Consider accepted bookings.
7. Choose corridor.
8. Plan route-aware sequence.
9. Build stop plan.
10. Resolve the first active/current pool stop from `poolStopPlan`.
11. If that stop has `bookingIds`, choose the first accepted booking ID from the stop.
12. Start the resolved first-stop booking, even if the requested booking ID was a different accepted booking in the same pool.
13. Reject only when no valid first-stop booking can be resolved, the booking is outside the operator pool, or another booking is already `on_the_way`.
14. Update sequence and stop state for accepted items.
15. Update the resolved started booking to `on_the_way`.
16. Optionally store operator location.
17. Write status history.
18. Return `startedBookingId`, `requestedBookingId`, `currentStopId`, and `poolGroupId`.

The important behavior is stop-level first, booking-level second:

```js
const resolvedStartBookingId =
  startableBookingIdAtCurrentPoolStop(stopState.plannedStops, acceptedIds) ||
  bookingId;

const startedItem = sequencePlan.find(
  (item) => item.id === resolvedStartBookingId
);

const currentStopAllowsBooking = canStartBookingAtCurrentPoolStop(
  stopState.plannedStops,
  resolvedStartBookingId
);

if (currentStopAllowsBooking === false) {
  throw new HttpsError(
    "failed-precondition",
    "Start the route at the first pool stop first."
  );
}

if (!startedItem) {
  throw new HttpsError(
    "failed-precondition",
    "Unable to resolve the first route stop booking."
  );
}
```

This prevents the old field-test failure where the operator clicked a card for one booking while the stop plan's first pickup belonged to another booking. For example, if the stop plan says `Taman Rempah` is the first pickup and `The Shore` is second, `Start Route` resolves to the Taman Rempah booking and returns that ID as `startedBookingId`.

The operator app treats the client-side current-stop booking as a hint only. The backend response is the source of truth for which booking became active.

## 15.1 Reject Pooled Booking Flow

Implemented by `rejectPooledBooking`.

Purpose:

- Allow an operator to decline a pending booking even while the operator is mid-trip.
- Remove the booking from that operator's actionable pending queue without forcing the booking into terminal rejected state unless all online operators have rejected it.
- Centralize reject behavior in the backend instead of relying on a client-side transaction.

Flow:

1. Require authenticated operator.
2. Require `bookingId`.
3. Load the booking.
4. Require `status == pending`.
5. Require the booking to be unassigned.
6. Reject if this operator already appears in `rejectedBy`.
7. Add operator UID to `rejectedBy`.
8. If every currently online operator has rejected the request, set `status = rejected`; otherwise keep `status = pending`.
9. Clear operator-specific pool deferral fields so the declined card does not remain actionable for the same operator.
10. Write status history only when the booking status changes.

This callable is safe during active navigation because it does not require the operator to have zero `on_the_way` bookings.

## 16. Mark Pool Stop Reached Flow

Implemented by `markPoolStopReached`.

This is the stop-level lifecycle transition. It handles both pickup and dropoff stops.

Flow:

1. Require authenticated operator.
2. Load target booking.
3. Ensure target is `on_the_way`.
4. Query bookings in the same pool group with status `accepted` or `on_the_way`.
5. Load or rebuild stop plan.
6. Resolve current stop.
7. If operator location is provided, require distance to stop <= `stopArrivalRadiusMeters`.
8. Ensure current stop has active booking IDs.
9. Ensure target booking belongs to current stop.
10. Mark current stop completed.
11. Recompute current stop state.

### Pickup stop behavior

For a pickup stop:

- All pool items receive updated stop plan/current stop state.
- Bookings at the current stop are marked:
  - `status = on_the_way`
  - `passengerPickedUpAt`
  - `pickedUpAt`
  - `poolPhase = onboard`
  - `onboard = true`
- Accepted bookings at that stop get status history from `accepted` to `on_the_way`.

This means multiple bookings can become `on_the_way` when a grouped pickup stop is completed.

### Dropoff stop behavior

For a dropoff stop:

- Bookings not at the current stop receive updated stop plan state.
- Bookings at the current stop are marked:
  - `status = completed`
  - `poolPhase = dropped_off`
  - `onboard = false`
  - `droppedOffAt`
- Completed bookings are archived.
- If all pool items are completed, `poolStatus = completed`.

## 17. Complete Pooled Booking Flow

`completePooledBooking` is a booking-level completion function.

It enforces:

- Target booking must be `on_the_way`.
- Target operator must match.
- There must be exactly one `on_the_way` booking for the operator and it must be the target.

If accepted bookings remain after completion:

- It chooses a corridor.
- It replans sequence from the completed booking's destination.
- It updates `poolSequence` and criteria version for accepted bookings.

This function is more booking-level than stop-level; the newer pool stop flow is handled by `markPoolStopReached`.

## 18. Replanning

`replanPoolSequenceOnBookingExit` triggers on Firestore booking document updates.

It replans when a booking leaves the active pool:

- Before status was `accepted` or `on_the_way`
- After status is not `accepted` or `on_the_way`, or operator changed

It does not replan when a booking stays in pool with the same operator.

`replanRouteAwarePoolForOperator`:

1. Queries remaining `accepted` and `on_the_way` bookings.
2. Exits if no accepted bookings remain.
3. Chooses corridor.
4. Chooses anchor from exited booking destination or sequence anchor.
5. Plans sequence.
6. Builds stop plan with previous stop plans.
7. Preserves completed/skipped stops.
8. Writes updated sequence/stop state only when changed.

## 19. Stale Accepted Booking Cleanup

There is scheduled/maintenance logic around stale accepted bookings. Relevant policy:

- `staleAcceptedMinutes = 12`

The intent is to prevent accepted bookings from remaining indefinitely queued if not started.

## 20. Operator App Sorting

The operator app sorts active bookings so:

1. `on_the_way` bookings come before accepted bookings.
2. Lower `poolSequence` comes first.
3. Bookings with a sequence come before those without.
4. Newer `updatedAt` can break ties.

Relevant locations:

- `operator_home_view_model.dart`
- `booking_repository.dart`

## 21. Operator Map Route Resolution

Implemented in `OperatorMapLayers`.

The map layer decides which polyline to show based on phase and available data.

### Route phase

`OperatorRoutePhase`:

- `toPickup`
- `toDestination`
- `none`

### Route source

`OperatorRouteSource`:

- `routeToOriginPolyline`
- `routeToDestinationPolyline`
- `straightLineFallback`
- `none`

### Active navigation booking

`isActiveNavigationBooking(booking)` returns true when:

- booking status is `on_the_way`, or
- booking `poolStatus == in_progress`

### Stop-first routing

When `booking.currentPoolStop` exists, map routing targets that stop instead of simply origin/destination.

`_stopFirstRoutePoints`:

1. Uses booking's stored route polyline.
2. Snaps operator location and current stop to the route.
3. Extracts the route segment between them.
4. Respects `routeDirection` for closed-loop routes.
5. Avoids rendering a route if operator is severely far from the stored route.
6. Optionally attaches live operator and stop anchors.

### Closed-loop route handling

For closed loops:

- If `routeDirection == forward`, extract segment with positive step.
- If `routeDirection == reverse`, extract segment with negative step.
- If direction unknown, choose shortest loop segment.

This matters for water routes where the polyline begins and ends near the same place.

### Fallback route

If no usable route polyline exists:

- To pickup: straight line from operator to origin/current stop.
- To destination: straight line from operator to destination/current stop.

Fallback route health includes warning text so the UI can tell the operator route quality is degraded.

## 22. Operator Navigation Guidance

Implemented by `computeOperatorNavigationGuidance`.

Inputs:

- booking
- current latitude/longitude
- current time
- reported speed
- smoothed speed
- previous GPS sample
- last resolved route marker

Output: `OperatorNavigationGuidance`

Fields include:

- `bookingId`
- `nearestRouteMarker`
- `nextRouteMarker`
- `totalRouteMarkers`
- `progressFraction`
- `remainingDistanceMeters`
- `offRouteDistanceMeters`
- `isOffRoute`
- `speedMetersPerSecond`
- `eta`
- `headingDegrees`
- `offRouteSeverity`
- `rejoinPoint`
- `routeHealth`
- `stopOvershootSeverity`
- `stopOvershootDistanceMeters`

### Preconditions

Guidance returns `null` unless booking status is `on_the_way`.

### Destination selection

If current pool stop exists:

- Destination is current stop coordinates.

Otherwise:

- Before pickup: destination is booking origin.
- After pickup: destination is booking destination.

### Progress projection

`_projectProgressOnRoute`:

1. Uses resolved route polyline when available.
2. Falls back to direct line when route has fewer than two points.
3. Finds nearest polyline segment to current operator point.
4. Calculates:
   - progress fraction
   - remaining distance
   - off-route distance
   - nearest segment index
   - rejoin point

Remaining distance for polyline route:

```text
remaining = totalRouteDistance - traveledAlongRoute + offRouteDistance
```

### Off-route severity

`_resolveOffRouteSeverity`:

- `onRoute`: distance <= tolerance, default 80 m
- `mild`: distance <= 150 m
- `moderate`: distance <= 300 m
- `severe`: distance > 300 m

If severe:

- Progress may be paused/floored.
- ETA may be hidden.
- UI can show rejoin guidance.

### Severe off-route cap

If off-route distance exceeds 5000 m:

- It is capped at 5000 m.
- Remaining distance falls back to total route distance.
- Progress is not allowed to go backward below previous marker.

### Monotonic progress

The view model stores `_maxReachedRouteMarker`.

If a new GPS projection would move backward:

- nearest route marker is clamped to last reached marker.

This avoids jitter causing the progress UI to regress.

### ETA

Speed priority:

1. Smoothed speed if >= 0.5 m/s
2. Instant reported/derived speed if >= 0.5 m/s

ETA:

```text
eta = remainingDistanceMeters / speedMetersPerSecond
```

ETA is not shown for severe off-route states.

### Heading

Heading is resolved from:

1. Movement between last GPS sample and current GPS sample if movement >= 1 m
2. Route segment bearing
3. `null`

### Stop overshoot

`_resolveStopOvershoot` compares operator route position with current stop route position.

It skips first-pickup deadhead warnings because movement toward first pickup may legitimately oppose the passenger route.

Thresholds:

- <= 30 m: no overshoot
- <= 50 m: soft overshoot
- > 50 m: missed stop

For forward direction:

```text
overshoot = operatorRoutePosition - stopRoutePosition
```

For reverse direction:

```text
overshoot = stopRoutePosition - operatorRoutePosition
```

## 23. View Model GPS Lifecycle

`OperatorHomeViewModel` manages live GPS updates.

Important behavior:

- Starts location sharing when an operator is online and has an `on_the_way` booking.
- Uses high accuracy location stream with `distanceFilter: 0`.
- Refreshes navigation guidance on each location tick.
- Publishes operator location to backend subject to throttling:
  - minimum interval: 6 seconds
  - minimum distance: 20 meters
- Runs heartbeat refresh every 2 seconds when stream data is stale.
- Marks live location stale after 45 seconds.

The UI now separates:

- `OperatorHomeSnapshot`: full map/navigation state, includes GPS churn.
- `OperatorBookingCardSnapshot`: stable booking card state, excludes GPS/navigation churn.

This prevents the top booking card from rebuilding on every GPS tick while still allowing map/navigation widgets to update live.

## 24. End-to-End Lifecycle Example

### Scenario

- Booking A: Jetty 11 to Jetty 20
- Booking B: Jetty 12 to Jetty 20
- Booking C: Jetty 14 to Jetty 18

### Accept A

1. A is pending.
2. Operator accepts A.
3. No active pool exists.
4. Corridor comes from A.
5. A passes eligibility.
6. `poolGroupId` is created.
7. A gets `status = accepted`.
8. A gets `poolSequence = 1`.
9. Stop plan has pickup A and dropoff A.

### Accept B

1. Active bookings include A.
2. Corridor comes from A.
3. B is projected onto A corridor.
4. B moves in same direction.
5. B pickup/dropoff fit corridor.
6. Added ETA is within limit.
7. Stop plan groups A and B dropoff if same jetty.
8. B gets `status = accepted`.
9. B gets sequence based on route-aware cost.

For a two-pickup, one-dropoff case:

- A: Jetty 15 to Jetty 22
- B: Jetty 18 to Jetty 22
- Forward route order: 15, 18, 22

Expected stop plan:

1. Pickup A at Jetty 15
2. Pickup B at Jetty 18
3. Grouped dropoff A+B at Jetty 22

The grouped dropoff has `bookingIds = [A, B]` and `passengerCount = 2` when both bookings have one passenger.

### Start A

1. Operator starts first route-aware booking.
2. System checks A is sequence 1.
3. A becomes `on_the_way`.
4. Stop plan becomes `in_progress`.
5. Current stop becomes first pending pickup.

### Complete pickup stop

1. Operator reaches current stop.
2. `markPoolStopReached` checks distance <= 30 m.
3. Current pickup stop becomes completed.
4. Bookings at this stop become onboard.
5. Next stop becomes active.

### Accept C mid-trip

1. A is `on_the_way`.
2. Candidate C is evaluated against A's active corridor.
3. If eligible, C is added as `accepted`.
4. Pool stop plan is rebuilt while preserving completed stops.
5. A remains `on_the_way`.
6. C waits until its pickup stop or start condition promotes it.

For a mid-trip two-pickup, one-dropoff case, candidate B should be accepted while the operator is still before B. Once the operator has passed B, B is deferred for a future sweep with `pickup_behind_operator`.

## 25. Key Algorithmic Assumptions

The current DRT system assumes:

- Pool size is small, so simple route-aware sorting is acceptable.
- A single route corridor can represent a pooled trip.
- Existing `on_the_way` booking should dominate corridor choice.
- Direction consistency matters more than opportunistic reverse pickup.
- Stop-level grouping by jetty/route position is sufficient.
- Stop-level passenger totals are the source of truth for grouped stop labels.
- Travel time can be approximated by route distance divided by constant speed.
- Operator GPS may be noisy, so progress must be monotonic and off-route-aware.

## 26. Known Limitations

This is not a full dial-a-ride optimizer.

Limitations:

- No global assignment across multiple operators.
- No exact pickup/dropoff precedence solver.
- Sequence cost is heuristic, not optimal.
- ETA uses constant speed rather than traffic/weather/tide-aware speed.
- Corridor fit depends heavily on stored route polyline quality.
- The stop grouping key uses rounded route position, jetty ID, and stop type.
- Closed-loop routes require correct `routeDirection` to avoid wrong loop segment.
- Multiple bookings can become `on_the_way` after grouped pickup stops, which is intentional for onboard riders but can complicate "only one active booking" assumptions in older code paths.
- Replanning preserves completed stops, but route changes can still affect future pending stop positions.
- Older stop plans may not include stop-level passenger totals, so clients must keep fallback count logic.
- Off-route detection is geometric distance from polyline, not navigability.

## 27. Important Rejection Reasons

Eligibility rejection reasons:

- `missing_coordinates`: unable to build route/corridor.
- `mixed_route_direction_not_allowed`: requested direction conflicts with active sweep.
- `reverse_direction`: candidate moves against current sweep.
- `outside_route_corridor`: candidate pickup/dropoff too far from corridor or outside route bounds.
- `pickup_behind_operator`: candidate pickup is behind the operator's current position.
- `max_pool_reached`: pool already at capacity.
- `added_eta_exceeded`: candidate adds too much rider delay.
- `pickup_distance_exceeded`: candidate pickup too far from current pool/operator reference.

Deferrable current-sweep reasons:

- `pickup_behind_operator`
- `reverse_direction`
- `mixed_route_direction_not_allowed`
- `route_ahead_distance_exceeded`
- `pickup_distance_exceeded`

## 28. Tests Worth Reading

`pooling.stop-plan.test.js` contains a compact scenario with:

- Three concurrent bookings.
- Max pool rejection.
- Reverse direction rejection.
- Pickup-behind-operator rejection.
- Completed pickup preservation.
- Adding a new booking mid-route.
- Stop ordering and grouped dropoff checks.
- Grouped pickup/dropoff passenger totals.
- Two-pickup, one-shared-dropoff acceptance before the second pickup is passed.
- Two-pickup, one-shared-dropoff deferral after the second pickup is passed.

This is currently the best single test file for understanding the DRT backend behavior.

## 29. How To Analyze A Booking Decision Manually

When you want to understand why a candidate booking was accepted/rejected:

1. Identify current operator active bookings:
   - statuses `accepted`, `on_the_way`
   - `operatorUid`
   - `poolGroupId`
   - `routeDirection`
2. Identify corridor source:
   - existing `on_the_way` booking if present
   - otherwise first active booking
   - otherwise candidate
3. Check candidate origin/destination coordinates.
4. Project candidate endpoints onto corridor.
5. Check direction:
   - forward: destination position > origin position
   - reverse: destination position < origin position
6. Check corridor deviation:
   - both endpoints <= 1200 m deviation
   - along-track ratio not too far before/after corridor
7. Check live operator position:
   - candidate pickup must not be behind current sweep
   - for `A -> C` active and `B -> C` candidate, B is valid only while B is ahead of the operator
8. Check pool size <= 3.
9. Estimate added distance and ETA.
10. Check max per-rider added ETA <= 8 minutes.
11. Check candidate pickup distance <= 1000 m from active/operator reference.
12. Inspect `poolEtaSnapshot` written on accepted bookings for diagnostics.
13. Inspect `poolStopPlan` grouped stops:
   - shared pickup/dropoff stops should contain all grouped `bookingIds`
   - `passengerCount`, `adultCount`, and `childCount` should match the grouped bookings

## 30. Suggested Future Improvements

Potential algorithm upgrades:

- Add explicit solver for pickup/dropoff precedence instead of heuristic booking sequence.
- Add operator-level global matching/ranking across all pending bookings.
- Replace constant speed with empirical speed by route segment/time/weather.
- Add stronger invariant checks around multiple `on_the_way` bookings.
- Normalize stop identity with stable jetty IDs instead of rounded route position when possible.
- Store route projection metrics at acceptance time for easier debugging.
- Add callable tests for `acceptPooledBooking`, `rejectPooledBooking`, `startPooledBooking`, and `markPoolStopReached`.
- Add property tests for completed-stop preservation across replans.
- Add visual debug overlays for corridor projection, candidate deviation, and pickup-behind-operator decisions.
