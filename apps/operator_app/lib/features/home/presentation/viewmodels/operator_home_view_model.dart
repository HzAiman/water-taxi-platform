import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
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
  StreamSubscription<Position>? _locationSubscription;

  String? _operatorId;
  String? _lastCancelledNoticeBookingId;
  String? _trackingBookingId;
  DateTime? _lastLocationPublishAt;
  Position? _lastPublishedPosition;
  bool _isPublishingLocation = false;

  static const Duration _locationPublishMinInterval = Duration(seconds: 6);
  static const double _locationPublishMinDistanceMeters = 20;

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
    try {
      final op = await _operatorRepo
          .getOperator(operatorId)
          .timeout(const Duration(seconds: 10));
      if (op != null) {
        _isOnline = op.isOnline;
        await _operatorRepo
            .syncPresence(operatorId, isOnline: op.isOnline)
            .timeout(const Duration(seconds: 8));
        notifyListeners();
      }
    } catch (_) {
      // Keep UI responsive even if initial profile/presence fetch stalls.
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
        _stopLocationSharing();
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
      actionName: 'accept_booking',
      bookingId: bookingId,
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
      actionName: 'reject_booking',
      bookingId: bookingId,
    );
  }

  Future<OperationResult> releaseBooking(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    final result = await _withBusy(
      () => _bookingRepo.releaseBooking(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
      actionName: 'release_booking',
      bookingId: bookingId,
    );

    if (result is OperationSuccess && _trackingBookingId == bookingId) {
      _stopLocationSharing();
    }

    return result;
  }

  Future<OperationResult> startTrip(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    final initial = await _currentPositionOrNull();

    final result = await _withBusy(
      () => _bookingRepo.startTrip(
        bookingId: bookingId,
        operatorId: operatorId,
        operatorLat: initial?.latitude,
        operatorLng: initial?.longitude,
      ),
      actionName: 'start_trip',
      bookingId: bookingId,
    );

    if (result is OperationSuccess) {
      await _startLocationSharing(bookingId, operatorId, initial: initial);
    }

    return result;
  }

  Future<OperationResult> completeTrip(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    final result = await _withBusy(
      () => _bookingRepo.completeTrip(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
      actionName: 'complete_trip',
      bookingId: bookingId,
    );

    if (result is OperationSuccess && _trackingBookingId == bookingId) {
      _stopLocationSharing();
    }

    return result;
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
    _stopStreams();

    _activeSubscription =
        _bookingRepo.streamActiveBookings(operatorId).listen((list) {
      _activeBookings = list;

      if (_trackingBookingId != null) {
        final tracked = list.where((b) => b.bookingId == _trackingBookingId);
        final stillOnTheWay = tracked.any(
          (b) => b.status == BookingStatus.onTheWay,
        );
        if (!stillOnTheWay) {
          _stopLocationSharing();
        }
      }

      // Detect passenger cancellations for bookings previously in our active list.
      // We can't easily detect this here since we only get the filtered list.
      // The widget layer checks for cancelled bookings via the raw stream.
      notifyListeners();
    }, onError: (_) {
      _activeBookings = [];
      notifyListeners();
    });

    _pendingSubscription =
        _bookingRepo.streamPendingBookings().listen((list) {
      _pendingBookings = list;
      notifyListeners();
    }, onError: (_) {
      _pendingBookings = [];
      notifyListeners();
    });
  }

  void _stopStreams() {
    _activeSubscription?.cancel();
    _pendingSubscription?.cancel();
    _stopLocationSharing();
    _activeBookings = [];
    _pendingBookings = [];
  }

  Future<void> _startLocationSharing(
    String bookingId,
    String operatorId, {
    Position? initial,
  }) async {
    _stopLocationSharing();
    _trackingBookingId = bookingId;

    if (!_isOnline) {
      return;
    }

    if (initial != null) {
      await _publishOperatorPosition(
        bookingId,
        operatorId,
        initial,
        force: true,
      );
    }

    final canTrack = await _canUseLocation();
    if (!canTrack || _trackingBookingId != bookingId) {
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        if (_trackingBookingId == null) return;
        unawaited(
          _publishOperatorPosition(
            _trackingBookingId!,
            operatorId,
            position,
          ),
        );
      },
      onError: (_) {
        _stopLocationSharing();
      },
    );
  }

  void _stopLocationSharing() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _trackingBookingId = null;
    _lastLocationPublishAt = null;
    _lastPublishedPosition = null;
    _isPublishingLocation = false;
  }

  Future<bool> _canUseLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<Position?> _currentPositionOrNull() async {
    final canUseLocation = await _canUseLocation();
    if (!canUseLocation) return null;
    try {
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  Future<void> _publishOperatorPosition(
    String bookingId,
    String operatorId,
    Position position, {
    bool force = false,
  }) async {
    if (_isPublishingLocation) return;

    if (!force && !_shouldPublishPosition(position)) {
      return;
    }

    _isPublishingLocation = true;
    try {
      final result = await _bookingRepo.updateOperatorLocation(
        bookingId: bookingId,
        operatorId: operatorId,
        operatorLat: position.latitude,
        operatorLng: position.longitude,
      );

      if (result is OperationSuccess) {
        _lastLocationPublishAt = DateTime.now();
        _lastPublishedPosition = position;
      }
    } finally {
      _isPublishingLocation = false;
    }
  }

  bool _shouldPublishPosition(Position current) {
    final lastAt = _lastLocationPublishAt;
    final lastPos = _lastPublishedPosition;

    return shouldPublishOperatorPosition(
      now: DateTime.now(),
      minInterval: _locationPublishMinInterval,
      minDistanceMeters: _locationPublishMinDistanceMeters,
      currentLat: current.latitude,
      currentLng: current.longitude,
      lastPublishedAt: lastAt,
      lastLat: lastPos?.latitude,
      lastLng: lastPos?.longitude,
    );
  }

  Future<OperationResult> _withBusy(
    Future<OperationResult> Function() action, {
    required String actionName,
    String? bookingId,
  }) async {
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
      final result = await action();
      return _normaliseAndLog(
        result,
        actionName: actionName,
        bookingId: bookingId,
      );
    } finally {
      _isUpdatingBooking = false;
      notifyListeners();
    }
  }

  OperationResult _normaliseAndLog(
    OperationResult result, {
    required String actionName,
    String? bookingId,
  }) {
    if (result case OperationFailure(:final title, :final message, :final isInfo)) {
      if (_isPermissionDenied(message)) {
        final friendly = OperationFailure(
          'Permission denied',
          'You no longer have permission to perform this action. Refresh, then sign in again if needed.',
          isInfo: false,
        );
        _logFailure(
          actionName,
          friendly,
          bookingId: bookingId,
          rawTitle: title,
          rawMessage: message,
        );
        return friendly;
      }

      final originalFailure = OperationFailure(
        title,
        message,
        isInfo: isInfo,
      );

      _logFailure(
        actionName,
        originalFailure,
        bookingId: bookingId,
      );
      return originalFailure;
    }
    return result;
  }

  bool _isPermissionDenied(String message) {
    final text = message.toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('insufficient permissions');
  }

  void _logFailure(
    String actionName,
    OperationFailure failure, {
    String? bookingId,
    String? rawTitle,
    String? rawMessage,
  }) {
    debugPrint(
      '[operator_action_failure] action=$actionName operatorId=${_operatorId ?? 'unknown'} bookingId=${bookingId ?? 'n/a'} title=${failure.title} message=${failure.message} rawTitle=${rawTitle ?? '-'} rawMessage=${rawMessage ?? '-'}',
    );
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

/// Decides whether a new operator location should be published.
bool shouldPublishOperatorPosition({
  required DateTime now,
  required Duration minInterval,
  required double minDistanceMeters,
  required double currentLat,
  required double currentLng,
  required DateTime? lastPublishedAt,
  required double? lastLat,
  required double? lastLng,
}) {
  if (lastPublishedAt == null || lastLat == null || lastLng == null) {
    return true;
  }

  final elapsed = now.difference(lastPublishedAt);
  final moved = Geolocator.distanceBetween(
    lastLat,
    lastLng,
    currentLat,
    currentLng,
  );

  return elapsed >= minInterval || moved >= minDistanceMeters;
}
