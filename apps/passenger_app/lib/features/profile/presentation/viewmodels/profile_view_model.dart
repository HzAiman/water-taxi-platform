import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';

/// ViewModel for [ProfileScreen] and its sub-routes.
///
/// Owns user profile loading/editing and booking history streaming.
class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({
    required UserRepository userRepo,
    required BookingRepository bookingRepo,
  })  : _userRepo = userRepo,
        _bookingRepo = bookingRepo;

  final UserRepository _userRepo;
  final BookingRepository _bookingRepo;

  // ── State ────────────────────────────────────────────────────────────────

  UserModel? _user;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isHistoryLoading = false;
  String? _historyError;
  String? _lastHistoryUserId;

  List<BookingModel> _bookingHistory = [];
  StreamSubscription<List<BookingModel>>? _historySubscription;

  // ── Getters ──────────────────────────────────────────────────────────────

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isHistoryLoading => _isHistoryLoading;
  String? get historyError => _historyError;
  List<BookingModel> get bookingHistory => _bookingHistory;

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> loadProfile(String uid) async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await _userRepo.getUser(uid);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void startBookingHistoryStream(String userId) {
    _lastHistoryUserId = userId;
    _historySubscription?.cancel();
    _isHistoryLoading = true;
    _historyError = null;
    notifyListeners();

    _historySubscription =
        _bookingRepo.streamUserBookingHistory(userId).listen((bookings) {
      _bookingHistory = bookings;
      _isHistoryLoading = false;
      _historyError = null;
      notifyListeners();
    }, onError: (Object error, StackTrace stackTrace) {
      _isHistoryLoading = false;
      _historyError =
          'Unable to load booking history. Please check your connection and retry.';
      notifyListeners();
    });
  }

  void retryBookingHistoryStream() {
    final userId = _lastHistoryUserId;
    if (userId == null || userId.isEmpty) {
      return;
    }
    startBookingHistoryStream(userId);
  }

  void stopBookingHistoryStream() {
    _historySubscription?.cancel();
    _historySubscription = null;
  }

  Future<OperationResult> updateProfile({
    required String uid,
    required String name,
    required String email,
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      await _userRepo.updateUser(uid, name: name, email: email);
      _user = _user?.copyWith(name: name, email: email);
      return const OperationSuccess('Profile updated successfully.');
    } catch (e) {
      return OperationFailure(
        'Update failed',
        'Failed to update profile: ${e.toString()}',
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<OperationResult> deleteAccount(String uid) async {
    _isSaving = true;
    notifyListeners();

    try {
      await _userRepo.deleteUser(uid);
      return const OperationSuccess('Account deleted.');
    } catch (e) {
      return OperationFailure(
        'Delete failed',
        'Error deleting account: ${e.toString()}',
      );
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    super.dispose();
  }
}
