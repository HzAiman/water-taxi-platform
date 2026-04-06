import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
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
    with WidgetsBindingObserver {
  static const MethodChannel _mapsConfigChannel = MethodChannel(
    'operator_app/maps_config',
  );

  bool _hasLocationPermission = false;
  bool _hasShownWelcomeAlert = false;
  bool _hasCheckedMapsConfig = false;
  bool _mapReady = false;
  bool _isActiveSectionExpanded = false;
  bool _isQueueSectionExpanded = false;
  bool _isInitializingViewModel = false;
  bool _hasInitializedViewModel = false;
  StreamSubscription<User?>? _authSubscription;
  DateTime? _lastRecoveryAttempt;

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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
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
    final granted = await _ensureLocationPermission();
    if (!granted) {
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition();
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

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        showTopInfo(
          context,
          title: 'Location services off',
          message: 'Enable location services to show your position.',
          actionLabel: 'Open Settings',
          onAction: Geolocator.openLocationSettings,
        );
      }
      setState(() => _hasLocationPermission = false);
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
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
      setState(() => _hasLocationPermission = false);
      return false;
    }

    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (mounted) {
      setState(() => _hasLocationPermission = granted);
    }
    return granted;
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

    final granted = await _ensureLocationPermission();
    if (!granted) {
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition();
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
                      : _buildInfoCard(
                          icon: Icons.directions_boat_filled_outlined,
                          iconColor: const Color(0xFF0066CC),
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
                      : _buildInfoCard(
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
            child: _buildStatTile(
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
            child: _buildStatTile(
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

  Widget _buildStatTile({
    required String label,
    required String value,
    required Color color,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.grey[700],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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
    final status = booking.status;
    final isAccepted = status == BookingStatus.accepted;
    final isOnTheWay = status == BookingStatus.onTheWay;
    final isStale = isAcceptedBookingStale(booking);
    final actionColor = isAccepted ? const Color(0xFF0066CC) : Colors.green;
    final detailText = _buildBookingDetailText(booking);
    final guidance = viewModel.navigationGuidance;
    final hasGuidance =
        isOnTheWay &&
        guidance != null &&
        guidance.bookingId == booking.bookingId;

    var subtitle = detailText;
    if (isStale) {
      subtitle =
          '$subtitle\n\nThis accepted booking looks stale. Start the trip or release it back to the queue.';
    }
    if (hasGuidance) {
      subtitle = '$subtitle\n\n${_buildNavigationGuidanceText(guidance)}';
    }

    return _buildInfoCard(
      icon: isAccepted ? Icons.directions_boat : Icons.route,
      iconColor: actionColor,
      title: 'Current Booking: ${formatStatusLabel(status.firestoreValue)}',
      subtitle: subtitle,
      actionLabel: isAccepted ? 'Start Trip' : 'Complete Trip',
      actionColor: actionColor,
      secondaryActionLabel: isAccepted ? 'Release' : null,
      secondaryActionColor: const Color(0xFFFFF1F1),
      secondaryActionTextColor: const Color(0xFFB42318),
      showActionLoading: viewModel.isUpdatingBooking,
      onAction: viewModel.isUpdatingBooking
          ? null
          : () async {
              final result = isAccepted
                  ? await viewModel.startTrip(booking.bookingId)
                  : await viewModel.completeTrip(booking.bookingId);
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

  Widget _buildPendingBookingCard(
    BookingModel booking,
    int pendingCount,
    OperatorHomeViewModel viewModel,
  ) {
    return _buildInfoCard(
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
    final fareValue = booking.totalFare > 0 ? booking.totalFare : booking.fare;

    return 'Booking ID: ${booking.bookingId}\n'
        'Route: ${booking.origin} -> ${booking.destination}\n'
        'Passengers: ${booking.passengerCount}\n'
        'Fare: ${fareValue > 0 ? formatCurrency(fareValue) : 'N/A'}\n'
        'Created: ${formatBookingTimestamp(booking.createdAt)}';
  }

  String _buildNavigationGuidanceText(OperatorNavigationGuidance guidance) {
    final progressPercent = (guidance.progressFraction * 100).round();
    final remaining = _formatDistanceMeters(guidance.remainingDistanceMeters);
    final offRoute = _formatDistanceMeters(guidance.offRouteDistanceMeters);
    final eta = _formatEta(guidance.eta);

    final lines = <String>[
      'Guidance: $progressPercent% complete',
      'Route marker: ${guidance.nearestRouteMarker}/${guidance.totalRouteMarkers}',
      'Next marker: ${guidance.nextRouteMarker}',
      'Remaining distance: $remaining',
      'ETA: $eta',
    ];

    if (guidance.isOffRoute) {
      lines.add('Off-route warning: approx $offRoute away from planned route.');
    }

    return lines.join('\n');
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

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? actionLabel,
    String? secondaryActionLabel,
    Color actionColor = const Color(0xFF0066CC),
    Color secondaryActionColor = const Color(0xFFF3F4F6),
    Color secondaryActionTextColor = const Color(0xFF1F2937),
    bool showActionLoading = false,
    Future<void> Function()? onAction,
    Future<void> Function()? onSecondaryAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (secondaryActionLabel != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondaryAction == null
                          ? null
                          : () => unawaited(onSecondaryAction()),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: secondaryActionColor,
                        foregroundColor: secondaryActionTextColor,
                        side: BorderSide(
                          color: secondaryActionTextColor.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Text(secondaryActionLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAction == null
                        ? null
                        : () => unawaited(onAction()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: actionColor,
                      foregroundColor: Colors.white,
                    ),
                    child: showActionLoading
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
                        : Text(actionLabel),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final operatorId = _operatorId;
    final viewModel = context.watch<OperatorHomeViewModel>();
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
                        markers: _buildMarkers(viewModel),
                        polylines: _buildPolylines(viewModel),
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
                          _mapReady = true;
                        },
                      ),
                ),
                Positioned.fill(
                  child: Stack(
                    children: [
                      if (isLoading)
                        const Center(child: CircularProgressIndicator()),
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (viewModel.isOnline) ...[
                              _buildBookingActionCard(operatorId, viewModel),
                            ] else ...[
                              _buildInfoCard(
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
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    onPressed: _centerOnUser,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
    );
  }

  Set<Marker> _buildMarkers(OperatorHomeViewModel viewModel) {
    final markers = <Marker>{};
    final activeBooking = viewModel.activeBookings.isNotEmpty
        ? viewModel.activeBookings.first
        : null;

    if (activeBooking == null) {
      return markers;
    }

    // Origin marker
    final originLat = activeBooking.originLat;
    final originLng = activeBooking.originLng;
    if (_isValidLatLng(originLat, originLng)) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: LatLng(originLat, originLng),
          infoWindow: InfoWindow(
            title: 'Pick-up',
            snippet: activeBooking.origin,
          ),
        ),
      );
    }

    // Destination marker (blue)
    final destLat = activeBooking.destinationLat;
    final destLng = activeBooking.destinationLng;
    if (_isValidLatLng(destLat, destLng)) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(destLat, destLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: 'Drop-off',
            snippet: activeBooking.destination,
          ),
        ),
      );
    }

    // Operator current location marker (green) for on-the-way bookings
    if (activeBooking.status == BookingStatus.onTheWay) {
      final opLat = activeBooking.operatorLat;
      final opLng = activeBooking.operatorLng;
      if (opLat != null && opLng != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('operator_location'),
            position: LatLng(opLat, opLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: const InfoWindow(
              title: 'Your Location',
              snippet: 'Current operator position',
            ),
          ),
        );
      }
    }

    return markers;
  }

  Set<Polyline> _buildPolylines(OperatorHomeViewModel viewModel) {
    final activeBooking = viewModel.activeBookings.isNotEmpty
        ? viewModel.activeBookings.first
        : null;

    if (activeBooking == null) {
      return const <Polyline>{};
    }

    final routePoints = activeBooking.routePolyline
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);

    if (routePoints.length >= 2) {
      return {
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: const Color(0xFF0066CC),
          width: 4,
        ),
      };
    }

    // Fallback: draw direct line if no polyline available
    final originLat = activeBooking.originLat;
    final originLng = activeBooking.originLng;
    final destLat = activeBooking.destinationLat;
    final destLng = activeBooking.destinationLng;

    if (_isValidLatLng(originLat, originLng) &&
        _isValidLatLng(destLat, destLng)) {
      return {
        Polyline(
          polylineId: const PolylineId('route'),
          points: [LatLng(originLat, originLng), LatLng(destLat, destLng)],
          color: const Color(0xFF0066CC),
          width: 4,
        ),
      };
    }

    return const <Polyline>{};
  }

  bool _isValidLatLng(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }
}
