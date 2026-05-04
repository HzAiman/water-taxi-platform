import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

enum OperatorRoutePhase { toPickup, toDestination, none }

class OperatorHomeRouteMapper {
  const OperatorHomeRouteMapper._();

  static bool isActiveNavigationBooking(BookingModel booking) {
    return booking.status == BookingStatus.accepted ||
        booking.status == BookingStatus.onTheWay;
  }

  static OperatorRoutePhase resolveRoutePhase(BookingModel booking) {
    switch (booking.status) {
      case BookingStatus.accepted:
        return OperatorRoutePhase.toPickup;
      case BookingStatus.onTheWay:
        return booking.passengerPickedUpAt == null
            ? OperatorRoutePhase.toPickup
            : OperatorRoutePhase.toDestination;
      case BookingStatus.pending:
      case BookingStatus.completed:
      case BookingStatus.cancelled:
      case BookingStatus.rejected:
      case BookingStatus.unknown:
        return OperatorRoutePhase.none;
    }
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

    final phasePoints = isActiveNavigationBooking(booking)
        ? (passengerPickedUp
              ? booking.routeToDestinationPolyline
              : booking.routeToOriginPolyline)
        : const <BookingRoutePoint>[];

    var points = phasePoints
        .map((point) => _latLngOrNull(point.lat, point.lng))
        .whereType<LatLng>()
        .toList(growable: false);

    if (points.isEmpty && operatorPoint != null) {
      return <LatLng>[operatorPoint];
    }

    if (points.length >= 2 && operatorPoint != null) {
      points = _trimRouteFromOperatorPosition(points, operatorPoint);
    }

    if (points.length < 2) {
      points = _phaseFallbackLine(
        booking,
        passengerPickedUp: passengerPickedUp,
        operatorPoint: operatorPoint,
        destinationPoint: destinationPoint,
      );
    }

    return points.length < 2 ? const <LatLng>[] : points;
  }

  static Set<Polyline> buildPolylines(
    BookingModel? activeBooking, {
    List<LatLng>? routePointsOverride,
    double opacity = 1,
  }) {
    if (activeBooking == null) {
      return const <Polyline>{};
    }

    final passengerPickedUp = activeBooking.passengerPickedUpAt != null;
    final routePoints = trimmedRoutePointsForCamera(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
      operatorPoint: _latLngOrNull(
        activeBooking.operatorLat,
        activeBooking.operatorLng,
      ),
      destinationPoint: _latLngOrNull(
        activeBooking.destinationLat,
        activeBooking.destinationLng,
      ),
    );

    final effectiveRoutePoints = routePoints.length >= 2
        ? routePoints
        : routePointsOverride == null
            ? const <LatLng>[]
            : routePointsOverride
                .where((point) => _isValidLatLng(point.latitude, point.longitude))
                .toList(growable: false);

    if (effectiveRoutePoints.length < 2) {
      return const <Polyline>{};
    }

    final phase = resolveRoutePhase(activeBooking);
    final isPreview =
        phase == OperatorRoutePhase.toPickup &&
        activeBooking.status == BookingStatus.accepted;

    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: effectiveRoutePoints,
        color: (isPreview
                ? const Color(0xFF94A3B8)
                : const Color(0xFF0066CC))
            .withValues(alpha: opacity.clamp(0, 1)),
        width: isPreview ? 3 : 5,
      ),
    };
  }

  static LatLngBounds boundsFromPoints(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  static String routePhaseSignature(
    BookingModel? booking, {
    required bool passengerPickedUp,
  }) {
    if (booking == null) {
      return 'none';
    }

    return '${booking.bookingId}|${booking.status.firestoreValue}|${passengerPickedUp ? 1 : 0}';
  }

  static List<LatLng> _trimRouteFromOperatorPosition(
    List<LatLng> routePoints,
    LatLng operatorPoint,
  ) {
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
    BookingModel booking, {
    required bool passengerPickedUp,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
  }) {
    if (!passengerPickedUp) {
      final opLat = booking.operatorLat;
      final opLng = booking.operatorLng;
      if (operatorPoint != null &&
          opLat != null &&
          opLng != null &&
          _isValidLatLng(opLat, opLng) &&
          _isValidLatLng(booking.originLat, booking.originLng)) {
        return <LatLng>[
          LatLng(opLat, opLng),
          LatLng(booking.originLat, booking.originLng),
        ];
      }
      return const <LatLng>[];
    }

    if (_isValidLatLng(booking.originLat, booking.originLng) &&
        destinationPoint != null &&
        _isValidLatLng(destinationPoint.latitude, destinationPoint.longitude)) {
      return <LatLng>[
        LatLng(booking.originLat, booking.originLng),
        destinationPoint,
      ];
    }
    return const <LatLng>[];
  }

  static bool _isValidLatLng(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  static LatLng? _latLngOrNull(double? lat, double? lng) {
    if (lat == null || lng == null) {
      return null;
    }
    if (!_isValidLatLng(lat, lng) || (lat == 0 && lng == 0)) {
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
