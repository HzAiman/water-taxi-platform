import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

enum _RoutePhase { toPickup, toDestination, none }

class OperatorMapLayers {
  const OperatorMapLayers._();

  static const double _closedLoopToleranceMeters = 12.0;

  static bool isActiveNavigationBooking(BookingModel booking) {
    return booking.status == BookingStatus.accepted ||
        booking.status == BookingStatus.onTheWay;
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
      passengerPickedUp ? '1' : '0',
      booking.passengerPickedUpAt?.millisecondsSinceEpoch.toString() ?? '-',
    ].join('|');
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
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
  }) {
    if (booking == null) {
      return const <LatLng>[];
    }

    var routePoints = resolvedRoutePointsForPhase(
      booking,
      passengerPickedUp: passengerPickedUp,
    );

    if (routePoints.length < 2) {
      routePoints = _phaseFallbackLine(
        booking,
        _resolveRoutePhase(booking, passengerPickedUp),
      );
    }

    return _trimRouteFromOperatorPosition(routePoints, booking);
  }

  static List<LatLng> resolvedRoutePointsForPhase(
    BookingModel booking, {
    required bool passengerPickedUp,
  }) {
    final phase = _resolveRoutePhase(booking, passengerPickedUp);
    return _routePointsForPhase(booking, phase);
  }

  static Set<Marker> buildMarkers(BookingModel? activeBooking) {
    final markers = <Marker>{};
    if (activeBooking == null) {
      return markers;
    }

    final passengerPickedUp = activeBooking.passengerPickedUpAt != null;
    final originLat = activeBooking.originLat;
    final originLng = activeBooking.originLng;
    if (!passengerPickedUp && _isValidLatLng(originLat, originLng)) {
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

    if (isActiveNavigationBooking(activeBooking)) {
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

  static Set<Polyline> buildPolylines(
    BookingModel? activeBooking, {
    List<LatLng>? routePointsOverride,
    required bool passengerPickedUp,
    double opacity = 1,
  }) {
    if (activeBooking == null) {
      return const <Polyline>{};
    }

    final phase = _resolveRoutePhase(activeBooking, passengerPickedUp);
    var routePoints = resolvedRoutePointsForPhase(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
    );

    // Use routePointsOverride only as a fallback/debug hook.
    if (routePoints.length < 2 && routePointsOverride != null) {
      routePoints = routePointsOverride
          .where((p) => _isValidLatLng(p.latitude, p.longitude))
          .toList(growable: false);
    }

    // Trim the live route so it visually progresses forward from the current
    // operator position instead of staying static.
    routePoints = _trimRouteFromOperatorPosition(routePoints, activeBooking);

    // Final fallback: if the phase route is missing, do not draw the old
    // origin->destination route. Use only a minimal phase-appropriate line.
    if (routePoints.length < 2) {
      routePoints = _phaseFallbackLine(activeBooking, phase);
    }

    if (routePoints.length < 2) {
      return const <Polyline>{};
    }

    final isPreview =
        phase == _RoutePhase.toPickup &&
        activeBooking.status == BookingStatus.accepted;

    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: routePoints,
        color: (isPreview ? const Color(0xFF94A3B8) : const Color(0xFF0066CC))
            .withValues(alpha: opacity.clamp(0, 1)),
        width: isPreview ? 3 : 5,
      ),
    };
  }

  static _RoutePhase _resolveRoutePhase(
    BookingModel booking,
    bool passengerPickedUp,
  ) {
    switch (booking.status) {
      case BookingStatus.accepted:
        return _RoutePhase.toPickup;
      case BookingStatus.onTheWay:
        return passengerPickedUp || booking.passengerPickedUpAt != null
            ? _RoutePhase.toDestination
            : _RoutePhase.toPickup;
      case BookingStatus.pending:
      case BookingStatus.completed:
      case BookingStatus.cancelled:
      case BookingStatus.rejected:
      case BookingStatus.unknown:
        return _RoutePhase.none;
    }
  }

  static List<LatLng> _routePointsForPhase(
    BookingModel booking,
    _RoutePhase phase,
  ) {
    final route = switch (phase) {
      _RoutePhase.toPickup => booking.routeToOriginPolyline,
      _RoutePhase.toDestination => booking.routeToDestinationPolyline,
      _RoutePhase.none => const <BookingRoutePoint>[],
    };

    final phasePoints = route
        .map((p) => LatLng(p.lat, p.lng))
        .where((p) => _isValidLatLng(p.latitude, p.longitude))
        .toList(growable: false);

    if (phasePoints.length >= 2) {
      final segmentedPhasePoints = _segmentFromRoutePoints(
        phasePoints,
        booking,
        phase,
      );
      if (segmentedPhasePoints.length >= 2) {
        return segmentedPhasePoints;
      }
      return phasePoints;
    }

    if (phase == _RoutePhase.toDestination) {
      // Important: never fall back to a generic pickup->dropoff polyline for
      // phase 2. If there is no true destination-phase route, draw the direct
      // operator->dropoff line instead.
      return const <LatLng>[];
    }

    return _segmentFromGenericRoutePolyline(booking, phase);
  }

  static List<LatLng> _trimRouteFromOperatorPosition(
    List<LatLng> routePoints,
    BookingModel booking,
  ) {
    final operatorPoint = _latLngOrNull(
      booking.operatorLat,
      booking.operatorLng,
    );
    if (operatorPoint == null || routePoints.length < 2) {
      return routePoints;
    }

    if (!_isValidLatLng(operatorPoint.latitude, operatorPoint.longitude)) {
      return routePoints;
    }

    var bestSegmentIndex = 0;
    var bestProjectedPoint = routePoints.first;
    var bestDistance = double.infinity;

    for (var i = 0; i < routePoints.length - 1; i++) {
      final projectedPoint = _projectPointOntoSegment(
        operatorPoint,
        routePoints[i],
        routePoints[i + 1],
      );
      final distance = _distanceMeters(operatorPoint, projectedPoint);
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
    _RoutePhase phase,
  ) {
    final operatorPoint = _latLngOrNull(
      booking.operatorLat,
      booking.operatorLng,
    );
    switch (phase) {
      case _RoutePhase.toPickup:
        if (operatorPoint != null &&
            _isValidLatLng(operatorPoint.latitude, operatorPoint.longitude) &&
            _isValidLatLng(booking.originLat, booking.originLng)) {
          return <LatLng>[
            operatorPoint,
            LatLng(booking.originLat, booking.originLng),
          ];
        }
        return const <LatLng>[];
      case _RoutePhase.toDestination:
        if (operatorPoint != null &&
            _isValidLatLng(operatorPoint.latitude, operatorPoint.longitude) &&
            _isValidLatLng(booking.destinationLat, booking.destinationLng)) {
          return <LatLng>[
            operatorPoint,
            LatLng(booking.destinationLat, booking.destinationLng),
          ];
        }
        return const <LatLng>[];
      case _RoutePhase.none:
        return const <LatLng>[];
    }
  }

  static List<LatLng> _segmentFromGenericRoutePolyline(
    BookingModel booking,
    _RoutePhase phase,
  ) {
    final genericPoints = booking.routePolyline
        .map((p) => LatLng(p.lat, p.lng))
        .where((p) => _isValidLatLng(p.latitude, p.longitude))
        .toList(growable: false);
    return _segmentFromRoutePoints(genericPoints, booking, phase);
  }

  static List<LatLng> _segmentFromRoutePoints(
    List<LatLng> routePoints,
    BookingModel booking,
    _RoutePhase phase,
  ) {
    final genericPoints = routePoints;
    if (genericPoints.length < 2) {
      return const <LatLng>[];
    }

    // Important: phase 2 must always resolve from the operator's current
    // location to the drop-off jetty. Never anchor the rendered segment at the
    // pickup jetty once the passenger has been picked up.
    final startPoint = switch (phase) {
      _RoutePhase.toPickup => _latLngOrNull(booking.operatorLat, booking.operatorLng),
      _RoutePhase.toDestination =>
        _latLngOrNull(booking.operatorLat, booking.operatorLng) ??
            LatLng(booking.originLat, booking.originLng),
      _RoutePhase.none => null,
    };
    final endPoint = switch (phase) {
      _RoutePhase.toPickup => LatLng(booking.originLat, booking.originLng),
      _RoutePhase.toDestination => LatLng(
        booking.destinationLat,
        booking.destinationLng,
      ),
      _RoutePhase.none => null,
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

    return _isClosedLoopPolyline(genericPoints)
        ? _extractShortestLoopSegment(genericPoints, startSnap, endSnap)
        : _extractLinearSegment(genericPoints, startSnap, endSnap);
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
