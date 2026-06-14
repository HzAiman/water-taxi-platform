import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:operator_app/core/theme/operator_brand.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

enum OperatorRoutePhase { toPickup, toDestination, none }

enum OperatorRouteSource {
  routeToOriginPolyline,
  routeToDestinationPolyline,
  straightLineFallback,
  none,
}

class OperatorRouteHealth {
  const OperatorRouteHealth({
    required this.phase,
    required this.source,
    required this.routePoints,
    required this.label,
    this.warning,
  });

  final OperatorRoutePhase phase;
  final OperatorRouteSource source;
  final List<LatLng> routePoints;
  final String label;
  final String? warning;

  bool get usesFallback => source == OperatorRouteSource.straightLineFallback;
  bool get isReady =>
      source != OperatorRouteSource.none && routePoints.length >= 2;
}

class OperatorMapLayers {
  const OperatorMapLayers._();

  static const double _closedLoopToleranceMeters = 12.0;
  static const double _maxStopRouteAnchorDistanceMeters = 50.0;
  static const double _maxStopRouteSevereOffRouteMeters = 300.0;

  static bool isActiveNavigationBooking(BookingModel booking) {
    return booking.status == BookingStatus.onTheWay ||
        booking.poolStatus == 'in_progress';
  }

  static bool shouldShowOperatorMarker(BookingModel booking) {
    return booking.status == BookingStatus.accepted;
  }

  static String routePhaseSignature(
    BookingModel? booking, {
    required bool passengerPickedUp,
  }) {
    if (booking == null) {
      return 'none';
    }

    return [
      booking.bookingId,
      booking.status.firestoreValue,
      booking.currentStopId ?? booking.currentPoolStop?.stopId ?? '-',
      passengerPickedUp ? '1' : '0',
      booking.passengerPickedUpAt?.millisecondsSinceEpoch.toString() ?? '-',
    ].join('|');
  }

  static String routeGeometrySignature(List<LatLng> routePoints) {
    if (routePoints.isEmpty) {
      return 'empty';
    }

    var latChecksum = 0;
    var lngChecksum = 0;
    for (final point in routePoints) {
      latChecksum += (point.latitude * 100000).round();
      lngChecksum += (point.longitude * 100000).round();
    }

    return [
      routePoints.length.toString(),
      routePoints.first.latitude.toStringAsFixed(5),
      routePoints.first.longitude.toStringAsFixed(5),
      routePoints.last.latitude.toStringAsFixed(5),
      routePoints.last.longitude.toStringAsFixed(5),
      latChecksum.toString(),
      lngChecksum.toString(),
    ].join(',');
  }

  static LatLngBounds boundsFromPoints(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(southwest: LatLng(0, 0), northeast: LatLng(0, 0));
    }

    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;

    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  static List<LatLng> trimmedRoutePointsForCamera(
    BookingModel? booking, {
    required bool passengerPickedUp,
    LatLng? operatorPoint,
  }) {
    if (booking == null) {
      return const <LatLng>[];
    }

    final routePoints = resolvedRoutePointsForPhase(
      booking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
      includeOperatorAnchors: false,
    );
    if (booking.currentPoolStop != null) {
      return routePoints;
    }

    return _trimRouteFromOperatorPosition(
      routePoints,
      booking,
      operatorPoint: operatorPoint,
    );
  }

  static List<LatLng> resolvedRoutePointsForPhase(
    BookingModel booking, {
    required bool passengerPickedUp,
    LatLng? operatorPoint,
    bool includeOperatorAnchors = true,
  }) {
    final phase = _resolveRoutePhase(booking, passengerPickedUp);
    if (phase == OperatorRoutePhase.none) {
      return const <LatLng>[];
    }

    if (booking.currentPoolStop != null) {
      final stopRoute = _stopFirstRoutePoints(
        booking,
        operatorPoint: operatorPoint,
        includeLiveAnchors: includeOperatorAnchors,
      );
      if (_hasUsableStoredRoute(booking)) {
        return stopRoute;
      }

      return _phaseFallbackLine(
        booking,
        phase,
        operatorPoint: includeOperatorAnchors ? operatorPoint : null,
      );
    }

    final phaseRoute = _phaseRoutePoints(booking, phase);
    if (phaseRoute.length >= 2) {
      final segmented = _segmentFromRoutePoints(
        phaseRoute,
        booking,
        phase,
        operatorPoint: operatorPoint,
        includeLiveAnchors: includeOperatorAnchors,
      );
      if (segmented.length >= 2) {
        return segmented;
      }
    }

    return _phaseFallbackLine(
      booking,
      phase,
      operatorPoint: includeOperatorAnchors ? operatorPoint : null,
    );
  }

  static OperatorRouteHealth resolveRouteHealth(
    BookingModel? booking, {
    required bool passengerPickedUp,
    LatLng? operatorPoint,
  }) {
    if (booking == null) {
      return const OperatorRouteHealth(
        phase: OperatorRoutePhase.none,
        source: OperatorRouteSource.none,
        routePoints: <LatLng>[],
        label: 'No active route',
      );
    }

    final phase = _resolveRoutePhase(booking, passengerPickedUp);
    if (phase == OperatorRoutePhase.none) {
      return const OperatorRouteHealth(
        phase: OperatorRoutePhase.none,
        source: OperatorRouteSource.none,
        routePoints: <LatLng>[],
        label: 'No active route',
      );
    }

    final currentStop = booking.currentPoolStop;
    final fallbackPoints = _phaseFallbackLine(
      booking,
      phase,
      operatorPoint: operatorPoint,
    );
    if (currentStop != null) {
      final stopRoute = _stopFirstRoutePoints(
        booking,
        operatorPoint: operatorPoint,
        includeLiveAnchors: true,
      );
      final hasUsableStoredRoute =
          _hasUsableStoredRoute(booking) && stopRoute.length >= 2;
      return OperatorRouteHealth(
        phase: phase,
        source: hasUsableStoredRoute
            ? currentStop.isPickup
                  ? OperatorRouteSource.routeToOriginPolyline
                  : OperatorRouteSource.routeToDestinationPolyline
            : OperatorRouteSource.straightLineFallback,
        routePoints: hasUsableStoredRoute ? stopRoute : fallbackPoints,
        label: hasUsableStoredRoute
            ? currentStop.isPickup
                  ? 'Using route to pickup stop'
                  : 'Using route to dropoff stop'
            : 'Using straight-line fallback',
        warning: hasUsableStoredRoute
            ? null
            : 'Missing stop route geometry. Showing straight line to current stop.',
      );
    }

    final phaseRoute = _phaseRoutePoints(booking, phase);
    if (phaseRoute.length >= 2) {
      final segmented = _segmentFromRoutePoints(
        phaseRoute,
        booking,
        phase,
        operatorPoint: operatorPoint,
        includeLiveAnchors: true,
      );
      final routePoints = segmented.length >= 2 ? segmented : fallbackPoints;
      final usesSegmentedRoute = segmented.length >= 2;
      return OperatorRouteHealth(
        phase: phase,
        source: usesSegmentedRoute
            ? phase == OperatorRoutePhase.toPickup
                  ? OperatorRouteSource.routeToOriginPolyline
                  : OperatorRouteSource.routeToDestinationPolyline
            : OperatorRouteSource.straightLineFallback,
        routePoints: routePoints,
        label: usesSegmentedRoute
            ? currentStop != null
                  ? currentStop.isPickup
                        ? 'Using route to pickup stop'
                        : 'Using route to dropoff stop'
                  : phase == OperatorRoutePhase.toPickup
                  ? 'Using operator-to-pickup route'
                  : 'Using operator-to-dropoff route'
            : 'Using straight-line fallback',
        warning: usesSegmentedRoute
            ? null
            : currentStop != null
            ? 'Missing stop route geometry. Showing straight line to current stop.'
            : phase == OperatorRoutePhase.toPickup
            ? 'Missing routeToOriginPolyline. Showing straight line to pickup.'
            : 'Missing routeToDestinationPolyline. Showing straight line to dropoff.',
      );
    }

    return OperatorRouteHealth(
      phase: phase,
      source: OperatorRouteSource.straightLineFallback,
      routePoints: fallbackPoints,
      label: 'Using straight-line fallback',
      warning: booking.currentPoolStop != null
          ? 'Missing stop route geometry. Showing straight line to current stop.'
          : phase == OperatorRoutePhase.toPickup
          ? 'Missing routeToOriginPolyline. Showing straight line to pickup.'
          : 'Missing routeToDestinationPolyline. Showing straight line to dropoff.',
    );
  }

  static Set<Marker> buildMarkers(
    BookingModel? activeBooking, {
    LatLng? operatorPoint,
    double? operatorHeading,
  }) {
    final markers = <Marker>{};
    if (activeBooking == null) {
      return markers;
    }

    final currentStop = activeBooking.currentPoolStop;
    final passengerPickedUp = _isPassengerPickedUp(activeBooking);
    final originLat = activeBooking.originLat;
    final originLng = activeBooking.originLng;
    if (currentStop != null &&
        _isValidLatLng(currentStop.lat, currentStop.lng)) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_pool_stop'),
          position: LatLng(currentStop.lat, currentStop.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            currentStop.isPickup
                ? BitmapDescriptor.hueRed
                : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: currentStop.isPickup
                ? 'Next pickup stop'
                : 'Next drop-off stop',
            snippet: currentStop.stopName,
          ),
        ),
      );
    } else if (!passengerPickedUp && _isValidLatLng(originLat, originLng)) {
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

    final destLat = activeBooking.destinationLat;
    final destLng = activeBooking.destinationLng;
    if (currentStop == null &&
        passengerPickedUp &&
        _isValidLatLng(destLat, destLng)) {
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

    if (shouldShowOperatorMarker(activeBooking)) {
      final markerPoint =
          operatorPoint ??
          _latLngOrNull(activeBooking.operatorLat, activeBooking.operatorLng);
      if (markerPoint != null &&
          _isValidLatLng(markerPoint.latitude, markerPoint.longitude)) {
        markers.add(
          Marker(
            markerId: const MarkerId('operator_location'),
            position: markerPoint,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            rotation: operatorHeading ?? 0,
            flat: operatorHeading != null,
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

  static Set<Polyline> buildPolylines(
    BookingModel? activeBooking, {
    required bool passengerPickedUp,
    LatLng? operatorPoint,
    double opacity = 1,
  }) {
    if (activeBooking == null) {
      return const <Polyline>{};
    }

    final routeHealth = resolveRouteHealth(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: operatorPoint,
    );
    var routePoints = routeHealth.routePoints;

    // Stop-first routes are already segmented from the operator to the current
    // pool stop. Re-trimming them can preserve a straight live connector as
    // part of the rendered route, so only legacy booking-first phase routes are
    // trimmed here.
    if (activeBooking.currentPoolStop == null) {
      routePoints = _trimRouteFromOperatorPosition(
        routePoints,
        activeBooking,
        operatorPoint: operatorPoint,
      );
    }

    if (routePoints.length < 2) {
      return const <Polyline>{};
    }

    final isPreview =
        routeHealth.phase == OperatorRoutePhase.toPickup &&
        activeBooking.status == BookingStatus.accepted;
    final isFallback = routeHealth.usesFallback;

    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: routePoints,
        color:
            (isFallback
                    ? const Color(0xFFF59E0B)
                    : isPreview
                    ? const Color(0xFF94A3B8)
                    : OperatorBrand.navigationBlue)
                .withValues(alpha: opacity.clamp(0, 1)),
        width: isFallback ? 4 : (isPreview ? 3 : 5),
        patterns: isFallback
            ? <PatternItem>[PatternItem.dash(24), PatternItem.gap(12)]
            : const <PatternItem>[],
      ),
    };
  }

  static OperatorRoutePhase _resolveRoutePhase(
    BookingModel booking,
    bool passengerPickedUp,
  ) {
    final currentStop = booking.currentPoolStop;
    if (currentStop != null) {
      return currentStop.isPickup
          ? OperatorRoutePhase.toPickup
          : OperatorRoutePhase.toDestination;
    }

    switch (booking.status) {
      case BookingStatus.accepted:
        return OperatorRoutePhase.toPickup;
      case BookingStatus.onTheWay:
        return passengerPickedUp || booking.passengerPickedUpAt != null
            ? OperatorRoutePhase.toDestination
            : OperatorRoutePhase.toPickup;
      case BookingStatus.pending:
      case BookingStatus.completed:
      case BookingStatus.cancelled:
      case BookingStatus.rejected:
      case BookingStatus.unknown:
        return OperatorRoutePhase.none;
    }
  }

  static List<LatLng> _phaseRoutePoints(
    BookingModel booking,
    OperatorRoutePhase phase,
  ) {
    if (booking.currentPoolStop != null && booking.routePolyline.length >= 2) {
      return booking.routePolyline
          .map((p) => LatLng(p.lat, p.lng))
          .where((p) => _isValidLatLng(p.latitude, p.longitude))
          .toList(growable: false);
    }

    final route = switch (phase) {
      OperatorRoutePhase.toPickup => booking.routeToOriginPolyline,
      OperatorRoutePhase.toDestination => booking.routeToDestinationPolyline,
      OperatorRoutePhase.none => const <BookingRoutePoint>[],
    };

    return route
        .map((p) => LatLng(p.lat, p.lng))
        .where((p) => _isValidLatLng(p.latitude, p.longitude))
        .toList(growable: false);
  }

  static List<LatLng> _stopFirstRoutePoints(
    BookingModel booking, {
    LatLng? operatorPoint,
    required bool includeLiveAnchors,
  }) {
    final currentStop = booking.currentPoolStop;
    if (currentStop == null || booking.routePolyline.length < 2) {
      return const <LatLng>[];
    }

    final routePoints = booking.routePolyline
        .map((p) => LatLng(p.lat, p.lng))
        .where((p) => _isValidLatLng(p.latitude, p.longitude))
        .toList(growable: false);
    if (routePoints.length < 2) {
      return const <LatLng>[];
    }

    final startPoint =
        operatorPoint ??
        _latLngOrNull(booking.operatorLat, booking.operatorLng);
    final endPoint = LatLng(currentStop.lat, currentStop.lng);
    if (startPoint == null ||
        !_isValidLatLng(startPoint.latitude, startPoint.longitude) ||
        !_isValidLatLng(endPoint.latitude, endPoint.longitude)) {
      return const <LatLng>[];
    }

    final startSnap = _snapPointToRoute(startPoint, routePoints);
    final endSnap = _snapPointToRoute(endPoint, routePoints);
    if (startSnap == null || endSnap == null) {
      return const <LatLng>[];
    }

    final segment = _extractCurrentStopSegment(
      routePoints,
      startSnap,
      endSnap,
      routeDirection: booking.routeDirection,
    );
    final startSnapDistance = _distanceMeters(startPoint, startSnap.point);
    if (startSnapDistance > _maxStopRouteSevereOffRouteMeters) {
      return const <LatLng>[];
    }
    if (!includeLiveAnchors) {
      return segment;
    }

    return _attachLiveAnchors(
      segment,
      startPoint,
      endPoint,
      maxStartAnchorDistanceMeters: _maxStopRouteAnchorDistanceMeters,
    );
  }

  static bool _hasUsableStoredRoute(BookingModel booking) {
    if (booking.routePolyline.length < 2) {
      return false;
    }
    var validPointCount = 0;
    for (final point in booking.routePolyline) {
      if (_isValidLatLng(point.lat, point.lng)) {
        validPointCount++;
      }
      if (validPointCount >= 2) {
        return true;
      }
    }
    return false;
  }

  static List<LatLng> _trimRouteFromOperatorPosition(
    List<LatLng> routePoints,
    BookingModel booking, {
    LatLng? operatorPoint,
  }) {
    final liveOperatorPoint =
        operatorPoint ??
        _latLngOrNull(booking.operatorLat, booking.operatorLng);
    if (liveOperatorPoint == null || routePoints.length < 2) {
      return routePoints;
    }

    if (!_isValidLatLng(
      liveOperatorPoint.latitude,
      liveOperatorPoint.longitude,
    )) {
      return routePoints;
    }

    var bestSegmentIndex = 0;
    var bestProjectedPoint = routePoints.first;
    var bestDistance = double.infinity;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final projectedPoint = _projectPointOntoSegment(
        liveOperatorPoint,
        routePoints[i],
        routePoints[i + 1],
      );
      final distance = _distanceMeters(liveOperatorPoint, projectedPoint);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestProjectedPoint = projectedPoint;
        bestSegmentIndex = i;
      }
    }

    final trimmedPoints = <LatLng>[bestProjectedPoint];
    trimmedPoints.addAll(routePoints.skip(bestSegmentIndex + 1));
    return trimmedPoints;
  }

  static List<LatLng> _phaseFallbackLine(
    BookingModel booking,
    OperatorRoutePhase phase, {
    LatLng? operatorPoint,
  }) {
    final liveOperatorPoint =
        operatorPoint ??
        _latLngOrNull(booking.operatorLat, booking.operatorLng);
    final currentStop = booking.currentPoolStop;
    if (currentStop != null &&
        liveOperatorPoint != null &&
        _isValidLatLng(
          liveOperatorPoint.latitude,
          liveOperatorPoint.longitude,
        ) &&
        _isValidLatLng(currentStop.lat, currentStop.lng)) {
      return <LatLng>[
        liveOperatorPoint,
        LatLng(currentStop.lat, currentStop.lng),
      ];
    }
    switch (phase) {
      case OperatorRoutePhase.toPickup:
        if (liveOperatorPoint != null &&
            _isValidLatLng(
              liveOperatorPoint.latitude,
              liveOperatorPoint.longitude,
            ) &&
            _isValidLatLng(booking.originLat, booking.originLng)) {
          return <LatLng>[
            liveOperatorPoint,
            LatLng(booking.originLat, booking.originLng),
          ];
        }
        return const <LatLng>[];
      case OperatorRoutePhase.toDestination:
        if (liveOperatorPoint != null &&
            _isValidLatLng(
              liveOperatorPoint.latitude,
              liveOperatorPoint.longitude,
            ) &&
            _isValidLatLng(booking.destinationLat, booking.destinationLng)) {
          return <LatLng>[
            liveOperatorPoint,
            LatLng(booking.destinationLat, booking.destinationLng),
          ];
        }
        return const <LatLng>[];
      case OperatorRoutePhase.none:
        return const <LatLng>[];
    }
  }

  static List<LatLng> _segmentFromRoutePoints(
    List<LatLng> routePoints,
    BookingModel booking,
    OperatorRoutePhase phase, {
    LatLng? operatorPoint,
    bool includeLiveAnchors = true,
  }) {
    final genericPoints = routePoints;
    if (genericPoints.length < 2) {
      return const <LatLng>[];
    }

    // Important: phase 2 must always resolve from the operator's current
    // location to the drop-off jetty. Never anchor the rendered segment at the
    // pickup jetty once the passenger has been picked up.
    final startPoint = switch (phase) {
      OperatorRoutePhase.toPickup =>
        operatorPoint ??
            _latLngOrNull(booking.operatorLat, booking.operatorLng),
      OperatorRoutePhase.toDestination =>
        operatorPoint ??
            _latLngOrNull(booking.operatorLat, booking.operatorLng),
      OperatorRoutePhase.none => null,
    };
    final currentStop = booking.currentPoolStop;
    final endPoint = currentStop != null
        ? LatLng(currentStop.lat, currentStop.lng)
        : switch (phase) {
            OperatorRoutePhase.toPickup => LatLng(
              booking.originLat,
              booking.originLng,
            ),
            OperatorRoutePhase.toDestination => LatLng(
              booking.destinationLat,
              booking.destinationLng,
            ),
            OperatorRoutePhase.none => null,
          };

    if (startPoint == null ||
        endPoint == null ||
        !_isValidLatLng(startPoint.latitude, startPoint.longitude) ||
        !_isValidLatLng(endPoint.latitude, endPoint.longitude)) {
      return const <LatLng>[];
    }

    final startSnap = _snapPointToRoute(startPoint, genericPoints);
    final endSnap = _snapPointToRoute(endPoint, genericPoints);
    if (startSnap == null || endSnap == null) {
      return const <LatLng>[];
    }

    final segment = _extractDirectedSegment(
      genericPoints,
      startSnap,
      endSnap,
      routeDirection: booking.routeDirection,
    );
    if (!includeLiveAnchors) {
      return segment;
    }
    return _attachLiveAnchors(
      segment,
      startPoint,
      endPoint,
      maxStartAnchorDistanceMeters: currentStop == null
          ? null
          : _maxStopRouteAnchorDistanceMeters,
    );
  }

  static List<LatLng> _attachLiveAnchors(
    List<LatLng> segmentedRoute,
    LatLng startPoint,
    LatLng endPoint, {
    double? maxStartAnchorDistanceMeters,
  }) {
    final firstRoutePoint = segmentedRoute.isNotEmpty
        ? segmentedRoute.first
        : startPoint;
    final shouldAttachStart =
        maxStartAnchorDistanceMeters == null ||
        _distanceMeters(startPoint, firstRoutePoint) <=
            maxStartAnchorDistanceMeters;
    final anchored = <LatLng>[if (shouldAttachStart) startPoint];
    for (final point in segmentedRoute) {
      _addIfDistinct(anchored, point);
    }
    _addIfDistinct(anchored, endPoint);
    return anchored;
  }

  static _SnappedRoutePoint? _snapPointToRoute(
    LatLng point,
    List<LatLng> routePoints,
  ) {
    if (routePoints.length < 2) {
      return null;
    }

    var bestSegmentIndex = 0;
    var bestProjectedPoint = routePoints.first;
    var bestDistance = double.infinity;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final projectedPoint = _projectPointOntoSegment(
        point,
        routePoints[i],
        routePoints[i + 1],
      );
      final distance = _distanceMeters(point, projectedPoint);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestProjectedPoint = projectedPoint;
        bestSegmentIndex = i;
      }
    }

    return _SnappedRoutePoint(
      point: bestProjectedPoint,
      segmentIndex: bestSegmentIndex,
    );
  }

  static List<LatLng> _extractLinearSegment(
    List<LatLng> routePoints,
    _SnappedRoutePoint startSnap,
    _SnappedRoutePoint endSnap,
  ) {
    final segment = <LatLng>[startSnap.point];

    if (startSnap.segmentIndex <= endSnap.segmentIndex) {
      for (var i = startSnap.segmentIndex + 1; i <= endSnap.segmentIndex; i++) {
        _addIfDistinct(segment, routePoints[i]);
      }
    } else {
      for (var i = startSnap.segmentIndex; i >= endSnap.segmentIndex + 1; i--) {
        _addIfDistinct(segment, routePoints[i]);
      }
    }

    _addIfDistinct(segment, endSnap.point);
    return segment;
  }

  static List<LatLng> _extractShortestLoopSegment(
    List<LatLng> routePoints,
    _SnappedRoutePoint startSnap,
    _SnappedRoutePoint endSnap,
  ) {
    final forward = _extractLoopSegment(
      routePoints,
      startSnap,
      endSnap,
      step: 1,
    );
    final backward = _extractLoopSegment(
      routePoints,
      startSnap,
      endSnap,
      step: -1,
    );
    return _polylineLengthMeters(backward) < _polylineLengthMeters(forward)
        ? backward
        : forward;
  }

  static List<LatLng> _extractDirectedSegment(
    List<LatLng> routePoints,
    _SnappedRoutePoint startSnap,
    _SnappedRoutePoint endSnap, {
    String? routeDirection,
  }) {
    if (!_isClosedLoopPolyline(routePoints)) {
      return _extractLinearSegment(routePoints, startSnap, endSnap);
    }

    final normalizedDirection = routeDirection?.trim().toLowerCase();
    if (normalizedDirection == 'forward') {
      return _extractLoopSegment(routePoints, startSnap, endSnap, step: 1);
    }
    if (normalizedDirection == 'reverse') {
      return _extractLoopSegment(routePoints, startSnap, endSnap, step: -1);
    }
    return _extractShortestLoopSegment(routePoints, startSnap, endSnap);
  }

  static List<LatLng> _extractCurrentStopSegment(
    List<LatLng> routePoints,
    _SnappedRoutePoint startSnap,
    _SnappedRoutePoint endSnap, {
    String? routeDirection,
  }) {
    if (!_isClosedLoopPolyline(routePoints)) {
      return _extractDirectedSegment(
        routePoints,
        startSnap,
        endSnap,
        routeDirection: routeDirection,
      );
    }
    return _extractShortestLoopSegment(routePoints, startSnap, endSnap);
  }

  static List<LatLng> _extractLoopSegment(
    List<LatLng> routePoints,
    _SnappedRoutePoint startSnap,
    _SnappedRoutePoint endSnap, {
    required int step,
  }) {
    final segment = <LatLng>[startSnap.point];
    final segmentCount = routePoints.length - 1;
    var index = startSnap.segmentIndex;
    var guard = 0;

    while (index != endSnap.segmentIndex && guard <= segmentCount + 1) {
      if (step > 0) {
        final nextIndex = (index + 1) % segmentCount;
        _addIfDistinct(segment, routePoints[nextIndex]);
        index = nextIndex;
      } else {
        _addIfDistinct(segment, routePoints[index]);
        index = (index - 1 + segmentCount) % segmentCount;
      }
      guard++;
    }

    _addIfDistinct(segment, endSnap.point);
    return segment;
  }

  static bool _isClosedLoopPolyline(List<LatLng> points) {
    if (points.length < 3) {
      return false;
    }
    return _distanceMeters(points.first, points.last) <=
        _closedLoopToleranceMeters;
  }

  static void _addIfDistinct(List<LatLng> points, LatLng next) {
    if (points.isEmpty) {
      points.add(next);
      return;
    }

    final last = points.last;
    if ((last.latitude - next.latitude).abs() < 1e-9 &&
        (last.longitude - next.longitude).abs() < 1e-9) {
      return;
    }
    points.add(next);
  }

  static double _polylineLengthMeters(List<LatLng> points) {
    if (points.length < 2) {
      return 0;
    }

    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _distanceMeters(points[i], points[i + 1]);
    }
    return total;
  }

  static bool _isValidLatLng(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  static LatLng? _latLngOrNull(double? lat, double? lng) {
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  static bool _isPassengerPickedUp(BookingModel booking) {
    return booking.passengerPickedUpAt != null ||
        booking.pickedUpAt != null ||
        booking.onboard ||
        booking.poolPhase?.trim().toLowerCase() == 'onboard';
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(b.latitude - a.latitude);
    final dLng = _degreesToRadians(b.longitude - a.longitude);
    final lat1 = _degreesToRadians(a.latitude);
    final lat2 = _degreesToRadians(b.latitude);

    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(h));
  }

  static LatLng _projectPointOntoSegment(
    LatLng point,
    LatLng segmentStart,
    LatLng segmentEnd,
  ) {
    final segmentVectorLat = segmentEnd.latitude - segmentStart.latitude;
    final segmentVectorLng = segmentEnd.longitude - segmentStart.longitude;
    final pointVectorLat = point.latitude - segmentStart.latitude;
    final pointVectorLng = point.longitude - segmentStart.longitude;

    final segmentLengthSquared =
        (segmentVectorLat * segmentVectorLat) +
        (segmentVectorLng * segmentVectorLng);
    if (segmentLengthSquared == 0) {
      return segmentStart;
    }

    final projectionRatio =
        ((pointVectorLat * segmentVectorLat) +
            (pointVectorLng * segmentVectorLng)) /
        segmentLengthSquared;
    final clampedRatio = projectionRatio.clamp(0.0, 1.0);

    return LatLng(
      segmentStart.latitude + (segmentVectorLat * clampedRatio),
      segmentStart.longitude + (segmentVectorLng * clampedRatio),
    );
  }

  static double _degreesToRadians(double degrees) => degrees * (math.pi / 180);
}

class _SnappedRoutePoint {
  const _SnappedRoutePoint({required this.point, required this.segmentIndex});

  final LatLng point;
  final int segmentIndex;
}
