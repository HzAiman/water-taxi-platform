import 'package:flutter/foundation.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/fare_repository.dart';
import 'package:passenger_app/data/repositories/jetty_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';
import 'package:passenger_app/services/payment/payment_gateway_service.dart';

/// Fare breakdown calculated from a [FareModel] and passenger counts.
class FareBreakdown {
  const FareBreakdown({
    required this.adultFarePerPerson,
    required this.childFarePerPerson,
    required this.adultSubtotal,
    required this.childSubtotal,
    required this.total,
  });

  final double adultFarePerPerson;
  final double childFarePerPerson;
  final double adultSubtotal;
  final double childSubtotal;
  final double total;
}

/// ViewModel for [PaymentScreen].
///
/// Owns fare loading and the booking-creation flow.
class PaymentViewModel extends ChangeNotifier {
  PaymentViewModel({
    required FareRepository fareRepo,
    required JettyRepository jettyRepo,
    required UserRepository userRepo,
    required BookingRepository bookingRepo,
    required PaymentGatewayService paymentGateway,
  }) : _fareRepo = fareRepo,
       _jettyRepo = jettyRepo,
       _userRepo = userRepo,
       _bookingRepo = bookingRepo,
       _paymentGateway = paymentGateway;

  final FareRepository _fareRepo;
  final JettyRepository _jettyRepo;
  final UserRepository _userRepo;
  final BookingRepository _bookingRepo;
  final PaymentGatewayService _paymentGateway;
  static const String _gatewayPaymentMethod = 'stripe_payment_sheet';

  // ── State ────────────────────────────────────────────────────────────────

  bool _isLoadingFare = true;
  FareBreakdown? _fareBreakdown;
  String? _fareSnapshotId;
  String? _fareError;
  bool _isProcessing = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isLoadingFare => _isLoadingFare;
  FareBreakdown? get fareBreakdown => _fareBreakdown;
  String? get fareError => _fareError;
  bool get isProcessing => _isProcessing;

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> loadFare({
    required String origin,
    required String destination,
    required int adultCount,
    required int childCount,
  }) async {
    _isLoadingFare = true;
    _fareError = null;
    _fareSnapshotId = null;
    notifyListeners();

    try {
      final originJettyFuture = _jettyRepo.getJettyByName(origin);
      final destJettyFuture = _jettyRepo.getJettyByName(destination);
      final jetties = await Future.wait([originJettyFuture, destJettyFuture]);
      final originJetty = jetties[0];
      final destJetty = jetties[1];
      final originJettyId = _resolveCanonicalJettyId(originJetty);
      final destinationJettyId = _resolveCanonicalJettyId(destJetty);

      if (originJettyId == null || destinationJettyId == null) {
        _fareError = 'Canonical jetty ID missing for selected route';
        return;
      }

      final fare = await _fareRepo.getFare(
        origin,
        destination,
        originJettyId: originJettyId,
        destinationJettyId: destinationJettyId,
      );
      if (fare == null) {
        _fareError = 'Fare not found for this route';
        return;
      }
      if (fare.snapshotId == null || fare.snapshotId!.isEmpty) {
        _fareError = 'Fare snapshot unavailable for this route';
        return;
      }

      final adultSubtotal = fare.adultFare * adultCount;
      final childSubtotal = fare.childFare * childCount;

      _fareBreakdown = FareBreakdown(
        adultFarePerPerson: fare.adultFare,
        childFarePerPerson: fare.childFare,
        adultSubtotal: adultSubtotal,
        childSubtotal: childSubtotal,
        total: adultSubtotal + childSubtotal,
      );
      _fareSnapshotId = fare.snapshotId;
    } catch (_) {
      _fareError = 'Failed to load fare information';
    } finally {
      _isLoadingFare = false;
      notifyListeners();
    }
  }

  /// Validates inputs, creates the booking document, and returns an
  /// [OperationResult]. On success, the result message contains the booking ID.
  Future<OperationResult> processPayment({
    required String userId,
    required String origin,
    required String destination,
    required int adultCount,
    required int childCount,
  }) async {
    if (_fareBreakdown == null) {
      return const OperationFailure(
        'Fare unavailable',
        'Fare details are unavailable. Please go back and try again.',
      );
    }

    _isProcessing = true;
    notifyListeners();

    try {
      final userFuture = _userRepo.getUser(userId);
      final originJettyFuture = _jettyRepo.getJettyByName(origin);
      final destJettyFuture = _jettyRepo.getJettyByName(destination);

      final results = await Future.wait([
        userFuture,
        originJettyFuture,
        destJettyFuture,
      ]);

      final user = results[0] as UserModel?;
      final originJetty = results[1] as JettyModel?;
      final destJetty = results[2] as JettyModel?;

      if (originJetty == null) {
        return OperationFailure('Jetty error', 'Jetty "$origin" not found.');
      }
      if (destJetty == null) {
        return OperationFailure(
          'Jetty error',
          'Jetty "$destination" not found.',
        );
      }

      final originJettyId = _resolveCanonicalJettyId(originJetty);
      final destinationJettyId = _resolveCanonicalJettyId(destJetty);
      if (originJettyId == null || destinationJettyId == null) {
        return const OperationFailure(
          'Jetty error',
          'Canonical jetty ID is required for booking creation.',
        );
      }

      final paymentAttemptId = _buildPaymentAttemptId(
        userId: userId,
        origin: origin,
        destination: destination,
        adultCount: adultCount,
        childCount: childCount,
        amount: _fareBreakdown!.total,
      );
      final idempotencyKey = _buildIdempotencyKey(
        userId: userId,
        origin: origin,
        destination: destination,
        adultCount: adultCount,
        childCount: childCount,
        amount: _fareBreakdown!.total,
        paymentAttemptId: paymentAttemptId,
      );
      final orderNumber = await _reserveUniqueOrderNumber(
        userId: userId,
        idempotencyKey: idempotencyKey,
      );

      final paymentResult = await _paymentGateway.charge(
        PaymentGatewayRequest(
          userId: userId,
          amount: _fareBreakdown!.total,
          currency: 'MYR',
          orderNumber: orderNumber,
          payerName: user?.name.trim().isNotEmpty == true
              ? user!.name
              : 'Passenger',
          payerEmail: user?.email.trim().isNotEmpty == true
              ? user!.email
              : 'passenger+$userId@water-taxi.local',
          payerTelephoneNumber: user?.phoneNumber,
          paymentMethod: _gatewayPaymentMethod,
          idempotencyKey: idempotencyKey,
          description:
              'Water taxi $origin to $destination for ${adultCount + childCount} passenger(s)',
        ),
      );

      if (paymentResult.status != PaymentGatewayStatus.authorized &&
          paymentResult.status != PaymentGatewayStatus.success) {
        if (paymentResult.status == PaymentGatewayStatus.cancelled) {
          return const OperationFailure(
            'Payment cancelled',
            'Payment was cancelled. No booking was created.',
            isInfo: true,
          );
        }

        return OperationFailure(
          'Payment failed',
          paymentResult.errorMessage ??
              'The payment gateway declined the transaction.',
        );
      }

      final bookingId = await _bookingRepo.createBooking(
        BookingCreationParams(
          userId: userId,
          userName: user?.name ?? 'Passenger',
          userPhone: user?.phoneNumber ?? '',
          origin: origin,
          destination: destination,
          originJettyId: originJettyId,
          destinationJettyId: destinationJettyId,
          originLat: originJetty.lat,
          originLng: originJetty.lng,
          destinationLat: destJetty.lat,
          destinationLng: destJetty.lng,
          adultCount: adultCount,
          childCount: childCount,
          totalFare: _fareBreakdown!.total,
          paymentMethod: _gatewayPaymentMethod,
          fareSnapshotId: _fareSnapshotId!,
          orderNumber: orderNumber,
          transactionId: paymentResult.transactionId,
        ),
      );

      return OperationSuccess(bookingId);
    } catch (e) {
      return OperationFailure(
        'Payment failed',
        'Could not complete booking: ${e.toString()}',
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  static String _buildIdempotencyKey({
    required String userId,
    required String origin,
    required String destination,
    required int adultCount,
    required int childCount,
    required double amount,
    required String paymentAttemptId,
  }) {
    final normalizedOrigin = origin.trim().toLowerCase();
    final normalizedDestination = destination.trim().toLowerCase();
    final amountCents = (amount * 100).toStringAsFixed(0);
    return '$userId|$normalizedOrigin|$normalizedDestination|$adultCount|$childCount|$amountCents|$paymentAttemptId';
  }

  static String? _resolveCanonicalJettyId(JettyModel? jetty) {
    if (jetty == null) {
      return null;
    }

    final normalized = jetty.jettyId.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String _buildPaymentAttemptId({
    required String userId,
    required String origin,
    required String destination,
    required int adultCount,
    required int childCount,
    required double amount,
  }) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final base =
        '$userId|$origin|$destination|$adultCount|$childCount|${(amount * 100).round()}';
    final fingerprint = base.hashCode.abs();
    return '$now-$fingerprint';
  }

  static String _buildOrderNumber({
    required String userId,
    required String idempotencyKey,
  }) {
    final compactUid = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final compactKey = idempotencyKey.hashCode.abs();
    final last6 = compactUid.length <= 6
        ? compactUid
        : compactUid.substring(compactUid.length - 6);
    return 'WT-$last6-$compactKey';
  }

  Future<String> _reserveUniqueOrderNumber({
    required String userId,
    required String idempotencyKey,
  }) async {
    const maxAttempts = 5;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final attemptKey = attempt == 0
          ? idempotencyKey
          : '$idempotencyKey#$attempt';
      final candidate = _buildOrderNumber(
        userId: userId,
        idempotencyKey: attemptKey,
      );

      try {
        await _bookingRepo.reserveOrderNumber(
          orderNumber: candidate,
          userId: userId,
        );
        return candidate;
      } on StateError {
        if (attempt == maxAttempts - 1) {
          rethrow;
        }
      }
    }

    throw StateError('Unable to reserve a unique order number.');
  }

  /// Captures a held payment (call after ride completion)
  Future<OperationResult> capturePayment({
    required String paymentIntentId,
    required String orderNumber,
  }) async {
    try {
      final result = await _paymentGateway.capturePayment(
        paymentIntentId: paymentIntentId,
        orderNumber: orderNumber,
      );

      if (result.isSuccess) {
        return const OperationSuccess('Payment captured successfully');
      }

      return OperationFailure(
        'Capture failed',
        result.errorMessage ?? 'Could not capture payment.',
      );
    } catch (e) {
      return OperationFailure(
        'Capture error',
        'Error capturing payment: ${e.toString()}',
      );
    }
  }

  /// Cancels a held payment (call if ride is cancelled)
  Future<OperationResult> cancelPayment({
    required String paymentIntentId,
    required String orderNumber,
    String reason = 'requested_by_customer',
  }) async {
    try {
      final result = await _paymentGateway.cancelPayment(
        paymentIntentId: paymentIntentId,
        orderNumber: orderNumber,
        reason: reason,
      );

      if (result.status == PaymentGatewayStatus.cancelled) {
        return const OperationSuccess('Payment cancelled, funds released');
      }

      return OperationFailure(
        'Cancellation failed',
        result.errorMessage ?? 'Could not cancel payment.',
      );
    } catch (e) {
      return OperationFailure(
        'Cancellation error',
        'Error cancelling payment: ${e.toString()}',
      );
    }
  }
}
