process.env.NODE_ENV = "test";

const assert = require("node:assert/strict");
const test = require("node:test");

const { __drtStabilityTest } = require("../index.js");

const { BOOKING_FIELDS, buildPickupStopUpdatePayload } = __drtStabilityTest;

test("pickup payload promotes only bookings at current stop", () => {
  const stopState = {
    plannedStops: [{ stopId: "pickup-1", status: "completed" }],
    currentStopIndex: 1,
    currentStopId: "dropoff-1",
    poolStatus: "in_progress",
  };
  const stopIds = {
    pickupStopId: "pickup-1",
    dropoffStopId: "dropoff-1",
  };
  const fieldValue = {
    serverTimestamp() {
      return "__SERVER_TIMESTAMP__";
    },
  };

  const atStop = buildPickupStopUpdatePayload({
    item: { id: "booking-at-stop" },
    stopBookingIds: new Set(["booking-at-stop"]),
    stopState,
    stopIds,
    fieldValue,
  }).payload;
  const futureStop = buildPickupStopUpdatePayload({
    item: { id: "booking-future-stop" },
    stopBookingIds: new Set(["booking-at-stop"]),
    stopState,
    stopIds,
    fieldValue,
  }).payload;

  assert.equal(atStop[BOOKING_FIELDS.status], "on_the_way");
  assert.equal(atStop[BOOKING_FIELDS.poolPhase], "onboard");
  assert.equal(atStop[BOOKING_FIELDS.onboard], true);
  assert.equal(futureStop[BOOKING_FIELDS.status], undefined);
  assert.equal(futureStop[BOOKING_FIELDS.poolPhase], undefined);
  assert.equal(futureStop[BOOKING_FIELDS.onboard], undefined);
  assert.equal(futureStop[BOOKING_FIELDS.currentStopId], "dropoff-1");
});
