import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/fare_repository.dart';
import 'package:passenger_app/data/repositories/jetty_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';

/// ViewModel for [HomeScreen].
///
/// Owns user data loading, jetty list, fare validation, and the real-time
/// active-booking stream that prevents double-booking.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required UserRepository userRepo,
    required JettyRepository jettyRepo,
    required FareRepository fareRepo,
    required BookingRepository bookingRepo,
  })  : _userRepo = userRepo,
        _jettyRepo = jettyRepo,
        _fareRepo = fareRepo,
        _bookingRepo = bookingRepo;

  final UserRepository _userRepo;
  final JettyRepository _jettyRepo;
  final FareRepository _fareRepo;
  final BookingRepository _bookingRepo;

  // ── State ────────────────────────────────────────────────────────────────

  String _userName = 'Passenger';
  List<JettyModel> _jetties = [];
  bool _isLoadingJetties = true;
  String? _jettyError;

  String? _selectedOrigin;
  String? _selectedDestination;
  int _adultCount = 1;
  int _childCount = 0;

  bool _isCheckingFare = false;

  BookingModel? _activeBooking;
  StreamSubscription<BookingModel?>? _activeBookingSubscription;

  // ── Getters ──────────────────────────────────────────────────────────────

  String get userName => _userName;
  List<JettyModel> get jetties => _jetties;
  bool get isLoadingJetties => _isLoadingJetties;
  String? get jettyError => _jettyError;

  String? get selectedOrigin => _selectedOrigin;
  String? get selectedDestination => _selectedDestination;
  int get adultCount => _adultCount;
  int get childCount => _childCount;

  bool get isCheckingFare => _isCheckingFare;
  BookingModel? get activeBooking => _activeBooking;

  bool get hasValidPassengerCount => (_adultCount + _childCount) > 0;

  bool get isRouteReady =>
      _selectedOrigin != null &&
      _selectedDestination != null &&
      _selectedOrigin != _selectedDestination;

  bool get canBook => isRouteReady && hasValidPassengerCount;

  // ── Initialise ───────────────────────────────────────────────────────────

  Future<void> init(String userId) async {
    await Future.wait([
      _loadUserName(userId),
      _loadJetties(),
    ]);
    _subscribeToActiveBooking(userId);
  }

  // ── User actions ─────────────────────────────────────────────────────────

  /// Sets the selected pickup jetty. Clears destination if it matches.
  void selectOrigin(String origin) {
    final destinationWasReset = _selectedDestination == origin;
    _selectedOrigin = origin;
    if (destinationWasReset) _selectedDestination = null;
    notifyListeners();
  }

  void selectDestination(String destination) {
    _selectedDestination = destination;
    notifyListeners();
  }

  void setAdultCount(int count) {
    _adultCount = count.clamp(0, 10);
    notifyListeners();
  }

  void setChildCount(int count) {
    _childCount = count.clamp(0, 10);
    notifyListeners();
  }

  /// Returns the [FareModel] for the selected route, or `null` if not found.
  Future<FareModel?> getFareForSelectedRoute() async {
    if (_selectedOrigin == null || _selectedDestination == null) return null;
    _isCheckingFare = true;
    notifyListeners();

    try {
      return await _fareRepo.getFare(_selectedOrigin!, _selectedDestination!);
    } finally {
      _isCheckingFare = false;
      notifyListeners();
    }
  }

  /// Returns `true` if at least one operator is currently online.
  Future<bool> hasOnlineOperators() {
    return _bookingRepo.hasOnlineOperators();
  }

  // ── Private ──────────────────────────────────────────────────────────────

  Future<void> _loadUserName(String userId) async {
    try {
      final user = await _userRepo
          .getUser(userId)
          .timeout(const Duration(seconds: 10));
      _userName = user?.name ?? 'Passenger';
    } catch (_) {
      _userName = 'Passenger';
    }
    notifyListeners();
  }

  Future<void> _loadJetties() async {
    try {
      _jetties = await _jettyRepo
          .getAllJetties()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      _jettyError = 'Failed to load jetties';
    } finally {
      _isLoadingJetties = false;
      notifyListeners();
    }
  }

  void _subscribeToActiveBooking(String userId) {
    _activeBookingSubscription?.cancel();
    _activeBookingSubscription =
        _bookingRepo.streamUserActiveBooking(userId).listen((booking) {
      _activeBooking = booking;
      notifyListeners();
    }, onError: (_) {
      _activeBooking = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _activeBookingSubscription?.cancel();
    super.dispose();
  }
}
