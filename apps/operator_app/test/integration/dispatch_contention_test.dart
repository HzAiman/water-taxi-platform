import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('Dispatch contention reliability', () {
    test(
      'concurrent accepts preserve a consistent claimed booking state',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = BookingRepository(firestore: firestore);
        const bookingId = 'booking-race-accept-1';

        await _seedPendingBooking(
          firestore,
          bookingId: bookingId,
          userId: 'user-race-1',
        );

        final results = await Future.wait([
          repo.acceptBooking(bookingId: bookingId, operatorId: 'operator-A'),
          repo.acceptBooking(bookingId: bookingId, operatorId: 'operator-B'),
        ]);

        expect(results, hasLength(2));

        final snap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .get();

        final data = snap.data()!;
        expect(
          data[BookingFields.status],
          BookingStatus.accepted.firestoreValue,
        );
        expect(
          data[BookingFields.operatorId],
          anyOf('operator-A', 'operator-B'),
        );
      },
    );

    test(
      'all online operators rejecting transitions booking to rejected',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = BookingRepository(firestore: firestore);
        const bookingId = 'booking-race-reject-1';

        await _seedPendingBooking(
          firestore,
          bookingId: bookingId,
          userId: 'user-race-2',
        );
        await _seedOperatorPresence(firestore, 'operator-A', isOnline: true);
        await _seedOperatorPresence(firestore, 'operator-B', isOnline: true);

        await repo.rejectBooking(
          bookingId: bookingId,
          operatorId: 'operator-A',
        );
        await repo.rejectBooking(
          bookingId: bookingId,
          operatorId: 'operator-B',
        );

        final snap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .get();
        final data = snap.data()!;

        expect(
          data[BookingFields.status],
          BookingStatus.rejected.firestoreValue,
        );
        expect(
          (data[BookingFields.rejectedBy] as List).cast<String>(),
          containsAll(['operator-A', 'operator-B']),
        );
      },
    );

    test('accept fails when booking is cancelled mid-dispatch', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = BookingRepository(firestore: firestore);
      const bookingId = 'booking-race-cancel-1';

      await _seedPendingBooking(
        firestore,
        bookingId: bookingId,
        userId: 'user-race-3',
      );

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .update({
            BookingFields.status: BookingStatus.cancelled.firestoreValue,
            BookingFields.updatedAt: FieldValue.serverTimestamp(),
            BookingFields.cancelledAt: FieldValue.serverTimestamp(),
          });

      final result = await repo.acceptBooking(
        bookingId: bookingId,
        operatorId: 'operator-A',
      );

      expect(result, isA<OperationFailure>());
      final failure = result as OperationFailure;
      expect(failure.isInfo, isTrue);
      expect(failure.message, contains('no longer pending'));
    });

    test('released booking can be claimed by another operator only', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = BookingRepository(firestore: firestore);
      const bookingId = 'booking-race-release-1';

      await _seedPendingBooking(
        firestore,
        bookingId: bookingId,
        userId: 'user-race-4',
      );

      final acceptA = await repo.acceptBooking(
        bookingId: bookingId,
        operatorId: 'operator-A',
      );
      expect(acceptA, isA<OperationSuccess>());

      final releaseA = await repo.releaseBooking(
        bookingId: bookingId,
        operatorId: 'operator-A',
      );
      expect(releaseA, isA<OperationSuccess>());

      final reacceptA = await repo.acceptBooking(
        bookingId: bookingId,
        operatorId: 'operator-A',
      );
      expect(reacceptA, isA<OperationFailure>());
      expect((reacceptA as OperationFailure).message, contains('already rejected'));

      final acceptB = await repo.acceptBooking(
        bookingId: bookingId,
        operatorId: 'operator-B',
      );
      expect(acceptB, isA<OperationSuccess>());

      final snap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .get();
      final data = snap.data()!;

      expect(data[BookingFields.status], BookingStatus.accepted.firestoreValue);
      expect(data[BookingFields.operatorId], 'operator-B');
      expect(
        (data[BookingFields.rejectedBy] as List).cast<String>(),
        contains('operator-A'),
      );
    });
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
    BookingFields.adultCount: 1,
    BookingFields.childCount: 0,
    BookingFields.passengerCount: 1,
    BookingFields.adultFare: 12.0,
    BookingFields.childFare: 6.0,
    BookingFields.adultSubtotal: 12.0,
    BookingFields.childSubtotal: 0.0,
    BookingFields.fare: 12.0,
    BookingFields.totalFare: 12.0,
    BookingFields.paymentMethod: PaymentMethods.creditCard,
    BookingFields.paymentStatus: 'paid',
    BookingFields.status: BookingStatus.pending.firestoreValue,
    BookingFields.operatorId: null,
    BookingFields.rejectedBy: <String>[],
    BookingFields.createdAt: Timestamp.now(),
    BookingFields.updatedAt: Timestamp.now(),
  });
}

Future<void> _seedOperatorPresence(
  FirebaseFirestore firestore,
  String operatorId, {
  required bool isOnline,
}) async {
  await firestore
      .collection(FirestoreCollections.operatorPresence)
      .doc(operatorId)
      .set({
        OperatorPresenceFields.isOnline: isOnline,
        OperatorPresenceFields.updatedAt: Timestamp.now(),
      });
}
