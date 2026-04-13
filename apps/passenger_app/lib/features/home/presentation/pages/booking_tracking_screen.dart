import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    required EdgeInsets padding,
  })?
  mapBuilder;

  @override
  State<BookingTrackingScreen> createState() => _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends State<BookingTrackingScreen> {
  final DateTime _openedAt = DateTime.now();

  GoogleMapController? _mapController;
  String? _lastFittedCameraSignature;
  LatLng? _lastFocusedOperatorPoint;
  DateTime? _lastOperatorFocusAt;
  String? _lastMarkerSetSignature;
  Set<Marker> _cachedMarkers = <Marker>{};
  String? _lastPolylineSetSignature;
  Set<Polyline> _cachedPolylines = <Polyline>{};
  DateTime? _lastMapPayloadLogAt;

  static const Duration _followRecenterInterval = Duration(seconds: 4);
  static const double _followRecenterDistanceMeters = 20;
  static const double _routeBoundsPadding = 220;
  static const double _routePreviewZoom = 14.5;
  static const double _singlePointZoom = 15.0;

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
      final slowLoad =
          viewModel.isLoading &&
          DateTime.now().difference(_openedAt) > const Duration(seconds: 6);

      return Scaffold(
        appBar: AppBar(
          title: const Text('Booking Status'),
          centerTitle: true,
          elevation: 0,
        ),
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
    final routePoints = _routePointsFor(
      booking,
      originPoint,
      destinationPoint,
    );
    final operatorPoint = _operatorPointForBooking(booking);
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
      mapPadding: mapPadding,
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
                      mapPadding: mapPadding,
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
                      _buildStateGuidance(booking),
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

  EdgeInsets _mapPaddingFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomPadding = (size.height * 0.46).clamp(
      220.0,
      420.0,
    );
    return EdgeInsets.only(
      top: 64,
      bottom: bottomPadding,
      left: 48,
      right: 48,
    );
  }

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
      return CameraPosition(target: _centerOfPoints(routePoints), zoom: _routePreviewZoom);
    }

    if (originPoint != null && destinationPoint != null) {
      return CameraPosition(
        target: LatLng(
          (originPoint.latitude + destinationPoint.latitude) / 2,
          (originPoint.longitude + destinationPoint.longitude) / 2,
        ),
        zoom: _routePreviewZoom,
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

  Set<Polyline> _buildPolylines(
      {
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
          color: const Color(0xFF0066CC),
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
        color: const Color(0xFF0066CC),
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
    required EdgeInsets mapPadding,
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
        mapPadding: mapPadding,
      );
      await _followOperatorIfNeeded(
        status,
        operatorPoint,
        routePoints,
        originPoint,
        destinationPoint,
        mapPadding,
      );
    });
  }

  Future<void> _fitRouteIfNeeded({
    required String bookingId,
    required List<LatLng> routePoints,
    required LatLng? originPoint,
    required LatLng? destinationPoint,
    required LatLng? operatorPoint,
    required EdgeInsets mapPadding,
  }) async {
    if (_mapController == null) {
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

    final signature = _cameraSignature(
      bookingId: bookingId,
      points: fitPoints,
      mapPadding: mapPadding,
    );
    if (_lastFittedCameraSignature == signature) {
      return;
    }

    await _animateToBounds(_boundsFromPoints(fitPoints), mapPadding);
    _lastFittedCameraSignature = signature;
  }

  Future<void> _followOperatorIfNeeded(
    BookingStatus status,
    LatLng? operatorPoint,
    List<LatLng> routePoints,
    LatLng? originPoint,
    LatLng? destinationPoint,
    EdgeInsets mapPadding,
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

    final focusPoints = <LatLng>[
      operatorPoint,
      ...routePoints,
      if (destinationPoint != null) destinationPoint,
      if (originPoint != null) originPoint,
    ];

    try {
      if (focusPoints.length >= 2) {
        await _animateToBounds(_boundsFromPoints(focusPoints), mapPadding);
      } else {
        await _mapController!.animateCamera(CameraUpdate.newLatLng(operatorPoint));
      }
      _lastFocusedOperatorPoint = operatorPoint;
      _lastOperatorFocusAt = DateTime.now();
    } catch (_) {
      // Ignore map camera errors; user can still view updates via markers.
    }
  }

  String _cameraSignature({
    required String bookingId,
    required List<LatLng> points,
    required EdgeInsets mapPadding,
  }) {
    final quantizedTop = (mapPadding.top / 12).round() * 12;
    final quantizedBottom = (mapPadding.bottom / 12).round() * 12;
    final quantizedLeft = (mapPadding.left / 12).round() * 12;
    final quantizedRight = (mapPadding.right / 12).round() * 12;

    final buffer = StringBuffer(bookingId);
    buffer
      ..write('|pad:')
      ..write(quantizedTop.toStringAsFixed(1))
      ..write(',')
      ..write(quantizedBottom.toStringAsFixed(1))
      ..write(',')
      ..write(quantizedLeft.toStringAsFixed(1))
      ..write(',')
      ..write(quantizedRight.toStringAsFixed(1));
    for (final p in points) {
      buffer
        ..write('|')
        ..write(p.latitude.toStringAsFixed(5))
        ..write(',')
        ..write(p.longitude.toStringAsFixed(5));
    }
    return buffer.toString();
  }

  Future<void> _animateToBounds(
    LatLngBounds bounds,
    EdgeInsets mapPadding,
  ) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final effectivePadding = math.max(
      _routeBoundsPadding,
      mapPadding.bottom * 0.55,
    );

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, effectivePadding),
      );
    } catch (_) {
      // The map may not have laid out yet; retry once shortly after.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, effectivePadding),
        );
      } catch (_) {
        // Ignore bounds-fit failure and keep default camera.
      }
    }
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
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
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

  String? _guidanceText(BookingModel booking) {
    switch (booking.status) {
      case BookingStatus.pending:
        final createdAt = booking.createdAt;
        if (createdAt != null &&
            DateTime.now().difference(createdAt) > const Duration(minutes: 1)) {
          return 'Operator assignment is taking longer than usual. You can keep waiting, or cancel and try another route/time.';
        }
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
