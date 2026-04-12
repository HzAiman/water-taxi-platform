const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

async function introspectSchema() {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "melaka-water-taxi";
  
  const app = initializeApp({
    credential: applicationDefault(),
    projectId,
  });
  const db = getFirestore(app);

  console.log(`\n📊 Firestore Schema Introspection for project: ${projectId}\n`);

  try {
    const collections = await db.listCollections();
    const schema = {};
    const collectionNames = []

    for (const collectionRef of collections) {
      collectionNames.push(collectionRef.id);
    }

    collectionNames.sort();

    for (const collectionName of collectionNames) {
      const collectionRef = db.collection(collectionName);
      console.log(`\n📁 Collection: ${collectionName}`);
      
      const snapshot = await collectionRef.limit(5).get();
      
      if (snapshot.empty) {
        console.log(`   (empty)`);
        schema[collectionName] = { count: 0, fields: {} };
        continue;
      }

      const allFields = new Set();
      const sampleDocs = [];

      for (const doc of snapshot.docs) {
        const data = doc.data();
        sampleDocs.push({ id: doc.id, data });
        
        Object.keys(data).forEach(key => allFields.add(key));
      }

      schema[collectionName] = {
        count: snapshot.size,
        fields: Array.from(allFields).sort(),
        samples: sampleDocs.slice(0, 2),
      };

      console.log(`   Fields: ${Array.from(allFields).sort().join(", ")}`);
      console.log(`   Sample docs (first 2):`);
      for (const sample of sampleDocs.slice(0, 2)) {
        console.log(`     - ID: ${sample.id}`);
        const dataStr = JSON.stringify(sample.data, (key, value) => {
          if (value && typeof value === 'object' && '_seconds' in value) {
            return `<Timestamp: ${new Date(value._seconds * 1000).toISOString()}>`;
          }
          if (value && typeof value === 'object' && '_latitude' in value) {
            return `<GeoPoint: ${value._latitude}, ${value._longitude}>`;
          }
          return value;
        }, 2);
        console.log(`       ${dataStr.split('\n').join('\n       ')}`);
      }
    }

    console.log("\n\n📋 Schema Summary:\n");
    for (const collName of collectionNames) {
      const info = schema[collName];
      console.log(`${collName}:`);
      console.log(`  Fields: ${info.fields.join(", ") || "(none)"}`);
      console.log(`  Sample count: ${info.samples.length} docs`);
    }

  } catch (error) {
    console.error("Error introspecting schema:", error?.message || error);
    process.exitCode = 1;
  }
}

introspectSchema();
