const fs = require("fs");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore: getAdminFirestore } = require("firebase-admin/firestore");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  serverTimestamp,
} = require("firebase/firestore");

const PROJECT_ID = "melaka-water-taxi-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");

let testEnv;
let adminApp;

function bookingPayload({ userId, bookingId, createdAt = serverTimestamp(), updatedAt = serverTimestamp() }) {
  return {
    bookingId,
    userId,
    userName: "Passenger",
    userPhone: "0123456789",
    origin: "A",
    destination: "B",
    originJettyId: "jetty-origin-1",
    destinationJettyId: "jetty-destination-2",
    routePolylineId: "polyline-1",
    originCoords: { latitude: 2.2, longitude: 102.2 },
    destinationCoords: { latitude: 2.3, longitude: 102.3 },
    routePolyline: [
      { lat: 2.2, lng: 102.2 },
      { lat: 2.3, lng: 102.3 },
    ],
    adultCount: 1,
    childCount: 0,
    passengerCount: 1,
    totalFare: 12.5,
    fareSnapshotId: "fare-1",
    paymentMethod: "card",
    paymentStatus: "authorized",
    orderNumber: "ORD-1",
    transactionId: "pi_123",
    status: "pending",
    operatorUid: null,
    operatorId: null,
    createdAt,
    updatedAt,
  };
}

test.before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
    },
  });

  adminApp = initializeApp({ projectId: PROJECT_ID }, "rules-seed-app");
  const adminDb = getAdminFirestore(adminApp);

  await adminDb.collection("bookings_archive").doc("arch_1").set({
      bookingId: "arch_1",
      userId: "user_1",
      operatorUid: "operator_1",
      status: "completed",
      archivedAt: new Date(),
  });

  await adminDb.collection("operators").doc("operator_1").set({
      name: "Op",
      operatorId: "operator_1",
      operatorIdKey: "operator_1",
      email: "op@example.com",
  });

  await adminDb.collection("bookings").doc("booking_3").set({
      ...bookingPayload({
        userId: "user_9",
        bookingId: "booking_3",
        createdAt: new Date(),
        updatedAt: new Date(),
      }),
      status: "pending",
      operatorUid: null,
      operatorId: null,
  });
});

test.after(async () => {
  await testEnv.cleanup();
  if (adminApp) {
    await deleteApp(adminApp);
  }
});

test("passenger can create own pending authorized booking", async () => {
  const ctx = testEnv.authenticatedContext("user_1");
  const db = ctx.firestore();
  const bookingRef = doc(db, "bookings", "booking_1");

  await assertSucceeds(
    setDoc(
      bookingRef,
      bookingPayload({
        userId: "user_1",
        bookingId: "booking_1",
      })
    )
  );
});

test("passenger cannot create booking for another user", async () => {
  const ctx = testEnv.authenticatedContext("user_1");
  const db = ctx.firestore();
  const bookingRef = doc(db, "bookings", "booking_2");

  await assertFails(
    setDoc(
      bookingRef,
      bookingPayload({
        userId: "user_2",
        bookingId: "booking_2",
      })
    )
  );
});

test("bookings_archive is read-only and owner-readable", async () => {
  const ownerCtx = testEnv.authenticatedContext("user_1").firestore();
  const otherCtx = testEnv.authenticatedContext("user_2").firestore();

  await assertSucceeds(getDoc(doc(ownerCtx, "bookings_archive", "arch_1")));
  await assertFails(getDoc(doc(otherCtx, "bookings_archive", "arch_1")));
  await assertFails(
    updateDoc(doc(ownerCtx, "bookings_archive", "arch_1"), {
      status: "cancelled",
    })
  );
});

test("operator can read pending bookings", async () => {
  const operatorDb = testEnv.authenticatedContext("operator_1").firestore();
  const pendingRef = doc(operatorDb, "bookings", "booking_3");
  const snap = await assertSucceeds(getDoc(pendingRef));
  assert.equal(snap.exists(), true);
});
