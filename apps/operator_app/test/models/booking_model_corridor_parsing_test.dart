import 'package:flutter_test/flutter_test.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('BookingModel corridor parsing', () {
    test('fromMap parses corridor metadata and route polyline points', () {
      final model = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-1',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'corridorId': 'melaka_main_01',
          'corridorVersion': '2',
          'originCheckpointSeq': '3',
          'destinationCheckpointSeq': 9,
          'routePoints': const [
            {'latitude': 2.2000, 'longitude': 102.2500},
            {'lat': 2.2100, 'lng': 102.2600},
          ],
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'adultFare': 12.0,
          'childFare': 6.0,
          'adultSubtotal': 12.0,
          'childSubtotal': 0.0,
          'fare': 12.0,
          'totalFare': 12.0,
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

      expect(model.corridorId, 'melaka_main_01');
      expect(model.corridorVersion, 2);
      expect(model.originCheckpointSeq, 3);
      expect(model.destinationCheckpointSeq, 9);
      expect(model.routePolyline, hasLength(2));
      expect(model.routePolyline.first.lat, closeTo(2.2000, 0.0000001));
      expect(model.routePolyline.first.lng, closeTo(102.2500, 0.0000001));
    });

    test('fromMap ignores empty/invalid corridor metadata values', () {
      final model = BookingModel.fromMap(
        {
          'bookingId': 'booking-parse-2',
          'userId': 'user-1',
          'userName': 'Passenger One',
          'userPhone': '0123456789',
          'origin': 'Jetty A',
          'destination': 'Jetty B',
          'corridorId': '',
          'corridorVersion': 'not-an-int',
          'originCheckpointSeq': null,
          'destinationCheckpointSeq': 'bad',
          'adultCount': 1,
          'childCount': 0,
          'passengerCount': 1,
          'adultFare': 12.0,
          'childFare': 6.0,
          'adultSubtotal': 12.0,
          'childSubtotal': 0.0,
          'fare': 12.0,
          'totalFare': 12.0,
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

      expect(model.corridorId, isNull);
      expect(model.corridorVersion, isNull);
      expect(model.originCheckpointSeq, isNull);
      expect(model.destinationCheckpointSeq, isNull);
    });
  });
}
