import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show ImageFilter;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:operator_app/core/theme/operator_brand.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/home/presentation/location/operator_location_coordinator.dart';
import 'package:operator_app/features/home/presentation/map/operator_map_layers.dart';
import 'package:operator_app/features/home/presentation/services/operator_navigation_guidance_service.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:operator_app/features/home/presentation/widgets/operator_booking_panels.dart';
import 'package:operator_app/features/home/presentation/widgets/operator_info_card.dart';
import 'package:operator_app/features/home/presentation/services/operator_map_controller_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorHomeScreen extends StatefulWidget {
  const OperatorHomeScreen({
    super.key,
    this.testOperatorId,
    this.testOperatorEmail,
    this.skipRuntimeChecks = false,
    this.mapBuilder,
  });

  final String? testOperatorId;
  final String? testOperatorEmail;
  final bool skipRuntimeChecks;
  final Widget Function({
    required CameraPosition initialCameraPosition,
    required bool hasLocationPermission,
    required ValueChanged<GoogleMapController> onMapCreated,
  })?
  mapBuilder;

  @override
  State<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

class _OperatorHomeScreenState extends State<OperatorHomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const Color _brandOrange = OperatorBrand.orange;
  static const Color _brandMagenta = OperatorBrand.magenta;
  static const Color _goOnlineGreen = OperatorBrand.goOnlineGreen;

  static const MethodChannel _mapsConfigChannel = MethodChannel(
    'operator_app/maps_config',
  );
  static const MethodChannel _screenAwakeChannel = MethodChannel(
    'operator_app/screen_awake',
  );
  static const MethodChannel _phoneChannel = MethodChannel(
    'operator_app/phone',
  );

  bool _hasLocationPermission = false;
  bool _hasShownWelcomeAlert = false;
  bool _hasCheckedMapsConfig = false;
  bool _isInitializingViewModel = false;
  StreamSubscription<User?>? _authSubscription;
  String? _initializedOperatorId;
  DateTime? _lastRecoveryAttempt;
  DateTime? _lastLocationLookupAt;
  String? _lastNavigationSyncKey;
  bool _isScreenAwakeEnabled = false;
  OperatorHomeViewModel? _observedViewModel;
  bool _isActiveSectionExpanded = false;
  bool _isQueueSectionExpanded = false;
  final OperatorLocationCoordinator _locationCoordinator =
      const OperatorLocationCoordinator();
  final Duration _routeTransitionDuration = const Duration(milliseconds: 700);
  late final AnimationController _routeTransitionController;
  final OperatorMapControllerService _mapCameraService =
      OperatorMapControllerService();
  double _cameraBoundsPadding = 180;

  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(3.1390, 101.6869),
    zoom: 12,
  );

  String? get _operatorId =>
      widget.testOperatorId ?? FirebaseAuth.instance.currentUser?.uid;

  String get _operatorLabel =>
      widget.testOperatorEmail ??
      FirebaseAuth.instance.currentUser?.email ??
      'Operator';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _routeTransitionController =
        AnimationController(vsync: this, duration: _routeTransitionDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _mapCameraService.clearTransitionState();
            }
          });

    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen((user) {
      if (!mounted || user == null) {
        return;
      }
      if (user.uid == _initializedOperatorId) {
        return;
      }
      unawaited(_initializeViewModel(user.uid));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (!_hasShownWelcomeAlert) {
        if (!widget.skipRuntimeChecks) {
          showTopWelcomeCard(context, operatorLabel: _operatorLabel);
        }
        _hasShownWelcomeAlert = true;
      }

      if (!widget.skipRuntimeChecks) {
        _checkMapsConfiguration();
      }

      final operatorId = _operatorId;
      if (operatorId != null) {
        unawaited(_initializeViewModel(operatorId));
      }
    });

    if (!widget.skipRuntimeChecks) {
      unawaited(_bootstrapLocation());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) {
      return;
    }

    if (_mapCameraService.currentState.isProgrammaticCameraMove) {
      return;
    }

    final now = DateTime.now();
    final last = _lastRecoveryAttempt;
    if (last != null && now.difference(last) < const Duration(seconds: 6)) {
      return;
    }
    _lastRecoveryAttempt = now;

    final operatorId = _operatorId;
    if (operatorId == null || _isInitializingViewModel) {
      return;
    }

    unawaited(
      context.read<OperatorHomeViewModel>().recoverAfterForeground(operatorId),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewModel = context.read<OperatorHomeViewModel>();
    if (_observedViewModel == viewModel) {
      return;
    }

    _observedViewModel?.setLocationWarningHandler(null);
    _observedViewModel?.removeListener(_onViewModelChanged);
    _observedViewModel = viewModel;
    _observedViewModel?.addListener(_onViewModelChanged);
    _observedViewModel?.setLocationWarningHandler(_showLocationWarning);
    _syncScreenAwake(viewModel.homeSnapshot.activeBooking);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    unawaited(_setScreenAwake(false));
    _routeTransitionController.dispose();
    _observedViewModel?.removeListener(_onViewModelChanged);
    _observedViewModel?.setLocationWarningHandler(null);
    _mapCameraService.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    final viewModel = _observedViewModel;
    if (!mounted || viewModel == null) {
      return;
    }

    final snapshot = viewModel.homeSnapshot;
    _syncScreenAwake(snapshot.activeBooking);
    final navigationKey = _navigationSyncKey(snapshot);
    if (navigationKey == _lastNavigationSyncKey) {
      return;
    }
    _lastNavigationSyncKey = navigationKey;

    final activeBooking = snapshot.activeBooking;
    final trimmedRoutePoints = OperatorMapLayers.trimmedRoutePointsForCamera(
      activeBooking,
      passengerPickedUp: snapshot.passengerPickedUp,
      operatorPoint: snapshot.operatorPoint,
    );

    _mapCameraService.prepareRouteFitBeforeFollow(
      activeBooking,
      routePoints: trimmedRoutePoints,
      passengerPickedUp: snapshot.passengerPickedUp,
    );

    unawaited(
      _syncNavigationCamera(
        activeBooking,
        routePoints: trimmedRoutePoints,
        operatorPoint: snapshot.operatorPoint,
        destinationPoint: snapshot.destinationPoint,
        forceFollow: false,
      ),
    );
  }

  void _syncScreenAwake(BookingModel? activeBooking) {
    final shouldKeepAwake =
        activeBooking != null && activeBooking.status == BookingStatus.onTheWay;
    if (shouldKeepAwake == _isScreenAwakeEnabled) {
      return;
    }

    unawaited(_setScreenAwake(shouldKeepAwake));
  }

  Future<void> _setScreenAwake(bool enabled) async {
    if (_isScreenAwakeEnabled == enabled) {
      return;
    }

    _isScreenAwakeEnabled = enabled;
    try {
      await _screenAwakeChannel.invokeMethod<void>(
        'setKeepScreenOn',
        <String, Object>{'enabled': enabled},
      );
    } catch (e) {
      developer.log(
        'set_screen_awake_failed',
        name: 'operator_home_screen',
        error: e,
        stackTrace: StackTrace.current,
      );
    }
  }

  void _showLocationWarning(String title, String message) {
    if (!mounted) {
      return;
    }

    showTopInfo(context, title: title, message: message);
  }

  Future<void> _initializeViewModel(
    String operatorId, {
    bool force = false,
  }) async {
    if (!mounted) {
      return;
    }
    if (!force && _initializedOperatorId == operatorId) {
      return;
    }

    setState(() => _isInitializingViewModel = true);

    try {
      await context.read<OperatorHomeViewModel>().ensureInitialized(
        operatorId,
        force: force,
      );
      _initializedOperatorId = operatorId;
    } catch (e) {
      if (mounted) {
        developer.log(
          'initialize_view_model_failed',
          name: 'operator_home_screen',
          error: e,
          stackTrace: StackTrace.current,
        );
        showTopError(
          context,
          title: 'Unable to load operator state',
          message: e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializingViewModel = false);
      }
    }
  }

  Future<void> _checkMapsConfiguration() async {
    if (!mounted || _hasCheckedMapsConfig) {
      return;
    }
    _hasCheckedMapsConfig = true;

    try {
      final result = await _mapsConfigChannel.invokeMapMethod<String, dynamic>(
        'getMapsConfigStatus',
      );
      if (!mounted || result == null) {
        return;
      }

      final injected = result['injected'] == true;
      if (!injected) {
        showTopError(
          context,
          title: 'Google Maps key not injected',
          message:
              'MAPS_API_KEY is not resolved from Android manifest. Check android/local.properties and API key restrictions.',
        );
        return;
      }

      if (kDebugMode) {
        final preview = (result['preview'] ?? '').toString();
        debugPrint('Operator Maps API key injected: $preview');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Maps config check failed: $e');
      }
    }
  }

  Future<void> _bootstrapLocation() async {
    if (!_shouldPerformLocationLookup()) {
      return;
    }

    final access = await _resolveLocationAccess();
    if (access != OperatorLocationAccess.granted) {
      return;
    }

    try {
      final pos = await _getUserPositionSafely();
      if (pos == null || !mounted) {
        return;
      }

      setState(() {
        _initialCameraPosition = CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 16,
        );
      });

      if (_mapCameraService.currentState.isMapReady) {
        await _animateCameraSafely(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      showTopError(
        context,
        message: 'Unable to get current location: $e',
        title: 'Location error',
      );
    }
  }

  Future<OperatorLocationAccess> _resolveLocationAccess() async {
    final access = await _locationCoordinator.ensureLocationAccess();

    if (mounted) {
      setState(
        () => _hasLocationPermission = access == OperatorLocationAccess.granted,
      );
    }

    switch (access) {
      case OperatorLocationAccess.serviceDisabled:
        if (mounted) {
          showTopInfo(
            context,
            title: 'Location services off',
            message: 'Enable location services to show your position.',
            actionLabel: 'Open Settings',
            onAction: Geolocator.openLocationSettings,
          );
        }
        break;
      case OperatorLocationAccess.deniedForever:
        if (mounted) {
          showTopInfo(
            context,
            title: 'Permission required',
            message:
                'Location permission was denied permanently. Enable it in Settings.',
            actionLabel: 'Open Settings',
            onAction: openAppSettings,
          );
        }
        break;
      case OperatorLocationAccess.denied:
      case OperatorLocationAccess.granted:
        break;
    }

    return access;
  }

  Future<void> _centerOnUser({bool showFeedback = true}) async {
    if (!_mapCameraService.currentState.isMapReady) {
      if (showFeedback) {
        showTopInfo(
          context,
          message: 'Map is still loading.',
          title: 'Please wait',
        );
      }
      return;
    }

    if (!_shouldPerformLocationLookup()) {
      return;
    }

    final access = await _resolveLocationAccess();
    if (access != OperatorLocationAccess.granted) {
      return;
    }

    try {
      final pos = await _getUserPositionSafely();
      if (pos == null || !mounted) {
        return;
      }
      await _animateCameraSafely(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (showFeedback) {
        showTopError(
          context,
          message: 'Unable to get location: $e',
          title: 'Location error',
        );
      }
    }
  }

  Future<void> _toggleStatus() async {
    final viewModel = context.read<OperatorHomeViewModel>();
    final snapshot = viewModel.bookingCardSnapshot;
    if (snapshot.isOnline &&
        !snapshot.activeBookings.any(
          (b) => b.status == BookingStatus.onTheWay,
        ) &&
        snapshot.activeBookings.any(
          (b) => b.status == BookingStatus.accepted,
        )) {
      final acceptedCount = snapshot.activeBookings
          .where((b) => b.status == BookingStatus.accepted)
          .length;
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Go offline?'),
            content: Text(
              '$acceptedCount accepted booking${acceptedCount == 1 ? '' : 's'} will be released back to the queue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Go Offline'),
              ),
            ],
          );
        },
      );
      if (shouldContinue != true || !mounted) {
        return;
      }
    }

    final result = snapshot.isOnline
        ? await viewModel.goOfflineSafely()
        : await viewModel.goOnline();
    if (!mounted) {
      return;
    }
    _showOperationResult(result);
  }

  Future<void> _refreshBookingData(String operatorId) async {
    await context.read<OperatorHomeViewModel>().refresh(operatorId);
    if (!mounted) {
      return;
    }
    showTopInfo(
      context,
      title: 'Bookings refreshed',
      message: 'Latest booking streams were reloaded.',
    );
  }

  Widget _buildBookingActionCard(
    String operatorId,
    OperatorHomeViewModel viewModel,
    OperatorBookingCardSnapshot cardSnapshot,
    OperatorHomeSnapshot navigationSnapshot,
  ) {
    final topPendingBooking = cardSnapshot.topPendingBooking;
    final pendingCount = cardSnapshot.pendingCount;
    final guidance = navigationSnapshot.navigationGuidance;
    final activeBooking = cardSnapshot.activeBooking;
    final activeCount = cardSnapshot.activeBookings.length;
    final isOnTheWay =
        activeBooking != null && activeBooking.status == BookingStatus.onTheWay;
    final passengerPickedUp = cardSnapshot.passengerPickedUp;
    final bookingGuidance =
        isOnTheWay &&
            guidance != null &&
            guidance.bookingId == activeBooking.bookingId
        ? guidance
        : null;

    return KeyedSubtree(
      key: ValueKey('booking-actions-${cardSnapshot.streamVersion}'),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OperatorBookingStatsCard(
              pendingCount: pendingCount,
              activeCount: activeCount,
              isQueueExpanded: _isQueueSectionExpanded,
              isActiveExpanded: _isActiveSectionExpanded,
              onPendingTap: () {
                setState(() {
                  final shouldExpand = !_isQueueSectionExpanded;
                  _isQueueSectionExpanded = shouldExpand;
                  _isActiveSectionExpanded = false;
                });
              },
              onActiveTap: () {
                setState(() {
                  final shouldExpand = !_isActiveSectionExpanded;
                  _isActiveSectionExpanded = shouldExpand;
                  _isQueueSectionExpanded = false;
                });
              },
              onRefresh: () => _refreshBookingData(operatorId),
              isRefreshing: cardSnapshot.isRefreshing,
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: activeBooking != null
                    ? _buildActiveBookingCard(activeBooking, viewModel)
                    : const OperatorInfoCard(
                        icon: Icons.directions_boat_filled_outlined,
                        iconColor: OperatorBrand.magenta,
                        title: 'No active trip',
                        subtitle:
                            'Accept a booking from the queue to start operating.',
                      ),
              ),
              crossFadeState: _isActiveSectionExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: topPendingBooking != null
                    ? _buildPendingBookingCard(
                        topPendingBooking,
                        pendingCount,
                        viewModel,
                      )
                    : const OperatorInfoCard(
                        icon: Icons.hourglass_top,
                        iconColor: Colors.orange,
                        title: 'No pending bookings',
                        subtitle: 'You are online. Waiting for passengers...',
                      ),
              ),
              crossFadeState: _isQueueSectionExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
            if (activeBooking != null &&
                activeBooking.status == BookingStatus.onTheWay)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildNavigationInfoCard(
                  booking: activeBooking,
                  guidance: bookingGuidance,
                  passengerPickedUp: passengerPickedUp,
                  isLiveLocationStale: navigationSnapshot.isLiveLocationStale,
                  viewModel: viewModel,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveBookingCard(
    BookingModel booking,
    OperatorHomeViewModel viewModel,
  ) {
    return OperatorActiveBookingCard(
      booking: booking,
      isUpdating: viewModel.isUpdatingBooking,
      detailText: _buildBookingDetailText(booking),
      poolBookings: viewModel.activeBookings,
      onCallCustomer: () => _callCustomer(booking),
      onCallPoolCustomer: _callCustomer,
      onStartTrip: () async {
        final bookingToStart = _bookingForCurrentPoolStop(
          booking,
          viewModel.activeBookings,
        );
        final result = await viewModel.startTrip(bookingToStart.bookingId);
        if (!mounted) {
          return;
        }
        _showOperationResult(result);
        if (result is OperationSuccess && mounted) {
          setState(() => _isActiveSectionExpanded = false);
        }
      },
      onRelease: () async {
        final result = await viewModel.releaseBooking(booking.bookingId);
        if (!mounted) {
          return;
        }
        _showOperationResult(result);
      },
    );
  }

  BookingModel _bookingForCurrentPoolStop(
    BookingModel fallback,
    List<BookingModel> poolBookings,
  ) {
    final currentStopBookingIds = fallback.currentPoolStop?.bookingIds;
    if (currentStopBookingIds == null || currentStopBookingIds.isEmpty) {
      return fallback;
    }

    final stopBookingIds = currentStopBookingIds.toSet();
    for (final booking in poolBookings) {
      if (stopBookingIds.contains(booking.bookingId)) {
        return booking;
      }
    }
    return fallback;
  }

  Widget _buildNavigationInfoCard({
    required BookingModel booking,
    required OperatorNavigationGuidance? guidance,
    required bool passengerPickedUp,
    required bool isLiveLocationStale,
    required OperatorHomeViewModel viewModel,
  }) {
    final hasPausedRecoveryState =
        guidance != null && guidance.shouldPauseProgress;
    final remaining = isLiveLocationStale
        ? 'Waiting for live location'
        : hasPausedRecoveryState
        ? 'Rejoin river route'
        : guidance == null
        ? 'N/A'
        : _formatDistanceMeters(guidance.remainingDistanceMeters);
    final eta = isLiveLocationStale || guidance?.shouldPauseEta == true
        ? 'N/A'
        : guidance?.isEtaLowConfidence == true
        ? '~ ${_formatEta(guidance?.eta)}'
        : _formatEta(guidance?.eta);
    final currentStop = booking.currentPoolStop;
    final isPickupStop = currentStop?.isPickup ?? !passengerPickedUp;
    final nextStop = currentStop == null
        ? null
        : _nextPoolStopAfter(booking.poolStopPlan, currentStop);
    final isGroupedStop = (currentStop?.bookingIds.length ?? 1) > 1;
    final actionLabel = currentStop == null
        ? (passengerPickedUp ? 'Complete Trip' : 'Passenger Picked Up')
        : !isGroupedStop
        ? (isPickupStop ? 'Mark Picked Up' : 'Complete Trip')
        : isPickupStop
        ? 'Complete Pickup Stop'
        : 'Complete Dropoff Stop';

    return OperatorCollapsibleNavigationCard(
      currentStopActionLabel: _formatPoolStopActionLabel(
        currentStop,
        viewModel.activeBookings,
      ),
      currentStopName: currentStop == null
          ? null
          : _poolStopDisplayName(currentStop),
      passengerContextLabel: _formatStopPassengerContext(
        currentStop,
        viewModel.activeBookings,
      ),
      miniTimelineLabel: _formatStopMiniTimeline(currentStop, nextStop),
      routeDirectionLabel: _formatRouteDirectionLabel(booking.routeDirection),
      remaining: remaining,
      eta: eta,
      isUpdating: viewModel.isUpdatingBooking,
      primaryActionLabel: actionLabel,
      routeWarningText: isLiveLocationStale
          ? 'Waiting for fresh GPS.'
          : _criticalRouteWarningText(booking, guidance),
      onPrimaryAction: () async {
        final result = !isPickupStop
            ? await viewModel.completeTrip(booking.bookingId)
            : await viewModel.markPassengerPickedUp(booking.bookingId);
        if (!mounted) {
          return;
        }
        _showStopOperationResult(
          result,
          isPickupStop: isPickupStop,
          currentStop: currentStop,
        );
        if (!isPickupStop && result is OperationSuccess) {
          await _centerOnUser(showFeedback: false);
        }
      },
    );
  }

  String? _formatPoolStopActionLabel(
    PoolStopPlanItem? stop,
    List<BookingModel> poolBookings,
  ) {
    if (stop == null) {
      return null;
    }
    final verb = stop.isPickup ? 'Pick up' : 'Drop off';
    final count = _resolvedStopPassengerCount(stop, poolBookings);
    final noun = count == 1 ? 'passenger' : 'passengers';
    return '$verb $count $noun';
  }

  int _resolvedStopPassengerCount(
    PoolStopPlanItem stop,
    List<BookingModel> poolBookings,
  ) {
    final stopPassengerCount = stop.passengerCount;
    if (stopPassengerCount != null && stopPassengerCount > 0) {
      return stopPassengerCount;
    }
    final stopBookingIds = stop.bookingIds.toSet();
    final count = poolBookings
        .where((booking) => stopBookingIds.contains(booking.bookingId))
        .fold<int>(0, (sum, booking) => sum + booking.passengerCount);
    if (count > 0) {
      return count;
    }
    return stop.bookingIds.isEmpty ? 1 : stop.bookingIds.length;
  }

  String _poolStopDisplayName(PoolStopPlanItem stop) {
    final stopName = stop.stopName.trim();
    if (stopName.isNotEmpty) {
      return stopName;
    }
    final stopJettyId = stop.stopJettyId?.trim();
    if (stopJettyId != null && stopJettyId.isNotEmpty) {
      return stopJettyId;
    }
    return stop.isPickup ? 'pickup stop' : 'dropoff stop';
  }

  PoolStopPlanItem? _nextPoolStopAfter(
    List<PoolStopPlanItem> stops,
    PoolStopPlanItem currentStop,
  ) {
    final currentIndex = stops.indexWhere(
      (stop) => stop.stopId == currentStop.stopId,
    );
    if (currentIndex < 0) {
      return null;
    }
    for (var i = currentIndex + 1; i < stops.length; i++) {
      final stop = stops[i];
      if (stop.status != 'completed' && stop.status != 'skipped') {
        return stop;
      }
    }
    return null;
  }

  String? _formatStopMiniTimeline(
    PoolStopPlanItem? currentStop,
    PoolStopPlanItem? nextStop,
  ) {
    if (currentStop == null) {
      return null;
    }
    final currentName = _poolStopDisplayName(currentStop);
    if (nextStop == null) {
      return '$currentName → Final stop';
    }
    return '$currentName → ${_poolStopDisplayName(nextStop)}';
  }

  String? _formatStopPassengerContext(
    PoolStopPlanItem? stop,
    List<BookingModel> poolBookings,
  ) {
    if (stop == null) {
      return null;
    }
    final passengerCount = _resolvedStopPassengerCount(stop, poolBookings);
    final noun = passengerCount == 1 ? 'passenger' : 'passengers';
    final state = stop.isPickup ? 'waiting' : 'onboard';
    return '$passengerCount $noun $state';
  }

  String? _formatRouteDirectionLabel(String? routeDirection) {
    final normalized = routeDirection?.trim().toLowerCase();
    if (normalized == 'forward') {
      return 'Forward route';
    }
    if (normalized == 'reverse') {
      return 'Reverse route';
    }
    return null;
  }

  Widget _buildPendingBookingCard(
    BookingModel booking,
    int pendingCount,
    OperatorHomeViewModel viewModel,
  ) {
    return OperatorPendingBookingCard(
      booking: booking,
      pendingCount: pendingCount,
      isUpdating: viewModel.isUpdatingBooking,
      detailText: _buildBookingDetailText(booking),
      onCallCustomer: () => _callCustomer(booking),
      onAccept: () async {
        final result = await viewModel.acceptBooking(booking.bookingId);
        if (!mounted) {
          return;
        }
        _showOperationResult(result);
      },
      onReject: () async {
        final result = await viewModel.rejectBooking(booking.bookingId);
        if (!mounted) {
          return;
        }
        _showOperationResult(result);
      },
    );
  }

  String _buildBookingDetailText(BookingModel booking) {
    final fareValue = booking.totalFare;

    return 'Route: ${booking.origin} → ${booking.destination}\n'
        'Passengers: ${booking.passengerCount}\n'
        'Fare: ${fareValue > 0 ? formatCurrency(fareValue) : 'N/A'}\n'
        'Created: ${formatBookingTimestamp(booking.createdAt)}';
  }

  Future<void> _callCustomer(BookingModel booking) async {
    final phone = booking.userPhone.trim();
    if (phone.isEmpty) {
      showTopInfo(
        context,
        title: 'No phone number',
        message: 'This booking does not include a customer phone number.',
      );
      return;
    }

    try {
      final didOpenDialer =
          await _phoneChannel.invokeMethod<bool>('dial', <String, Object>{
            'phone': phone,
          }) ??
          false;
      if (!mounted) {
        return;
      }
      if (!didOpenDialer) {
        showTopInfo(
          context,
          title: 'Unable to open dialer',
          message: 'Please call the customer manually: $phone',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      showTopInfo(
        context,
        title: 'Unable to open dialer',
        message: 'Please call the customer manually: $phone',
      );
    }
  }

  String _formatDistanceMeters(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.round()} m';
  }

  String _formatEta(Duration? eta) {
    if (eta == null) {
      return 'N/A';
    }

    final minutes = eta.inMinutes;
    if (minutes <= 0) {
      return '< 1 min';
    }
    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '$hours h' : '$hours h $rem min';
  }

  void _showOperationResult(OperationResult result) {
    switch (result) {
      case OperationSuccess(:final message):
        showTopSuccess(context, message: message);
      case OperationFailure(:final title, :final message, :final isInfo):
        if (isInfo) {
          showTopInfo(context, title: title, message: message);
        } else {
          showTopError(context, title: title, message: message);
        }
    }
  }

  void _showStopOperationResult(
    OperationResult result, {
    required bool isPickupStop,
    required PoolStopPlanItem? currentStop,
  }) {
    if (result is OperationSuccess && currentStop != null) {
      final count = currentStop.bookingIds.length;
      final bookingText = count <= 1 ? '1 booking' : '$count bookings';
      final stopName = _poolStopDisplayName(currentStop);
      showTopSuccess(
        context,
        message: isPickupStop
            ? 'Picked up $bookingText at $stopName.'
            : 'Dropped off $bookingText at $stopName.',
      );
      return;
    }
    _showOperationResult(result);
  }

  Future<void> _syncNavigationCamera(
    BookingModel? activeBooking, {
    required List<LatLng> routePoints,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
    required bool forceFollow,
  }) async {
    final nextMode = await _mapCameraService.syncNavigationCamera(
      activeBooking,
      routePoints: routePoints,
      operatorPoint: operatorPoint,
      destinationPoint: destinationPoint,
      forceFollow: forceFollow,
    );

    if (mounted && nextMode != _mapCameraService.navigationMode) {
      setState(() {});
    }
  }

  Set<Polyline> _buildMapPolylines(
    BookingModel? activeBooking, {
    required bool passengerPickedUp,
    required OperatorNavigationGuidance? guidance,
    required LatLng? operatorPoint,
  }) {
    final polylines = OperatorMapLayers.buildPolylines(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
      opacity: 1,
    ).toSet();

    final rejoinPoint = guidance?.rejoinPoint;
    if (guidance != null &&
        activeBooking?.currentPoolStop == null &&
        operatorPoint != null &&
        rejoinPoint != null &&
        guidance.offRouteSeverity.index >=
            OperatorOffRouteSeverity.moderate.index) {
      final rejoinLatLng = LatLng(rejoinPoint.lat, rejoinPoint.lng);
      final distanceToRejoin = Geolocator.distanceBetween(
        operatorPoint.latitude,
        operatorPoint.longitude,
        rejoinLatLng.latitude,
        rejoinLatLng.longitude,
      );
      if (distanceToRejoin >= 5) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('route_rejoin_connector'),
            points: <LatLng>[operatorPoint, rejoinLatLng],
            color: const Color(0xFFF97316),
            width: 3,
            patterns: <PatternItem>[PatternItem.dash(18), PatternItem.gap(10)],
          ),
        );
      }
    }

    return polylines;
  }

  String? _criticalRouteWarningText(
    BookingModel booking,
    OperatorNavigationGuidance? guidance,
  ) {
    final currentStop = booking.currentPoolStop;
    final stopName = currentStop == null
        ? 'the current stop'
        : _poolStopDisplayName(currentStop);
    if (guidance?.stopOvershootSeverity ==
        OperatorStopOvershootSeverity.missed) {
      return 'Missed stop. Return to $stopName.';
    }
    if (guidance?.stopOvershootSeverity == OperatorStopOvershootSeverity.soft) {
      return 'Passed stop slightly. Return safely.';
    }
    if (guidance?.offRouteSeverity == OperatorOffRouteSeverity.severe) {
      return 'Too far from river route. Move closer to the river before trusting guidance.';
    }
    return null;
  }

  Future<void> _animateCameraSafely(
    CameraUpdate update, {
    bool allowIfBusy = false,
  }) async {
    await _mapCameraService.animateCameraSafely(
      update,
      allowIfBusy: allowIfBusy,
    );
  }

  Future<Position?> _getUserPositionSafely() async {
    try {
      return await _locationCoordinator.getCurrentPosition();
    } catch (e) {
      developer.log(
        'get_user_position_failed',
        name: 'operator_home_screen',
        error: e,
        stackTrace: StackTrace.current,
      );
      return null;
    }
  }

  bool _shouldPerformLocationLookup() {
    final now = DateTime.now();
    final lastLookup = _lastLocationLookupAt;
    if (lastLookup != null &&
        now.difference(lastLookup) < const Duration(seconds: 2)) {
      return false;
    }
    _lastLocationLookupAt = now;
    return true;
  }

  String _navigationSyncKey(OperatorHomeSnapshot snapshot) {
    final activeBooking = snapshot.activeBooking;
    final operatorPoint = snapshot.operatorPoint;
    final destinationPoint = snapshot.destinationPoint;
    final routePoints = snapshot.routeHealth.routePoints;
    return [
      activeBooking?.bookingId ?? '-',
      activeBooking?.status.firestoreValue ?? '-',
      OperatorMapLayers.routePhaseSignature(
        activeBooking,
        passengerPickedUp: snapshot.passengerPickedUp,
      ),
      OperatorMapLayers.routeGeometrySignature(routePoints),
      snapshot.routeHealth.source.name,
      snapshot.routeHealth.warning ?? '-',
      snapshot.isLiveLocationStale ? '1' : '0',
      snapshot.passengerPickedUp ? '1' : '0',
      operatorPoint?.latitude.toStringAsFixed(5) ?? '-',
      operatorPoint?.longitude.toStringAsFixed(5) ?? '-',
      destinationPoint?.latitude.toStringAsFixed(5) ?? '-',
      destinationPoint?.longitude.toStringAsFixed(5) ?? '-',
      snapshot.pendingCount.toString(),
      snapshot.topPendingBooking?.bookingId ?? '-',
      snapshot.navigationGuidance?.nearestRouteMarker.toString() ?? '-',
      snapshot.navigationGuidance?.isOffRoute == true ? '1' : '0',
      snapshot.navigationGuidance?.progressFraction.toStringAsFixed(2) ?? '-',
      snapshot.navigationGuidance?.offRouteSeverity.name ?? '-',
      snapshot.navigationGuidance?.headingDegrees?.toStringAsFixed(1) ?? '-',
      snapshot.navigationGuidance?.rejoinPoint?.lat.toStringAsFixed(5) ?? '-',
      snapshot.navigationGuidance?.rejoinPoint?.lng.toStringAsFixed(5) ?? '-',
    ].join('|');
  }

  Widget _buildMap(
    BuildContext context,
    BookingModel? activeBooking,
    OperatorHomeSnapshot snapshot,
    List<LatLng> trimmedRoutePoints,
  ) {
    final operatorPoint = snapshot.operatorPoint;
    final destinationPoint = snapshot.destinationPoint;

    Widget buildMapContent(ValueChanged<GoogleMapController> onMapCreated) {
      if (widget.mapBuilder != null) {
        return widget.mapBuilder!.call(
          initialCameraPosition: _initialCameraPosition,
          hasLocationPermission: _hasLocationPermission,
          onMapCreated: onMapCreated,
        );
      }

      return AnimatedBuilder(
        animation: _routeTransitionController,
        builder: (context, _) {
          return GoogleMap(
            key: const ValueKey('operator-map'),
            initialCameraPosition: _initialCameraPosition,
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: OperatorMapLayers.buildMarkers(
              activeBooking,
              operatorPoint: operatorPoint,
              operatorHeading: snapshot.navigationGuidance?.headingDegrees,
            ),
            polylines: _buildMapPolylines(
              activeBooking,
              passengerPickedUp: snapshot.passengerPickedUp,
              guidance: snapshot.navigationGuidance,
              operatorPoint: operatorPoint,
            ),
            onMapCreated: onMapCreated,
            onCameraMove: _mapCameraService.handleCameraMove,
            onCameraMoveStarted: () {
              if (_mapCameraService.currentState.isProgrammaticCameraMove ||
                  activeBooking == null ||
                  !OperatorMapLayers.isActiveNavigationBooking(activeBooking)) {
                return;
              }
              _mapCameraService.handleCameraMoveStarted(
                shouldYieldToUser: true,
              );
            },
            onCameraIdle: _mapCameraService.handleCameraIdle,
          );
        },
      );
    }

    return Positioned.fill(
      child: buildMapContent((GoogleMapController controller) {
        _mapCameraService.attachMapController(controller);
        _mapCameraService.updateCameraBoundsPadding(_cameraBoundsPadding);
        unawaited(
          _syncNavigationCamera(
            activeBooking,
            routePoints: trimmedRoutePoints,
            operatorPoint: operatorPoint,
            destinationPoint: destinationPoint,
            forceFollow: false,
          ),
        );
      }),
    );
  }

  Widget _buildOverlayUI(
    BuildContext context,
    String? operatorId,
    OperatorHomeViewModel viewModel,
    OperatorBookingCardSnapshot cardSnapshot,
    OperatorHomeSnapshot navigationSnapshot,
  ) {
    if (operatorId == null) {
      return const SizedBox.shrink();
    }
    final topInset = MediaQuery.paddingOf(context).top;

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: topInset + 12,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cardSnapshot.isOnline) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.80,
                    ),
                    child: _buildBookingActionCard(
                      operatorId,
                      viewModel,
                      cardSnapshot,
                      navigationSnapshot,
                    ),
                  ),
                ] else ...[
                  const OperatorInfoCard(
                    icon: Icons.power_settings_new,
                    iconColor: Colors.red,
                    title: 'You are offline',
                    subtitle:
                        'Go online to view active trips and pending booking queue.',
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: (cardSnapshot.isToggling || _isInitializingViewModel)
                    ? null
                    : _toggleStatus,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cardSnapshot.isOnline
                      ? Colors.red
                      : _goOnlineGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: cardSnapshot.isToggling
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.power_settings_new),
                label: Text(
                  cardSnapshot.isOnline ? 'Go Offline' : 'Go Online',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBarScrim(BuildContext context) {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    if (statusBarHeight <= 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: statusBarHeight + 6,
      child: IgnorePointer(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.46),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _brandOrange.withValues(alpha: 0.06),
                    _brandMagenta.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingButtons(
    BookingModel? activeBooking,
    List<LatLng> trimmedRoutePoints,
    LatLng? operatorPoint,
    LatLng? destinationPoint,
  ) {
    return Positioned(
      bottom: 100,
      right: 16,
      child: ValueListenableBuilder<MapCameraState>(
        valueListenable: _mapCameraService.state,
        builder: (context, cameraState, _) {
          final isActiveNavigation =
              activeBooking != null &&
              OperatorMapLayers.isActiveNavigationBooking(activeBooking);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  bottom:
                      (isActiveNavigation &&
                          cameraState.showRecenterButton &&
                          operatorPoint != null)
                      ? 8
                      : 0,
                ),
                child: FloatingActionButton.small(
                  heroTag: 'toggle_camera_tilt',
                  backgroundColor: Colors.white,
                  foregroundColor: OperatorBrand.magenta,
                  onPressed: () {
                    unawaited(_mapCameraService.toggleMapTilt());
                  },
                  child: Text(
                    cameraState.isNavigationTilt3d ? '2D' : '3D',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              if (isActiveNavigation &&
                  cameraState.showRecenterButton &&
                  operatorPoint != null)
                FloatingActionButton(
                  heroTag: 'resume_navigation',
                  backgroundColor: OperatorBrand.magenta,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    unawaited(
                      _syncNavigationCamera(
                        activeBooking,
                        routePoints: trimmedRoutePoints,
                        operatorPoint: operatorPoint,
                        destinationPoint: destinationPoint,
                        forceFollow: true,
                      ),
                    );
                  },
                  child: const Icon(Icons.near_me),
                ),
              if (!isActiveNavigation)
                FloatingActionButton(
                  heroTag: 'center_on_user',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  onPressed: _centerOnUser,
                  child: const Icon(Icons.near_me),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _cameraBoundsPadding = MediaQuery.sizeOf(context).width * 0.2;
    final operatorId = _operatorId;
    final snapshot = context
        .select<OperatorHomeViewModel, OperatorHomeSnapshot>(
          (viewModel) => viewModel.homeSnapshot,
        );
    final cardSnapshot = context
        .select<OperatorHomeViewModel, OperatorBookingCardSnapshot>(
          (viewModel) => viewModel.bookingCardSnapshot,
        );
    final viewModel = context.read<OperatorHomeViewModel>();
    final activeBooking = snapshot.activeBooking;
    final trimmedRoutePoints = OperatorMapLayers.trimmedRoutePointsForCamera(
      activeBooking,
      passengerPickedUp: snapshot.passengerPickedUp,
      operatorPoint: snapshot.operatorPoint,
    );
    final isLoading = _isInitializingViewModel;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: operatorId == null
            ? const Center(child: Text('Not signed in'))
            : Stack(
                fit: StackFit.expand,
                children: [
                  _buildMap(
                    context,
                    activeBooking,
                    snapshot,
                    trimmedRoutePoints,
                  ),
                  _buildStatusBarScrim(context),
                  if (isLoading)
                    const Positioned.fill(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  _buildOverlayUI(
                    context,
                    operatorId,
                    viewModel,
                    cardSnapshot,
                    snapshot,
                  ),
                  _buildFloatingButtons(
                    activeBooking,
                    trimmedRoutePoints,
                    snapshot.operatorPoint,
                    snapshot.destinationPoint,
                  ),
                ],
              ),
      ),
    );
  }
}
