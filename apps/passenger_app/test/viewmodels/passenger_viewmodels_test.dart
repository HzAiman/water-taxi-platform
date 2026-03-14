import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/fare_repository.dart';
import 'package:passenger_app/data/repositories/jetty_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/booking_tracking_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/home_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/payment_view_model.dart';
import 'package:passenger_app/features/profile/presentation/viewmodels/profile_view_model.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('HomeViewModel', () {
    test('init loads user, jetties, and active booking stream', () async {
      final userRepo = FakeUserRepository(
        user: const UserModel(
          uid: 'user-1',
          name: 'Aiman',
          email: 'aiman@example.com',
          phoneNumber: '0123456789',
        ),
      );
      final jettyRepo = FakeJettyRepository(
        jetties: const [
          JettyModel(jettyId: '2', name: 'B Jetty', lat: 2.0, lng: 102.0),
          JettyModel(jettyId: '1', name: 'A Jetty', lat: 1.0, lng: 101.0),
        ],
      );
      final fareRepo = FakeFareRepository();
      final bookingRepo = FakeBookingRepository();
      final viewModel = HomeViewModel(
        userRepo: userRepo,
        jettyRepo: jettyRepo,
        fareRepo: fareRepo,
        bookingRepo: bookingRepo,
      );

      await viewModel.init('user-1');
      bookingRepo.emitActiveBooking(_sampleBooking(status: BookingStatus.pending));
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.userName, 'Aiman');
      expect(viewModel.jetties.map((j) => j.jettyId), ['2', '1']);
      expect(viewModel.activeBooking?.bookingId, 'booking-1');
    });

    test('selectOrigin clears destination when they conflict', () {
      final viewModel = HomeViewModel(
        userRepo: FakeUserRepository(),
        jettyRepo: FakeJettyRepository(),
        fareRepo: FakeFareRepository(),
        bookingRepo: FakeBookingRepository(),
      );

      viewModel.selectDestination('Terminal A');
      viewModel.selectOrigin('Terminal A');

      expect(viewModel.selectedOrigin, 'Terminal A');
      expect(viewModel.selectedDestination, isNull);
    });

    test('getFareForSelectedRoute returns configured fare', () async {
      final fareRepo = FakeFareRepository(
        fare: const FareModel(
          origin: 'Terminal A',
          destination: 'Terminal B',
          adultFare: 12.5,
          childFare: 6.0,
        ),
      );
      final viewModel = HomeViewModel(
        userRepo: FakeUserRepository(),
        jettyRepo: FakeJettyRepository(),
        fareRepo: fareRepo,
        bookingRepo: FakeBookingRepository(),
      )
        ..selectOrigin('Terminal A')
        ..selectDestination('Terminal B');

      final fare = await viewModel.getFareForSelectedRoute();

      expect(fare, isNotNull);
      expect(fare?.adultFare, 12.5);
      expect(viewModel.isCheckingFare, isFalse);
    });
  });

  group('PaymentViewModel', () {
    test('loadFare computes the full breakdown', () async {
      final viewModel = PaymentViewModel(
        fareRepo: FakeFareRepository(
          fare: const FareModel(
            origin: 'Terminal A',
            destination: 'Terminal B',
            adultFare: 10,
            childFare: 4,
          ),
        ),
        jettyRepo: FakeJettyRepository(),
        userRepo: FakeUserRepository(),
        bookingRepo: FakeBookingRepository(),
      );

      await viewModel.loadFare(
        origin: 'Terminal A',
        destination: 'Terminal B',
        adultCount: 2,
        childCount: 1,
      );

      expect(viewModel.fareBreakdown, isNotNull);
      expect(viewModel.fareBreakdown?.adultSubtotal, 20);
      expect(viewModel.fareBreakdown?.childSubtotal, 4);
      expect(viewModel.fareBreakdown?.total, 24);
    });

    test('processPayment returns success and passes booking params', () async {
      final bookingRepo = FakeBookingRepository();
      final viewModel = PaymentViewModel(
        fareRepo: FakeFareRepository(
          fare: const FareModel(
            origin: 'Terminal A',
            destination: 'Terminal B',
            adultFare: 8,
            childFare: 4,
          ),
        ),
        jettyRepo: FakeJettyRepository(
          jetties: const [
            JettyModel(jettyId: '1', name: 'Terminal A', lat: 1, lng: 101),
            JettyModel(jettyId: '2', name: 'Terminal B', lat: 2, lng: 102),
          ],
        ),
        userRepo: FakeUserRepository(
          user: const UserModel(
            uid: 'user-1',
            name: 'Aiman',
            email: 'aiman@example.com',
            phoneNumber: '0123456789',
          ),
        ),
        bookingRepo: bookingRepo,
      );

      await viewModel.loadFare(
        origin: 'Terminal A',
        destination: 'Terminal B',
        adultCount: 2,
        childCount: 1,
      );
      viewModel.selectPaymentMethod(PaymentMethods.creditCard);

      final result = await viewModel.processPayment(
        userId: 'user-1',
        origin: 'Terminal A',
        destination: 'Terminal B',
        adultCount: 2,
        childCount: 1,
      );

      expect(result, isA<OperationSuccess>());
      expect((result as OperationSuccess).message, 'booking-1');
      expect(bookingRepo.lastCreatedParams?.paymentMethod, PaymentMethods.creditCard);
      expect(bookingRepo.lastCreatedParams?.adultCount, 2);
      expect(bookingRepo.lastCreatedParams?.childCount, 1);
    });
  });

  group('BookingTrackingViewModel', () {
    test('startTracking reflects stream updates and cancel succeeds', () async {
      final bookingRepo = FakeBookingRepository();
      final viewModel = BookingTrackingViewModel(bookingRepo: bookingRepo);

      viewModel.startTracking('booking-1');
      bookingRepo.emitTrackedBooking(_sampleBooking(status: BookingStatus.accepted));
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.booking?.status, BookingStatus.accepted);

      final result = await viewModel.cancelBooking('booking-1');

      expect(result, isA<OperationSuccess>());
      expect(bookingRepo.cancelledBookingId, 'booking-1');
      expect(viewModel.isCancelling, isFalse);
    });

    test('cancelBooking returns info failure for completed booking', () async {
      final bookingRepo = FakeBookingRepository();
      final viewModel = BookingTrackingViewModel(bookingRepo: bookingRepo);

      viewModel.startTracking('booking-1');
      bookingRepo.emitTrackedBooking(
        _sampleBooking(status: BookingStatus.completed),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await viewModel.cancelBooking('booking-1');

      expect(result, isA<OperationFailure>());
      final failure = result as OperationFailure;
      expect(failure.title, 'Cancellation unavailable');
      expect(failure.isInfo, isTrue);
      expect(bookingRepo.cancelledBookingId, isNull);
      expect(viewModel.isCancelling, isFalse);
    });
  });

  group('ProfileViewModel', () {
    test('loadProfile and updateProfile refresh local state', () async {
      final userRepo = FakeUserRepository(
        user: const UserModel(
          uid: 'user-1',
          name: 'Before',
          email: 'before@example.com',
          phoneNumber: '0123456789',
        ),
      );
      final viewModel = ProfileViewModel(
        userRepo: userRepo,
        bookingRepo: FakeBookingRepository(),
      );

      await viewModel.loadProfile('user-1');
      final result = await viewModel.updateProfile(
        uid: 'user-1',
        name: 'After',
        email: 'after@example.com',
      );

      expect(result, isA<OperationSuccess>());
      expect(viewModel.user?.name, 'After');
      expect(viewModel.user?.email, 'after@example.com');
      expect(userRepo.updatedName, 'After');
    });

    test('booking history stream updates the exposed list', () async {
      final bookingRepo = FakeBookingRepository();
      final viewModel = ProfileViewModel(
        userRepo: FakeUserRepository(),
        bookingRepo: bookingRepo,
      );

      viewModel.startBookingHistoryStream('user-1');
      bookingRepo.emitHistory([
        _sampleBooking(status: BookingStatus.completed),
        _sampleBooking(
          id: 'booking-2',
          status: BookingStatus.cancelled,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.bookingHistory, hasLength(2));
      expect(viewModel.bookingHistory.first.status, BookingStatus.completed);
    });
  });
}

class FakeUserRepository extends UserRepository {
  FakeUserRepository({this.user}) : super(firestore: FakeFirebaseFirestore());

  UserModel? user;
  String? updatedName;
  String? updatedEmail;
  bool deleteCalled = false;

  @override
  Future<UserModel?> getUser(String uid) async => user;

  @override
  Future<void> updateUser(
    String uid, {
    String? name,
    String? email,
  }) async {
    updatedName = name;
    updatedEmail = email;
    user = (user ??
            UserModel(
              uid: uid,
              name: '',
              email: '',
              phoneNumber: '',
            ))
        .copyWith(name: name, email: email);
  }

  @override
  Future<void> deleteUser(String uid) async {
    deleteCalled = true;
  }
}

class FakeJettyRepository extends JettyRepository {
  FakeJettyRepository({List<JettyModel>? jetties})
      : jetties = jetties ?? [],
        super(firestore: FakeFirebaseFirestore());

  final List<JettyModel> jetties;

  @override
  Future<List<JettyModel>> getAllJetties() async => List<JettyModel>.from(jetties);

  @override
  Future<JettyModel?> getJettyByName(String name) async {
    for (final jetty in jetties) {
      if (jetty.name == name) {
        return jetty;
      }
    }
    return null;
  }
}

class FakeFareRepository extends FareRepository {
  FakeFareRepository({this.fare}) : super(firestore: FakeFirebaseFirestore());

  FareModel? fare;

  @override
  Future<FareModel?> getFare(String origin, String destination) async {
    if (fare == null) {
      return null;
    }
    if (fare!.origin == origin && fare!.destination == destination) {
      return fare;
    }
    return null;
  }
}

class FakeBookingRepository extends BookingRepository {
  FakeBookingRepository()
      : _trackedBookingController = StreamController<BookingModel?>.broadcast(),
        _activeBookingController = StreamController<BookingModel?>.broadcast(),
        _historyController = StreamController<List<BookingModel>>.broadcast(),
        super(firestore: FakeFirebaseFirestore());

  final StreamController<BookingModel?> _trackedBookingController;
  final StreamController<BookingModel?> _activeBookingController;
  final StreamController<List<BookingModel>> _historyController;

  BookingCreationParams? lastCreatedParams;
  String? cancelledBookingId;

  @override
  Future<String> createBooking(BookingCreationParams p) async {
    lastCreatedParams = p;
    return 'booking-1';
  }

  @override
  Future<void> cancelBooking(String bookingId) async {
    cancelledBookingId = bookingId;
  }

  @override
  Stream<BookingModel?> streamBooking(String bookingId) =>
      _trackedBookingController.stream;

  @override
  Stream<BookingModel?> streamUserActiveBooking(String userId) =>
      _activeBookingController.stream;

  @override
  Stream<List<BookingModel>> streamUserBookingHistory(String userId) =>
      _historyController.stream;

  @override
  Future<bool> hasActiveBooking(String userId) async => false;

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
  String id = 'booking-1',
  BookingStatus status = BookingStatus.pending,
}) {
  return BookingModel(
    bookingId: id,
    userId: 'user-1',
    userName: 'Aiman',
    userPhone: '0123456789',
    origin: 'Terminal A',
    destination: 'Terminal B',
    originLat: 1.0,
    originLng: 101.0,
    destinationLat: 2.0,
    destinationLng: 102.0,
    adultCount: 2,
    childCount: 1,
    passengerCount: 3,
    adultFare: 10,
    childFare: 5,
    adultSubtotal: 20,
    childSubtotal: 5,
    fare: 25,
    totalFare: 25,
    paymentMethod: PaymentMethods.creditCard,
    paymentStatus: 'paid',
    status: status,
    driverId: null,
    rejectedBy: const [],
    createdAt: DateTime(2026, 3, 15, 10, 30),
    updatedAt: DateTime(2026, 3, 15, 10, 35),
    cancelledAt: null,
  );
}
