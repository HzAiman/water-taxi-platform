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
  })  : _fareRepo = fareRepo,
        _jettyRepo = jettyRepo,
        _userRepo = userRepo,
        _bookingRepo = bookingRepo,
        _paymentGateway = paymentGateway;

  final FareRepository _fareRepo;
  final JettyRepository _jettyRepo;
  final UserRepository _userRepo;
  final BookingRepository _bookingRepo;
  final PaymentGatewayService _paymentGateway;
  static const String _gatewayPaymentMethod = 'bayarcash_payment_intent';

  // ── State ────────────────────────────────────────────────────────────────

  bool _isLoadingFare = true;
  FareBreakdown? _fareBreakdown;
  String? _fareError;
  bool _isLoadingBanks = false;
  String? _bankError;
  List<PaymentBankOption> _availableBanks = const [];
  PaymentBankOption? _selectedBank;

  bool _isProcessing = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isLoadingFare => _isLoadingFare;
  FareBreakdown? get fareBreakdown => _fareBreakdown;
  String? get fareError => _fareError;
  bool get isLoadingBanks => _isLoadingBanks;
  String? get bankError => _bankError;
  List<PaymentBankOption> get availableBanks => _availableBanks;
  PaymentBankOption? get selectedBank => _selectedBank;
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
    notifyListeners();

    try {
      final fare = await _fareRepo.getFare(origin, destination);
      if (fare == null) {
        _fareError = 'Fare not found for this route';
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

      await _loadBanks();
    } catch (_) {
      _fareError = 'Failed to load fare information';
    } finally {
      _isLoadingFare = false;
      notifyListeners();
    }
  }

  void selectBank(PaymentBankOption? bank) {
    _selectedBank = bank;
    notifyListeners();
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
            'Jetty error', 'Jetty "$destination" not found.');
      }

      final paymentResult = await _paymentGateway.charge(
        PaymentGatewayRequest(
          userId: userId,
          amount: _fareBreakdown!.total,
          currency: 'MYR',
          orderNumber: _buildOrderNumber(
            userId: userId,
            idempotencyKey: _buildIdempotencyKey(
              userId: userId,
              origin: origin,
              destination: destination,
              adultCount: adultCount,
              childCount: childCount,
            ),
          ),
          payerName: user?.name.trim().isNotEmpty == true
              ? user!.name
              : 'Passenger',
          payerEmail: user?.email.trim().isNotEmpty == true
              ? user!.email
              : 'passenger+$userId@water-taxi.local',
          payerTelephoneNumber: user?.phoneNumber,
            payerBankCode: _selectedBank?.code,
            payerBankName: _selectedBank?.name,
          paymentMethod: _gatewayPaymentMethod,
          idempotencyKey: _buildIdempotencyKey(
            userId: userId,
            origin: origin,
            destination: destination,
            adultCount: adultCount,
            childCount: childCount,
          ),
          description:
              'Water taxi $origin to $destination for ${adultCount + childCount} passenger(s)',
        ),
      );

      if (!paymentResult.isSuccess) {
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
          originLat: originJetty.lat,
          originLng: originJetty.lng,
          destinationLat: destJetty.lat,
          destinationLng: destJetty.lng,
          adultCount: adultCount,
          childCount: childCount,
          adultFare: _fareBreakdown!.adultFarePerPerson,
          childFare: _fareBreakdown!.childFarePerPerson,
          paymentMethod: _gatewayPaymentMethod,
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

  Future<void> _loadBanks() async {
    _isLoadingBanks = true;
    _bankError = null;
    notifyListeners();

    try {
      final banks = await _paymentGateway.fetchDobwBanks();
      _availableBanks = banks;
      if (_selectedBank != null &&
          !_availableBanks.any((b) => b.code == _selectedBank!.code)) {
        _selectedBank = null;
      }
    } catch (_) {
      _bankError = 'Unable to load bank list. You can continue without preselecting.';
      _availableBanks = const [];
      _selectedBank = null;
    } finally {
      _isLoadingBanks = false;
      notifyListeners();
    }
  }

  static String _buildIdempotencyKey({
    required String userId,
    required String origin,
    required String destination,
    required int adultCount,
    required int childCount,
  }) {
    final normalizedOrigin = origin.trim().toLowerCase();
    final normalizedDestination = destination.trim().toLowerCase();
    return '$userId|$normalizedOrigin|$normalizedDestination|$adultCount|$childCount';
  }

  static String _buildOrderNumber({
    required String userId,
    required String idempotencyKey,
  }) {
    final compactUid = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final compactKey = idempotencyKey.hashCode.abs();
    return 'WT-${compactUid.takeLast(6)}-$compactKey';
  }
}

extension on String {
  String takeLast(int count) {
    if (length <= count) return this;
    return substring(length - count);
  }
}
