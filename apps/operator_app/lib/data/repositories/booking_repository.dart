import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `bookings` Firestore collection (operator side).
///
/// All write operations that can race (accept, reject, release) use Firestore
/// transactions. Start and complete use a lightweight retry wrapper.
class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const String _canonicalCorridorId = 'melaka_main_01';
  static const double _checkpointCoordMatchMaxMeters = 180;

  // ── Streams ──────────────────────────────────────────────────────────────

  /// Streams bookings currently assigned to [operatorId] (accepted or
  /// on_the_way), ordered by `updatedAt` descending.
  Stream<List<BookingModel>> streamActiveBookings(String operatorId) {
    return _db
        .collection(FirestoreCollections.bookings)
        // Transitional read path: keep legacy field until old data is migrated.
        .where(BookingFields.operatorId, isEqualTo: operatorId)
        .limit(50)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
          final active =
              snap.docs
                  .map((d) => _fromDoc(d.id, d.data()))
                  .where(
                    (b) =>
                        b.status == BookingStatus.accepted ||
                        b.status == BookingStatus.onTheWay,
                  )
                  .toList()
                ..sort((a, b) {
                  final at = a.updatedAt;
                  final bt = b.updatedAt;
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return bt.compareTo(at);
                });
          return active;
        });
  }

  /// Streams all pending bookings (no driver assigned yet), ordered by
  /// `createdAt` ascending (oldest first = FIFO queue).
  Stream<List<BookingModel>> streamPendingBookings() {
    return _db
        .collection(FirestoreCollections.bookings)
        .where(
          BookingFields.status,
          isEqualTo: BookingStatus.pending.firestoreValue,
        )
        .limit(100)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
          final pending =
              snap.docs
                  .map((d) => _fromDoc(d.id, d.data()))
                  .where((b) => b.operatorUid == null || b.operatorUid!.isEmpty)
                  .toList()
                ..sort((a, b) {
                  final at = a.createdAt;
                  final bt = b.createdAt;
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return at.compareTo(bt);
                });
          return pending;
        });
  }

  /// Streams booking history associated with [operatorId], newest first.
  Stream<List<BookingModel>> streamOperatorBookingHistory(String operatorId) {
    return _db
        .collection(FirestoreCollections.bookings)
        // Transitional read path: keep legacy field until old data is migrated.
        .where(BookingFields.operatorId, isEqualTo: operatorId)
        .limit(500)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
          final history =
              snap.docs.map((d) => _fromDoc(d.id, d.data())).toList()
                ..sort((a, b) {
                  final at = a.updatedAt ?? a.createdAt;
                  final bt = b.updatedAt ?? b.createdAt;
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return bt.compareTo(at);
                });
          return history;
        });
  }

  // ── Transactions ─────────────────────────────────────────────────────────

  /// Atomically accepts a pending booking. Returns an [OperationResult].
  Future<OperationResult> acceptBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db
            .collection(FirestoreCollections.bookings)
            .doc(bookingId);
        final snap = await tx.get(ref);

        if (!snap.exists) throw StateError('This booking no longer exists.');

        final data = snap.data()!;
        final status = BookingStatus.fromString(
          (data[BookingFields.status] ?? '').toString(),
        );
        final assignedOperatorUid = _assignedOperatorUid(data);
        final rejectedBy = _strList(data[BookingFields.rejectedBy]);

        if (status != BookingStatus.pending) {
          throw StateError('This booking is no longer pending.');
        }
        if (assignedOperatorUid.isNotEmpty) {
          throw StateError(
            'This booking was already assigned to another operator.',
          );
        }
        if (rejectedBy.contains(operatorId)) {
          throw StateError('You already rejected this booking.');
        }

        final payload = <String, dynamic>{
          BookingFields.status: BookingStatus.accepted.firestoreValue,
          BookingFields.operatorUid: operatorId,
          BookingFields.operatorId: operatorId,
          BookingFields.updatedAt: FieldValue.serverTimestamp(),
        };

        final corridorBinding = await _buildCorridorBindingPayload(tx, data);
        if (corridorBinding != null) {
          payload.addAll(corridorBinding);
        }

        tx.update(ref, payload);
      });

      return const OperationSuccess('Booking accepted successfully.');
    } on StateError catch (e) {
      return OperationFailure(
        'Unable to accept booking',
        e.message,
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Accept failed', 'Could not accept booking: $e');
    }
  }

  /// Atomically rejects a pending booking.
  ///
  /// If ALL currently online operators have now rejected the booking, its
  /// status is automatically set to [BookingStatus.rejected].
  Future<OperationResult> rejectBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    try {
      final onlineIds = await _loadOnlineOperatorIds();

      final fullyRejected = await _db.runTransaction<bool>((tx) async {
        final ref = _db
            .collection(FirestoreCollections.bookings)
            .doc(bookingId);
        final snap = await tx.get(ref);

        if (!snap.exists) throw StateError('This booking no longer exists.');

        final data = snap.data()!;
        final status = BookingStatus.fromString(
          (data[BookingFields.status] ?? '').toString(),
        );
        final assignedOperatorUid = _assignedOperatorUid(data);
        final rejectedBy = _strList(data[BookingFields.rejectedBy]);

        if (status != BookingStatus.pending || assignedOperatorUid.isNotEmpty) {
          throw StateError('Only unassigned pending bookings can be rejected.');
        }
        if (rejectedBy.contains(operatorId)) {
          throw StateError('You already rejected this booking.');
        }

        final updated = {...rejectedBy, operatorId};
        final isFullyRejected =
            onlineIds.isNotEmpty && onlineIds.every(updated.contains);

        tx.update(ref, {
          BookingFields.rejectedBy: updated.toList(),
          BookingFields.status: isFullyRejected
              ? BookingStatus.rejected.firestoreValue
              : BookingStatus.pending.firestoreValue,
          BookingFields.updatedAt: FieldValue.serverTimestamp(),
        });

        return isFullyRejected;
      });

      if (fullyRejected) {
        return const OperationSuccess(
          'All online operators declined this request — the passenger will see it as rejected.',
        );
      }
      return const OperationSuccess(
        'Booking rejected. It stays pending for other operators.',
      );
    } on StateError catch (e) {
      return OperationFailure(
        'Unable to reject booking',
        e.message,
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Reject failed', 'Could not reject booking: $e');
    }
  }

  /// Atomically releases an accepted booking back to the pending queue and
  /// adds the operator to its [BookingFields.rejectedBy] list.
  Future<OperationResult> releaseBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    try {
      await _runWithRetry(
        () => _db.runTransaction((tx) async {
          final ref = _db
              .collection(FirestoreCollections.bookings)
              .doc(bookingId);
          final snap = await tx.get(ref);

          if (!snap.exists) throw StateError('This booking no longer exists.');

          final data = snap.data()!;
          final status = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          final assignedOperatorUid = _assignedOperatorUid(data);
          final rejectedBy = _strList(data[BookingFields.rejectedBy]);

          if (status != BookingStatus.accepted ||
              assignedOperatorUid != operatorId) {
            throw StateError('Only your accepted booking can be released.');
          }

          tx.update(ref, {
            BookingFields.status: BookingStatus.pending.firestoreValue,
            BookingFields.operatorUid: null,
            BookingFields.operatorId: null,
            BookingFields.rejectedBy: {...rejectedBy, operatorId}.toList(),
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
          });
        }),
      );

      return const OperationSuccess('Booking released back to the queue.');
    } on StateError catch (e) {
      return OperationFailure(
        'Unable to release booking',
        e.message,
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure(
        'Release failed',
        'Could not release booking: $e',
      );
    }
  }

  /// Updates the booking status to `on_the_way` (start trip).
  Future<OperationResult> startTrip({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) => _updateStatus(
    bookingId: bookingId,
    status: BookingStatus.onTheWay,
    operatorId: operatorId,
    operatorLat: operatorLat,
    operatorLng: operatorLng,
  );

  /// Updates the booking status to `completed`.
  Future<OperationResult> completeTrip({
    required String bookingId,
    required String operatorId,
  }) => _updateStatus(
    bookingId: bookingId,
    status: BookingStatus.completed,
    operatorId: operatorId,
  );

  /// Publishes the operator's latest location for an active `on_the_way`
  /// booking so passengers can track in real time.
  Future<OperationResult> updateOperatorLocation({
    required String bookingId,
    required String operatorId,
    required double operatorLat,
    required double operatorLng,
  }) async {
    try {
      await _runWithRetry(
        () => _db
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .update({
              BookingFields.operatorUid: operatorId,
              BookingFields.operatorId: operatorId,
              BookingFields.operatorLat: operatorLat,
              BookingFields.operatorLng: operatorLng,
              BookingFields.updatedAt: FieldValue.serverTimestamp(),
            }),
      );

      return const OperationSuccess('Location updated.');
    } catch (e) {
      return OperationFailure(
        'Location update failed',
        'Could not update operator location: $e',
      );
    }
  }

  // ── Batch operations ─────────────────────────────────────────────────────

  /// Releases all accepted bookings for [operatorId] (called when going
  /// offline). Returns the count of bookings released.
  Future<int> releaseAllAcceptedBookings(String operatorId) async {
    final snap = await _db
        .collection(FirestoreCollections.bookings)
        // Transitional read path: keep legacy field until old data is migrated.
        .where(BookingFields.operatorId, isEqualTo: operatorId)
        .limit(50)
        .get();

    final accepted = snap.docs.where((d) {
      final s = BookingStatus.fromString(
        (d.data()[BookingFields.status] ?? '').toString(),
      );
      return s == BookingStatus.accepted;
    }).toList();

    for (final doc in accepted) {
      final rejectedBy = _strList(doc.data()[BookingFields.rejectedBy]);
      await _runWithRetry(
        () => doc.reference.update({
          BookingFields.status: BookingStatus.pending.firestoreValue,
          BookingFields.operatorUid: null,
          BookingFields.operatorId: null,
          BookingFields.rejectedBy: {...rejectedBy, operatorId}.toList(),
          BookingFields.updatedAt: FieldValue.serverTimestamp(),
        }),
      );
    }

    return accepted.length;
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<OperationResult> _updateStatus({
    required String bookingId,
    required BookingStatus status,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) async {
    try {
      final payload = <String, dynamic>{
        BookingFields.status: status.firestoreValue,
        BookingFields.operatorUid: operatorId,
        BookingFields.operatorId: operatorId,
        BookingFields.updatedAt: FieldValue.serverTimestamp(),
      };

      if (operatorLat != null && operatorLng != null) {
        payload[BookingFields.operatorLat] = operatorLat;
        payload[BookingFields.operatorLng] = operatorLng;
      }

      await _runWithRetry(
        () => _db
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .update(payload),
      );

      final label = status == BookingStatus.onTheWay ? 'started' : 'completed';
      return OperationSuccess('Trip $label successfully.');
    } catch (e) {
      return OperationFailure('Update failed', 'Could not update booking: $e');
    }
  }

  Future<Set<String>> _loadOnlineOperatorIds() async {
    final snap = await _db
        .collection(FirestoreCollections.operatorPresence)
        .where(OperatorPresenceFields.isOnline, isEqualTo: true)
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  static Future<T> _runWithRetry<T>(Future<T> Function() action) async {
    const maxAttempts = 2;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt == maxAttempts) rethrow;
      } on FirebaseException catch (e) {
        lastError = e;
        final retryable =
            e.code == 'unavailable' ||
            e.code == 'aborted' ||
            e.code == 'deadline-exceeded';
        if (!retryable || attempt == maxAttempts) rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }

    throw lastError ?? StateError('Firestore write failed.');
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

  static List<String> _strList(dynamic v) {
    if (v is Iterable) return v.map((e) => e.toString()).toList();
    return const [];
  }

  static String _assignedOperatorUid(Map<String, dynamic> data) {
    return (data[BookingFields.operatorUid] ?? data[BookingFields.operatorId] ?? '')
        .toString();
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

    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<Map<String, dynamic>?> _buildCorridorBindingPayload(
    Transaction tx,
    Map<String, dynamic> bookingData,
  ) async {
    final originLabel = (bookingData[BookingFields.origin] ?? '').toString();
    final destinationLabel =
        (bookingData[BookingFields.destination] ?? '').toString();

    if (originLabel.trim().isEmpty || destinationLabel.trim().isEmpty) {
      return null;
    }

    final corridorRef = _db
        .collection(FirestoreCollections.navigationCorridors)
        .doc(_canonicalCorridorId);
    DocumentSnapshot<Map<String, dynamic>> corridorSnap;
    try {
      corridorSnap = await tx.get(corridorRef);
    } catch (_) {
      return null;
    }
    final corridor = corridorSnap.data();

    if (!corridorSnap.exists || corridor == null) {
      return null;
    }

    final version = _asInt(corridor[NavigationCorridorFields.version]);
    final checkpoints = corridor[NavigationCorridorFields.checkpoints];

    if (version == null || version < 1 || checkpoints is! Iterable) {
      return null;
    }

    final originCoords = bookingData[BookingFields.originCoords] as GeoPoint?;
    final destinationCoords =
        bookingData[BookingFields.destinationCoords] as GeoPoint?;

    final originSeq = _findCheckpointSeq(
      checkpoints,
      label: originLabel,
      near: originCoords,
    );
    final destinationSeq = _findCheckpointSeq(
      checkpoints,
      label: destinationLabel,
      near: destinationCoords,
    );

    if (originSeq == null || destinationSeq == null) {
      return null;
    }

    if (originSeq < 1 || destinationSeq > 14 || originSeq >= destinationSeq) {
      return null;
    }

    final existingRoutePolyline = _normaliseRoutePolyline(
      _extractRoutePolylineRaw(bookingData),
    );
    final corridorRoutePolyline = _normaliseRoutePolyline(
      corridor[NavigationCorridorFields.polyline],
    );

    final payload = <String, dynamic>{
      BookingFields.corridorId: _canonicalCorridorId,
      BookingFields.corridorVersion: version,
      BookingFields.originCheckpointSeq: originSeq,
      BookingFields.destinationCheckpointSeq: destinationSeq,
    };

    if (existingRoutePolyline == null && corridorRoutePolyline != null) {
      payload[BookingFields.routePolyline] = corridorRoutePolyline;
    }

    return payload;
  }

  static int? _findCheckpointSeq(
    Iterable checkpoints, {
    required String label,
    GeoPoint? near,
  }) {
    final normalizedLabel = _normalizeLabel(label);
    if (normalizedLabel.isEmpty) {
      return null;
    }

    int? nearestSeq;
    double? nearestDistanceMeters;

    for (final entry in checkpoints) {
      if (entry is! Map) continue;

      final seq = _asInt(entry['seq'] ?? entry['sequence']);
      if (seq == null) continue;

      if (_checkpointMatchesLabel(entry, normalizedLabel)) {
        return seq;
      }

      if (near == null) continue;

      final checkpointLat = _asDouble(entry['lat'] ?? entry['latitude']);
      final checkpointLng =
          _asDouble(entry['lng'] ?? entry['longitude'] ?? entry['lon']);
      if (checkpointLat == null || checkpointLng == null) {
        continue;
      }

      final distanceMeters = _distanceMeters(
        near.latitude,
        near.longitude,
        checkpointLat,
        checkpointLng,
      );

      if (nearestDistanceMeters == null ||
          distanceMeters < nearestDistanceMeters) {
        nearestDistanceMeters = distanceMeters;
        nearestSeq = seq;
      }
    }

    if (nearestDistanceMeters != null &&
        nearestDistanceMeters <= _checkpointCoordMatchMaxMeters) {
      return nearestSeq;
    }

    return null;
  }

  static bool _checkpointMatchesLabel(Map raw, String normalizedLabel) {
    final candidates = <String>{
      _normalizeLabel(raw['name']),
      _normalizeLabel(raw['checkpointId']),
      _normalizeLabel(raw['jettyId']),
      _normalizeLabel(raw['jettyName']),
    };

    final aliases = raw['aliases'];
    if (aliases is Iterable) {
      for (final alias in aliases) {
        candidates.add(_normalizeLabel(alias));
      }
    }

    return candidates.contains(normalizedLabel);
  }

  static String _normalizeLabel(dynamic input) {
    if (input == null) return '';
    return input
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * (3.1415926535897932 / 180.0);
}
