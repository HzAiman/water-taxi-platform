import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/fare_repository.dart';
import 'package:passenger_app/data/repositories/jetty_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';
import 'package:passenger_app/features/home/presentation/pages/booking_tracking_screen.dart';
import 'package:passenger_app/features/home/presentation/pages/home_screen.dart';
import 'package:passenger_app/features/home/presentation/pages/payment_screen.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/booking_tracking_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/home_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/payment_view_model.dart';
import 'package:passenger_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:passenger_app/features/profile/presentation/viewmodels/profile_view_model.dart';
import 'package:provider/provider.dart';
import 'package:passenger_app/services/payment/payment_gateway_service.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setupFirebaseCoreMocks();
  });

  setUp(() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  });

  group('HomeScreen widgets', () {
    testWidgets('shows active booking card and disables booking action', (
      tester,
    ) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = HomeViewModel(
        userRepo: _FakeUserRepository(),
        jettyRepo: _FakeJettyRepository(),
        fareRepo: _FakeFareRepository(),
        bookingRepo: bookingRepo,
      );

      await vm.init('user-1');
      bookingRepo.emitActiveBooking(
        _sampleBooking(id: 'booking-active', status: BookingStatus.pending),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<HomeViewModel>.value(
          value: vm,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Current Booking'), findsOneWidget);
      expect(find.text('View Booking Status'), findsOneWidget);
      expect(find.text('Jetty A → Jetty B'), findsOneWidget);
      expect(find.textContaining('Booking ID'), findsNothing);
      expect(find.textContaining('->'), findsNothing);
      expect(find.text('Adults: 1 • Children: 0'), findsOneWidget);
      expect(find.text('Operator: Not assigned yet'), findsOneWidget);
      expect(
        find.text(
          'You have an active booking. Open View Booking Status above to continue.',
        ),
        findsOneWidget,
      );

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Book Water Taxi'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('PaymentScreen widgets', () {
    testWidgets('shows minimum payment adjustment for low fare', (
      tester,
    ) async {
      final vm = PaymentViewModel(
        fareRepo: _FakeFareRepository(
          fare: const FareModel(
            snapshotId: 'fare-low',
            origin: 'Jetty A',
            destination: 'Jetty B',
            adultFare: 1.3,
            childFare: 0.3,
          ),
        ),
        jettyRepo: _FakeJettyRepository(),
        userRepo: _FakeUserRepository(),
        bookingRepo: _FakeBookingRepository(),
        paymentGateway: _FakePaymentGatewayService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<PaymentViewModel>.value(
          value: vm,
          child: const MaterialApp(
            home: PaymentScreen(
              origin: 'Jetty A',
              destination: 'Jetty B',
              adultCount: 1,
              childCount: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Base Fare'), findsOneWidget);
      expect(find.text('Minimum payment adjustment'), findsOneWidget);
      expect(find.text('RM 0.40'), findsOneWidget);
      expect(find.text('Continue to Payment (RM 2.00)'), findsOneWidget);
    });

    testWidgets('hides minimum payment adjustment for normal fare', (
      tester,
    ) async {
      final vm = PaymentViewModel(
        fareRepo: _FakeFareRepository(
          fare: const FareModel(
            snapshotId: 'fare-normal',
            origin: 'Jetty A',
            destination: 'Jetty B',
            adultFare: 3,
            childFare: 1,
          ),
        ),
        jettyRepo: _FakeJettyRepository(),
        userRepo: _FakeUserRepository(),
        bookingRepo: _FakeBookingRepository(),
        paymentGateway: _FakePaymentGatewayService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<PaymentViewModel>.value(
          value: vm,
          child: const MaterialApp(
            home: PaymentScreen(
              origin: 'Jetty A',
              destination: 'Jetty B',
              adultCount: 1,
              childCount: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Minimum payment adjustment'), findsNothing);
      expect(find.text('Continue to Payment (RM 3.00)'), findsOneWidget);
    });
  });

  group('BookingTrackingScreen widgets', () {
    testWidgets('renders accepted status with close action', (tester) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = BookingTrackingViewModel(bookingRepo: bookingRepo);

      await tester.pumpWidget(
        ChangeNotifierProvider<BookingTrackingViewModel>.value(
          value: vm,
          child: MaterialApp(
            home: BookingTrackingScreen(
              bookingId: 'booking-1',
              origin: 'Jetty A',
              destination: 'Jetty B',
              passengerCount: 1,
              mapBuilder:
                  ({
                    required initialCameraPosition,
                    required markers,
                    required padding,
                    required polylines,
                  }) {
                    return const SizedBox(key: ValueKey('mock-tracking-map'));
                  },
            ),
          ),
        ),
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(id: 'booking-1', status: BookingStatus.accepted),
      );
      await tester.pump();

      expect(find.text('Booking Confirmed'), findsOneWidget);
      expect(
        find.text('An operator has accepted your booking.'),
        findsOneWidget,
      );
    });

    testWidgets('renders rejected status with rebook guidance', (tester) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = BookingTrackingViewModel(bookingRepo: bookingRepo);

      await tester.pumpWidget(
        ChangeNotifierProvider<BookingTrackingViewModel>.value(
          value: vm,
          child: MaterialApp(
            home: BookingTrackingScreen(
              bookingId: 'booking-3',
              origin: 'Jetty A',
              destination: 'Jetty B',
              passengerCount: 1,
              mapBuilder:
                  ({
                    required initialCameraPosition,
                    required markers,
                    required padding,
                    required polylines,
                  }) {
                    return const SizedBox(key: ValueKey('mock-tracking-map'));
                  },
            ),
          ),
        ),
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(id: 'booking-3', status: BookingStatus.rejected),
      );
      await tester.pump();

      expect(find.text('Booking Rejected'), findsOneWidget);
      expect(
        find.text(
          'All available operators declined this request. Please create a new booking when an operator becomes available.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not render legacy corridor metadata notice', (
      tester,
    ) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = BookingTrackingViewModel(bookingRepo: bookingRepo);

      await tester.pumpWidget(
        ChangeNotifierProvider<BookingTrackingViewModel>.value(
          value: vm,
          child: MaterialApp(
            home: BookingTrackingScreen(
              bookingId: 'booking-3a',
              origin: 'Jetty A',
              destination: 'Jetty B',
              passengerCount: 1,
              mapBuilder:
                  ({
                    required initialCameraPosition,
                    required markers,
                    required padding,
                    required polylines,
                  }) {
                    return const SizedBox(key: ValueKey('mock-tracking-map'));
                  },
            ),
          ),
        ),
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(id: 'booking-3a', status: BookingStatus.onTheWay),
      );
      await tester.pump();

      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      await tester.pump();

      expect(find.text('Route Corridor'), findsNothing);
    });

    testWidgets('shows pickup ETA after live operator movement', (
      tester,
    ) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = BookingTrackingViewModel(bookingRepo: bookingRepo);

      await tester.pumpWidget(
        ChangeNotifierProvider<BookingTrackingViewModel>.value(
          value: vm,
          child: MaterialApp(
            home: BookingTrackingScreen(
              bookingId: 'booking-eta',
              origin: 'Jetty A',
              destination: 'Jetty B',
              passengerCount: 1,
              mapBuilder:
                  ({
                    required initialCameraPosition,
                    required markers,
                    required padding,
                    required polylines,
                  }) {
                    return const SizedBox(key: ValueKey('mock-tracking-map'));
                  },
            ),
          ),
        ),
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(
          id: 'booking-eta',
          status: BookingStatus.onTheWay,
          operatorLat: 0.9990,
          operatorLng: 101.0,
          updatedAt: DateTime.now().subtract(const Duration(seconds: 10)),
        ),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView).first, const Offset(0, -220));
      await tester.pump();

      expect(find.text('ETA to pickup'), findsOneWidget);
      expect(find.text('Calculating ETA'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      bookingRepo.emitTrackedBooking(
        _sampleBooking(
          id: 'booking-eta',
          status: BookingStatus.onTheWay,
          operatorLat: 0.9995,
          operatorLng: 101.0,
          updatedAt: DateTime.now(),
        ),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView).first, const Offset(0, -40));
      await tester.pump();

      expect(find.text('ETA to pickup'), findsOneWidget);
      expect(find.text('< 1 min'), findsOneWidget);
      expect(find.text('Calculating ETA'), findsNothing);
    });

    testWidgets('does not show ETA without live operator location', (
      tester,
    ) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = BookingTrackingViewModel(bookingRepo: bookingRepo);

      await tester.pumpWidget(
        ChangeNotifierProvider<BookingTrackingViewModel>.value(
          value: vm,
          child: MaterialApp(
            home: BookingTrackingScreen(
              bookingId: 'booking-no-eta',
              origin: 'Jetty A',
              destination: 'Jetty B',
              passengerCount: 1,
              mapBuilder:
                  ({
                    required initialCameraPosition,
                    required markers,
                    required padding,
                    required polylines,
                  }) {
                    return const SizedBox(key: ValueKey('mock-tracking-map'));
                  },
            ),
          ),
        ),
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(id: 'booking-no-eta', status: BookingStatus.onTheWay),
      );
      await tester.pump();

      expect(find.textContaining('ETA'), findsNothing);
    });

    testWidgets('does not show ETA before operator is on the way', (
      tester,
    ) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = BookingTrackingViewModel(bookingRepo: bookingRepo);

      await tester.pumpWidget(
        ChangeNotifierProvider<BookingTrackingViewModel>.value(
          value: vm,
          child: MaterialApp(
            home: BookingTrackingScreen(
              bookingId: 'booking-accepted-no-eta',
              origin: 'Jetty A',
              destination: 'Jetty B',
              passengerCount: 1,
              mapBuilder:
                  ({
                    required initialCameraPosition,
                    required markers,
                    required padding,
                    required polylines,
                  }) {
                    return const SizedBox(key: ValueKey('mock-tracking-map'));
                  },
            ),
          ),
        ),
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(
          id: 'booking-accepted-no-eta',
          status: BookingStatus.accepted,
          operatorLat: 0.9995,
          operatorLng: 101.0,
        ),
      );
      await tester.pump();

      expect(find.textContaining('ETA'), findsNothing);
    });

    testWidgets('uses route polyline and gates operator marker to on_the_way', (
      tester,
    ) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = BookingTrackingViewModel(bookingRepo: bookingRepo);

      Set<Marker> latestMarkers = const <Marker>{};
      Set<Polyline> latestPolylines = const <Polyline>{};

      await tester.pumpWidget(
        ChangeNotifierProvider<BookingTrackingViewModel>.value(
          value: vm,
          child: MaterialApp(
            home: BookingTrackingScreen(
              bookingId: 'booking-4',
              origin: 'Jetty A',
              destination: 'Jetty B',
              passengerCount: 2,
              mapBuilder:
                  ({
                    required initialCameraPosition,
                    required markers,
                    required padding,
                    required polylines,
                  }) {
                    latestMarkers = markers;
                    latestPolylines = polylines;
                    return const SizedBox(key: ValueKey('mock-tracking-map'));
                  },
            ),
          ),
        ),
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(
          id: 'booking-4',
          status: BookingStatus.accepted,
          operatorLat: 2.10,
          operatorLng: 102.10,
          routePolyline: const [
            BookingRoutePoint(lat: 2.00, lng: 102.00),
            BookingRoutePoint(lat: 2.05, lng: 102.05),
            BookingRoutePoint(lat: 2.10, lng: 102.10),
          ],
        ),
      );
      await tester.pump();

      expect(latestPolylines, hasLength(1));
      expect(latestPolylines.first.points, hasLength(3));
      expect(
        latestMarkers.any((m) => m.markerId == const MarkerId('operator_live')),
        isFalse,
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(
          id: 'booking-4',
          status: BookingStatus.onTheWay,
          operatorLat: 2.10,
          operatorLng: 102.10,
          routePolyline: const [
            BookingRoutePoint(lat: 2.00, lng: 102.00),
            BookingRoutePoint(lat: 2.05, lng: 102.05),
            BookingRoutePoint(lat: 2.10, lng: 102.10),
          ],
        ),
      );
      await tester.pump();

      expect(
        latestMarkers.any((m) => m.markerId == const MarkerId('operator_live')),
        isTrue,
      );

      bookingRepo.emitTrackedBooking(
        _sampleBooking(
          id: 'booking-4',
          status: BookingStatus.completed,
          operatorLat: 2.10,
          operatorLng: 102.10,
          routePolyline: const [
            BookingRoutePoint(lat: 2.00, lng: 102.00),
            BookingRoutePoint(lat: 2.05, lng: 102.05),
            BookingRoutePoint(lat: 2.10, lng: 102.10),
          ],
        ),
      );
      await tester.pump();

      expect(
        latestMarkers.any((m) => m.markerId == const MarkerId('operator_live')),
        isFalse,
      );
    });
  });

  group('Profile booking history filters', () {
    testWidgets('filters booking history by completed status', (tester) async {
      final bookingRepo = _FakeBookingRepository();
      final vm = ProfileViewModel(
        userRepo: _FakeUserRepository(),
        bookingRepo: bookingRepo,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ProfileViewModel>.value(
          value: vm,
          child: const MaterialApp(
            home: ProfileScreen(
              testUserId: 'user-1',
              testPhoneNumber: '0123456789',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Booking History'));
      await tester.pumpAndSettle();

      bookingRepo.emitHistory([
        _sampleBooking(
          id: 'booking-active',
          status: BookingStatus.pending,
          origin: 'Pier A',
          destination: 'Pier B',
        ),
        _sampleBooking(
          id: 'booking-completed',
          status: BookingStatus.completed,
          origin: 'Pier C',
          destination: 'Pier D',
          adultCount: 2,
          childCount: 1,
          assignedOperatorName: 'Captain Maya',
          assignedOperatorDisplayId: 'OP-7788',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Pier A → Pier B'), findsOneWidget);
      expect(find.text('Pier C → Pier D'), findsOneWidget);
      expect(find.text('booking-active'), findsNothing);
      expect(find.text('booking-completed'), findsNothing);
      expect(find.text('Open Live Tracking'), findsNothing);
      expect(
        find.textContaining('Adults: 2', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Children: 1', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Captain Maya', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('OP-7788', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Completed'));
      await tester.pumpAndSettle();

      expect(find.text('Pier C → Pier D'), findsOneWidget);
      expect(find.text('Pier A → Pier B'), findsNothing);
    });
  });
}

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository() : super(firestore: FakeFirebaseFirestore());

  UserModel? user = const UserModel(
    uid: 'user-1',
    name: 'Passenger Test',
    email: 'passenger@test.com',
    phoneNumber: '0123456789',
  );

  @override
  Future<UserModel?> getUser(String uid) async => user;
}

class _FakeJettyRepository extends JettyRepository {
  _FakeJettyRepository() : super(firestore: FakeFirebaseFirestore());

  static const _jetties = [
    JettyModel(jettyId: '1', name: 'Jetty A', lat: 1, lng: 101),
    JettyModel(jettyId: '2', name: 'Jetty B', lat: 2, lng: 102),
  ];

  @override
  Future<List<JettyModel>> getAllJetties() async {
    return _jetties;
  }

  @override
  Future<JettyModel?> getJettyByName(String name) async {
    for (final jetty in _jetties) {
      if (jetty.name == name) {
        return jetty;
      }
    }
    return null;
  }
}

class _FakeFareRepository extends FareRepository {
  _FakeFareRepository({FareModel? fare})
    : fare =
          fare ??
          const FareModel(
            snapshotId: 'fare-a-b',
            origin: 'Jetty A',
            destination: 'Jetty B',
            adultFare: 10,
            childFare: 5,
          ),
      super(firestore: FakeFirebaseFirestore());

  final FareModel fare;

  @override
  Future<FareModel?> getFare(
    String origin,
    String destination, {
    required String originJettyId,
    required String destinationJettyId,
  }) async {
    if (fare.origin == origin && fare.destination == destination) {
      return fare;
    }
    return null;
  }
}

class _FakePaymentGatewayService implements PaymentGatewayService {
  @override
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request) async {
    return const PaymentGatewayResult(
      status: PaymentGatewayStatus.authorized,
      transactionId: 'txn-widget',
    );
  }

  @override
  Future<PaymentGatewayResult> capturePayment({
    required String paymentIntentId,
    required String orderNumber,
  }) async {
    return const PaymentGatewayResult(status: PaymentGatewayStatus.success);
  }

  @override
  Future<PaymentGatewayResult> cancelPayment({
    required String paymentIntentId,
    required String orderNumber,
    String reason = 'requested_by_customer',
  }) async {
    return const PaymentGatewayResult(status: PaymentGatewayStatus.cancelled);
  }
}

class _FakeBookingRepository extends BookingRepository {
  _FakeBookingRepository()
    : _trackedBookingController = StreamController<BookingModel?>.broadcast(),
      _activeBookingController = StreamController<BookingModel?>.broadcast(),
      _historyController = StreamController<List<BookingModel>>.broadcast(),
      super(firestore: FakeFirebaseFirestore());

  final StreamController<BookingModel?> _trackedBookingController;
  final StreamController<BookingModel?> _activeBookingController;
  final StreamController<List<BookingModel>> _historyController;

  @override
  Stream<BookingModel?> streamBooking(String bookingId) =>
      _trackedBookingController.stream;

  @override
  Stream<BookingModel?> streamUserActiveBooking(String userId) =>
      _activeBookingController.stream;

  @override
  Stream<List<BookingModel>> streamUserBookingHistory(String userId) =>
      _historyController.stream;

  void emitTrackedBooking(BookingModel? booking) {
    _trackedBookingController.add(booking);
  }

  void emitActiveBooking(BookingModel? booking) {
    _activeBookingController.add(booking);
  }

  void emitHistory(List<BookingModel> bookings) {
    _historyController.add(bookings);
  }
}

BookingModel _sampleBooking({
  required String id,
  required BookingStatus status,
  String origin = 'Jetty A',
  String destination = 'Jetty B',
  int adultCount = 1,
  int childCount = 0,
  String assignedOperatorName = '',
  String assignedOperatorDisplayId = '',
  double? operatorLat,
  double? operatorLng,
  List<BookingRoutePoint> routePolyline = const <BookingRoutePoint>[],
  DateTime? updatedAt,
}) {
  return BookingModel(
    bookingId: id,
    userId: 'user-1',
    userName: 'Passenger One',
    userPhone: '0123456789',
    origin: origin,
    destination: destination,
    originLat: 1.0,
    originLng: 101.0,
    destinationLat: 2.0,
    destinationLng: 102.0,
    adultCount: adultCount,
    childCount: childCount,
    passengerCount: adultCount + childCount,
    totalFare: 12.0,
    paymentMethod: PaymentMethods.creditCard,
    paymentStatus: 'paid',
    status: status,
    operatorUid: status == BookingStatus.pending ? null : 'operator-1',
    assignedOperatorName: assignedOperatorName,
    assignedOperatorDisplayId: assignedOperatorDisplayId,
    operatorLat: operatorLat,
    operatorLng: operatorLng,
    routePolyline: routePolyline,
    rejectedBy: const [],
    createdAt: DateTime(2026, 3, 15, 10, 0),
    updatedAt: updatedAt ?? DateTime(2026, 3, 15, 10, 5),
    cancelledAt: null,
  );
}
