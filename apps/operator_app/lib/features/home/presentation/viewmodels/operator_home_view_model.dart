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
import 'package:operator_app/core/services/firebase_session_service.dart';
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
    Future<void> Function()? refreshSessionForNavigation,
  }) : _bookingRepo = bookingRepo,
       _operatorRepo = operatorRepo,
       _refreshSessionForNavigation =
           refreshSessionForNavigation ?? FirebaseSessionService.refreshIdToken;

  final BookingRepository _bookingRepo;
  final OperatorRepository _operatorRepo;
  final Future<void> Function() _refreshSessionForNavigation;

  // ── State ────────────────────────────────────────────────────────────────

  bool _isOnline = false;
  bool _isToggling = false;
  bool _isUpdatingBooking = false;
  bool _isRefreshing = false;
  int _streamVersion = 0; // bumped on manual refresh to force stream rebuild

  List<BookingModel> _activeBookings = [];
  List<BookingModel> _pendingBookings = [];
  final Set<String> _locallyCompletedBookingIds = <String>{};
  final Set<String> _offRouteAlertedBookingIds = <String>{};

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
  DateTime? _lastNavigationSessionRefreshAt;
  Timer? _liveLocationStaleTimer;
  int _emptyActiveReconcileVersion = 0;
  int? _maxReachedRouteMarker;
  int? _lastAlertRouteMarker;
  bool _wasOffRoute = false;
  OperatorHomeSnapshot? _cachedHomeSnapshot;
  String? _cachedHomeSnapshotKey;
  OperatorBookingCardSnapshot? _cachedCardSnapshot;
  String? _cachedCardSnapshotKey;
  Future<void>? _initializationFuture;
  bool _hasInitialized = false;
  void Function(String title, String message)? _locationWarningHandler;

  static const Duration _locationPublishMinInterval = Duration(seconds: 6);
  static const double _locationPublishMinDistanceMeters = 20;
  static const Duration _liveLocationRefreshInterval = Duration(seconds: 2);
  static const Duration _liveLocationStaleThreshold = Duration(seconds: 45);
  static const Duration _navigationSessionRefreshInterval = Duration(
    minutes: 1,
  );
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

  OperatorBookingCardSnapshot get bookingCardSnapshot =>
      _resolveBookingCardSnapshot();

  /// Pending bookings visible to this operator (not already rejected by them).
  List<BookingModel> visiblePendingBookings(String operatorId) =>
      _pendingBookings
          .where((b) => !b.rejectedBy.contains(operatorId))
          .where((b) => !_isDeferredForCurrentSweep(b, operatorId))
          .toList();

  bool _isDeferredForCurrentSweep(BookingModel booking, String operatorId) {
    if (booking.poolDeferredForOperatorUid != operatorId) return false;
    final deferredUntil = booking.poolDeferredUntil;
    if (deferredUntil == null || DateTime.now().isAfter(deferredUntil)) {
      return false;
    }
    if (_activeBookings.isEmpty) {
      return false;
    }

    final activePoolGroupId = _firstNonEmpty(
      _activeBookings.map((b) => b.poolGroupId),
    );
    if (activePoolGroupId == null) {
      return false;
    }
    final deferredPoolGroupId = booking.poolDeferredPoolGroupId;
    if (deferredPoolGroupId != null &&
        deferredPoolGroupId.isNotEmpty &&
        deferredPoolGroupId != activePoolGroupId) {
      return false;
    }

    final activeDirection = _firstNonEmpty(
      _activeBookings.map((b) => b.routeDirection),
    );
    if (activeDirection == null) {
      return false;
    }
    final deferredDirection = booking.poolDeferredRouteDirection;
    if (deferredDirection != null &&
        deferredDirection.isNotEmpty &&
        deferredDirection != activeDirection) {
      return false;
    }

    return true;
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

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
      _initialize(operatorId, preserveExistingBookings: force)
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

  Future<void> _initialize(
    String operatorId, {
    bool preserveExistingBookings = false,
  }) async {
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
      preserveExistingBookings: preserveExistingBookings,
    );

    // Fallback for slow devices or cold cache misses: sync after 500ms if not
    // already triggered by stream callback.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_trackingBookingId == null) {
      await _syncNavigationLifecycle(operatorId);
    }
  }

  // ── Online / Offline ─────────────────────────────────────────────────────

  Future<OperationResult> goOnline() async {
    final operatorId = _operatorId;
    if (operatorId == null) {
      return _notInitialised;
    }

    _isToggling = true;
    _isOnline = true;
    notifyListeners();

    try {
      await _operatorRepo
          .setOnlineStatus(operatorId, isOnline: true)
          .timeout(const Duration(seconds: 6));
      unawaited(_syncNavigationLifecycle(operatorId));
      return const OperationSuccess('You are now online.');
    } on TimeoutException {
      _isOnline = false;
      return const OperationFailure(
        'Timeout',
        'Updating status timed out. Check your network.',
      );
    } catch (e) {
      _isOnline = false;
      return OperationFailure('Status update failed', e.toString());
    } finally {
      _isToggling = false;
      notifyListeners();
    }
  }

  Future<OperationResult> goOfflineSafely({
    OfflineReason reason = OfflineReason.manual,
  }) async {
    final operatorId = _operatorId;
    if (operatorId == null) {
      return _notInitialised;
    }

    if (_activeBookings.any((b) => b.status == BookingStatus.onTheWay)) {
      return const OperationFailure(
        'Active trip in progress',
        'Complete this trip before going offline.',
        isInfo: true,
      );
    }

    final wasOnline = _isOnline;
    _isToggling = true;
    _isOnline = false;
    notifyListeners();

    try {
      final releasedCount = await _bookingRepo.releaseAllAcceptedBookings(
        operatorId,
      );

      _stopLocationSharing();

      await _operatorRepo
          .setOnlineStatus(operatorId, isOnline: false)
          .timeout(const Duration(seconds: 6));

      if (releasedCount > 0) {
        return OperationSuccess(
          '$releasedCount accepted booking${releasedCount == 1 ? '' : 's'} released. You are now offline.',
        );
      }
      return OperationSuccess(
        reason == OfflineReason.logout
            ? 'You are now offline and ready to logout.'
            : 'You are now offline.',
      );
    } on TimeoutException {
      _isOnline = wasOnline;
      return const OperationFailure(
        'Timeout',
        'Updating status timed out. Check your network.',
      );
    } catch (e) {
      _isOnline = wasOnline;
      return OperationFailure('Status update failed', e.toString());
    } finally {
      _isToggling = false;
      notifyListeners();
    }
  }

  Future<OperationResult> toggleOnlineStatus() async {
    return _isOnline ? goOfflineSafely() : goOnline();
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
      () async {
        final position = await _currentPositionOrNull();
        return _bookingRepo.acceptBooking(
          bookingId: bookingId,
          operatorId: operatorId,
          operatorLat: position?.latitude,
          operatorLng: position?.longitude,
          locationUpdatedAt: position?.timestamp,
        );
      },
      actionName: 'accept_booking',
      bookingId: bookingId,
    );

    if (result is OperationSuccess && pendingBooking != null) {
      _promoteAcceptedBookingLocally(pendingBooking, operatorId);
    }
    if (result is OperationFailure &&
        result.title == 'Queued for later route') {
      _removePendingBookingLocally(bookingId);
    }
    if (result is OperationSuccess ||
        (result is OperationFailure &&
            result.title == 'Queued for later route')) {
      unawaited(refresh(operatorId));
    }

    return result;
  }

  Future<OperationResult> rejectBooking(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    final result = await _withBusy(
      () => _bookingRepo.rejectBooking(
        bookingId: bookingId,
        operatorId: operatorId,
      ),
      actionName: 'reject_booking',
      bookingId: bookingId,
    );
    if (result is OperationSuccess) {
      _removePendingBookingLocally(bookingId);
      unawaited(refresh(operatorId));
    }
    return result;
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
          final startedBookingId = result.data['startedBookingId']
              ?.toString()
              .trim();
          final trackingBookingId =
              startedBookingId != null && startedBookingId.isNotEmpty
              ? startedBookingId
              : bookingId;
          _markTripStartedLocally(trackingBookingId, initial);
          await _startLocationSharing(
            trackingBookingId,
            operatorId,
            initial: initial,
          );
          unawaited(refresh(operatorId));
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
      () async {
        final position = await _currentPositionOrNull();
        return _bookingRepo.completeTrip(
          bookingId: bookingId,
          operatorId: operatorId,
          operatorLat: position?.latitude,
          operatorLng: position?.longitude,
        );
      },
      actionName: 'complete_trip',
      bookingId: bookingId,
    );

    if (result is OperationSuccess) {
      _markTripCompletedLocally(bookingId);
      unawaited(refresh(operatorId));
    }

    return result;
  }

  Future<OperationResult> markPassengerPickedUp(String bookingId) async {
    final operatorId = _operatorId;
    if (operatorId == null) return _notInitialised;
    final result = await _withBusy(
      () async {
        final position = await _currentPositionOrNull();
        return _bookingRepo.markPassengerPickedUp(
          bookingId: bookingId,
          operatorId: operatorId,
          operatorLat: position?.latitude,
          operatorLng: position?.longitude,
        );
      },
      actionName: 'mark_passenger_picked_up',
      bookingId: bookingId,
    );

    if (result is OperationSuccess) {
      _markPassengerPickedUpLocally(bookingId);
      unawaited(refresh(operatorId));
      return result;
    }

    if (result case OperationFailure(:final title, :final message)) {
      if (_isPermissionDenied('$title $message')) {
        // Firestore rules may block custom marker fields; keep the pickup
        // interaction usable and allow progression to trip completion.
        _markPassengerPickedUpLocally(bookingId);
        unawaited(refresh(operatorId));
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
      _stopStreams(clearBookings: false, stopLocationSharing: false);
      _streamVersion += 1;
      _startStreams(operatorId, preserveExistingBookings: true);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  // ── Cancellation notice ──────────────────────────────────────────────────

  Future<void> recoverAfterForeground(String operatorId) async {
    _operatorId = operatorId;

    if (_activeSubscription == null || _pendingSubscription == null) {
      _startStreams(
        operatorId,
        onFirstActiveEmission: () =>
            unawaited(_syncNavigationLifecycle(operatorId)),
        preserveExistingBookings: true,
      );
    }

    await _syncNavigationLifecycle(operatorId);
  }

  /// Records that the cancellation notice for [bookingId] was shown, so it
  /// isn't shown again on the next stream event.
  void markCancellationNoticeShown(String bookingId) {
    _lastCancelledNoticeBookingId = bookingId;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _startStreams(
    String operatorId, {
    void Function()? onFirstActiveEmission,
    bool preserveExistingBookings = false,
  }) {
    _stopStreams(
      clearBookings: !preserveExistingBookings,
      stopLocationSharing: !preserveExistingBookings,
    );

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

            if (list.isEmpty && _shouldVerifyEmptyActiveEmission()) {
              unawaited(_verifyEmptyActiveEmission(operatorId));
              notifyListeners();
              return;
            }

            _emptyActiveReconcileVersion += 1;
            _activeBookings = _filterLocallyCompleted(list);
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
            if (!preserveExistingBookings) {
              _activeBookings = [];
              _stopLocationSharing();
              _refreshNavigationGuidance(notify: false);
            }
            notifyListeners();
          },
        );

    _pendingSubscription = _bookingRepo.streamPendingBookings().listen(
      (list) {
        _pendingBookings = list;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'pending_bookings_stream_failed',
          name: 'operator_home_vm',
          error: error,
          stackTrace: stackTrace,
        );
        if (!preserveExistingBookings) {
          _pendingBookings = [];
        }
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
      _activeBookings = <BookingModel>[..._activeBookings, acceptedBooking];
    } else {
      final updated = [..._activeBookings];
      updated[existingIndex] = acceptedBooking;
      _activeBookings = updated;
    }

    _refreshNavigationGuidance(notify: false);
    notifyListeners();
  }

  void _removePendingBookingLocally(String bookingId) {
    _pendingBookings = _pendingBookings
        .where((item) => item.bookingId != bookingId)
        .toList(growable: false);
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

  void _markPassengerPickedUpLocally(String bookingId) {
    final index = _activeBookings.indexWhere(
      (booking) => booking.bookingId == bookingId,
    );
    if (index == -1) {
      return;
    }

    final current = _activeBookings[index];
    final currentStop = current.currentPoolStop;
    if (current.passengerPickedUpAt != null && currentStop == null) {
      return;
    }

    final now = DateTime.now();
    final stopBookingIds = currentStop?.bookingIds.toSet() ?? {bookingId};
    final nextStopPlan = currentStop == null
        ? current.poolStopPlan
        : _completeAndAdvanceStopPlan(current.poolStopPlan, currentStop, now);
    final nextCurrentStop = _firstIncompleteStop(nextStopPlan);
    final updated = _activeBookings
        .map((booking) {
          final belongsToPool =
              current.poolGroupId == null ||
              current.poolGroupId!.isEmpty ||
              booking.poolGroupId == current.poolGroupId;
          if (!belongsToPool && booking.bookingId != bookingId) {
            return booking;
          }

          final isAtStop = stopBookingIds.contains(booking.bookingId);
          return booking.copyWith(
            status: isAtStop ? BookingStatus.onTheWay : booking.status,
            passengerPickedUpAt: isAtStop ? now : booking.passengerPickedUpAt,
            pickedUpAt: isAtStop ? now : booking.pickedUpAt,
            onboard: isAtStop ? true : booking.onboard,
            poolPhase: isAtStop ? 'onboard' : booking.poolPhase,
            poolStopPlan: nextStopPlan,
            currentStopIndex:
                nextCurrentStop?.index ?? booking.currentStopIndex,
            currentStopId: nextCurrentStop?.stopId ?? booking.currentStopId,
            currentPoolStopId:
                nextCurrentStop?.stopId ?? booking.currentPoolStopId,
            updatedAt: now,
          );
        })
        .toList(growable: false);
    _activeBookings = updated;
    _refreshNavigationGuidance(
      currentPosition: _latestOperatorPosition,
      notify: false,
    );
    notifyListeners();
  }

  List<PoolStopPlanItem> _completeAndAdvanceStopPlan(
    List<PoolStopPlanItem> stopPlan,
    PoolStopPlanItem completedStop,
    DateTime completedAt,
  ) {
    final completed = stopPlan
        .map((stop) {
          if (stop.stopId == completedStop.stopId) {
            return _copyStopPlanItem(
              stop,
              status: 'completed',
              reachedAt: stop.reachedAt ?? completedAt,
              completedAt: completedAt,
            );
          }
          return stop;
        })
        .toList(growable: false);
    return _applyCurrentStopStateLocally(completed);
  }

  List<PoolStopPlanItem> _applyCurrentStopStateLocally(
    List<PoolStopPlanItem> stopPlan,
  ) {
    final nextStop = _firstIncompleteStop(stopPlan);
    return stopPlan
        .map((stop) {
          if (stop.status == 'completed' || stop.status == 'skipped') {
            return stop;
          }
          return _copyStopPlanItem(
            stop,
            status: nextStop != null && stop.stopId == nextStop.stopId
                ? 'active'
                : 'pending',
          );
        })
        .toList(growable: false);
  }

  PoolStopPlanItem? _firstIncompleteStop(List<PoolStopPlanItem> stopPlan) {
    for (final stop in stopPlan) {
      if (stop.status != 'completed' && stop.status != 'skipped') {
        return stop;
      }
    }
    return null;
  }

  PoolStopPlanItem _copyStopPlanItem(
    PoolStopPlanItem stop, {
    String? status,
    DateTime? reachedAt,
    DateTime? completedAt,
  }) {
    return PoolStopPlanItem(
      stopId: stop.stopId,
      index: stop.index,
      stopType: stop.stopType,
      stopJettyId: stop.stopJettyId,
      stopName: stop.stopName,
      lat: stop.lat,
      lng: stop.lng,
      routePositionMeters: stop.routePositionMeters,
      distanceFromRouteMeters: stop.distanceFromRouteMeters,
      bookingIds: stop.bookingIds,
      status: status ?? stop.status,
      etaToStopMinutes: stop.etaToStopMinutes,
      reachedAt: reachedAt ?? stop.reachedAt,
      completedAt: completedAt ?? stop.completedAt,
    );
  }

  void _markTripCompletedLocally(String bookingId) {
    _locallyCompletedBookingIds.add(bookingId);
    _activeBookings = _activeBookings
        .where((booking) => booking.bookingId != bookingId)
        .toList(growable: false);
    if (_trackingBookingId == bookingId) {
      _stopLocationSharing();
    } else {
      _refreshNavigationGuidance(notify: false);
    }
    _clearSnapshotCaches();
    notifyListeners();
  }

  void _stopStreams({
    bool clearBookings = true,
    bool stopLocationSharing = true,
  }) {
    _activeSubscription?.cancel();
    _pendingSubscription?.cancel();
    if (stopLocationSharing) {
      _stopLocationSharing();
    }
    if (clearBookings) {
      _activeBookings = [];
      _pendingBookings = [];
      _clearSnapshotCaches();
    }
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

    final sessionReady = await _refreshSessionBeforeNavigation();
    if (!sessionReady) {
      return;
    }

    await _startLocationSharing(
      tracked.bookingId,
      operatorId,
      initial: _latestOperatorPosition,
    );
  }

  Future<bool> _refreshSessionBeforeNavigation() async {
    final lastRefreshAt = _lastNavigationSessionRefreshAt;
    final now = DateTime.now();
    if (lastRefreshAt != null &&
        now.difference(lastRefreshAt) < _navigationSessionRefreshInterval) {
      return true;
    }

    try {
      await _refreshSessionForNavigation();
      _lastNavigationSessionRefreshAt = now;
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'navigation_session_refresh_failed',
        name: 'operator_home_vm',
        error: error,
        stackTrace: stackTrace,
      );
      _locationWarningHandler?.call(
        'Session refresh needed',
        'Navigation is paused until your sign-in session is refreshed.',
      );
      return false;
    }
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
    final trackedId = _trackingBookingId;
    if (trackedId != null) {
      for (final booking in _activeBookings) {
        if (booking.bookingId == trackedId &&
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
    return _activeBookings.first;
  }

  List<BookingModel> _filterLocallyCompleted(List<BookingModel> bookings) {
    return bookings
        .where(
          (booking) => !_locallyCompletedBookingIds.contains(booking.bookingId),
        )
        .toList(growable: false);
  }

  bool _shouldVerifyEmptyActiveEmission() {
    if (_activeBookings.isEmpty) {
      return false;
    }
    final trackedId = _trackingBookingId;
    if (trackedId != null) {
      return _activeBookings.any((booking) => booking.bookingId == trackedId);
    }
    return _resolveActiveBooking() != null;
  }

  Future<void> _verifyEmptyActiveEmission(String operatorId) async {
    final candidate = _resolveActiveBooking();
    final bookingId = _trackingBookingId ?? candidate?.bookingId;
    if (bookingId == null) {
      return;
    }

    final version = ++_emptyActiveReconcileVersion;
    try {
      final booking = await _bookingRepo.getBooking(bookingId);
      if (version != _emptyActiveReconcileVersion) {
        return;
      }

      if (booking != null &&
          booking.operatorUid == operatorId &&
          _isRepositoryActiveBooking(booking) &&
          !_locallyCompletedBookingIds.contains(booking.bookingId)) {
        final updated = [..._activeBookings];
        final index = updated.indexWhere((b) => b.bookingId == bookingId);
        if (index >= 0) {
          updated[index] = booking;
        } else {
          updated.add(booking);
        }
        _activeBookings = updated..sort(_compareActiveBookingSequence);
        _refreshNavigationGuidance(notify: false);
        unawaited(_syncNavigationLifecycle(operatorId));
        notifyListeners();
        return;
      }

      _activeBookings = const <BookingModel>[];
      _stopLocationSharing();
      _refreshNavigationGuidance(notify: false);
      notifyListeners();
    } catch (error, stackTrace) {
      developer.log(
        'verify_empty_active_emission_failed',
        name: 'operator_home_vm',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static bool _isRepositoryActiveBooking(BookingModel booking) {
    return booking.status == BookingStatus.accepted ||
        booking.status == BookingStatus.onTheWay;
  }

  static int _compareActiveBookingSequence(BookingModel a, BookingModel b) {
    if (a.status == BookingStatus.onTheWay &&
        b.status != BookingStatus.onTheWay) {
      return -1;
    }
    if (b.status == BookingStatus.onTheWay &&
        a.status != BookingStatus.onTheWay) {
      return 1;
    }

    final aSeq = a.poolSequence;
    final bSeq = b.poolSequence;
    if (aSeq != null && bSeq != null && aSeq != bSeq) {
      return aSeq.compareTo(bSeq);
    }
    if (aSeq != null && bSeq == null) return -1;
    if (aSeq == null && bSeq != null) return 1;

    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  void _clearSnapshotCaches() {
    _cachedHomeSnapshot = null;
    _cachedHomeSnapshotKey = null;
    _cachedCardSnapshot = null;
    _cachedCardSnapshotKey = null;
  }

  String _stopPlanSignature(List<PoolStopPlanItem> stops) {
    if (stops.isEmpty) {
      return '-';
    }
    return stops
        .map(
          (stop) => [
            stop.stopId,
            stop.status,
            stop.stopType,
            stop.bookingIds.join('+'),
          ].join('/'),
        )
        .join(',');
  }

  OperatorBookingCardSnapshot _resolveBookingCardSnapshot() {
    final activeBooking = _resolveActiveBooking();
    final operatorId = _operatorId;
    final passengerPickedUp = _isPassengerPickedUp(activeBooking);
    final pendingBookings = operatorId == null
        ? const <BookingModel>[]
        : _pendingBookings
              .where((booking) => !booking.rejectedBy.contains(operatorId))
              .where(
                (booking) => !_isDeferredForCurrentSweep(booking, operatorId),
              )
              .toList(growable: false);
    final topPendingBooking = pendingBookings.isNotEmpty
        ? pendingBookings.first
        : null;
    final activeBookings = List<BookingModel>.unmodifiable(_activeBookings);
    final activeSignature = activeBookings
        .map(
          (booking) => [
            booking.bookingId,
            booking.status.firestoreValue,
            booking.poolSequence?.toString() ?? '-',
            booking.currentStopId ?? '-',
            booking.currentStopIndex?.toString() ?? '-',
            _stopPlanSignature(booking.poolStopPlan),
            booking.passengerPickedUpAt?.millisecondsSinceEpoch.toString() ??
                '-',
          ].join(':'),
        )
        .join(',');

    final key = [
      operatorId ?? '-',
      activeBooking?.bookingId ?? '-',
      activeBooking?.status.firestoreValue ?? '-',
      activeBooking?.currentStopId ??
          activeBooking?.currentPoolStop?.stopId ??
          '-',
      activeBooking?.currentStopIndex?.toString() ?? '-',
      _stopPlanSignature(activeBooking?.poolStopPlan ?? const []),
      activeBooking?.passengerPickedUpAt?.millisecondsSinceEpoch.toString() ??
          '-',
      activeBooking?.poolGroupId ?? '-',
      activeBooking?.poolStopPlan.length.toString() ?? '-',
      passengerPickedUp ? '1' : '0',
      pendingBookings.length.toString(),
      topPendingBooking?.bookingId ?? '-',
      _isOnline ? '1' : '0',
      _isToggling ? '1' : '0',
      _isUpdatingBooking ? '1' : '0',
      _isRefreshing ? '1' : '0',
      _streamVersion.toString(),
      activeSignature,
    ].join('|');

    if (_cachedCardSnapshotKey == key && _cachedCardSnapshot != null) {
      return _cachedCardSnapshot!;
    }

    final snapshot = OperatorBookingCardSnapshot(
      isOnline: _isOnline,
      isToggling: _isToggling,
      isUpdatingBooking: _isUpdatingBooking,
      isRefreshing: _isRefreshing,
      streamVersion: _streamVersion,
      activeBooking: activeBooking,
      passengerPickedUp: passengerPickedUp,
      pendingCount: pendingBookings.length,
      topPendingBooking: topPendingBooking,
      activeBookings: activeBookings,
    );

    _cachedCardSnapshotKey = key;
    _cachedCardSnapshot = snapshot;
    return snapshot;
  }

  OperatorHomeSnapshot _resolveHomeSnapshot() {
    final activeBooking = _resolveActiveBooking();
    final operatorId = _operatorId;
    final passengerPickedUp = _isPassengerPickedUp(activeBooking);
    final operatorPoint = _bookingPoint(activeBooking);
    final routeHealth = OperatorMapLayers.resolveRouteHealth(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
    );
    final isLiveLocationStale = _isLiveLocationStale(DateTime.now());
    final currentStop = activeBooking?.currentPoolStop;
    final destinationPoint = currentStop != null
        ? LatLng(currentStop.lat, currentStop.lng)
        : activeBooking == null
        ? null
        : LatLng(activeBooking.destinationLat, activeBooking.destinationLng);
    final pendingBookings = operatorId == null
        ? const <BookingModel>[]
        : visiblePendingBookings(operatorId);
    final topPendingBooking = pendingBookings.isNotEmpty
        ? pendingBookings.first
        : null;
    final key = [
      operatorId ?? '-',
      activeBooking?.bookingId ?? '-',
      activeBooking?.status.firestoreValue ?? '-',
      activeBooking?.currentStopId ??
          activeBooking?.currentPoolStop?.stopId ??
          '-',
      activeBooking?.currentStopIndex?.toString() ?? '-',
      _stopPlanSignature(activeBooking?.poolStopPlan ?? const []),
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

  bool _isPassengerPickedUp(BookingModel? booking) {
    if (booking == null) {
      return false;
    }
    return booking.passengerPickedUpAt != null ||
        booking.pickedUpAt != null ||
        booking.onboard ||
        booking.poolPhase == 'onboard';
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
          body: 'You are progressing along the planned river route.',
        ),
      );
    }

    if (guidance.isOffRoute && !_wasOffRoute) {
      _wasOffRoute = true;
      if (_offRouteAlertedBookingIds.add(bookingId)) {
        OperatorNavigationAlertBus.publish(
          OperatorNavigationAlert(
            eventId: bookingId.hashCode ^ 0x0F01,
            bookingId: bookingId,
            title: 'Off-route detected',
            body:
                'You are about ${guidance.offRouteDistanceMeters.round()} m from the planned river route. Rejoin the highlighted route to resume guidance.',
          ),
        );
      }
      return;
    }

    if (!guidance.isOffRoute && _wasOffRoute) {
      _wasOffRoute = false;
      OperatorNavigationAlertBus.publish(
        OperatorNavigationAlert(
          eventId: bookingId.hashCode ^ 0x0F02,
          bookingId: bookingId,
          title: 'Route resumed',
          body: 'You are back on the planned river route.',
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
      if (_isPermissionDenied(message) ||
          FirebaseSessionService.isSessionPermissionError(message)) {
        final friendly = OperationFailure(
          'Permission denied',
          'Your sign-in session could not be refreshed. Please sign in again if this continues.',
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
    if (!kDebugMode) {
      return;
    }
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

enum OfflineReason { manual, logout }

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

@immutable
class OperatorBookingCardSnapshot {
  const OperatorBookingCardSnapshot({
    required this.isOnline,
    required this.isToggling,
    required this.isUpdatingBooking,
    required this.isRefreshing,
    required this.streamVersion,
    required this.activeBooking,
    required this.passengerPickedUp,
    required this.pendingCount,
    required this.topPendingBooking,
    required this.activeBookings,
  });

  final bool isOnline;
  final bool isToggling;
  final bool isUpdatingBooking;
  final bool isRefreshing;
  final int streamVersion;
  final BookingModel? activeBooking;
  final bool passengerPickedUp;
  final int pendingCount;
  final BookingModel? topPendingBooking;
  final List<BookingModel> activeBookings;
}

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
