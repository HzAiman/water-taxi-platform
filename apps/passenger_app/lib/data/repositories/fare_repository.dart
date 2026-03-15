import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `fares` Firestore collection.
class FareRepository {
  FareRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns the fare for the given route, or `null` if no fare is configured.
  Future<FareModel?> getFare(String origin, String destination) async {
    // Fast path: exact match with current schema.
    final snap = await _db
        .collection(FirestoreCollections.fares)
        .where(FareFields.origin, isEqualTo: origin)
        .where(FareFields.destination, isEqualTo: destination)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      return FareModel.fromMap(snap.docs.first.data());
    }

    // Fallback path: tolerate legacy/messy fare docs (trim/case differences
    // and alternative field names) so existing seeded routes keep working.
    final normalizedOrigin = _normalizeRouteValue(origin);
    final normalizedDestination = _normalizeRouteValue(destination);

    final allFares =
        await _db.collection(FirestoreCollections.fares).limit(500).get();

    for (final doc in allFares.docs) {
      final data = doc.data();
      final docOrigin = _normalizeRouteValue(
        data[FareFields.origin] ?? data['pickup'] ?? data['from'] ?? '',
      );
      final docDestination = _normalizeRouteValue(
        data[FareFields.destination] ?? data['dropoff'] ?? data['to'] ?? '',
      );

      if (docOrigin == normalizedOrigin &&
          docDestination == normalizedDestination) {
        return FareModel.fromMap({
          FareFields.origin: data[FareFields.origin] ?? data['pickup'] ?? '',
          FareFields.destination:
              data[FareFields.destination] ?? data['dropoff'] ?? '',
          FareFields.adultFare: data[FareFields.adultFare],
          FareFields.childFare: data[FareFields.childFare],
        });
      }
    }

    return null;
  }

  /// Returns `true` if a fare document exists for the given route.
  Future<bool> fareExists(String origin, String destination) async {
    final fare = await getFare(origin, destination);
    return fare != null;
  }

  String _normalizeRouteValue(Object? value) {
    return value
        .toString()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }
}
