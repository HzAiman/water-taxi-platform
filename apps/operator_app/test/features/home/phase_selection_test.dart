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
  group('Phase Selection Logic', () {
    test('Phase 1 shows operator->origin polyline when pre-pickup', () {
      final mockOriginPolyline = [
        BookingRoutePoint(lat: 3.1357, lng: 101.6880),
        BookingRoutePoint(lat: 3.1365, lng: 101.6890),
      ];
      final mockDestinationPolyline = [
        BookingRoutePoint(lat: 3.1365, lng: 101.6890),
        BookingRoutePoint(lat: 3.1400, lng: 101.6950),
      ];

      final booking = _bookingFixture(
        bookingId: 'test-phase-1',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1350,
        operatorLng: 101.6870,
        routeToOriginPolyline: mockOriginPolyline,
        routeToDestinationPolyline: mockDestinationPolyline,
        routePolyline: const [], // Empty fallback
      );

      // Phase 1: Pre-pickup should use routeToOriginPolyline
      final passengerPickedUp = booking.passengerPickedUpAt != null;
      expect(
        passengerPickedUp,
        false,
        reason: 'passengerPickedUpAt should be null pre-pickup',
      );

      final phase1Polyline = passengerPickedUp
          ? booking.routeToDestinationPolyline
          : booking.routeToOriginPolyline;
      expect(
        phase1Polyline,
        mockOriginPolyline,
        reason: 'Phase 1 should show operator->origin',
      );
      expect(
        phase1Polyline.isNotEmpty,
        true,
        reason: 'Phase 1 polyline should not be empty',
      );
    });

    test('Phase 2 shows origin->destination polyline when post-pickup', () {
      final mockOriginPolyline = [
        BookingRoutePoint(lat: 3.1357, lng: 101.6880),
        BookingRoutePoint(lat: 3.1365, lng: 101.6890),
      ];
      final mockDestinationPolyline = [
        BookingRoutePoint(lat: 3.1365, lng: 101.6890),
        BookingRoutePoint(lat: 3.1400, lng: 101.6950),
      ];

      final booking = _bookingFixture(
        bookingId: 'test-phase-2',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1365,
        operatorLng: 101.6890,
        passengerPickedUpAt: DateTime(
          2024,
          1,
          1,
          10,
          15,
        ), // Passenger picked up
        routeToOriginPolyline: mockOriginPolyline,
        routeToDestinationPolyline: mockDestinationPolyline,
        routePolyline: const [],
      );

      // Phase 2: Post-pickup should use routeToDestinationPolyline
      final passengerPickedUp = booking.passengerPickedUpAt != null;
      expect(
        passengerPickedUp,
        true,
        reason: 'passengerPickedUpAt should be set post-pickup',
      );

      final phase2Polyline = passengerPickedUp
          ? booking.routeToDestinationPolyline
          : booking.routeToOriginPolyline;
      expect(
        phase2Polyline,
        mockDestinationPolyline,
        reason: 'Phase 2 should show origin->destination',
      );
      expect(
        phase2Polyline.isNotEmpty,
        true,
        reason: 'Phase 2 polyline should not be empty',
      );
    });

    test('Fallback to routePolyline when phase polyline is missing', () {
      final mockFullPolyline = [
        BookingRoutePoint(lat: 3.1350, lng: 101.6870),
        BookingRoutePoint(lat: 3.1357, lng: 101.6880),
        BookingRoutePoint(lat: 3.1365, lng: 101.6890),
        BookingRoutePoint(lat: 3.1400, lng: 101.6950),
      ];

      final booking = _bookingFixture(
        bookingId: 'test-fallback',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1350,
        operatorLng: 101.6870,
        routeToOriginPolyline: const [], // Empty phase 1
        routeToDestinationPolyline: const [], // Empty phase 2
        routePolyline: mockFullPolyline, // Has fallback
      );

      final passengerPickedUp = booking.passengerPickedUpAt != null;

      // Phase 1: Should use routePolyline as fallback
      final phase1Primary = passengerPickedUp
          ? booking.routeToDestinationPolyline
          : booking.routeToOriginPolyline;
      final phase1Fallback = phase1Primary.isEmpty
          ? booking.routePolyline
          : const <BookingRoutePoint>[];

      expect(
        phase1Primary.isEmpty,
        true,
        reason: 'Phase 1 primary should be empty',
      );
      expect(
        phase1Fallback,
        mockFullPolyline,
        reason: 'Phase 1 fallback should use routePolyline',
      );
    });

    test('Empty fallback for post-pickup if destination polyline missing', () {
      final mockOriginPolyline = [
        BookingRoutePoint(lat: 3.1357, lng: 101.6880),
        BookingRoutePoint(lat: 3.1365, lng: 101.6890),
      ];

      final booking = _bookingFixture(
        bookingId: 'test-phase2-empty',
        userId: 'pass1',
        operatorUid: 'op1',
        operatorLat: 3.1365,
        operatorLng: 101.6890,
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 15),
        routeToOriginPolyline: mockOriginPolyline,
        routeToDestinationPolyline: const [], // Missing destination route
        routePolyline: const [], // Empty fallback too
      );

      final passengerPickedUp = booking.passengerPickedUpAt != null;
      expect(passengerPickedUp, true);

      final phase2Primary = passengerPickedUp
          ? booking.routeToDestinationPolyline
          : booking.routeToOriginPolyline;
      final phase2Fallback = phase2Primary.isEmpty && passengerPickedUp
          ? booking.routePolyline
          : const <BookingRoutePoint>[];

      expect(
        phase2Primary.isEmpty,
        true,
        reason: 'Destination polyline missing',
      );
      expect(
        phase2Fallback.isEmpty,
        true,
        reason:
            'Should use empty fallback for phase 2 with missing destination',
      );
    });
  });
}
