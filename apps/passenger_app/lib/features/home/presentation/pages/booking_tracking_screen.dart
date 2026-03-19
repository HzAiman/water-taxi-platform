import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  })?
  mapBuilder;

  @override
  State<BookingTrackingScreen> createState() => _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends State<BookingTrackingScreen> {
  GoogleMapController? _mapController;
  String? _lastFittedBookingId;
  LatLng? _lastFocusedOperatorPoint;
  DateTime? _lastOperatorFocusAt;

  static const Duration _followRecenterInterval = Duration(seconds: 8);
  static const double _followRecenterDistanceMeters = 35;

  @override
  void initState() {
    super.initState();
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
      return Scaffold(
        appBar: AppBar(
          title: const Text('Booking Status'),
          centerTitle: true,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
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
    final rejectedPaymentMessage =
      isRejected ? _rejectedPaymentMessage(paymentStatus) : null;

    final originPoint = _latLngOrNull(booking.originLat, booking.originLng);
    final destinationPoint = _latLngOrNull(
      booking.destinationLat,
      booking.destinationLng,
    );
    final routePoints = _routePointsFor(booking);
    final operatorPoint = _operatorPointForBooking(booking);
    final markers = _buildMarkers(
      originPoint: originPoint,
      destinationPoint: destinationPoint,
      operatorPoint: operatorPoint,
      originLabel: currentOrigin,
      destinationLabel: currentDestination,
    );
    final polylines = _buildPolylines(booking, originPoint, destinationPoint);

    _scheduleCameraSync(
      bookingId: booking.bookingId,
      status: status,
      routePoints: routePoints,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
      operatorPoint: operatorPoint,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Status'),
        centerTitle: true,
        elevation: 0,
      ),
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
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusTheme.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
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
                      const SizedBox(height: 14),
                      _buildStatusTimeline(status),
                      if (isLocatingOperator || isOperatorLocationStale) ...[
                        const SizedBox(height: 12),
                        _buildLocationStatusNotice(
                          isLocating: isLocatingOperator,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            'Booking ID',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              booking.bookingId,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDDE5F0)),
                        ),
                        child: Column(
                          children: [
                            _buildLocationRow(
                              Icons.location_on,
                              'Pick-up',
                              currentOrigin,
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(color: Color(0xFFDDE5F0)),
                            ),
                            _buildLocationRow(
                              Icons.flag,
                              'Drop-off',
                              currentDestination,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoTile(
                              icon: Icons.people,
                              label: 'Passengers',
                              value:
                                  '$currentPassengerCount ${currentPassengerCount == 1 ? 'Passenger' : 'Passengers'}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoTile(
                              icon: Icons.account_balance_wallet,
                              label: 'Payment',
                              value:
                                  '${PaymentMethods.label(paymentMethod)} • ${_formatStatusLabel(paymentStatus)}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildStateGuidance(status),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canCancel
                                ? const Color(0xFFD64545)
                                : const Color(0xFF0066CC),
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

  Widget _buildLocationRow(IconData icon, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF0066CC), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0066CC), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CameraPosition _cameraPositionFor(
    List<LatLng> routePoints,
    LatLng? originPoint,
    LatLng? destinationPoint,
    LatLng? operatorPoint,
  ) {
    if (routePoints.length >= 2) {
      return CameraPosition(target: _centerOfPoints(routePoints), zoom: 14);
    }

    if (originPoint != null && destinationPoint != null) {
      return CameraPosition(
        target: LatLng(
          (originPoint.latitude + destinationPoint.latitude) / 2,
          (originPoint.longitude + destinationPoint.longitude) / 2,
        ),
        zoom: 14,
      );
    }

    if (originPoint != null) {
      return CameraPosition(target: originPoint, zoom: 16);
    }

    if (destinationPoint != null) {
      return CameraPosition(target: destinationPoint, zoom: 16);
    }

    if (operatorPoint != null) {
      return CameraPosition(target: operatorPoint, zoom: 16);
    }

    return _fallbackCameraPosition;
  }

  Set<Marker> _buildMarkers({
    required LatLng? originPoint,
    required LatLng? destinationPoint,
    required LatLng? operatorPoint,
    required String originLabel,
    required String destinationLabel,
  }) {
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
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    if (operatorPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('operator_live'),
          position: operatorPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(
            title: 'Operator Location',
            snippet: 'Live location',
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines(
    BookingModel booking,
    LatLng? originPoint,
    LatLng? destinationPoint,
  ) {
    final routePoints = booking.routePolyline
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

    if (originPoint == null || destinationPoint == null) {
      return const <Polyline>{};
    }

    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [originPoint, destinationPoint],
        color: const Color(0xFF0066CC),
        width: 4,
      ),
    };
  }

  List<LatLng> _routePointsFor(BookingModel booking) {
    return booking.routePolyline
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);
  }

  LatLng? _operatorPointForBooking(BookingModel booking) {
    if (booking.status != BookingStatus.onTheWay) {
      return null;
    }
    if (booking.operatorLat == null || booking.operatorLng == null) {
      return null;
    }
    return LatLng(booking.operatorLat!, booking.operatorLng!);
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
        operatorPoint: operatorPoint,
      );
      await _followOperatorIfNeeded(status, operatorPoint);
    });
  }

  Future<void> _fitRouteIfNeeded({
    required String bookingId,
    required List<LatLng> routePoints,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
    required LatLng? operatorPoint,
  }) async {
    if (_mapController == null || _lastFittedBookingId == bookingId) {
      return;
    }

    final fitPoints = <LatLng>[
      ...routePoints,
      if (originPoint != null) originPoint,
      if (destinationPoint != null) destinationPoint,
      if (operatorPoint != null) operatorPoint,
    ];

    if (fitPoints.length < 2) {
      return;
    }

    await _animateToBounds(_boundsFromPoints(fitPoints));
    _lastFittedBookingId = bookingId;
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
        _distanceMeters(lastPoint, operatorPoint) >= _followRecenterDistanceMeters;

    if (!shouldFocus) {
      return;
    }

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLng(operatorPoint),
      );
      _lastFocusedOperatorPoint = operatorPoint;
      _lastOperatorFocusAt = DateTime.now();
    } catch (_) {
      // Ignore map camera errors; user can still view updates via markers.
    }
  }

  Future<void> _animateToBounds(LatLngBounds bounds) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 54));
    } catch (_) {
      // The map may not have laid out yet; retry once shortly after.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 54),
        );
      } catch (_) {
        // Ignore bounds-fit failure and keep default camera.
      }
    }
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

  Widget _buildStatusTimeline(BookingStatus status) {
    final steps = [
      _TimelineStep('Request Sent'),
      _TimelineStep('Operator Assigned'),
      _TimelineStep('Trip In Progress'),
      _TimelineStep('Trip Completed'),
    ];

    final currentIndex = _timelineIndex(status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Progress',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(steps.length, (i) {
            final step = steps[i];
            final reached = currentIndex >= i;
            final isCurrent = currentIndex == i;
            final isLast = i == steps.length - 1;

            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: reached
                          ? const Color(0xFF0066CC)
                          : const Color(0xFFD2DCEB),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: reached
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFF8A97A8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStateGuidance(BookingStatus status) {
    final guidance = _guidanceText(status);
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
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFD9FF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.near_me, size: 16, color: Color(0xFF0066CC)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLocating
                  ? 'Locating operator. Live position will appear shortly.'
                  : 'Operator location update is delayed. Showing the most recent known position.',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0E4A8A),
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

  String? _guidanceText(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return 'Looking for an available operator. You may keep waiting or cancel if your plans changed.';
      case BookingStatus.rejected:
        return 'No operator accepted this request. Tap Book Again to return and create a new booking.';
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
    if (lat == 0 && lng == 0) {
      return null;
    }
    return LatLng(lat, lng);
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
          color: Color(0xFF0066CC),
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
              'All available operators declined this request. Please create a new booking when an operator becomes available.',
          color: Colors.deepOrange,
        );
      case BookingStatus.unknown:
        return const _BookingStatusTheme(
          title: 'Booking Updated',
          message: 'This booking has been updated.',
          color: Color(0xFF0066CC),
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
