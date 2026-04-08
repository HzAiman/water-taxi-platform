import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `fares` Firestore collection.
class FareRepository {
  FareRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns the fare for the given route, or `null` if no fare is configured.
  Future<FareModel?> getFare(
    String origin,
    String destination, {
    required String originJettyId,
    required String destinationJettyId,
  }) async {
    final byJettyId = await _db
        .collection(FirestoreCollections.fares)
        .where(FareFields.originJettyId, isEqualTo: originJettyId)
        .where(FareFields.destinationJettyId, isEqualTo: destinationJettyId)
        .limit(1)
        .get();

    if (byJettyId.docs.isEmpty) {
      return null;
    }

    return FareModel.fromMap(
      byJettyId.docs.first.data(),
      snapshotId: byJettyId.docs.first.id,
    );
  }

  /// Returns `true` if a fare document exists for the given route.
  Future<bool> fareExists(
    String origin,
    String destination, {
    required String originJettyId,
    required String destinationJettyId,
  }) async {
    final fare = await getFare(
      origin,
      destination,
      originJettyId: originJettyId,
      destinationJettyId: destinationJettyId,
    );
    return fare != null;
  }

  
}
