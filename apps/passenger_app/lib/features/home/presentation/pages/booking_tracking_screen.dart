import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:passenger_app/core/theme/passenger_brand.dart';
import 'package:passenger_app/core/widgets/gradient_app_bar.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/booking_tracking_view_model.dart';
import 'package:provider/provider.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class BookingTrackingScreen extends StatefulWidget {
  const BookingTrackingScreen({
    super.key,
    required this.bookingId,
    required this.origin,
    required this.destination,
    required this.passengerCount,
    this.mapBuilder,
  });

  final String bookingId;
  final String origin;
  final String destination;
  final int passengerCount;
  final Widget Function({
    required CameraPosition initialCameraPosition,
    required Set<Marker> markers,
    required Set<Polyline> polylines,
    required EdgeInsets padding,
  })?
  mapBuilder;

  @override
  State<BookingTrackingScreen> createState() => _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends State<BookingTrackingScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _phoneChannel = MethodChannel(
    'passenger_app/phone',
  );

  final DateTime _openedAt = DateTime.now();

  GoogleMapController? _mapController;
  late final AnimationController _pulseController;
  String? _initialFitBookingId;
  LatLng? _lastFocusedOperatorPoint;
  DateTime? _lastOperatorFocusAt;
  String? _lastMarkerSetSignature;
  Set<Marker> _cachedMarkers = <Marker>{};
  String? _lastPolylineSetSignature;
  Set<Polyline> _cachedPolylines = <Polyline>{};
  DateTime? _lastMapPayloadLogAt;
  String? _etaBookingId;
  LatLng? _previousEtaOperatorPoint;
  DateTime? _previousEtaOperatorAt;
  double? _lastEtaSpeedMps;
  DateTime? _lastEtaSpeedAt;

  static const Duration _followRecenterInterval = Duration(seconds: 4);
  static const double _followRecenterDistanceMeters = 20;
  static const double _initialBoundsPadding = 80;
  static const double _operatorFollowZoom = 16.0;
  static const double _singlePointZoom = 15.0;
  static const Duration _etaSpeedFreshness = Duration(seconds: 45);
  static const double _etaMinimumSpeedMps = 0.5;
  static const double _etaLowConfidenceOffRouteMeters = 300;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      context.read<BookingTrackingViewModel>().startTracking(widget.bookingId);
    });
  }

  void _closeTrackingScreen() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _cancelBooking() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel Booking'),
          content: const Text('Are you sure you want to cancel this booking?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Booking'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel Booking'),
            ),
          ],
        );
      },
    );

    if (shouldCancel != true || !mounted) {
      return;
    }

    final result = await context.read<BookingTrackingViewModel>().cancelBooking(
      widget.bookingId,
    );
    if (!mounted) {
      return;
    }

    switch (result) {
      case OperationSuccess(:final message):
        showTopSuccess(context, message: message);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        _closeTrackingScreen();
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
    final viewModel = context.watch<BookingTrackingViewModel>();
    final booking = viewModel.booking;

    if (booking == null) {
      final slowLoad =
          viewModel.isLoading &&
          DateTime.now().difference(_openedAt) > const Duration(seconds: 6);

      return Scaffold(
        appBar: const GradientAppBar(title: 'Booking Status'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (viewModel.trackingError != null) ...[
                  const Icon(
                    Icons.wifi_off,
                    size: 36,
                    color: Color(0xFFD64545),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    viewModel.trackingError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF444444),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: viewModel.retryTracking,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ] else if (slowLoad) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text(
                    'Loading booking details is taking longer than expected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF444444)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You can retry now or keep waiting for sync.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: viewModel.retryTracking,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Sync'),
                  ),
                ] else ...[
                  const CircularProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final currentOrigin = booking.origin.isNotEmpty
        ? booking.origin
        : widget.origin;
    final currentDestination = booking.destination.isNotEmpty
        ? booking.destination
        : widget.destination;
    final currentPassengerCount = booking.passengerCount > 0
        ? booking.passengerCount
        : widget.passengerCount;
    final status = booking.status;
    final statusTheme = _statusThemeFor(status);
    final canCancel = status.canBeCancelledByPassenger;
    final isRejected = status == BookingStatus.rejected;
    final hasOperatorLocation =
        booking.operatorLat != null && booking.operatorLng != null;
    final isLocatingOperator =
        status == BookingStatus.onTheWay && !hasOperatorLocation;
    final isOperatorLocationStale =
        status == BookingStatus.onTheWay &&
        hasOperatorLocation &&
        booking.updatedAt != null &&
        DateTime.now().difference(booking.updatedAt!) >
            const Duration(seconds: 35);
    final paymentMethod = booking.paymentMethod;
    final paymentStatus = booking.paymentStatus;
    final rejectedPaymentMessage = isRejected
        ? _rejectedPaymentMessage(paymentStatus)
        : null;

    final originPoint = _latLngOrNull(booking.originLat, booking.originLng);
    final destinationPoint = _latLngOrNull(
      booking.destinationLat,
      booking.destinationLng,
    );
    final routePoints = _routePointsFor(booking, originPoint, destinationPoint);
    final operatorPoint = _operatorPointForBooking(booking);
    final etaDisplay = _passengerEtaForBooking(
      booking: booking,
      operatorPoint: operatorPoint,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
      isOperatorLocationStale: isOperatorLocationStale,
    );
    final markers = _buildMarkers(
      bookingId: booking.bookingId,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
      operatorPoint: operatorPoint,
      originLabel: currentOrigin,
      destinationLabel: currentDestination,
    );
    final polylines = _buildPolylines(
      bookingId: booking.bookingId,
      routePoints: routePoints,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
    );
    final mapPadding = _mapPaddingFor(context);

    _scheduleCameraSync(
      bookingId: booking.bookingId,
      status: status,
      routePoints: routePoints,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
      operatorPoint: operatorPoint,
    );

    return Scaffold(
      appBar: const GradientAppBar(title: 'Booking Status'),
      body: Stack(
        children: [
          Positioned.fill(
            child:
                widget.mapBuilder?.call(
                  initialCameraPosition: _cameraPositionFor(
                    routePoints,
                    originPoint,
                    destinationPoint,
                    operatorPoint,
                  ),
                  markers: markers,
                  polylines: polylines,
                  padding: mapPadding,
                ) ??
                GoogleMap(
                  initialCameraPosition: _cameraPositionFor(
                    routePoints,
                    originPoint,
                    destinationPoint,
                    operatorPoint,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _scheduleCameraSync(
                      bookingId: booking.bookingId,
                      status: status,
                      routePoints: routePoints,
                      originPoint: originPoint,
                      destinationPoint: destinationPoint,
                      operatorPoint: operatorPoint,
                    );
                  },
                  markers: markers,
                  polylines: polylines,
                  padding: mapPadding,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.30,
            minChildSize: 0.22,
            maxChildSize: 0.68,
            snap: true,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 12,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDE5F0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            child: _buildStatusRippleDot(
                              status: status,
                              color: statusTheme.color,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              statusTheme.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusTheme.message,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666666),
                        ),
                      ),
                      if (rejectedPaymentMessage != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFD7AE)),
                          ),
                          child: Text(
                            rejectedPaymentMessage,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8A4B08),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildStatusTimeline(status),
                      if (isLocatingOperator || isOperatorLocationStale) ...[
                        const SizedBox(height: 12),
                        _buildLocationStatusNotice(
                          isLocating: isLocatingOperator,
                        ),
                      ],
                      if (etaDisplay != null) ...[
                        const SizedBox(height: 12),
                        _buildEtaCard(etaDisplay),
                      ],
                      const SizedBox(height: 12),
                      _buildCompactRouteCard(
                        origin: currentOrigin,
                        destination: currentDestination,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoTile(
                              icon: Icons.people,
                              label: 'Passengers',
                              value: '$currentPassengerCount',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: _buildPaymentStatusCard(
                              paymentMethod: PaymentMethods.label(
                                paymentMethod,
                              ),
                              paymentStatus: _formatStatusLabel(paymentStatus),
                            ),
                          ),
                        ],
                      ),
                      if (booking.operatorUid?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        _buildAssignedOperatorCard(booking: booking),
                      ],
                      const SizedBox(height: 12),
                      _buildStateGuidance(booking),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canCancel
                                ? const Color(0xFFD64545)
                                : PassengerBrand.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: viewModel.isCancelling
                              ? null
                              : canCancel
                              ? _cancelBooking
                              : _closeTrackingScreen,
                          child: viewModel.isCancelling
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  canCancel
                                      ? 'Cancel Booking'
                                      : isRejected
                                      ? 'Book Again'
                                      : 'Close',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static const CameraPosition _fallbackCameraPosition = CameraPosition(
    target: LatLng(2.1916, 102.2490),
    zoom: 14,
  );

  EdgeInsets _mapPaddingFor(BuildContext context) {
    return const EdgeInsets.only(top: 64, bottom: 80, left: 40, right: 40);
  }

  Widget _buildCompactRouteCard({
    required String origin,
    required String destination,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PassengerBrand.softMint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: PassengerBrand.blue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: _AutoScrollText(
              text: origin,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: Color(0xFF6E7B8B),
            ),
          ),
          const Icon(Icons.flag, color: PassengerBrand.blue, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: _AutoScrollText(
              text: destination,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: PassengerBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: PassengerBrand.blue, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                _AutoScrollText(
                  text: value,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusCard({
    required String paymentMethod,
    required String paymentStatus,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: PassengerBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildCompactInfoContent(
              icon: Icons.credit_card,
              label: 'Payment',
              value: paymentMethod,
            ),
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFFDDE5F0),
          ),
          Expanded(
            child: _buildCompactInfoContent(
              icon: Icons.verified,
              label: 'Status',
              value: paymentStatus,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtaCard(_PassengerEtaDisplay eta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PassengerBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: PassengerBrand.blue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eta.label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  eta.value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoContent({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: PassengerBrand.blue, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 1),
              _AutoScrollText(
                text: value,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRippleDot({
    required BookingStatus status,
    required Color color,
  }) {
    final rippleMode = _rippleModeFor(status);
    if (rippleMode == _StatusRippleMode.none) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final value = _pulseController.value;
        final progress = rippleMode == _StatusRippleMode.outward
            ? value
            : 1 - value;
        final outerScale = 1.0 + (progress * 1.35);
        final innerScale = 1.0 + ((progress + 0.45) % 1.0 * 1.1);
        final outerOpacity = 0.30 * (1 - progress);
        final innerOpacity = 0.18 * (1 - ((progress + 0.45) % 1.0));

        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: outerScale,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: outerOpacity),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Transform.scale(
              scale: innerScale,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: innerOpacity),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildAssignedOperatorCard({required BookingModel booking}) {
    final name = booking.assignedOperatorName.trim();
    final operatorId = booking.assignedOperatorDisplayId.trim();
    final phone = booking.assignedOperatorPhone.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PassengerBrand.softMint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PassengerBrand.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: PassengerBrand.gradient,
            ),
            child: const Icon(
              Icons.directions_boat_filled,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AutoScrollText(
                  text: name.isNotEmpty ? name : 'Operator',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                _AutoScrollText(
                  text: operatorId.isNotEmpty
                      ? 'Operator ID: $operatorId'
                      : 'Operator ID: Unavailable',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A6878),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: phone.isEmpty ? null : () => _callOperator(phone),
            style: IconButton.styleFrom(
              backgroundColor: phone.isEmpty
                  ? const Color(0xFFDDE5F0)
                  : PassengerBrand.blue,
              foregroundColor: Colors.white,
              disabledForegroundColor: const Color(0xFF8A97A8),
            ),
            icon: const Icon(Icons.call, size: 18),
            tooltip: phone.isEmpty
                ? 'Operator phone number unavailable'
                : 'Call operator',
          ),
        ],
      ),
    );
  }

  Future<void> _callOperator(String phone) async {
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
          message: 'Please call the operator manually: $phone',
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      showTopInfo(
        context,
        title: 'Unable to open dialer',
        message: 'Please call the operator manually: $phone',
      );
    }
  }

  CameraPosition _cameraPositionFor(
    List<LatLng> routePoints,
    LatLng? originPoint,
    LatLng? destinationPoint,
    LatLng? operatorPoint,
  ) {
    if (routePoints.length >= 2) {
      return CameraPosition(
        target: _centerOfPoints(routePoints),
        zoom: _previewZoomForPoints(routePoints),
      );
    }

    if (originPoint != null && destinationPoint != null) {
      final points = <LatLng>[originPoint, destinationPoint];
      return CameraPosition(
        target: LatLng(
          (originPoint.latitude + destinationPoint.latitude) / 2,
          (originPoint.longitude + destinationPoint.longitude) / 2,
        ),
        zoom: _previewZoomForPoints(points),
      );
    }

    if (originPoint != null) {
      return CameraPosition(target: originPoint, zoom: _singlePointZoom);
    }

    if (destinationPoint != null) {
      return CameraPosition(target: destinationPoint, zoom: _singlePointZoom);
    }

    if (operatorPoint != null) {
      return CameraPosition(target: operatorPoint, zoom: _singlePointZoom);
    }

    return _fallbackCameraPosition;
  }

  Set<Marker> _buildMarkers({
    required String bookingId,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
    required LatLng? operatorPoint,
    required String originLabel,
    required String destinationLabel,
  }) {
    final markerSignature = [
      _pointSignature(originPoint),
      _pointSignature(destinationPoint),
      _pointSignature(operatorPoint),
    ].join('|');
    if (_lastMarkerSetSignature == markerSignature) {
      return _cachedMarkers;
    }

    final markers = <Marker>{};

    if (originPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: originPoint,
          infoWindow: InfoWindow(title: 'Pick-up', snippet: originLabel),
        ),
      );
    }

    if (destinationPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationPoint,
          infoWindow: InfoWindow(title: 'Drop-off', snippet: destinationLabel),
        ),
      );
    }

    if (operatorPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('operator_live'),
          position: operatorPoint,
          infoWindow: const InfoWindow(
            title: 'Operator Location',
            snippet: 'Live location',
          ),
        ),
      );
    }

    _lastMarkerSetSignature = markerSignature;
    _cachedMarkers = markers;
    _debugMapPayload(
      '[MapDiag][Markers] booking=$bookingId count=${markers.length} '
      'origin=${_pointSignature(originPoint)} '
      'destination=${_pointSignature(destinationPoint)} '
      'operator=${_pointSignature(operatorPoint)} '
      'signature=$markerSignature',
    );
    return markers;
  }

  Set<Polyline> _buildPolylines({
    required String bookingId,
    required List<LatLng> routePoints,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
  }) {
    final polylineSignature = _polylineSignature(
      routePoints: routePoints,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
    );
    if (_lastPolylineSetSignature == polylineSignature) {
      return _cachedPolylines;
    }

    if (routePoints.length >= 2) {
      final result = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: PassengerBrand.blue,
          width: 4,
        ),
      };
      _lastPolylineSetSignature = polylineSignature;
      _cachedPolylines = result;
      _debugMapPayload(
        '[MapDiag][Polyline] booking=$bookingId points=${routePoints.length} '
        'start=${_pointSignature(routePoints.first)} '
        'end=${_pointSignature(routePoints.last)} '
        'signature=$polylineSignature',
      );
      return result;
    }

    if (originPoint == null || destinationPoint == null) {
      const result = <Polyline>{};
      _lastPolylineSetSignature = polylineSignature;
      _cachedPolylines = result;
      _debugMapPayload(
        '[MapDiag][Polyline] booking=$bookingId points=0 reason=missing-endpoint '
        'origin=${_pointSignature(originPoint)} '
        'destination=${_pointSignature(destinationPoint)} '
        'signature=$polylineSignature',
      );
      return result;
    }

    final result = {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [originPoint, destinationPoint],
        color: PassengerBrand.blue,
        width: 4,
      ),
    };
    _lastPolylineSetSignature = polylineSignature;
    _cachedPolylines = result;
    _debugMapPayload(
      '[MapDiag][Polyline] booking=$bookingId points=2 reason=fallback-straight-line '
      'origin=${_pointSignature(originPoint)} '
      'destination=${_pointSignature(destinationPoint)} '
      'signature=$polylineSignature',
    );
    return result;
  }

  List<LatLng> _routePointsFor(
    BookingModel booking,
    LatLng? originPoint,
    LatLng? destinationPoint,
  ) {
    final sourcePoints = booking.routePolyline
        .where((p) => _isValidCoordinate(p.lat, p.lng))
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: true);

    final points = List<LatLng>.from(sourcePoints);

    if (points.length >= 2) {
      if (originPoint != null && destinationPoint != null) {
        final directScore =
            _distanceMeters(points.first, originPoint) +
            _distanceMeters(points.last, destinationPoint);
        final reversedScore =
            _distanceMeters(points.first, destinationPoint) +
            _distanceMeters(points.last, originPoint);
        if (reversedScore + 1 < directScore) {
          points
            ..clear()
            ..addAll(sourcePoints.reversed);
          _debugMapPayload(
            '[MapDiag][RouteDirection] booking=${booking.bookingId} reversed=true '
            'direct=${directScore.toStringAsFixed(2)} '
            'reversed=${reversedScore.toStringAsFixed(2)}',
          );
        }
      }

      if (originPoint != null) {
        points[0] = originPoint;
      }
      if (destinationPoint != null) {
        points[points.length - 1] = destinationPoint;
      }
      return points;
    }

    if (originPoint != null && destinationPoint != null) {
      return <LatLng>[originPoint, destinationPoint];
    }

    return points;
  }

  LatLng? _operatorPointForBooking(BookingModel booking) {
    if (booking.status != BookingStatus.onTheWay) {
      return null;
    }
    if (booking.operatorLat == null || booking.operatorLng == null) {
      return null;
    }
    return _latLngOrNull(booking.operatorLat!, booking.operatorLng!);
  }

  void _scheduleCameraSync({
    required String bookingId,
    required BookingStatus status,
    required List<LatLng> routePoints,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
    required LatLng? operatorPoint,
  }) {
    if (widget.mapBuilder != null || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _fitRouteIfNeeded(
        bookingId: bookingId,
        routePoints: routePoints,
        originPoint: originPoint,
        destinationPoint: destinationPoint,
      );
      await _followOperatorIfNeeded(status, operatorPoint);
    });
  }

  Future<void> _fitRouteIfNeeded({
    required String bookingId,
    required List<LatLng> routePoints,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
  }) async {
    if (_mapController == null || _initialFitBookingId == bookingId) {
      return;
    }

    final fitPoints = <LatLng>[
      ...routePoints,
      if (originPoint != null) originPoint,
      if (destinationPoint != null) destinationPoint,
    ];

    if (fitPoints.length < 2) {
      return;
    }

    await _animateToBounds(_boundsFromPoints(fitPoints), _initialBoundsPadding);
    _initialFitBookingId = bookingId;
  }

  Future<void> _followOperatorIfNeeded(
    BookingStatus status,
    LatLng? operatorPoint,
  ) async {
    if (_mapController == null) {
      return;
    }

    if (status != BookingStatus.onTheWay || operatorPoint == null) {
      _lastFocusedOperatorPoint = null;
      _lastOperatorFocusAt = null;
      return;
    }

    final lastPoint = _lastFocusedOperatorPoint;
    final lastAt = _lastOperatorFocusAt;
    final shouldFocus =
        lastPoint == null ||
        lastAt == null ||
        DateTime.now().difference(lastAt) >= _followRecenterInterval ||
        _distanceMeters(lastPoint, operatorPoint) >=
            _followRecenterDistanceMeters;

    if (!shouldFocus) {
      return;
    }

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(operatorPoint, _operatorFollowZoom),
      );
      _lastFocusedOperatorPoint = operatorPoint;
      _lastOperatorFocusAt = DateTime.now();
    } catch (_) {
      // Ignore map camera errors; user can still view updates via markers.
    }
  }

  Future<void> _animateToBounds(LatLngBounds bounds, double padding) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
    } catch (_) {
      // The map may not have laid out yet; retry once shortly after.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, padding),
        );
      } catch (_) {
        // Ignore bounds-fit failure and keep default camera.
      }
    }
  }

  double _previewZoomForPoints(List<LatLng> points) {
    if (points.length < 2) {
      return _singlePointZoom;
    }
    final bounds = _boundsFromPoints(points);
    final diagonalMeters = _distanceMeters(bounds.southwest, bounds.northeast);
    return _zoomForDistanceMeters(diagonalMeters);
  }

  double _zoomForDistanceMeters(double meters) {
    if (meters <= 300) return 16.6;
    if (meters <= 700) return 15.8;
    if (meters <= 1500) return 15.0;
    if (meters <= 3000) return 14.2;
    if (meters <= 7000) return 13.4;
    return 12.6;
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    final safePoints = points
        .where((p) => _isValidCoordinate(p.latitude, p.longitude))
        .toList(growable: false);

    if (safePoints.isEmpty) {
      return LatLngBounds(
        southwest: _fallbackCameraPosition.target,
        northeast: _fallbackCameraPosition.target,
      );
    }

    var minLat = safePoints.first.latitude;
    var maxLat = safePoints.first.latitude;
    var minLng = safePoints.first.longitude;
    var maxLng = safePoints.first.longitude;

    for (final p in safePoints.skip(1)) {
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

  LatLng _centerOfPoints(List<LatLng> points) {
    var latSum = 0.0;
    var lngSum = 0.0;
    for (final p in points) {
      latSum += p.latitude;
      lngSum += p.longitude;
    }
    return LatLng(latSum / points.length, lngSum / points.length);
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);

    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadius * c;
  }

  double _toRadians(double deg) => deg * (math.pi / 180);

  _PassengerEtaDisplay? _passengerEtaForBooking({
    required BookingModel booking,
    required LatLng? operatorPoint,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
    required bool isOperatorLocationStale,
  }) {
    if (booking.status != BookingStatus.onTheWay || operatorPoint == null) {
      _resetEtaSamplesIfNeeded(booking.bookingId);
      return null;
    }

    final target = _etaTargetForBooking(
      booking: booking,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
    );
    if (target == null) {
      return null;
    }

    if (isOperatorLocationStale) {
      return _PassengerEtaDisplay(
        label: target.label,
        value: 'Waiting for live location',
      );
    }

    final now = booking.updatedAt ?? DateTime.now();
    final speedMps = _resolveEtaSpeed(
      bookingId: booking.bookingId,
      operatorPoint: operatorPoint,
      now: now,
    );
    if (speedMps == null) {
      return _PassengerEtaDisplay(
        label: target.label,
        value: 'Calculating ETA',
      );
    }

    final phaseRoutePoints = _etaRoutePointsForPhase(
      booking: booking,
      operatorPoint: operatorPoint,
      targetPoint: target.point,
      passengerPickedUp: target.isDestination,
    );
    final remainingDistanceMeters = _remainingDistanceMetersToTarget(
      operatorPoint: operatorPoint,
      targetPoint: target.point,
      routePoints: phaseRoutePoints,
    );
    if (remainingDistanceMeters <= 0) {
      return _PassengerEtaDisplay(label: target.label, value: '< 1 min');
    }

    final eta = Duration(seconds: (remainingDistanceMeters / speedMps).round());
    final lowConfidence =
        phaseRoutePoints.length >= 2 &&
        _offRouteDistanceMeters(operatorPoint, phaseRoutePoints) >
            _etaLowConfidenceOffRouteMeters;

    return _PassengerEtaDisplay(
      label: target.label,
      value: '${lowConfidence ? '~ ' : ''}${_formatEta(eta)}',
    );
  }

  _PassengerEtaTarget? _etaTargetForBooking({
    required BookingModel booking,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
  }) {
    final currentStop = booking.currentPoolStop;
    if (currentStop != null) {
      final stopPoint = _latLngOrNull(currentStop.lat, currentStop.lng);
      if (stopPoint == null) {
        return null;
      }
      return _PassengerEtaTarget(
        label: currentStop.isDropoff ? 'ETA to destination' : 'ETA to pickup',
        point: stopPoint,
        isDestination: currentStop.isDropoff,
      );
    }

    final passengerPickedUp =
        booking.passengerPickedUpAt != null ||
        booking.pickedUpAt != null ||
        booking.onboard;
    final targetPoint = passengerPickedUp ? destinationPoint : originPoint;
    if (targetPoint == null) {
      return null;
    }
    return _PassengerEtaTarget(
      label: passengerPickedUp ? 'ETA to destination' : 'ETA to pickup',
      point: targetPoint,
      isDestination: passengerPickedUp,
    );
  }

  List<LatLng> _etaRoutePointsForPhase({
    required BookingModel booking,
    required LatLng operatorPoint,
    required LatLng targetPoint,
    required bool passengerPickedUp,
  }) {
    final source = passengerPickedUp
        ? (booking.routeToDestinationPolyline.isNotEmpty
              ? booking.routeToDestinationPolyline
              : booking.routePolyline)
        : booking.routeToOriginPolyline;
    final points = source
        .where((p) => _isValidCoordinate(p.lat, p.lng))
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: true);

    if (points.length < 2) {
      return <LatLng>[operatorPoint, targetPoint];
    }
    if (_distanceMeters(points.last, targetPoint) > 5) {
      points.add(targetPoint);
    }
    return points;
  }

  double _remainingDistanceMetersToTarget({
    required LatLng operatorPoint,
    required LatLng targetPoint,
    required List<LatLng> routePoints,
  }) {
    if (routePoints.length < 2) {
      return _distanceMeters(operatorPoint, targetPoint);
    }

    final projection = _projectPointOntoRoute(operatorPoint, routePoints);
    if (projection == null) {
      return _distanceMeters(operatorPoint, targetPoint);
    }
    return (projection.distanceFromRouteMeters +
            _distanceAlongRouteFromProjection(routePoints, projection))
        .clamp(0.0, double.infinity);
  }

  double _offRouteDistanceMeters(LatLng point, List<LatLng> routePoints) {
    return _projectPointOntoRoute(
          point,
          routePoints,
        )?.distanceFromRouteMeters ??
        0;
  }

  _RouteProjectionOnPolyline? _projectPointOntoRoute(
    LatLng point,
    List<LatLng> routePoints,
  ) {
    if (routePoints.length < 2) {
      return null;
    }

    var nearestSegmentIndex = 0;
    var nearestT = 0.0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < routePoints.length - 1; i++) {
      final projection = _projectPointOntoSegment(
        point: point,
        start: routePoints[i],
        end: routePoints[i + 1],
      );
      if (projection.distanceMeters < nearestDistance) {
        nearestDistance = projection.distanceMeters;
        nearestSegmentIndex = i;
        nearestT = projection.t;
      }
    }

    return _RouteProjectionOnPolyline(
      segmentIndex: nearestSegmentIndex,
      t: nearestT,
      distanceFromRouteMeters: nearestDistance,
    );
  }

  _SegmentProjection _projectPointOntoSegment({
    required LatLng point,
    required LatLng start,
    required LatLng end,
  }) {
    final meanLat = _toRadians((start.latitude + end.latitude) / 2);
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng = 111320.0 * math.cos(meanLat);

    final sx = start.longitude * metersPerDegreeLng;
    final sy = start.latitude * metersPerDegreeLat;
    final ex = end.longitude * metersPerDegreeLng;
    final ey = end.latitude * metersPerDegreeLat;
    final px = point.longitude * metersPerDegreeLng;
    final py = point.latitude * metersPerDegreeLat;
    final dx = ex - sx;
    final dy = ey - sy;
    final lengthSquared = dx * dx + dy * dy;

    if (lengthSquared <= 0) {
      final ox = px - sx;
      final oy = py - sy;
      return _SegmentProjection(
        t: 0,
        distanceMeters: math.sqrt((ox * ox) + (oy * oy)),
      );
    }

    final t = ((((px - sx) * dx) + ((py - sy) * dy)) / lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
    final cx = sx + (dx * t);
    final cy = sy + (dy * t);
    final ox = px - cx;
    final oy = py - cy;
    return _SegmentProjection(
      t: t,
      distanceMeters: math.sqrt((ox * ox) + (oy * oy)),
    );
  }

  double _distanceAlongRouteFromProjection(
    List<LatLng> routePoints,
    _RouteProjectionOnPolyline projection,
  ) {
    var remaining = 0.0;
    for (var i = projection.segmentIndex; i < routePoints.length - 1; i++) {
      final segmentDistance = _distanceMeters(
        routePoints[i],
        routePoints[i + 1],
      );
      remaining += i == projection.segmentIndex
          ? segmentDistance * (1 - projection.t)
          : segmentDistance;
    }
    return remaining;
  }

  double? _resolveEtaSpeed({
    required String bookingId,
    required LatLng operatorPoint,
    required DateTime now,
  }) {
    if (_etaBookingId != bookingId) {
      _resetEtaSamples();
      _etaBookingId = bookingId;
    }

    double? speedMps;
    final previousPoint = _previousEtaOperatorPoint;
    final previousAt = _previousEtaOperatorAt;
    if (previousPoint != null && previousAt != null) {
      final elapsedSeconds = now.difference(previousAt).inMilliseconds / 1000;
      final movedMeters = _distanceMeters(previousPoint, operatorPoint);
      if (elapsedSeconds >= 0.5 && movedMeters > 0.5) {
        final derivedSpeed = movedMeters / elapsedSeconds;
        if (derivedSpeed.isFinite && derivedSpeed >= _etaMinimumSpeedMps) {
          speedMps = derivedSpeed;
          _lastEtaSpeedMps = speedMps;
          _lastEtaSpeedAt = now;
        }
      }
    }

    _previousEtaOperatorPoint = operatorPoint;
    _previousEtaOperatorAt = now;

    if (speedMps != null) {
      return speedMps;
    }
    final cachedSpeed = _lastEtaSpeedMps;
    final cachedAt = _lastEtaSpeedAt;
    if (cachedSpeed != null &&
        cachedAt != null &&
        now.difference(cachedAt) <= _etaSpeedFreshness) {
      return cachedSpeed;
    }
    return null;
  }

  void _resetEtaSamplesIfNeeded(String bookingId) {
    if (_etaBookingId != null && _etaBookingId != bookingId) {
      _resetEtaSamples();
    }
  }

  void _resetEtaSamples() {
    _previousEtaOperatorPoint = null;
    _previousEtaOperatorAt = null;
    _lastEtaSpeedMps = null;
    _lastEtaSpeedAt = null;
  }

  String _formatEta(Duration eta) {
    final minutes = eta.inMinutes;
    if (minutes <= 0) {
      return '< 1 min';
    }
    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours h' : '$hours h $remainder min';
  }

  Widget _buildStatusTimeline(BookingStatus status) {
    final steps = [
      _TimelineStep('Request'),
      _TimelineStep('Assigned'),
      _TimelineStep('Trip'),
      _TimelineStep('Done'),
    ];

    final currentIndex = _timelineIndex(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PassengerBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: List.generate(steps.length, (i) {
          final step = steps[i];
          final reached = currentIndex >= i;
          final isCurrent = currentIndex == i;
          final isLast = i == steps.length - 1;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: isCurrent ? 10 : 8,
                        height: isCurrent ? 10 : 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: reached
                              ? PassengerBrand.blue
                              : const Color(0xFFD2DCEB),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        step.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: reached
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFF8A97A8),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 16,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: currentIndex > i
                        ? PassengerBrand.blue
                        : const Color(0xFFD2DCEB),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStateGuidance(BookingModel booking) {
    final guidance = _guidanceText(booking);
    if (guidance == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE1B0)),
      ),
      child: Text(
        guidance,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF8A5A00),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLocationStatusNotice({required bool isLocating}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PassengerBrand.softMint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PassengerBrand.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.near_me, size: 16, color: PassengerBrand.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLocating
                  ? 'Locating operator. Live position will appear shortly.'
                  : 'Operator location update is delayed. Showing the most recent known position.',
              style: const TextStyle(
                fontSize: 12,
                color: PassengerBrand.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _timelineIndex(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return 0;
      case BookingStatus.accepted:
        return 1;
      case BookingStatus.onTheWay:
        return 2;
      case BookingStatus.completed:
        return 3;
      case BookingStatus.cancelled:
      case BookingStatus.rejected:
      case BookingStatus.unknown:
        return 0;
    }
  }

  _StatusRippleMode _rippleModeFor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return _StatusRippleMode.outward;
      case BookingStatus.accepted:
      case BookingStatus.onTheWay:
        return _StatusRippleMode.inward;
      case BookingStatus.completed:
      case BookingStatus.cancelled:
      case BookingStatus.rejected:
      case BookingStatus.unknown:
        return _StatusRippleMode.none;
    }
  }

  String? _guidanceText(BookingModel booking) {
    switch (booking.status) {
      case BookingStatus.pending:
        final createdAt = booking.createdAt;
        if (createdAt != null &&
            DateTime.now().difference(createdAt) > const Duration(minutes: 1)) {
          return 'Operator assignment is taking longer than usual. You can keep waiting, or cancel if your plans changed.';
        }
        return 'Looking for an available operator. You may keep waiting or cancel if your plans changed.';
      case BookingStatus.rejected:
        return 'No operator is available right now. Tap Book Again to try later.';
      case BookingStatus.accepted:
      case BookingStatus.onTheWay:
      case BookingStatus.completed:
      case BookingStatus.cancelled:
      case BookingStatus.unknown:
        return null;
    }
  }

  String? _rejectedPaymentMessage(String paymentStatus) {
    final normalized = paymentStatus.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.contains('refunded')) {
      return 'Payment refunded successfully. Funds will appear back in your account shortly.';
    }
    if (normalized.contains('cancelled')) {
      return 'Payment authorization was released. No charge was captured for this rejected booking.';
    }
    if (normalized.contains('authorized')) {
      return 'Payment is authorized and pending release. Please wait a moment for payment status to update.';
    }
    if (normalized.contains('paid')) {
      return 'Payment was captured. A refund is being processed for this rejected booking.';
    }

    return 'Payment status: ${_formatStatusLabel(paymentStatus)}';
  }

  LatLng? _latLngOrNull(double lat, double lng) {
    if (!_isValidCoordinate(lat, lng)) {
      return null;
    }
    return LatLng(lat, lng);
  }

  bool _isValidCoordinate(double lat, double lng) {
    if (lat == 0 && lng == 0) {
      return false;
    }
    if (!lat.isFinite || !lng.isFinite) {
      return false;
    }
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  String _pointSignature(LatLng? point) {
    if (point == null) {
      return 'null';
    }
    return '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
  }

  void _debugMapPayload(String message) {
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now();
    if (_lastMapPayloadLogAt != null &&
        now.difference(_lastMapPayloadLogAt!) <
            const Duration(milliseconds: 250)) {
      return;
    }
    _lastMapPayloadLogAt = now;
    debugPrint(message);
  }

  String _polylineSignature({
    required List<LatLng> routePoints,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
  }) {
    final buffer = StringBuffer()
      ..write('o=')
      ..write(_pointSignature(originPoint))
      ..write('|d=')
      ..write(_pointSignature(destinationPoint));

    for (final point in routePoints) {
      buffer
        ..write('|')
        ..write(point.latitude.toStringAsFixed(5))
        ..write(',')
        ..write(point.longitude.toStringAsFixed(5));
    }
    return buffer.toString();
  }

  String _formatStatusLabel(String status) {
    return status
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  _BookingStatusTheme _statusThemeFor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return const _BookingStatusTheme(
          title: 'Booking Request Pending',
          message: 'Waiting for an operator to accept your booking request.',
          color: Colors.orange,
        );
      case BookingStatus.accepted:
        return const _BookingStatusTheme(
          title: 'Booking Confirmed',
          message: 'An operator has accepted your booking.',
          color: PassengerBrand.blue,
        );
      case BookingStatus.onTheWay:
        return const _BookingStatusTheme(
          title: 'Trip In Progress',
          message: 'Your assigned operator is currently handling this trip.',
          color: Colors.teal,
        );
      case BookingStatus.completed:
        return const _BookingStatusTheme(
          title: 'Trip Completed',
          message: 'This booking has been completed successfully.',
          color: Colors.green,
        );
      case BookingStatus.cancelled:
        return const _BookingStatusTheme(
          title: 'Booking Cancelled',
          message: 'This booking was cancelled.',
          color: Colors.red,
        );
      case BookingStatus.rejected:
        return const _BookingStatusTheme(
          title: 'Booking Rejected',
          message:
              'No operator is available right now. Please try again later.',
          color: Colors.deepOrange,
        );
      case BookingStatus.unknown:
        return const _BookingStatusTheme(
          title: 'Booking Updated',
          message: 'This booking has been updated.',
          color: PassengerBrand.blue,
        );
    }
  }
}

class _BookingStatusTheme {
  const _BookingStatusTheme({
    required this.title,
    required this.message,
    required this.color,
  });

  final String title;
  final String message;
  final Color color;
}

class _TimelineStep {
  const _TimelineStep(this.label);

  final String label;
}

class _PassengerEtaDisplay {
  const _PassengerEtaDisplay({required this.label, required this.value});

  final String label;
  final String value;
}

class _PassengerEtaTarget {
  const _PassengerEtaTarget({
    required this.label,
    required this.point,
    required this.isDestination,
  });

  final String label;
  final LatLng point;
  final bool isDestination;
}

class _RouteProjectionOnPolyline {
  const _RouteProjectionOnPolyline({
    required this.segmentIndex,
    required this.t,
    required this.distanceFromRouteMeters,
  });

  final int segmentIndex;
  final double t;
  final double distanceFromRouteMeters;
}

class _SegmentProjection {
  const _SegmentProjection({required this.t, required this.distanceMeters});

  final double t;
  final double distanceMeters;
}

enum _StatusRippleMode { outward, inward, none }

class _AutoScrollText extends StatefulWidget {
  const _AutoScrollText({required this.text, required this.style});

  final String text;
  final TextStyle style;
  static const Duration _pause = Duration(milliseconds: 900);

  @override
  State<_AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<_AutoScrollText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _scrollDistance = 0;
  Duration? _duration;
  bool _loopScheduled = false;
  Timer? _scrollPauseTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _duration = null;
      _scrollPauseTimer?.cancel();
      _loopScheduled = false;
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final maxWidth = constraints.maxWidth;
        final textWidth = textPainter.width;

        if (!maxWidth.isFinite || textWidth <= maxWidth) {
          _controller.stop();
          _controller.value = 0;
          _duration = null;
          _loopScheduled = false;
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.clip,
          );
        }

        final distance = textWidth - maxWidth + 24;
        final duration = Duration(
          milliseconds: (distance * 42).clamp(2600, 9000).round(),
        );
        _configureScrolling(distance: distance, duration: duration);

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_scrollDistance * _controller.value, 0),
                child: child,
              );
            },
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        );
      },
    );
  }

  void _configureScrolling({
    required double distance,
    required Duration duration,
  }) {
    _scrollDistance = distance;
    if (_duration == duration && _loopScheduled) {
      return;
    }
    _duration = duration;
    _loopScheduled = true;
    _controller.duration = duration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _duration != duration) {
        _loopScheduled = false;
        return;
      }
      _scheduleNextScrollLoop(duration);
    });
  }

  void _scheduleNextScrollLoop(Duration duration) {
    _scrollPauseTimer?.cancel();
    _scrollPauseTimer = Timer(_AutoScrollText._pause, () async {
      if (!mounted || _duration != duration) {
        _loopScheduled = false;
        return;
      }
      await _controller.forward(from: 0);
      if (!mounted || _duration != duration) {
        _loopScheduled = false;
        return;
      }
      _scheduleNextScrollLoop(duration);
    });
  }

  @override
  void dispose() {
    _scrollPauseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}
