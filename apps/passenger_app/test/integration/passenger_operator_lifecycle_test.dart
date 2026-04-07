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
import 'package:passenger_app/services/payment/payment_gateway_service.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  test(
    'integration: booking lifecycle syncs across passenger viewmodels',
    () async {
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
        operatorId: 'operator-1',
      );
      await Future<void>.delayed(Duration.zero);
      expect(trackingVm.booking?.status, BookingStatus.accepted);
      expect(homeVm.activeBooking?.status, BookingStatus.accepted);

      await _operatorUpdateStatus(
        firestore: firestore,
        bookingId: bookingId,
        status: BookingStatus.onTheWay,
        operatorId: 'operator-1',
      );
      await Future<void>.delayed(Duration.zero);
      expect(trackingVm.booking?.status, BookingStatus.onTheWay);
      expect(homeVm.activeBooking?.status, BookingStatus.onTheWay);

      await _operatorUpdateStatus(
        firestore: firestore,
        bookingId: bookingId,
        status: BookingStatus.completed,
        operatorId: 'operator-1',
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
    },
  );

  for (final status in [
    BookingStatus.pending,
    BookingStatus.accepted,
    BookingStatus.onTheWay,
  ]) {
    test('integration: passenger can cancel $status booking', () async {
      final setup = await _createSetup();
      final firestore = setup.firestore;
      final trackingVm = setup.trackingVm;

      final bookingId = await _createBookingAndTrack(setup: setup);

      if (status != BookingStatus.pending) {
        await _operatorUpdateStatus(
          firestore: firestore,
          bookingId: bookingId,
          status: status,
          operatorId: 'operator-1',
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
      expect(
        snap.data()?[BookingFields.status],
        BookingStatus.cancelled.firestoreValue,
      );
      expect(snap.data()?[BookingFields.cancelledAt], isNotNull);

      setup.profileVm.stopBookingHistoryStream();
      setup.homeVm.dispose();
      setup.trackingVm.dispose();
      setup.profileVm.dispose();
    });
  }

  test(
    'integration: completed booking cannot be cancelled by passenger',
    () async {
      final setup = await _createSetup();
      final firestore = setup.firestore;
      final trackingVm = setup.trackingVm;

      final bookingId = await _createBookingAndTrack(setup: setup);

      await _operatorUpdateStatus(
        firestore: firestore,
        bookingId: bookingId,
        status: BookingStatus.completed,
        operatorId: 'operator-1',
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
    },
  );

  test(
    'integration: passenger tracking receives operator location and route polyline updates',
    () async {
      final setup = await _createSetup();
      final firestore = setup.firestore;
      final trackingVm = setup.trackingVm;

      final bookingId = await _createBookingAndTrack(setup: setup);

      await _operatorUpdateStatus(
        firestore: firestore,
        bookingId: bookingId,
        status: BookingStatus.onTheWay,
        operatorId: 'operator-1',
        operatorLat: 2.1910,
        operatorLng: 102.2490,
        routePolyline: const [
          {'lat': 2.1900, 'lng': 102.2480},
          {'lat': 2.1910, 'lng': 102.2490},
          {'lat': 2.1920, 'lng': 102.2500},
        ],
      );
      await Future<void>.delayed(Duration.zero);

      expect(trackingVm.booking, isNotNull);
      expect(trackingVm.booking!.status, BookingStatus.onTheWay);
      expect(trackingVm.booking!.operatorLat, closeTo(2.1910, 0.0000001));
      expect(trackingVm.booking!.operatorLng, closeTo(102.2490, 0.0000001));
      expect(trackingVm.booking!.routePolyline, hasLength(3));
      expect(trackingVm.booking!.routePolyline.first.lat, closeTo(2.1900, 0.0000001));
      expect(trackingVm.booking!.routePolyline.first.lng, closeTo(102.2480, 0.0000001));

      await _operatorUpdateStatus(
        firestore: firestore,
        bookingId: bookingId,
        status: BookingStatus.completed,
        operatorId: 'operator-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(trackingVm.booking, isNotNull);
      expect(trackingVm.booking!.status, BookingStatus.completed);
      expect(trackingVm.booking!.routePolyline, hasLength(3));

      setup.profileVm.stopBookingHistoryStream();
      setup.homeVm.dispose();
      setup.trackingVm.dispose();
      setup.profileVm.dispose();
    },
  );

  test(
    'integration: passenger tracking parses legacy polyline field variants',
    () async {
      final setup = await _createSetup();
      final firestore = setup.firestore;
      final trackingVm = setup.trackingVm;

      final bookingId = await _createBookingAndTrack(setup: setup);

      final ref = firestore.collection(FirestoreCollections.bookings).doc(bookingId);

      await ref.update({
        BookingFields.status: BookingStatus.onTheWay.firestoreValue,
        BookingFields.operatorUid: 'operator-1',
        BookingFields.operatorId: 'operator-1',
        BookingFields.updatedAt: Timestamp.now(),
        BookingFields.routePolyline: FieldValue.delete(),
        'routeCoordinates': const [
          {'lat': 2.2000, 'lng': 102.2600},
          {'lat': 2.2100, 'lng': 102.2700},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(trackingVm.booking, isNotNull);
      expect(trackingVm.booking!.routePolyline, hasLength(2));
      expect(trackingVm.booking!.routePolyline.first.lat, closeTo(2.2000, 0.0000001));
      expect(trackingVm.booking!.routePolyline.first.lng, closeTo(102.2600, 0.0000001));

      await ref.update({
        BookingFields.updatedAt: Timestamp.now(),
        'routeCoordinates': FieldValue.delete(),
        'polylineCoordinates': const [
          {'lat': 2.2200, 'lng': 102.2800},
          {'lat': 2.2300, 'lng': 102.2900},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(trackingVm.booking!.routePolyline, hasLength(2));
      expect(trackingVm.booking!.routePolyline.first.lat, closeTo(2.2200, 0.0000001));
      expect(trackingVm.booking!.routePolyline.first.lng, closeTo(102.2800, 0.0000001));

      await ref.update({
        BookingFields.updatedAt: Timestamp.now(),
        'polylineCoordinates': FieldValue.delete(),
        'routePoints': const [
          {'latitude': 2.2400, 'longitude': 102.3000},
          {'latitude': 2.2500, 'longitude': 102.3100},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(trackingVm.booking!.routePolyline, hasLength(2));
      expect(trackingVm.booking!.routePolyline.first.lat, closeTo(2.2400, 0.0000001));
      expect(trackingVm.booking!.routePolyline.first.lng, closeTo(102.3000, 0.0000001));

      setup.profileVm.stopBookingHistoryStream();
      setup.homeVm.dispose();
      setup.trackingVm.dispose();
      setup.profileVm.dispose();
    },
  );

  test(
    'integration: payment failure can be retried and only successful attempt creates booking',
    () async {
      final setup = await _createSetup(
        paymentGateway: _ScriptedPaymentGatewayService(
          chargeResponses: [
            const PaymentGatewayResult(
              status: PaymentGatewayStatus.failed,
              errorMessage: 'Gateway timeout',
            ),
            const PaymentGatewayResult(
              status: PaymentGatewayStatus.authorized,
              transactionId: 'pi-retry-success-1',
            ),
          ],
        ),
      );

      await setup.homeVm.init('user-1');
      await setup.paymentVm.loadFare(
        origin: 'Jetty A',
        destination: 'Jetty B',
        adultCount: 1,
        childCount: 0,
      );

      final firstAttempt = await setup.paymentVm.processPayment(
        userId: 'user-1',
        origin: 'Jetty A',
        destination: 'Jetty B',
        adultCount: 1,
        childCount: 0,
      );

      expect(firstAttempt, isA<OperationFailure>());
      final failedDocs = await setup.firestore
          .collection(FirestoreCollections.bookings)
          .where(BookingFields.userId, isEqualTo: 'user-1')
          .get();
      expect(failedDocs.docs, isEmpty);

      final retryAttempt = await setup.paymentVm.processPayment(
        userId: 'user-1',
        origin: 'Jetty A',
        destination: 'Jetty B',
        adultCount: 1,
        childCount: 0,
      );

      expect(retryAttempt, isA<OperationSuccess>());
      final retryBookingId = (retryAttempt as OperationSuccess).message;
      expect(retryBookingId, isNotEmpty);

      final createdSnap = await setup.firestore
          .collection(FirestoreCollections.bookings)
          .where(BookingFields.userId, isEqualTo: 'user-1')
          .get();
      expect(createdSnap.docs, hasLength(1));

      setup.profileVm.stopBookingHistoryStream();
      setup.homeVm.dispose();
      setup.trackingVm.dispose();
      setup.profileVm.dispose();
    },
  );

  test(
    'integration: cancellation continues when payment cancel returns NOT_FOUND reconciliation signal',
    () async {
      final setup = await _createSetup(
        paymentGateway: _ScriptedPaymentGatewayService(
          chargeResponses: const [
            PaymentGatewayResult(
              status: PaymentGatewayStatus.authorized,
              transactionId: 'pi-not-found-1',
            ),
          ],
          cancelResponse: const PaymentGatewayResult(
            status: PaymentGatewayStatus.failed,
            errorMessage: 'NOT_FOUND: PaymentIntent does not exist',
          ),
        ),
      );

      final bookingId = await _createBookingAndTrack(setup: setup);
      await _operatorUpdateStatus(
        firestore: setup.firestore,
        bookingId: bookingId,
        status: BookingStatus.accepted,
        operatorId: 'operator-1',
      );
      await Future<void>.delayed(Duration.zero);

      final result = await setup.trackingVm.cancelBooking(bookingId);
      await Future<void>.delayed(Duration.zero);

      expect(result, isA<OperationSuccess>());

      final snap = await setup.firestore
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .get();
      expect(
        snap.data()?[BookingFields.status],
        BookingStatus.cancelled.firestoreValue,
      );

      setup.profileVm.stopBookingHistoryStream();
      setup.homeVm.dispose();
      setup.trackingVm.dispose();
      setup.profileVm.dispose();
    },
  );

  test(
    'integration: cancellation is blocked when payment cancellation fails without reconciliation override',
    () async {
      final setup = await _createSetup(
        paymentGateway: _ScriptedPaymentGatewayService(
          chargeResponses: const [
            PaymentGatewayResult(
              status: PaymentGatewayStatus.authorized,
              transactionId: 'pi-fail-cancel-1',
            ),
          ],
          cancelResponse: const PaymentGatewayResult(
            status: PaymentGatewayStatus.failed,
            errorMessage: 'Gateway timeout',
          ),
        ),
      );

      final bookingId = await _createBookingAndTrack(setup: setup);
      await _operatorUpdateStatus(
        firestore: setup.firestore,
        bookingId: bookingId,
        status: BookingStatus.accepted,
        operatorId: 'operator-1',
      );
      await Future<void>.delayed(Duration.zero);

      final result = await setup.trackingVm.cancelBooking(bookingId);

      expect(result, isA<OperationFailure>());
      final failure = result as OperationFailure;
      expect(failure.title, 'Refund failed');

      final snap = await setup.firestore
          .collection(FirestoreCollections.bookings)
          .doc(bookingId)
          .get();
      expect(
        snap.data()?[BookingFields.status],
        BookingStatus.accepted.firestoreValue,
      );

      setup.profileVm.stopBookingHistoryStream();
      setup.homeVm.dispose();
      setup.trackingVm.dispose();
      setup.profileVm.dispose();
    },
  );
}

Future<_IntegrationSetup> _createSetup({
  PaymentGatewayService? paymentGateway,
}) async {
  final firestore = FakeFirebaseFirestore();
  await _seedFirestore(firestore);

  final userRepo = UserRepository(firestore: firestore);
  final jettyRepo = JettyRepository(firestore: firestore);
  final fareRepo = FareRepository(firestore: firestore);
  final bookingRepo = BookingRepository(firestore: firestore);
  final gateway = paymentGateway ?? SimulatedExternalPaymentGatewayService(
    simulatedLatency: Duration.zero,
  );

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
    paymentGateway: gateway,
  );
  final trackingVm = BookingTrackingViewModel(
    bookingRepo: bookingRepo,
    paymentGateway: gateway,
  );
  final profileVm = ProfileViewModel(
    userRepo: userRepo,
    bookingRepo: bookingRepo,
  );

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

class _ScriptedPaymentGatewayService implements PaymentGatewayService {
  _ScriptedPaymentGatewayService({
    required List<PaymentGatewayResult> chargeResponses,
    PaymentGatewayResult? cancelResponse,
  })  : _chargeResponses = List<PaymentGatewayResult>.from(chargeResponses),
        _cancelResponse =
            cancelResponse ??
            const PaymentGatewayResult(status: PaymentGatewayStatus.cancelled);

  final List<PaymentGatewayResult> _chargeResponses;
  final PaymentGatewayResult _cancelResponse;

  @override
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request) async {
    if (_chargeResponses.isEmpty) {
      return const PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: 'No scripted charge response available',
      );
    }
    return _chargeResponses.removeAt(0);
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
    return _cancelResponse;
  }
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
  required String operatorId,
  double? operatorLat,
  double? operatorLng,
  List<Map<String, double>>? routePolyline,
}) async {
  final payload = <String, dynamic>{
    BookingFields.status: status.firestoreValue,
    BookingFields.operatorUid: operatorId,
    BookingFields.operatorId: operatorId,
    BookingFields.updatedAt: Timestamp.now(),
  };

  if (operatorLat != null && operatorLng != null) {
    payload[BookingFields.operatorLat] = operatorLat;
    payload[BookingFields.operatorLng] = operatorLng;
  }

  if (routePolyline != null) {
    payload[BookingFields.routePolyline] = routePolyline;
  }

  await firestore
      .collection(FirestoreCollections.bookings)
      .doc(bookingId)
      .update(payload);
}
