import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/services/payment/payment_gateway_service.dart';

/// ViewModel for [BookingTrackingScreen].
///
/// Streams a single booking and exposes a cancel action.
class BookingTrackingViewModel extends ChangeNotifier {
  BookingTrackingViewModel({
    required BookingRepository bookingRepo,
    PaymentGatewayService? paymentGateway,
  })  : _bookingRepo = bookingRepo,
        _paymentGateway = paymentGateway ?? CloudFunctionPaymentGatewayService();

  final BookingRepository _bookingRepo;
  final PaymentGatewayService _paymentGateway;

  BookingModel? _booking;
  bool _isCancelling = false;
  StreamSubscription<BookingModel?>? _subscription;

  BookingModel? get booking => _booking;
  bool get isCancelling => _isCancelling;

  void _debugLog(String message) {
    if (kDebugMode) {
      developer.log(message, name: 'BookingTrackingViewModel');
    }
  }

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
      _debugLog(
        'cancelBooking start: bookingId=$bookingId, orderNumber=${currentBooking.orderNumber}, transactionId=${currentBooking.transactionId}',
      );

      // First, attempt to refund held payment if it exists
      if (currentBooking.transactionId?.isNotEmpty == true &&
          currentBooking.orderNumber?.isNotEmpty == true) {
        _debugLog(
          'Attempting payment cancellation for intent=${currentBooking.transactionId}',
        );

        final refundResult = await _paymentGateway.cancelPayment(
          paymentIntentId: currentBooking.transactionId!,
          orderNumber: currentBooking.orderNumber!,
          reason: 'passenger_cancelled_booking',
        );

        _debugLog(
          'Refund result: status=${refundResult.status}, error=${refundResult.errorMessage}',
        );

        // Check if refund was successful (status should be 'cancelled')
        if (refundResult.status != PaymentGatewayStatus.cancelled) {
          final errorMsg = refundResult.errorMessage ?? 'Unknown error';

          // Special handling for NOT_FOUND - might be a pre-paid booking
          if (errorMsg.contains('NOT_FOUND')) {
            _debugLog(
              'Payment intent not found during cancel; allowing booking cancellation to proceed.',
            );
            // Allow cancellation to proceed even if refund fails with NOT_FOUND
            // (payment may have already been processed differently)
          } else {
            return OperationFailure(
              'Refund failed',
              'Failed to process refund: $errorMsg',
            );
          }
        }
      }

      // Update booking status to cancelled
      await _bookingRepo.cancelBooking(bookingId);
      _debugLog('Booking status updated to cancelled: bookingId=$bookingId');
      return const OperationSuccess('Booking cancelled successfully.');
    } catch (e) {
      _debugLog('cancelBooking exception: ${e.toString()}');
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
