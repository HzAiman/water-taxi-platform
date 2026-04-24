import 'package:flutter_test/flutter_test.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('BookingModel route parsing', () {
    test('fromMap parses route polyline points from mixed coordinate keys', () {
      final model = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-1',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'routePoints': const [
            {'latitude': 2.2000, 'longitude': 102.2500},
            {'lat': 2.2100, 'lng': 102.2600},
          ],
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'totalFare': 12.0,
          'fareSnapshotId': 'fare-snapshot-test',
          'paymentMethod': PaymentMethods.creditCard,
          'paymentStatus': 'paid',
          'status': BookingStatus.onTheWay.firestoreValue,
          'rejectedBy': const <String>[],
        },
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2100,
        destinationLng: 102.2600,
      );

      expect(model.routePolyline, hasLength(2));
      expect(model.routePolyline.first.lat, closeTo(2.2000, 0.0000001));
      expect(model.routePolyline.first.lng, closeTo(102.2500, 0.0000001));
    });

    test('fromMap ignores invalid route points', () {
      final model = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-2',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'routePoints': const [
            {'lat': null, 'lng': 102.2500},
            {'lat': 2.2100, 'lng': 102.2600},
          ],
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'totalFare': 12.0,
          'fareSnapshotId': 'fare-snapshot-test',
          'paymentMethod': PaymentMethods.creditCard,
          'paymentStatus': 'paid',
          'status': BookingStatus.pending.firestoreValue,
          'rejectedBy': const <String>[],
        },
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2100,
        destinationLng: 102.2600,
      );

      expect(model.routePolyline, hasLength(1));
      expect(model.routePolyline.first.lat, closeTo(2.2100, 0.0000001));
      expect(model.routePolyline.first.lng, closeTo(102.2600, 0.0000001));
    });

    test('fromMap parses phase-specific polylines from alias keys', () {
      final model = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-3',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'routePolyline': const [
            {'lat': 2.2000, 'lng': 102.2500},
            {'lat': 2.2100, 'lng': 102.2600},
          ],
          'pickupPathCoordinates': const [
            {'lat': 2.1990, 'lng': 102.2490},
            {'lat': 2.2000, 'lng': 102.2500},
          ],
          'dropoffPathCoordinates': const [
            {'lat': 2.2000, 'lng': 102.2500},
            {'lat': 2.2120, 'lng': 102.2620},
          ],
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'totalFare': 12.0,
          'fareSnapshotId': 'fare-snapshot-test',
          'paymentMethod': PaymentMethods.creditCard,
          'paymentStatus': 'paid',
          'status': BookingStatus.onTheWay.firestoreValue,
          'rejectedBy': const <String>[],
        },
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2100,
        destinationLng: 102.2600,
      );

      expect(model.routeToOriginPolyline, hasLength(2));
      expect(model.routeToDestinationPolyline, hasLength(2));
      expect(model.routeToOriginPolyline.first.lat, closeTo(2.1990, 0.0000001));
      expect(
        model.routeToDestinationPolyline.last.lng,
        closeTo(102.2620, 0.0000001),
      );
    });

    test('fromMap parses passengerPickedUpAt from string and epoch millis', () {
      final fromIso = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-4',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'totalFare': 12.0,
          'fareSnapshotId': 'fare-snapshot-test',
          'paymentMethod': PaymentMethods.creditCard,
          'paymentStatus': 'paid',
          'status': BookingStatus.onTheWay.firestoreValue,
          'rejectedBy': const <String>[],
          'passengerPickedUpAt': '2026-04-24T12:34:56.000Z',
        },
        originLat: 2.2,
        originLng: 102.25,
        destinationLat: 2.21,
        destinationLng: 102.26,
      );

      final fromEpoch = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-5',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'totalFare': 12.0,
          'fareSnapshotId': 'fare-snapshot-test',
          'paymentMethod': PaymentMethods.creditCard,
          'paymentStatus': 'paid',
          'status': BookingStatus.onTheWay.firestoreValue,
          'rejectedBy': const <String>[],
          'passengerPickedUpAt': 1713960000000,
        },
        originLat: 2.2,
        originLng: 102.25,
        destinationLat: 2.21,
        destinationLng: 102.26,
      );

      expect(fromIso.passengerPickedUpAt, isNotNull);
      expect(fromEpoch.passengerPickedUpAt, isNotNull);
      expect(
        fromEpoch.passengerPickedUpAt!.millisecondsSinceEpoch,
        1713960000000,
      );
    });

    test('copyWith propagates new phase route and pickup fields', () {
      final original = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-6',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'totalFare': 12.0,
          'fareSnapshotId': 'fare-snapshot-test',
          'paymentMethod': PaymentMethods.creditCard,
          'paymentStatus': 'paid',
          'status': BookingStatus.accepted.firestoreValue,
          'rejectedBy': const <String>[],
        },
        originLat: 2.2,
        originLng: 102.25,
        destinationLat: 2.21,
        destinationLng: 102.26,
      );

      final updated = original.copyWith(
        routeToOriginPolyline: const [
          BookingRoutePoint(lat: 2.19, lng: 102.24),
          BookingRoutePoint(lat: 2.2, lng: 102.25),
        ],
        routeToDestinationPolyline: const [
          BookingRoutePoint(lat: 2.2, lng: 102.25),
          BookingRoutePoint(lat: 2.22, lng: 102.27),
        ],
        passengerPickedUpAt: DateTime.utc(2026, 4, 24, 13, 0),
      );

      expect(updated.routeToOriginPolyline, hasLength(2));
      expect(updated.routeToDestinationPolyline, hasLength(2));
      expect(updated.passengerPickedUpAt, DateTime.utc(2026, 4, 24, 13, 0));
      expect(updated.bookingId, original.bookingId);
    });
  });
}
