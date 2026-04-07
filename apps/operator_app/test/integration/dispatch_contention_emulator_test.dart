import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/firebase_options.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  final runEmulatorTests =
      Platform.environment['FIREBASE_EMULATOR_TESTS'] == '1';

  group('Dispatch contention (Firestore Emulator)', () {
    setUpAll(() async {
      if (!runEmulatorTests) return;

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final db = FirebaseFirestore.instance;
      db.useFirestoreEmulator('127.0.0.1', 8080);
      await db.disableNetwork();
      await db.enableNetwork();
    });

    test(
      'concurrent accepts allow only one operator to claim booking',
      () async {
        final db = FirebaseFirestore.instance;
        final repo = BookingRepository(firestore: db);
        const bookingId = 'booking-emulator-accept-1';

        await _seedPendingBooking(
          db,
          bookingId: bookingId,
          userId: 'user-em-1',
        );

        final results = await Future.wait([
          repo.acceptBooking(bookingId: bookingId, operatorId: 'operator-A'),
          repo.acceptBooking(bookingId: bookingId, operatorId: 'operator-B'),
        ]);

        final successCount = results.whereType<OperationSuccess>().length;
        final infoFailureCount = results
            .whereType<OperationFailure>()
            .where((f) => f.isInfo)
            .length;

        expect(successCount, 1);
        expect(infoFailureCount, 1);

        final snap = await db
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
      skip: !runEmulatorTests,
    );

    test(
      'all online operators rejecting transitions booking to rejected',
      () async {
        final db = FirebaseFirestore.instance;
        final repo = BookingRepository(firestore: db);
        const bookingId = 'booking-emulator-reject-1';

        await _seedPendingBooking(
          db,
          bookingId: bookingId,
          userId: 'user-em-2',
        );
        await _seedOperatorPresence(db, 'operator-A', isOnline: true);
        await _seedOperatorPresence(db, 'operator-B', isOnline: true);

        await repo.rejectBooking(
          bookingId: bookingId,
          operatorId: 'operator-A',
        );
        await repo.rejectBooking(
          bookingId: bookingId,
          operatorId: 'operator-B',
        );

        final snap = await db
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
      skip: !runEmulatorTests,
    );

    test(
      'accept booking recovers after temporary offline period',
      () async {
        final db = FirebaseFirestore.instance;
        final repo = BookingRepository(firestore: db);
        const bookingId = 'booking-emulator-network-1';

        await _seedPendingBooking(
          db,
          bookingId: bookingId,
          userId: 'user-em-3',
        );

        await db.disableNetwork();
        final offlineResult = await repo
            .acceptBooking(bookingId: bookingId, operatorId: 'operator-A')
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => const OperationFailure(
                'Network timeout',
                'Timed out while offline.',
              ),
            );

        await db.enableNetwork();
        final onlineResult = await repo.acceptBooking(
          bookingId: bookingId,
          operatorId: 'operator-A',
        );

        expect(offlineResult, isA<OperationFailure>());
        expect(onlineResult, isA<OperationSuccess>());

        final snap = await db
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .get();
        final data = snap.data()!;
        expect(
          data[BookingFields.status],
          BookingStatus.accepted.firestoreValue,
        );
        expect(data[BookingFields.operatorId], 'operator-A');
      },
      skip: !runEmulatorTests,
    );
  });
}

Future<void> _seedPendingBooking(
  FirebaseFirestore db, {
  required String bookingId,
  required String userId,
}) async {
  await db.collection(FirestoreCollections.bookings).doc(bookingId).set({
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
    BookingFields.totalFare: 12.0,
    BookingFields.fareSnapshotId: 'fare-snapshot-test',
    BookingFields.paymentMethod: PaymentMethods.creditCard,
    BookingFields.paymentStatus: 'paid',
    BookingFields.status: BookingStatus.pending.firestoreValue,
    BookingFields.operatorId: null,
    BookingFields.rejectedBy: <String>[],
    BookingFields.createdAt: FieldValue.serverTimestamp(),
    BookingFields.updatedAt: FieldValue.serverTimestamp(),
  });
}

Future<void> _seedOperatorPresence(
  FirebaseFirestore db,
  String operatorId, {
  required bool isOnline,
}) async {
  await db
      .collection(FirestoreCollections.operatorPresence)
      .doc(operatorId)
      .set({
        OperatorPresenceFields.isOnline: isOnline,
        OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
      });
}
