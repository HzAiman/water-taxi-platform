import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:operator_app/features/home/presentation/map/operator_map_layers.dart';

enum OperatorMapNavigationMode { overview, tracking, userControlled }

@immutable
class MapCameraState {
  const MapCameraState({
    required this.navigationMode,
    required this.isFollowing,
    required this.showRecenterButton,
    required this.isMapReady,
    required this.isProgrammaticCameraMove,
    required this.isNavigationTilt3d,
  });

  const MapCameraState.initial()
    : this(
        navigationMode: OperatorMapNavigationMode.overview,
        isFollowing: false,
        showRecenterButton: false,
        isMapReady: false,
        isProgrammaticCameraMove: false,
        isNavigationTilt3d: true,
      );

  final OperatorMapNavigationMode navigationMode;
  final bool isFollowing;
  final bool showRecenterButton;
  final bool isMapReady;
  final bool isProgrammaticCameraMove;
  final bool isNavigationTilt3d;
}

class OperatorMapControllerService {
  OperatorMapControllerService({this.enableDebugLogging = kDebugMode});

  final bool enableDebugLogging;
  final ValueNotifier<MapCameraState> state = ValueNotifier<MapCameraState>(
    const MapCameraState.initial(),
  );

  GoogleMapController? _mapController;
  bool _isMapReady = false;
  bool _isCameraAnimating = false;
  bool _isProgrammaticCameraMove = false;
  OperatorMapNavigationMode _navigationMode =
      OperatorMapNavigationMode.overview;
  bool _shouldFitRouteBeforeFollow = false;
  bool _forceRouteFitBeforeFollow = false;
  String? _lastRouteFitPhaseSignature;
  String? _lastRouteFitPhaseOnlySignature;
  DateTime? _lastFollowAt;
  LatLng? _lastFollowOperatorPoint;
  double? _lastBearing;
  LatLng? _lastCameraTarget;
  double? _lastZoom;
  double? _lastTilt;
  CameraPosition? _visibleCameraPosition;
  double _cameraBoundsPadding = 180;
  bool _use3dNavigationTilt = true;
  static const double _trackingTilt = 45.0;
  static const double _overviewTilt = 0.0;

  bool get isMapReady => _isMapReady;
  bool get isCameraAnimating => _isCameraAnimating;
  bool get isProgrammaticCameraMove => _isProgrammaticCameraMove;
  OperatorMapNavigationMode get navigationMode => _navigationMode;
  MapCameraState get currentState => state.value;
  @visibleForTesting
  bool get debugHasPendingRouteFit => _shouldFitRouteBeforeFollow;
  @visibleForTesting
  bool get debugHasForcedRouteFit => _forceRouteFitBeforeFollow;
  @visibleForTesting
  bool get debugUses3dNavigationTilt => _use3dNavigationTilt;

  void attachMapController(GoogleMapController controller) {
    _mapController = controller;
    _isMapReady = true;
    _log('map_attached');
    _emitState();
  }

  void updateCameraBoundsPadding(double padding) {
    _cameraBoundsPadding = padding;
  }

  void clearTransitionState() {
    _shouldFitRouteBeforeFollow = false;
    _emitState();
  }

  Future<void> resetForNoActiveBooking() async {
    if (_isMapReady) {
      await _resetCameraTiltToOverview();
    }
    _lastFollowOperatorPoint = null;
    _lastFollowAt = null;
    _lastBearing = null;
    _lastCameraTarget = null;
    _lastZoom = null;
    _lastTilt = null;
    _visibleCameraPosition = null;
    _lastRouteFitPhaseSignature = null;
    _lastRouteFitPhaseOnlySignature = null;
    _shouldFitRouteBeforeFollow = false;
    _forceRouteFitBeforeFollow = false;
    _use3dNavigationTilt = true;
    _emitState();
  }

  Future<void> toggleNavigationTilt() async {
    _use3dNavigationTilt = !_use3dNavigationTilt;
    final targetTilt = _desiredTrackingTilt;
    final visibleCamera = _visibleCameraPosition;

    if (_isMapReady && visibleCamera != null) {
      await animateCameraSafely(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: visibleCamera.target,
            zoom: visibleCamera.zoom,
            bearing: visibleCamera.bearing,
            tilt: targetTilt,
          ),
        ),
        allowIfBusy: true,
      );
    } else if (_isMapReady && _lastCameraTarget != null && _lastZoom != null) {
      await animateCameraSafely(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _lastCameraTarget!,
            zoom: _lastZoom!,
            bearing: _lastBearing ?? 0.0,
            tilt: targetTilt,
          ),
        ),
        allowIfBusy: true,
      );
    }

    _lastTilt = targetTilt;
    _emitState();
  }

  OperatorMapNavigationMode resolveNavigationMode({
    required BookingModel? activeBooking,
    required LatLng? operatorPoint,
  }) {
    if (activeBooking == null ||
        !OperatorMapLayers.isActiveNavigationBooking(activeBooking) ||
        operatorPoint == null) {
      return OperatorMapNavigationMode.overview;
    }

    if (_navigationMode == OperatorMapNavigationMode.userControlled) {
      return OperatorMapNavigationMode.userControlled;
    }

    _emitState();
    return OperatorMapNavigationMode.tracking;
  }

  void prepareRouteFitBeforeFollow(
    BookingModel? activeBooking, {
    required List<LatLng> routePoints,
    required bool passengerPickedUp,
  }) {
    if (activeBooking == null || routePoints.length < 2) {
      return;
    }

    final phaseSignature = OperatorMapLayers.routePhaseSignature(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
    );
    final isPhaseTransition =
        _lastRouteFitPhaseOnlySignature != null &&
        _lastRouteFitPhaseOnlySignature != phaseSignature;
    final routeFitSignature = [
      phaseSignature,
      OperatorMapLayers.routeGeometrySignature(routePoints),
    ].join('|');
    if (_lastRouteFitPhaseSignature == routeFitSignature) {
      return;
    }

    _lastRouteFitPhaseOnlySignature = phaseSignature;
    _lastRouteFitPhaseSignature = routeFitSignature;
    _shouldFitRouteBeforeFollow = true;
    _forceRouteFitBeforeFollow = isPhaseTransition;
    if (isPhaseTransition) {
      _navigationMode = OperatorMapNavigationMode.overview;
    }
  }

  Future<OperatorMapNavigationMode> syncNavigationCamera(
    BookingModel? activeBooking, {
    required List<LatLng> routePoints,
    required LatLng? operatorPoint,
    required LatLng? destinationPoint,
    required bool forceFollow,
  }) async {
    if (!_isMapReady) {
      return _navigationMode;
    }

    if (forceFollow &&
        activeBooking != null &&
        OperatorMapLayers.isActiveNavigationBooking(activeBooking) &&
        operatorPoint != null) {
      _navigationMode = OperatorMapNavigationMode.tracking;
    }

    _navigationMode = resolveNavigationMode(
      activeBooking: activeBooking,
      operatorPoint: operatorPoint,
    );

    if (activeBooking == null) {
      await resetForNoActiveBooking();
      return _navigationMode;
    }

    if (_shouldFitRouteBeforeFollow &&
        (_navigationMode != OperatorMapNavigationMode.userControlled ||
            _forceRouteFitBeforeFollow)) {
      await runOverviewCamera(
        activeBooking,
        routePoints: routePoints,
        operatorPoint: operatorPoint,
        destinationPoint: destinationPoint,
      );
      _shouldFitRouteBeforeFollow = false;
      _forceRouteFitBeforeFollow = false;
      if (_navigationMode == OperatorMapNavigationMode.tracking &&
          operatorPoint != null) {
        await followOperatorWithPolicy(
          operatorPoint,
          forceFollow: true,
          routePoints: routePoints,
        );
      }
      _emitState();
      return _navigationMode;
    }

    switch (_navigationMode) {
      case OperatorMapNavigationMode.userControlled:
        return _navigationMode;
      case OperatorMapNavigationMode.overview:
        await runOverviewCamera(
          activeBooking,
          routePoints: routePoints,
          operatorPoint: operatorPoint,
          destinationPoint: destinationPoint,
        );
        await _ensureTilt(_overviewTilt);
        _emitState();
        return _navigationMode;
      case OperatorMapNavigationMode.tracking:
        if (operatorPoint != null) {
          await _ensureTrackingTilt(operatorPoint);
          await followOperatorWithPolicy(
            operatorPoint,
            forceFollow: forceFollow,
            routePoints: routePoints,
          );
        }
        _emitState();
        return _navigationMode;
    }
  }

  void handleCameraMoveStarted({required bool shouldYieldToUser}) {
    if (shouldYieldToUser &&
        _navigationMode == OperatorMapNavigationMode.tracking) {
      _navigationMode = OperatorMapNavigationMode.userControlled;
      _log('camera_yield_to_user');
      _emitState();
    }
  }

  void handleCameraMove(CameraPosition position) {
    _visibleCameraPosition = position;
  }

  void handleCameraIdle() {
    _isProgrammaticCameraMove = false;
    _emitState();
  }

  Future<void> runOverviewCamera(
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
        await animateCameraSafely(
          CameraUpdate.newLatLngZoom(operatorPoint, 16),
        );
      }
      return;
    }

    final padding = _resolveBoundsPadding(fitPoints);
    await animateCameraSafely(
      CameraUpdate.newLatLngBounds(
        OperatorMapLayers.boundsFromPoints(fitPoints),
        padding,
      ),
      allowIfBusy: true,
    );
  }

  Future<void> followOperatorWithPolicy(
    LatLng operatorPoint, {
    required bool forceFollow,
    List<LatLng> routePoints = const <LatLng>[],
  }) async {
    final lastPoint = _lastFollowOperatorPoint;
    final lastAt = _lastFollowAt;
    final now = DateTime.now();
    final elapsed = lastAt == null ? null : now.difference(lastAt);
    final movementDistance = lastPoint == null
        ? double.infinity
        : _distanceMeters(lastPoint, operatorPoint);
    final movementBearing = lastPoint == null
        ? null
        : _bearingDegrees(lastPoint, operatorPoint);
    final routeBearing = _routeBearingAhead(operatorPoint, routePoints);
    final bearing =
        routeBearing ?? movementBearing ?? _lastBearing ?? _overviewTilt;
    final bearingDelta = _lastBearing == null
        ? double.infinity
        : _bearingDeltaDegrees(_lastBearing!, bearing);
    final shouldFollow =
        forceFollow ||
        lastPoint == null ||
        (elapsed != null &&
            elapsed >= const Duration(milliseconds: 700) &&
            (movementDistance >= 4 || bearingDelta >= 2));

    if (!shouldFollow) {
      return;
    }

    try {
      final speedMps = lastPoint == null || elapsed == null
          ? 0.0
          : _distanceMeters(lastPoint, operatorPoint) /
                math.max(elapsed.inMilliseconds / 1000, 0.001);
      final aheadMeters = (85 + (speedMps * 6)).clamp(85.0, 170.0);
      final targetZoom = (18.45 - (speedMps * 0.08)).clamp(17.4, 18.45);
      final targetTilt = _desiredTrackingTilt;
      final smoothing = _cameraSmoothingFactor(speedMps);
      final rawTarget = _offsetPoint(operatorPoint, bearing, aheadMeters);
      final predictedTarget = lastPoint == null
          ? rawTarget
          : _offsetPoint(
              operatorPoint,
              bearing,
              (speedMps * 0.6).clamp(0.0, 18.0),
            );
      final easedTarget = _lastCameraTarget == null
          ? rawTarget
          : _lerpLatLng(rawTarget, predictedTarget, smoothing * 0.35);
      final cameraTarget = _lastCameraTarget == null || forceFollow
          ? easedTarget
          : _lerpLatLng(_lastCameraTarget!, easedTarget, smoothing);
      final cameraBearing = _lastBearing == null
          ? bearing
          : _lerpAngle(_lastBearing!, bearing, smoothing);
      final cameraZoom = lerpDouble(
        _lastZoom ?? targetZoom,
        targetZoom,
        smoothing,
      )!;
      final cameraTilt = lerpDouble(
        _lastTilt ?? targetTilt,
        targetTilt,
        smoothing,
      )!;

      await animateCameraSafely(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: cameraTarget,
            zoom: cameraZoom,
            tilt: cameraTilt,
            bearing: cameraBearing,
          ),
        ),
      );
      _lastFollowOperatorPoint = operatorPoint;
      _lastFollowAt = now;
      _lastBearing = cameraBearing;
      _lastCameraTarget = cameraTarget;
      _lastZoom = cameraZoom;
      _lastTilt = cameraTilt;
      _emitState();
    } catch (e) {
      _log('camera_follow_failed', data: {'error': e.toString()});
    }
  }

  Future<void> _ensureTrackingTilt(LatLng operatorPoint) async {
    final desiredTilt = _desiredTrackingTilt;
    if ((_lastTilt ?? _overviewTilt) == desiredTilt) {
      return;
    }

    final target = _lastCameraTarget ?? operatorPoint;
    final zoom = _lastZoom ?? 16.8;
    final bearing = _lastBearing ?? 0.0;

    await animateCameraSafely(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: zoom,
          bearing: bearing,
          tilt: desiredTilt,
        ),
      ),
      allowIfBusy: true,
    );

    _lastCameraTarget = target;
    _lastZoom = zoom;
    _lastBearing = bearing;
    _lastTilt = desiredTilt;
  }

  double get _desiredTrackingTilt =>
      _use3dNavigationTilt ? _trackingTilt : _overviewTilt;

  Future<void> _ensureTilt(double tilt) async {
    if (_lastCameraTarget == null || _lastZoom == null) {
      _lastTilt = tilt;
      return;
    }

    final targetBearing = _lastBearing ?? 0.0;
    await animateCameraSafely(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _lastCameraTarget!,
          zoom: _lastZoom!,
          bearing: targetBearing,
          tilt: tilt,
        ),
      ),
      allowIfBusy: true,
    );
    _lastTilt = tilt;
  }

  Future<void> _resetCameraTiltToOverview() async {
    final target = _lastCameraTarget;
    final zoom = _lastZoom;
    if (target == null || zoom == null) {
      return;
    }

    await animateCameraSafely(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: zoom,
          bearing: 0.0,
          tilt: _overviewTilt,
        ),
      ),
      allowIfBusy: true,
    );
  }

  Future<void> animateCameraSafely(
    CameraUpdate update, {
    bool allowIfBusy = false,
  }) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    if (_isCameraAnimating) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_isCameraAnimating && !allowIfBusy) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (_isCameraAnimating) {
          return;
        }
      }
    }

    _isCameraAnimating = true;
    _isProgrammaticCameraMove = true;
    _emitState();
    try {
      await controller.animateCamera(update);
    } catch (e) {
      _log('camera_animation_failed', data: {'error': e.toString()});
    } finally {
      _isCameraAnimating = false;
      _isProgrammaticCameraMove = false;
      _emitState();
    }
  }

  double _resolveBoundsPadding(List<LatLng> points) {
    if (points.length < 2) {
      return _cameraBoundsPadding;
    }

    final bounds = OperatorMapLayers.boundsFromPoints(points);
    final latSpan = (bounds.northeast.latitude - bounds.southwest.latitude)
        .abs();
    final lngSpan = (bounds.northeast.longitude - bounds.southwest.longitude)
        .abs();
    final span = math.max(latSpan, lngSpan);
    final multiplier = span > 0.08
        ? 0.8
        : span > 0.03
        ? 0.9
        : 1.0;
    return (_cameraBoundsPadding * multiplier).clamp(96.0, 240.0);
  }

  void _log(String event, {Map<String, Object?> data = const {}}) {
    if (!enableDebugLogging) {
      return;
    }

    developer.log(
      event,
      name: 'operator_map_camera',
      error: data.isEmpty ? null : data,
    );
  }

  void dispose() {
    state.dispose();
  }

  double _distanceMeters(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  double? _routeBearingAhead(LatLng operatorPoint, List<LatLng> routePoints) {
    if (routePoints.length < 2) {
      return null;
    }

    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < routePoints.length; i++) {
      final distance = _distanceMeters(operatorPoint, routePoints[i]);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    for (var i = nearestIndex + 1; i < routePoints.length; i++) {
      if (_distanceMeters(operatorPoint, routePoints[i]) >= 8) {
        return _bearingDegrees(operatorPoint, routePoints[i]);
      }
    }

    for (var i = nearestIndex - 1; i >= 0; i--) {
      if (_distanceMeters(operatorPoint, routePoints[i]) >= 8) {
        return _bearingDegrees(routePoints[i], operatorPoint);
      }
    }

    return null;
  }

  double _bearingDegrees(LatLng from, LatLng to) {
    final fromLat = _degreesToRadians(from.latitude);
    final fromLng = _degreesToRadians(from.longitude);
    final toLat = _degreesToRadians(to.latitude);
    final toLng = _degreesToRadians(to.longitude);
    final y = math.sin(toLng - fromLng) * math.cos(toLat);
    final x =
        math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(toLng - fromLng);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  LatLng _offsetPoint(
    LatLng origin,
    double bearingDegrees,
    double distanceMeters,
  ) {
    const earthRadiusMeters = 6371000.0;
    final angularDistance = distanceMeters / earthRadiusMeters;
    final bearing = _degreesToRadians(bearingDegrees);
    final lat1 = _degreesToRadians(origin.latitude);
    final lng1 = _degreesToRadians(origin.longitude);

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
    );
    final lng2 =
        lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );

    return LatLng(
      lat2 * 180 / math.pi,
      ((lng2 * 180 / math.pi) + 540) % 360 - 180,
    );
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      lerpDouble(a.latitude, b.latitude, t)!,
      lerpDouble(a.longitude, b.longitude, t)!,
    );
  }

  double _cameraSmoothingFactor(double speedMps) {
    return (0.42 + (speedMps * 0.01)).clamp(0.42, 0.62);
  }

  double _lerpAngle(double from, double to, double t) {
    final delta = _bearingDeltaDegrees(from, to);
    return _normalizeBearing(from + (delta * t));
  }

  double _bearingDeltaDegrees(double from, double to) {
    final delta = _normalizeBearing(to) - _normalizeBearing(from);
    if (delta > 180) {
      return delta - 360;
    }
    if (delta < -180) {
      return delta + 360;
    }
    return delta;
  }

  double _normalizeBearing(double bearing) {
    final normalized = bearing % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static double _degreesToRadians(double degrees) => degrees * (math.pi / 180);

  void _emitState() {
    state.value = MapCameraState(
      navigationMode: _navigationMode,
      isFollowing: _navigationMode == OperatorMapNavigationMode.tracking,
      showRecenterButton:
          _navigationMode == OperatorMapNavigationMode.userControlled,
      isMapReady: _isMapReady,
      isProgrammaticCameraMove: _isProgrammaticCameraMove,
      isNavigationTilt3d: _use3dNavigationTilt,
    );
  }
}
