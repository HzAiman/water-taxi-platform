const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldPath, FieldValue } = require("firebase-admin/firestore");

function parseArgs(argv) {
  const parsed = {
    dryRun: true,
    dropMirror: false,
    pageSize: 200,
    projectId: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "melaka-water-taxi",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;

    const separatorIndex = token.indexOf("=");
    const hasInlineValue = separatorIndex > -1;
    const key = hasInlineValue ? token.slice(2, separatorIndex) : token.slice(2);
    let value = hasInlineValue ? token.slice(separatorIndex + 1) : undefined;

    if (value === undefined && argv[i + 1] && !argv[i + 1].startsWith("--")) {
      value = argv[i + 1];
      i += 1;
    }

    if (key === "dry-run") {
      parsed.dryRun = String(value).toLowerCase() !== "false";
    } else if (key === "drop-mirror") {
      parsed.dropMirror = String(value).toLowerCase() === "true";
    } else if (key === "page-size") {
      const asInt = Number.parseInt(String(value || ""), 10);
      if (!Number.isNaN(asInt) && asInt > 0 && asInt <= 500) {
        parsed.pageSize = asInt;
      }
    } else if (key === "project-id") {
      const normalized = String(value || "").trim();
      if (normalized) parsed.projectId = normalized;
    }
  }

  return parsed;
}

async function* scanCollection(db, collection, pageSize) {
  let cursor = null;

  while (true) {
    let query = db.collection(collection).orderBy(FieldPath.documentId()).limit(pageSize);
    if (cursor) query = query.startAfter(cursor);

    const snapshot = await query.get();
    if (snapshot.empty) return;

    for (const doc of snapshot.docs) {
      yield doc;
    }

    cursor = snapshot.docs[snapshot.docs.length - 1].id;
    if (snapshot.size < pageSize) return;
  }
}

async function run() {
  const args = parseArgs(process.argv.slice(2));

  initializeApp({
    credential: applicationDefault(),
    projectId: args.projectId,
  });

  const db = getFirestore();
  const summary = {
    projectId: args.projectId,
    dryRun: args.dryRun,
    dropMirror: args.dropMirror,
    pageSize: args.pageSize,
    scanned: 0,
    updated: 0,
    operatorUidBackfilled: 0,
    operatorIdRemoved: 0,
    changedDocs: [],
  };

  for await (const doc of scanCollection(db, "bookings", args.pageSize)) {
    summary.scanned += 1;
    const data = doc.data() || {};

    const currentUid = String(data.operatorUid || "").trim();
    const currentId = String(data.operatorId || "").trim();

    const patch = {};
    let changed = false;

    if (!currentUid && currentId) {
      patch.operatorUid = currentId;
      summary.operatorUidBackfilled += 1;
      changed = true;
    }

    if (args.dropMirror && currentId) {
      const nextUid = patch.operatorUid ? String(patch.operatorUid) : currentUid;
      if (!nextUid || nextUid === currentId) {
        patch.operatorId = FieldValue.delete();
        summary.operatorIdRemoved += 1;
        changed = true;
      }
    }

    if (!changed) {
      continue;
    }

    patch.updatedAt = new Date();
    summary.updated += 1;
    summary.changedDocs.push(doc.id);

    if (!args.dryRun) {
      await doc.ref.update(patch);
    }
  }

  console.log(JSON.stringify(summary, null, 2));
}

run().catch((error) => {
  console.error("Booking operatorUid migration failed:", error?.message || error);
  process.exitCode = 1;
});
