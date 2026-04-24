import 'dart:async';

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

  // ── Streams ──────────────────────────────────────────────────────────────

  /// Streams bookings currently assigned to [operatorId] (accepted or
  /// on_the_way), ordered by `updatedAt` descending.
  Stream<List<BookingModel>> streamActiveBookings(String operatorId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.operatorUid, isEqualTo: operatorId)
        .limit(50)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snap) async {
          final active =
              (await Future.wait(
                    snap.docs.map((d) => _fromDoc(d.id, d.data())),
                  ))
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
        .asyncMap((snap) async {
          final pending =
              (await Future.wait(
                    snap.docs.map((d) => _fromDoc(d.id, d.data())),
                  ))
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
        .where(BookingFields.operatorUid, isEqualTo: operatorId)
        .limit(500)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snap) async {
          final history =
              (await Future.wait(
                snap.docs.map((d) => _fromDoc(d.id, d.data())),
              ))..sort((a, b) {
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

        tx.update(ref, {
          BookingFields.status: BookingStatus.accepted.firestoreValue,
          BookingFields.operatorUid: operatorId,
          BookingFields.updatedAt: FieldValue.serverTimestamp(),
        });
        _appendStatusHistory(
          tx: tx,
          ref: ref,
          from: status,
          to: BookingStatus.accepted,
          changedBy: operatorId,
        );
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

        final nextStatus = isFullyRejected
            ? BookingStatus.rejected
            : BookingStatus.pending;

        tx.update(ref, {
          BookingFields.rejectedBy: updated.toList(),
          BookingFields.status: nextStatus.firestoreValue,
          BookingFields.updatedAt: FieldValue.serverTimestamp(),
        });

        if (nextStatus != status) {
          _appendStatusHistory(
            tx: tx,
            ref: ref,
            from: status,
            to: nextStatus,
            changedBy: operatorId,
          );
        }

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
            BookingFields.rejectedBy: {...rejectedBy, operatorId}.toList(),
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
          });

          _appendStatusHistory(
            tx: tx,
            ref: ref,
            from: status,
            to: BookingStatus.pending,
            changedBy: operatorId,
          );
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

  /// Marks that the passenger has been picked up while trip remains
  /// `on_the_way`.
  Future<OperationResult> markPassengerPickedUp({
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
          if (!snap.exists || snap.data() == null) {
            throw StateError('This booking no longer exists.');
          }

          final data = snap.data()!;
          final currentStatus = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          final assignedOperatorUid = _assignedOperatorUid(data);

          if (currentStatus != BookingStatus.onTheWay ||
              assignedOperatorUid != operatorId) {
            throw StateError(
              'Only your on-the-way booking can be marked as picked up.',
            );
          }

          tx.update(ref, {
            BookingFields.passengerPickedUpAt: FieldValue.serverTimestamp(),
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
          });
        }),
      );

      return const OperationSuccess('Passenger marked as picked up.');
    } on StateError catch (e) {
      return OperationFailure(
        'Unable to update booking',
        e.message,
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Update failed', 'Could not update booking: $e');
    }
  }

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
        () => _db.collection(FirestoreCollections.tracking).doc(bookingId).set({
          TrackingFields.bookingId: bookingId,
          TrackingFields.operatorUid: operatorId,
          TrackingFields.operatorLat: operatorLat,
          TrackingFields.operatorLng: operatorLng,
          TrackingFields.updatedAt: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
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
        .where(BookingFields.operatorUid, isEqualTo: operatorId)
        .limit(50)
        .get();

    final accepted = snap.docs.where((d) {
      final s = BookingStatus.fromString(
        (d.data()[BookingFields.status] ?? '').toString(),
      );
      return s == BookingStatus.accepted;
    }).toList();

    for (final doc in accepted) {
      await _runWithRetry(
        () => _db.runTransaction((tx) async {
          final ref = doc.reference;
          final snap = await tx.get(ref);
          if (!snap.exists || snap.data() == null) {
            return;
          }

          final data = snap.data()!;
          final currentStatus = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          final rejectedBy = _strList(data[BookingFields.rejectedBy]);

          tx.update(ref, {
            BookingFields.status: BookingStatus.pending.firestoreValue,
            BookingFields.operatorUid: null,
            BookingFields.rejectedBy: {...rejectedBy, operatorId}.toList(),
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
          });

          _appendStatusHistory(
            tx: tx,
            ref: ref,
            from: currentStatus,
            to: BookingStatus.pending,
            changedBy: operatorId,
          );
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
      await _runWithRetry(
        () => _db.runTransaction((tx) async {
          final ref = _db
              .collection(FirestoreCollections.bookings)
              .doc(bookingId);
          final snap = await tx.get(ref);
          if (!snap.exists || snap.data() == null) {
            throw StateError('This booking no longer exists.');
          }

          final data = snap.data()!;
          final currentStatus = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );

          final payload = <String, dynamic>{
            BookingFields.status: status.firestoreValue,
            BookingFields.operatorUid: operatorId,
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
          };

          if (operatorLat != null && operatorLng != null) {
            payload[BookingFields.operatorLat] = operatorLat;
            payload[BookingFields.operatorLng] = operatorLng;
          }

          tx.update(ref, payload);
          _appendStatusHistory(
            tx: tx,
            ref: ref,
            from: currentStatus,
            to: status,
            changedBy: operatorId,
          );

          if (_shouldArchive(status)) {
            tx.set(_archiveRef(bookingId), {
              ...data,
              ...payload,
              BookingFields.status: status.firestoreValue,
              BookingFields.updatedAt: FieldValue.serverTimestamp(),
              'archivedAt': FieldValue.serverTimestamp(),
              'archivedStatus': status.firestoreValue,
            });
          }
        }),
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

  Future<BookingModel> _fromDoc(String id, Map<String, dynamic> data) async {
    final origin = data[BookingFields.originCoords] as GeoPoint?;
    final dest = data[BookingFields.destinationCoords] as GeoPoint?;
    final routePolyline = await _resolveRoutePolyline(data);
    final routeToOriginPolyline = await _resolveRouteToOriginPolyline(
      data,
      fallback: routePolyline,
    );
    final routeToDestinationPolyline = await _resolveRouteToDestinationPolyline(
      data,
      fallback: routePolyline,
    );
    final createdAt = (data[BookingFields.createdAt] as Timestamp?)?.toDate();
    final updatedAt = (data[BookingFields.updatedAt] as Timestamp?)?.toDate();
    final cancelledAt = (data[BookingFields.cancelledAt] as Timestamp?)
        ?.toDate();
    final passengerPickedUpAt =
        (data[BookingFields.passengerPickedUpAt] as Timestamp?)?.toDate();

    data = {
      ...data,
      if (data[BookingFields.bookingId] == null) BookingFields.bookingId: id,
      if (routePolyline != null) BookingFields.routePolyline: routePolyline,
      if (routeToOriginPolyline != null)
        BookingFields.routeToOriginPolyline: routeToOriginPolyline,
      if (routeToDestinationPolyline != null)
        BookingFields.routeToDestinationPolyline: routeToDestinationPolyline,
      if (passengerPickedUpAt != null)
        BookingFields.passengerPickedUpAt: passengerPickedUpAt,
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

  Future<List<Map<String, double>>?> _resolveRouteToOriginPolyline(
    Map<String, dynamic> data, {
    required List<Map<String, double>>? fallback,
  }) async {
    final direct = _normaliseRoutePolyline(
      _extractPhaseRouteRaw(data, const [
        BookingFields.routeToOriginPolyline,
        'operatorToOriginPolyline',
        'toOriginPolyline',
        'routeToOrigin',
        'pickupPolyline',
        'routeToPickupPolyline',
        'operatorToPickupPolyline',
        'pickupRoutePolyline',
        'pickupRoute',
        'pickupPath',
        'toOriginPath',
        'operatorToPickupPath',
        'operatorToOriginCoordinates',
        'pickupPathCoordinates',
      ]),
    );
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final nested = _normaliseRoutePolyline(
      _extractNestedPhaseRouteRaw(data, const [
        'to_origin',
        'toOrigin',
        'to_pickup',
        'toPickup',
        'pickup',
        'operator_to_origin',
        'operatorToOrigin',
      ]),
    );
    if (nested != null && nested.isNotEmpty) {
      return nested;
    }

    final byId = await _resolvePhaseRouteFromId(
      data,
      idKeyCandidates: const [
        'routeToOriginPolylineId',
        'operatorToOriginPolylineId',
        'toOriginPolylineId',
        'routeToPickupPolylineId',
        'operatorToPickupPolylineId',
      ],
      nestedIdCandidates: const [
        'to_origin',
        'toOrigin',
        'to_pickup',
        'toPickup',
        'pickup',
      ],
    );
    if (byId != null && byId.isNotEmpty) {
      return byId;
    }

    return fallback;
  }

  Future<List<Map<String, double>>?> _resolveRouteToDestinationPolyline(
    Map<String, dynamic> data, {
    required List<Map<String, double>>? fallback,
  }) async {
    final direct = _normaliseRoutePolyline(
      _extractPhaseRouteRaw(data, const [
        BookingFields.routeToDestinationPolyline,
        'originToDestinationPolyline',
        'toDestinationPolyline',
        'routeToDestination',
        'dropoffPolyline',
        'dropoffRoutePolyline',
        'dropoffRoute',
        'destinationRoutePolyline',
        'toDestinationPath',
        'pickupToDestinationPath',
        'originToDestinationCoordinates',
        'dropoffPathCoordinates',
      ]),
    );
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final nested = _normaliseRoutePolyline(
      _extractNestedPhaseRouteRaw(data, const [
        'to_destination',
        'toDestination',
        'to_dropoff',
        'toDropoff',
        'dropoff',
        'origin_to_destination',
        'originToDestination',
      ]),
    );
    if (nested != null && nested.isNotEmpty) {
      return nested;
    }

    final byId = await _resolvePhaseRouteFromId(
      data,
      idKeyCandidates: const [
        'routeToDestinationPolylineId',
        'originToDestinationPolylineId',
        'toDestinationPolylineId',
        'dropoffPolylineId',
      ],
      nestedIdCandidates: const [
        'to_destination',
        'toDestination',
        'to_dropoff',
        'toDropoff',
        'dropoff',
        'origin_to_destination',
        'originToDestination',
      ],
    );
    if (byId != null && byId.isNotEmpty) {
      return byId;
    }

    return fallback;
  }

  Future<List<Map<String, double>>?> _resolvePhaseRouteFromId(
    Map<String, dynamic> data, {
    required List<String> idKeyCandidates,
    required List<String> nestedIdCandidates,
  }) async {
    String? routeId;
    for (final key in idKeyCandidates) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        routeId = value;
        break;
      }
    }

    if (routeId == null || routeId.isEmpty) {
      final nestedIds = data['phasePolylineIds'] ?? data['phaseRouteIds'];
      if (nestedIds is Map) {
        for (final key in nestedIdCandidates) {
          final value = nestedIds[key]?.toString().trim();
          if (value != null && value.isNotEmpty) {
            routeId = value;
            break;
          }
        }
      }
    }

    if (routeId == null || routeId.isEmpty) {
      return null;
    }

    final snap = await _db
        .collection(FirestoreCollections.polylines)
        .doc(routeId)
        .get();
    if (!snap.exists || snap.data() == null) {
      return null;
    }

    return _normaliseRoutePolyline(
      snap.data()!['path'] ??
          snap.data()!['coordinates'] ??
          snap.data()!['polyline'] ??
          snap.data()!['geometry'] ??
          snap.data()![BookingFields.routePolyline],
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

  static bool _shouldArchive(BookingStatus status) {
    return status == BookingStatus.completed ||
        status == BookingStatus.cancelled;
  }

  DocumentReference<Map<String, dynamic>> _archiveRef(String bookingId) {
    return _db.collection(FirestoreCollections.bookingsArchive).doc(bookingId);
  }

  static List<String> _strList(dynamic v) {
    if (v is Iterable) return v.map((e) => e.toString()).toList();
    return const [];
  }

  static String _assignedOperatorUid(Map<String, dynamic> data) {
    return (data[BookingFields.operatorUid] ??
            data[BookingFields.operatorId] ??
            '')
        .toString();
  }

  static dynamic _extractRoutePolylineRaw(Map<String, dynamic> data) {
    return data[BookingFields.routePolyline] ??
        data['routeCoordinates'] ??
        data['polylineCoordinates'] ??
        data['routePoints'];
  }

  static dynamic _extractPhaseRouteRaw(
    Map<String, dynamic> data,
    List<String> candidates,
  ) {
    for (final key in candidates) {
      final value = data[key];
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  static dynamic _extractNestedPhaseRouteRaw(
    Map<String, dynamic> data,
    List<String> candidates,
  ) {
    final container = data['phasePolylines'] ?? data['phaseRoutes'];
    if (container is! Map) {
      return null;
    }

    for (final key in candidates) {
      final value = container[key];
      if (value != null) {
        return value;
      }
    }
    return null;
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

  void _appendStatusHistory({
    required Transaction tx,
    required DocumentReference<Map<String, dynamic>> ref,
    required BookingStatus from,
    required BookingStatus to,
    required String changedBy,
  }) {
    tx.set(ref.collection(BookingSubcollections.statusHistory).doc(), {
      BookingStatusHistoryFields.from: from.firestoreValue,
      BookingStatusHistoryFields.to: to.firestoreValue,
      BookingStatusHistoryFields.changedBy: changedBy,
      BookingStatusHistoryFields.source: 'operator_app',
      BookingStatusHistoryFields.timestamp: FieldValue.serverTimestamp(),
    });
  }
}
