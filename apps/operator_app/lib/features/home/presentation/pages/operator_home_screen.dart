import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/home/presentation/location/operator_location_coordinator.dart';
import 'package:operator_app/features/home/presentation/map/operator_map_layers.dart';
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
  static const MethodChannel _mapsConfigChannel = MethodChannel(
    'operator_app/maps_config',
  );

  bool _hasLocationPermission = false;
  bool _hasShownWelcomeAlert = false;
  bool _hasCheckedMapsConfig = false;
  bool _isInitializingViewModel = false;
  StreamSubscription<User?>? _authSubscription;
  DateTime? _lastRecoveryAttempt;
  DateTime? _lastLocationLookupAt;
  String? _lastNavigationSyncKey;
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

    unawaited(_initializeViewModel(operatorId, force: true));
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
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
      destinationPoint: snapshot.destinationPoint,
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

    setState(() => _isInitializingViewModel = true);

    try {
      await context
          .read<OperatorHomeViewModel>()
          .ensureInitialized(operatorId, force: force);
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

  Future<void> _centerOnUser() async {
    if (!_mapCameraService.currentState.isMapReady) {
      showTopInfo(
        context,
        message: 'Map is still loading.',
        title: 'Please wait',
      );
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
      showTopError(
        context,
        message: 'Unable to get location: $e',
        title: 'Location error',
      );
    }
  }

  Future<void> _toggleStatus() async {
    final result = await context
        .read<OperatorHomeViewModel>()
        .toggleOnlineStatus();
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
  ) {
    final activeBooking = viewModel.activeBookings.isNotEmpty
        ? viewModel.activeBookings.first
        : null;
    final pendingBookings = viewModel.visiblePendingBookings(operatorId);
    final topPendingBooking = pendingBookings.isNotEmpty
        ? pendingBookings.first
        : null;
    final pendingCount = pendingBookings.length;
    final activeCount = activeBooking == null ? 0 : 1;
    final guidance = viewModel.navigationGuidance;
    final isOnTheWay =
        activeBooking != null && activeBooking.status == BookingStatus.onTheWay;
    final passengerPickedUp =
        activeBooking != null && _isPassengerPickedUp(activeBooking);
    final bookingGuidance =
        isOnTheWay &&
            guidance != null &&
            guidance.bookingId == activeBooking.bookingId
        ? guidance
        : null;

    return KeyedSubtree(
      key: ValueKey('booking-actions-${viewModel.streamVersion}'),
      child: RefreshIndicator(
        onRefresh: () => _refreshBookingData(operatorId),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                isRefreshing: viewModel.isRefreshing,
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: activeBooking != null
                      ? _buildActiveBookingCard(activeBooking, viewModel)
                      : const OperatorInfoCard(
                          icon: Icons.directions_boat_filled_outlined,
                          iconColor: Color(0xFF0066CC),
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
                    viewModel: viewModel,
                  ),
                ),
            ],
          ),
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
      onStartTrip: () async {
        final result = await viewModel.startTrip(booking.bookingId);
        if (!mounted) {
          return;
        }
        _showOperationResult(result);
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

  Widget _buildNavigationInfoCard({
    required BookingModel booking,
    required OperatorNavigationGuidance? guidance,
    required bool passengerPickedUp,
    required OperatorHomeViewModel viewModel,
  }) {
    final progressPercent = guidance == null
        ? null
        : (guidance.progressFraction * 100).round();
    final remaining = guidance == null
        ? 'N/A'
        : _formatDistanceMeters(guidance.remainingDistanceMeters);
    final offRoute = guidance == null
        ? 'N/A'
        : _formatDistanceMeters(guidance.offRouteDistanceMeters);
    final eta = _formatEta(guidance?.eta);

    return OperatorCollapsibleNavigationCard(
      progressLabel: progressPercent == null ? '...' : '$progressPercent%',
      remaining: remaining,
      eta: eta,
      nextMarkerText: guidance == null
          ? 'Getting navigation guidance...'
          : 'Next marker: ${guidance.nextRouteMarker} / ${guidance.totalRouteMarkers}',
      offRouteText: guidance?.isOffRoute == true
          ? 'Off-route warning: approx $offRoute away from planned route.'
          : null,
      isUpdating: viewModel.isUpdatingBooking,
      primaryActionLabel: passengerPickedUp
          ? 'Complete Trip'
          : 'Passenger Picked Up',
      onPrimaryAction: () async {
        final result = passengerPickedUp
            ? await viewModel.completeTrip(booking.bookingId)
            : await viewModel.markPassengerPickedUp(booking.bookingId);
        if (!mounted) {
          return;
        }
        _showOperationResult(result);
      },
    );
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

    return 'Booking ID: ${booking.bookingId}\n'
        'Route: ${booking.origin} -> ${booking.destination}\n'
        'Passengers: ${booking.passengerCount}\n'
        'Fare: ${fareValue > 0 ? formatCurrency(fareValue) : 'N/A'}\n'
        'Created: ${formatBookingTimestamp(booking.createdAt)}';
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
    required List<LatLng> routePoints,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
    required bool passengerPickedUp,
  }) {
    return OperatorMapLayers.buildPolylines(
      activeBooking,
      routePointsOverride: routePoints,
      opacity: 1,
    );
  }

  bool _isPassengerPickedUp(BookingModel booking) {
    return booking.passengerPickedUpAt != null;
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
    if (lastLookup != null && now.difference(lastLookup) < const Duration(seconds: 2)) {
      return false;
    }
    _lastLocationLookupAt = now;
    return true;
  }

  String _navigationSyncKey(OperatorHomeSnapshot snapshot) {
    final activeBooking = snapshot.activeBooking;
    final operatorPoint = snapshot.operatorPoint;
    final destinationPoint = snapshot.destinationPoint;
    return [
      activeBooking?.bookingId ?? '-',
      activeBooking?.status.firestoreValue ?? '-',
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
            markers: OperatorMapLayers.buildMarkers(activeBooking),
            polylines: _buildMapPolylines(
              activeBooking,
              routePoints: trimmedRoutePoints,
              operatorPoint: operatorPoint,
              destinationPoint: destinationPoint,
              passengerPickedUp: snapshot.passengerPickedUp,
            ),
            onMapCreated: onMapCreated,
            onCameraMoveStarted: () {
              if (_mapCameraService.currentState.isProgrammaticCameraMove ||
                  activeBooking == null ||
                  !OperatorMapLayers.isActiveNavigationBooking(
                    activeBooking,
                  )) {
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
  ) {
    if (operatorId == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (viewModel.isOnline) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.80,
                    ),
                    child: _buildBookingActionCard(
                      operatorId,
                      viewModel,
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
                onPressed: (viewModel.isToggling || _isInitializingViewModel)
                    ? null
                    : _toggleStatus,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      viewModel.isOnline ? Colors.red : const Color(0xFF0066CC),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: viewModel.isToggling
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
                  viewModel.isOnline ? 'Go Offline' : 'Go Online',
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (cameraState.showRecenterButton && operatorPoint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FloatingActionButton.small(
                    heroTag: 'resume_follow',
                    backgroundColor: const Color(0xFF0066CC),
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
                    child: const Icon(Icons.my_location),
                  ),
                ),
              FloatingActionButton(
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
    final snapshot = context.select<OperatorHomeViewModel, OperatorHomeSnapshot>(
      (viewModel) => viewModel.homeSnapshot,
    );
    final viewModel = context.read<OperatorHomeViewModel>();
    final activeBooking = snapshot.activeBooking;
    final trimmedRoutePoints = OperatorMapLayers.trimmedRoutePointsForCamera(
      activeBooking,
      passengerPickedUp: snapshot.passengerPickedUp,
      operatorPoint: snapshot.operatorPoint,
      destinationPoint: snapshot.destinationPoint,
    );
    final isLoading = _isInitializingViewModel;

    return Scaffold(
      appBar: AppBar(toolbarHeight: 0, elevation: 0),
      body: operatorId == null
          ? const Center(child: Text('Not signed in'))
          : Stack(
              children: [
                _buildMap(
                  context,
                  activeBooking,
                  snapshot,
                  trimmedRoutePoints,
                ),
                if (isLoading)
                  const Positioned.fill(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                _buildOverlayUI(context, operatorId, viewModel),
                _buildFloatingButtons(
                  activeBooking,
                  trimmedRoutePoints,
                  snapshot.operatorPoint,
                  snapshot.destinationPoint,
                ),
              ],
            ),
    );
  }
}
