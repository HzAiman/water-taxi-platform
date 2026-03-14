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
        .where(BookingFields.driverId, isEqualTo: operatorId)
        .limit(50)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final active = snap.docs
          .map((d) => _fromDoc(d.id, d.data()))
          .where((b) =>
              b.status == BookingStatus.accepted ||
              b.status == BookingStatus.onTheWay)
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
        .where(BookingFields.status, isEqualTo: BookingStatus.pending.firestoreValue)
        .limit(100)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final pending = snap.docs
          .map((d) => _fromDoc(d.id, d.data()))
          .where((b) => b.driverId == null || b.driverId!.isEmpty)
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

  // ── Transactions ─────────────────────────────────────────────────────────

  /// Atomically accepts a pending booking. Returns an [OperationResult].
  Future<OperationResult> acceptBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _db.collection(FirestoreCollections.bookings).doc(bookingId);
        final snap = await tx.get(ref);

        if (!snap.exists) throw StateError('This booking no longer exists.');

        final data = snap.data()!;
        final status = BookingStatus.fromString(
          (data[BookingFields.status] ?? '').toString(),
        );
        final driverId = (data[BookingFields.driverId] ?? '').toString();
        final rejectedBy = _strList(data[BookingFields.rejectedBy]);

        if (status != BookingStatus.pending) {
          throw StateError('This booking is no longer pending.');
        }
        if (driverId.isNotEmpty) {
          throw StateError('This booking was already assigned to another operator.');
        }
        if (rejectedBy.contains(operatorId)) {
          throw StateError('You already rejected this booking.');
        }

        tx.update(ref, {
          BookingFields.status: BookingStatus.accepted.firestoreValue,
          BookingFields.driverId: operatorId,
          BookingFields.updatedAt: FieldValue.serverTimestamp(),
        });
      });

      return const OperationSuccess('Booking accepted successfully.');
    } on StateError catch (e) {
      return OperationFailure('Unable to accept booking', e.message, isInfo: true);
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
        final ref = _db.collection(FirestoreCollections.bookings).doc(bookingId);
        final snap = await tx.get(ref);

        if (!snap.exists) throw StateError('This booking no longer exists.');

        final data = snap.data()!;
        final status = BookingStatus.fromString(
          (data[BookingFields.status] ?? '').toString(),
        );
        final driverId = (data[BookingFields.driverId] ?? '').toString();
        final rejectedBy = _strList(data[BookingFields.rejectedBy]);

        if (status != BookingStatus.pending || driverId.isNotEmpty) {
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
      return OperationFailure('Unable to reject booking', e.message, isInfo: true);
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
      await _runWithRetry(() => _db.runTransaction((tx) async {
            final ref =
                _db.collection(FirestoreCollections.bookings).doc(bookingId);
            final snap = await tx.get(ref);

            if (!snap.exists) throw StateError('This booking no longer exists.');

            final data = snap.data()!;
            final status = BookingStatus.fromString(
              (data[BookingFields.status] ?? '').toString(),
            );
            final driverId = (data[BookingFields.driverId] ?? '').toString();
            final rejectedBy = _strList(data[BookingFields.rejectedBy]);

            if (status != BookingStatus.accepted || driverId != operatorId) {
              throw StateError('Only your accepted booking can be released.');
            }

            tx.update(ref, {
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.driverId: null,
              BookingFields.rejectedBy: {...rejectedBy, operatorId}.toList(),
              BookingFields.updatedAt: FieldValue.serverTimestamp(),
            });
          }));

      return const OperationSuccess('Booking released back to the queue.');
    } on StateError catch (e) {
      return OperationFailure('Unable to release booking', e.message, isInfo: true);
    } catch (e) {
      return OperationFailure('Release failed', 'Could not release booking: $e');
    }
  }

  /// Updates the booking status to `on_the_way` (start trip).
  Future<OperationResult> startTrip({
    required String bookingId,
    required String operatorId,
  }) =>
      _updateStatus(
        bookingId: bookingId,
        status: BookingStatus.onTheWay,
        operatorId: operatorId,
      );

  /// Updates the booking status to `completed`.
  Future<OperationResult> completeTrip({
    required String bookingId,
    required String operatorId,
  }) =>
      _updateStatus(
        bookingId: bookingId,
        status: BookingStatus.completed,
        operatorId: operatorId,
      );

  // ── Batch operations ─────────────────────────────────────────────────────

  /// Releases all accepted bookings for [operatorId] (called when going
  /// offline). Returns the count of bookings released.
  Future<int> releaseAllAcceptedBookings(String operatorId) async {
    final snap = await _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.driverId, isEqualTo: operatorId)
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
      await _runWithRetry(() => doc.reference.update({
            BookingFields.status: BookingStatus.pending.firestoreValue,
            BookingFields.driverId: null,
            BookingFields.rejectedBy: {...rejectedBy, operatorId}.toList(),
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
          }));
    }

    return accepted.length;
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<OperationResult> _updateStatus({
    required String bookingId,
    required BookingStatus status,
    required String operatorId,
  }) async {
    try {
      await _runWithRetry(() => _db
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .update({
        BookingFields.status: status.firestoreValue,
        BookingFields.driverId: operatorId,
        BookingFields.updatedAt: FieldValue.serverTimestamp(),
      }));

      final label = status == BookingStatus.onTheWay ? 'started' : 'completed';
      return OperationSuccess('Trip $label successfully.');
    } catch (e) {
      return OperationFailure('Update failed', 'Could not update booking: $e');
    }
  }

  Future<Set<String>> _loadOnlineOperatorIds() async {
    final snap = await _db
        .collection(FirestoreCollections.operators)
        .where(OperatorFields.isOnline, isEqualTo: true)
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
        final retryable = e.code == 'unavailable' ||
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
    final createdAt = (data[BookingFields.createdAt] as Timestamp?)?.toDate();
    final updatedAt = (data[BookingFields.updatedAt] as Timestamp?)?.toDate();
    final cancelledAt =
        (data[BookingFields.cancelledAt] as Timestamp?)?.toDate();

    if (data[BookingFields.bookingId] == null) {
      data = {...data, BookingFields.bookingId: id};
    }

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
}
