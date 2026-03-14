/// Immutable data class representing a `fares/{id}` Firestore document.
class FareModel {
  const FareModel({
    required this.origin,
    required this.destination,
    required this.adultFare,
    required this.childFare,
  });

  final String origin;
  final String destination;
  final double adultFare;
  final double childFare;

  factory FareModel.fromMap(Map<String, dynamic> data) {
    return FareModel(
      origin: (data['origin'] ?? '').toString(),
      destination: (data['destination'] ?? '').toString(),
      adultFare: _toDouble(data['adultFare']),
      childFare: _toDouble(data['childFare']),
    );
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
