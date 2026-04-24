import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  group('OperatorRepository', () {
    test('setOnlineStatus updates only operator presence document', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = OperatorRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.operators)
          .doc('operator-1')
          .set({
            OperatorFields.operatorId: 'OP-1',
            OperatorFields.name: 'Captain Aiman',
            OperatorFields.email: 'captain@example.com',
            OperatorFields.isOnline: false,
          });

      await repository.setOnlineStatus('operator-1', isOnline: true);

      final operatorSnap = await firestore
          .collection(FirestoreCollections.operators)
          .doc('operator-1')
          .get();
      final presenceSnap = await firestore
          .collection(FirestoreCollections.operatorPresence)
          .doc('operator-1')
          .get();

      expect(operatorSnap.data()?[OperatorFields.isOnline], isFalse);
      expect(presenceSnap.data()?[OperatorPresenceFields.isOnline], isTrue);
    });
  });

  group('BookingRepository', () {
    test('acceptBooking preserves existing route polyline', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-1')
          .set({
            BookingFields.bookingId: 'booking-bind-1',
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Jetty A',
            BookingFields.destination: 'Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.pending.firestoreValue,
            BookingFields.operatorId: null,
            BookingFields.routePolyline: const [
              {'lat': 2.2, 'lng': 102.2},
              {'lat': 2.3, 'lng': 102.3},
            ],
            BookingFields.createdAt: Timestamp.now(),
            BookingFields.updatedAt: Timestamp.now(),
          });

      final result = await repository.acceptBooking(
        bookingId: 'booking-bind-1',
        operatorId: 'operator-1',
      );

      final bookingSnap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-1')
          .get();

      expect(result, isA<OperationSuccess>());
      expect(bookingSnap.data()?[BookingFields.status], 'accepted');
      expect(
        bookingSnap.data()?[BookingFields.routePolyline],
        equals(const [
          {'lat': 2.2, 'lng': 102.2},
          {'lat': 2.3, 'lng': 102.3},
        ]),
      );

      final historySnap = await bookingSnap.reference
          .collection(BookingSubcollections.statusHistory)
          .get();
      expect(historySnap.docs, hasLength(1));
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.from],
        BookingStatus.pending.firestoreValue,
      );
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.to],
        BookingStatus.accepted.firestoreValue,
      );
      expect(
        historySnap.docs.first.data()[BookingStatusHistoryFields.changedBy],
        'operator-1',
      );
    });

    test('acceptBooking succeeds without optional route config', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-2')
          .set({
            BookingFields.bookingId: 'booking-bind-2',
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Unknown Jetty A',
            BookingFields.destination: 'Unknown Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.pending.firestoreValue,
            BookingFields.operatorId: null,
            BookingFields.createdAt: Timestamp.now(),
            BookingFields.updatedAt: Timestamp.now(),
          });

      final result = await repository.acceptBooking(
        bookingId: 'booking-bind-2',
        operatorId: 'operator-1',
      );

      final bookingSnap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-bind-2')
          .get();

      expect(result, isA<OperationSuccess>());
      expect(bookingSnap.data()?[BookingFields.status], 'accepted');
    });

    test(
      'acceptBooking does not depend on unrelated config documents',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore.collection('misc').doc('config').set({'value': 'noop'});

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-bind-3')
            .set({
              BookingFields.bookingId: 'booking-bind-3',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.operatorId: null,
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final result = await repository.acceptBooking(
          bookingId: 'booking-bind-3',
          operatorId: 'operator-1',
        );

        final bookingSnap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-bind-3')
            .get();

        expect(result, isA<OperationSuccess>());
        expect(bookingSnap.data()?[BookingFields.status], 'accepted');
      },
    );

    test(
      'rejectBooking uses operator presence to fully reject booking',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore
            .collection(FirestoreCollections.operatorPresence)
            .doc('operator-1')
            .set({
              OperatorPresenceFields.isOnline: true,
              OperatorPresenceFields.updatedAt: Timestamp.now(),
            });

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-1')
            .set({
              BookingFields.bookingId: 'booking-1',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.operatorId: null,
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final result = await repository.rejectBooking(
          bookingId: 'booking-1',
          operatorId: 'operator-1',
        );

        final bookingSnap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-1')
            .get();

        expect(result, isA<OperationSuccess>());
        expect(
          bookingSnap.data()?[BookingFields.status],
          BookingStatus.rejected.firestoreValue,
        );
        expect(bookingSnap.data()?[BookingFields.rejectedBy], ['operator-1']);
      },
    );

    test('markPassengerPickedUp writes pickup timestamp only', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-pickup-1')
          .set({
            BookingFields.bookingId: 'booking-pickup-1',
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Jetty A',
            BookingFields.destination: 'Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.onTheWay.firestoreValue,
            BookingFields.operatorUid: 'operator-1',
            BookingFields.createdAt: Timestamp.now(),
            BookingFields.updatedAt: Timestamp.now(),
          });

      final result = await repository.markPassengerPickedUp(
        bookingId: 'booking-pickup-1',
        operatorId: 'operator-1',
      );

      final bookingSnap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-pickup-1')
          .get();

      expect(result, isA<OperationSuccess>());
      expect(
        bookingSnap.data()?[BookingFields.status],
        BookingStatus.onTheWay.firestoreValue,
      );
      expect(
        bookingSnap.data()?[BookingFields.passengerPickedUpAt],
        isA<Timestamp>(),
      );
    });

    test(
      'streamActiveBookings hydrates direct phase polylines and pickup timestamp',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);
        final pickupAt = Timestamp.fromDate(DateTime.utc(2026, 4, 24, 12, 0));

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-stream-1')
            .set({
              BookingFields.bookingId: 'booking-stream-1',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.onTheWay.firestoreValue,
              BookingFields.operatorUid: 'operator-1',
              BookingFields.routePolyline: const [
                {'lat': 2.2, 'lng': 102.2},
                {'lat': 2.3, 'lng': 102.3},
              ],
              BookingFields.routeToOriginPolyline: const [
                {'lat': 2.19, 'lng': 102.19},
                {'lat': 2.2, 'lng': 102.2},
              ],
              BookingFields.routeToDestinationPolyline: const [
                {'lat': 2.2, 'lng': 102.2},
                {'lat': 2.31, 'lng': 102.31},
              ],
              BookingFields.passengerPickedUpAt: pickupAt,
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final active = await repository
            .streamActiveBookings('operator-1')
            .first;
        expect(active, hasLength(1));
        final booking = active.first;
        expect(booking.routeToOriginPolyline, hasLength(2));
        expect(booking.routeToDestinationPolyline, hasLength(2));
        expect(booking.passengerPickedUpAt, pickupAt.toDate());
      },
    );

    test(
      'streamActiveBookings resolves nested phase routes and falls back to base route',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-stream-2')
            .set({
              BookingFields.bookingId: 'booking-stream-2',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.onTheWay.firestoreValue,
              BookingFields.operatorUid: 'operator-1',
              BookingFields.routePolyline: const [
                {'lat': 2.2, 'lng': 102.2},
                {'lat': 2.3, 'lng': 102.3},
              ],
              'phaseRoutes': const {
                'to_origin': [
                  {'lat': 2.18, 'lng': 102.18},
                  {'lat': 2.2, 'lng': 102.2},
                ],
              },
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final active = await repository
            .streamActiveBookings('operator-1')
            .first;
        expect(active, hasLength(1));
        final booking = active.first;

        expect(booking.routeToOriginPolyline, hasLength(2));
        expect(
          booking.routeToOriginPolyline.first.lat,
          closeTo(2.18, 0.000001),
        );
        // Destination phase missing -> falls back to main route polyline.
        expect(booking.routeToDestinationPolyline, hasLength(2));
        expect(
          booking.routeToDestinationPolyline.first.lat,
          closeTo(2.2, 0.000001),
        );
        expect(
          booking.routeToDestinationPolyline.last.lng,
          closeTo(102.3, 0.000001),
        );
      },
    );

    test(
      'streamPendingBookings filters assigned and sorts oldest first',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('pending-assigned')
            .set({
              BookingFields.bookingId: 'pending-assigned',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.operatorUid: 'operator-1',
              BookingFields.createdAt: Timestamp.fromDate(
                DateTime.utc(2026, 4, 25, 9, 30),
              ),
              BookingFields.updatedAt: Timestamp.now(),
            });

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('pending-new')
            .set({
              BookingFields.bookingId: 'pending-new',
              BookingFields.userId: 'user-2',
              BookingFields.userName: 'Passenger Two',
              BookingFields.userPhone: '0123456788',
              BookingFields.origin: 'Jetty C',
              BookingFields.destination: 'Jetty D',
              BookingFields.originCoords: const GeoPoint(2.25, 102.25),
              BookingFields.destinationCoords: const GeoPoint(2.35, 102.35),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 11.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.createdAt: Timestamp.fromDate(
                DateTime.utc(2026, 4, 25, 9, 40),
              ),
              BookingFields.updatedAt: Timestamp.now(),
            });

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('pending-old')
            .set({
              BookingFields.bookingId: 'pending-old',
              BookingFields.userId: 'user-3',
              BookingFields.userName: 'Passenger Three',
              BookingFields.userPhone: '0123456777',
              BookingFields.origin: 'Jetty E',
              BookingFields.destination: 'Jetty F',
              BookingFields.originCoords: const GeoPoint(2.26, 102.26),
              BookingFields.destinationCoords: const GeoPoint(2.36, 102.36),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 12.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.pending.firestoreValue,
              BookingFields.createdAt: Timestamp.fromDate(
                DateTime.utc(2026, 4, 25, 9, 20),
              ),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final pending = await repository.streamPendingBookings().first;
        expect(pending.map((b) => b.bookingId), ['pending-old', 'pending-new']);
      },
    );

    test(
      'streamActiveBookings keeps only accepted and on_the_way statuses',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        Future<void> seed(String id, String status, DateTime updatedAt) {
          return firestore
              .collection(FirestoreCollections.bookings)
              .doc(id)
              .set({
                BookingFields.bookingId: id,
                BookingFields.userId: 'user-1',
                BookingFields.userName: 'Passenger One',
                BookingFields.userPhone: '0123456789',
                BookingFields.origin: 'Jetty A',
                BookingFields.destination: 'Jetty B',
                BookingFields.originCoords: const GeoPoint(2.2, 102.2),
                BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
                BookingFields.adultCount: 1,
                BookingFields.childCount: 0,
                BookingFields.passengerCount: 1,
                BookingFields.totalFare: 10.0,
                BookingFields.fareSnapshotId: 'fare-snapshot-test',
                BookingFields.paymentMethod: PaymentMethods.onlineBanking,
                BookingFields.paymentStatus: 'paid',
                BookingFields.status: status,
                BookingFields.operatorUid: 'operator-1',
                BookingFields.createdAt: Timestamp.now(),
                BookingFields.updatedAt: Timestamp.fromDate(updatedAt),
              });
        }

        await seed(
          'active-completed',
          BookingStatus.completed.firestoreValue,
          DateTime.utc(2026, 4, 25, 10, 0),
        );
        await seed(
          'active-accepted',
          BookingStatus.accepted.firestoreValue,
          DateTime.utc(2026, 4, 25, 10, 5),
        );
        await seed(
          'active-ontheway',
          BookingStatus.onTheWay.firestoreValue,
          DateTime.utc(2026, 4, 25, 10, 10),
        );

        final active = await repository
            .streamActiveBookings('operator-1')
            .first;
        expect(active.map((b) => b.bookingId), [
          'active-ontheway',
          'active-accepted',
        ]);
      },
    );

    test(
      'streamActiveBookings hydrates route via routePolylineId coordinates',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore
            .collection(FirestoreCollections.polylines)
            .doc('polyline-1')
            .set({
              'coordinates': const [
                {'lat': 2.205, 'lng': 102.245},
                {'lat': 2.215, 'lng': 102.255},
              ],
            });

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-polyline-id')
            .set({
              BookingFields.bookingId: 'booking-polyline-id',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.routePolylineId: 'polyline-1',
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.onTheWay.firestoreValue,
              BookingFields.operatorUid: 'operator-1',
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final active = await repository
            .streamActiveBookings('operator-1')
            .first;
        expect(active, hasLength(1));
        expect(active.first.routePolyline, hasLength(2));
        expect(active.first.routePolyline.first.lat, closeTo(2.205, 0.000001));
        expect(active.first.routePolyline.last.lng, closeTo(102.255, 0.000001));
      },
    );

    test(
      'streamActiveBookings falls back to direct route when polyline doc missing',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-polyline-fallback')
            .set({
              BookingFields.bookingId: 'booking-polyline-fallback',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2001, 102.2001),
              BookingFields.destinationCoords: const GeoPoint(2.3002, 102.3002),
              BookingFields.routePolylineId: 'polyline-missing',
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.onTheWay.firestoreValue,
              BookingFields.operatorUid: 'operator-1',
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final active = await repository
            .streamActiveBookings('operator-1')
            .first;
        expect(active, hasLength(1));
        expect(active.first.routePolyline, hasLength(2));
        expect(active.first.routePolyline.first.lat, closeTo(2.2001, 0.000001));
        expect(
          active.first.routePolyline.last.lng,
          closeTo(102.3002, 0.000001),
        );
      },
    );

    test(
      'releaseBooking returns booking to pending and appends history',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-release-1')
            .set({
              BookingFields.bookingId: 'booking-release-1',
              BookingFields.userId: 'user-1',
              BookingFields.userName: 'Passenger One',
              BookingFields.userPhone: '0123456789',
              BookingFields.origin: 'Jetty A',
              BookingFields.destination: 'Jetty B',
              BookingFields.originCoords: const GeoPoint(2.2, 102.2),
              BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
              BookingFields.adultCount: 1,
              BookingFields.childCount: 0,
              BookingFields.passengerCount: 1,
              BookingFields.totalFare: 10.0,
              BookingFields.fareSnapshotId: 'fare-snapshot-test',
              BookingFields.paymentMethod: PaymentMethods.onlineBanking,
              BookingFields.paymentStatus: 'paid',
              BookingFields.status: BookingStatus.accepted.firestoreValue,
              BookingFields.operatorUid: 'operator-1',
              BookingFields.rejectedBy: const ['operator-2'],
              BookingFields.createdAt: Timestamp.now(),
              BookingFields.updatedAt: Timestamp.now(),
            });

        final result = await repository.releaseBooking(
          bookingId: 'booking-release-1',
          operatorId: 'operator-1',
        );

        final bookingSnap = await firestore
            .collection(FirestoreCollections.bookings)
            .doc('booking-release-1')
            .get();
        final history = await bookingSnap.reference
            .collection(BookingSubcollections.statusHistory)
            .get();

        expect(result, isA<OperationSuccess>());
        expect(
          bookingSnap.data()?[BookingFields.status],
          BookingStatus.pending.firestoreValue,
        );
        expect(bookingSnap.data()?[BookingFields.operatorUid], isNull);
        expect(
          bookingSnap.data()?[BookingFields.rejectedBy],
          contains('operator-1'),
        );
        expect(history.docs, hasLength(1));
        expect(
          history.docs.first.data()[BookingStatusHistoryFields.to],
          BookingStatus.pending.firestoreValue,
        );
      },
    );

    test('releaseBooking rejects when booking not owned by operator', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-release-2')
          .set({
            BookingFields.bookingId: 'booking-release-2',
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Jetty A',
            BookingFields.destination: 'Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.accepted.firestoreValue,
            BookingFields.operatorUid: 'operator-x',
            BookingFields.createdAt: Timestamp.now(),
            BookingFields.updatedAt: Timestamp.now(),
          });

      final result = await repository.releaseBooking(
        bookingId: 'booking-release-2',
        operatorId: 'operator-1',
      );

      expect(result, isA<OperationFailure>());
      expect((result as OperationFailure).isInfo, isTrue);
      expect(
        result.message,
        contains('Only your accepted booking can be released'),
      );
    });

    test('releaseAllAcceptedBookings updates only accepted bookings', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      Future<void> seed(String id, BookingStatus status) {
        return firestore.collection(FirestoreCollections.bookings).doc(id).set({
          BookingFields.bookingId: id,
          BookingFields.userId: 'user-1',
          BookingFields.userName: 'Passenger One',
          BookingFields.userPhone: '0123456789',
          BookingFields.origin: 'Jetty A',
          BookingFields.destination: 'Jetty B',
          BookingFields.originCoords: const GeoPoint(2.2, 102.2),
          BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
          BookingFields.adultCount: 1,
          BookingFields.childCount: 0,
          BookingFields.passengerCount: 1,
          BookingFields.totalFare: 10.0,
          BookingFields.fareSnapshotId: 'fare-snapshot-test',
          BookingFields.paymentMethod: PaymentMethods.onlineBanking,
          BookingFields.paymentStatus: 'paid',
          BookingFields.status: status.firestoreValue,
          BookingFields.operatorUid: 'operator-1',
          BookingFields.rejectedBy: const <String>[],
          BookingFields.createdAt: Timestamp.now(),
          BookingFields.updatedAt: Timestamp.now(),
        });
      }

      await seed('release-all-accepted-1', BookingStatus.accepted);
      await seed('release-all-accepted-2', BookingStatus.accepted);
      await seed('release-all-ontheway', BookingStatus.onTheWay);

      final released = await repository.releaseAllAcceptedBookings(
        'operator-1',
      );

      final b1 = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('release-all-accepted-1')
          .get();
      final b2 = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('release-all-accepted-2')
          .get();
      final b3 = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('release-all-ontheway')
          .get();

      expect(released, 2);
      expect(
        b1.data()?[BookingFields.status],
        BookingStatus.pending.firestoreValue,
      );
      expect(
        b2.data()?[BookingFields.status],
        BookingStatus.pending.firestoreValue,
      );
      expect(
        b3.data()?[BookingFields.status],
        BookingStatus.onTheWay.firestoreValue,
      );
    });

    test('completeTrip archives booking with terminal metadata', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = BookingRepository(firestore: firestore);

      await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-complete-1')
          .set({
            BookingFields.bookingId: 'booking-complete-1',
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Jetty A',
            BookingFields.destination: 'Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.onTheWay.firestoreValue,
            BookingFields.operatorUid: 'operator-1',
            BookingFields.createdAt: Timestamp.now(),
            BookingFields.updatedAt: Timestamp.now(),
          });

      final result = await repository.completeTrip(
        bookingId: 'booking-complete-1',
        operatorId: 'operator-1',
      );

      final bookingSnap = await firestore
          .collection(FirestoreCollections.bookings)
          .doc('booking-complete-1')
          .get();
      final archiveSnap = await firestore
          .collection(FirestoreCollections.bookingsArchive)
          .doc('booking-complete-1')
          .get();

      expect(result, isA<OperationSuccess>());
      expect(
        bookingSnap.data()?[BookingFields.status],
        BookingStatus.completed.firestoreValue,
      );
      expect(archiveSnap.exists, isTrue);
      expect(
        archiveSnap.data()?['archivedStatus'],
        BookingStatus.completed.firestoreValue,
      );
    });

    test(
      'streamOperatorBookingHistory sorts by updatedAt descending',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = BookingRepository(firestore: firestore);

        Future<void> seed({
          required String id,
          required DateTime created,
          DateTime? updated,
        }) {
          final data = <String, dynamic>{
            BookingFields.bookingId: id,
            BookingFields.userId: 'user-1',
            BookingFields.userName: 'Passenger One',
            BookingFields.userPhone: '0123456789',
            BookingFields.origin: 'Jetty A',
            BookingFields.destination: 'Jetty B',
            BookingFields.originCoords: const GeoPoint(2.2, 102.2),
            BookingFields.destinationCoords: const GeoPoint(2.3, 102.3),
            BookingFields.adultCount: 1,
            BookingFields.childCount: 0,
            BookingFields.passengerCount: 1,
            BookingFields.totalFare: 10.0,
            BookingFields.fareSnapshotId: 'fare-snapshot-test',
            BookingFields.paymentMethod: PaymentMethods.onlineBanking,
            BookingFields.paymentStatus: 'paid',
            BookingFields.status: BookingStatus.completed.firestoreValue,
            BookingFields.operatorUid: 'operator-1',
            BookingFields.createdAt: Timestamp.fromDate(created),
          };
          if (updated != null) {
            data[BookingFields.updatedAt] = Timestamp.fromDate(updated);
          }
          return firestore
              .collection(FirestoreCollections.bookings)
              .doc(id)
              .set(data);
        }

        await seed(
          id: 'history-1',
          created: DateTime.utc(2026, 4, 25, 9, 0),
          updated: DateTime.utc(2026, 4, 25, 10, 0),
        );
        await seed(id: 'history-2', created: DateTime.utc(2026, 4, 25, 11, 0));
        await seed(
          id: 'history-3',
          created: DateTime.utc(2026, 4, 25, 8, 0),
          updated: DateTime.utc(2026, 4, 25, 12, 0),
        );

        final history = await repository
            .streamOperatorBookingHistory('operator-1')
            .first;
        expect(history.map((b) => b.bookingId), [
          'history-3',
          'history-2',
          'history-1',
        ]);
      },
    );
  });
}
