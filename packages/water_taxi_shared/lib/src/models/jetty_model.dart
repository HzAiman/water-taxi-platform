/// Immutable data class representing a `jetties/{id}` Firestore document.
class JettyModel {
  const JettyModel({
    required this.jettyId,
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String jettyId;
  final String name;
  final double lat;
  final double lng;

  factory JettyModel.fromMap(Map<String, dynamic> data) {
    return JettyModel(
      jettyId: (data['jettyId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      lat: _toDouble(data['lat']),
      lng: _toDouble(data['lng']),
    );
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
