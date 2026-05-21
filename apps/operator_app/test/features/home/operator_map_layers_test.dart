import 'package:flutter/material.dart';
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
  List<PoolStopPlanItem> poolStopPlan = const <PoolStopPlanItem>[],
  String? currentStopId,
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
    poolStopPlan: poolStopPlan,
    currentStopId: currentStopId,
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
  group('OperatorMapLayers navigation state', () {
    test('true navigation starts only when booking is on the way', () {
      final acceptedBooking = _bookingFixture(
        bookingId: 'state-accepted',
        status: BookingStatus.accepted,
      );
      final onTheWayBooking = _bookingFixture(
        bookingId: 'state-on-the-way',
        status: BookingStatus.onTheWay,
      );

      expect(
        OperatorMapLayers.isActiveNavigationBooking(acceptedBooking),
        isFalse,
      );
      expect(
        OperatorMapLayers.isActiveNavigationBooking(onTheWayBooking),
        isTrue,
      );
      expect(OperatorMapLayers.shouldShowOperatorMarker(acceptedBooking), true);
      expect(
        OperatorMapLayers.shouldShowOperatorMarker(onTheWayBooking),
        false,
      );
    });
  });

  group('OperatorMapLayers.buildMarkers', () {
    test('shows operator marker for accepted preview only', () {
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
        isFalse,
      );
    });

    test(
      'uses live operator point for accepted preview marker when provided',
      () {
        final booking = _bookingFixture(
          bookingId: 'm-live',
          status: BookingStatus.accepted,
          operatorLat: 2.2100,
          operatorLng: 102.2500,
        );

        final markers = OperatorMapLayers.buildMarkers(
          booking,
          operatorPoint: const LatLng(2.2050, 102.2550),
        );

        final operatorMarker = markers.singleWhere(
          (marker) => marker.markerId.value == 'operator_location',
        );
        expect(operatorMarker.position, const LatLng(2.2050, 102.2550));
      },
    );

    test(
      'hides operator marker during live navigation so blue dot is primary',
      () {
        final booking = _bookingFixture(
          bookingId: 'm-live-nav',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2100,
          operatorLng: 102.2500,
        );

        final markers = OperatorMapLayers.buildMarkers(
          booking,
          operatorPoint: const LatLng(2.2050, 102.2550),
        );

        expect(
          markers.any((marker) => marker.markerId.value == 'operator_location'),
          isFalse,
        );
      },
    );

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

      expect(
        markers.any((marker) => marker.markerId.value == 'origin'),
        isFalse,
      );
      expect(
        markers.any((marker) => marker.markerId.value == 'destination'),
        isTrue,
      );
    });

    test('hides dropoff marker while navigating to pickup', () {
      final booking = _bookingFixture(
        bookingId: 'm5',
        status: BookingStatus.onTheWay,
      );

      final markers = OperatorMapLayers.buildMarkers(booking);

      expect(
        markers.any((marker) => marker.markerId.value == 'origin'),
        isTrue,
      );
      expect(
        markers.any((marker) => marker.markerId.value == 'destination'),
        isFalse,
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
        operatorLat: 2.201667,
        operatorLng: 102.2450,
        routeToOriginPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.201667, lng: 102.2400),
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
        ],
      );

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        passengerPickedUp: false,
      );
      expect(polylines, hasLength(1));

      final polyline = polylines.first;
      expect(polyline.points.first.latitude, closeTo(2.201667, 0.00001));
      expect(polyline.points.first.longitude, closeTo(102.2450, 0.00001));
      expect(polyline.points.last, const LatLng(2.201667, 102.249444));

      final movedBooking = _bookingFixture(
        bookingId: 'b1b',
        operatorLat: 2.201667,
        operatorLng: 102.2450,
        routeToOriginPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.201667, lng: 102.2400),
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
        ],
      );

      final movedPolylines = OperatorMapLayers.buildPolylines(
        movedBooking,
        passengerPickedUp: false,
      );
      expect(movedPolylines, hasLength(1));
      expect(movedPolylines.first.points, const <LatLng>[
        LatLng(2.201667, 102.2450),
        LatLng(2.201667, 102.249444),
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
      expect(polyline.points, hasLength(3));
      expect(polyline.points.first, const LatLng(2.2100, 102.2500));
      expect(polyline.points[1], const LatLng(2.201667, 102.249444));
      expect(polyline.points.last, const LatLng(2.193056, 102.246111));
    });

    test(
      'IMPORTANT: post-pickup phase 2 polyline starts at operator location and ends at dropoff',
      () {
        final booking = _bookingFixture(
          bookingId: 'b2-segmented',
          operatorLat: 2.2005186,
          operatorLng: 102.2478974,
          passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
          routeToDestinationPolyline: const <BookingRoutePoint>[
            BookingRoutePoint(lat: 2.2010520, lng: 102.2483375),
            BookingRoutePoint(lat: 2.2007938, lng: 102.2480053),
            BookingRoutePoint(lat: 2.2005186, lng: 102.2478974),
            BookingRoutePoint(lat: 2.2001006, lng: 102.2479594),
            BookingRoutePoint(lat: 2.1994408, lng: 102.2483514),
          ],
        );

        final polylines = OperatorMapLayers.buildPolylines(
          booking,
          passengerPickedUp: true,
        );

        expect(polylines, hasLength(1));
        expect(polylines.first.points.length, greaterThan(2));
        expect(
          polylines.first.points.first.longitude,
          closeTo(102.2478974, 0.00001),
        );
        expect(
          polylines.first.points.first.latitude,
          closeTo(2.2005186, 0.00001),
        );
        expect(polylines.first.points.last, const LatLng(2.193056, 102.246111));
      },
    );

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

    test(
      'post-pickup does not use generic routePolyline fallback and draws operator to dropoff line',
      () {
        final booking = _bookingFixture(
          bookingId: 'b2-routepolyline-fallback',
          operatorLat: 2.2001006,
          operatorLng: 102.2479594,
          passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
          routeToDestinationPolyline: const <BookingRoutePoint>[],
          routePolyline: const <BookingRoutePoint>[
            BookingRoutePoint(lat: 2.2010520, lng: 102.2483375),
            BookingRoutePoint(lat: 2.2007938, lng: 102.2480053),
            BookingRoutePoint(lat: 2.2005186, lng: 102.2478974),
            BookingRoutePoint(lat: 2.2001006, lng: 102.2479594),
            BookingRoutePoint(lat: 2.1994408, lng: 102.2483514),
            BookingRoutePoint(lat: 2.1983528, lng: 102.2483828),
            BookingRoutePoint(lat: 2.1977739, lng: 102.2485790),
          ],
        );

        final polylines = OperatorMapLayers.buildPolylines(
          booking,
          passengerPickedUp: true,
        );

        expect(polylines, hasLength(1));
        expect(polylines.first.points, const <LatLng>[
          LatLng(2.2001006, 102.2479594),
          LatLng(2.193056, 102.246111),
        ]);
      },
    );

    test(
      'pre-pickup uses straight-line fallback when pickup phase route is missing',
      () {
        final booking = _bookingFixture(
          bookingId: 'b3',
          operatorLat: 2.2001006,
          operatorLng: 102.2479594,
          routeToOriginPolyline: const <BookingRoutePoint>[],
          routeToDestinationPolyline: const <BookingRoutePoint>[],
          routePolyline: const <BookingRoutePoint>[
            BookingRoutePoint(lat: 2.2010520, lng: 102.2483375),
            BookingRoutePoint(lat: 2.2007938, lng: 102.2480053),
            BookingRoutePoint(lat: 2.2005186, lng: 102.2478974),
            BookingRoutePoint(lat: 2.2001006, lng: 102.2479594),
            BookingRoutePoint(lat: 2.1994408, lng: 102.2483514),
            BookingRoutePoint(lat: 2.1991486, lng: 102.2484224),
            BookingRoutePoint(lat: 2.1983528, lng: 102.2483828),
          ],
        );

        final polylines = OperatorMapLayers.buildPolylines(
          booking,
          passengerPickedUp: false,
        );
        expect(polylines, hasLength(1));
        final polyline = polylines.first;
        expect(polyline.points, const <LatLng>[
          LatLng(2.2001006, 102.2479594),
          LatLng(2.201667, 102.249444),
        ]);
      },
    );

    test('fallback polyline is styled amber and dashed', () {
      final booking = _bookingFixture(
        bookingId: 'b4',
        operatorLat: 2.2000,
        operatorLng: 102.2400,
        routeToOriginPolyline: const <BookingRoutePoint>[],
      );

      final polylines = OperatorMapLayers.buildPolylines(
        booking,
        passengerPickedUp: false,
      );

      expect(polylines, hasLength(1));
      final polyline = polylines.first;
      expect(polyline.color, const Color(0xFFF59E0B));
      expect(polyline.patterns, isNotEmpty);
    });

    test(
      'stop-first route uses stored route geometry to current pickup stop',
      () {
        final booking = _bookingFixture(
          bookingId: 'stop-first-pickup',
          operatorLat: 2.0,
          operatorLng: 102.0,
          passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
          routeToDestinationPolyline: const <BookingRoutePoint>[
            BookingRoutePoint(lat: 9, lng: 109),
            BookingRoutePoint(lat: 8, lng: 108),
          ],
          routePolyline: const <BookingRoutePoint>[
            BookingRoutePoint(lat: 2.0, lng: 102.0),
            BookingRoutePoint(lat: 2.001, lng: 102.001),
            BookingRoutePoint(lat: 2.002, lng: 102.002),
            BookingRoutePoint(lat: 2.003, lng: 102.003),
          ],
          currentStopId: 'pickup-stop-1',
          poolStopPlan: const <PoolStopPlanItem>[
            PoolStopPlanItem(
              stopId: 'pickup-stop-1',
              index: 0,
              stopType: 'pickup',
              stopJettyId: 'jetty-15',
              stopName: 'The Shore',
              lat: 2.002,
              lng: 102.002,
              bookingIds: <String>['stop-first-pickup'],
              status: 'active',
            ),
          ],
        );

        final polylines = OperatorMapLayers.buildPolylines(
          booking,
          passengerPickedUp: true,
        );

        expect(polylines, hasLength(1));
        final points = polylines.first.points;
        expect(points, contains(const LatLng(2.001, 102.001)));
        expect(points.last, const LatLng(2.002, 102.002));
        expect(points, isNot(contains(const LatLng(9, 109))));
      },
    );

    test(
      'stop-first route shows amber fallback when live location is far from route',
      () {
        final booking = _bookingFixture(
          bookingId: 'stop-first-no-long-anchor',
          operatorLat: 2.0005,
          operatorLng: 102.010,
          routePolyline: const <BookingRoutePoint>[
            BookingRoutePoint(lat: 2.0, lng: 102.0),
            BookingRoutePoint(lat: 2.001, lng: 102.0),
            BookingRoutePoint(lat: 2.002, lng: 102.0),
          ],
          currentStopId: 'pickup-stop-1',
          poolStopPlan: const <PoolStopPlanItem>[
            PoolStopPlanItem(
              stopId: 'pickup-stop-1',
              index: 0,
              stopType: 'pickup',
              stopJettyId: 'jetty-15',
              stopName: 'The Shore',
              lat: 2.002,
              lng: 102.0,
              bookingIds: <String>['stop-first-no-long-anchor'],
              status: 'active',
            ),
          ],
        );

        final polylines = OperatorMapLayers.buildPolylines(
          booking,
          passengerPickedUp: false,
        );

        expect(polylines, hasLength(1));
        expect(polylines.first.points.first, const LatLng(2.0005, 102.010));
        expect(polylines.first.points.last, const LatLng(2.002, 102.0));
        expect(polylines.first.color, const Color(0xFFF59E0B));
        expect(polylines.first.patterns, isNotEmpty);
      },
    );
  });

  group('OperatorMapLayers.resolveRouteHealth', () {
    test('reports routeToOriginPolyline for phase 1 readiness', () {
      final booking = _bookingFixture(
        bookingId: 'health-origin',
        routeToOriginPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.2100, lng: 102.2500),
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
        ],
      );

      final health = OperatorMapLayers.resolveRouteHealth(
        booking,
        passengerPickedUp: false,
      );

      expect(health.source, OperatorRouteSource.routeToOriginPolyline);
      expect(health.warning, isNull);
      expect(health.usesFallback, isFalse);
    });

    test('reports routeToDestinationPolyline for phase 2 readiness', () {
      final booking = _bookingFixture(
        bookingId: 'health-destination',
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
        routeToDestinationPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.2000, lng: 102.2400),
          BookingRoutePoint(lat: 2.193056, lng: 102.246111),
        ],
      );

      final health = OperatorMapLayers.resolveRouteHealth(
        booking,
        passengerPickedUp: true,
      );

      expect(health.source, OperatorRouteSource.routeToDestinationPolyline);
      expect(health.warning, isNull);
      expect(health.usesFallback, isFalse);
    });

    test('phase 2 never uses generic pickup-to-dropoff route as fallback', () {
      final booking = _bookingFixture(
        bookingId: 'health-fallback',
        operatorLat: 2.2001006,
        operatorLng: 102.2479594,
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
        routeToDestinationPolyline: const <BookingRoutePoint>[],
        routePolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
          BookingRoutePoint(lat: 2.193056, lng: 102.246111),
        ],
      );

      final health = OperatorMapLayers.resolveRouteHealth(
        booking,
        passengerPickedUp: true,
      );

      expect(health.source, OperatorRouteSource.straightLineFallback);
      expect(health.warning, contains('routeToDestinationPolyline'));
      expect(health.routePoints, const <LatLng>[
        LatLng(2.2001006, 102.2479594),
        LatLng(2.193056, 102.246111),
      ]);
    });

    test('phase route segmentation failure does not draw raw stored route', () {
      final booking = _bookingFixture(
        bookingId: 'health-no-raw-phase-route',
        operatorLat: null,
        operatorLng: null,
        passengerPickedUpAt: DateTime(2024, 1, 1, 10, 30),
        routeToDestinationPolyline: const <BookingRoutePoint>[
          BookingRoutePoint(lat: 2.201667, lng: 102.249444),
          BookingRoutePoint(lat: 2.193056, lng: 102.246111),
        ],
      );

      final health = OperatorMapLayers.resolveRouteHealth(
        booking,
        passengerPickedUp: true,
      );

      expect(health.source, OperatorRouteSource.straightLineFallback);
      expect(health.routePoints, isEmpty);
    });
  });
}
