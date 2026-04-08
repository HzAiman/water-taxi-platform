import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `jetties` Firestore collection.
class JettyRepository {
  JettyRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns all jetties sorted by canonical jetty doc ID.
  Future<List<JettyModel>> getAllJetties() async {
    final snap = await _db
        .collection(FirestoreCollections.jetties)
        .orderBy(FieldPath.documentId)
        .get();

    final jetties = snap.docs
      .map((d) => JettyModel.fromMap(d.data(), snapshotId: d.id))
        .toList()
      ..sort((a, b) {
        final ai = double.tryParse(a.jettyId) ?? double.infinity;
        final bi = double.tryParse(b.jettyId) ?? double.infinity;
        if (ai != bi) return ai.compareTo(bi);
        return a.name.compareTo(b.name);
      });

    return jetties;
  }

  /// Returns the jetty with the given [name], or `null` if not found.
  Future<JettyModel?> getJettyByName(String name) async {
    final snap = await _db
        .collection(FirestoreCollections.jetties)
        .where(JettyFields.name, isEqualTo: name)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return JettyModel.fromMap(snap.docs.first.data(), snapshotId: snap.docs.first.id);
  }
}
