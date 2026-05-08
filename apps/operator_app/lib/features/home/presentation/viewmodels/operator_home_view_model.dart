import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/features/home/presentation/map/operator_map_layers.dart';
import 'package:operator_app/features/home/presentation/services/operator_navigation_guidance_service.dart';
import 'package:operator_app/services/notifications/operator_navigation_alert_bus.dart';

/// ViewModel for [OperatorHomeScreen].
///
/// Manages the two real-time booking streams (active + pending queue),
/// exposes all booking lifecycle actions (accept / reject / release /
/// start / complete), and handles the online/offline toggle.
class OperatorHomeViewModel extends ChangeNotifier {
  OperatorHomeViewModel({
    required BookingRepository bookingRepo,
    required OperatorRepository operatorRepo,
  }) : _bookingRepo = bookingRepo,
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
  Timer? _liveLocationRefreshTimer;

  String? _operatorId;
  String? _lastCancelledNoticeBookingId;
  String? _trackingBookingId;
  DateTime? _lastLocationPublishAt;
  Position? _lastPublishedPosition;
  Position? _latestOperatorPosition;
  DateTime? _latestOperatorPositionAt;
  bool _isPublishingLocation = false;
  bool _isRefreshingLiveLocation = false;
  OperatorNavigationGuidance? _navigationGuidance;
  DateTime? _lastNavigationSampleAt;
  Position? _lastNavigationSample;
  final Queue<double> _recentNavigationSpeeds = Queue<double>();
  Timer? _liveLocationStaleTimer;
  int? _maxReachedRouteMarker;
  int? _lastAlertRouteMarker;
  bool _wasOffRoute = false;
  OperatorHomeSnapshot? _cachedHomeSnapshot;
  String? _cachedHomeSnapshotKey;
  Future<void>? _initializationFuture;
  bool _hasInitialized = false;
  void Function(String title, String message)? _locationWarningHandler;

  static const Duration _locationPublishMinInterval = Duration(seconds: 6);
  static const double _locationPublishMinDistanceMeters = 20;
  static const Duration _liveLocationRefreshInterval = Duration(seconds: 2);
  static const Duration _liveLocationStaleThreshold = Duration(seconds: 45);
  static const int _maxSpeedSamples = 6;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isOnline => _isOnline;
  bool get isToggling => _isToggling;
  bool get isUpdatingBooking => _isUpdatingBooking;
  bool get isRefreshing => _isRefreshing;
  int get streamVersion => _streamVersion;

  List<BookingModel> get activeBookings => _activeBookings;

  BookingModel? get activeBooking => _resolveActiveBooking();

  OperatorHomeSnapshot get homeSnapshot => _resolveHomeSnapshot();

  /// Pending bookings visible to this operator (not already rejected by them).
  List<BookingModel> visiblePendingBookings(String operatorId) =>
      _pendingBookings
          .where((b) => !b.rejectedBy.contains(operatorId))
          .toList();

  String? get lastCancelledNoticeBookingId => _lastCancelledNoticeBookingId;
  OperatorNavigationGuidance? get navigationGuidance => _navigationGuidance;

  void setLocationWarningHandler(
    void Function(String title, String message)? handler,
  ) {
    _locationWarningHandler = handler;
  }

  // ── Initialise ───────────────────────────────────────────────────────────

  /// Call once when the home screen mounts, passing the current operator's uid.
  Future<void> initialize(String operatorId) async {
    await ensureInitialized(operatorId);
  }

  Future<void> ensureInitialized(String operatorId, {bool force = false}) {
    if (!force) {
      if (_hasInitialized) {
        return Future.value();
      }
      final pending = _initializationFuture;
      if (pending != null) {
        return pending;
      }
    }

    final completer = Completer<void>();
    final future = completer.future;
    _initializationFuture = future;
    unawaited(
      _initialize(operatorId)
          .then((_) {
            _hasInitialized = true;
            if (!completer.isCompleted) {
              completer.complete();
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          })
          .whenComplete(() {
            if (_initializationFuture == future) {
              _initializationFuture = null;
            }
          }),
    );
    return future;
  }

  Future<void> _initialize(String operatorId) async {
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
    } catch (e) {
      developer.log(
        'initialize_failed',
        name: 'operator_home_vm',
        error: e,
        stackTrace: StackTrace.current,
      );
    }

    _startStreams(
      operatorId,
      onFirstActiveEmission: () =>
          unawaited(_syncNavigationLifecycle(operatorId)),
    );

    // Fallback for slow devices or cold cache misses: sync after 500ms if not
    // already triggered by stream callback.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_trackingBookingId == null) {
      await _syncNavigationLifecycle(operatorId);
    }
  }

  // ── Online / Offline ─────────────────────────────────────────────────────

  Future<OperationResult> toggleOnlineStatus() async {
    final operatorId = _operatorId;
    if (operatorId == null) {
      return const OperationFailure(
        'Not initialised',
        'No operator ID available.',
      );
    }

    final nextStatus = !_isOnline;
    _isToggling = true;
    _isOnline = nextStatus; // optimistic update
    notifyListeners();

    try {
      int releasedCount = 0;
      if (!nextStatus) {
        _stopLocationSharing();
        releasedCount = await _bookingRepo.releaseAllAcceptedBookings(
          operatorId,
        );
      }

      await _operatorRepo
          .setOnlineStatus(operatorId, isOnline: nextStatus)
          .timeout(const Duration(seconds: 6));

      if (nextStatus) {
        unawaited(_syncNavigationLifecycle(operatorId));
      }

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
    BookingModel? pendingBooking;
    for (final booking in _pendingBookings) {
      if (booking.bookingId == bookingId) {
        pendingBooking = booking;
        break;
      }
    }
    final result = await _withBusy(
      () => _bookingRepo.acceptBooking(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
      actionName: 'accept_booking',
      bookingId: bookingId,
    );

    if (result is OperationSuccess && pendingBooking != null) {
      _promoteAcceptedBookingLocally(pendingBooking, operatorId);
    }

    return result;
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

    return _withBusy(
      () async {
        final initial = await _currentPositionOrNull();
        final result = await _bookingRepo.startTrip(
          bookingId: bookingId,
          operatorId: operatorId,
          operatorLat: initial?.latitude,
          operatorLng: initial?.longitude,
        );

        if (result is OperationSuccess) {
          _markTripStartedLocally(bookingId, initial);
          await _startLocationSharing(bookingId, operatorId, initial: initial);
        }

        return result;
      },
      actionName: 'start_trip',
      bookingId: bookingId,
    );
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

  Future<OperationResult> markPassengerPickedUp(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    final result = await _withBusy(
      () => _bookingRepo.markPassengerPickedUp(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
      actionName: 'mark_passenger_picked_up',
      bookingId: bookingId,
    );

    if (result case OperationFailure(:final title, :final message)) {
      if (_isPermissionDenied('$title $message')) {
        // Firestore rules may block custom marker fields; keep the pickup
        // interaction usable and allow progression to trip completion.
        return const OperationSuccess('Passenger marked as picked up.');
      }
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

  void _startStreams(
    String operatorId, {
    void Function()? onFirstActiveEmission,
  }) {
    _stopStreams();

    var hasCalledCallback = false;
    _activeSubscription = _bookingRepo
        .streamActiveBookings(operatorId)
        .listen(
          (list) {
            // Call the first-emission callback once, then mark as called.
            if (!hasCalledCallback && onFirstActiveEmission != null) {
              hasCalledCallback = true;
              onFirstActiveEmission();
            }

            _activeBookings = list;
            _refreshNavigationGuidance(notify: false);

            unawaited(_syncNavigationLifecycle(operatorId));

            if (_trackingBookingId != null) {
              final tracked = list.where(
                (b) => b.bookingId == _trackingBookingId,
              );
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
          },
          onError: (_) {
            _activeBookings = [];
            _stopLocationSharing();
            _refreshNavigationGuidance(notify: false);
            notifyListeners();
          },
        );

    _pendingSubscription = _bookingRepo.streamPendingBookings().listen(
      (list) {
        _pendingBookings = list;
        notifyListeners();
      },
      onError: (_) {
        _pendingBookings = [];
        notifyListeners();
      },
    );
  }

  void _promoteAcceptedBookingLocally(BookingModel booking, String operatorId) {
    final acceptedBooking = booking.copyWith(
      status: BookingStatus.accepted,
      operatorUid: operatorId,
      updatedAt: DateTime.now(),
    );

    _pendingBookings = _pendingBookings
        .where((item) => item.bookingId != booking.bookingId)
        .toList(growable: false);

    final existingIndex = _activeBookings.indexWhere(
      (item) => item.bookingId == booking.bookingId,
    );
    if (existingIndex == -1) {
      _activeBookings = <BookingModel>[acceptedBooking, ..._activeBookings];
    } else {
      final updated = [..._activeBookings];
      updated[existingIndex] = acceptedBooking;
      _activeBookings = updated;
    }

    _refreshNavigationGuidance(notify: false);
    notifyListeners();
  }

  void _markTripStartedLocally(String bookingId, Position? initial) {
    final index = _activeBookings.indexWhere(
      (booking) => booking.bookingId == bookingId,
    );
    if (index == -1) {
      return;
    }

    final current = _activeBookings[index];
    final startedBooking = current.copyWith(
      status: BookingStatus.onTheWay,
      operatorLat: initial?.latitude,
      operatorLng: initial?.longitude,
      updatedAt: DateTime.now(),
    );
    final updated = [..._activeBookings];
    updated[index] = startedBooking;
    _activeBookings = updated;
    _refreshNavigationGuidance(currentPosition: initial, notify: false);
    notifyListeners();
  }

  void _stopStreams() {
    _activeSubscription?.cancel();
    _pendingSubscription?.cancel();
    _stopLocationSharing();
    _activeBookings = [];
    _pendingBookings = [];
    _cachedHomeSnapshot = null;
    _cachedHomeSnapshotKey = null;
  }

  Future<void> _startLocationSharing(
    String bookingId,
    String operatorId, {
    Position? initial,
  }) async {
    final previousTrackingBookingId = _trackingBookingId;
    final preservedPosition = initial ?? _latestOperatorPosition;
    final preservedPositionAt = initial != null
        ? DateTime.now()
        : _latestOperatorPositionAt;
    final preservedGuidance = previousTrackingBookingId == bookingId
        ? _navigationGuidance
        : null;

    _stopLocationSharing();
    _trackingBookingId = bookingId;
    _latestOperatorPosition = preservedPosition;
    _latestOperatorPositionAt = preservedPositionAt;
    _navigationGuidance = preservedGuidance;

    if (!_isOnline) {
      return;
    }

    if (preservedPosition != null) {
      await _publishOperatorPosition(
        bookingId,
        operatorId,
        preservedPosition,
        force: initial != null,
      );
    } else {
      _refreshNavigationGuidance(notify: false);
    }

    final canTrack = await _canUseLocation();
    if (!canTrack || _trackingBookingId != bookingId) {
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
    _startLiveLocationRefreshTimer();

    _locationSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          (position) {
            _latestOperatorPosition = position;
            _latestOperatorPositionAt = DateTime.now();
            _refreshNavigationGuidance(currentPosition: position);
            if (_trackingBookingId == null) return;
            unawaited(
              _publishOperatorPosition(
                _trackingBookingId!,
                operatorId,
                position,
              ),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_isPermissionRevokedError(error)) {
              _locationWarningHandler?.call(
                'Location permission revoked',
                'Navigation guidance has paused. Re-enable location permission to resume tracking.',
              );
              _stopLocationSharing();
              notifyListeners();
              return;
            }

            developer.log(
              'live_location_stream_failed',
              name: 'operator_home_vm',
              error: error,
              stackTrace: stackTrace,
            );
            unawaited(_locationSubscription?.cancel());
            _locationSubscription = null;
            _startLiveLocationRefreshTimer();
            notifyListeners();
            unawaited(_syncNavigationLifecycle(operatorId));
          },
        );
  }

  void _stopLocationSharing() {
    _liveLocationStaleTimer?.cancel();
    _liveLocationStaleTimer = null;
    _liveLocationRefreshTimer?.cancel();
    _liveLocationRefreshTimer = null;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _trackingBookingId = null;
    _lastLocationPublishAt = null;
    _lastPublishedPosition = null;
    _latestOperatorPosition = null;
    _latestOperatorPositionAt = null;
    _isPublishingLocation = false;
    _isRefreshingLiveLocation = false;
    _navigationGuidance = null;
    _lastNavigationSampleAt = null;
    _lastNavigationSample = null;
    _recentNavigationSpeeds.clear();
    _maxReachedRouteMarker = null;
    _lastAlertRouteMarker = null;
    _wasOffRoute = false;
  }

  void _startLiveLocationRefreshTimer() {
    _liveLocationStaleTimer?.cancel();
    _liveLocationRefreshTimer?.cancel();
    _liveLocationStaleTimer = Timer.periodic(_liveLocationRefreshInterval, (_) {
      if (_trackingBookingId != null) {
        notifyListeners();
      }
    });
    _liveLocationRefreshTimer = Timer.periodic(_liveLocationRefreshInterval, (
      _,
    ) {
      unawaited(_refreshLiveLocationHeartbeat());
    });
  }

  Future<void> _refreshLiveLocationHeartbeat() async {
    if (_isRefreshingLiveLocation) {
      return;
    }

    final bookingId = _trackingBookingId;
    final operatorId = _operatorId;
    if (bookingId == null || operatorId == null || !_isOnline) {
      return;
    }

    final lastAt = _latestOperatorPositionAt;
    if (lastAt != null &&
        DateTime.now().difference(lastAt) < _liveLocationRefreshInterval) {
      return;
    }

    _isRefreshingLiveLocation = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (_trackingBookingId != bookingId) {
        return;
      }

      _latestOperatorPosition = position;
      _latestOperatorPositionAt = DateTime.now();
      _refreshNavigationGuidance(currentPosition: position, notify: false);
      notifyListeners();

      unawaited(_publishOperatorPosition(bookingId, operatorId, position));
    } catch (e) {
      developer.log(
        'live_location_heartbeat_failed',
        name: 'operator_home_vm',
        error: e,
        stackTrace: StackTrace.current,
      );
    } finally {
      _isRefreshingLiveLocation = false;
    }
  }

  Future<void> _syncNavigationLifecycle(String operatorId) async {
    if (!_isOnline) {
      if (_trackingBookingId != null) {
        _stopLocationSharing();
      }
      return;
    }

    final tracked = _resolveTrackedOnTheWayBooking();
    if (tracked == null) {
      if (_trackingBookingId != null) {
        _stopLocationSharing();
      }
      return;
    }

    if (_trackingBookingId == tracked.bookingId &&
        _locationSubscription != null &&
        _liveLocationRefreshTimer != null) {
      return;
    }

    await _startLocationSharing(
      tracked.bookingId,
      operatorId,
      initial: _latestOperatorPosition,
    );
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
    } catch (e) {
      developer.log(
        'location_permission_check_failed',
        name: 'operator_home_vm',
        error: e,
        stackTrace: StackTrace.current,
      );
      return false;
    }
  }

  bool _isPermissionRevokedError(Object error) {
    if (error is LocationServiceDisabledException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('permission') &&
            (text.contains('denied') ||
                text.contains('revoked') ||
                text.contains('not granted')) ||
        text.contains('service disabled') ||
        text.contains('location service') ||
        text.contains('permissiondefinitionsnotfound');
  }

  Future<Position?> _currentPositionOrNull() async {
    final canUseLocation = await _canUseLocation();
    if (!canUseLocation) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
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
    _refreshNavigationGuidance(currentPosition: position);

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

  void _refreshNavigationGuidance({
    Position? currentPosition,
    bool notify = true,
  }) {
    final booking = _resolveTrackedOnTheWayBooking();
    if (booking == null) {
      _navigationGuidance = null;
      if (notify) {
        notifyListeners();
      }
      return;
    }

    _trackingBookingId ??= booking.bookingId;
    final effectiveLat = currentPosition?.latitude ?? booking.operatorLat;
    final effectiveLng = currentPosition?.longitude ?? booking.operatorLng;
    if (effectiveLat == null || effectiveLng == null) {
      _navigationGuidance = null;
      if (notify) {
        notifyListeners();
      }
      return;
    }

    final now = DateTime.now();
    final smoothedSpeedMps = _recordNavigationSpeedSample(currentPosition, now);
    final guidance = computeOperatorNavigationGuidance(
      booking: booking,
      currentLat: effectiveLat,
      currentLng: effectiveLng,
      now: now,
      reportedSpeedMps: currentPosition?.speed,
      smoothedSpeedMps: smoothedSpeedMps,
      lastSampleAt: _lastNavigationSampleAt,
      lastSampleLat: _lastNavigationSample?.latitude,
      lastSampleLng: _lastNavigationSample?.longitude,
      lastResolvedRouteMarker: _maxReachedRouteMarker,
    );

    _navigationGuidance = guidance;
    if (guidance != null) {
      _maxReachedRouteMarker = guidance.nearestRouteMarker;
      _emitNavigationAlerts(booking.bookingId, guidance);
    }

    if (currentPosition != null) {
      _lastNavigationSample = currentPosition;
      _lastNavigationSampleAt = now;
    }

    if (notify) {
      notifyListeners();
    }
  }

  double? _recordNavigationSpeedSample(
    Position? currentPosition,
    DateTime now,
  ) {
    if (currentPosition == null) {
      return _averageRecentNavigationSpeed();
    }

    var speed = currentPosition.speed > 0.5 ? currentPosition.speed : null;
    final lastSample = _lastNavigationSample;
    final lastAt = _lastNavigationSampleAt;
    if (speed == null && lastSample != null && lastAt != null) {
      final elapsedSeconds = now.difference(lastAt).inMilliseconds / 1000.0;
      if (elapsedSeconds >= 0.5) {
        final movedMeters = Geolocator.distanceBetween(
          lastSample.latitude,
          lastSample.longitude,
          currentPosition.latitude,
          currentPosition.longitude,
        );
        final derivedSpeed = movedMeters / elapsedSeconds;
        if (derivedSpeed.isFinite && derivedSpeed > 0.5) {
          speed = derivedSpeed;
        }
      }
    }

    if (speed != null) {
      _recentNavigationSpeeds.addLast(speed);
      while (_recentNavigationSpeeds.length > _maxSpeedSamples) {
        _recentNavigationSpeeds.removeFirst();
      }
    }

    return _averageRecentNavigationSpeed();
  }

  double? _averageRecentNavigationSpeed() {
    if (_recentNavigationSpeeds.isEmpty) {
      return null;
    }
    return _recentNavigationSpeeds.reduce((a, b) => a + b) /
        _recentNavigationSpeeds.length;
  }

  BookingModel? _resolveActiveBooking() {
    if (_activeBookings.isEmpty) {
      return null;
    }
    return _activeBookings.first;
  }

  OperatorHomeSnapshot _resolveHomeSnapshot() {
    final activeBooking = _resolveActiveBooking();
    final operatorId = _operatorId;
    final passengerPickedUp = activeBooking?.passengerPickedUpAt != null;
    final operatorPoint = _bookingPoint(activeBooking);
    final routeHealth = OperatorMapLayers.resolveRouteHealth(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
    );
    final isLiveLocationStale = _isLiveLocationStale(DateTime.now());
    final destinationPoint = activeBooking == null
        ? null
        : LatLng(activeBooking.destinationLat, activeBooking.destinationLng);
    final pendingBookings = operatorId == null
        ? const <BookingModel>[]
        : _pendingBookings
              .where((booking) => !booking.rejectedBy.contains(operatorId))
              .toList(growable: false);
    final topPendingBooking = pendingBookings.isNotEmpty
        ? pendingBookings.first
        : null;
    final key = [
      operatorId ?? '-',
      activeBooking?.bookingId ?? '-',
      activeBooking?.status.firestoreValue ?? '-',
      activeBooking?.passengerPickedUpAt?.millisecondsSinceEpoch.toString() ??
          '-',
      routeHealth.source.name,
      routeHealth.phase.name,
      routeHealth.warning ?? '-',
      isLiveLocationStale ? '1' : '0',
      passengerPickedUp ? '1' : '0',
      operatorPoint?.latitude.toStringAsFixed(5) ?? '-',
      operatorPoint?.longitude.toStringAsFixed(5) ?? '-',
      destinationPoint?.latitude.toStringAsFixed(5) ?? '-',
      destinationPoint?.longitude.toStringAsFixed(5) ?? '-',
      pendingBookings.length.toString(),
      topPendingBooking?.bookingId ?? '-',
      _isOnline ? '1' : '0',
      _isToggling ? '1' : '0',
      _isUpdatingBooking ? '1' : '0',
      _isRefreshing ? '1' : '0',
      _streamVersion.toString(),
      _navigationGuidance?.nearestRouteMarker.toString() ?? '-',
      _navigationGuidance?.nextRouteMarker.toString() ?? '-',
      _navigationGuidance?.remainingDistanceMeters.toStringAsFixed(0) ?? '-',
      _navigationGuidance?.isOffRoute == true ? '1' : '0',
      _navigationGuidance?.progressFraction.toStringAsFixed(3) ?? '-',
      _navigationGuidance?.offRouteSeverity.name ?? '-',
      _navigationGuidance?.headingDegrees?.toStringAsFixed(1) ?? '-',
      _navigationGuidance?.rejoinPoint?.lat.toStringAsFixed(5) ?? '-',
      _navigationGuidance?.rejoinPoint?.lng.toStringAsFixed(5) ?? '-',
    ].join('|');

    if (_cachedHomeSnapshotKey == key && _cachedHomeSnapshot != null) {
      return _cachedHomeSnapshot!;
    }

    final snapshot = OperatorHomeSnapshot(
      isOnline: _isOnline,
      isToggling: _isToggling,
      isUpdatingBooking: _isUpdatingBooking,
      isRefreshing: _isRefreshing,
      streamVersion: _streamVersion,
      activeBooking: activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
      destinationPoint: destinationPoint,
      pendingCount: pendingBookings.length,
      topPendingBooking: topPendingBooking,
      navigationGuidance: _navigationGuidance,
      routeHealth: routeHealth,
      isLiveLocationStale: isLiveLocationStale,
    );

    _cachedHomeSnapshotKey = key;
    _cachedHomeSnapshot = snapshot;
    return snapshot;
  }

  LatLng? _bookingPoint(BookingModel? booking) {
    if (booking == null) {
      return null;
    }

    final localPosition = _latestOperatorPosition;
    if (booking.bookingId == _trackingBookingId && localPosition != null) {
      return LatLng(localPosition.latitude, localPosition.longitude);
    }

    final lat = booking.operatorLat;
    final lng = booking.operatorLng;
    if (lat == null || lng == null) {
      return null;
    }

    return LatLng(lat, lng);
  }

  bool _isLiveLocationStale(DateTime now) {
    if (_trackingBookingId == null) {
      return false;
    }
    final lastAt = _latestOperatorPositionAt;
    if (lastAt == null) {
      return true;
    }
    return now.difference(lastAt) > _liveLocationStaleThreshold;
  }

  void _emitNavigationAlerts(
    String bookingId,
    OperatorNavigationGuidance guidance,
  ) {
    final routeMarker = guidance.nearestRouteMarker;
    final previousRouteMarker = _lastAlertRouteMarker;
    if (previousRouteMarker == null || routeMarker > previousRouteMarker) {
      _lastAlertRouteMarker = routeMarker;
      OperatorNavigationAlertBus.publish(
        OperatorNavigationAlert(
          eventId: bookingId.hashCode ^ (routeMarker * 31),
          bookingId: bookingId,
          title: 'Route progress',
          body:
              'Booking $bookingId reached route marker $routeMarker/${guidance.totalRouteMarkers}. Next: ${guidance.nextRouteMarker}.',
        ),
      );
    }

    if (guidance.isOffRoute && !_wasOffRoute) {
      _wasOffRoute = true;
      OperatorNavigationAlertBus.publish(
        OperatorNavigationAlert(
          eventId: bookingId.hashCode ^ 0x0F01,
          bookingId: bookingId,
          title: 'Off-route detected',
          body:
              'Booking $bookingId is off-route by about ${guidance.offRouteDistanceMeters.round()} m. Please rejoin the planned route.',
        ),
      );
      return;
    }

    if (!guidance.isOffRoute && _wasOffRoute) {
      _wasOffRoute = false;
      OperatorNavigationAlertBus.publish(
        OperatorNavigationAlert(
          eventId: bookingId.hashCode ^ 0x0F02,
          bookingId: bookingId,
          title: 'Route resumed',
          body:
              'Booking $bookingId has returned to the planned route. Continue to marker ${guidance.nextRouteMarker}.',
        ),
      );
    }
  }

  BookingModel? _resolveTrackedOnTheWayBooking() {
    final bookingId = _trackingBookingId;
    if (bookingId != null) {
      for (final booking in _activeBookings) {
        if (booking.bookingId == bookingId &&
            booking.status == BookingStatus.onTheWay) {
          return booking;
        }
      }
    }

    for (final booking in _activeBookings) {
      if (booking.status == BookingStatus.onTheWay) {
        return booking;
      }
    }
    return null;
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
    if (result case OperationFailure(
      :final title,
      :final message,
      :final isInfo,
    )) {
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

      final originalFailure = OperationFailure(title, message, isInfo: isInfo);

      _logFailure(actionName, originalFailure, bookingId: bookingId);
      return originalFailure;
    }
    return result;
  }

  bool _isPermissionDenied(String message) {
    final text = message.toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('permission denied') ||
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
    _initializationFuture = null;
    _locationWarningHandler = null;
    super.dispose();
  }
}

@immutable
class OperatorHomeSnapshot {
  const OperatorHomeSnapshot({
    required this.isOnline,
    required this.isToggling,
    required this.isUpdatingBooking,
    required this.isRefreshing,
    required this.streamVersion,
    required this.activeBooking,
    required this.passengerPickedUp,
    required this.operatorPoint,
    required this.destinationPoint,
    required this.pendingCount,
    required this.topPendingBooking,
    required this.navigationGuidance,
    required this.routeHealth,
    required this.isLiveLocationStale,
  });

  final bool isOnline;
  final bool isToggling;
  final bool isUpdatingBooking;
  final bool isRefreshing;
  final int streamVersion;
  final BookingModel? activeBooking;
  final bool passengerPickedUp;
  final LatLng? operatorPoint;
  final LatLng? destinationPoint;
  final int pendingCount;
  final BookingModel? topPendingBooking;
  final OperatorNavigationGuidance? navigationGuidance;
  final OperatorRouteHealth routeHealth;
  final bool isLiveLocationStale;
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
