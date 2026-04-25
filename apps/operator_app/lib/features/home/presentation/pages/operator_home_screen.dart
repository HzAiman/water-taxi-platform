import 'dart:async';
import 'dart:math' as math;

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
import 'package:operator_app/features/home/presentation/widgets/operator_info_card.dart';
import 'package:operator_app/features/home/presentation/widgets/operator_stat_tile.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

enum _MapNavigationMode { overview, tracking, userControlled }

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
    with WidgetsBindingObserver {
  static const MethodChannel _mapsConfigChannel = MethodChannel(
    'operator_app/maps_config',
  );

  bool _hasLocationPermission = false;
  bool _hasShownWelcomeAlert = false;
  bool _hasCheckedMapsConfig = false;
  bool _mapReady = false;
  bool _isInitializingViewModel = false;
  bool _hasInitializedViewModel = false;
  StreamSubscription<User?>? _authSubscription;
  DateTime? _lastRecoveryAttempt;
  String? _lastScheduledCameraSyncSignature;
  String? _lastCameraBoundsSignature;
  LatLng? _lastFollowOperatorPoint;
  DateTime? _lastFollowAt;
  bool _isProgrammaticCameraMove = false;
  _MapNavigationMode _mapNavigationMode = _MapNavigationMode.overview;
  OperatorHomeViewModel? _observedViewModel;
  bool _isActiveSectionExpanded = false;
  bool _isQueueSectionExpanded = false;
  final Set<String> _pickedUpBookingIds = <String>{};
  final OperatorLocationCoordinator _locationCoordinator =
      const OperatorLocationCoordinator();

  static const Duration _followRecenterInterval = Duration(seconds: 4);
  static const double _followRecenterDistanceMeters = 20;
  static const double _cameraBoundsPadding = 180;

  late GoogleMapController _mapController;
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

    _authSubscription = FirebaseAuth.instance.idTokenChanges().listen((user) {
      if (!mounted || _hasInitializedViewModel || user == null) {
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

    _observedViewModel?.removeListener(_onViewModelChanged);
    _observedViewModel = viewModel;
    _observedViewModel?.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _observedViewModel?.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    final viewModel = _observedViewModel;
    if (!mounted || viewModel == null) {
      return;
    }

    final activeBooking = viewModel.activeBookings.isNotEmpty
        ? viewModel.activeBookings.first
        : null;
    _pickedUpBookingIds.removeWhere(
      (id) => !viewModel.activeBookings.any(
        (b) => b.bookingId == id && b.status == BookingStatus.onTheWay,
      ),
    );
    for (final booking in viewModel.activeBookings) {
      if (booking.status == BookingStatus.onTheWay &&
          booking.passengerPickedUpAt != null) {
        _pickedUpBookingIds.add(booking.bookingId);
      }
    }

    final passengerPickedUp =
        activeBooking != null && _isPassengerPickedUp(activeBooking);
    final operatorPoint = _operatorPointForBooking(activeBooking);
    final destinationPoint = activeBooking == null
        ? null
        : _latLngOrNull(
            activeBooking.destinationLat,
            activeBooking.destinationLng,
          );
    final trimmedRoutePoints = _trimmedRoutePointsForCamera(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
      destinationPoint: destinationPoint,
    );

    _scheduleMapCameraSync(
      activeBooking,
      routePoints: trimmedRoutePoints,
      operatorPoint: operatorPoint,
      destinationPoint: destinationPoint,
    );
  }

  Future<void> _initializeViewModel(
    String operatorId, {
    bool force = false,
  }) async {
    if ((_hasInitializedViewModel && !force) || !mounted) {
      return;
    }

    _hasInitializedViewModel = true;
    setState(() => _isInitializingViewModel = true);

    try {
      await context.read<OperatorHomeViewModel>().initialize(operatorId);
    } catch (e) {
      if (mounted) {
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
    final access = await _resolveLocationAccess();
    if (access != OperatorLocationAccess.granted) {
      return;
    }

    try {
      final pos = await _locationCoordinator.getCurrentPosition();
      if (!mounted) {
        return;
      }

      setState(() {
        _initialCameraPosition = CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 16,
        );
      });

      if (_mapReady) {
        await _mapController.animateCamera(
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
    if (!_mapReady) {
      showTopInfo(
        context,
        message: 'Map is still loading.',
        title: 'Please wait',
      );
      return;
    }

    final access = await _resolveLocationAccess();
    if (access != OperatorLocationAccess.granted) {
      return;
    }

    try {
      final pos = await _locationCoordinator.getCurrentPosition();
      if (!mounted) {
        return;
      }
      await _mapController.animateCamera(
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
              _buildStatsCard(
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

  Widget _buildStatsCard({
    required int pendingCount,
    required int activeCount,
    required bool isQueueExpanded,
    required bool isActiveExpanded,
    required VoidCallback onPendingTap,
    required VoidCallback onActiveTap,
    required bool isRefreshing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OperatorStatTile(
              label: 'Pending Queue',
              value: pendingCount.toString(),
              color: Colors.orange,
              isExpanded: isQueueExpanded,
              onTap: onPendingTap,
            ),
          ),
          if (isRefreshing) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          Container(width: 1, height: 36, color: Colors.grey[300]),
          Expanded(
            child: OperatorStatTile(
              label: 'Active Trip',
              value: activeCount.toString(),
              color: const Color(0xFF0066CC),
              isExpanded: isActiveExpanded,
              onTap: onActiveTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBookingCard(
    BookingModel booking,
    OperatorHomeViewModel viewModel,
  ) {
    final status = booking.status;
    final isAccepted = status == BookingStatus.accepted;
    final isOnTheWay = status == BookingStatus.onTheWay;
    final isStale = isAcceptedBookingStale(booking);
    final actionColor = isAccepted ? const Color(0xFF0066CC) : Colors.green;
    final detailText = _buildBookingDetailText(booking);

    var subtitle = detailText;
    if (isStale) {
      subtitle =
          '$subtitle\n\nThis accepted booking looks stale. Start the trip or release it back to the queue.';
    }

    return OperatorInfoCard(
      icon: isAccepted ? Icons.directions_boat : Icons.route,
      iconColor: actionColor,
      title: 'Current Booking: ${formatStatusLabel(status.firestoreValue)}',
      subtitle: subtitle,
      actionLabel: isAccepted ? 'Start Trip' : null,
      actionColor: actionColor,
      secondaryActionLabel: isAccepted ? 'Release' : null,
      secondaryActionColor: const Color(0xFFFFF1F1),
      secondaryActionTextColor: const Color(0xFFB42318),
      showActionLoading: viewModel.isUpdatingBooking,
      onAction: viewModel.isUpdatingBooking || isOnTheWay
          ? null
          : () async {
              final result = await viewModel.startTrip(booking.bookingId);
              if (!mounted) {
                return;
              }
              _showOperationResult(result);
            },
      onSecondaryAction: viewModel.isUpdatingBooking || !isAccepted
          ? null
          : () async {
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

    return _CollapsibleNavigationCard(
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
        if (result is OperationSuccess && !passengerPickedUp) {
          setState(() {
            _pickedUpBookingIds.add(booking.bookingId);
          });
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
    return OperatorInfoCard(
      icon: Icons.notifications_active,
      iconColor: Colors.orange,
      title: pendingCount > 1
          ? 'Next Pending Booking ($pendingCount in queue)'
          : 'Next Pending Booking',
      subtitle: _buildBookingDetailText(booking),
      actionLabel: 'Accept Booking',
      actionColor: const Color(0xFF0066CC),
      secondaryActionLabel: 'Reject',
      secondaryActionColor: Colors.orange.shade50,
      secondaryActionTextColor: Colors.orange.shade900,
      showActionLoading: viewModel.isUpdatingBooking,
      onAction: viewModel.isUpdatingBooking
          ? null
          : () async {
              final result = await viewModel.acceptBooking(booking.bookingId);
              if (!mounted) {
                return;
              }
              _showOperationResult(result);
            },
      onSecondaryAction: viewModel.isUpdatingBooking
          ? null
          : () async {
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

  void _scheduleMapCameraSync(
    BookingModel? activeBooking, {
    required List<LatLng> routePoints,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
    bool forceFollow = false,
  }) {
    if (!_mapReady || !mounted || widget.mapBuilder != null) {
      return;
    }

    final nextMode = _resolveMapNavigationMode(
      activeBooking,
      operatorPoint: operatorPoint,
    );

    if (!forceFollow && _mapNavigationMode != nextMode) {
      setState(() {
        _mapNavigationMode = nextMode;
      });
    } else {
      _mapNavigationMode = nextMode;
    }

    if (activeBooking == null) {
      _lastScheduledCameraSyncSignature = null;
      _lastCameraBoundsSignature = null;
      _lastFollowOperatorPoint = null;
      _lastFollowAt = null;
    }

    final syncSignature =
        'm=${_mapNavigationMode.name}|f=${forceFollow ? 1 : 0}|${_cameraSyncScheduleSignature(bookingId: activeBooking?.bookingId, status: activeBooking?.status, routePoints: routePoints, operatorPoint: operatorPoint, destinationPoint: destinationPoint)}';
    if (_lastScheduledCameraSyncSignature == syncSignature) {
      return;
    }
    _lastScheduledCameraSyncSignature = syncSignature;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_mapReady) {
        return;
      }
      await _runCameraByMode(
        activeBooking,
        routePoints: routePoints,
        operatorPoint: operatorPoint,
        destinationPoint: destinationPoint,
        forceFollow: forceFollow,
      );
    });
  }

  _MapNavigationMode _resolveMapNavigationMode(
    BookingModel? activeBooking, {
    required LatLng? operatorPoint,
  }) {
    if (activeBooking == null ||
        activeBooking.status != BookingStatus.onTheWay ||
        operatorPoint == null) {
      return _MapNavigationMode.overview;
    }

    if (_mapNavigationMode == _MapNavigationMode.userControlled) {
      return _MapNavigationMode.userControlled;
    }

    return _MapNavigationMode.tracking;
  }

  Future<void> _runCameraByMode(
    BookingModel? activeBooking, {
    required List<LatLng> routePoints,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
    required bool forceFollow,
  }) async {
    if (!_mapReady) {
      return;
    }

    switch (_mapNavigationMode) {
      case _MapNavigationMode.userControlled:
        return;
      case _MapNavigationMode.tracking:
        if (operatorPoint == null) {
          return;
        }
        await _followOperatorWithPolicy(
          operatorPoint,
          forceFollow: forceFollow,
        );
        return;
      case _MapNavigationMode.overview:
        await _runOverviewCamera(
          activeBooking,
          routePoints: routePoints,
          operatorPoint: operatorPoint,
          destinationPoint: destinationPoint,
        );
        return;
    }
  }

  Future<void> _runOverviewCamera(
    BookingModel? activeBooking, {
    required List<LatLng> routePoints,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
  }) async {
    if (activeBooking == null) {
      return;
    }

    final fitPoints = <LatLng>[
      ...routePoints,
      if (destinationPoint != null) destinationPoint,
    ];

    if (fitPoints.length < 2) {
      if (operatorPoint != null) {
        await _mapController.animateCamera(
          CameraUpdate.newLatLngZoom(operatorPoint, 16),
        );
      }
      return;
    }

    final signature = _cameraBoundsSignature(
      bookingId: activeBooking.bookingId,
      routePoints: routePoints,
      destinationPoint: destinationPoint,
      padding: _cameraBoundsPadding,
    );

    if (_lastCameraBoundsSignature == signature) {
      return;
    }

    await _animateToBounds(_boundsFromPoints(fitPoints), _cameraBoundsPadding);
    _lastCameraBoundsSignature = signature;
  }

  Future<void> _followOperatorWithPolicy(
    LatLng operatorPoint, {
    required bool forceFollow,
  }) async {
    final lastPoint = _lastFollowOperatorPoint;
    final lastAt = _lastFollowAt;
    final shouldFollow =
        forceFollow ||
        lastPoint == null ||
        lastAt == null ||
        DateTime.now().difference(lastAt) >= _followRecenterInterval ||
        _distanceMeters(lastPoint, operatorPoint) >=
            _followRecenterDistanceMeters;

    if (!shouldFollow) {
      return;
    }

    try {
      _isProgrammaticCameraMove = true;
      await _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(operatorPoint, 16),
      );
      _lastFollowOperatorPoint = operatorPoint;
      _lastFollowAt = DateTime.now();
    } catch (_) {
      // Ignore camera failures; next sync can recover.
    }
  }

  LatLng? _operatorPointForBooking(BookingModel? booking) {
    if (booking == null || booking.status != BookingStatus.onTheWay) {
      return null;
    }
    final lat = booking.operatorLat;
    final lng = booking.operatorLng;
    if (lat == null || lng == null) {
      return null;
    }
    return _latLngOrNull(lat, lng);
  }

  List<LatLng> _trimmedRoutePointsForCamera(
    BookingModel? booking, {
    required bool passengerPickedUp,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
  }) {
    if (booking == null) {
      return const <LatLng>[];
    }

    // For onTheWay status, select appropriate phase polyline:
    // - Pre-pickup (phase 1): routeToOriginPolyline (operator -> origin/pickup)
    // - Post-pickup (phase 2): routeToDestinationPolyline (pickup location -> destination)
    final phasePoints = booking.status == BookingStatus.onTheWay
        ? (passengerPickedUp
              ? booking.routeToDestinationPolyline
              : booking.routeToOriginPolyline)
        : booking.routePolyline;

    // Fallback chain for missing polylines:
    // 1. Try phase-specific polyline (preferred - has detailed routing)
    // 2. Try full route polyline (may show wrong direction but better than nothing)
    // 3. Use operator location marker for visibility
    final fallbackPoints = booking.status == BookingStatus.onTheWay
        ? (phasePoints.isEmpty
              ? booking.routePolyline
              : const <BookingRoutePoint>[])
        : const <BookingRoutePoint>[];

    final points = (phasePoints.isNotEmpty ? phasePoints : fallbackPoints)
        .map((p) => _latLngOrNull(p.lat, p.lng))
        .whereType<LatLng>()
        .toList(growable: false);

    // If we still have no polyline but have operator location, include it for map visibility
    if (points.isEmpty && operatorPoint != null) {
      return <LatLng>[operatorPoint];
    }

    return points;
  }

  bool _isPassengerPickedUp(BookingModel booking) {
    return booking.passengerPickedUpAt != null ||
        _pickedUpBookingIds.contains(booking.bookingId);
  }

  LatLng? _latLngOrNull(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) {
      return null;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return null;
    }
    if (lat == 0 && lng == 0) {
      return null;
    }
    return LatLng(lat, lng);
  }

  Future<void> _animateToBounds(LatLngBounds bounds, double padding) async {
    try {
      await _mapController.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      try {
        await _mapController.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, padding),
        );
      } catch (_) {
        // Ignore bounds-fit failure and keep current camera.
      }
    }
  }

  String _cameraBoundsSignature({
    required String bookingId,
    required List<LatLng> routePoints,
    required LatLng? destinationPoint,
    required double padding,
  }) {
    final buffer = StringBuffer(bookingId)
      ..write('|pad=${padding.toStringAsFixed(0)}');

    for (final p in routePoints) {
      buffer
        ..write('|')
        ..write(p.latitude.toStringAsFixed(4))
        ..write(',')
        ..write(p.longitude.toStringAsFixed(4));
    }
    if (destinationPoint != null) {
      buffer
        ..write('|d=')
        ..write(destinationPoint.latitude.toStringAsFixed(4))
        ..write(',')
        ..write(destinationPoint.longitude.toStringAsFixed(4));
    }
    return buffer.toString();
  }

  String _cameraSyncScheduleSignature({
    required String? bookingId,
    required BookingStatus? status,
    required List<LatLng> routePoints,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
  }) {
    final buffer = StringBuffer(bookingId ?? 'none')
      ..write('|s=${status?.firestoreValue ?? 'none'}')
      ..write('|r=${routePoints.length}');

    if (routePoints.isNotEmpty) {
      final first = routePoints.first;
      final last = routePoints.last;
      buffer
        ..write('|rf=')
        ..write(first.latitude.toStringAsFixed(4))
        ..write(',')
        ..write(first.longitude.toStringAsFixed(4))
        ..write('|rl=')
        ..write(last.latitude.toStringAsFixed(4))
        ..write(',')
        ..write(last.longitude.toStringAsFixed(4));
    }

    if (operatorPoint != null) {
      buffer
        ..write('|o=')
        ..write(operatorPoint.latitude.toStringAsFixed(4))
        ..write(',')
        ..write(operatorPoint.longitude.toStringAsFixed(4));
    }

    if (destinationPoint != null) {
      buffer
        ..write('|d=')
        ..write(destinationPoint.latitude.toStringAsFixed(4))
        ..write(',')
        ..write(destinationPoint.longitude.toStringAsFixed(4));
    }

    return buffer.toString();
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  double _distanceMeters(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final operatorId = _operatorId;
    final viewModel = context.watch<OperatorHomeViewModel>();
    final activeBooking = viewModel.activeBookings.isNotEmpty
        ? viewModel.activeBookings.first
        : null;
    final passengerPickedUp =
        activeBooking != null && _isPassengerPickedUp(activeBooking);
    final operatorPoint = _operatorPointForBooking(activeBooking);
    final destinationPoint = activeBooking == null
        ? null
        : _latLngOrNull(
            activeBooking.destinationLat,
            activeBooking.destinationLng,
          );
    final trimmedRoutePoints = _trimmedRoutePointsForCamera(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
      destinationPoint: destinationPoint,
    );
    final isLoading = _isInitializingViewModel;

    return Scaffold(
      appBar: AppBar(toolbarHeight: 0, elevation: 0),
      body: operatorId == null
          ? const Center(child: Text('Not signed in'))
          : Stack(
              children: [
                Positioned.fill(
                  child:
                      widget.mapBuilder?.call(
                        initialCameraPosition: _initialCameraPosition,
                        hasLocationPermission: _hasLocationPermission,
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
                          _mapReady = true;
                        },
                      ) ??
                      GoogleMap(
                        key: const ValueKey('operator-map'),
                        initialCameraPosition: _initialCameraPosition,
                        myLocationEnabled: _hasLocationPermission,
                        myLocationButtonEnabled: false,
                        compassEnabled: true,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        markers: OperatorMapLayers.buildMarkers(activeBooking),
                        polylines: OperatorMapLayers.buildPolylines(
                          activeBooking,
                          routePointsOverride: trimmedRoutePoints,
                        ),
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
                          _mapReady = true;
                          _scheduleMapCameraSync(
                            activeBooking,
                            routePoints: trimmedRoutePoints,
                            operatorPoint: operatorPoint,
                            destinationPoint: destinationPoint,
                          );
                        },
                        onCameraMoveStarted: () {
                          if (_isProgrammaticCameraMove ||
                              activeBooking == null ||
                              activeBooking.status != BookingStatus.onTheWay) {
                            return;
                          }
                          if (_mapNavigationMode ==
                              _MapNavigationMode.tracking) {
                            setState(() {
                              _mapNavigationMode =
                                  _MapNavigationMode.userControlled;
                            });
                          }
                        },
                        onCameraIdle: () {
                          _isProgrammaticCameraMove = false;
                        },
                      ),
                ),
                if (isLoading)
                  const Positioned.fill(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                Positioned.fill(
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
                                  maxHeight:
                                      MediaQuery.sizeOf(context).height * 0.80,
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
                            onPressed: (viewModel.isToggling || isLoading)
                                ? null
                                : _toggleStatus,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: viewModel.isOnline
                                  ? Colors.red
                                  : const Color(0xFF0066CC),
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
                ),
                Positioned(
                  bottom: 100,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_mapNavigationMode ==
                              _MapNavigationMode.userControlled &&
                          operatorPoint != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FloatingActionButton.small(
                            heroTag: 'resume_follow',
                            backgroundColor: const Color(0xFF0066CC),
                            foregroundColor: Colors.white,
                            onPressed: () async {
                              setState(() {
                                _mapNavigationMode =
                                    _MapNavigationMode.tracking;
                              });
                              _scheduleMapCameraSync(
                                activeBooking,
                                routePoints: trimmedRoutePoints,
                                operatorPoint: operatorPoint,
                                destinationPoint: destinationPoint,
                                forceFollow: true,
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
                  ),
                ),
              ],
            ),
    );
  }
}

class _CollapsibleNavigationCard extends StatefulWidget {
  const _CollapsibleNavigationCard({
    required this.progressLabel,
    required this.remaining,
    required this.eta,
    required this.nextMarkerText,
    required this.offRouteText,
    required this.isUpdating,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
  });

  final String progressLabel;
  final String remaining;
  final String eta;
  final String nextMarkerText;
  final String? offRouteText;
  final bool isUpdating;
  final String primaryActionLabel;
  final Future<void> Function() onPrimaryAction;

  @override
  State<_CollapsibleNavigationCard> createState() =>
      _CollapsibleNavigationCardState();
}

class _CollapsibleNavigationCardState
    extends State<_CollapsibleNavigationCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.navigation,
                    color: Color(0xFF0066CC),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Navigation',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[900],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.progressLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0066CC),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[700],
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.remaining}  •  ETA ${widget.eta}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildNavigationMetric('Remaining', widget.remaining),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildNavigationMetric('ETA', widget.eta)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.nextMarkerText,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.offRouteText != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.offRouteText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A3412),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.isUpdating
                    ? null
                    : () => unawaited(widget.onPrimaryAction()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: widget.isUpdating
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
                    : Text(
                        widget.primaryActionLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigationMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
