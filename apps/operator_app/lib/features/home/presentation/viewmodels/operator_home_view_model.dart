import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';

/// ViewModel for [OperatorHomeScreen].
///
/// Manages the two real-time booking streams (active + pending queue),
/// exposes all booking lifecycle actions (accept / reject / release /
/// start / complete), and handles the online/offline toggle.
class OperatorHomeViewModel extends ChangeNotifier {
  OperatorHomeViewModel({
    required BookingRepository bookingRepo,
    required OperatorRepository operatorRepo,
  })  : _bookingRepo = bookingRepo,
        _operatorRepo = operatorRepo;

  final BookingRepository _bookingRepo;
  final OperatorRepository _operatorRepo;

  // ── State ────────────────────────────────────────────────────────────────

  bool _isOnline = false;
  bool _isToggling = false;
  bool _isUpdatingBooking = false;
  bool _isRefreshing = false;
  int _streamVersion = 0; // bumped on manual refresh to force stream rebuild

  List<BookingModel> _activeBookings = [];
  List<BookingModel> _pendingBookings = [];

  StreamSubscription<List<BookingModel>>? _activeSubscription;
  StreamSubscription<List<BookingModel>>? _pendingSubscription;

  String? _operatorId;
  String? _lastCancelledNoticeBookingId;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isOnline => _isOnline;
  bool get isToggling => _isToggling;
  bool get isUpdatingBooking => _isUpdatingBooking;
  bool get isRefreshing => _isRefreshing;
  int get streamVersion => _streamVersion;

  List<BookingModel> get activeBookings => _activeBookings;

  /// Pending bookings visible to this operator (not already rejected by them).
  List<BookingModel> visiblePendingBookings(String operatorId) =>
      _pendingBookings
          .where((b) => !b.rejectedBy.contains(operatorId))
          .toList();

  String? get lastCancelledNoticeBookingId => _lastCancelledNoticeBookingId;

  // ── Initialise ───────────────────────────────────────────────────────────

  /// Call once when the home screen mounts, passing the current operator's uid.
  Future<void> initialize(String operatorId) async {
    _operatorId = operatorId;

    // Resolve current online status from Firestore.
    final op = await _operatorRepo.getOperator(operatorId);
    if (op != null) {
      _isOnline = op.isOnline;
      notifyListeners();
    }

    _startStreams(operatorId);
  }

  // ── Online / Offline ─────────────────────────────────────────────────────

  Future<OperationResult> toggleOnlineStatus() async {
    final operatorId = _operatorId;
    if (operatorId == null) {
      return const OperationFailure('Not initialised', 'No operator ID available.');
    }

    final nextStatus = !_isOnline;
    _isToggling = true;
    _isOnline = nextStatus; // optimistic update
    notifyListeners();

    try {
      int releasedCount = 0;
      if (!nextStatus) {
        releasedCount =
            await _bookingRepo.releaseAllAcceptedBookings(operatorId);
      }

      await _operatorRepo
          .setOnlineStatus(operatorId, isOnline: nextStatus)
          .timeout(const Duration(seconds: 6));

      if (nextStatus) {
        return const OperationSuccess('You are now online.');
      }
      if (releasedCount > 0) {
        return OperationSuccess(
          '$releasedCount accepted booking${releasedCount == 1 ? '' : 's'} released. You are now offline.',
        );
      }
      return const OperationSuccess('You are now offline.');
    } on TimeoutException {
      _isOnline = !nextStatus; // revert
      return const OperationFailure(
        'Timeout',
        'Updating status timed out. Check your network.',
      );
    } catch (e) {
      _isOnline = !nextStatus; // revert
      return OperationFailure('Status update failed', e.toString());
    } finally {
      _isToggling = false;
      notifyListeners();
    }
  }

  // ── Booking actions ──────────────────────────────────────────────────────

  Future<OperationResult> acceptBooking(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    return _withBusy(
      () => _bookingRepo.acceptBooking(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
    );
  }

  Future<OperationResult> rejectBooking(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    return _withBusy(
      () => _bookingRepo.rejectBooking(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
    );
  }

  Future<OperationResult> releaseBooking(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    return _withBusy(
      () => _bookingRepo.releaseBooking(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
    );
  }

  Future<OperationResult> startTrip(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    return _withBusy(
      () => _bookingRepo.startTrip(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
    );
  }

  Future<OperationResult> completeTrip(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    return _withBusy(
      () => _bookingRepo.completeTrip(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
    );
  }

  // ── Refresh ──────────────────────────────────────────────────────────────

  Future<void> refresh(String operatorId) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    try {
      _stopStreams();
      _streamVersion += 1;
      _startStreams(operatorId);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  // ── Cancellation notice ──────────────────────────────────────────────────

  /// Records that the cancellation notice for [bookingId] was shown, so it
  /// isn't shown again on the next stream event.
  void markCancellationNoticeShown(String bookingId) {
    _lastCancelledNoticeBookingId = bookingId;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _startStreams(String operatorId) {
    _activeSubscription =
        _bookingRepo.streamActiveBookings(operatorId).listen((list) {
      _activeBookings = list;

      // Detect passenger cancellations for bookings previously in our active list.
      // We can't easily detect this here since we only get the filtered list.
      // The widget layer checks for cancelled bookings via the raw stream.
      notifyListeners();
    });

    _pendingSubscription =
        _bookingRepo.streamPendingBookings().listen((list) {
      _pendingBookings = list;
      notifyListeners();
    });
  }

  void _stopStreams() {
    _activeSubscription?.cancel();
    _pendingSubscription?.cancel();
    _activeBookings = [];
    _pendingBookings = [];
  }

  Future<OperationResult> _withBusy(
    Future<OperationResult> Function() action,
  ) async {
    if (_isUpdatingBooking) {
      return const OperationFailure(
        'Busy',
        'Another operation is in progress.',
        isInfo: true,
      );
    }
    _isUpdatingBooking = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _isUpdatingBooking = false;
      notifyListeners();
    }
  }

  static const OperationResult _notInitialised = OperationFailure(
    'Not initialised',
    'Operator ID is not available.',
  );

  @override
  void dispose() {
    _stopStreams();
    super.dispose();
  }
}

// ── Stale booking helper (used by widget layer) ──────────────────────────────

/// Returns `true` if an accepted booking has been sitting for more than
/// [_staleThreshold] without being started.
bool isAcceptedBookingStale(
  BookingModel booking, {
  Duration threshold = const Duration(minutes: 5),
}) {
  if (booking.status != BookingStatus.accepted) return false;
  final updatedAt = booking.updatedAt;
  if (updatedAt == null) return false;
  return DateTime.now().difference(updatedAt) >= threshold;
}

/// Formats a [DateTime] as `DD/MM/YYYY HH:mm`, or `'Unknown'` if null.
String formatBookingTimestamp(DateTime? dt) {
  if (dt == null) return 'Unknown';
  final local = dt.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

/// Formats a fare value as `RM X.XX`.
String formatCurrency(double value) => 'RM ${value.toStringAsFixed(2)}';

/// Capitalises each word in a snake_case or kebab-case status string.
String formatStatusLabel(String status) {
  return status
      .split(RegExp(r'[_\s-]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

extension OperatorAuthHelper on FirebaseAuth {
  String? get operatorId => currentUser?.uid;
}
