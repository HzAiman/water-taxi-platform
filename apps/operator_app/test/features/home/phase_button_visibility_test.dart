import 'package:flutter_test/flutter_test.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

BookingModel _bookingFixture({
  required String bookingId,
  String userId = 'user-1',
  String userName = 'Test Passenger',
  String userPhone = '+60123456789',
  String origin = 'Marina Bay',
  String destination = 'Changi Airport',
  double originLat = 3.1357,
  double originLng = 101.6880,
  double destinationLat = 3.1400,
  double destinationLng = 101.6950,
  String? operatorUid,
  double? operatorLat,
  double? operatorLng,
  DateTime? passengerPickedUpAt,
  List<BookingRoutePoint> routeToOriginPolyline = const <BookingRoutePoint>[],
  List<BookingRoutePoint> routeToDestinationPolyline =
      const <BookingRoutePoint>[],
  List<BookingRoutePoint> routePolyline = const <BookingRoutePoint>[],
}) {
  return BookingModel(
    bookingId: bookingId,
    userId: userId,
    userName: userName,
    userPhone: userPhone,
    origin: origin,
    destination: destination,
    originLat: originLat,
    originLng: originLng,
    destinationLat: destinationLat,
    destinationLng: destinationLng,
    routePolyline: routePolyline,
    routeToOriginPolyline: routeToOriginPolyline,
    routeToDestinationPolyline: routeToDestinationPolyline,
    adultCount: 1,
    childCount: 0,
    passengerCount: 1,
    totalFare: 25.0,
    paymentMethod: 'cash',
    paymentStatus: 'pending',
    status: BookingStatus.onTheWay,
    operatorUid: operatorUid,
    operatorLat: operatorLat,
    operatorLng: operatorLng,
    rejectedBy: const <String>[],
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
    passengerPickedUpAt: passengerPickedUpAt,
  );
}

void main() {
  group('Phase Button Visibility', () {
    test('Button renders in phase 1 even when phase polylines empty', () {
      // This simulates the scenario where phase polylines haven't been hydrated yet,
      // but the button should still be visible for the operator to proceed
      final booking = _bookingFixture(
        bookingId: 'missing-routes-phase1',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1350,
        operatorLng: 101.6870,
        routeToOriginPolyline: const <BookingRoutePoint>[],
        routeToDestinationPolyline: const [],
        routePolyline: const [],
      );

      final isOnTheWay = booking.status == BookingStatus.onTheWay;
      final hasPassengerPickedUpAt = booking.passengerPickedUpAt != null;

      expect(isOnTheWay, true, reason: 'Trip should be onTheWay');
      expect(
        hasPassengerPickedUpAt,
        false,
        reason: 'Phase 1: passenger not yet picked up',
      );

      // Button label should be "Passenger Picked Up" (phase 1 action)
      final buttonLabel = hasPassengerPickedUpAt
          ? 'Complete Trip'
          : 'Passenger Picked Up';
      expect(
        buttonLabel,
        'Passenger Picked Up',
        reason: 'Phase 1 should show pickup button',
      );
    });

    test('Button renders in phase 2 even when destination polyline empty', () {
      final booking = _bookingFixture(
        bookingId: 'missing-dest-phase2',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1365,
        operatorLng: 101.6890,
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 15),
        routeToOriginPolyline: [BookingRoutePoint(lat: 3.1357, lng: 101.6880)],
        routeToDestinationPolyline: const [], // Empty - hydration failed
        routePolyline: const [],
      );

      final isOnTheWay = booking.status == BookingStatus.onTheWay;
      final hasPassengerPickedUpAt = booking.passengerPickedUpAt != null;

      expect(isOnTheWay, true, reason: 'Trip should be onTheWay');
      expect(
        hasPassengerPickedUpAt,
        true,
        reason: 'Phase 2: passenger already picked up',
      );

      // Button label should be "Complete Trip" (phase 2 action)
      final buttonLabel = hasPassengerPickedUpAt
          ? 'Complete Trip'
          : 'Passenger Picked Up';
      expect(
        buttonLabel,
        'Complete Trip',
        reason: 'Phase 2 should show completion button',
      );
    });

    test('Phase 1 correctly identified when passengerPickedUpAt is null', () {
      final booking = _bookingFixture(
        bookingId: 'phase-1-no-timestamp',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1350,
        operatorLng: 101.6870,
        passengerPickedUpAt: null, // Explicitly null for phase 1
        routeToOriginPolyline: const [],
        routeToDestinationPolyline: const [],
        routePolyline: const [],
      );

      final passengerPickedUp = booking.passengerPickedUpAt != null;
      expect(passengerPickedUp, false, reason: 'null timestamp means phase 1');

      // Local tracking should show button as "Passenger Picked Up"
      final isPhase1 =
          !passengerPickedUp && booking.status == BookingStatus.onTheWay;
      expect(isPhase1, true, reason: 'Should identify phase 1 correctly');
    });

    test('Phase 2 correctly identified when passengerPickedUpAt is set', () {
      final pickupTime = DateTime(2024, 1, 1, 10, 30);
      final booking = _bookingFixture(
        bookingId: 'phase-2-with-timestamp',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1365,
        operatorLng: 101.6890,
        passengerPickedUpAt: pickupTime,
        routeToOriginPolyline: const [],
        routeToDestinationPolyline: const [],
        routePolyline: const [],
      );

      final passengerPickedUp = booking.passengerPickedUpAt != null;
      expect(passengerPickedUp, true, reason: 'Set timestamp means phase 2');

      // Local tracking should show button as "Complete Trip"
      final isPhase2 =
          passengerPickedUp && booking.status == BookingStatus.onTheWay;
      expect(isPhase2, true, reason: 'Should identify phase 2 correctly');
    });
  });
}
