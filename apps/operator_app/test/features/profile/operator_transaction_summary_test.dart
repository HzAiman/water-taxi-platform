import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_transaction_summary_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('custom period filters summary metrics and ride history', () async {
    final repo = _FakeBookingRepository();
    final vm = OperatorTransactionSummaryViewModel(
      bookingRepository: repo,
      operatorId: 'operator-1',
    );

    await vm.initialize();
    repo.emit([
      _booking(
        id: 'inside-completed',
        status: BookingStatus.completed,
        fare: 18,
        updatedAt: DateTime(2026, 5, 10, 12),
      ),
      _booking(
        id: 'inside-cancelled',
        status: BookingStatus.cancelled,
        fare: 9,
        updatedAt: DateTime(2026, 5, 11, 9),
      ),
      _booking(
        id: 'inside-active',
        status: BookingStatus.onTheWay,
        fare: 7,
        updatedAt: DateTime(2026, 5, 12, 14),
      ),
      _booking(
        id: 'outside-completed',
        status: BookingStatus.completed,
        fare: 50,
        updatedAt: DateTime(2026, 5, 20, 12),
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    vm.selectCustomPeriod(DateTime(2026, 5, 10), DateTime(2026, 5, 12));

    expect(vm.selectedPeriod, SummaryPeriod.custom);
    expect(vm.selectedPeriodEarnings, 18);
    expect(vm.selectedPeriodCancelled, 1);
    expect(vm.selectedPeriodPendingOrActive, 1);
    expect(vm.historyForSelectedPeriod.map((booking) => booking.bookingId), [
      'inside-active',
      'inside-cancelled',
      'inside-completed',
    ]);
    expect(vm.selectedPeriodRangeLabel, '10 May 2026 - 12 May 2026');

    vm.dispose();
    await repo.close();
  });

  test('statement records preserve custom period range', () {
    final record = StatementRecord(
      filePath: 'statement.pdf',
      fileName: 'statement.pdf',
      period: SummaryPeriod.custom,
      generatedAt: DateTime(2026, 5, 21, 8),
      totalEarnings: 42,
      completedRides: 3,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 15, 23, 59, 59),
    );

    final restored = StatementRecord.fromMap(record.toMap());

    expect(restored.period, SummaryPeriod.custom);
    expect(restored.periodStart, DateTime(2026, 5, 1));
    expect(restored.periodEnd, DateTime(2026, 5, 15, 23, 59, 59));
  });

  testWidgets('ride history tile uses route title and passenger details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideHistoryTile(
            booking: _booking(
              id: 'booking-hidden-id',
              status: BookingStatus.completed,
              fare: 24.5,
              userName: 'Aina Rahman',
              origin: 'The Shore',
              destination: 'Kampung Jawa',
              adultCount: 2,
              childCount: 1,
              passengerCount: 3,
              updatedAt: DateTime(2026, 5, 10, 12, 30),
            ),
          ),
        ),
      ),
    );

    expect(find.text('booking-hidden-id'), findsNothing);
    expect(find.text('The Shore -> Kampung Jawa'), findsOneWidget);
    expect(find.text('Aina Rahman'), findsOneWidget);
    expect(find.text('Total 3'), findsOneWidget);
    expect(find.text('Adults 2'), findsOneWidget);
    expect(find.text('Children 1'), findsOneWidget);
    expect(find.text('RM 24.50'), findsOneWidget);
    expect(find.text('2026-05-10 12:30'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
}

class _FakeBookingRepository extends BookingRepository {
  _FakeBookingRepository()
    : _controller = StreamController<List<BookingModel>>.broadcast(),
      super(firestore: FakeFirebaseFirestore());

  final StreamController<List<BookingModel>> _controller;

  @override
  Stream<List<BookingModel>> streamOperatorBookingHistory(String operatorId) {
    return _controller.stream;
  }

  void emit(List<BookingModel> bookings) {
    _controller.add(bookings);
  }

  Future<void> close() => _controller.close();
}

BookingModel _booking({
  required String id,
  required BookingStatus status,
  required double fare,
  required DateTime updatedAt,
  String userName = 'Passenger One',
  String origin = 'Jetty A',
  String destination = 'Jetty B',
  int adultCount = 1,
  int childCount = 0,
  int passengerCount = 1,
}) {
  return BookingModel(
    bookingId: id,
    userId: 'user-1',
    userName: userName,
    userPhone: '0123456789',
    origin: origin,
    destination: destination,
    originLat: 1.0,
    originLng: 101.0,
    destinationLat: 2.0,
    destinationLng: 102.0,
    adultCount: adultCount,
    childCount: childCount,
    passengerCount: passengerCount,
    totalFare: fare,
    paymentMethod: PaymentMethods.creditCard,
    paymentStatus: 'paid',
    status: status,
    operatorUid: 'operator-1',
    rejectedBy: const [],
    createdAt: updatedAt.subtract(const Duration(minutes: 15)),
    updatedAt: updatedAt,
  );
}
