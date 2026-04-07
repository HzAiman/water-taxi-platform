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
import 'package:passenger_app/features/home/presentation/viewmodels/booking_tracking_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/home_view_model.dart';
import 'package:passenger_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:passenger_app/features/profile/presentation/viewmodels/profile_view_model.dart';
import 'package:provider/provider.dart';
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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      await tester.pumpAndSettle();

      expect(find.text('Route Corridor'), findsNothing);
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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
        _sampleBooking(id: 'booking-active', status: BookingStatus.pending),
        _sampleBooking(
          id: 'booking-completed',
          status: BookingStatus.completed,
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('booking-active'), findsOneWidget);
      expect(find.text('booking-completed'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Completed'));
      await tester.pumpAndSettle();

      expect(find.text('booking-completed'), findsOneWidget);
      expect(find.text('booking-active'), findsNothing);
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

  @override
  Future<List<JettyModel>> getAllJetties() async {
    return const [
      JettyModel(jettyId: '1', name: 'Jetty A', lat: 1, lng: 101),
      JettyModel(jettyId: '2', name: 'Jetty B', lat: 2, lng: 102),
    ];
  }
}

class _FakeFareRepository extends FareRepository {
  _FakeFareRepository() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<FareModel?> getFare(String origin, String destination) async {
    return const FareModel(
      origin: 'Jetty A',
      destination: 'Jetty B',
      adultFare: 10,
      childFare: 5,
    );
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
  double? operatorLat,
  double? operatorLng,
  List<BookingRoutePoint> routePolyline = const <BookingRoutePoint>[],
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
    totalFare: 12.0,
    paymentMethod: PaymentMethods.creditCard,
    paymentStatus: 'paid',
    status: status,
    operatorUid: status == BookingStatus.pending ? null : 'operator-1',
    operatorLat: operatorLat,
    operatorLng: operatorLng,
    routePolyline: routePolyline,
    rejectedBy: const [],
    createdAt: DateTime(2026, 3, 15, 10, 0),
    updatedAt: DateTime(2026, 3, 15, 10, 5),
    cancelledAt: null,
  );
}
