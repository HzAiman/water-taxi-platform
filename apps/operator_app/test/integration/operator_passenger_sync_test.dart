import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('Operator-passenger lifecycle sync', () {
    test(
      'operator lifecycle updates are reflected in tracking and final history',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = BookingRepository(firestore: firestore);
        const bookingId = 'booking-sync-1';

        await _seedPendingBooking(
          firestore,
          bookingId: bookingId,
          userId: 'user-1',
        );

        final trackingStatuses = <String>[];
        final trackingSub = firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .snapshots()
            .listen((snap) {
              final data = snap.data();
              if (data == null) return;
              trackingStatuses.add(
                (data[BookingFields.status] ?? '').toString(),
              );
            });

        await Future<void>.delayed(const Duration(milliseconds: 20));

        await repo.acceptBooking(
          bookingId: bookingId,
          operatorId: 'operator-1',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repo.startTrip(bookingId: bookingId, operatorId: 'operator-1');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await repo.completeTrip(bookingId: bookingId, operatorId: 'operator-1');

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await trackingSub.cancel();

        expect(
          trackingStatuses,
          containsAllInOrder([
            BookingStatus.pending.firestoreValue,
            BookingStatus.accepted.firestoreValue,
            BookingStatus.onTheWay.firestoreValue,
            BookingStatus.completed.firestoreValue,
          ]),
        );

        final historySnap = await firestore
            .collection(FirestoreCollections.bookings)
            .where(BookingFields.userId, isEqualTo: 'user-1')
            .get();
        final statuses = historySnap.docs
            .map((d) => (d.data()[BookingFields.status] ?? '').toString())
            .toList();
        expect(statuses, contains(BookingStatus.completed.firestoreValue));
      },
    );

    test(
      'en-route cancellation removes booking from operator active stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = BookingRepository(firestore: firestore);
        const bookingId = 'booking-cancel-edge-1';

        await _seedPendingBooking(
          firestore,
          bookingId: bookingId,
          userId: 'user-2',
        );

        final activeSnapshots = <List<String>>[];
        final activeSub = repo.streamActiveBookings('operator-1').listen((
          bookings,
        ) {
          activeSnapshots.add(bookings.map((b) => b.bookingId).toList());
        });

        await repo.acceptBooking(
          bookingId: bookingId,
          operatorId: 'operator-1',
        );
        await repo.startTrip(bookingId: bookingId, operatorId: 'operator-1');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .update({
              BookingFields.status: BookingStatus.cancelled.firestoreValue,
              BookingFields.updatedAt: FieldValue.serverTimestamp(),
              BookingFields.cancelledAt: FieldValue.serverTimestamp(),
            });

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await activeSub.cancel();

        final bookingSnap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .get();
        expect(
          bookingSnap.data()?[BookingFields.status],
          BookingStatus.cancelled.firestoreValue,
        );
        expect(activeSnapshots.last, isNot(contains(bookingId)));
      },
    );

    test(
      'integration flow covers accept start progression off-route recover complete',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = BookingRepository(firestore: firestore);
        const bookingId = 'booking-nav-flow-1';

        await _seedPendingBooking(
          firestore,
          bookingId: bookingId,
          userId: 'user-3',
        );

        final trackingStatuses = <String>[];
        final seenLng = <double>[];
        final trackingSub = firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .snapshots()
            .listen((snap) {
              final data = snap.data();
              if (data == null) return;
              trackingStatuses.add(
                (data[BookingFields.status] ?? '').toString(),
              );
              final lng = data[BookingFields.operatorLng];
              if (lng is num) {
                seenLng.add(lng.toDouble());
              }
            });

        await Future<void>.delayed(const Duration(milliseconds: 20));

        final accepted = await repo.acceptBooking(
          bookingId: bookingId,
          operatorId: 'operator-1',
        );
        expect(accepted, isA<OperationSuccess>());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final started = await repo.startTrip(
          bookingId: bookingId,
          operatorId: 'operator-1',
        );
        expect(started, isA<OperationSuccess>());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final progressed = await repo.updateOperatorLocation(
          bookingId: bookingId,
          operatorId: 'operator-1',
          operatorLat: 2.2010,
          operatorLng: 102.2510,
        );
        expect(progressed, isA<OperationSuccess>());

        final offRoute = await repo.updateOperatorLocation(
          bookingId: bookingId,
          operatorId: 'operator-1',
          operatorLat: 2.2010,
          operatorLng: 102.2550,
        );
        expect(offRoute, isA<OperationSuccess>());

        final recovered = await repo.updateOperatorLocation(
          bookingId: bookingId,
          operatorId: 'operator-1',
          operatorLat: 2.2020,
          operatorLng: 102.2520,
        );
        expect(recovered, isA<OperationSuccess>());

        final completed = await repo.completeTrip(
          bookingId: bookingId,
          operatorId: 'operator-1',
        );
        expect(completed, isA<OperationSuccess>());

        await Future<void>.delayed(const Duration(milliseconds: 40));
        await trackingSub.cancel();

        final bookingSnap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .get();
        final data = bookingSnap.data()!;

        expect(
          trackingStatuses,
          containsAllInOrder([
            BookingStatus.pending.firestoreValue,
            BookingStatus.accepted.firestoreValue,
            BookingStatus.onTheWay.firestoreValue,
            BookingStatus.completed.firestoreValue,
          ]),
        );
        expect(
          data[BookingFields.status],
          BookingStatus.completed.firestoreValue,
        );
        expect(seenLng.any((lng) => lng > 102.254), isTrue);
        expect(
          seenLng.any((lng) => lng >= 102.2515 && lng <= 102.2525),
          isTrue,
        );
      },
    );
  });
}

Future<void> _seedPendingBooking(
  FirebaseFirestore firestore, {
  required String bookingId,
  required String userId,
}) async {
  await firestore.collection(FirestoreCollections.bookings).doc(bookingId).set({
    BookingFields.bookingId: bookingId,
    BookingFields.userId: userId,
    BookingFields.userName: 'Passenger',
    BookingFields.userPhone: '0123456789',
    BookingFields.origin: 'Jetty A',
    BookingFields.destination: 'Jetty B',
    BookingFields.originCoords: const GeoPoint(2.2000, 102.2500),
    BookingFields.destinationCoords: const GeoPoint(2.2100, 102.2600),
    BookingFields.routePolyline: const [
      {'lat': 2.2000, 'lng': 102.2500},
      {'lat': 2.2010, 'lng': 102.2510},
      {'lat': 2.2020, 'lng': 102.2520},
      {'lat': 2.2030, 'lng': 102.2530},
    ],
    BookingFields.adultCount: 1,
    BookingFields.childCount: 0,
    BookingFields.passengerCount: 1,
    BookingFields.totalFare: 12.0,
    BookingFields.fareSnapshotId: 'fare-snapshot-test',
    BookingFields.paymentMethod: PaymentMethods.creditCard,
    BookingFields.paymentStatus: 'paid',
    BookingFields.status: BookingStatus.pending.firestoreValue,
    BookingFields.operatorId: null,
    BookingFields.rejectedBy: <String>[],
    BookingFields.createdAt: Timestamp.now(),
    BookingFields.updatedAt: Timestamp.now(),
  });
}
