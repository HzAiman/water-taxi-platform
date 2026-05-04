import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

enum _RoutePhase { toPickup, toDestination, none }

class OperatorMapLayers {
  const OperatorMapLayers._();

  static Set<Marker> buildMarkers(BookingModel? activeBooking) {
    final markers = <Marker>{};
    if (activeBooking == null) {
      return markers;
    }

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

    if (_shouldShowOperatorMarker(activeBooking.status)) {
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
    double opacity = 1,
  }) {
    if (activeBooking == null) {
      return const <Polyline>{};
    }

    final phase = _resolveRoutePhase(activeBooking);
    var routePoints = _routePointsForPhase(activeBooking, phase);

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

  static _RoutePhase _resolveRoutePhase(BookingModel booking) {
    switch (booking.status) {
      case BookingStatus.accepted:
        return _RoutePhase.toPickup;
      case BookingStatus.onTheWay:
        return booking.passengerPickedUpAt == null
            ? _RoutePhase.toPickup
            : _RoutePhase.toDestination;
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

    return route
        .map((p) => LatLng(p.lat, p.lng))
        .where((p) => _isValidLatLng(p.latitude, p.longitude))
        .toList(growable: false);
  }

  static List<LatLng> _trimRouteFromOperatorPosition(
    List<LatLng> routePoints,
    BookingModel booking,
  ) {
    final opLat = booking.operatorLat;
    final opLng = booking.operatorLng;
    if (opLat == null || opLng == null || routePoints.length < 2) {
      return routePoints;
    }

    final operatorPoint = LatLng(opLat, opLng);
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
    switch (phase) {
      case _RoutePhase.toPickup:
        final opLat = booking.operatorLat;
        final opLng = booking.operatorLng;
        if (opLat != null &&
            opLng != null &&
            _isValidLatLng(opLat, opLng) &&
            _isValidLatLng(booking.originLat, booking.originLng)) {
          return <LatLng>[
            LatLng(opLat, opLng),
            LatLng(booking.originLat, booking.originLng),
          ];
        }
        return const <LatLng>[];
      case _RoutePhase.toDestination:
        if (_isValidLatLng(booking.originLat, booking.originLng) &&
            _isValidLatLng(booking.destinationLat, booking.destinationLng)) {
          return <LatLng>[
            LatLng(booking.originLat, booking.originLng),
            LatLng(booking.destinationLat, booking.destinationLng),
          ];
        }
        return const <LatLng>[];
      case _RoutePhase.none:
        return const <LatLng>[];
    }
  }

  static bool _isValidLatLng(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  static bool _shouldShowOperatorMarker(BookingStatus status) {
    return status == BookingStatus.accepted || status == BookingStatus.onTheWay;
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
