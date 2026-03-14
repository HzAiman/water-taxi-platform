import 'package:flutter/foundation.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/fare_repository.dart';
import 'package:passenger_app/data/repositories/jetty_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';

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
  })  : _fareRepo = fareRepo,
        _jettyRepo = jettyRepo,
        _userRepo = userRepo,
        _bookingRepo = bookingRepo;

  final FareRepository _fareRepo;
  final JettyRepository _jettyRepo;
  final UserRepository _userRepo;
  final BookingRepository _bookingRepo;

  // ── State ────────────────────────────────────────────────────────────────

  bool _isLoadingFare = true;
  FareBreakdown? _fareBreakdown;
  String? _fareError;

  String? _selectedPaymentMethod;
  bool _isProcessing = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isLoadingFare => _isLoadingFare;
  FareBreakdown? get fareBreakdown => _fareBreakdown;
  String? get fareError => _fareError;
  String? get selectedPaymentMethod => _selectedPaymentMethod;
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
    } catch (_) {
      _fareError = 'Failed to load fare information';
    } finally {
      _isLoadingFare = false;
      notifyListeners();
    }
  }

  void selectPaymentMethod(String method) {
    _selectedPaymentMethod = method;
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
    if (_selectedPaymentMethod == null) {
      return const OperationFailure(
        'Payment method required',
        'Please select a payment method.',
        isInfo: true,
      );
    }
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
          paymentMethod: _selectedPaymentMethod!,
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
}
