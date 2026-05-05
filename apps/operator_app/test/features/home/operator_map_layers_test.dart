import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:operator_app/features/home/presentation/map/operator_map_layers.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

BookingModel _bookingFixture({
  required String bookingId,
  BookingStatus status = BookingStatus.onTheWay,
  double? operatorLat = 2.2100,
  double? operatorLng = 102.2500,
  DateTime? passengerPickedUpAt,
  List<BookingRoutePoint> routeToOriginPolyline = const <BookingRoutePoint>[],
  List<BookingRoutePoint> routeToDestinationPolyline =
      const <BookingRoutePoint>[],
  List<BookingRoutePoint> routePolyline = const <BookingRoutePoint>[],
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
    routePolyline: routePolyline,
    routeToOriginPolyline: routeToOriginPolyline,
    routeToDestinationPolyline: routeToDestinationPolyline,
    adultCount: 1,
    childCount: 0,
    passengerCount: 1,
    totalFare: 25,
    paymentMethod: 'cash',
    paymentStatus: 'pending',
    status: status,
    operatorUid: 'op-1',
    operatorLat: operatorLat,
    operatorLng: operatorLng,
    rejectedBy: const <String>[],
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
    passengerPickedUpAt: passengerPickedUpAt,
  );
}

void main() {
  group('OperatorMapLayers.buildMarkers', () {
    test('shows operator marker from accepted onward', () {
      final acceptedBooking = _bookingFixture(
        bookingId: 'm1',
        status: BookingStatus.accepted,
      );
      final onTheWayBooking = _bookingFixture(
        bookingId: 'm2',
        status: BookingStatus.onTheWay,
      );

      final acceptedMarkers = OperatorMapLayers.buildMarkers(acceptedBooking);
      final onTheWayMarkers = OperatorMapLayers.buildMarkers(onTheWayBooking);

      expect(
        acceptedMarkers.any(
          (marker) => marker.markerId.value == 'operator_location',
        ),
        isTrue,
      );
      expect(
        onTheWayMarkers.any(
          (marker) => marker.markerId.value == 'operator_location',
        ),
        isTrue,
      );
    });

    test('does not show operator marker before acceptance', () {
      final pendingBooking = _bookingFixture(
        bookingId: 'm3',
        status: BookingStatus.pending,
      );

      final markers = OperatorMapLayers.buildMarkers(pendingBooking);

      expect(
        markers.any((marker) => marker.markerId.value == 'operator_location'),
        isFalse,
      );
    });

    test('hides pickup marker after passenger is picked up', () {
      final booking = _bookingFixture(
        bookingId: 'm4',
        status: BookingStatus.onTheWay,
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
      );

      final markers = OperatorMapLayers.buildMarkers(booking);

      expect(markers.any((marker) => marker.markerId.value == 'origin'), isFalse);
      expect(
        markers.any((marker) => marker.markerId.value == 'destination'),
        isTrue,
      );
    });
  });

  group('OperatorMapLayers.buildPolylines', () {
    test('onTheWay pre-pickup renders routeToOriginPolyline', () {
      final booking = _bookingFixture(
        bookingId: 'b1',
        routeToOriginPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.2100, lng: 102.2500),
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
        ],
        routeToDestinationPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
          BookingRoutePoint(lat: 2.193056, lng: 102.246111),
        ],
        routePolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 9.0, lng: 9.0),
          BookingRoutePoint(lat: 8.0, lng: 8.0),
        ],
      );

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        passengerPickedUp: false,
      );
      expect(polylines, hasLength(1));
      final polyline = polylines.first;
      expect(polyline.points, hasLength(2));
      expect(polyline.points.first, const LatLng(2.2100, 102.2500));
      expect(polyline.points.last, const LatLng(2.201667, 102.249444));
    });

    test('trims the active route from the current operator position', () {
      final booking = _bookingFixture(
        bookingId: 'b1a',
        operatorLat: 2.2030,
        operatorLng: 102.2450,
        routeToOriginPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.2000, lng: 102.2400),
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2000, lng: 102.2600),
        ],
      );

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        passengerPickedUp: false,
      );
      expect(polylines, hasLength(1));

      final polyline = polylines.first;
      expect(polyline.points.first.latitude, closeTo(2.2000, 0.00001));
      expect(polyline.points.first.longitude, closeTo(102.2450, 0.00001));
      expect(polyline.points.last, const LatLng(2.2000, 102.2600));

      final movedBooking = _bookingFixture(
        bookingId: 'b1b',
        operatorLat: 2.2030,
        operatorLng: 102.2450,
        routeToOriginPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.2000, lng: 102.2400),
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2000, lng: 102.2600),
        ],
      );

      final movedPolylines = OperatorMapLayers.buildPolylines(
        movedBooking,
        passengerPickedUp: false,
      );
      expect(movedPolylines, hasLength(1));
      expect(movedPolylines.first.points, const <LatLng>[
        LatLng(2.2000, 102.2450),
        LatLng(2.2000, 102.2500),
        LatLng(2.2000, 102.2600),
      ]);
    });

    test('onTheWay post-pickup renders routeToDestinationPolyline', () {
      final booking = _bookingFixture(
        bookingId: 'b2',
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
        routeToOriginPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.2100, lng: 102.2500),
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
        ],
        routeToDestinationPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
          BookingRoutePoint(lat: 2.193056, lng: 102.246111),
        ],
      );

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        passengerPickedUp: true,
      );
      expect(polylines, hasLength(1));
      final polyline = polylines.first;
      expect(polyline.points, hasLength(2));
      expect(polyline.points.first, const LatLng(2.201667, 102.249444));
      expect(polyline.points.last, const LatLng(2.193056, 102.246111));
    });

    test('post-pickup fallback uses operator to destination', () {
      final booking = _bookingFixture(
        bookingId: 'b2-fallback',
        operatorLat: 2.198500,
        operatorLng: 102.247500,
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
        routeToDestinationPolyline: const <BookingRoutePoint>[],
      );

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        passengerPickedUp: true,
      );

      expect(polylines, hasLength(1));
      expect(polylines.first.points, const <LatLng>[
        LatLng(2.198500, 102.247500),
        LatLng(2.193056, 102.246111),
      ]);
    });

    test('does not use routePolyline for phase selection', () {
      final booking = _bookingFixture(
        bookingId: 'b3',
        routeToOriginPolyline: const <BookingRoutePoint>[],
        routeToDestinationPolyline: const <BookingRoutePoint>[],
        routePolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 9.0, lng: 9.0),
          BookingRoutePoint(lat: 8.0, lng: 8.0),
        ],
      );

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        passengerPickedUp: false,
      );
      expect(polylines, hasLength(1));
      final polyline = polylines.first;
      // fallback line for phase 1 should be operator -> pickup, not routePolyline
      expect(polyline.points.first, const LatLng(2.2100, 102.2500));
      expect(polyline.points.last, const LatLng(2.201667, 102.249444));
      expect(polyline.points.first, isNot(const LatLng(9.0, 9.0)));
    });

    test('routePointsOverride is used only as fallback', () {
      final booking = _bookingFixture(
        bookingId: 'b4',
        operatorLat: null,
        operatorLng: null,
        routeToOriginPolyline: const <BookingRoutePoint>[],
      );

      final override = <LatLng>[
        const LatLng(2.3000, 102.3000),
        const LatLng(2.3100, 102.3100),
      ];

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        routePointsOverride: override,
        passengerPickedUp: false,
      );
      expect(polylines, hasLength(1));
      final polyline = polylines.first;
      expect(polyline.points, override);
    });
  });
}
