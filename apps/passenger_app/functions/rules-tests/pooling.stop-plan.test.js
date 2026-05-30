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
  canStartBookingAtCurrentPoolStop,
  startableBookingIdAtCurrentPoolStop,
  canCompleteCurrentPoolStopWithBooking,
  shouldEnforceActivePoolPickupWindow,
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
    [BOOKING_FIELDS.passengerCount]: 1,
    [BOOKING_FIELDS.adultCount]: 1,
    [BOOKING_FIELDS.childCount]: 0,
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

test("start gate follows current pool stop before booking sequence", () => {
  const stopPlan = [
    {
      stopId: "pickup_taman_rempah",
      stopIndex: 0,
      stopType: "pickup",
      stopName: "15 - Taman Rempah",
      bookingIds: ["taman-rempah-booking"],
      status: "active",
    },
    {
      stopId: "pickup_the_shore",
      stopIndex: 1,
      stopType: "pickup",
      stopName: "18 - The Shore",
      bookingIds: ["the-shore-booking"],
      status: "pending",
    },
  ];

  assert.equal(
    canStartBookingAtCurrentPoolStop(stopPlan, "the-shore-booking"),
    false,
    "The Shore booking must not start while Taman Rempah is the active stop"
  );
  assert.equal(
    canStartBookingAtCurrentPoolStop(stopPlan, "taman-rempah-booking"),
    true,
    "Taman Rempah booking is allowed because it belongs to the current stop"
  );
  assert.equal(
    canStartBookingAtCurrentPoolStop([], "the-shore-booking"),
    null,
    "Missing stop plan falls back to the booking-level sequence gate"
  );
});

test("one pickup to two dropoffs stores grouped pickup passenger totals", () => {
  const a = booking("A", 18, 22);
  const b = booking("B", 18, 24);

  const stopPlan = planFor([a, b]);
  const pickup = stopPlan.find(
    (stop) => stop.stopType === "pickup" && stop.stopName === "Jetty 18"
  );

  assert.deepEqual(pendingStopLabels(stopPlan), [
    "pickup:Jetty 18:A,B",
    "dropoff:Jetty 22:A",
    "dropoff:Jetty 24:B",
  ]);
  assert.equal(pickup?.passengerCount, 2);
  assert.equal(pickup?.adultCount, 2);
  assert.equal(pickup?.childCount, 0);
});

test("two pickups to one dropoff stores shared dropoff passenger totals", () => {
  const a = booking("A", 15, 22);
  const b = booking("B", 18, 22);

  const stopPlan = planFor([a, b]);
  const sharedDropoff = stopPlan.find(
    (stop) => stop.stopType === "dropoff" && stop.stopName === "Jetty 22"
  );

  assert.deepEqual(pendingStopLabels(stopPlan), [
    "pickup:Jetty 15:A",
    "pickup:Jetty 18:B",
    "dropoff:Jetty 22:A,B",
  ]);
  assert.equal(sharedDropoff?.passengerCount, 2);
  assert.equal(sharedDropoff?.adultCount, 2);
  assert.equal(sharedDropoff?.childCount, 0);
});

test("two pickups to one dropoff is eligible until the second pickup is passed", () => {
  const active = booking("A", 15, 22, {
    [BOOKING_FIELDS.status]: "on_the_way",
    [BOOKING_FIELDS.routeDirection]: "forward",
    [BOOKING_FIELDS.operatorLat]: baseLat,
    [BOOKING_FIELDS.operatorLng]: baseLng + 15.5 * lngStep,
    [BOOKING_FIELDS.passengerPickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
    [BOOKING_FIELDS.pickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
    [BOOKING_FIELDS.onboard]: true,
  });
  const candidate = booking("B", 18, 22, {
    [BOOKING_FIELDS.status]: "pending",
  });

  const beforeSecondPickup = evaluatePoolingEligibility([active], candidate);
  assert.equal(beforeSecondPickup.eligible, true);
  assert.equal(beforeSecondPickup.reason, "eligible");

  const activePastSecondPickup = {
    ...active,
    [BOOKING_FIELDS.operatorLng]: baseLng + 18.5 * lngStep,
  };
  const afterSecondPickup = evaluatePoolingEligibility(
    [activePastSecondPickup],
    candidate
  );
  assert.equal(afterSecondPickup.reason, "pickup_behind_operator");
});

test("static accepted pool can add same-direction pickup ahead without live movement", () => {
  const previousMaxPickupDistance = POOLING_POLICY.maxPickupDistanceMeters;
  POOLING_POLICY.maxPickupDistanceMeters = 10;
  try {
    const active = booking("A", 15, 22, {
      [BOOKING_FIELDS.status]: "accepted",
      [BOOKING_FIELDS.routeDirection]: "forward",
    });
    const candidate = booking("B", 18, 22, {
      [BOOKING_FIELDS.status]: "pending",
    });

    const eligibility = evaluatePoolingEligibility([active], candidate);

    assert.equal(eligibility.eligible, true);
    assert.equal(eligibility.reason, "eligible");
    assert.equal(
      eligibility.candidatePickupRouteAheadDistanceMeters > 0,
      true,
      "Candidate pickup should be treated as ahead from the route-origin fallback anchor"
    );
  } finally {
    POOLING_POLICY.maxPickupDistanceMeters = previousMaxPickupDistance;
  }
});

test("completed first pickup remains completed when replanning two pickups to one dropoff", () => {
  const a = booking("A", 15, 22, {
    [BOOKING_FIELDS.status]: "on_the_way",
    [BOOKING_FIELDS.routeDirection]: "forward",
    [BOOKING_FIELDS.operatorLat]: baseLat,
    [BOOKING_FIELDS.operatorLng]: baseLng + 16 * lngStep,
    [BOOKING_FIELDS.passengerPickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
    [BOOKING_FIELDS.pickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
    [BOOKING_FIELDS.onboard]: true,
  });
  const b = booking("B", 18, 22);
  const initialPlan = planFor([a]);
  const pickupACompletedPlan = initialPlan.map((stop) =>
    stop.stopName === "Jetty 15" && stop.stopType === "pickup"
      ? { ...stop, status: "completed", completedAt: new Date() }
      : stop
  );

  const replanned = planFor(
    [a, b],
    a,
    [item("A", { ...a, [BOOKING_FIELDS.poolStopPlan]: pickupACompletedPlan })]
  );

  assert.deepEqual(
    replanned.map(
      (stop) =>
        `${stop.status}:${stop.stopType}:${stop.stopName}:${[...stop.bookingIds].sort().join(",")}:${stop.passengerCount}`
    ),
    [
      "completed:pickup:Jetty 15:A:1",
      "active:pickup:Jetty 18:B:1",
      "pending:dropoff:Jetty 22:A,B:2",
    ]
  );
});

test("active pool handle can complete the next pickup stop", () => {
  const stopPlan = [
    {
      stopId: "pickup_stadthuys",
      stopIndex: 0,
      stopType: "pickup",
      stopName: "Stadthuys",
      bookingIds: ["stadthuys-booking"],
      status: "completed",
    },
    {
      stopId: "pickup_quayside",
      stopIndex: 1,
      stopType: "pickup",
      stopName: "Quayside",
      bookingIds: ["quayside-booking"],
      status: "active",
    },
    {
      stopId: "dropoff_samudera",
      stopIndex: 2,
      stopType: "dropoff",
      stopName: "Samudera",
      bookingIds: ["stadthuys-booking", "quayside-booking"],
      status: "pending",
    },
  ];

  assert.equal(
    canCompleteCurrentPoolStopWithBooking(
      stopPlan,
      "stadthuys-booking",
      new Set(["stadthuys-booking"])
    ),
    true,
    "The current on-the-way booking can act as the pool-level completion handle"
  );
  assert.equal(
    canCompleteCurrentPoolStopWithBooking(
      stopPlan,
      "quayside-booking",
      new Set(["stadthuys-booking"])
    ),
    true,
    "The booking attached to the current pickup stop can complete that stop"
  );
  assert.equal(
    canCompleteCurrentPoolStopWithBooking(
      stopPlan,
      "samudera-only-booking",
      new Set(["stadthuys-booking"])
    ),
    false,
    "A non-current booking that is not the active pool handle is rejected"
  );
});

test("startable booking resolves from the first current pool stop", () => {
  const stopPlan = [
    {
      stopId: "pickup_first",
      stopIndex: 0,
      stopType: "pickup",
      stopName: "First pickup",
      bookingIds: ["first-booking"],
      status: "active",
    },
    {
      stopId: "pickup_second",
      stopIndex: 1,
      stopType: "pickup",
      stopName: "Second pickup",
      bookingIds: ["second-booking"],
      status: "pending",
    },
  ];

  assert.equal(
    startableBookingIdAtCurrentPoolStop(
      stopPlan,
      new Set(["first-booking", "second-booking"])
    ),
    "first-booking",
    "Start Route should resolve to the first active stop booking"
  );
  assert.equal(
    startableBookingIdAtCurrentPoolStop(stopPlan, new Set(["second-booking"])),
    null,
    "A booking outside the current stop cannot be auto-selected"
  );
});

test("active pickup window is pre-start only", () => {
  assert.equal(
    shouldEnforceActivePoolPickupWindow({ hasActiveTrip: false }),
    true,
    "Accepted-only pooling still enforces the pre-start pickup window"
  );
  assert.equal(
    shouldEnforceActivePoolPickupWindow({ hasActiveTrip: true }),
    false,
    "Mid-trip pooling relies on route-position eligibility instead of pool age"
  );
});

test("mid-trip ahead pickup is eligible until the boat passes it", () => {
  const active = booking("A", 18, 27, {
    [BOOKING_FIELDS.status]: "on_the_way",
    [BOOKING_FIELDS.routeDirection]: "forward",
    [BOOKING_FIELDS.operatorLat]: baseLat,
    [BOOKING_FIELDS.operatorLng]: baseLng + 18.5 * lngStep,
    [BOOKING_FIELDS.createdAt]: new Date("2026-05-12T07:00:00.000Z"),
  });
  const kampungJawaToSamudera = booking("KJ", 22, 27, {
    [BOOKING_FIELDS.createdAt]: new Date("2026-05-12T07:27:00.000Z"),
  });

  const beforeKampungJawa = evaluatePoolingEligibility(
    [active],
    kampungJawaToSamudera
  );
  assert.equal(
    beforeKampungJawa.eligible,
    true,
    "Kampung Jawa pickup should be eligible while the boat is still before it"
  );

  const activePastKampungJawa = {
    ...active,
    [BOOKING_FIELDS.operatorLng]: baseLng + 22.5 * lngStep,
  };
  const afterKampungJawa = evaluatePoolingEligibility(
    [activePastKampungJawa],
    kampungJawaToSamudera
  );
  assert.equal(
    afterKampungJawa.reason,
    "pickup_behind_operator",
    "Kampung Jawa pickup should be rejected once the boat has passed it"
  );
});

test("mid-trip same-sweep pickup ahead is not deferred by straight-line pickup distance", () => {
  const previousMaxPickupDistance = POOLING_POLICY.maxPickupDistanceMeters;
  POOLING_POLICY.maxPickupDistanceMeters = 80;
  try {
    const active = booking("A", 15, 20, {
      [BOOKING_FIELDS.status]: "on_the_way",
      [BOOKING_FIELDS.routeDirection]: "forward",
      [BOOKING_FIELDS.operatorLat]: baseLat,
      [BOOKING_FIELDS.operatorLng]: baseLng + 18.5 * lngStep,
      [BOOKING_FIELDS.passengerPickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
      [BOOKING_FIELDS.pickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
      [BOOKING_FIELDS.onboard]: true,
    });
    const aheadPickup = booking("Ahead", 22, 23, {
      [BOOKING_FIELDS.status]: "pending",
    });

    const eligibility = evaluatePoolingEligibility([active], aheadPickup);

    assert.equal(
      eligibility.eligible,
      true,
      "A same-direction pickup ahead on the current route should stay in the current sweep even when straight-line pickup distance exceeds the generic threshold"
    );
    assert.equal(
      eligibility.reason,
      "eligible",
      "Valid ahead pickup should not be deferred as pickup_distance_exceeded"
    );
  } finally {
    POOLING_POLICY.maxPickupDistanceMeters = previousMaxPickupDistance;
  }
});

test("mid-trip ETA calculation does not revisit already completed active pickup", () => {
  const active = booking("A", 11, 20, {
    [BOOKING_FIELDS.status]: "on_the_way",
    [BOOKING_FIELDS.routeDirection]: "forward",
    [BOOKING_FIELDS.operatorLat]: baseLat,
    [BOOKING_FIELDS.operatorLng]: baseLng + 18.5 * lngStep,
    [BOOKING_FIELDS.passengerPickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
    [BOOKING_FIELDS.pickedUpAt]: new Date("2026-05-12T07:10:00.000Z"),
    [BOOKING_FIELDS.onboard]: true,
  });
  const aheadPickup = booking("Ahead", 21, 23, {
    [BOOKING_FIELDS.status]: "pending",
  });

  const eligibility = evaluatePoolingEligibility([active], aheadPickup);

  assert.equal(eligibility.eligible, true);
  assert.equal(
    eligibility.maxPerRiderAddedEtaMinutes <= POOLING_POLICY.addedEtaLimitMinutes,
    true,
    "Already picked-up passengers should be evaluated from their remaining dropoff leg, not from their completed pickup stop"
  );
});

test("same uncompleted pickup is not deferred by projection jitter", () => {
  const active = booking("A", 18, 24, {
    [BOOKING_FIELDS.status]: "on_the_way",
    [BOOKING_FIELDS.routeDirection]: "forward",
    [BOOKING_FIELDS.operatorLat]: baseLat,
    [BOOKING_FIELDS.operatorLng]: baseLng + 17.95 * lngStep,
  });
  const samePickupCandidate = booking("B", 18, 21, {
    [BOOKING_FIELDS.status]: "pending",
  });

  const eligibility = evaluatePoolingEligibility([active], samePickupCandidate);

  assert.equal(
    eligibility.eligible,
    true,
    "A booking at the same uncompleted pickup should stay in the current sweep when projection is near the pickup"
  );
});
