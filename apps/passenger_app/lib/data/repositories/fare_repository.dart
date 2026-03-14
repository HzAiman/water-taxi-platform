import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `fares` Firestore collection.
class FareRepository {
  FareRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns the fare for the given route, or `null` if no fare is configured.
  Future<FareModel?> getFare(String origin, String destination) async {
    final snap = await _db
        .collection(FirestoreCollections.fares)
        .where(FareFields.origin, isEqualTo: origin)
        .where(FareFields.destination, isEqualTo: destination)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return FareModel.fromMap(snap.docs.first.data());
  }

  /// Returns `true` if a fare document exists for the given route.
  Future<bool> fareExists(String origin, String destination) async {
    final fare = await getFare(origin, destination);
    return fare != null;
  }
}
