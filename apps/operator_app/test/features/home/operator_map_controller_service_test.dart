import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:operator_app/features/home/presentation/services/operator_map_controller_service.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

BookingModel _bookingFixture({
  required String bookingId,
  required BookingStatus status,
  DateTime? passengerPickedUpAt,
}) {
  return BookingModel(
    bookingId: bookingId,
    userId: 'user-1',
    userName: 'Passenger',
    userPhone: '+60123456789',
    origin: 'The Shore',
    destination: 'Casa Del Rio',
    originLat: 2.201667,
    originLng: 102.249444,
    destinationLat: 2.193056,
    destinationLng: 102.246111,
    adultCount: 1,
    childCount: 0,
    passengerCount: 1,
    totalFare: 25,
    paymentMethod: 'cash',
    paymentStatus: 'pending',
    status: status,
    operatorUid: 'op-1',
    operatorLat: 2.2100,
    operatorLng: 102.2500,
    rejectedBy: const <String>[],
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
    passengerPickedUpAt: passengerPickedUpAt,
  );
}

void main() {
  group('OperatorMapControllerService.resolveNavigationMode', () {
    test('keeps accepted bookings in overview preview mode', () {
      final service = OperatorMapControllerService(enableDebugLogging: false);
      addTearDown(service.dispose);

      final mode = service.resolveNavigationMode(
        activeBooking: _bookingFixture(
          bookingId: 'accepted-preview',
          status: BookingStatus.accepted,
        ),
        operatorPoint: const LatLng(2.2100, 102.2500),
      );

      expect(mode, OperatorMapNavigationMode.overview);
    });

    test(
      'starts tracking only for on-the-way bookings with operator point',
      () {
        final service = OperatorMapControllerService(enableDebugLogging: false);
        addTearDown(service.dispose);

        final mode = service.resolveNavigationMode(
          activeBooking: _bookingFixture(
            bookingId: 'tracking-trip',
            status: BookingStatus.onTheWay,
          ),
          operatorPoint: const LatLng(2.2100, 102.2500),
        );

        expect(mode, OperatorMapNavigationMode.tracking);
      },
    );

    test('stays in overview when operator point is missing', () {
      final service = OperatorMapControllerService(enableDebugLogging: false);
      addTearDown(service.dispose);

      final mode = service.resolveNavigationMode(
        activeBooking: _bookingFixture(
          bookingId: 'missing-position',
          status: BookingStatus.onTheWay,
        ),
        operatorPoint: null,
      );

      expect(mode, OperatorMapNavigationMode.overview);
    });

    test('completed bookings resolve back to overview mode', () {
      final service = OperatorMapControllerService(enableDebugLogging: false);
      addTearDown(service.dispose);

      final mode = service.resolveNavigationMode(
        activeBooking: _bookingFixture(
          bookingId: 'completed-trip',
          status: BookingStatus.completed,
        ),
        operatorPoint: const LatLng(2.2100, 102.2500),
      );

      expect(mode, OperatorMapNavigationMode.overview);
    });
  });

  group('OperatorMapControllerService phase route fitting', () {
    test('passenger pickup phase transition forces an overview refit', () {
      final service = OperatorMapControllerService(enableDebugLogging: false);
      addTearDown(service.dispose);

      service.prepareRouteFitBeforeFollow(
        _bookingFixture(
          bookingId: 'phase-trip',
          status: BookingStatus.onTheWay,
        ),
        routePoints: const <LatLng>[
          LatLng(2.2100, 102.2500),
          LatLng(2.201667, 102.249444),
        ],
        passengerPickedUp: false,
      );

      expect(service.debugHasPendingRouteFit, isTrue);
      expect(service.debugHasForcedRouteFit, isFalse);

      service.prepareRouteFitBeforeFollow(
        _bookingFixture(
          bookingId: 'phase-trip',
          status: BookingStatus.onTheWay,
          passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
        ),
        routePoints: const <LatLng>[
          LatLng(2.2000, 102.2400),
          LatLng(2.193056, 102.246111),
        ],
        passengerPickedUp: true,
      );

      expect(service.debugHasPendingRouteFit, isTrue);
      expect(service.debugHasForcedRouteFit, isTrue);
    });
  });
}
