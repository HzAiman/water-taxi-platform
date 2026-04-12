import 'dart:async';

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
    required this.originJettyId,
    required this.destinationJettyId,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.adultCount,
    required this.childCount,
    required this.totalFare,
    required this.paymentMethod,
    required this.fareSnapshotId,
    this.orderNumber,
    this.transactionId,
  });

  final String userId;
  final String userName;
  final String userPhone;
  final String origin;
  final String destination;
  final String originJettyId;
  final String destinationJettyId;
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final int adultCount;
  final int childCount;
  final double totalFare;
  final String paymentMethod;
  final String fareSnapshotId;
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
    final routeSelection = await _buildRouteSelectionForBooking(
      originJettyId: p.originJettyId,
      destinationJettyId: p.destinationJettyId,
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
      BookingFields.originJettyId: p.originJettyId,
      BookingFields.destinationJettyId: p.destinationJettyId,
      BookingFields.originCoords: GeoPoint(p.originLat, p.originLng),
      BookingFields.destinationCoords: GeoPoint(
        p.destinationLat,
        p.destinationLng,
      ),
      BookingFields.adultCount: p.adultCount,
      BookingFields.childCount: p.childCount,
      BookingFields.passengerCount: passengerCount,
      BookingFields.totalFare: p.totalFare,
      BookingFields.fareSnapshotId: p.fareSnapshotId,
      BookingFields.paymentMethod: p.paymentMethod,
      // Payment is authorized/held first and captured after trip completion.
      BookingFields.paymentStatus: 'authorized',
      if (p.orderNumber != null) BookingFields.orderNumber: p.orderNumber,
      if (p.transactionId != null) BookingFields.transactionId: p.transactionId,
      BookingFields.status: BookingStatus.pending.firestoreValue,
      BookingFields.operatorUid: null,
      if (routeSelection.routePolylineId != null)
        BookingFields.routePolylineId: routeSelection.routePolylineId,
      BookingFields.createdAt: FieldValue.serverTimestamp(),
      BookingFields.updatedAt: FieldValue.serverTimestamp(),
    });

    return id;
  }

  /// Cancels a booking owned by the current passenger.
  Future<void> cancelBooking(String bookingId) async {
    await _db.runTransaction((tx) async {
      final ref = _db.collection(FirestoreCollections.bookings).doc(bookingId);
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data() == null) {
        throw StateError('Booking does not exist.');
      }

      final data = snap.data()!;
      final fromStatus = BookingStatus.fromString(
        (data[BookingFields.status] ?? '').toString(),
      );

      tx.update(ref, {
        BookingFields.status: BookingStatus.cancelled.firestoreValue,
        BookingFields.updatedAt: FieldValue.serverTimestamp(),
        BookingFields.cancelledAt: FieldValue.serverTimestamp(),
      });

      tx.set(ref.collection(BookingSubcollections.statusHistory).doc(), {
        BookingStatusHistoryFields.from: fromStatus.firestoreValue,
        BookingStatusHistoryFields.to: BookingStatus.cancelled.firestoreValue,
        BookingStatusHistoryFields.changedBy:
            data[BookingFields.userId] ?? 'passenger',
        BookingStatusHistoryFields.source: 'passenger_app',
        BookingStatusHistoryFields.timestamp: FieldValue.serverTimestamp(),
      });

      tx.set(_archiveRef(bookingId), {
        ...data,
        BookingFields.status: BookingStatus.cancelled.firestoreValue,
        BookingFields.cancelledAt: FieldValue.serverTimestamp(),
        BookingFields.updatedAt: FieldValue.serverTimestamp(),
        'archivedAt': FieldValue.serverTimestamp(),
        'archivedStatus': BookingStatus.cancelled.firestoreValue,
      });
    });
  }

  Future<void> reserveOrderNumber({
    required String orderNumber,
    required String userId,
  }) async {
    await _db.runTransaction((tx) async {
      final ref = _db
          .collection(FirestoreCollections.orderNumberIndex)
          .doc(orderNumber);
      final snap = await tx.get(ref);
      if (snap.exists) {
        throw StateError('Order number is already in use.');
      }

      tx.set(ref, {
        'orderNumber': orderNumber,
        'userId': userId,
        'reservedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().add(const Duration(hours: 24)),
        ),
      });
    });
  }

  DocumentReference<Map<String, dynamic>> _archiveRef(String bookingId) {
    return _db.collection(FirestoreCollections.bookingsArchive).doc(bookingId);
  }

  DocumentReference<Map<String, dynamic>> _trackingRef(String bookingId) {
    return _db.collection(FirestoreCollections.tracking).doc(bookingId);
  }

  // ── Read / Stream ────────────────────────────────────────────────────────

  /// Streams a single booking document in real-time. Emits `null` if the
  /// document does not exist.
  Stream<BookingModel?> streamBooking(String bookingId) {
    final bookingRef = _db.collection(FirestoreCollections.bookings).doc(bookingId);
    final trackingRef = _trackingRef(bookingId);

    late final StreamController<BookingModel?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? bookingSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? trackingSub;

    Map<String, dynamic>? bookingData;
    Map<String, dynamic>? trackingData;
    var hasBookingSnapshot = false;

    Future<void> emitCurrent() async {
      if (!hasBookingSnapshot) return;
      if (bookingData == null) {
        controller.add(null);
        return;
      }

      var booking = await _fromDoc(bookingId, bookingData!);
      final lat = _asDouble(trackingData?[TrackingFields.operatorLat]);
      final lng = _asDouble(trackingData?[TrackingFields.operatorLng]);
      if (lat != null && lng != null) {
        booking = booking.copyWith(operatorLat: lat, operatorLng: lng);
      }

      controller.add(booking);
    }

    controller = StreamController<BookingModel?>.broadcast(
      onListen: () {
        bookingSub = bookingRef.snapshots().listen((snap) async {
          hasBookingSnapshot = true;
          bookingData = snap.data();
          await emitCurrent();
        }, onError: controller.addError);

        trackingSub = trackingRef.snapshots().listen((snap) async {
          trackingData = snap.data();
          if (hasBookingSnapshot && bookingData != null) {
            await emitCurrent();
          }
        }, onError: controller.addError);
      },
      onCancel: () async {
        await bookingSub?.cancel();
        await trackingSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Streams the user's currently active booking (pending / accepted /
  /// on_the_way), or `null` if there is none.
  Stream<BookingModel?> streamUserActiveBooking(String userId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.userId, isEqualTo: userId)
        .snapshots()
        .asyncMap((snap) async {
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
        .asyncMap((snap) async {
          final bookings =
              await Future.wait(snap.docs.map((d) => _fromDoc(d.id, d.data())))
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

  Future<_PolylineSelection> _buildRouteSelectionForBooking({
    required String originJettyId,
    required String destinationJettyId,
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final origin = _LatLngPoint(lat: originLat, lng: originLng);
    final destination = _LatLngPoint(lat: destinationLat, lng: destinationLng);
    final polylineSources = await _loadPolylineSources();
    _PolylineMatch? bestMatch;

    for (final raw in polylineSources) {
      final supportsPairValidation =
          raw.originJettyId != null && raw.destinationJettyId != null;
      if (supportsPairValidation &&
          (raw.originJettyId != originJettyId ||
              raw.destinationJettyId != destinationJettyId)) {
        continue;
      }

      final parsed = _normaliseRoutePolyline(raw.path);
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
          polylineId: raw.id,
          polyline: points,
          start: startSnap,
          end: endSnap,
          score: score,
        );
      }
    }

    if (bestMatch != null) {
      final segment = _extractSegment(bestMatch);
      if (segment.length >= 3) {
        return _PolylineSelection(
          routePolylineId: bestMatch.polylineId,
          routePolyline: segment
              .map((p) => <String, double>{'lat': p.lat, 'lng': p.lng})
              .toList(),
        );
      }

      // If snapped segment is too short but source geometry is richer,
      // keep the richer route to avoid rendering a misleading straight line.
      if (bestMatch.polyline.length >= 3) {
        return _PolylineSelection(
          routePolylineId: bestMatch.polylineId,
          routePolyline: bestMatch.polyline
              .map((p) => <String, double>{'lat': p.lat, 'lng': p.lng})
              .toList(),
        );
      }
    }

    return _PolylineSelection(
      routePolyline: [
        <String, double>{'lat': origin.lat, 'lng': origin.lng},
        <String, double>{'lat': destination.lat, 'lng': destination.lng},
      ],
    );
  }

  Future<List<_PolylineSource>> _loadPolylineSources() async {
    final sources = <_PolylineSource>[];

    try {
      final snap = await _db.collection(FirestoreCollections.polylines).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        sources.add(
          _PolylineSource(
            id: doc.id,
            path:
                data['path'] ??
                data['coordinates'] ??
                data['polyline'] ??
                data['geometry'] ??
                data[BookingFields.routePolyline],
            originJettyId: _normalizeOptionalString(
              data[BookingFields.originJettyId] ??
                  (data['properties'] is Map
                      ? (data['properties'] as Map)[BookingFields.originJettyId]
                      : null),
            ),
            destinationJettyId: _normalizeOptionalString(
              data[BookingFields.destinationJettyId] ??
                  (data['properties'] is Map
                      ? (data['properties'] as Map)[BookingFields.destinationJettyId]
                      : null),
            ),
          ),
        );
      }
    } catch (_) {
      // No polyline source available.
    }

    return sources;
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

  Future<BookingModel> _fromDoc(String id, Map<String, dynamic> data) async {
    final origin = data[BookingFields.originCoords] as GeoPoint?;
    final dest = data[BookingFields.destinationCoords] as GeoPoint?;
    final routePolyline = await _resolveRoutePolyline(data);
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

  Future<List<Map<String, double>>?> _resolveRoutePolyline(
    Map<String, dynamic> data,
  ) async {
    final embedded = _normaliseRoutePolyline(_extractRoutePolylineRaw(data));
    if (embedded != null && embedded.isNotEmpty) {
      return embedded;
    }

    final routePolylineId = data[BookingFields.routePolylineId]?.toString();
    if (routePolylineId == null || routePolylineId.isEmpty) {
      return _directRoutePolyline(data);
    }

    final snap = await _db
        .collection(FirestoreCollections.polylines)
        .doc(routePolylineId)
        .get();
    if (!snap.exists || snap.data() == null) {
      return _directRoutePolyline(data);
    }

    final polyline = _normaliseRoutePolyline(
      snap.data()!['path'] ??
          snap.data()!['coordinates'] ??
          snap.data()!['polyline'] ??
          snap.data()!['geometry'] ??
          snap.data()![BookingFields.routePolyline],
    );
    if (polyline != null && polyline.isNotEmpty) {
      return polyline;
    }

    return _directRoutePolyline(data);
  }

  List<Map<String, double>> _directRoutePolyline(Map<String, dynamic> data) {
    final origin = data[BookingFields.originCoords] as GeoPoint?;
    final dest = data[BookingFields.destinationCoords] as GeoPoint?;
    if (origin == null || dest == null) {
      return const <Map<String, double>>[];
    }
    return [
      <String, double>{'lat': origin.latitude, 'lng': origin.longitude},
      <String, double>{'lat': dest.latitude, 'lng': dest.longitude},
    ];
  }

  static dynamic _extractRoutePolylineRaw(Map<String, dynamic> data) {
    return data[BookingFields.routePolyline] ??
        data['routeCoordinates'] ??
        data['polylineCoordinates'] ??
        data['routePoints'];
  }

  static List<Map<String, double>>? _normaliseRoutePolyline(dynamic raw) {
    if (raw is Map) {
      raw =
          raw['path'] ??
          raw['coordinates'] ??
          raw['polyline'] ??
          raw['points'] ??
          raw['geometry'];
    }

    if (raw is String) {
      final compact = raw.trim();
      if (compact.contains(';')) {
        final pairs = compact
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty);
        final points = <Map<String, double>>[];
        for (final pair in pairs) {
          final point = _toRoutePointMap(pair);
          if (point != null) {
            points.add(point);
          }
        }
        return points.isEmpty ? null : points;
      }
    }

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

  static String? _normalizeOptionalString(dynamic value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

class _PolylineSource {
  const _PolylineSource({
    required this.id,
    required this.path,
    this.originJettyId,
    this.destinationJettyId,
  });

  final String id;
  final dynamic path;
  final String? originJettyId;
  final String? destinationJettyId;
}

class _PolylineSelection {
  const _PolylineSelection({this.routePolylineId, this.routePolyline});

  final String? routePolylineId;
  final List<Map<String, double>>? routePolyline;
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
    required this.polylineId,
    required this.polyline,
    required this.start,
    required this.end,
    required this.score,
  });

  final String polylineId;
  final List<_LatLngPoint> polyline;
  final _SnapResult start;
  final _SnapResult end;
  final double score;
}
