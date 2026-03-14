import 'package:cloud_firestore/cloud_firestore.dart';
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
  test('integration: booking lifecycle syncs across passenger viewmodels', () async {
    final setup = await _createSetup();
    final firestore = setup.firestore;
    final homeVm = setup.homeVm;
    final paymentVm = setup.paymentVm;
    final trackingVm = setup.trackingVm;
    final profileVm = setup.profileVm;

    await homeVm.init('user-1');
    homeVm.selectOrigin('Jetty A');
    homeVm.selectDestination('Jetty B');

    await paymentVm.loadFare(
      origin: 'Jetty A',
      destination: 'Jetty B',
      adultCount: 2,
      childCount: 1,
    );
    paymentVm.selectPaymentMethod(PaymentMethods.creditCard);

    final bookingResult = await paymentVm.processPayment(
      userId: 'user-1',
      origin: 'Jetty A',
      destination: 'Jetty B',
      adultCount: 2,
      childCount: 1,
    );

    expect(bookingResult, isA<OperationSuccess>());
    final bookingId = (bookingResult as OperationSuccess).message;
    expect(bookingId, isNotEmpty);

    trackingVm.startTracking(bookingId);
    profileVm.startBookingHistoryStream('user-1');
    await Future<void>.delayed(Duration.zero);

    expect(trackingVm.booking, isNotNull);
    expect(trackingVm.booking!.status, BookingStatus.pending);
    expect(homeVm.activeBooking?.status, BookingStatus.pending);
    expect(profileVm.bookingHistory, hasLength(1));

    await _operatorUpdateStatus(
      firestore: firestore,
      bookingId: bookingId,
      status: BookingStatus.accepted,
      driverId: 'operator-1',
    );
    await Future<void>.delayed(Duration.zero);
    expect(trackingVm.booking?.status, BookingStatus.accepted);
    expect(homeVm.activeBooking?.status, BookingStatus.accepted);

    await _operatorUpdateStatus(
      firestore: firestore,
      bookingId: bookingId,
      status: BookingStatus.onTheWay,
      driverId: 'operator-1',
    );
    await Future<void>.delayed(Duration.zero);
    expect(trackingVm.booking?.status, BookingStatus.onTheWay);
    expect(homeVm.activeBooking?.status, BookingStatus.onTheWay);

    await _operatorUpdateStatus(
      firestore: firestore,
      bookingId: bookingId,
      status: BookingStatus.completed,
      driverId: 'operator-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(trackingVm.booking?.status, BookingStatus.completed);
    expect(homeVm.activeBooking, isNull);
    expect(profileVm.bookingHistory, hasLength(1));
    expect(profileVm.bookingHistory.first.status, BookingStatus.completed);

    profileVm.stopBookingHistoryStream();
    homeVm.dispose();
    trackingVm.dispose();
    profileVm.dispose();
  });

  for (final status in [
    BookingStatus.pending,
    BookingStatus.accepted,
    BookingStatus.onTheWay,
  ]) {
    test(
      'integration: passenger can cancel $status booking',
      () async {
        final setup = await _createSetup();
        final firestore = setup.firestore;
        final trackingVm = setup.trackingVm;

        final bookingId = await _createBookingAndTrack(
          setup: setup,
          paymentMethod: PaymentMethods.creditCard,
        );

        if (status != BookingStatus.pending) {
          await _operatorUpdateStatus(
            firestore: firestore,
            bookingId: bookingId,
            status: status,
            driverId: 'operator-1',
          );
          await Future<void>.delayed(Duration.zero);
        }

        final result = await trackingVm.cancelBooking(bookingId);
        await Future<void>.delayed(Duration.zero);

        expect(result, isA<OperationSuccess>());
        expect(trackingVm.booking?.status, BookingStatus.cancelled);

        final snap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc(bookingId)
            .get();
        expect(snap.data()?[BookingFields.status], BookingStatus.cancelled.firestoreValue);
        expect(snap.data()?[BookingFields.cancelledAt], isNotNull);

        setup.profileVm.stopBookingHistoryStream();
        setup.homeVm.dispose();
        setup.trackingVm.dispose();
        setup.profileVm.dispose();
      },
    );
  }

  test('integration: completed booking cannot be cancelled by passenger', () async {
    final setup = await _createSetup();
    final firestore = setup.firestore;
    final trackingVm = setup.trackingVm;

    final bookingId = await _createBookingAndTrack(
      setup: setup,
      paymentMethod: PaymentMethods.eWallet,
    );

    await _operatorUpdateStatus(
      firestore: firestore,
      bookingId: bookingId,
      status: BookingStatus.completed,
      driverId: 'operator-1',
    );
    await Future<void>.delayed(Duration.zero);

    final result = await trackingVm.cancelBooking(bookingId);
    expect(result, isA<OperationFailure>());
    expect((result as OperationFailure).title, 'Cancellation unavailable');

    final snap = await firestore
        .collection(FirestoreCollections.bookings)
        .doc(bookingId)
        .get();
    expect(
      snap.data()?[BookingFields.status],
      BookingStatus.completed.firestoreValue,
    );

    setup.profileVm.stopBookingHistoryStream();
    setup.homeVm.dispose();
    setup.trackingVm.dispose();
    setup.profileVm.dispose();
  });
}

Future<_IntegrationSetup> _createSetup() async {
  final firestore = FakeFirebaseFirestore();
  await _seedFirestore(firestore);

  final userRepo = UserRepository(firestore: firestore);
  final jettyRepo = JettyRepository(firestore: firestore);
  final fareRepo = FareRepository(firestore: firestore);
  final bookingRepo = BookingRepository(firestore: firestore);

  final homeVm = HomeViewModel(
    userRepo: userRepo,
    jettyRepo: jettyRepo,
    fareRepo: fareRepo,
    bookingRepo: bookingRepo,
  );
  final paymentVm = PaymentViewModel(
    fareRepo: fareRepo,
    jettyRepo: jettyRepo,
    userRepo: userRepo,
    bookingRepo: bookingRepo,
  );
  final trackingVm = BookingTrackingViewModel(bookingRepo: bookingRepo);
  final profileVm = ProfileViewModel(userRepo: userRepo, bookingRepo: bookingRepo);

  return _IntegrationSetup(
    firestore: firestore,
    bookingRepo: bookingRepo,
    homeVm: homeVm,
    paymentVm: paymentVm,
    trackingVm: trackingVm,
    profileVm: profileVm,
  );
}

Future<String> _createBookingAndTrack({
  required _IntegrationSetup setup,
  required String paymentMethod,
}) async {
  await setup.homeVm.init('user-1');
  setup.homeVm.selectOrigin('Jetty A');
  setup.homeVm.selectDestination('Jetty B');

  await setup.paymentVm.loadFare(
    origin: 'Jetty A',
    destination: 'Jetty B',
    adultCount: 2,
    childCount: 1,
  );
  setup.paymentVm.selectPaymentMethod(paymentMethod);

  final bookingResult = await setup.paymentVm.processPayment(
    userId: 'user-1',
    origin: 'Jetty A',
    destination: 'Jetty B',
    adultCount: 2,
    childCount: 1,
  );
  expect(bookingResult, isA<OperationSuccess>());

  final bookingId = (bookingResult as OperationSuccess).message;
  setup.trackingVm.startTracking(bookingId);
  setup.profileVm.startBookingHistoryStream('user-1');
  await Future<void>.delayed(Duration.zero);

  return bookingId;
}

class _IntegrationSetup {
  const _IntegrationSetup({
    required this.firestore,
    required this.bookingRepo,
    required this.homeVm,
    required this.paymentVm,
    required this.trackingVm,
    required this.profileVm,
  });

  final FakeFirebaseFirestore firestore;
  final BookingRepository bookingRepo;
  final HomeViewModel homeVm;
  final PaymentViewModel paymentVm;
  final BookingTrackingViewModel trackingVm;
  final ProfileViewModel profileVm;
}

Future<void> _seedFirestore(FakeFirebaseFirestore firestore) async {
  await firestore.collection(FirestoreCollections.users).doc('user-1').set({
    UserFields.uid: 'user-1',
    UserFields.name: 'Passenger One',
    UserFields.email: 'passenger@example.com',
    UserFields.phoneNumber: '0123456789',
    UserFields.createdAt: Timestamp.now(),
    UserFields.updatedAt: Timestamp.now(),
  });

  await firestore.collection(FirestoreCollections.jetties).doc('jetty-a').set({
    JettyFields.jettyId: '1',
    JettyFields.name: 'Jetty A',
    JettyFields.lat: 1.0,
    JettyFields.lng: 101.0,
  });

  await firestore.collection(FirestoreCollections.jetties).doc('jetty-b').set({
    JettyFields.jettyId: '2',
    JettyFields.name: 'Jetty B',
    JettyFields.lat: 2.0,
    JettyFields.lng: 102.0,
  });

  await firestore.collection(FirestoreCollections.fares).doc('fare-a-b').set({
    FareFields.origin: 'Jetty A',
    FareFields.destination: 'Jetty B',
    FareFields.adultFare: 12.0,
    FareFields.childFare: 6.0,
  });
}

Future<void> _operatorUpdateStatus({
  required FakeFirebaseFirestore firestore,
  required String bookingId,
  required BookingStatus status,
  required String driverId,
}) async {
  await firestore
      .collection(FirestoreCollections.bookings)
      .doc(bookingId)
      .update({
    BookingFields.status: status.firestoreValue,
    BookingFields.driverId: driverId,
    BookingFields.updatedAt: Timestamp.now(),
  });
}
