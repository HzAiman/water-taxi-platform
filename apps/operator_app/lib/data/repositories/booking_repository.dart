import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

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
  List<_PolylineSource>? _cachedPolylineSources;
  DateTime? _cachedPolylineSourcesAt;

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
        final operatorRef = _db
            .collection(FirestoreCollections.operators)
            .doc(operatorId);
        final snap = await tx.get(ref);
        final operatorSnap = await tx.get(operatorRef);

        if (!snap.exists) throw StateError('This booking no longer exists.');

        final data = snap.data()!;
        final operatorData = operatorSnap.data() ?? const <String, dynamic>{};
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
          BookingFields.assignedOperatorName:
              (operatorData[OperatorFields.name] ?? '').toString(),
          BookingFields.assignedOperatorDisplayId:
              (operatorData[OperatorFields.operatorId] ?? '').toString(),
          BookingFields.assignedOperatorPhone:
              (operatorData[OperatorFields.phoneNumber] ?? '').toString(),
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
      await _runWithRetry(() async {
        final bookingRef = _db
            .collection(FirestoreCollections.bookings)
            .doc(bookingId);
        await bookingRef.set({
          BookingFields.operatorLat: operatorLat,
          BookingFields.operatorLng: operatorLng,
          BookingFields.updatedAt: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _db.collection(FirestoreCollections.tracking).doc(bookingId).set({
          TrackingFields.bookingId: bookingId,
          TrackingFields.operatorUid: operatorId,
          TrackingFields.operatorLat: operatorLat,
          TrackingFields.operatorLng: operatorLng,
          TrackingFields.updatedAt: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

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
      final archivePayload = await _runWithRetry(
        () => _db.runTransaction<Map<String, dynamic>?>((tx) async {
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
            return {
              ...data,
              ...payload,
              BookingFields.status: status.firestoreValue,
              BookingFields.updatedAt: FieldValue.serverTimestamp(),
              'archivedAt': FieldValue.serverTimestamp(),
              'archivedStatus': status.firestoreValue,
            };
          }

          return null;
        }),
      );

      if (archivePayload != null) {
        await _writeArchiveBestEffort(bookingId, archivePayload);
      }

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
    final routeResolution = await _resolveRoutePolyline(data);
    final routePolyline = routeResolution.points;
    final routeToOriginPolyline = await _resolveRouteToOriginPolyline(
      data,
      sharedRouteFallback: routeResolution.isUsableForPhaseFallback
          ? routePolyline
          : null,
    );
    final routeToDestinationPolyline = await _resolveRouteToDestinationPolyline(
      data,
      sharedRouteFallback: routeResolution.isUsableForPhaseFallback
          ? routePolyline
          : null,
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
      if ((data[BookingFields.routePolylineId] == null ||
              data[BookingFields.routePolylineId].toString().trim().isEmpty) &&
          routeResolution.sourceId != null)
        BookingFields.routePolylineId: routeResolution.sourceId,
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
    List<Map<String, double>>? sharedRouteFallback,
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

    if (sharedRouteFallback != null && sharedRouteFallback.length >= 2) {
      return sharedRouteFallback;
    }

    return null;
  }

  Future<List<Map<String, double>>?> _resolveRouteToDestinationPolyline(
    Map<String, dynamic> data, {
    List<Map<String, double>>? sharedRouteFallback,
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

    if (sharedRouteFallback != null && sharedRouteFallback.length >= 2) {
      return sharedRouteFallback;
    }

    return null;
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

    routeId ??= _extractNestedPhaseRouteId(data, nestedIdCandidates);

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

  Future<_ResolvedRoutePolyline> _resolveRoutePolyline(
    Map<String, dynamic> data,
  ) async {
    final embedded = _normaliseRoutePolyline(_extractRoutePolylineRaw(data));
    if (embedded != null && embedded.isNotEmpty) {
      return _ResolvedRoutePolyline(
        points: embedded,
        isDirectFallback: embedded.length < 3,
      );
    }

    final routePolylineId = data[BookingFields.routePolylineId]
        ?.toString()
        .trim();
    if (routePolylineId == null || routePolylineId.isEmpty) {
      final matched = await _resolveBestSharedRoutePolyline(data);
      if (matched != null) {
        return matched;
      }
      return _ResolvedRoutePolyline(
        points: _directRoutePolyline(data),
        isDirectFallback: true,
      );
    }

    final snap = await _db
        .collection(FirestoreCollections.polylines)
        .doc(routePolylineId)
        .get();
    if (snap.exists && snap.data() != null) {
      final polyline = _normaliseRoutePolyline(
        snap.data()!['path'] ??
            snap.data()!['coordinates'] ??
            snap.data()!['polyline'] ??
            snap.data()!['geometry'] ??
            snap.data()![BookingFields.routePolyline],
      );
      if (polyline != null && polyline.isNotEmpty) {
        return _ResolvedRoutePolyline(
          points: polyline,
          sourceId: routePolylineId,
        );
      }
    }

    final matched = await _resolveBestSharedRoutePolyline(data);
    if (matched != null) {
      return matched;
    }

    return _ResolvedRoutePolyline(
      points: _directRoutePolyline(data),
      sourceId: routePolylineId,
      isDirectFallback: true,
    );
  }

  Future<_ResolvedRoutePolyline?> _resolveBestSharedRoutePolyline(
    Map<String, dynamic> data,
  ) async {
    final origin = data[BookingFields.originCoords] as GeoPoint?;
    final destination = data[BookingFields.destinationCoords] as GeoPoint?;
    if (origin == null || destination == null) {
      return null;
    }

    final originPoint = _LatLngPoint(
      lat: origin.latitude,
      lng: origin.longitude,
    );
    final destinationPoint = _LatLngPoint(
      lat: destination.latitude,
      lng: destination.longitude,
    );
    final originJettyId = _normalizeOptionalString(
      data[BookingFields.originJettyId],
    );
    final destinationJettyId = _normalizeOptionalString(
      data[BookingFields.destinationJettyId],
    );
    final sources = await _loadPolylineSources();

    _PolylineMatch? bestMatch;
    for (final raw in sources) {
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
          .map((point) => _LatLngPoint(lat: point['lat']!, lng: point['lng']!))
          .toList(growable: false);
      final startSnap = _snapPointToPolyline(originPoint, points);
      final endSnap = _snapPointToPolyline(destinationPoint, points);
      final candidate = _PolylineMatch(
        polylineId: raw.id,
        polyline: points,
        start: startSnap,
        end: endSnap,
        score: 0,
      );
      final segment = _extractSegment(candidate);
      final startOffset = _distanceBetweenPoints(originPoint, startSnap.point);
      final endOffset = _distanceBetweenPoints(destinationPoint, endSnap.point);
      final segmentLength = _polylineLength(segment);
      final directLength = _distanceBetweenPoints(
        startSnap.point,
        endSnap.point,
      );
      final detourPenalty = directLength <= 1e-9
          ? 0.0
          : (segmentLength - directLength).abs();
      final score =
          ((startOffset + endOffset) * 2.0) +
          segmentLength +
          (detourPenalty * 4.0);

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

    if (bestMatch == null) {
      return null;
    }

    return _ResolvedRoutePolyline(
      points: bestMatch.polyline
          .map((point) => <String, double>{'lat': point.lat, 'lng': point.lng})
          .toList(growable: false),
      sourceId: bestMatch.polylineId,
    );
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

  Future<void> _writeArchiveBestEffort(
    String bookingId,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _archiveRef(bookingId).set(payload);
    } catch (e, stackTrace) {
      developer.log(
        'Booking completion succeeded, but archive write was skipped.',
        name: 'BookingRepository',
        error: e,
        stackTrace: stackTrace,
      );
    }
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
        return _unwrapPhaseRoutePayload(value);
      }
    }
    return null;
  }

  static dynamic _unwrapPhaseRoutePayload(dynamic value) {
    if (value is Map) {
      return value['path'] ??
          value['coordinates'] ??
          value['polyline'] ??
          value['geometry'] ??
          value['points'] ??
          value[BookingFields.routePolyline] ??
          value;
    }
    return value;
  }

  static String? _extractNestedPhaseRouteId(
    Map<String, dynamic> data,
    List<String> nestedIdCandidates,
  ) {
    final container = data['phasePolylines'] ?? data['phaseRoutes'];
    if (container is! Map) {
      return null;
    }

    for (final key in nestedIdCandidates) {
      final value = container[key];
      if (value is String) {
        final routeId = value.trim();
        if (routeId.isNotEmpty) {
          return routeId;
        }
      }

      if (value is Map) {
        final routeId =
            value['routePolylineId'] ??
            value['polylineId'] ??
            value['routeId'] ??
            value['id'] ??
            value['ref'];
        final normalized = routeId?.toString().trim();
        if (normalized != null && normalized.isNotEmpty) {
          return normalized;
        }
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
      final lat = _asDouble(
        entry['lat'] ?? entry['latitude'] ?? entry['_latitude'],
      );
      final lng = _asDouble(
        entry['lng'] ??
            entry['longitude'] ??
            entry['lon'] ??
            entry['_longitude'],
      );
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

  Future<List<_PolylineSource>> _loadPolylineSources() async {
    final fetchedAt = _cachedPolylineSourcesAt;
    if (_cachedPolylineSources != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(minutes: 2)) {
      return _cachedPolylineSources!;
    }

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
                      ? (data['properties']
                            as Map)[BookingFields.destinationJettyId]
                      : null),
            ),
          ),
        );
      }
    } catch (_) {
      return _cachedPolylineSources ?? const <_PolylineSource>[];
    }

    _cachedPolylineSources = sources;
    _cachedPolylineSourcesAt = DateTime.now();
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
    if (match.polyline.length < 2) {
      return <_LatLngPoint>[match.start.point, match.end.point];
    }

    if (!_isClosedLoopPolyline(match.polyline)) {
      return _extractLinearSegment(match);
    }

    final forward = _extractLoopSegment(match, step: 1);
    final backward = _extractLoopSegment(match, step: -1);
    return _polylineLength(backward) < _polylineLength(forward)
        ? backward
        : forward;
  }

  static List<_LatLngPoint> _extractLinearSegment(_PolylineMatch match) {
    final segment = <_LatLngPoint>[match.start.point];
    if (match.start.segmentIndex <= match.end.segmentIndex) {
      for (
        var i = match.start.segmentIndex + 1;
        i <= match.end.segmentIndex;
        i++
      ) {
        _addIfDistinct(segment, match.polyline[i]);
      }
    } else {
      for (
        var i = match.start.segmentIndex;
        i >= match.end.segmentIndex + 1;
        i--
      ) {
        _addIfDistinct(segment, match.polyline[i]);
      }
    }
    _addIfDistinct(segment, match.end.point);
    return segment;
  }

  static List<_LatLngPoint> _extractLoopSegment(
    _PolylineMatch match, {
    required int step,
  }) {
    final segment = <_LatLngPoint>[match.start.point];
    final segmentCount = match.polyline.length - 1;
    var index = match.start.segmentIndex;
    var guard = 0;

    while (index != match.end.segmentIndex && guard <= segmentCount + 1) {
      if (step > 0) {
        final nextIndex = (index + 1) % segmentCount;
        _addIfDistinct(segment, match.polyline[nextIndex]);
        index = nextIndex;
      } else {
        _addIfDistinct(segment, match.polyline[index]);
        index = (index - 1 + segmentCount) % segmentCount;
      }
      guard++;
    }

    _addIfDistinct(segment, match.end.point);
    return segment;
  }

  static bool _isClosedLoopPolyline(List<_LatLngPoint> points) {
    if (points.length < 3) {
      return false;
    }
    return _distanceBetweenPoints(points.first, points.last) <= 1e-6;
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

  static double _distanceBetweenPoints(_LatLngPoint a, _LatLngPoint b) {
    final dLat = a.lat - b.lat;
    final dLng = a.lng - b.lng;
    return math.sqrt((dLat * dLat) + (dLng * dLng));
  }

  static double _polylineLength(List<_LatLngPoint> points) {
    if (points.length < 2) {
      return 0;
    }
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += _distanceBetweenPoints(points[i - 1], points[i]);
    }
    return length;
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

class _ResolvedRoutePolyline {
  const _ResolvedRoutePolyline({
    this.points,
    this.sourceId,
    this.isDirectFallback = false,
  });

  final List<Map<String, double>>? points;
  final String? sourceId;
  final bool isDirectFallback;

  bool get isUsableForPhaseFallback =>
      !isDirectFallback && points != null && points!.length >= 2;
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
