import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('OperatorRepository', () {
    test('setOnlineStatus updates only operator presence document', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OperatorRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.operators)
          .doc('operator-1')
          .set({
            OperatorFields.operatorId: 'OP-1',
            OperatorFields.name: 'Captain Aiman',
            OperatorFields.email: 'captain@example.com',
            OperatorFields.isOnline: false,
          });

      await repository.setOnlineStatus('operator-1', isOnline: true);

      final operatorSnap = await firestore
          .collection(FirestoreCollections.operators)
          .doc('operator-1')
          .get();
      final presenceSnap = await firestore
          .collection(FirestoreCollections.operatorPresence)
          .doc('operator-1')
          .get();

      expect(operatorSnap.data()?[OperatorFields.isOnline], isFalse);
      expect(presenceSnap.data()?[OperatorPresenceFields.isOnline], isTrue);
    });
  });

  group('BookingRepository', () {
    test('acceptBooking preserves existing route polyline', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-1')
          .set({
            BookingFields.bookingId: 'booking-bind-1',
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Jetty A',
            BookingFields.destination: 'Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.pending.firestoreValue,
            BookingFields.operatorId: null,
            BookingFields.routePolyline: const [
              {'lat': 2.2, 'lng': 102.2},
              {'lat': 2.3, 'lng': 102.3},
            ],
            BookingFields.createdAt: Timestamp.now(),
            BookingFields.updatedAt: Timestamp.now(),
          });

      final result = await repository.acceptBooking(
        bookingId: 'booking-bind-1',
        operatorId: 'operator-1',
      );

      final bookingSnap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-1')
          .get();

      expect(result, isA<OperationSuccess>());
      expect(bookingSnap.data()?[BookingFields.status], 'accepted');
      expect(
        bookingSnap.data()?[BookingFields.routePolyline],
        equals(const [
          {'lat': 2.2, 'lng': 102.2},
          {'lat': 2.3, 'lng': 102.3},
        ]),
      );

      final historySnap = await bookingSnap.reference
          .collection(BookingSubcollections.statusHistory)
          .get();
      expect(historySnap.docs, hasLength(1));
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.from],
        BookingStatus.pending.firestoreValue,
      );
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.to],
        BookingStatus.accepted.firestoreValue,
      );
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.changedBy],
        'operator-1',
      );
    });

    test('acceptBooking succeeds without optional route config', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-2')
          .set({
            BookingFields.bookingId: 'booking-bind-2',
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Unknown Jetty A',
            BookingFields.destination: 'Unknown Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.pending.firestoreValue,
            BookingFields.operatorId: null,
            BookingFields.createdAt: Timestamp.now(),
            BookingFields.updatedAt: Timestamp.now(),
          });

      final result = await repository.acceptBooking(
        bookingId: 'booking-bind-2',
        operatorId: 'operator-1',
      );

      final bookingSnap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-2')
          .get();

      expect(result, isA<OperationSuccess>());
      expect(bookingSnap.data()?[BookingFields.status], 'accepted');
    });

    test(
      'acceptBooking does not depend on unrelated config documents',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore.collection('misc').doc('config').set({'value': 'noop'});

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-bind-3')
            .set({
              BookingFields.bookingId: 'booking-bind-3',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.operatorId: null,
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final result = await repository.acceptBooking(
          bookingId: 'booking-bind-3',
          operatorId: 'operator-1',
        );

        final bookingSnap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-bind-3')
            .get();

        expect(result, isA<OperationSuccess>());
        expect(bookingSnap.data()?[BookingFields.status], 'accepted');
      },
    );

    test(
      'rejectBooking uses operator presence to fully reject booking',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore
            .collection(FirestoreCollections.operatorPresence)
            .doc('operator-1')
            .set({
              OperatorPresenceFields.isOnline: true,
              OperatorPresenceFields.updatedAt: Timestamp.now(),
            });

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-1')
            .set({
              BookingFields.bookingId: 'booking-1',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.operatorId: null,
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final result = await repository.rejectBooking(
          bookingId: 'booking-1',
          operatorId: 'operator-1',
        );

        final bookingSnap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-1')
            .get();

        expect(result, isA<OperationSuccess>());
        expect(
          bookingSnap.data()?[BookingFields.status],
          BookingStatus.rejected.firestoreValue,
        );
        expect(bookingSnap.data()?[BookingFields.rejectedBy], ['operator-1']);
      },
    );
  });
}
