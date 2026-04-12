#!/usr/bin/env node

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

/**
 * Quick health check for Water Taxi Firestore schema.
 * 
 * Usage:
 *   node ./scripts/firestore_health_check.js
 *
 * Checks:
 * - Jetties collection exists and has required fields
 * - Fares collection has canonical jetty references
 * - Polylines collection has valid geometry
 * - Supporting collections are accessible
 */

async function healthCheck() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "melaka-water-taxi";
  
  const app = initializeApp({
    credential: applicationDefault(),
    projectId,
  });
  const db = getFirestore(app);

  console.log(`\n🏥 Firestore Health Check - ${projectId}\n`);

  const health = {
    timestamp: new Date().toISOString(),
    projectId,
    status: "healthy",
    checks: [],
  };

  // Check: Jetties
  try {
    const count = await db.collection("jetties").count().get();
    const sample = await db.collection("jetties").limit(1).get();
    
    if (count.data().count > 0 && !sample.empty) {
      const doc = sample.docs[0];
      const data = doc.data();
      const hasRequired = ['name', 'lat', 'lng'].every(f => f in data);
      
      health.checks.push({
        collection: "jetties",
        status: hasRequired ? "✅ healthy" : "⚠️ missing fields",
        records: count.data().count,
        sample_id: doc.id,
      });
      
      console.log(`✅ jetties (${count.data().count} docs) - has required fields`);
    } else {
      health.checks.push({
        collection: "jetties",
        status: "⚠️ empty",
        records: 0,
      });
      console.log(`⚠️ jetties - EMPTY (will be created on first save)`);
    }
  } catch (e) {
    health.status = "unhealthy";
    health.checks.push({
      collection: "jetties",
      status: `❌ error: ${e.message}`,
    });
    console.log(`❌ jetties - ERROR: ${e.message}`);
  }

  // Check: Fares
  try {
    const count = await db.collection("fares").count().get();
    const sample = await db.collection("fares").limit(1).get();
    
    if (count.data().count > 0) {
      const doc = sample.docs[0];
      const data = doc.data();
      const hasCanonical = ['originJettyId', 'destinationJettyId'].every(f => f in data);
      
      health.checks.push({
        collection: "fares",
        status: hasCanonical ? "✅ healthy" : "⚠️ missing jetty IDs",
        records: count.data().count,
        sample_id: doc.id,
      });
      
      console.log(`✅ fares (${count.data().count} docs) - has canonical references`);
    } else {
      health.checks.push({
        collection: "fares",
        status: "⚠️ empty",
        records: 0,
      });
      console.log(`⚠️ fares - EMPTY (will be created on first save)`);
    }
  } catch (e) {
    health.status = "unhealthy";
    health.checks.push({
      collection: "fares",
      status: `❌ error: ${e.message}`,
    });
    console.log(`❌ fares - ERROR: ${e.message}`);
  }

  // Check: Polylines
  try {
    const count = await db.collection("polylines").count().get();
    const sample = await db.collection("polylines").limit(1).get();
    
    if (count.data().count > 0) {
      const doc = sample.docs[0];
      const data = doc.data();
      const hasPath = 'path' in data && Array.isArray(data.path);
      
      health.checks.push({
        collection: "polylines",
        status: hasPath ? "✅ healthy" : "⚠️ invalid path",
        records: count.data().count,
        sample_id: doc.id,
        path_length: hasPath ? data.path.length : 0,
      });
      
      console.log(`✅ polylines (${count.data().count} docs) - path geometry valid`);
    } else {
      health.checks.push({
        collection: "polylines",
        status: "⚠️ empty",
        records: 0,
      });
      console.log(`⚠️ polylines - EMPTY (fallback routing will be used)`);
    }
  } catch (e) {
    health.status = "unhealthy";
    health.checks.push({
      collection: "polylines",
      status: `❌ error: ${e.message}`,
    });
    console.log(`❌ polylines - ERROR: ${e.message}`);
  }

  // Check: Supporting collections (informational)
  const supporting = ["bookings", "users", "operators", "bookings_archive", "order_number_index"];
  console.log("\nℹ️  Supporting Collections (auto-create on first write):");
  
  for (const collName of supporting) {
    try {
      const count = await db.collection(collName).count().get();
      const status = count.data().count > 0 ? `✅ ${count.data().count} docs` : "⚠️ empty (not yet used)";
      console.log(`   ${collName}: ${status}`);
      
      health.checks.push({
        collection: collName,
        status: count.data().count > 0 ? "created" : "pending",
        records: count.data().count,
      });
    } catch (e) {
      console.log(`   ${collName}: ℹ️ not yet accessible`);
      health.checks.push({
        collection: collName,
        status: "not accessible",
        records: 0,
      });
    }
  }

  console.log(`\n${health.status === "healthy" ? "✅ Health Status: HEALTHY" : "⚠️ Health Status: UNHEALTHY"}\n`);
  
  // Output health as JSON for automation
  console.log(JSON.stringify(health, null, 2));
}

healthCheck().catch(err => {
  console.error("\n❌ Health check failed:", err?.message || err);
  process.exitCode = 1;
});
