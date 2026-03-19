import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
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
        final viewModel = OperatorHomeViewModel(
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
        final viewModel = OperatorHomeViewModel(
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
        final viewModel = OperatorHomeViewModel(
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

    test('acceptBooking delegates operator id and resets busy state', () async {
      final bookingRepo = FakeOperatorBookingRepository();
      final viewModel = OperatorHomeViewModel(
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
      final viewModel = OperatorHomeViewModel(
        bookingRepo: FakeOperatorBookingRepository(),
        operatorRepo: FakeOperatorRepository(),
      );

      final result = await viewModel.acceptBooking('booking-1');

      expect(result, isA<OperationFailure>());
      expect((result as OperationFailure).title, 'Not initialised');
      expect(viewModel.isUpdatingBooking, isFalse);
    });

    test('busy guard blocks overlapping booking operations', () async {
      final bookingRepo = FakeOperatorBookingRepository()
        ..acceptCompleter = Completer<OperationResult>();
      final viewModel = OperatorHomeViewModel(
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
        final viewModel = OperatorHomeViewModel(
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
          contains('You no longer have permission to perform this action'),
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
      final viewModel = OperatorHomeViewModel(
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
      final viewModel = OperatorHomeViewModel(
        bookingRepo: bookingRepo,
        operatorRepo: FakeOperatorRepository(),
      );

      await viewModel.initialize('operator-1');
      expect(viewModel.streamVersion, 0);

      await viewModel.refresh('operator-1');

      expect(viewModel.streamVersion, 1);
      expect(viewModel.isRefreshing, isFalse);
      expect(bookingRepo.activeListenCount, greaterThanOrEqualTo(2));
      expect(bookingRepo.pendingListenCount, greaterThanOrEqualTo(2));
    });

    test('markCancellationNoticeShown stores latest booking id', () async {
      final viewModel = OperatorHomeViewModel(
        bookingRepo: FakeOperatorBookingRepository(),
        operatorRepo: FakeOperatorRepository(),
      );

      viewModel.markCancellationNoticeShown('booking-x');

      expect(viewModel.lastCancelledNoticeBookingId, 'booking-x');
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

    test('location publish helper blocks when below time and distance limits', () {
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
    });

    test('location publish helper allows when interval threshold is reached', () {
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
    });

    test('location publish helper allows when distance threshold is reached', () {
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
    });

    test('navigation helper resolves checkpoint progress and ETA from polyline', () {
      final booking = BookingModel(
        bookingId: 'nav-1',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        corridorId: 'melaka_main_01',
        corridorVersion: 1,
        originCheckpointSeq: 3,
        destinationCheckpointSeq: 6,
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2030,
        destinationLng: 102.2530,
        routePolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
          BookingRoutePoint(lat: 2.2030, lng: 102.2530),
        ],
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        adultFare: 12,
        childFare: 6,
        adultSubtotal: 12,
        childSubtotal: 0,
        fare: 12,
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
      expect(guidance!.nearestCheckpointSeq, inInclusiveRange(3, 6));
      expect(guidance.nextCheckpointSeq, inInclusiveRange(3, 6));
      expect(guidance.progressFraction, inInclusiveRange(0.0, 1.0));
      expect(guidance.remainingDistanceMeters, greaterThan(0));
      expect(guidance.eta, isNotNull);
      expect(guidance.isOffRoute, isFalse);
    });

    test('navigation helper keeps checkpoint progression monotonic', () {
      final booking = BookingModel(
        bookingId: 'nav-2',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        corridorId: 'melaka_main_01',
        corridorVersion: 1,
        originCheckpointSeq: 1,
        destinationCheckpointSeq: 4,
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2030,
        destinationLng: 102.2530,
        routePolyline: const [
          BookingRoutePoint(lat: 2.2000, lng: 102.2500),
          BookingRoutePoint(lat: 2.2010, lng: 102.2510),
          BookingRoutePoint(lat: 2.2020, lng: 102.2520),
          BookingRoutePoint(lat: 2.2030, lng: 102.2530),
        ],
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        adultFare: 12,
        childFare: 6,
        adultSubtotal: 12,
        childSubtotal: 0,
        fare: 12,
        totalFare: 12,
        paymentMethod: PaymentMethods.creditCard,
        paymentStatus: 'paid',
        status: BookingStatus.onTheWay,
        operatorUid: 'operator-1',
        rejectedBy: const [],
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2002,
        currentLng: 102.2502,
        now: DateTime(2026, 3, 19, 10, 0, 0),
        lastResolvedCheckpointSeq: 3,
      );

      expect(guidance, isNotNull);
      expect(guidance!.nearestCheckpointSeq, greaterThanOrEqualTo(3));
    });

    test('navigation helper flags off-route when far from segment', () {
      final booking = BookingModel(
        bookingId: 'nav-3',
        userId: 'user-1',
        userName: 'Passenger One',
        userPhone: '0123456789',
        origin: 'Jetty A',
        destination: 'Jetty B',
        corridorId: 'melaka_main_01',
        corridorVersion: 1,
        originCheckpointSeq: 1,
        destinationCheckpointSeq: 2,
        originLat: 2.2000,
        originLng: 102.2500,
        destinationLat: 2.2050,
        destinationLng: 102.2500,
        adultCount: 1,
        childCount: 0,
        passengerCount: 1,
        adultFare: 12,
        childFare: 6,
        adultSubtotal: 12,
        childSubtotal: 0,
        fare: 12,
        totalFare: 12,
        paymentMethod: PaymentMethods.creditCard,
        paymentStatus: 'paid',
        status: BookingStatus.onTheWay,
        operatorUid: 'operator-1',
        rejectedBy: const [],
      );

      final guidance = computeOperatorNavigationGuidance(
        booking: booking,
        currentLat: 2.2000,
        currentLng: 102.2550,
        now: DateTime(2026, 3, 19, 10, 0, 0),
        offRouteToleranceMeters: 50,
      );

      expect(guidance, isNotNull);
      expect(guidance!.isOffRoute, isTrue);
      expect(guidance.offRouteDistanceMeters, greaterThan(50));
    });
  });
}

class FakeOperatorRepository extends OperatorRepository {
  FakeOperatorRepository({this.operator})
    : super(firestore: FakeFirebaseFirestore());

  OperatorModel? operator;
  bool? lastOnlineStatus;
  Duration? setOnlineStatusDelay;

  @override
  Future<OperatorModel?> getOperator(String uid) async => operator;

  @override
  Future<void> setOnlineStatus(String uid, {required bool isOnline}) async {
    if (setOnlineStatusDelay != null) {
      await Future<void>.delayed(setOnlineStatusDelay!);
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
  OperationResult completeResult = const OperationSuccess(
    'Trip completed successfully.',
  );
  Completer<OperationResult>? acceptCompleter;

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
  Future<int> releaseAllAcceptedBookings(String operatorId) async =>
      releasedCount;

  @override
  Future<OperationResult> acceptBooking({
    required String bookingId,
    required String operatorId,
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
  Future<OperationResult> completeTrip({
    required String bookingId,
    required String operatorId,
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
    adultCount: 1,
    childCount: 0,
    passengerCount: 1,
    adultFare: 12.0,
    childFare: 6.0,
    adultSubtotal: 12.0,
    childSubtotal: 0.0,
    fare: 12.0,
    totalFare: 12.0,
    paymentMethod: PaymentMethods.creditCard,
    paymentStatus: 'paid',
    status: status,
    operatorUid: status == BookingStatus.pending ? null : 'operator-1',
    rejectedBy: rejectedBy,
    createdAt: DateTime(2026, 3, 15, 10, 0),
    updatedAt: updatedAt ?? DateTime(2026, 3, 15, 10, 5),
    cancelledAt: null,
  );
}
