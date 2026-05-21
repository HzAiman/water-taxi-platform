process.env.NODE_ENV = "test";

const assert = require("node:assert/strict");
const test = require("node:test");

const { __pendingNoOperatorTest } = require("../index.js");

const {
  BOOKING_FIELDS,
  PENDING_NO_OPERATOR_POLICY,
  rejectStalePendingBookingsWithoutOnlineOperators,
} = __pendingNoOperatorTest;

const NOW = new Date("2026-05-21T12:00:00.000Z");

test("rejects stale unassigned pending bookings when no operators are online", async () => {
  const oldPending = bookingDoc("old-pending", {
    [BOOKING_FIELDS.status]: "pending",
    [BOOKING_FIELDS.createdAt]: minutesAgo(6),
  });
  const firestore = new FakeFirestore({
    operator_presence: [],
    bookings: [oldPending],
  });

  const result = await rejectStalePendingBookingsWithoutOnlineOperators({
    firestore,
    now: NOW,
    log: silentLog(),
    fieldValue: fakeFieldValue(),
  });

  assert.equal(result.rejected, 1);
  assert.equal(result.skipped, 0);
  assert.equal(firestore.commits, 1);
  assert.equal(oldPending.updates.length, 1);
  assert.equal(oldPending.updates[0][BOOKING_FIELDS.status], "rejected");
  assert.equal(oldPending.historyWrites.length, 1);
  assert.deepEqual(
    pick(oldPending.historyWrites[0], ["from", "to", "changedBy", "source"]),
    {
      from: "pending",
      to: "rejected",
      changedBy: PENDING_NO_OPERATOR_POLICY.changedBy,
      source: PENDING_NO_OPERATOR_POLICY.source,
    }
  );
});

test("keeps fresh pending bookings waiting during the grace window", async () => {
  const freshPending = bookingDoc("fresh-pending", {
    [BOOKING_FIELDS.status]: "pending",
    [BOOKING_FIELDS.createdAt]: minutesAgo(4),
  });
  const firestore = new FakeFirestore({
    operator_presence: [],
    bookings: [freshPending],
  });

  const result = await rejectStalePendingBookingsWithoutOnlineOperators({
    firestore,
    now: NOW,
    log: silentLog(),
    fieldValue: fakeFieldValue(),
  });

  assert.equal(result.rejected, 0);
  assert.equal(result.scanned, 0);
  assert.equal(firestore.commits, 0);
  assert.equal(freshPending.updates.length, 0);
});

test("does nothing while any operator is online", async () => {
  const oldPending = bookingDoc("old-pending", {
    [BOOKING_FIELDS.status]: "pending",
    [BOOKING_FIELDS.createdAt]: minutesAgo(10),
  });
  const firestore = new FakeFirestore({
    operator_presence: [presenceDoc("operator-1", true)],
    bookings: [oldPending],
  });

  const result = await rejectStalePendingBookingsWithoutOnlineOperators({
    firestore,
    now: NOW,
    log: silentLog(),
    fieldValue: fakeFieldValue(),
  });

  assert.equal(result.onlineOperatorsPresent, true);
  assert.equal(result.rejected, 0);
  assert.equal(firestore.commits, 0);
  assert.equal(oldPending.updates.length, 0);
});

test("skips stale pending bookings that are already assigned", async () => {
  const assignedPending = bookingDoc("assigned-pending", {
    [BOOKING_FIELDS.status]: "pending",
    [BOOKING_FIELDS.operatorUid]: "operator-1",
    [BOOKING_FIELDS.createdAt]: minutesAgo(10),
  });
  const firestore = new FakeFirestore({
    operator_presence: [],
    bookings: [assignedPending],
  });

  const result = await rejectStalePendingBookingsWithoutOnlineOperators({
    firestore,
    now: NOW,
    log: silentLog(),
    fieldValue: fakeFieldValue(),
  });

  assert.equal(result.rejected, 0);
  assert.equal(result.skipped, 1);
  assert.equal(firestore.commits, 0);
  assert.equal(assignedPending.updates.length, 0);
});

test("ignores non-pending bookings", async () => {
  const accepted = bookingDoc("accepted", {
    [BOOKING_FIELDS.status]: "accepted",
    [BOOKING_FIELDS.createdAt]: minutesAgo(10),
  });
  const firestore = new FakeFirestore({
    operator_presence: [],
    bookings: [accepted],
  });

  const result = await rejectStalePendingBookingsWithoutOnlineOperators({
    firestore,
    now: NOW,
    log: silentLog(),
    fieldValue: fakeFieldValue(),
  });

  assert.equal(result.rejected, 0);
  assert.equal(result.scanned, 0);
  assert.equal(firestore.commits, 0);
  assert.equal(accepted.updates.length, 0);
});

function minutesAgo(minutes) {
  return new Date(NOW.getTime() - minutes * 60 * 1000);
}

function silentLog() {
  return {
    info() {},
    warn() {},
    error() {},
  };
}

function fakeFieldValue() {
  return {
    serverTimestamp() {
      return "__SERVER_TIMESTAMP__";
    },
  };
}

function pick(source, keys) {
  return Object.fromEntries(keys.map((key) => [key, source[key]]));
}

function presenceDoc(id, isOnline) {
  return fakeDoc(id, { isOnline });
}

function bookingDoc(id, data) {
  return fakeDoc(id, data);
}

function fakeDoc(id, data) {
  const doc = {
    id,
    _data: data,
    updates: [],
    historyWrites: [],
    data() {
      return this._data;
    },
  };
  doc.ref = {
    id,
    collection(name) {
      assert.equal(name, "statusHistory");
      return {
        doc() {
          return {
            set(data) {
              doc.historyWrites.push(data);
            },
          };
        },
      };
    },
  };
  return doc;
}

class FakeFirestore {
  constructor(collections) {
    this.collections = collections;
    this.commits = 0;
  }

  collection(name) {
    return new FakeQuery(this.collections[name] || []);
  }

  batch() {
    const firestore = this;
    return {
      update(ref, update) {
        refDoc(ref, firestore.collections.bookings).updates.push(update);
      },
      set(ref, data) {
        ref.set(data);
      },
      async commit() {
        firestore.commits += 1;
      },
    };
  }
}

class FakeQuery {
  constructor(docs) {
    this.docs = docs;
    this.filters = [];
    this.max = null;
  }

  where(field, op, value) {
    this.filters.push({ field, op, value });
    return this;
  }

  limit(value) {
    this.max = value;
    return this;
  }

  async get() {
    let docs = this.docs.filter((doc) => {
      const data = doc.data();
      return this.filters.every(({ field, op, value }) => {
        const current = data[field];
        if (op === "==") return current === value;
        if (op === "<=") {
          return current instanceof Date && current.getTime() <= value.getTime();
        }
        throw new Error(`Unsupported fake query op: ${op}`);
      });
    });
    if (this.max != null) {
      docs = docs.slice(0, this.max);
    }
    return {
      docs,
      size: docs.length,
      empty: docs.length === 0,
    };
  }
}

function refDoc(ref, docs) {
  const found = docs.find((doc) => doc.ref === ref);
  assert.ok(found, "fake ref should belong to a seeded booking doc");
  return found;
}
