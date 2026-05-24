import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:operator_app/features/home/presentation/map/operator_map_layers.dart';

class OperatorNavigationGuidance {
  const OperatorNavigationGuidance({
    required this.bookingId,
    required this.nearestRouteMarker,
    required this.nextRouteMarker,
    required this.totalRouteMarkers,
    required this.progressFraction,
    required this.remainingDistanceMeters,
    required this.offRouteDistanceMeters,
    required this.isOffRoute,
    required this.speedMetersPerSecond,
    required this.eta,
    required this.headingDegrees,
    required this.offRouteSeverity,
    required this.rejoinPoint,
    required this.routeHealth,
    required this.stopOvershootSeverity,
    required this.stopOvershootDistanceMeters,
  });

  final String bookingId;
  final int nearestRouteMarker;
  final int nextRouteMarker;
  final int totalRouteMarkers;
  final double progressFraction;
  final double remainingDistanceMeters;
  final double offRouteDistanceMeters;
  final bool isOffRoute;
  final double? speedMetersPerSecond;
  final Duration? eta;
  final double? headingDegrees;
  final OperatorOffRouteSeverity offRouteSeverity;
  final BookingRoutePoint? rejoinPoint;
  final OperatorRouteHealth routeHealth;
  final OperatorStopOvershootSeverity stopOvershootSeverity;
  final double stopOvershootDistanceMeters;

  bool get shouldPauseProgress =>
      offRouteSeverity == OperatorOffRouteSeverity.severe;
  bool get shouldPauseEta =>
      offRouteSeverity == OperatorOffRouteSeverity.severe;
  bool get isEtaLowConfidence =>
      offRouteSeverity == OperatorOffRouteSeverity.moderate;
}

enum OperatorOffRouteSeverity { onRoute, mild, moderate, severe }

enum OperatorStopOvershootSeverity { none, soft, missed }

OperatorNavigationGuidance? computeOperatorNavigationGuidance({
  required BookingModel booking,
  required double currentLat,
  required double currentLng,
  required DateTime now,
  double? reportedSpeedMps,
  double? smoothedSpeedMps,
  DateTime? lastSampleAt,
  double? lastSampleLat,
  double? lastSampleLng,
  int? lastResolvedRouteMarker,
  double offRouteToleranceMeters = 80,
}) {
  if (booking.status != BookingStatus.onTheWay) {
    return null;
  }

  const severeOffRouteCapMeters = 5000.0;

  final passengerPickedUp = booking.passengerPickedUpAt != null;
  final liveOperatorPoint = LatLng(currentLat, currentLng);
  final routeHealth = OperatorMapLayers.resolveRouteHealth(
    booking,
    passengerPickedUp: passengerPickedUp,
    operatorPoint: liveOperatorPoint,
  );
  final polyline =
      OperatorMapLayers.resolvedRoutePointsForPhase(
            booking,
            passengerPickedUp: passengerPickedUp,
            operatorPoint: liveOperatorPoint,
            includeOperatorAnchors: false,
          )
          .map(
            (point) =>
                BookingRoutePoint(lat: point.latitude, lng: point.longitude),
          )
          .toList(growable: false);
  final startLat = currentLat;
  final startLng = currentLng;
  final currentStop = booking.currentPoolStop;
  final endLat =
      currentStop?.lat ??
      (passengerPickedUp ? booking.destinationLat : booking.originLat);
  final endLng =
      currentStop?.lng ??
      (passengerPickedUp ? booking.destinationLng : booking.originLng);
  final projection = _projectProgressOnRoute(
    currentLat: currentLat,
    currentLng: currentLng,
    originLat: startLat,
    originLng: startLng,
    destinationLat: endLat,
    destinationLng: endLng,
    routePolyline: polyline,
  );

  final totalRouteMarkers = max(polyline.length, 2);
  var progressFraction = projection.progressFraction;
  var remainingDistanceMeters = projection.remainingDistanceMeters;
  var offRouteDistanceMeters = projection.offRouteDistanceMeters;
  final offRouteSeverity = _resolveOffRouteSeverity(
    offRouteDistanceMeters,
    offRouteToleranceMeters,
  );
  final stopOvershoot = _resolveStopOvershoot(
    booking: booking,
    currentLat: currentLat,
    currentLng: currentLng,
    now: now,
    lastSampleAt: lastSampleAt,
    lastSampleLat: lastSampleLat,
    lastSampleLng: lastSampleLng,
    offRouteSeverity: offRouteSeverity,
  );

  if (offRouteDistanceMeters > severeOffRouteCapMeters) {
    final floorMarker = lastResolvedRouteMarker ?? 1;
    final minProgress = totalRouteMarkers <= 1
        ? 0.0
        : ((floorMarker - 1) / (totalRouteMarkers - 1)).clamp(0.0, 1.0);
    progressFraction = max(progressFraction, minProgress).clamp(0.0, 1.0);
    remainingDistanceMeters = _routeTotalDistanceMeters(
      originLat: startLat,
      originLng: startLng,
      destinationLat: endLat,
      destinationLng: endLng,
      routePolyline: polyline,
    );
    offRouteDistanceMeters = severeOffRouteCapMeters;
  }

  if (offRouteSeverity == OperatorOffRouteSeverity.severe &&
      lastResolvedRouteMarker != null &&
      totalRouteMarkers > 1) {
    progressFraction = ((lastResolvedRouteMarker - 1) / (totalRouteMarkers - 1))
        .clamp(0.0, 1.0);
  }

  var nearestRouteMarker =
      (progressFraction * (totalRouteMarkers - 1)).round() + 1;
  nearestRouteMarker = nearestRouteMarker.clamp(1, totalRouteMarkers).toInt();

  if (lastResolvedRouteMarker != null &&
      nearestRouteMarker < lastResolvedRouteMarker) {
    nearestRouteMarker = lastResolvedRouteMarker
        .clamp(1, totalRouteMarkers)
        .toInt();
  }

  final nextRouteMarker = (nearestRouteMarker + 1)
      .clamp(1, totalRouteMarkers)
      .toInt();

  final instantSpeed = _resolveEffectiveSpeedMps(
    reportedSpeedMps: reportedSpeedMps,
    now: now,
    lastSampleAt: lastSampleAt,
    currentLat: currentLat,
    currentLng: currentLng,
    lastSampleLat: lastSampleLat,
    lastSampleLng: lastSampleLng,
  );
  final etaSpeed = smoothedSpeedMps != null && smoothedSpeedMps >= 0.5
      ? smoothedSpeedMps
      : instantSpeed;

  Duration? eta;
  if (etaSpeed != null &&
      etaSpeed >= 0.5 &&
      remainingDistanceMeters > 0 &&
      offRouteSeverity != OperatorOffRouteSeverity.severe) {
    eta = Duration(seconds: (remainingDistanceMeters / etaSpeed).round());
  }

  return OperatorNavigationGuidance(
    bookingId: booking.bookingId,
    nearestRouteMarker: nearestRouteMarker,
    nextRouteMarker: nextRouteMarker,
    totalRouteMarkers: totalRouteMarkers,
    progressFraction: progressFraction,
    remainingDistanceMeters: remainingDistanceMeters,
    offRouteDistanceMeters: offRouteDistanceMeters,
    isOffRoute: offRouteDistanceMeters > offRouteToleranceMeters,
    speedMetersPerSecond: etaSpeed,
    eta: eta,
    headingDegrees: _resolveHeadingDegrees(
      currentLat: currentLat,
      currentLng: currentLng,
      lastSampleLat: lastSampleLat,
      lastSampleLng: lastSampleLng,
      routePolyline: polyline,
      nearestSegmentIndex: projection.nearestSegmentIndex,
    ),
    offRouteSeverity: offRouteSeverity,
    rejoinPoint: projection.rejoinPoint,
    routeHealth: routeHealth,
    stopOvershootSeverity: stopOvershoot.severity,
    stopOvershootDistanceMeters: stopOvershoot.distanceMeters,
  );
}

_StopOvershoot _resolveStopOvershoot({
  required BookingModel booking,
  required double currentLat,
  required double currentLng,
  required DateTime now,
  DateTime? lastSampleAt,
  double? lastSampleLat,
  double? lastSampleLng,
  required OperatorOffRouteSeverity offRouteSeverity,
}) {
  const softOvershootMeters = 50.0;
  const missedOvershootMeters = 75.0;
  const stopProximityMeters = 80.0;
  const minMovementMeters = 8.0;
  const movingAwayToleranceMeters = 5.0;

  final currentStop = booking.currentPoolStop;
  final stopRoutePosition = currentStop?.routePositionMeters;
  if (currentStop == null ||
      stopRoutePosition == null ||
      booking.routePolyline.length < 2) {
    return const _StopOvershoot.none();
  }

  final operatorProjection = _projectRoutePositionOnPolyline(
    currentLat: currentLat,
    currentLng: currentLng,
    routePolyline: booking.routePolyline,
  );
  if (operatorProjection == null) {
    return const _StopOvershoot.none();
  }

  final direction = booking.routeDirection?.trim().toLowerCase();
  final overshootDistance = direction == 'reverse'
      ? stopRoutePosition - operatorProjection
      : operatorProjection - stopRoutePosition;
  if (overshootDistance <= softOvershootMeters) {
    return const _StopOvershoot.none();
  }

  final distanceToStopMeters = Geolocator.distanceBetween(
    currentLat,
    currentLng,
    currentStop.lat,
    currentStop.lng,
  );
  if (distanceToStopMeters <= stopProximityMeters ||
      offRouteSeverity == OperatorOffRouteSeverity.severe) {
    return const _StopOvershoot.none();
  }

  if (lastSampleAt == null ||
      lastSampleLat == null ||
      lastSampleLng == null ||
      !now.isAfter(lastSampleAt)) {
    return const _StopOvershoot.none();
  }

  final previousDistanceToStopMeters = Geolocator.distanceBetween(
    lastSampleLat,
    lastSampleLng,
    currentStop.lat,
    currentStop.lng,
  );
  final movementMeters = Geolocator.distanceBetween(
    lastSampleLat,
    lastSampleLng,
    currentLat,
    currentLng,
  );
  final hasReliableMovementSample = movementMeters >= minMovementMeters;
  final isMovingAwayFromStop =
      distanceToStopMeters >
      previousDistanceToStopMeters + movingAwayToleranceMeters;

  if (overshootDistance < missedOvershootMeters ||
      !hasReliableMovementSample ||
      !isMovingAwayFromStop) {
    if (!hasReliableMovementSample || !isMovingAwayFromStop) {
      return const _StopOvershoot.none();
    }
    return _StopOvershoot(
      severity: OperatorStopOvershootSeverity.soft,
      distanceMeters: overshootDistance,
    );
  }

  return _StopOvershoot(
    severity: OperatorStopOvershootSeverity.missed,
    distanceMeters: overshootDistance,
  );
}

double? _projectRoutePositionOnPolyline({
  required double currentLat,
  required double currentLng,
  required List<BookingRoutePoint> routePolyline,
}) {
  var totalDistance = 0.0;
  final cumulative = <double>[0.0];
  for (var i = 0; i < routePolyline.length - 1; i++) {
    totalDistance += Geolocator.distanceBetween(
      routePolyline[i].lat,
      routePolyline[i].lng,
      routePolyline[i + 1].lat,
      routePolyline[i + 1].lng,
    );
    cumulative.add(totalDistance);
  }

  if (totalDistance <= 0) return null;

  var nearestSegmentIndex = 0;
  var nearestProjectionT = 0.0;
  var minDistance = double.infinity;
  for (var i = 0; i < routePolyline.length - 1; i++) {
    final projection = _projectPointOntoSegmentMeters(
      pointLat: currentLat,
      pointLng: currentLng,
      startLat: routePolyline[i].lat,
      startLng: routePolyline[i].lng,
      endLat: routePolyline[i + 1].lat,
      endLng: routePolyline[i + 1].lng,
    );
    if (projection.distanceMeters < minDistance) {
      minDistance = projection.distanceMeters;
      nearestSegmentIndex = i;
      nearestProjectionT = projection.t;
    }
  }

  final segmentLength = Geolocator.distanceBetween(
    routePolyline[nearestSegmentIndex].lat,
    routePolyline[nearestSegmentIndex].lng,
    routePolyline[nearestSegmentIndex + 1].lat,
    routePolyline[nearestSegmentIndex + 1].lng,
  );
  return (cumulative[nearestSegmentIndex] + segmentLength * nearestProjectionT)
      .clamp(0.0, totalDistance);
}

_RouteProjection _projectProgressOnRoute({
  required double currentLat,
  required double currentLng,
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
  required List<BookingRoutePoint> routePolyline,
}) {
  if (routePolyline.length < 2) {
    final directTotal = Geolocator.distanceBetween(
      originLat,
      originLng,
      destinationLat,
      destinationLng,
    );
    final directRemaining = Geolocator.distanceBetween(
      currentLat,
      currentLng,
      destinationLat,
      destinationLng,
    );
    final progress = directTotal <= 0
        ? 0.0
        : (1 - (directRemaining / directTotal)).clamp(0.0, 1.0);
    final offRoute = _distanceToLineSegmentMeters(
      pointLat: currentLat,
      pointLng: currentLng,
      startLat: originLat,
      startLng: originLng,
      endLat: destinationLat,
      endLng: destinationLng,
    );

    return _RouteProjection(
      progressFraction: progress,
      remainingDistanceMeters: directRemaining,
      offRouteDistanceMeters: offRoute,
      nearestSegmentIndex: 0,
      rejoinPoint: BookingRoutePoint(
        lat: _lerp(originLat, destinationLat, progress),
        lng: _lerp(originLng, destinationLng, progress),
      ),
    );
  }

  final pathPoints = routePolyline;
  var totalDistance = 0.0;
  final cumulative = <double>[0.0];

  for (var i = 0; i < pathPoints.length - 1; i++) {
    final seg = Geolocator.distanceBetween(
      pathPoints[i].lat,
      pathPoints[i].lng,
      pathPoints[i + 1].lat,
      pathPoints[i + 1].lng,
    );
    totalDistance += seg;
    cumulative.add(totalDistance);
  }

  var nearestSegmentIndex = 0;
  var nearestProjectionT = 0.0;
  var minDistance = double.infinity;

  for (var i = 0; i < pathPoints.length - 1; i++) {
    final segment = _projectPointOntoSegmentMeters(
      pointLat: currentLat,
      pointLng: currentLng,
      startLat: pathPoints[i].lat,
      startLng: pathPoints[i].lng,
      endLat: pathPoints[i + 1].lat,
      endLng: pathPoints[i + 1].lng,
    );
    if (segment.distanceMeters < minDistance) {
      minDistance = segment.distanceMeters;
      nearestSegmentIndex = i;
      nearestProjectionT = segment.t;
    }
  }

  final segmentLength = Geolocator.distanceBetween(
    pathPoints[nearestSegmentIndex].lat,
    pathPoints[nearestSegmentIndex].lng,
    pathPoints[nearestSegmentIndex + 1].lat,
    pathPoints[nearestSegmentIndex + 1].lng,
  );

  final traveled =
      (cumulative[nearestSegmentIndex] + segmentLength * nearestProjectionT)
          .clamp(0.0, totalDistance);
  final remaining = (totalDistance - traveled + minDistance).clamp(
    0.0,
    double.infinity,
  );
  final progress = totalDistance <= 0
      ? 0.0
      : (traveled / totalDistance).clamp(0.0, 1.0);

  return _RouteProjection(
    progressFraction: progress,
    remainingDistanceMeters: remaining,
    offRouteDistanceMeters: minDistance,
    nearestSegmentIndex: nearestSegmentIndex,
    rejoinPoint: BookingRoutePoint(
      lat:
          pathPoints[nearestSegmentIndex].lat +
          ((pathPoints[nearestSegmentIndex + 1].lat -
                  pathPoints[nearestSegmentIndex].lat) *
              nearestProjectionT),
      lng:
          pathPoints[nearestSegmentIndex].lng +
          ((pathPoints[nearestSegmentIndex + 1].lng -
                  pathPoints[nearestSegmentIndex].lng) *
              nearestProjectionT),
    ),
  );
}

OperatorOffRouteSeverity _resolveOffRouteSeverity(
  double offRouteDistanceMeters,
  double offRouteToleranceMeters,
) {
  if (offRouteDistanceMeters <= offRouteToleranceMeters) {
    return OperatorOffRouteSeverity.onRoute;
  }
  if (offRouteDistanceMeters <= 150) {
    return OperatorOffRouteSeverity.mild;
  }
  if (offRouteDistanceMeters <= 300) {
    return OperatorOffRouteSeverity.moderate;
  }
  return OperatorOffRouteSeverity.severe;
}

double? _resolveEffectiveSpeedMps({
  required double? reportedSpeedMps,
  required DateTime now,
  required DateTime? lastSampleAt,
  required double currentLat,
  required double currentLng,
  required double? lastSampleLat,
  required double? lastSampleLng,
}) {
  if (reportedSpeedMps != null && reportedSpeedMps > 0.5) {
    return reportedSpeedMps;
  }

  if (lastSampleAt == null || lastSampleLat == null || lastSampleLng == null) {
    return null;
  }

  final elapsedSeconds = now.difference(lastSampleAt).inMilliseconds / 1000.0;
  if (elapsedSeconds < 0.5) {
    return null;
  }

  final movedMeters = Geolocator.distanceBetween(
    lastSampleLat,
    lastSampleLng,
    currentLat,
    currentLng,
  );
  if (movedMeters <= 0.5) {
    return null;
  }

  final speed = movedMeters / elapsedSeconds;
  if (!speed.isFinite || speed <= 0.5) {
    return null;
  }

  return speed;
}

double _routeTotalDistanceMeters({
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
  required List<BookingRoutePoint> routePolyline,
}) {
  if (routePolyline.length < 2) {
    return Geolocator.distanceBetween(
      originLat,
      originLng,
      destinationLat,
      destinationLng,
    );
  }

  var total = 0.0;
  for (var i = 0; i < routePolyline.length - 1; i++) {
    total += Geolocator.distanceBetween(
      routePolyline[i].lat,
      routePolyline[i].lng,
      routePolyline[i + 1].lat,
      routePolyline[i + 1].lng,
    );
  }
  return total;
}

double _distanceToLineSegmentMeters({
  required double pointLat,
  required double pointLng,
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
}) {
  final meanLat = ((startLat + endLat) / 2) * (pi / 180.0);
  const metersPerDegLat = 111320.0;
  final metersPerDegLng = 111320.0 * cos(meanLat);

  final sx = startLng * metersPerDegLng;
  final sy = startLat * metersPerDegLat;
  final ex = endLng * metersPerDegLng;
  final ey = endLat * metersPerDegLat;
  final px = pointLng * metersPerDegLng;
  final py = pointLat * metersPerDegLat;

  final dx = ex - sx;
  final dy = ey - sy;
  final lenSq = dx * dx + dy * dy;
  if (lenSq <= 0.0) {
    final ddx = px - sx;
    final ddy = py - sy;
    return sqrt(ddx * ddx + ddy * ddy);
  }

  var t = ((px - sx) * dx + (py - sy) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);

  final cx = sx + t * dx;
  final cy = sy + t * dy;
  final ox = px - cx;
  final oy = py - cy;
  return sqrt(ox * ox + oy * oy);
}

_SegmentProjection _projectPointOntoSegmentMeters({
  required double pointLat,
  required double pointLng,
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
}) {
  final meanLat = ((startLat + endLat) / 2) * (pi / 180.0);
  const metersPerDegLat = 111320.0;
  final metersPerDegLng = 111320.0 * cos(meanLat);

  final sx = startLng * metersPerDegLng;
  final sy = startLat * metersPerDegLat;
  final ex = endLng * metersPerDegLng;
  final ey = endLat * metersPerDegLat;
  final px = pointLng * metersPerDegLng;
  final py = pointLat * metersPerDegLat;

  final dx = ex - sx;
  final dy = ey - sy;
  final lenSq = dx * dx + dy * dy;
  if (lenSq <= 0.0) {
    final ddx = px - sx;
    final ddy = py - sy;
    return _SegmentProjection(
      t: 0.0,
      distanceMeters: sqrt(ddx * ddx + ddy * ddy),
    );
  }

  var t = ((px - sx) * dx + (py - sy) * dy) / lenSq;
  t = t.clamp(0.0, 1.0);

  final cx = sx + t * dx;
  final cy = sy + t * dy;
  final ox = px - cx;
  final oy = py - cy;
  return _SegmentProjection(t: t, distanceMeters: sqrt(ox * ox + oy * oy));
}

double? _resolveHeadingDegrees({
  required double currentLat,
  required double currentLng,
  required double? lastSampleLat,
  required double? lastSampleLng,
  required List<BookingRoutePoint> routePolyline,
  required int nearestSegmentIndex,
}) {
  if (lastSampleLat != null && lastSampleLng != null) {
    final moved = Geolocator.distanceBetween(
      lastSampleLat,
      lastSampleLng,
      currentLat,
      currentLng,
    );
    if (moved >= 1.0) {
      return _bearingDegrees(
        lastSampleLat,
        lastSampleLng,
        currentLat,
        currentLng,
      );
    }
  }

  if (routePolyline.length >= 2 &&
      nearestSegmentIndex < routePolyline.length - 1) {
    final from = routePolyline[nearestSegmentIndex];
    final to = routePolyline[nearestSegmentIndex + 1];
    return _bearingDegrees(from.lat, from.lng, to.lat, to.lng);
  }

  return null;
}

double _bearingDegrees(
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
) {
  final fromLatRad = fromLat * pi / 180;
  final fromLngRad = fromLng * pi / 180;
  final toLatRad = toLat * pi / 180;
  final toLngRad = toLng * pi / 180;
  final y = sin(toLngRad - fromLngRad) * cos(toLatRad);
  final x =
      cos(fromLatRad) * sin(toLatRad) -
      sin(fromLatRad) * cos(toLatRad) * cos(toLngRad - fromLngRad);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

class _RouteProjection {
  const _RouteProjection({
    required this.progressFraction,
    required this.remainingDistanceMeters,
    required this.offRouteDistanceMeters,
    required this.nearestSegmentIndex,
    required this.rejoinPoint,
  });

  final double progressFraction;
  final double remainingDistanceMeters;
  final double offRouteDistanceMeters;
  final int nearestSegmentIndex;
  final BookingRoutePoint rejoinPoint;
}

class _SegmentProjection {
  const _SegmentProjection({required this.t, required this.distanceMeters});

  final double t;
  final double distanceMeters;
}

class _StopOvershoot {
  const _StopOvershoot({required this.severity, required this.distanceMeters});

  const _StopOvershoot.none()
    : severity = OperatorStopOvershootSeverity.none,
      distanceMeters = 0;

  final OperatorStopOvershootSeverity severity;
  final double distanceMeters;
}

double _lerp(double from, double to, double t) => from + ((to - from) * t);
