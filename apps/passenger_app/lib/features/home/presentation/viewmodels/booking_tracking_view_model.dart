import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:passenger_app/data/repositories/booking_repository.dart';

/// ViewModel for [BookingTrackingScreen].
///
/// Streams a single booking and exposes a cancel action.
class BookingTrackingViewModel extends ChangeNotifier {
  BookingTrackingViewModel({required BookingRepository bookingRepo})
      : _bookingRepo = bookingRepo;

  final BookingRepository _bookingRepo;

  BookingModel? _booking;
  bool _isCancelling = false;
  StreamSubscription<BookingModel?>? _subscription;

  BookingModel? get booking => _booking;
  bool get isCancelling => _isCancelling;

  /// Subscribes to real-time updates for [bookingId].
  void startTracking(String bookingId) {
    _subscription?.cancel();
    _subscription = _bookingRepo.streamBooking(bookingId).listen((b) {
      _booking = b;
      notifyListeners();
    });
  }

  /// Cancels the tracked booking.
  Future<OperationResult> cancelBooking(String bookingId) async {
    final currentBooking = _booking;
    if (currentBooking == null) {
      return const OperationFailure(
        'Booking unavailable',
        'Unable to cancel because booking details are not loaded yet.',
        isInfo: true,
      );
    }
    if (!currentBooking.status.canBeCancelledByPassenger) {
      return OperationFailure(
        'Cancellation unavailable',
        'This booking is already ${currentBooking.status.firestoreValue.replaceAll('_', ' ')} and cannot be cancelled.',
        isInfo: true,
      );
    }

    _isCancelling = true;
    notifyListeners();

    try {
      await _bookingRepo.cancelBooking(bookingId);
      return const OperationSuccess('Booking cancelled successfully.');
    } catch (e) {
      return OperationFailure(
        'Cancel failed',
        'Failed to cancel booking: ${e.toString()}',
      );
    } finally {
      _isCancelling = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
