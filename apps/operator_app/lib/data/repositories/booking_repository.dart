import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:operator_app/core/services/firebase_session_service.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `bookings` Firestore collection (operator side).
///
/// All write operations that can race (accept, reject, release) use Firestore
/// transactions. Start and complete use a lightweight retry wrapper.
class BookingRepository {
  BookingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions,
       _useCallableBackend = firestore == null || functions != null;

  final FirebaseFirestore _db;
  final FirebaseFunctions? _functions;
  final bool _useCallableBackend;
  List<_PolylineSource>? _cachedPolylineSources;
  DateTime? _cachedPolylineSourcesAt;

  FirebaseFunctions get _callableFunctions =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  static const Duration _acceptCallableTimeout = Duration(seconds: 15);
  static const Duration _stopCallableTimeout = Duration(seconds: 12);
  static const Duration _rejectCallableTimeout = Duration(seconds: 12);

  // ── Streams ──────────────────────────────────────────────────────────────

  /// Streams bookings currently assigned to [operatorId] (accepted or
  /// on_the_way), ordered by backend route-aware pool sequence.
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
                ..sort(_compareActiveBookingSequence);
          return active;
        });
  }

  Future<BookingModel?> getBooking(String bookingId) async {
    final snap = await _db
        .collection(FirestoreCollections.bookings)
        .doc(bookingId)
        .get();
    final data = snap.data();
    if (!snap.exists || data == null) {
      return null;
    }
    return _fromDoc(snap.id, data);
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
        .orderBy(BookingFields.createdAt)
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
    double? operatorLat,
    double? operatorLng,
    DateTime? locationUpdatedAt,
    String? routeDirection,
  }) async {
    if (!_useCallableBackend) {
      return _acceptBookingDirect(
        bookingId: bookingId,
        operatorId: operatorId,
        operatorLat: operatorLat,
        operatorLng: operatorLng,
        locationUpdatedAt: locationUpdatedAt,
        routeDirection: routeDirection,
      );
    }

    try {
      return await FirebaseSessionService.runWithFreshToken(() async {
        final callable = _callableFunctions.httpsCallable(
          'acceptPooledBooking',
        );
        final result = await callable
            .call(<String, dynamic>{
              'bookingId': bookingId,
              if (operatorLat != null) 'operatorLat': operatorLat,
              if (operatorLng != null) 'operatorLng': operatorLng,
              if (locationUpdatedAt != null)
                'locationUpdatedAt': locationUpdatedAt.toIso8601String(),
              if (routeDirection != null) 'routeDirection': routeDirection,
            })
            .timeout(_acceptCallableTimeout);
        final data = result.data is Map ? result.data as Map : const {};
        final status = data['status']?.toString().trim();
        final message = data['message']?.toString().trim();
        if (status == 'deferred') {
          return OperationFailure(
            'Queued for later route',
            message != null && message.isNotEmpty
                ? message
                : 'This request is queued for a later route sweep.',
            isInfo: true,
          );
        }
        return OperationSuccess(
          message != null && message.isNotEmpty
              ? message
              : 'Booking accepted successfully.',
        );
      });
    } on FirebaseFunctionsException catch (e) {
      final message = e.message ?? '';
      return OperationFailure(
        _acceptFailureTitle(message),
        _acceptFailureMessage(message),
        isInfo:
            e.code == 'failed-precondition' ||
            e.code == 'unimplemented' ||
            e.code == 'not-found' ||
            e.code == 'unavailable',
      );
    } on TimeoutException {
      return const OperationFailure(
        'Connection is slow',
        'Accepting this booking is taking too long. Refresh and try again.',
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Accept failed', 'Could not accept booking: $e');
    }
  }

  /// Rejects a pending pooled booking through the backend callable.
  Future<OperationResult> rejectBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    if (!_useCallableBackend) {
      return _rejectBookingDirect(bookingId: bookingId, operatorId: operatorId);
    }

    try {
      return await FirebaseSessionService.runWithFreshToken(() async {
        final callable = _callableFunctions.httpsCallable(
          'rejectPooledBooking',
        );

        final result = await callable
            .call(<String, dynamic>{'bookingId': bookingId})
            .timeout(_rejectCallableTimeout);
        final data = result.data is Map ? result.data as Map : const {};
        final message = data['message']?.toString().trim();
        return OperationSuccess(
          message != null && message.isNotEmpty
              ? message
              : 'Booking rejected. It stays pending for other operators.',
        );
      });
    } on FirebaseFunctionsException catch (e) {
      final message = e.message ?? '';
      return OperationFailure(
        'Unable to reject booking',
        message.isNotEmpty ? message : 'Could not reject this booking.',
        isInfo:
            e.code == 'failed-precondition' ||
            e.code == 'not-found' ||
            e.code == 'unavailable',
      );
    } on TimeoutException {
      return const OperationFailure(
        'Connection is slow',
        'Rejecting this booking is taking too long. Refresh and try again.',
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
      await _runWithFreshTokenIfNeeded(() {
        return _runWithRetry(
          () => _db.runTransaction((tx) async {
            final ref = _db
                .collection(FirestoreCollections.bookings)
                .doc(bookingId);
            final snap = await tx.get(ref);

            if (!snap.exists) {
              throw StateError('This booking no longer exists.');
            }

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
      });

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
  }) async {
    if (!_useCallableBackend) {
      return _startTripDirect(
        bookingId: bookingId,
        operatorId: operatorId,
        operatorLat: operatorLat,
        operatorLng: operatorLng,
      );
    }

    try {
      return await FirebaseSessionService.runWithFreshToken(() async {
        final callable = _callableFunctions.httpsCallable('startPooledBooking');
        final result = await callable
            .call(<String, dynamic>{
              'bookingId': bookingId,
              if (operatorLat != null) 'operatorLat': operatorLat,
              if (operatorLng != null) 'operatorLng': operatorLng,
            })
            .timeout(_stopCallableTimeout);
        final data = result.data is Map ? result.data as Map : const {};
        final startedBookingId = data['startedBookingId']?.toString().trim();
        final successData = Map<String, Object?>.from(
          data.cast<String, Object?>(),
        );
        if (startedBookingId != null &&
            startedBookingId.isNotEmpty &&
            startedBookingId != bookingId) {
          return OperationSuccess(
            'Route started at the first pool stop.',
            data: successData,
          );
        }
        return OperationSuccess(
          'Route started successfully.',
          data: successData,
        );
      });
    } on FirebaseFunctionsException catch (e) {
      return OperationFailure(
        'Unable to start trip',
        e.message ??
            'Backend trip sequencing is unavailable. Please refresh and try again.',
        isInfo:
            e.code == 'failed-precondition' ||
            e.code == 'unimplemented' ||
            e.code == 'not-found' ||
            e.code == 'unavailable',
      );
    } on TimeoutException {
      return const OperationFailure(
        'Connection is slow',
        'Starting this route is taking too long. Refresh and try again.',
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Start failed', 'Could not start trip: $e');
    }
  }

  /// Marks that the passenger has been picked up while trip remains
  /// `on_the_way`.
  Future<OperationResult> markPassengerPickedUp({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) async {
    if (!_useCallableBackend) {
      return _markPassengerPickedUpDirect(
        bookingId: bookingId,
        operatorId: operatorId,
        operatorLat: operatorLat,
        operatorLng: operatorLng,
      );
    }

    try {
      await FirebaseSessionService.runWithFreshToken(() async {
        final callable = _callableFunctions.httpsCallable(
          'markPoolStopReached',
        );
        await callable
            .call(<String, dynamic>{
              'bookingId': bookingId,
              if (operatorLat != null) 'operatorLat': operatorLat,
              if (operatorLng != null) 'operatorLng': operatorLng,
            })
            .timeout(_stopCallableTimeout);
      });
      return const OperationSuccess('Pool stop completed.');
    } on FirebaseFunctionsException catch (e) {
      return OperationFailure(
        'Unable to complete stop',
        e.message ??
            'Backend pool stop validation is unavailable. Please refresh and try again.',
        isInfo:
            e.code == 'failed-precondition' ||
            e.code == 'unimplemented' ||
            e.code == 'not-found' ||
            e.code == 'unavailable',
      );
    } on TimeoutException {
      return const OperationFailure(
        'Connection is slow',
        'Completing this stop is taking too long. Refresh and try again.',
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Update failed', 'Could not complete stop: $e');
    }
  }

  /// Updates the booking status to `completed`.
  Future<OperationResult> completeTrip({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) async {
    if (!_useCallableBackend) {
      return _completeTripDirect(
        bookingId: bookingId,
        operatorId: operatorId,
        operatorLat: operatorLat,
        operatorLng: operatorLng,
      );
    }

    try {
      await FirebaseSessionService.runWithFreshToken(() async {
        final callable = _callableFunctions.httpsCallable(
          'markPoolStopReached',
        );
        await callable
            .call(<String, dynamic>{
              'bookingId': bookingId,
              if (operatorLat != null) 'operatorLat': operatorLat,
              if (operatorLng != null) 'operatorLng': operatorLng,
            })
            .timeout(_stopCallableTimeout);
      });
      return const OperationSuccess('Pool stop completed successfully.');
    } on FirebaseFunctionsException catch (e) {
      return OperationFailure(
        'Unable to complete stop',
        e.message ??
            'Backend pool stop validation is unavailable. Please refresh and try again.',
        isInfo:
            e.code == 'failed-precondition' ||
            e.code == 'unimplemented' ||
            e.code == 'not-found' ||
            e.code == 'unavailable',
      );
    } on TimeoutException {
      return const OperationFailure(
        'Connection is slow',
        'Completing this stop is taking too long. Refresh and try again.',
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Complete failed', 'Could not complete trip: $e');
    }
  }

  /// Publishes the operator's latest location for an active `on_the_way`
  /// booking so passengers can track in real time.
  Future<OperationResult> updateOperatorLocation({
    required String bookingId,
    required String operatorId,
    required double operatorLat,
    required double operatorLng,
  }) async {
    try {
      await _runWithFreshTokenIfNeeded(() {
        return _runWithRetry(() async {
          final bookingRef = _db
              .collection(FirestoreCollections.bookings)
              .doc(bookingId);
          final seedSnap = await bookingRef.get();
          final seedData = seedSnap.data();
          final poolGroupId = seedData?[BookingFields.poolGroupId]?.toString();
          final bookingRefs = <DocumentReference<Map<String, dynamic>>>[
            bookingRef,
          ];

          if (poolGroupId != null && poolGroupId.trim().isNotEmpty) {
            final pooledSnap = await _db
                .collection(FirestoreCollections.bookings)
                .where(BookingFields.operatorUid, isEqualTo: operatorId)
                .where(BookingFields.poolGroupId, isEqualTo: poolGroupId)
                .where(
                  BookingFields.status,
                  isEqualTo: BookingStatus.onTheWay.firestoreValue,
                )
                .get();
            bookingRefs
              ..clear()
              ..addAll(pooledSnap.docs.map((doc) => doc.reference));
            if (bookingRefs.isEmpty) {
              bookingRefs.add(bookingRef);
            }
          }

          final batch = _db.batch();
          for (final ref in bookingRefs) {
            batch.set(ref, {
              BookingFields.operatorLat: operatorLat,
              BookingFields.operatorLng: operatorLng,
              BookingFields.updatedAt: FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            batch.set(
              _db.collection(FirestoreCollections.tracking).doc(ref.id),
              {
                TrackingFields.bookingId: ref.id,
                TrackingFields.operatorUid: operatorId,
                TrackingFields.operatorLat: operatorLat,
                TrackingFields.operatorLng: operatorLng,
                TrackingFields.updatedAt: FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
          await batch.commit();
        });
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
    return _runWithFreshTokenIfNeeded(() async {
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
    });
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<OperationResult> _acceptBookingDirect({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
    DateTime? locationUpdatedAt,
    String? routeDirection,
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
          final status = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          final rejectedBy = _strList(data[BookingFields.rejectedBy]);
          if (status != BookingStatus.pending) {
            throw StateError('This booking is no longer pending.');
          }
          if (rejectedBy.contains(operatorId)) {
            throw StateError(
              'This booking was already rejected by this operator.',
            );
          }

          tx.update(ref, {
            BookingFields.status: BookingStatus.accepted.firestoreValue,
            BookingFields.operatorUid: operatorId,
            BookingFields.operatorId: operatorId,
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
            if (operatorLat != null) BookingFields.operatorLat: operatorLat,
            if (operatorLng != null) BookingFields.operatorLng: operatorLng,
            if (locationUpdatedAt != null)
              'locationUpdatedAt': Timestamp.fromDate(locationUpdatedAt),
            if (routeDirection != null)
              BookingFields.routeDirection: routeDirection,
          });

          _appendStatusHistory(
            tx: tx,
            ref: ref,
            from: status,
            to: BookingStatus.accepted,
            changedBy: operatorId,
          );
        }),
      );
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

  Future<OperationResult> _rejectBookingDirect({
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
          final status = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          if (status != BookingStatus.pending) {
            throw StateError('Only pending bookings can be rejected.');
          }

          final rejectedBy = {
            ..._strList(data[BookingFields.rejectedBy]),
            operatorId,
          };
          final onlineOperatorsSnap = await _db
              .collection(FirestoreCollections.operatorPresence)
              .where(OperatorPresenceFields.isOnline, isEqualTo: true)
              .get();
          final onlineOperators = onlineOperatorsSnap.docs
              .map((d) => d.id)
              .toSet();
          final allOnlineRejected =
              onlineOperators.isNotEmpty &&
              onlineOperators.difference(rejectedBy).isEmpty;

          tx.update(ref, {
            BookingFields.rejectedBy: rejectedBy.toList(),
            BookingFields.status: allOnlineRejected
                ? BookingStatus.rejected.firestoreValue
                : BookingStatus.pending.firestoreValue,
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
          });

          if (allOnlineRejected) {
            _appendStatusHistory(
              tx: tx,
              ref: ref,
              from: status,
              to: BookingStatus.rejected,
              changedBy: operatorId,
            );
          }
        }),
      );
      return const OperationSuccess('Booking rejected.');
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

  Future<OperationResult> _startTripDirect({
    required String bookingId,
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
          final status = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          if (status != BookingStatus.accepted ||
              _assignedOperatorUid(data) != operatorId) {
            throw StateError('Only your accepted booking can be started.');
          }

          tx.update(ref, {
            BookingFields.status: BookingStatus.onTheWay.firestoreValue,
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
            if (operatorLat != null) BookingFields.operatorLat: operatorLat,
            if (operatorLng != null) BookingFields.operatorLng: operatorLng,
          });

          _appendStatusHistory(
            tx: tx,
            ref: ref,
            from: status,
            to: BookingStatus.onTheWay,
            changedBy: operatorId,
          );
        }),
      );
      return const OperationSuccess('Route started successfully.');
    } on StateError catch (e) {
      return OperationFailure('Unable to start trip', e.message, isInfo: true);
    } catch (e) {
      return OperationFailure('Start failed', 'Could not start trip: $e');
    }
  }

  Future<OperationResult> _markPassengerPickedUpDirect({
    required String bookingId,
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
          final status = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          if (status != BookingStatus.onTheWay ||
              _assignedOperatorUid(data) != operatorId) {
            throw StateError('Only your active trip stop can be completed.');
          }

          tx.update(ref, {
            BookingFields.passengerPickedUpAt:
                data[BookingFields.passengerPickedUpAt] ??
                FieldValue.serverTimestamp(),
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
            if (operatorLat != null) BookingFields.operatorLat: operatorLat,
            if (operatorLng != null) BookingFields.operatorLng: operatorLng,
          });
        }),
      );
      return const OperationSuccess('Pool stop completed.');
    } on StateError catch (e) {
      return OperationFailure(
        'Unable to complete stop',
        e.message,
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Update failed', 'Could not complete stop: $e');
    }
  }

  Future<OperationResult> _completeTripDirect({
    required String bookingId,
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
          final archiveRef = _db
              .collection(FirestoreCollections.bookingsArchive)
              .doc(bookingId);
          final snap = await tx.get(ref);
          if (!snap.exists || snap.data() == null) {
            throw StateError('This booking no longer exists.');
          }

          final data = snap.data()!;
          final status = BookingStatus.fromString(
            (data[BookingFields.status] ?? '').toString(),
          );
          if (status != BookingStatus.onTheWay ||
              _assignedOperatorUid(data) != operatorId) {
            throw StateError('Only your active trip can be completed.');
          }

          final updates = <String, dynamic>{
            BookingFields.status: BookingStatus.completed.firestoreValue,
            BookingFields.completedAt: FieldValue.serverTimestamp(),
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
            if (operatorLat != null) BookingFields.operatorLat: operatorLat,
            if (operatorLng != null) BookingFields.operatorLng: operatorLng,
          };
          tx.update(ref, updates);
          tx.set(archiveRef, {
            ...data,
            ...updates,
            'archivedAt': FieldValue.serverTimestamp(),
            'archivedStatus': BookingStatus.completed.firestoreValue,
          }, SetOptions(merge: true));

          _appendStatusHistory(
            tx: tx,
            ref: ref,
            from: status,
            to: BookingStatus.completed,
            changedBy: operatorId,
          );
        }),
      );
      return const OperationSuccess('Pool stop completed successfully.');
    } on StateError catch (e) {
      return OperationFailure(
        'Unable to complete stop',
        e.message,
        isInfo: true,
      );
    } catch (e) {
      return OperationFailure('Complete failed', 'Could not complete trip: $e');
    }
  }

  Future<T> _runWithFreshTokenIfNeeded<T>(Future<T> Function() action) {
    if (_useCallableBackend) {
      return FirebaseSessionService.runWithFreshToken(action);
    }
    return action();
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

  static String _acceptFailureTitle(String message) {
    final text = message.toLowerCase();
    if (text.contains('maximum pooled booking limit')) {
      return 'Pool is full';
    }
    if (text.contains('later route') ||
        text.contains('reverse') ||
        text.contains('behind') ||
        text.contains('current route')) {
      return 'Queued for later route';
    }
    return 'Unable to accept booking';
  }

  static String _acceptFailureMessage(String message) {
    final text = message.toLowerCase();
    if (text.contains('maximum pooled booking limit')) {
      return 'This route already has the maximum number of active bookings.';
    }
    if (text.contains('later route') ||
        text.contains('reverse') ||
        text.contains('behind') ||
        text.contains('current route')) {
      return 'This request does not fit the current route sweep. It can be handled later.';
    }
    return message.isNotEmpty
        ? message
        : 'Backend booking assignment is unavailable. Please refresh and try again.';
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
    final createdAt = _dateTimeFromFirestoreValue(
      data[BookingFields.createdAt],
    );
    final updatedAt = _dateTimeFromFirestoreValue(
      data[BookingFields.updatedAt],
    );
    final cancelledAt = _dateTimeFromFirestoreValue(
      data[BookingFields.cancelledAt],
    );
    final passengerPickedUpAt = _dateTimeFromFirestoreValue(
      data[BookingFields.passengerPickedUpAt],
    );

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

  static DateTime? _dateTimeFromFirestoreValue(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
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
        final segment = _segmentFromRoutePolyline(data, polyline);
        return _ResolvedRoutePolyline(
          points: segment != null && segment.isNotEmpty ? segment : polyline,
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
      points: _extractSegment(bestMatch)
          .map((point) => <String, double>{'lat': point.lat, 'lng': point.lng})
          .toList(growable: false),
      sourceId: bestMatch.polylineId,
    );
  }

  List<Map<String, double>>? _segmentFromRoutePolyline(
    Map<String, dynamic> data,
    List<Map<String, double>> polyline,
  ) {
    final origin = data[BookingFields.originCoords] as GeoPoint?;
    final destination = data[BookingFields.destinationCoords] as GeoPoint?;
    if (origin == null || destination == null || polyline.length < 2) {
      return null;
    }

    final points = polyline
        .map((point) => _LatLngPoint(lat: point['lat']!, lng: point['lng']!))
        .toList(growable: false);
    final match = _PolylineMatch(
      polylineId: data[BookingFields.routePolylineId]?.toString() ?? '',
      polyline: points,
      start: _snapPointToPolyline(
        _LatLngPoint(lat: origin.latitude, lng: origin.longitude),
        points,
      ),
      end: _snapPointToPolyline(
        _LatLngPoint(lat: destination.latitude, lng: destination.longitude),
        points,
      ),
      score: 0,
    );
    final segment = _extractSegment(match);
    if (segment.length < 2) {
      return null;
    }
    return segment
        .map((point) => <String, double>{'lat': point.lat, 'lng': point.lng})
        .toList(growable: false);
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

  static int _compareActiveBookingSequence(BookingModel a, BookingModel b) {
    if (a.status == BookingStatus.onTheWay &&
        b.status != BookingStatus.onTheWay) {
      return -1;
    }
    if (b.status == BookingStatus.onTheWay &&
        a.status != BookingStatus.onTheWay) {
      return 1;
    }

    final aSeq = a.poolSequence;
    final bSeq = b.poolSequence;
    if (aSeq != null && bSeq != null && aSeq != bSeq) {
      return aSeq.compareTo(bSeq);
    }
    if (aSeq != null && bSeq == null) return -1;
    if (aSeq == null && bSeq != null) return 1;

    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
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
    return _haversineDistanceMeters(points.first, points.last) <= 25;
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

  static double _haversineDistanceMeters(_LatLngPoint a, _LatLngPoint b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(b.lat - a.lat);
    final dLng = _degreesToRadians(b.lng - a.lng);
    final lat1 = _degreesToRadians(a.lat);
    final lat2 = _degreesToRadians(b.lat);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final aa =
        sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;

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
