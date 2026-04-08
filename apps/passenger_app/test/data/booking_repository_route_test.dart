import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('BookingRepository route polyline snapshot', () {
    test('snapshots a polyline segment from polylines path', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('polylines').doc('melaka_river_main').set({
        'name': 'Melaka River Main',
        'path': const [
          {'lat': 0.0, 'lng': 100.0},
          {'lat': 1.0, 'lng': 100.0},
          {'lat': 2.0, 'lng': 100.0},
          {'lat': 3.0, 'lng': 100.0},
        ],
      });

      final repo = BookingRepository(firestore: firestore);
      final bookingId = await repo.createBooking(
        _params(
          originLat: 0.2,
          originLng: 100.0,
          destinationLat: 2.7,
          destinationLng: 100.0,
        ),
      );

      final bookingDoc = await firestore
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .get();
      final data = bookingDoc.data();

      expect(data, isNotNull);
      expect(data![BookingFields.routePolylineId], 'melaka_river_main');
      expect(data[BookingFields.routePolyline], isNull);

      final hydrated = await repo.streamBooking(bookingId).firstWhere(
        (booking) => booking != null,
      );
      expect(hydrated, isNotNull);
      expect(hydrated!.routePolylineId, 'melaka_river_main');
      expect(hydrated.routePolyline, hasLength(4));

      expect(hydrated.routePolyline.first.lat, closeTo(0.0, 0.000001));
      expect(hydrated.routePolyline.first.lng, closeTo(100.0, 0.000001));
      expect(hydrated.routePolyline.last.lat, closeTo(3.0, 0.000001));
      expect(hydrated.routePolyline.last.lng, closeTo(100.0, 0.000001));
    });

    test(
      'falls back to direct route when no polyline documents exist',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = BookingRepository(firestore: firestore);

        final bookingId = await repo.createBooking(
          _params(
            originLat: 2.1984,
            originLng: 102.2470,
            destinationLat: 2.2130,
            destinationLng: 102.2485,
          ),
        );

        final bookingDoc = await firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .get();
        final data = bookingDoc.data();

        expect(data, isNotNull);
        expect(data![BookingFields.routePolylineId], isNull);

        final hydrated = await repo.streamBooking(bookingId).firstWhere(
          (booking) => booking != null,
        );
        expect(hydrated, isNotNull);
        expect(hydrated!.routePolyline, hasLength(2));

        expect(hydrated.routePolyline.first.lat, closeTo(2.1984, 0.000001));
        expect(hydrated.routePolyline.first.lng, closeTo(102.2470, 0.000001));
        expect(hydrated.routePolyline.last.lat, closeTo(2.2130, 0.000001));
        expect(hydrated.routePolyline.last.lng, closeTo(102.2485, 0.000001));
      },
    );

    test('parses nested coordinate path formats', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('polylines').doc('route_nested').set({
        'path': {
          'coordinates': const [
            {'lat': 2.2000, 'lng': 102.2500},
            {'lat': 2.2010, 'lng': 102.2510},
            {'lat': 2.2020, 'lng': 102.2520},
          ],
        },
      });

      final repo = BookingRepository(firestore: firestore);
      final bookingId = await repo.createBooking(
        _params(
          originLat: 2.2002,
          originLng: 102.2502,
          destinationLat: 2.2018,
          destinationLng: 102.2518,
        ),
      );

      final bookingDoc = await firestore
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .get();
      final data = bookingDoc.data();

      expect(data, isNotNull);
      expect(data![BookingFields.routePolylineId], 'route_nested');

      final hydrated = await repo.streamBooking(bookingId).firstWhere(
        (booking) => booking != null,
      );
      expect(hydrated, isNotNull);
      expect(hydrated!.routePolyline, hasLength(3));
    });

    test('records cancellation status history', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = BookingRepository(firestore: firestore);

      final bookingId = await repo.createBooking(
        _params(
          originLat: 2.1984,
          originLng: 102.2470,
          destinationLat: 2.2130,
          destinationLng: 102.2485,
        ),
      );

      await repo.cancelBooking(bookingId);

      final historySnap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .collection(BookingSubcollections.statusHistory)
          .get();

      expect(historySnap.docs, hasLength(1));
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.from],
        BookingStatus.pending.firestoreValue,
      );
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.to],
        BookingStatus.cancelled.firestoreValue,
      );
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.changedBy],
        'user-1',
      );

      final archiveSnap = await firestore
          .collection(FirestoreCollections.bookingsArchive)
          .doc(bookingId)
          .get();

      expect(archiveSnap.exists, isTrue);
      expect(
        archiveSnap.data()?[BookingFields.status],
        BookingStatus.cancelled.firestoreValue,
      );
      expect(
        archiveSnap.data()?[BookingFields.cancelledAt],
        isNotNull,
      );
      expect(archiveSnap.data()?["archivedStatus"], BookingStatus.cancelled.firestoreValue);
    });
  });
}

BookingCreationParams _params({
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
}) {
  return BookingCreationParams(
    userId: 'user-1',
    userName: 'Test Passenger',
    userPhone: '0123456789',
    origin: 'Jetty A',
    destination: 'Jetty B',
    originJettyId: 'jetty-a',
    destinationJettyId: 'jetty-b',
    originLat: originLat,
    originLng: originLng,
    destinationLat: destinationLat,
    destinationLng: destinationLng,
    adultCount: 1,
    childCount: 0,
    totalFare: 10.0,
    paymentMethod: 'stripe_payment_sheet',
    fareSnapshotId: 'fare-route-1',
  );
}
