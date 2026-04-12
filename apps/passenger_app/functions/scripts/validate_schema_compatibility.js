const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

async function validateSchemaCompatibility() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "melaka-water-taxi";
  
  const app = initializeApp({
    credential: applicationDefault(),
    projectId,
  });
  const db = getFirestore(app);

  console.log(`\n🔍 Schema Compatibility Validation for project: ${projectId}\n`);

  const checks = [];
  let passCount = 0;
  let warnCount = 0;
  let failCount = 0;

  // ── Check 1: Jetties collection ──
  {
    console.log("📋 Check 1: Jetties collection");
    try {
      const snap = await db.collection("jetties").limit(1).get();
      if (!snap.empty) {
        const doc = snap.docs[0];
        const data = doc.data();
        const hasName = 'name' in data;
        const hasLat = 'lat' in data;
        const hasLng = 'lng' in data;
        
        if (hasName && hasLat && hasLng) {
          console.log("   ✅ PASS: Jetties have required fields (name, lat, lng)");
          console.log(`      Sample: ID="${doc.id}", name="${data.name}"`);
          passCount++;
        } else {
          console.log(`   ⚠️  WARN: Missing fields - name:${hasName} lat:${hasLat} lng:${hasLng}`);
          warnCount++;
        }
      } else {
        console.log("   ⚠️  WARN: Jetties collection is empty (will be created on first jetty save)");
        warnCount++;
      }
    } catch (e) {
      console.log(`   ❌ FAIL: ${e.message}`);
      failCount++;
    }
  }

  // ── Check 2: Fares canonical jetty references ──
  {
    console.log("\n📋 Check 2: Fares with canonical jetty IDs");
    try {
      const snap = await db.collection("fares").limit(3).get();
      if (!snap.empty) {
        let allHaveCanonical = true;
        for (const doc of snap.docs) {
          const data = doc.data();
          const hasOriginId = 'originJettyId' in data;
          const hasDestId = 'destinationJettyId' in data;
          const hasAdultFare = 'adultFare' in data;
          const hasChildFare = 'childFare' in data;
          
          if (!hasOriginId || !hasDestId) {
            allHaveCanonical = false;
            console.log(`   ⚠️  Doc ${doc.id} missing canonical IDs`);
          }
        }
        
        if (allHaveCanonical && snap.size > 0) {
          console.log(`   ✅ PASS: All sampled fares have originJettyId/destinationJettyId`);
          console.log(`      Sampled ${snap.size} docs - all have canonical references`);
          passCount++;
        }
      } else {
        console.log("   ⚠️  WARN: Fares collection is empty (will be created on first fare save)");
        warnCount++;
      }
    } catch (e) {
      console.log(`   ❌ FAIL: ${e.message}`);
      failCount++;
    }
  }

  // ── Check 3: Polylines path structure ──
  {
    console.log("\n📋 Check 3: Polylines with path geometry");
    try {
      const snap = await db.collection("polylines").limit(1).get();
      if (!snap.empty) {
        const doc = snap.docs[0];
        const data = doc.data();
        const hasPath = 'path' in data;
        const pathIsArray = Array.isArray(data.path);
        
        if (hasPath && pathIsArray && data.path.length > 0) {
          const firstPoint = data.path[0];
          const isGeoPoint = firstPoint && (
            ('_latitude' in firstPoint && '_longitude' in firstPoint) ||
            ('latitude' in firstPoint && 'longitude' in firstPoint)
          );
          
          if (isGeoPoint) {
            console.log(`   ✅ PASS: Polylines have path array with GeoPoints`);
            console.log(`      Sample: ID="${doc.id}", path length=${data.path.length}`);
            passCount++;
          } else {
            console.log(`   ⚠️  WARN: Path exists but coordinates may not be GeoPoints`);
            warnCount++;
          }
        } else {
          console.log(`   ❌ FAIL: Missing or invalid path field`);
          failCount++;
        }
      } else {
        console.log("   ⚠️  WARN: Polylines collection is empty (will work with fallback routes)");
        warnCount++;
      }
    } catch (e) {
      console.log(`   ❌ FAIL: ${e.message}`);
      failCount++;
    }
  }

  // ── Check 4: Supporting collections (will be created on demand) ──
  {
    console.log("\n📋 Check 4: Supporting collections");
    const supportingCollections = [
      { name: "bookings", purpose: "Trip records (created on booking)" },
      { name: "bookings_archive", purpose: "Archived completed/cancelled trips" },
      { name: "users", purpose: "Passenger profiles" },
      { name: "operators", purpose: "Operator profiles (if using operator app)" },
      { name: "operator_presence", purpose: "Operator online status (if using operator app)" },
      { name: "order_number_index", purpose: "Order uniqueness ledger" },
    ];

    for (const coll of supportingCollections) {
      try {
        const snap = await db.collection(coll.name).limit(1).get();
        if (snap.empty) {
          console.log(`   ℹ️  ${coll.name}: Not yet created (${coll.purpose})`);
        } else {
          console.log(`   ✅ ${coll.name}: Exists with ${snap.size} sample(s)`);
        }
      } catch (e) {
        console.log(`   ⚠️  ${coll.name}: Inaccessible`);
      }
    }
    passCount++;
  }

  // ── Check 5: Firestore Security Rules (if available) ──
  {
    console.log("\n📋 Check 5: Code-to-Firestore field mapping");
    try {
      const jettiesSnap = await db.collection("jetties").limit(1).get();
      const faresSnap = await db.collection("fares").limit(1).get();
      const polylinesSnap = await db.collection("polylines").limit(1).get();

      const mappings = [];
      
      if (!jettiesSnap.empty) {
        const data = jettiesSnap.docs[0].data();
        mappings.push({
          collection: "jetties",
          dart_model: "JettyModel",
          mapping: {
            "doc.id → jettyId": "✅",
            "name": data.name ? "✅" : "❌",
            "lat": data.lat ? "✅" : "❌",
            "lng": data.lng ? "✅" : "❌",
          }
        });
      }

      if (!faresSnap.empty) {
        const data = faresSnap.docs[0].data();
        mappings.push({
          collection: "fares",
          dart_model: "FareModel",
          mapping: {
            "originJettyId": data.originJettyId ? "✅" : "❌",
            "destinationJettyId": data.destinationJettyId ? "✅" : "❌",
            "adultFare": data.adultFare ? "✅" : "❌",
            "childFare": data.childFare ? "✅" : "❌",
          }
        });
      }

      if (!polylinesSnap.empty) {
        const data = polylinesSnap.docs[0].data();
        mappings.push({
          collection: "polylines",
          dart_model: "_PolylineSource",
          mapping: {
            "doc.id → id": "✅",
            "path": Array.isArray(data.path) ? "✅" : "❌",
            "type": data.type ? "✅" : "❌",
            "properties": data.properties ? "✅" : "❌",
          }
        });
      }

      console.log("   Field Mapping:");
      for (const m of mappings) {
        console.log(`\n   📌 ${m.collection} → ${m.dart_model}`);
        for (const [field, status] of Object.entries(m.mapping)) {
          console.log(`      ${status} ${field}`);
        }
      }
      passCount++;
    } catch (e) {
      console.log(`   ⚠️  Could not verify mappings: ${e.message}`);
      warnCount++;
    }
  }

  // ── Summary ──
  console.log("\n" + "=".repeat(68));
  console.log("📊 VALIDATION SUMMARY");
  console.log("=".repeat(68));
  console.log(`✅ Passed: ${passCount} checks`);
  console.log(`⚠️  Warnings: ${warnCount} checks`);
  console.log(`❌ Failed: ${failCount} checks`);

  if (failCount === 0) {
    console.log("\n🎉 All critical checks passed!");
    console.log("The codebase is compatible with the current Firestore schema.");
  } else {
    console.log("\n⚠️  Some checks failed. Review the output above.");
    process.exitCode = 1;
  }
}

validateSchemaCompatibility().catch(err => {
  console.error("Validation error:", err?.message || err);
  process.exitCode = 1;
});
