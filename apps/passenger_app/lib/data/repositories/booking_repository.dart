import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Parameters required to create a new booking document.
class BookingCreationParams {
  const BookingCreationParams({
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.origin,
    required this.destination,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.adultCount,
    required this.childCount,
    required this.adultFare,
    required this.childFare,
    required this.paymentMethod,
    this.orderNumber,
    this.transactionId,
  });

  final String userId;
  final String userName;
  final String userPhone;
  final String origin;
  final String destination;
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final int adultCount;
  final int childCount;
  final double adultFare;
  final double childFare;
  final String paymentMethod;
  final String? orderNumber;
  final String? transactionId;
}

/// Data-access layer for the `bookings` Firestore collection (passenger side).
class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ── Write ────────────────────────────────────────────────────────────────

  /// Creates a new booking document and returns the generated booking ID.
  Future<String> createBooking(BookingCreationParams p) async {
    final ref = _db.collection(FirestoreCollections.bookings).doc();
    final id = ref.id;
    final passengerCount = p.adultCount + p.childCount;
    final adultSubtotal = p.adultFare * p.adultCount;
    final childSubtotal = p.childFare * p.childCount;
    final total = adultSubtotal + childSubtotal;
    final routePolyline = await _buildRoutePolylineForBooking(
      originLat: p.originLat,
      originLng: p.originLng,
      destinationLat: p.destinationLat,
      destinationLng: p.destinationLng,
    );

    await ref.set({
      BookingFields.bookingId: id,
      BookingFields.userId: p.userId,
      BookingFields.userName: p.userName,
      BookingFields.userPhone: p.userPhone,
      BookingFields.origin: p.origin,
      BookingFields.destination: p.destination,
      BookingFields.originCoords: GeoPoint(p.originLat, p.originLng),
      BookingFields.destinationCoords: GeoPoint(
        p.destinationLat,
        p.destinationLng,
      ),
      BookingFields.adultCount: p.adultCount,
      BookingFields.childCount: p.childCount,
      BookingFields.passengerCount: passengerCount,
      BookingFields.adultFare: p.adultFare,
      BookingFields.childFare: p.childFare,
      BookingFields.adultSubtotal: adultSubtotal,
      BookingFields.childSubtotal: childSubtotal,
      BookingFields.fare: total,
      BookingFields.totalFare: total,
      BookingFields.paymentMethod: p.paymentMethod,
      // Payment is authorized/held first and captured after trip completion.
      BookingFields.paymentStatus: 'authorized',
      if (p.orderNumber != null) BookingFields.orderNumber: p.orderNumber,
      if (p.transactionId != null) BookingFields.transactionId: p.transactionId,
      BookingFields.status: BookingStatus.pending.firestoreValue,
      BookingFields.operatorUid: null,
      BookingFields.operatorId: null,
      if (routePolyline != null) BookingFields.routePolyline: routePolyline,
      BookingFields.createdAt: FieldValue.serverTimestamp(),
      BookingFields.updatedAt: FieldValue.serverTimestamp(),
    });

    return id;
  }

  /// Cancels a booking owned by the current passenger.
  Future<void> cancelBooking(String bookingId) async {
    await _db.collection(FirestoreCollections.bookings).doc(bookingId).update({
      BookingFields.status: BookingStatus.cancelled.firestoreValue,
      BookingFields.updatedAt: FieldValue.serverTimestamp(),
      BookingFields.cancelledAt: FieldValue.serverTimestamp(),
    });
  }

  // ── Read / Stream ────────────────────────────────────────────────────────

  /// Streams a single booking document in real-time. Emits `null` if the
  /// document does not exist.
  Stream<BookingModel?> streamBooking(String bookingId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .doc(bookingId)
        .snapshots()
        .map((snap) {
          if (!snap.exists || snap.data() == null) return null;
          return _fromDoc(snap.id, snap.data()!);
        });
  }

  /// Streams the user's currently active booking (pending / accepted /
  /// on_the_way), or `null` if there is none.
  Stream<BookingModel?> streamUserActiveBooking(String userId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.userId, isEqualTo: userId)
        .snapshots()
        .map((snap) {
          final activeDocs = snap.docs.where((d) {
            final status = BookingStatus.fromString(
              (d.data()[BookingFields.status] ?? '').toString(),
            );
            return status.isActive;
          }).toList();

          if (activeDocs.isEmpty) return null;
          return _fromDoc(activeDocs.first.id, activeDocs.first.data());
        });
  }

  /// Streams the complete booking history for a user, sorted newest first.
  Stream<List<BookingModel>> streamUserBookingHistory(String userId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.userId, isEqualTo: userId)
        .snapshots()
        .map((snap) {
          final bookings =
              snap.docs.map((d) => _fromDoc(d.id, d.data())).toList()
                ..sort((a, b) {
                  final at = a.createdAt;
                  final bt = b.createdAt;
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return bt.compareTo(at);
                });
          return bookings;
        });
  }

  /// Returns `true` if the user has at least one active booking.
  Future<bool> hasActiveBooking(String userId) async {
    final snap = await _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.userId, isEqualTo: userId)
        .get();

    return snap.docs.any((d) {
      final status = BookingStatus.fromString(
        (d.data()[BookingFields.status] ?? '').toString(),
      );
      return status.isActive;
    });
  }

  /// Returns `true` when at least one operator is currently online.
  Future<bool> hasOnlineOperators() async {
    final snap = await _db
        .collection(FirestoreCollections.operatorPresence)
        .where(OperatorPresenceFields.isOnline, isEqualTo: true)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<List<Map<String, double>>?> _buildRoutePolylineForBooking({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final origin = _LatLngPoint(lat: originLat, lng: originLng);
    final destination = _LatLngPoint(lat: destinationLat, lng: destinationLng);

    try {
      final snap = await _db.collection(FirestoreCollections.polylines).get();
      _PolylineMatch? bestMatch;

      for (final doc in snap.docs) {
        final data = doc.data();
        final raw =
            data['path'] ?? data['polyline'] ?? data[BookingFields.routePolyline];
        final parsed = _normaliseRoutePolyline(raw);
        if (parsed == null || parsed.length < 2) {
          continue;
        }

        final points = parsed
            .map((p) => _LatLngPoint(lat: p['lat']!, lng: p['lng']!))
            .toList();
        final startSnap = _snapPointToPolyline(origin, points);
        final endSnap = _snapPointToPolyline(destination, points);
        final score = startSnap.distanceSquared + endSnap.distanceSquared;

        if (bestMatch == null || score < bestMatch.score) {
          bestMatch = _PolylineMatch(
            polyline: points,
            start: startSnap,
            end: endSnap,
            score: score,
          );
        }
      }

      if (bestMatch != null) {
        final segment = _extractSegment(bestMatch);
        if (segment.length >= 2) {
          return segment
              .map((p) => <String, double>{'lat': p.lat, 'lng': p.lng})
              .toList();
        }
      }
    } catch (_) {
      // Fall back to direct origin→destination line when route docs are missing.
    }

    return [
      <String, double>{'lat': origin.lat, 'lng': origin.lng},
      <String, double>{'lat': destination.lat, 'lng': destination.lng},
    ];
  }

  static _SnapResult _snapPointToPolyline(
    _LatLngPoint point,
    List<_LatLngPoint> polyline,
  ) {
    var best = _projectPointOntoSegment(point, polyline[0], polyline[1], 0);
    for (var i = 1; i < polyline.length - 1; i++) {
      final candidate = _projectPointOntoSegment(
        point,
        polyline[i],
        polyline[i + 1],
        i,
      );
      if (candidate.distanceSquared < best.distanceSquared) {
        best = candidate;
      }
    }
    return best;
  }

  static _SnapResult _projectPointOntoSegment(
    _LatLngPoint point,
    _LatLngPoint a,
    _LatLngPoint b,
    int segmentIndex,
  ) {
    final abLat = b.lat - a.lat;
    final abLng = b.lng - a.lng;
    final apLat = point.lat - a.lat;
    final apLng = point.lng - a.lng;
    final abLenSquared = abLat * abLat + abLng * abLng;

    double t;
    if (abLenSquared <= 0) {
      t = 0;
    } else {
      t = (apLat * abLat + apLng * abLng) / abLenSquared;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
    }

    final projected = _LatLngPoint(
      lat: a.lat + (abLat * t),
      lng: a.lng + (abLng * t),
    );

    final dx = projected.lat - point.lat;
    final dy = projected.lng - point.lng;
    return _SnapResult(
      point: projected,
      segmentIndex: segmentIndex,
      distanceSquared: (dx * dx) + (dy * dy),
    );
  }

  static List<_LatLngPoint> _extractSegment(_PolylineMatch match) {
    final start = match.start;
    final end = match.end;
    final points = match.polyline;

    final segment = <_LatLngPoint>[start.point];

    if (start.segmentIndex <= end.segmentIndex) {
      for (var i = start.segmentIndex + 1; i <= end.segmentIndex; i++) {
        _addIfDistinct(segment, points[i]);
      }
    } else {
      for (var i = start.segmentIndex; i >= end.segmentIndex + 1; i--) {
        _addIfDistinct(segment, points[i]);
      }
    }

    _addIfDistinct(segment, end.point);
    return segment;
  }

  static void _addIfDistinct(List<_LatLngPoint> points, _LatLngPoint next) {
    if (points.isEmpty) {
      points.add(next);
      return;
    }
    final last = points.last;
    if ((last.lat - next.lat).abs() < 1e-9 &&
        (last.lng - next.lng).abs() < 1e-9) {
      return;
    }
    points.add(next);
  }

  static BookingModel _fromDoc(String id, Map<String, dynamic> data) {
    final origin = data[BookingFields.originCoords] as GeoPoint?;
    final dest = data[BookingFields.destinationCoords] as GeoPoint?;
    final routePolyline = _normaliseRoutePolyline(
      _extractRoutePolylineRaw(data),
    );
    final createdAt = (data[BookingFields.createdAt] as Timestamp?)?.toDate();
    final updatedAt = (data[BookingFields.updatedAt] as Timestamp?)?.toDate();
    final cancelledAt = (data[BookingFields.cancelledAt] as Timestamp?)
        ?.toDate();

    // Ensure bookingId is present (fallback to document ID)
    data = {
      ...data,
      if (data[BookingFields.bookingId] == null) BookingFields.bookingId: id,
      if (routePolyline != null) BookingFields.routePolyline: routePolyline,
    };

    return BookingModel.fromMap(
      data,
      originLat: origin?.latitude ?? 0.0,
      originLng: origin?.longitude ?? 0.0,
      destinationLat: dest?.latitude ?? 0.0,
      destinationLng: dest?.longitude ?? 0.0,
      createdAt: createdAt,
      updatedAt: updatedAt,
      cancelledAt: cancelledAt,
    );
  }

  static dynamic _extractRoutePolylineRaw(Map<String, dynamic> data) {
    return data[BookingFields.routePolyline] ??
        data['routeCoordinates'] ??
        data['polylineCoordinates'] ??
        data['routePoints'];
  }

  static List<Map<String, double>>? _normaliseRoutePolyline(dynamic raw) {
    if (raw is! Iterable) return null;

    final points = <Map<String, double>>[];
    for (final entry in raw) {
      final point = _toRoutePointMap(entry);
      if (point != null) {
        points.add(point);
      }
    }

    if (points.isEmpty) return null;
    return points;
  }

  static Map<String, double>? _toRoutePointMap(dynamic entry) {
    if (entry is GeoPoint) {
      return {'lat': entry.latitude, 'lng': entry.longitude};
    }

    if (entry is Map) {
      final lat = _asDouble(entry['lat'] ?? entry['latitude']);
      final lng = _asDouble(entry['lng'] ?? entry['longitude'] ?? entry['lon']);
      if (lat != null && lng != null) {
        return {'lat': lat, 'lng': lng};
      }
      return null;
    }

    if (entry is List && entry.length >= 2) {
      final lat = _asDouble(entry[0]);
      final lng = _asDouble(entry[1]);
      if (lat != null && lng != null) {
        return {'lat': lat, 'lng': lng};
      }
      return null;
    }

    if (entry is String) {
      final parts = entry.split(',');
      if (parts.length >= 2) {
        final lat = _asDouble(parts[0].trim());
        final lng = _asDouble(parts[1].trim());
        if (lat != null && lng != null) {
          return {'lat': lat, 'lng': lng};
        }
      }
      return null;
    }

    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

}

class _LatLngPoint {
  const _LatLngPoint({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

class _SnapResult {
  const _SnapResult({
    required this.point,
    required this.segmentIndex,
    required this.distanceSquared,
  });

  final _LatLngPoint point;
  final int segmentIndex;
  final double distanceSquared;
}

class _PolylineMatch {
  const _PolylineMatch({
    required this.polyline,
    required this.start,
    required this.end,
    required this.score,
  });

  final List<_LatLngPoint> polyline;
  final _SnapResult start;
  final _SnapResult end;
  final double score;
}
