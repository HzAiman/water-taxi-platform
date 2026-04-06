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
      final polyline = data![BookingFields.routePolyline] as List<dynamic>;
      expect(polyline.length, greaterThanOrEqualTo(2));

      final first = polyline.first as Map<String, dynamic>;
      final last = polyline.last as Map<String, dynamic>;
      expect((first['lat'] as num).toDouble(), closeTo(0.2, 0.000001));
      expect((first['lng'] as num).toDouble(), closeTo(100.0, 0.000001));
      expect((last['lat'] as num).toDouble(), closeTo(2.7, 0.000001));
      expect((last['lng'] as num).toDouble(), closeTo(100.0, 0.000001));
    });

    test('falls back to direct route when no polyline documents exist', () async {
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
      final polyline = data![BookingFields.routePolyline] as List<dynamic>;
      expect(polyline, hasLength(2));

      final first = polyline.first as Map<String, dynamic>;
      final last = polyline.last as Map<String, dynamic>;
      expect((first['lat'] as num).toDouble(), closeTo(2.1984, 0.000001));
      expect((first['lng'] as num).toDouble(), closeTo(102.2470, 0.000001));
      expect((last['lat'] as num).toDouble(), closeTo(2.2130, 0.000001));
      expect((last['lng'] as num).toDouble(), closeTo(102.2485, 0.000001));
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
    originLat: originLat,
    originLng: originLng,
    destinationLat: destinationLat,
    destinationLng: destinationLng,
    adultCount: 1,
    childCount: 0,
    adultFare: 10.0,
    childFare: 5.0,
    paymentMethod: 'stripe_payment_sheet',
  );
}
