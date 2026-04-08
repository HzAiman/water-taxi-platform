/// Immutable data class representing a `fares/{id}` Firestore document.
class FareModel {
  const FareModel({
    this.snapshotId,
    required this.origin,
    required this.destination,
    this.originJettyId,
    this.destinationJettyId,
    required this.adultFare,
    required this.childFare,
  });

  final String? snapshotId;
  final String origin;
  final String destination;
  final String? originJettyId;
  final String? destinationJettyId;
  final double adultFare;
  final double childFare;

  factory FareModel.fromMap(Map<String, dynamic> data, {String? snapshotId}) {
    return FareModel(
      snapshotId: snapshotId,
      origin: (data['origin'] ?? '').toString(),
      destination: (data['destination'] ?? '').toString(),
      originJettyId: _toNullableString(data['originJettyId']),
      destinationJettyId: _toNullableString(data['destinationJettyId']),
      adultFare: _toDouble(data['adultFare']),
      childFare: _toDouble(data['childFare']),
    );
  }

  static String? _toNullableString(dynamic v) {
    final normalized = v?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
