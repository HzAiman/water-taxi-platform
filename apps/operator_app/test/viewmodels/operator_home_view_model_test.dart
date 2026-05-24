import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/features/home/presentation/services/operator_navigation_guidance_service.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:operator_app/services/notifications/operator_navigation_alert_bus.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

OperatorHomeViewModel createViewModel({
  required BookingRepository bookingRepo,
  required OperatorRepository operatorRepo,
}) {
  return OperatorHomeViewModel(
    bookingRepo: bookingRepo,
    operatorRepo: operatorRepo,
    refreshSessionForNavigation: () async {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalDebugPrint = debugPrint;
  setUpAll(() {
    setupFirebaseCoreMocks();
    debugPrint = (String? message, {int? wrapWidth}) {};
  });
  setUp(() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  });
  tearDownAll(() {
    debugPrint = originalDebugPrint;
  });

  group('OperatorHomeViewModel', () {
    test(
      'initialize loads operator status and subscribes to streams',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final operatorRepo = FakeOperatorRepository(
          operator: const OperatorModel(
            uid: 'operator-1',
            operatorId: 'OP-1',
            name: 'Captain Aiman',
            email: 'captain@example.com',
            isOnline: true,
          ),
        );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: operatorRepo,
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([
          _sampleBooking(id: 'active-1', status: BookingStatus.accepted),
        ]);
        bookingRepo.emitPending([
          _sampleBooking(id: 'pending-1', status: BookingStatus.pending),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.isOnline, isTrue);
        expect(viewModel.activeBookings, hasLength(1));
        expect(viewModel.visiblePendingBookings('operator-1'), hasLength(1));
      },
    );

    test(
      'visiblePendingBookings filters bookings already rejected by operator',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: FakeOperatorRepository(),
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitPending([
          _sampleBooking(id: 'visible', status: BookingStatus.pending),
          _sampleBooking(
            id: 'hidden',
            status: BookingStatus.pending,
            rejectedBy: const ['operator-1'],
          ),
        ]);
        await Future<void>.delayed(Duration.zero);

        final visible = viewModel.visiblePendingBookings('operator-1');

        expect(visible.map((b) => b.bookingId), ['visible']);
      },
    );

    test(
      'toggleOnlineStatus releases accepted bookings when going offline',
      () async {
        final bookingRepo = FakeOperatorBookingRepository()..releasedCount = 2;
        final operatorRepo = FakeOperatorRepository(
          operator: const OperatorModel(
            uid: 'operator-1',
            operatorId: 'OP-1',
            name: 'Captain Aiman',
            email: 'captain@example.com',
            isOnline: true,
          ),
        );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: operatorRepo,
        );

        await viewModel.initialize('operator-1');
        final result = await viewModel.toggleOnlineStatus();

        expect(result, isA<OperationSuccess>());
        expect(
          (result as OperationSuccess).message,
          contains('2 accepted bookings released'),
        );
        expect(viewModel.isOnline, isFalse);
        expect(operatorRepo.lastOnlineStatus, isFalse);
      },
    );

    test(
      'goOfflineSafely sets offline when there are no active bookings',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final operatorRepo = FakeOperatorRepository(
          operator: const OperatorModel(
            uid: 'operator-1',
            operatorId: 'OP-1',
            name: 'Captain Aiman',
            email: 'captain@example.com',
            isOnline: true,
          ),
        );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: operatorRepo,
        );

        await viewModel.initialize('operator-1');
        final result = await viewModel.goOfflineSafely();

        expect(result, isA<OperationSuccess>());
        expect(viewModel.isOnline, isFalse);
        expect(operatorRepo.lastOnlineStatus, isFalse);
      },
    );

    test('goOfflineSafely blocks active on-the-way trip', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final operatorRepo = FakeOperatorRepository(
        operator: const OperatorModel(
          uid: 'operator-1',
          operatorId: 'OP-1',
          name: 'Captain Aiman',
          email: 'captain@example.com',
          isOnline: true,
        ),
      );
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
      );

      await viewModel.initialize('operator-1');
      bookingRepo.emitActive([
        _sampleBooking(id: 'active-1', status: BookingStatus.onTheWay),
      ]);
      await Future<void>.delayed(Duration.zero);

      final result = await viewModel.goOfflineSafely();

      expect(result, isA<OperationFailure>());
      expect((result as OperationFailure).title, 'Active trip in progress');
      expect(result.message, contains('Complete this trip'));
      expect(viewModel.isOnline, isTrue);
      expect(operatorRepo.lastOnlineStatus, isNull);
    });

    test(
      'goOfflineSafely keeps online when release accepted bookings fails',
      () async {
        final bookingRepo = FakeOperatorBookingRepository()
          ..releaseAllError = StateError('release failed');
        final operatorRepo = FakeOperatorRepository(
          operator: const OperatorModel(
            uid: 'operator-1',
            operatorId: 'OP-1',
            name: 'Captain Aiman',
            email: 'captain@example.com',
            isOnline: true,
          ),
        );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: operatorRepo,
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([
          _sampleBooking(id: 'accepted-1', status: BookingStatus.accepted),
        ]);
        await Future<void>.delayed(Duration.zero);

        final result = await viewModel.goOfflineSafely();

        expect(result, isA<OperationFailure>());
        expect(viewModel.isOnline, isTrue);
        expect(operatorRepo.lastOnlineStatus, isNull);
      },
    );

    test('goOfflineSafely keeps online when presence update fails', () async {
      final bookingRepo = FakeOperatorBookingRepository()..releasedCount = 1;
      final operatorRepo = FakeOperatorRepository(
        operator: const OperatorModel(
          uid: 'operator-1',
          operatorId: 'OP-1',
          name: 'Captain Aiman',
          email: 'captain@example.com',
          isOnline: true,
        ),
      )..setOnlineStatusError = StateError('presence failed');
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
      );

      await viewModel.initialize('operator-1');
      bookingRepo.emitActive([
        _sampleBooking(id: 'accepted-1', status: BookingStatus.accepted),
      ]);
      await Future<void>.delayed(Duration.zero);

      final result = await viewModel.goOfflineSafely();

      expect(result, isA<OperationFailure>());
      expect(viewModel.isOnline, isTrue);
      expect(operatorRepo.lastOnlineStatus, isNull);
    });

    test('acceptBooking delegates operator id and resets busy state', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: FakeOperatorRepository(),
      );

      await viewModel.initialize('operator-77');
      final result = await viewModel.acceptBooking('booking-42');

      expect(result, isA<OperationSuccess>());
      expect(bookingRepo.lastAcceptedBookingId, 'booking-42');
      expect(bookingRepo.lastAcceptedOperatorId, 'operator-77');
      expect(viewModel.isUpdatingBooking, isFalse);
    });

    test('booking actions fail before initialize', () async {
      final viewModel = createViewModel(
        bookingRepo: FakeOperatorBookingRepository(),
        operatorRepo: FakeOperatorRepository(),
      );

      final result = await viewModel.acceptBooking('booking-1');

      expect(result, isA<OperationFailure>());
      expect((result as OperationFailure).title, 'Not initialised');
      expect(viewModel.isUpdatingBooking, isFalse);
    });

    test('completeTrip removes completed booking locally', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: FakeOperatorRepository(),
      );

      await viewModel.initialize('operator-1');
      bookingRepo.emitActive([
        _sampleBooking(id: 'active-1', status: BookingStatus.onTheWay),
      ]);
      await Future<void>.delayed(Duration.zero);

      final result = await viewModel.completeTrip('active-1');

      expect(result, isA<OperationSuccess>());
      expect(viewModel.activeBookings, isEmpty);

      bookingRepo.emitActive([
        _sampleBooking(id: 'active-1', status: BookingStatus.onTheWay),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.activeBookings, isEmpty);
    });

    test(
      'markPassengerPickedUp locally advances current stop route order',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: FakeOperatorRepository(
            operator: const OperatorModel(
              uid: 'operator-1',
              operatorId: 'OP-1',
              name: 'Captain Aiman',
              email: 'captain@example.com',
              isOnline: true,
            ),
          ),
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([
          _sampleBooking(
            id: 'active-1',
            status: BookingStatus.onTheWay,
            poolStopPlan: _twoStopPlan(),
            currentStopIndex: 0,
            currentStopId: 'pickup-active-1',
            currentPoolStopId: 'pickup-active-1',
            poolGroupId: 'pool-1',
          ),
        ]);
        await Future<void>.delayed(Duration.zero);

        final result = await viewModel.markPassengerPickedUp('active-1');

        expect(result, isA<OperationSuccess>());
        final updated = viewModel.activeBookings.single;
        expect(updated.passengerPickedUpAt, isNotNull);
        expect(updated.onboard, isTrue);
        expect(updated.poolPhase, 'onboard');
        expect(updated.currentStopId, 'dropoff-active-1');
        expect(updated.currentPoolStop?.stopId, 'dropoff-active-1');
        expect(updated.poolStopPlan.first.status, 'completed');
        expect(updated.poolStopPlan.last.status, 'active');
      },
    );

    test('busy guard blocks overlapping booking operations', () async {
      final bookingRepo = FakeOperatorBookingRepository()
        ..acceptCompleter = Completer<OperationResult>();
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: FakeOperatorRepository(),
      );

      await viewModel.initialize('operator-1');
      final first = viewModel.acceptBooking('booking-1');
      await Future<void>.delayed(Duration.zero);

      final second = await viewModel.rejectBooking('booking-2');
      bookingRepo.acceptCompleter!.complete(
        const OperationSuccess('Booking accepted successfully.'),
      );
      await first;

      expect(second, isA<OperationFailure>());
      expect((second as OperationFailure).title, 'Busy');
      expect(viewModel.isUpdatingBooking, isFalse);
      expect(bookingRepo.lastAcceptedBookingId, 'booking-1');
      expect(bookingRepo.lastRejectedBookingId, isNull);
    });

    test(
      'permission-denied failures are normalized to user-friendly message',
      () async {
        final bookingRepo = FakeOperatorBookingRepository()
          ..rejectResult = const OperationFailure(
            'Reject failed',
            'Could not reject booking: [cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation',
          );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: FakeOperatorRepository(),
        );

        await viewModel.initialize('operator-1');
        final result = await viewModel.rejectBooking('booking-2');

        expect(result, isA<OperationFailure>());
        final failure = result as OperationFailure;
        expect(failure.title, 'Permission denied');
        expect(
          failure.message,
          contains('Your sign-in session could not be refreshed'),
        );
      },
    );

    test('toggleOnlineStatus reverts state on timeout', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final operatorRepo = FakeOperatorRepository(
        operator: const OperatorModel(
          uid: 'operator-1',
          operatorId: 'OP-1',
          name: 'Captain Aiman',
          email: 'captain@example.com',
          isOnline: false,
        ),
      )..setOnlineStatusDelay = const Duration(seconds: 7);
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
      );

      await viewModel.initialize('operator-1');
      final result = await viewModel.toggleOnlineStatus();

      expect(result, isA<OperationFailure>());
      expect((result as OperationFailure).title, 'Timeout');
      expect(viewModel.isOnline, isFalse);
      expect(viewModel.isToggling, isFalse);
    });

    test('refresh bumps stream version and restarts subscriptions', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: FakeOperatorRepository(),
      );

      await viewModel.initialize('operator-1');
      bookingRepo.emitActive([
        _sampleBooking(id: 'active-1', status: BookingStatus.onTheWay),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.streamVersion, 0);
      expect(viewModel.activeBookings, hasLength(1));

      await viewModel.refresh('operator-1');

      expect(viewModel.streamVersion, 1);
      expect(viewModel.isRefreshing, isFalse);
      expect(viewModel.activeBookings, hasLength(1));
      expect(bookingRepo.activeListenCount, greaterThanOrEqualTo(2));
      expect(bookingRepo.pendingListenCount, greaterThanOrEqualTo(2));
    });

    test(
      'forced reinitialization keeps active trip while streams reconnect',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: FakeOperatorRepository(
            operator: const OperatorModel(
              uid: 'operator-1',
              operatorId: 'operator-1',
              name: 'Operator',
              email: 'operator@example.com',
              isOnline: true,
            ),
          ),
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([
          _sampleBooking(id: 'active-1', status: BookingStatus.onTheWay),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.activeBookings, hasLength(1));

        await viewModel.ensureInitialized('operator-1', force: true);

        expect(viewModel.activeBookings, hasLength(1));
        expect(bookingRepo.activeListenCount, greaterThanOrEqualTo(2));
      },
    );

    test(
      'foreground recovery keeps active trip and existing streams',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: FakeOperatorRepository(
            operator: const OperatorModel(
              uid: 'operator-1',
              operatorId: 'operator-1',
              name: 'Operator',
              email: 'operator@example.com',
              isOnline: true,
            ),
          ),
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([
          _sampleBooking(id: 'active-1', status: BookingStatus.onTheWay),
        ]);
        await Future<void>.delayed(Duration.zero);
        final listenCount = bookingRepo.activeListenCount;

        await viewModel.recoverAfterForeground('operator-1');

        expect(viewModel.activeBookings, hasLength(1));
        expect(bookingRepo.activeListenCount, listenCount);
      },
    );

    test('markCancellationNoticeShown stores latest booking id', () async {
      final viewModel = createViewModel(
        bookingRepo: FakeOperatorBookingRepository(),
        operatorRepo: FakeOperatorRepository(),
      );

      viewModel.markCancellationNoticeShown('booking-x');

      expect(viewModel.lastCancelledNoticeBookingId, 'booking-x');
    });

    test(
      'navigation lifecycle initializes guidance from on-the-way active booking',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final operatorRepo = FakeOperatorRepository(
          operator: const OperatorModel(
            uid: 'operator-1',
            operatorId: 'OP-1',
            name: 'Captain Aiman',
            email: 'captain@example.com',
            isOnline: true,
          ),
        );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: operatorRepo,
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([
          _sampleBooking(
            id: 'trip-1',
            status: BookingStatus.onTheWay,
            operatorLat: 2.2015,
            operatorLng: 102.2515,
            routeToOriginPolyline: const [
              BookingRoutePoint(lat: 2.2000, lng: 102.2500),
              BookingRoutePoint(lat: 1.8000, lng: 101.8000),
              BookingRoutePoint(lat: 1.4000, lng: 101.4000),
              BookingRoutePoint(lat: 1.0000, lng: 101.0000),
            ],
          ),
        ]);

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(viewModel.navigationGuidance, isNotNull);
        expect(viewModel.navigationGuidance!.totalRouteMarkers, equals(4));
      },
    );

    test(
      'navigation lifecycle clears guidance when on-the-way booking disappears',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final operatorRepo = FakeOperatorRepository(
          operator: const OperatorModel(
            uid: 'operator-1',
            operatorId: 'OP-1',
            name: 'Captain Aiman',
            email: 'captain@example.com',
            isOnline: true,
          ),
        );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: operatorRepo,
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([
          _sampleBooking(
            id: 'trip-2',
            status: BookingStatus.onTheWay,
            operatorLat: 2.2010,
            operatorLng: 102.2510,
            routePolyline: const [
              BookingRoutePoint(lat: 2.2000, lng: 102.2500),
              BookingRoutePoint(lat: 2.2010, lng: 102.2510),
              BookingRoutePoint(lat: 2.2020, lng: 102.2520),
            ],
          ),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(viewModel.navigationGuidance, isNotNull);

        bookingRepo.emitActive([
          _sampleBooking(id: 'trip-2', status: BookingStatus.accepted),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(viewModel.navigationGuidance, isNull);
      },
    );

    test('navigation lifecycle resumes after refresh stream restart', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final operatorRepo = FakeOperatorRepository(
        operator: const OperatorModel(
          uid: 'operator-1',
          operatorId: 'OP-1',
          name: 'Captain Aiman',
          email: 'captain@example.com',
          isOnline: true,
        ),
      );
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
      );

      await viewModel.initialize('operator-1');
      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-3',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2012,
          operatorLng: 102.2512,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2012, lng: 102.2512),
            BookingRoutePoint(lat: 1.8000, lng: 101.8000),
            BookingRoutePoint(lat: 1.4000, lng: 101.4000),
            BookingRoutePoint(lat: 1.0000, lng: 101.0000),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(viewModel.navigationGuidance, isNotNull);

      await viewModel.refresh('operator-1');
      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-3',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2013,
          operatorLng: 102.2513,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2013, lng: 102.2513),
            BookingRoutePoint(lat: 1.8000, lng: 101.8000),
            BookingRoutePoint(lat: 1.4000, lng: 101.4000),
            BookingRoutePoint(lat: 1.0000, lng: 101.0000),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(viewModel.streamVersion, equals(1));
      expect(viewModel.navigationGuidance, isNotNull);
      expect(viewModel.navigationGuidance!.totalRouteMarkers, equals(4));
    });

    test(
      'refresh keeps active navigation when replacement stream briefly emits empty',
      () async {
        final bookingRepo = FakeOperatorBookingRepository();
        final operatorRepo = FakeOperatorRepository(
          operator: const OperatorModel(
            uid: 'operator-1',
            operatorId: 'OP-1',
            name: 'Captain Aiman',
            email: 'captain@example.com',
            isOnline: true,
          ),
        );
        final viewModel = createViewModel(
          bookingRepo: bookingRepo,
          operatorRepo: operatorRepo,
        );
        final activeBooking = _sampleBooking(
          id: 'trip-preserve',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2012,
          operatorLng: 102.2512,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2012, lng: 102.2512),
            BookingRoutePoint(lat: 1.8000, lng: 101.8000),
            BookingRoutePoint(lat: 1.4000, lng: 101.4000),
          ],
        );

        await viewModel.initialize('operator-1');
        bookingRepo.emitActive([activeBooking]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(viewModel.activeBookings, hasLength(1));
        expect(
          viewModel.homeSnapshot.activeBooking?.bookingId,
          'trip-preserve',
        );

        bookingRepo.bookingById['trip-preserve'] = activeBooking;
        await viewModel.refresh('operator-1');
        bookingRepo.emitActive(const <BookingModel>[]);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(viewModel.activeBookings, hasLength(1));
        expect(
          viewModel.homeSnapshot.activeBooking?.bookingId,
          'trip-preserve',
        );
        expect(viewModel.navigationGuidance, isNotNull);
      },
    );

    test('navigation lifecycle emits route progress alert', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final operatorRepo = FakeOperatorRepository(
        operator: const OperatorModel(
          uid: 'operator-1',
          operatorId: 'OP-1',
          name: 'Captain Aiman',
          email: 'captain@example.com',
          isOnline: true,
        ),
      );
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
      );

      final alerts = <OperatorNavigationAlert>[];
      final sub = OperatorNavigationAlertBus.stream.listen(alerts.add);

      await viewModel.initialize('operator-1');
      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-alert-1',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2010,
          operatorLng: 102.2510,
          routePolyline: const [
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
            BookingRoutePoint(lat: 2.2010, lng: 102.2510),
            BookingRoutePoint(lat: 2.2020, lng: 102.2520),
            BookingRoutePoint(lat: 2.2030, lng: 102.2530),
          ],
        ),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 25));
      await sub.cancel();

      expect(
        alerts.any(
          (a) => a.bookingId == 'trip-alert-1' && a.title == 'Route progress',
        ),
        isTrue,
      );
    });

    test('navigation lifecycle emits off-route and resume alerts', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final operatorRepo = FakeOperatorRepository(
        operator: const OperatorModel(
          uid: 'operator-1',
          operatorId: 'OP-1',
          name: 'Captain Aiman',
          email: 'captain@example.com',
          isOnline: true,
        ),
      );
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
      );

      final alerts = <OperatorNavigationAlert>[];
      final sub = OperatorNavigationAlertBus.stream.listen(alerts.add);

      await viewModel.initialize('operator-1');

      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-alert-2',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2010,
          operatorLng: 102.2500,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
            BookingRoutePoint(lat: 2.2010, lng: 102.2500),
            BookingRoutePoint(lat: 2.2020, lng: 102.2500),
            BookingRoutePoint(lat: 2.2030, lng: 102.2500),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-alert-2',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2010,
          operatorLng: 102.2550,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
            BookingRoutePoint(lat: 2.2010, lng: 102.2500),
            BookingRoutePoint(lat: 2.2020, lng: 102.2500),
            BookingRoutePoint(lat: 2.2030, lng: 102.2500),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-alert-2',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2020,
          operatorLng: 102.2500,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
            BookingRoutePoint(lat: 2.2010, lng: 102.2500),
            BookingRoutePoint(lat: 2.2020, lng: 102.2500),
            BookingRoutePoint(lat: 2.2030, lng: 102.2500),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-alert-2',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2020,
          operatorLng: 102.2550,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
            BookingRoutePoint(lat: 2.2010, lng: 102.2500),
            BookingRoutePoint(lat: 2.2020, lng: 102.2500),
            BookingRoutePoint(lat: 2.2030, lng: 102.2500),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await sub.cancel();

      final alertTitles = alerts
          .where((a) => a.bookingId == 'trip-alert-2')
          .map((a) => a.title)
          .toList();

      expect(alertTitles, contains('Off-route detected'));
      expect(alertTitles, contains('Route resumed'));
      expect(
        alertTitles.where((title) => title == 'Off-route detected'),
        hasLength(1),
      );
    });

    test('navigation guidance follows booking status transitions', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final operatorRepo = FakeOperatorRepository(
        operator: const OperatorModel(
          uid: 'operator-1',
          operatorId: 'OP-1',
          name: 'Captain Aiman',
          email: 'captain@example.com',
          isOnline: true,
        ),
      );
      final viewModel = createViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
      );

      await viewModel.initialize('operator-1');

      bookingRepo.emitActive([
        _sampleBooking(id: 'trip-transition-1', status: BookingStatus.accepted),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(viewModel.navigationGuidance, isNull);

      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-transition-1',
          status: BookingStatus.onTheWay,
          operatorLat: 2.2011,
          operatorLng: 102.2511,
          routePolyline: const [
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
            BookingRoutePoint(lat: 2.2010, lng: 102.2510),
            BookingRoutePoint(lat: 2.2020, lng: 102.2520),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(viewModel.navigationGuidance, isNotNull);

      bookingRepo.emitActive([
        _sampleBooking(
          id: 'trip-transition-1',
          status: BookingStatus.completed,
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(viewModel.navigationGuidance, isNull);
    });
  });

  group('Operator home helpers', () {
    test('isAcceptedBookingStale returns true for old accepted bookings', () {
      final booking = _sampleBooking(
        id: 'stale-1',
        status: BookingStatus.accepted,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 6)),
      );

      expect(isAcceptedBookingStale(booking), isTrue);
    });

    test('format helpers produce expected labels', () {
      expect(formatCurrency(12.5), 'RM 12.50');
      expect(formatStatusLabel('on_the_way'), 'On The Way');
      expect(
        formatBookingTimestamp(DateTime(2026, 3, 15, 9, 7)),
        '15/03/2026 09:07',
      );
    });

    test('location publish helper allows first publish without history', () {
      final shouldPublish = shouldPublishOperatorPosition(
        now: DateTime(2026, 3, 19, 10, 0, 0),
        minInterval: const Duration(seconds: 6),
        minDistanceMeters: 20,
        currentLat: 2.190,
        currentLng: 102.250,
        lastPublishedAt: null,
        lastLat: null,
        lastLng: null,
      );

      expect(shouldPublish, isTrue);
    });

    test(
      'location publish helper blocks when below time and distance limits',
      () {
        final shouldPublish = shouldPublishOperatorPosition(
          now: DateTime(2026, 3, 19, 10, 0, 3),
          minInterval: const Duration(seconds: 6),
          minDistanceMeters: 20,
          currentLat: 2.190001,
          currentLng: 102.250001,
          lastPublishedAt: DateTime(2026, 3, 19, 10, 0, 0),
          lastLat: 2.190000,
          lastLng: 102.250000,
        );

        expect(shouldPublish, isFalse);
      },
    );

    test(
      'location publish helper allows when interval threshold is reached',
      () {
        final shouldPublish = shouldPublishOperatorPosition(
          now: DateTime(2026, 3, 19, 10, 0, 8),
          minInterval: const Duration(seconds: 6),
          minDistanceMeters: 20,
          currentLat: 2.190001,
          currentLng: 102.250001,
          lastPublishedAt: DateTime(2026, 3, 19, 10, 0, 0),
          lastLat: 2.190000,
          lastLng: 102.250000,
        );

        expect(shouldPublish, isTrue);
      },
    );

    test(
      'location publish helper allows when distance threshold is reached',
      () {
        final shouldPublish = shouldPublishOperatorPosition(
          now: DateTime(2026, 3, 19, 10, 0, 2),
          minInterval: const Duration(seconds: 6),
          minDistanceMeters: 20,
          currentLat: 2.190400,
          currentLng: 102.250400,
          lastPublishedAt: DateTime(2026, 3, 19, 10, 0, 0),
          lastLat: 2.190000,
          lastLng: 102.250000,
        );

        expect(shouldPublish, isTrue);
      },
    );

    test('navigation helper resolves route progress and ETA from polyline', () {
      final booking = BookingModel(
        bookingId: 'nav-1',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2030,
        destinationLng: 102.2530,
        routeToOriginPolyline: const [
          BookingRoutePoint(lat: 2.2030, lng: 102.2530),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
        ],
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        totalFare: 12,
        paymentMethod: PaymentMethods.creditCard,
        paymentStatus: 'paid',
        status: BookingStatus.onTheWay,
        operatorUid: 'operator-1',
        rejectedBy: const [],
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2014,
        currentLng: 102.2514,
        now: DateTime(2026, 3, 19, 10, 0, 0),
        reportedSpeedMps: 4.0,
      );

      expect(guidance, isNotNull);
      expect(guidance!.nearestRouteMarker, inInclusiveRange(1, 4));
      expect(guidance.nextRouteMarker, inInclusiveRange(1, 4));
      expect(guidance.progressFraction, inInclusiveRange(0.0, 1.0));
      expect(guidance.remainingDistanceMeters, greaterThan(0));
      expect(guidance.eta, isNotNull);
      expect(guidance.isOffRoute, isFalse);
    });

    test('navigation helper keeps route marker progression monotonic', () {
      final booking = BookingModel(
        bookingId: 'nav-2',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2030,
        destinationLng: 102.2530,
        routeToOriginPolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
          BookingRoutePoint(lat: 2.2030, lng: 102.2530),
        ],
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        totalFare: 12,
        paymentMethod: PaymentMethods.creditCard,
        paymentStatus: 'paid',
        status: BookingStatus.onTheWay,
        operatorUid: 'operator-1',
        operatorLat: 2.2020,
        operatorLng: 102.2520,
        rejectedBy: const [],
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2020,
        currentLng: 102.2520,
        now: DateTime(2026, 3, 19, 10, 0, 0),
        lastResolvedRouteMarker: 3,
      );

      expect(guidance, isNotNull);
      expect(guidance!.nearestRouteMarker, greaterThanOrEqualTo(3));
    });

    test('navigation helper uses routeToOriginPolyline before pickup', () {
      final booking = BookingModel(
        bookingId: 'nav-phase-1',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2050,
        destinationLng: 102.2600,
        routePolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2025, lng: 102.2550),
          BookingRoutePoint(lat: 2.2050, lng: 102.2600),
        ],
        routeToOriginPolyline: const [
          BookingRoutePoint(lat: 2.1900, lng: 102.2400),
          BookingRoutePoint(lat: 2.1950, lng: 102.2450),
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
        ],
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        totalFare: 12,
        paymentMethod: PaymentMethods.creditCard,
        paymentStatus: 'paid',
        status: BookingStatus.onTheWay,
        operatorUid: 'operator-1',
        operatorLat: 2.1950,
        operatorLng: 102.2450,
        rejectedBy: const [],
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.1951,
        currentLng: 102.2451,
        now: DateTime(2026, 3, 19, 10, 0, 0),
      );

      expect(guidance, isNotNull);
      expect(guidance!.nearestRouteMarker, inInclusiveRange(1, 3));
      expect(guidance.nextRouteMarker, inInclusiveRange(1, 3));
      expect(guidance.offRouteDistanceMeters, lessThan(80));
    });

    test(
      'navigation helper phase 2 fallback starts from operator position',
      () {
        final booking = BookingModel(
          bookingId: 'nav-phase-2-fallback',
          userId: 'user-1',
          userName: 'Passenger One',
          userPhone: '0123456789',
          origin: 'Jetty A',
          destination: 'Jetty B',
          originLat: 2.2010,
          originLng: 102.2490,
          destinationLat: 2.1930,
          destinationLng: 102.2460,
          routeToDestinationPolyline: const [],
          adultCount: 1,
          childCount: 0,
          passengerCount: 1,
          totalFare: 12,
          paymentMethod: PaymentMethods.creditCard,
          paymentStatus: 'paid',
          status: BookingStatus.onTheWay,
          operatorUid: 'operator-1',
          operatorLat: 2.1960,
          operatorLng: 102.2472,
          passengerPickedUpAt: DateTime(2026, 3, 19, 10, 0, 0),
          rejectedBy: const [],
        );

        final guidance = computeOperatorNavigationGuidance(
          booking: booking,
          currentLat: 2.1960,
          currentLng: 102.2472,
          now: DateTime(2026, 3, 19, 10, 5, 0),
          reportedSpeedMps: 4.0,
        );

        expect(guidance, isNotNull);
        expect(guidance!.remainingDistanceMeters, lessThan(400));
        expect(guidance.eta, isNotNull);
      },
    );

    test('navigation helper flags off-route when far from segment', () {
      final booking = BookingModel(
        bookingId: 'nav-3',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2050,
        destinationLng: 102.2500,
        routeToOriginPolyline: const [
          BookingRoutePoint(lat: 2.2050, lng: 102.2500),
          BookingRoutePoint(lat: 2.2030, lng: 102.2500),
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
        ],
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        totalFare: 12,
        paymentMethod: PaymentMethods.creditCard,
        paymentStatus: 'paid',
        status: BookingStatus.onTheWay,
        operatorUid: 'operator-1',
        operatorLat: 2.2050,
        operatorLng: 102.2500,
        rejectedBy: const [],
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2020,
        currentLng: 102.2550,
        now: DateTime(2026, 3, 19, 10, 0, 0),
        offRouteToleranceMeters: 50,
      );

      expect(guidance, isNotNull);
      expect(guidance!.isOffRoute, isTrue);
      expect(guidance.offRouteDistanceMeters, greaterThan(50));
      expect(guidance.offRouteSeverity, OperatorOffRouteSeverity.severe);
      expect(guidance.shouldPauseProgress, isTrue);
      expect(guidance.shouldPauseEta, isTrue);
      expect(guidance.rejoinPoint, isNotNull);
    });

    test('navigation helper does not flag off-route at exact tolerance', () {
      final booking = BookingModel(
        bookingId: 'nav-4',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2050,
        destinationLng: 102.2500,
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        totalFare: 12,
        paymentMethod: PaymentMethods.creditCard,
        paymentStatus: 'paid',
        status: BookingStatus.onTheWay,
        operatorUid: 'operator-1',
        rejectedBy: const [],
      );

      final baseline = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2000,
        currentLng: 102.2550,
        now: DateTime(2026, 3, 19, 10, 0, 0),
        offRouteToleranceMeters: 1,
      );
      expect(baseline, isNotNull);

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2000,
        currentLng: 102.2550,
        now: DateTime(2026, 3, 19, 10, 0, 0),
        offRouteToleranceMeters: baseline!.offRouteDistanceMeters,
      );

      expect(guidance, isNotNull);
      expect(
        guidance!.offRouteDistanceMeters,
        closeTo(baseline.offRouteDistanceMeters, 0.0001),
      );
      expect(guidance.isOffRoute, isFalse);
    });

    test(
      'navigation helper marks moderate off-route ETA as low confidence',
      () {
        final booking = BookingModel(
          bookingId: 'nav-4b',
          userId: 'user-1',
          userName: 'Passenger One',
          userPhone: '0123456789',
          origin: 'Jetty A',
          destination: 'Jetty B',
          originLat: 2.2000,
          originLng: 102.2500,
          destinationLat: 2.2050,
          destinationLng: 102.2500,
          routeToOriginPolyline: const [
            BookingRoutePoint(lat: 2.2050, lng: 102.2500),
            BookingRoutePoint(lat: 2.2030, lng: 102.2500),
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          ],
          adultCount: 1,
          childCount: 0,
          passengerCount: 1,
          totalFare: 12,
          paymentMethod: PaymentMethods.creditCard,
          paymentStatus: 'paid',
          status: BookingStatus.onTheWay,
          operatorUid: 'operator-1',
          operatorLat: 2.2050,
          operatorLng: 102.2500,
          rejectedBy: const [],
        );

        final guidance = computeOperatorNavigationGuidance(
          booking: booking,
          currentLat: 2.2040,
          currentLng: 102.2518,
          now: DateTime(2026, 3, 19, 10, 0, 0),
          smoothedSpeedMps: 3.5,
        );

        expect(guidance, isNotNull);
        expect(guidance!.offRouteSeverity, OperatorOffRouteSeverity.moderate);
        expect(guidance.isEtaLowConfidence, isTrue);
        expect(guidance.shouldPauseEta, isFalse);
        expect(guidance.eta, isNotNull);
        expect(guidance.rejoinPoint, isNotNull);
      },
    );

    test(
      'navigation helper derives ETA from sample speed and gates low speed',
      () {
        final booking = BookingModel(
          bookingId: 'nav-5',
          userId: 'user-1',
          userName: 'Passenger One',
          userPhone: '0123456789',
          origin: 'Jetty A',
          destination: 'Jetty B',
          originLat: 2.2000,
          originLng: 102.2500,
          destinationLat: 2.2100,
          destinationLng: 102.2500,
          adultCount: 1,
          childCount: 0,
          passengerCount: 1,
          totalFare: 12,
          paymentMethod: PaymentMethods.creditCard,
          paymentStatus: 'paid',
          status: BookingStatus.onTheWay,
          operatorUid: 'operator-1',
          rejectedBy: const [],
        );

        final withDerivedSpeed = computeOperatorNavigationGuidance(
          booking: booking,
          currentLat: 2.2010,
          currentLng: 102.2500,
          now: DateTime(2026, 3, 19, 10, 0, 10),
          reportedSpeedMps: null,
          lastSampleAt: DateTime(2026, 3, 19, 10, 0, 0),
          lastSampleLat: 2.2000,
          lastSampleLng: 102.2500,
        );

        expect(withDerivedSpeed, isNotNull);
        expect(withDerivedSpeed!.speedMetersPerSecond, greaterThan(0.5));
        expect(withDerivedSpeed.eta, isNotNull);

        final withLowSpeed = computeOperatorNavigationGuidance(
          booking: booking,
          currentLat: 2.2010,
          currentLng: 102.2500,
          now: DateTime(2026, 3, 19, 10, 0, 10),
          reportedSpeedMps: 0.2,
        );

        expect(withLowSpeed, isNotNull);
        expect(withLowSpeed!.speedMetersPerSecond, isNull);
        expect(withLowSpeed.eta, isNull);
      },
    );

    test('navigation helper does not warn while approaching current stop', () {
      final booking = _sampleBooking(
        id: 'approaching-pickup',
        status: BookingStatus.onTheWay,
        routePolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
        ],
        poolStopPlan: _twoStopPlan(),
        currentStopIndex: 0,
        currentStopId: 'pickup-active-1',
        currentPoolStopId: 'pickup-active-1',
        routeDirection: 'forward',
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2005,
        currentLng: 102.2505,
        now: DateTime(2026, 3, 19, 10, 0, 10),
        lastSampleAt: DateTime(2026, 3, 19, 10, 0, 0),
        lastSampleLat: 2.2000,
        lastSampleLng: 102.2500,
      );

      expect(guidance, isNotNull);
      expect(
        guidance!.stopOvershootSeverity,
        OperatorStopOvershootSeverity.none,
      );
    });

    test('navigation helper ignores projection jitter near current stop', () {
      final booking = _sampleBooking(
        id: 'pickup-jitter',
        status: BookingStatus.onTheWay,
        routePolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
        ],
        poolStopPlan: _twoStopPlan(),
        currentStopIndex: 0,
        currentStopId: 'pickup-active-1',
        currentPoolStopId: 'pickup-active-1',
        routeDirection: 'forward',
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2014,
        currentLng: 102.2514,
        now: DateTime(2026, 3, 19, 10, 0, 10),
        lastSampleAt: DateTime(2026, 3, 19, 10, 0, 0),
        lastSampleLat: 2.2020,
        lastSampleLng: 102.2520,
      );

      expect(guidance, isNotNull);
      expect(
        guidance!.stopOvershootSeverity,
        isNot(OperatorStopOvershootSeverity.missed),
      );
    });

    test('navigation helper warns when first pickup stop is missed', () {
      final booking = _sampleBooking(
        id: 'missed-pickup',
        status: BookingStatus.onTheWay,
        routePolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
        ],
        poolStopPlan: _twoStopPlan(),
        currentStopIndex: 0,
        currentStopId: 'pickup-active-1',
        currentPoolStopId: 'pickup-active-1',
        routeDirection: 'forward',
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2020,
        currentLng: 102.2520,
        now: DateTime(2026, 3, 19, 10, 0, 10),
        lastSampleAt: DateTime(2026, 3, 19, 10, 0, 0),
        lastSampleLat: 2.2012,
        lastSampleLng: 102.2512,
      );

      expect(guidance, isNotNull);
      expect(
        guidance!.stopOvershootSeverity,
        OperatorStopOvershootSeverity.missed,
      );
    });

    test('navigation helper warns when reverse-route stop is missed', () {
      final booking = _sampleBooking(
        id: 'missed-reverse-pickup',
        status: BookingStatus.onTheWay,
        routePolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
        ],
        poolStopPlan: _twoStopPlan(),
        currentStopIndex: 0,
        currentStopId: 'pickup-active-1',
        currentPoolStopId: 'pickup-active-1',
        routeDirection: 'reverse',
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2000,
        currentLng: 102.2500,
        now: DateTime(2026, 3, 19, 10, 0, 10),
        lastSampleAt: DateTime(2026, 3, 19, 10, 0, 0),
        lastSampleLat: 2.2008,
        lastSampleLng: 102.2508,
      );

      expect(guidance, isNotNull);
      expect(
        guidance!.stopOvershootSeverity,
        OperatorStopOvershootSeverity.missed,
      );
    });

    test(
      'navigation helper suppresses missed stop while severely off route',
      () {
        final booking = _sampleBooking(
          id: 'off-route-pickup',
          status: BookingStatus.onTheWay,
          routePolyline: const [
            BookingRoutePoint(lat: 2.2000, lng: 102.2500),
            BookingRoutePoint(lat: 2.2010, lng: 102.2510),
            BookingRoutePoint(lat: 2.2020, lng: 102.2520),
          ],
          poolStopPlan: _twoStopPlan(),
          currentStopIndex: 0,
          currentStopId: 'pickup-active-1',
          currentPoolStopId: 'pickup-active-1',
          routeDirection: 'forward',
        );

        final guidance = computeOperatorNavigationGuidance(
          booking: booking,
          currentLat: 2.2020,
          currentLng: 102.2620,
          now: DateTime(2026, 3, 19, 10, 0, 10),
          lastSampleAt: DateTime(2026, 3, 19, 10, 0, 0),
          lastSampleLat: 2.2012,
          lastSampleLng: 102.2612,
        );

        expect(guidance, isNotNull);
        expect(guidance!.offRouteSeverity, OperatorOffRouteSeverity.severe);
        expect(
          guidance.stopOvershootSeverity,
          OperatorStopOvershootSeverity.none,
        );
      },
    );
  });
}

class FakeOperatorRepository extends OperatorRepository {
  FakeOperatorRepository({this.operator})
    : super(firestore: FakeFirebaseFirestore());

  OperatorModel? operator;
  bool? lastOnlineStatus;
  Duration? setOnlineStatusDelay;
  Object? setOnlineStatusError;

  @override
  Future<OperatorModel?> getOperator(String uid) async => operator;

  @override
  Future<void> syncPresence(String uid, {required bool isOnline}) async {}

  @override
  Future<void> setOnlineStatus(String uid, {required bool isOnline}) async {
    if (setOnlineStatusDelay != null) {
      await Future<void>.delayed(setOnlineStatusDelay!);
    }
    final error = setOnlineStatusError;
    if (error != null) {
      throw error;
    }
    lastOnlineStatus = isOnline;
    operator =
        (operator ??
                OperatorModel(
                  uid: uid,
                  operatorId: uid,
                  name: '',
                  email: '',
                  isOnline: false,
                ))
            .copyWith(isOnline: isOnline);
  }
}

class FakeOperatorBookingRepository extends BookingRepository {
  FakeOperatorBookingRepository()
    : _activeController = StreamController<List<BookingModel>>.broadcast(),
      _pendingController = StreamController<List<BookingModel>>.broadcast(),
      super(firestore: FakeFirebaseFirestore());

  final StreamController<List<BookingModel>> _activeController;
  final StreamController<List<BookingModel>> _pendingController;

  int activeListenCount = 0;
  int pendingListenCount = 0;
  int releasedCount = 0;
  Object? releaseAllError;
  String? lastAcceptedBookingId;
  String? lastAcceptedOperatorId;
  String? lastRejectedBookingId;
  OperationResult acceptResult = const OperationSuccess(
    'Booking accepted successfully.',
  );
  OperationResult rejectResult = const OperationSuccess('Booking rejected.');
  OperationResult releaseResult = const OperationSuccess('Booking released.');
  OperationResult startResult = const OperationSuccess(
    'Trip started successfully.',
  );
  OperationResult markPickedUpResult = const OperationSuccess(
    'Passenger marked as picked up.',
  );
  OperationResult completeResult = const OperationSuccess(
    'Trip completed successfully.',
  );
  Completer<OperationResult>? acceptCompleter;
  final Map<String, BookingModel?> bookingById = <String, BookingModel?>{};

  @override
  Stream<List<BookingModel>> streamActiveBookings(String operatorId) {
    activeListenCount += 1;
    return _activeController.stream;
  }

  @override
  Stream<List<BookingModel>> streamPendingBookings() {
    pendingListenCount += 1;
    return _pendingController.stream;
  }

  @override
  Future<BookingModel?> getBooking(String bookingId) async {
    return bookingById[bookingId];
  }

  @override
  Future<int> releaseAllAcceptedBookings(String operatorId) async {
    final error = releaseAllError;
    if (error != null) {
      throw error;
    }
    return releasedCount;
  }

  @override
  Future<OperationResult> acceptBooking({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
    DateTime? locationUpdatedAt,
    String? routeDirection,
  }) async {
    lastAcceptedBookingId = bookingId;
    lastAcceptedOperatorId = operatorId;
    if (acceptCompleter != null) {
      return acceptCompleter!.future;
    }
    return acceptResult;
  }

  @override
  Future<OperationResult> rejectBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    lastRejectedBookingId = bookingId;
    return rejectResult;
  }

  @override
  Future<OperationResult> releaseBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    return releaseResult;
  }

  @override
  Future<OperationResult> startTrip({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) async {
    return startResult;
  }

  @override
  Future<OperationResult> markPassengerPickedUp({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) async {
    return markPickedUpResult;
  }

  @override
  Future<OperationResult> completeTrip({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) async {
    return completeResult;
  }

  void emitActive(List<BookingModel> bookings) {
    _activeController.add(bookings);
  }

  void emitPending(List<BookingModel> bookings) {
    _pendingController.add(bookings);
  }
}

BookingModel _sampleBooking({
  required String id,
  required BookingStatus status,
  List<String> rejectedBy = const [],
  List<BookingRoutePoint> routePolyline = const [],
  List<BookingRoutePoint> routeToOriginPolyline = const [],
  List<BookingRoutePoint> routeToDestinationPolyline = const [],
  List<PoolStopPlanItem> poolStopPlan = const [],
  int? currentStopIndex,
  String? currentStopId,
  String? currentPoolStopId,
  String? poolGroupId,
  String? routeDirection,
  double? operatorLat,
  double? operatorLng,
  DateTime? updatedAt,
}) {
  return BookingModel(
    bookingId: id,
    userId: 'user-1',
    userName: 'Passenger One',
    userPhone: '0123456789',
    origin: 'Jetty A',
    destination: 'Jetty B',
    originLat: 1.0,
    originLng: 101.0,
    destinationLat: 2.0,
    destinationLng: 102.0,
    routePolyline: routePolyline,
    routeToOriginPolyline: routeToOriginPolyline,
    routeToDestinationPolyline: routeToDestinationPolyline,
    poolStopPlan: poolStopPlan,
    currentStopIndex: currentStopIndex,
    currentStopId: currentStopId,
    currentPoolStopId: currentPoolStopId,
    poolGroupId: poolGroupId,
    routeDirection: routeDirection,
    adultCount: 1,
    childCount: 0,
    passengerCount: 1,
    totalFare: 12.0,
    fareSnapshotId: 'fare-snapshot-test',
    paymentMethod: PaymentMethods.creditCard,
    paymentStatus: 'paid',
    status: status,
    operatorUid: status == BookingStatus.pending ? null : 'operator-1',
    operatorLat: operatorLat,
    operatorLng: operatorLng,
    rejectedBy: rejectedBy,
    createdAt: DateTime(2026, 3, 15, 10, 0),
    updatedAt: updatedAt ?? DateTime(2026, 3, 15, 10, 5),
    cancelledAt: null,
  );
}

List<PoolStopPlanItem> _twoStopPlan() {
  return const [
    PoolStopPlanItem(
      stopId: 'pickup-active-1',
      index: 0,
      stopType: 'pickup',
      stopName: 'Jetty A',
      lat: 2.2010,
      lng: 102.2510,
      routePositionMeters: 150,
      bookingIds: ['active-1'],
      status: 'active',
    ),
    PoolStopPlanItem(
      stopId: 'dropoff-active-1',
      index: 1,
      stopType: 'dropoff',
      stopName: 'Jetty B',
      lat: 2.2020,
      lng: 102.2520,
      routePositionMeters: 300,
      bookingIds: ['active-1'],
      status: 'pending',
    ),
  ];
}
