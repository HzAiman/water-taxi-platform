process.env.NODE_ENV = "test";

const assert = require("node:assert/strict");
const test = require("node:test");

const { __poolingTest } = require("../index.js");

const {
  BOOKING_FIELDS,
  POOLING_POLICY,
  choosePoolCorridor,
  evaluatePoolingEligibility,
  planRouteAwarePoolSequence,
  buildPoolStopPlan,
  resolveCurrentStopIndex,
  applyCurrentStopState,
  currentStopFromPlan,
} = __poolingTest;

const baseLat = 2.2;
const baseLng = 102.2;
const lngStep = 0.00045;

function jetty(index) {
  return {
    lat: baseLat,
    lng: baseLng + (index - 1) * lngStep,
    name: `Jetty ${index}`,
    id: `jetty_${index}`,
  };
}

const routePolyline = Array.from({ length: 23 }, (_, i) => {
  const point = jetty(i + 1);
  return { _latitude: point.lat, _longitude: point.lng };
});

function geo(point) {
  return { _latitude: point.lat, _longitude: point.lng };
}

function booking(id, pickupIndex, dropoffIndex, overrides = {}) {
  const pickup = jetty(pickupIndex);
  const dropoff = jetty(dropoffIndex);
  return {
    [BOOKING_FIELDS.bookingId]: id,
    [BOOKING_FIELDS.status]: "accepted",
    [BOOKING_FIELDS.origin]: pickup.name,
    [BOOKING_FIELDS.destination]: dropoff.name,
    originJettyId: pickup.id,
    destinationJettyId: dropoff.id,
    [BOOKING_FIELDS.originCoords]: geo(pickup),
    [BOOKING_FIELDS.destinationCoords]: geo(dropoff),
    [BOOKING_FIELDS.routePolyline]: routePolyline,
    [BOOKING_FIELDS.createdAt]: new Date("2026-05-12T00:00:00.000Z"),
    [BOOKING_FIELDS.updatedAt]: new Date("2026-05-12T00:00:00.000Z"),
    ...overrides,
  };
}

function item(id, data) {
  return { id, data };
}

function pendingStopLabels(stopPlan) {
  return stopPlan
    .filter((stop) => stop.status !== "completed" && stop.status !== "skipped")
    .map(
      (stop) =>
        `${stop.stopType}:${stop.stopName}:${[...stop.bookingIds].sort().join(",")}`
    );
}

function planFor(bookings, anchorBooking = bookings[0], previousItems = []) {
  const items = bookings.map((data) => item(data[BOOKING_FIELDS.bookingId], data));
  const corridor = choosePoolCorridor(bookings, anchorBooking);
  const sequence = planRouteAwarePoolSequence({
    items,
    corridor,
    anchor: jetty(10.5),
  });
  const rawPlan = buildPoolStopPlan({
    items: sequence,
    corridor,
    anchor: jetty(10.5),
    previousItems,
  });
  return applyCurrentStopState(
    rawPlan,
    resolveCurrentStopIndex(rawPlan, sequence)
  );
}

test("complex stop-level pooling scenario follows route-aware stop order", () => {
  const a = booking("A", 11, 20);
  const b = booking("B", 12, 20);
  const c = booking("C", 14, 18);
  const d = booking("D", 13, 23);
  const e = booking("E", 9, 15);
  const f = booking("F", 16, 12);

  const initialActive = [a, b, c];
  assert.equal(initialActive.length, POOLING_POLICY.maxConcurrent);
  assert.equal(
    initialActive.length >= POOLING_POLICY.maxConcurrent,
    true,
    "D must be rejected by max pool limit before eligibility checks"
  );
  assert.equal(
    evaluatePoolingEligibility(initialActive, d).eligible,
    false,
    "D is not eligible once the pool is already full"
  );
  assert.equal(
    evaluatePoolingEligibility([a, b], f).reason,
    "reverse_direction",
    "F is rejected because it travels backward against the stored route"
  );

  const initialPlan = planFor(initialActive);
  assert.deepEqual(pendingStopLabels(initialPlan), [
    "pickup:Jetty 11:A",
    "pickup:Jetty 12:B",
    "pickup:Jetty 14:C",
    "dropoff:Jetty 18:C",
    "dropoff:Jetty 20:A,B",
  ]);
  assert.equal(currentStopFromPlan(initialPlan).stopName, "Jetty 11");

  const operatorBetween12And13 = {
    [BOOKING_FIELDS.status]: "on_the_way",
    [BOOKING_FIELDS.operatorLat]: baseLat,
    [BOOKING_FIELDS.operatorLng]: baseLng + 11.5 * lngStep,
    [BOOKING_FIELDS.updatedAt]: new Date(),
  };
  const activeMidTrip = [
    { ...a, ...operatorBetween12And13, passengerPickedUpAt: new Date() },
    b,
    c,
  ];

  assert.equal(
    evaluatePoolingEligibility(activeMidTrip, e).reason,
    "pickup_behind_operator",
    "E stays rejected because Jetty 9 is behind the operator"
  );

  const pickupACompletedPlan = initialPlan.map((stop) =>
    stop.stopName === "Jetty 11" && stop.stopType === "pickup"
      ? { ...stop, status: "completed", completedAt: new Date() }
      : stop
  );
  const afterCancelCPlan = planFor(
    [
      { ...a, ...operatorBetween12And13, passengerPickedUpAt: new Date() },
      b,
    ],
    a,
    [item("A", { ...a, [BOOKING_FIELDS.poolStopPlan]: pickupACompletedPlan })]
  );
  assert.deepEqual(pendingStopLabels(afterCancelCPlan), [
    "pickup:Jetty 12:B",
    "dropoff:Jetty 20:A,B",
  ]);

  const g = booking("G", 19, 23);
  const gEligibilityBeforeJetty19 = evaluatePoolingEligibility(
    [
      { ...a, ...operatorBetween12And13, passengerPickedUpAt: new Date() },
      b,
    ],
    g
  );
  assert.equal(gEligibilityBeforeJetty19.eligible, true);

  const withGPlan = planFor(
    [
      { ...a, ...operatorBetween12And13, passengerPickedUpAt: new Date() },
      b,
      g,
    ],
    a,
    [item("A", { ...a, [BOOKING_FIELDS.poolStopPlan]: pickupACompletedPlan })]
  );
  assert.deepEqual(pendingStopLabels(withGPlan), [
    "pickup:Jetty 12:B",
    "pickup:Jetty 19:G",
    "dropoff:Jetty 20:A,B",
    "dropoff:Jetty 23:G",
  ]);

  const operatorPastJetty19 = {
    ...operatorBetween12And13,
    [BOOKING_FIELDS.operatorLng]: baseLng + 19.25 * lngStep,
  };
  assert.equal(
    evaluatePoolingEligibility(
      [{ ...a, ...operatorPastJetty19, passengerPickedUpAt: new Date() }, b],
      g
    ).reason,
    "pickup_behind_operator",
    "G is rejected once the operator is already past Jetty 19"
  );
});
