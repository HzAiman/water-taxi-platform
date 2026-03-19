import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/features/home/presentation/pages/operator_home_screen.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:provider/provider.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const geolocatorChannels = <String>[
    'flutter.baseflow.com/geolocator',
    'flutter.baseflow.com/geolocator_android',
  ];

  Future<dynamic> geolocatorHandler(MethodCall call) async {
    switch (call.method) {
      case 'isLocationServiceEnabled':
        return false;
      case 'checkPermission':
        return 2;
      case 'requestPermission':
        return 2;
      default:
        return null;
    }
  }

  setUpAll(() {
    setupFirebaseCoreMocks();

    for (final channelName in geolocatorChannels) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channelName),
        geolocatorHandler,
      );
    }

    messenger.setMockMethodCallHandler(
      const MethodChannel('operator_app/maps_config'),
      (MethodCall call) async {
        return <String, dynamic>{'injected': true, 'preview': 'test'};
      },
    );
  });

  setUp(() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  });

  tearDownAll(() {
    for (final channelName in geolocatorChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channelName), null);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('operator_app/maps_config'),
      null,
    );
  });

  Widget buildTestWidget({
    String? operatorId,
    String? operatorEmail,
    _FakeOperatorRepository? operatorRepo,
    _FakeBookingRepository? bookingRepo,
  }) {
    final effectiveOperatorRepo = operatorRepo ?? _FakeOperatorRepository();
    final effectiveBookingRepo = bookingRepo ?? _FakeBookingRepository();

    return ChangeNotifierProvider<OperatorHomeViewModel>(
      create: (_) => OperatorHomeViewModel(
        bookingRepo: effectiveBookingRepo,
        operatorRepo: effectiveOperatorRepo,
      ),
      child: MaterialApp(
        home: OperatorHomeScreen(
          testOperatorId: operatorId,
          testOperatorEmail: operatorEmail,
          skipRuntimeChecks: true,
          mapBuilder:
              ({
                required initialCameraPosition,
                required hasLocationPermission,
                required onMapCreated,
              }) {
                return const SizedBox(key: ValueKey('mock-map'));
              },
        ),
      ),
    );
  }

  testWidgets('shows signed-out placeholder when no Firebase user', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
  });

  testWidgets('does not show online toggle when signed out', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('Go Online'), findsNothing);
    expect(find.text('Go Offline'), findsNothing);
  });

  testWidgets('signed-in operator shows offline state and go-online button', (
    tester,
  ) async {
    final operatorRepo = _FakeOperatorRepository(
      operator: const OperatorModel(
        uid: 'operator-1',
        operatorId: 'OP-1',
        name: 'Captain Aiman',
        email: 'captain@example.com',
        isOnline: false,
      ),
    );

    await tester.pumpWidget(
      buildTestWidget(
        operatorId: 'operator-1',
        operatorEmail: 'captain@example.com',
        operatorRepo: operatorRepo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mock-map')), findsOneWidget);
    expect(find.text('Not signed in'), findsNothing);
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.text('Go Online'), findsOneWidget);
  });

  testWidgets('signed-in operator can toggle online status from button', (
    tester,
  ) async {
    final operatorRepo = _FakeOperatorRepository(
      operator: const OperatorModel(
        uid: 'operator-1',
        operatorId: 'OP-1',
        name: 'Captain Aiman',
        email: 'captain@example.com',
        isOnline: false,
      ),
    );

    await tester.pumpWidget(
      buildTestWidget(
        operatorId: 'operator-1',
        operatorEmail: 'captain@example.com',
        operatorRepo: operatorRepo,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go Online'));
    await tester.pumpAndSettle();

    expect(find.text('Go Offline'), findsOneWidget);
    expect(operatorRepo.lastOnlineStatus, isTrue);
  });

  testWidgets('online operator can expand pending queue and accept booking', (
    tester,
  ) async {
    final operatorRepo = _FakeOperatorRepository(
      operator: const OperatorModel(
        uid: 'operator-1',
        operatorId: 'OP-1',
        name: 'Captain Aiman',
        email: 'captain@example.com',
        isOnline: true,
      ),
    );
    final bookingRepo = _FakeBookingRepository();

    await tester.pumpWidget(
      buildTestWidget(
        operatorId: 'operator-1',
        operatorEmail: 'captain@example.com',
        operatorRepo: operatorRepo,
        bookingRepo: bookingRepo,
      ),
    );
    await tester.pumpAndSettle();

    bookingRepo.emitPending([
      _sampleBooking(id: 'pending-1', status: BookingStatus.pending),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pending Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Next Pending Booking'), findsOneWidget);
    expect(find.text('Accept Booking'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);

    await tester.tap(find.text('Accept Booking'));
    await tester.pumpAndSettle();

    expect(bookingRepo.lastAcceptedBookingId, 'pending-1');
    expect(bookingRepo.lastAcceptedOperatorId, 'operator-1');
  });

  testWidgets('online operator can expand active trip section', (tester) async {
    final operatorRepo = _FakeOperatorRepository(
      operator: const OperatorModel(
        uid: 'operator-1',
        operatorId: 'OP-1',
        name: 'Captain Aiman',
        email: 'captain@example.com',
        isOnline: true,
      ),
    );
    final bookingRepo = _FakeBookingRepository();

    await tester.pumpWidget(
      buildTestWidget(
        operatorId: 'operator-1',
        operatorEmail: 'captain@example.com',
        operatorRepo: operatorRepo,
        bookingRepo: bookingRepo,
      ),
    );
    await tester.pumpAndSettle();

    bookingRepo.emitActive([
      _sampleBooking(id: 'active-1', status: BookingStatus.accepted),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active Trip'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Current Booking: Accepted'), findsOneWidget);
    expect(find.text('Start Trip'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);
  });

  testWidgets('online operator start trip delegates to repository', (
    tester,
  ) async {
    final operatorRepo = _FakeOperatorRepository(
      operator: const OperatorModel(
        uid: 'operator-1',
        operatorId: 'OP-1',
        name: 'Captain Aiman',
        email: 'captain@example.com',
        isOnline: true,
      ),
    );
    final bookingRepo = _FakeBookingRepository();

    await tester.pumpWidget(
      buildTestWidget(
        operatorId: 'operator-1',
        operatorEmail: 'captain@example.com',
        operatorRepo: operatorRepo,
        bookingRepo: bookingRepo,
      ),
    );
    await tester.pumpAndSettle();

    bookingRepo.emitActive([
      _sampleBooking(id: 'active-1', status: BookingStatus.accepted),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active Trip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Trip'));
    await tester.pumpAndSettle();

    expect(bookingRepo.lastStartedBookingId, 'active-1');
    expect(bookingRepo.lastStartedOperatorId, 'operator-1');
  });

  testWidgets('online operator complete trip delegates to repository', (
    tester,
  ) async {
    final operatorRepo = _FakeOperatorRepository(
      operator: const OperatorModel(
        uid: 'operator-1',
        operatorId: 'OP-1',
        name: 'Captain Aiman',
        email: 'captain@example.com',
        isOnline: true,
      ),
    );
    final bookingRepo = _FakeBookingRepository();

    await tester.pumpWidget(
      buildTestWidget(
        operatorId: 'operator-1',
        operatorEmail: 'captain@example.com',
        operatorRepo: operatorRepo,
        bookingRepo: bookingRepo,
      ),
    );
    await tester.pumpAndSettle();

    bookingRepo.emitActive([
      _sampleBooking(id: 'active-2', status: BookingStatus.onTheWay),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active Trip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete Trip'));
    await tester.pumpAndSettle();

    expect(bookingRepo.lastCompletedBookingId, 'active-2');
    expect(bookingRepo.lastCompletedOperatorId, 'operator-1');
  });
}

class _FakeOperatorRepository extends OperatorRepository {
  _FakeOperatorRepository({this.operator})
    : super(firestore: FakeFirebaseFirestore());

  OperatorModel? operator;
  bool? lastOnlineStatus;

  @override
  Future<OperatorModel?> getOperator(String uid) async => operator;

  @override
  Future<void> setOnlineStatus(String uid, {required bool isOnline}) async {
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

class _FakeBookingRepository extends BookingRepository {
  _FakeBookingRepository()
    : _activeController = StreamController<List<BookingModel>>.broadcast(),
      _pendingController = StreamController<List<BookingModel>>.broadcast(),
      super(firestore: FakeFirebaseFirestore());

  final StreamController<List<BookingModel>> _activeController;
  final StreamController<List<BookingModel>> _pendingController;

  String? lastAcceptedBookingId;
  String? lastAcceptedOperatorId;
  String? lastStartedBookingId;
  String? lastStartedOperatorId;
  String? lastCompletedBookingId;
  String? lastCompletedOperatorId;

  @override
  Stream<List<BookingModel>> streamActiveBookings(String operatorId) =>
      _activeController.stream;

  @override
  Stream<List<BookingModel>> streamPendingBookings() =>
      _pendingController.stream;

  @override
  Future<OperationResult> acceptBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    lastAcceptedBookingId = bookingId;
    lastAcceptedOperatorId = operatorId;
    return const OperationSuccess('Booking accepted successfully.');
  }

  @override
  Future<OperationResult> rejectBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    return const OperationSuccess('Booking rejected.');
  }

  @override
  Future<OperationResult> releaseBooking({
    required String bookingId,
    required String operatorId,
  }) async {
    return const OperationSuccess('Booking released.');
  }

  @override
  Future<OperationResult> startTrip({
    required String bookingId,
    required String operatorId,
    double? operatorLat,
    double? operatorLng,
  }) async {
    lastStartedBookingId = bookingId;
    lastStartedOperatorId = operatorId;
    return const OperationSuccess('Trip started successfully.');
  }

  @override
  Future<OperationResult> completeTrip({
    required String bookingId,
    required String operatorId,
  }) async {
    lastCompletedBookingId = bookingId;
    lastCompletedOperatorId = operatorId;
    return const OperationSuccess('Trip completed successfully.');
  }

  @override
  Future<int> releaseAllAcceptedBookings(String operatorId) async => 0;

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
    rejectedBy: const [],
    createdAt: DateTime(2026, 3, 15, 10, 0),
    updatedAt: DateTime(2026, 3, 15, 10, 5),
    cancelledAt: null,
  );
}
