import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

import 'package:operator_app/features/home/presentation/map/operator_home_route_mapper.dart';

enum OperatorMapNavigationMode { overview, tracking, userControlled }

@immutable
class MapCameraState {
  const MapCameraState({
    required this.navigationMode,
    required this.isFollowing,
    required this.showRecenterButton,
    required this.isMapReady,
    required this.isProgrammaticCameraMove,
  });

  const MapCameraState.initial()
      : this(
          navigationMode: OperatorMapNavigationMode.overview,
          isFollowing: false,
          showRecenterButton: false,
          isMapReady: false,
          isProgrammaticCameraMove: false,
        );

  final OperatorMapNavigationMode navigationMode;
  final bool isFollowing;
  final bool showRecenterButton;
  final bool isMapReady;
  final bool isProgrammaticCameraMove;
}

class OperatorMapControllerService {
  OperatorMapControllerService({this.enableDebugLogging = kDebugMode});

  final bool enableDebugLogging;
  final ValueNotifier<MapCameraState> state =
      ValueNotifier<MapCameraState>(const MapCameraState.initial());

  GoogleMapController? _mapController;
  bool _isMapReady = false;
  bool _isCameraAnimating = false;
  bool _isProgrammaticCameraMove = false;
  Future<void> _cameraAnimationTail = Future<void>.value();
  OperatorMapNavigationMode _navigationMode = OperatorMapNavigationMode.overview;
  bool _shouldFitRouteBeforeFollow = false;
  String? _lastRouteFitPhaseSignature;
  DateTime? _lastFollowAt;
  LatLng? _lastFollowOperatorPoint;
  double? _lastBearing;
  LatLng? _lastCameraTarget;
  double? _lastZoom;
  double? _lastTilt;
  double _cameraBoundsPadding = 180;

  bool get isMapReady => _isMapReady;
  bool get isCameraAnimating => _isCameraAnimating;
  bool get isProgrammaticCameraMove => _isProgrammaticCameraMove;
  OperatorMapNavigationMode get navigationMode => _navigationMode;
  MapCameraState get currentState => state.value;

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

  void resetForNoActiveBooking() {
    _lastFollowOperatorPoint = null;
    _lastFollowAt = null;
    _lastBearing = null;
    _lastCameraTarget = null;
    _lastZoom = null;
    _lastTilt = null;
    _lastRouteFitPhaseSignature = null;
    _shouldFitRouteBeforeFollow = false;
    _emitState();
  }

  OperatorMapNavigationMode resolveNavigationMode({
    required BookingModel? activeBooking,
    required LatLng? operatorPoint,
  }) {
    if (activeBooking == null ||
        !OperatorHomeRouteMapper.isActiveNavigationBooking(activeBooking) ||
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

    final phaseSignature = OperatorHomeRouteMapper.routePhaseSignature(
      activeBooking,
      passengerPickedUp: passengerPickedUp,
    );
    if (_lastRouteFitPhaseSignature == phaseSignature) {
      return;
    }

    _lastRouteFitPhaseSignature = phaseSignature;
    _shouldFitRouteBeforeFollow = true;
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

    _navigationMode = resolveNavigationMode(
      activeBooking: activeBooking,
      operatorPoint: operatorPoint,
    );

    if (activeBooking == null) {
      resetForNoActiveBooking();
      return _navigationMode;
    }

    if (_shouldFitRouteBeforeFollow &&
        _navigationMode != OperatorMapNavigationMode.userControlled) {
      await runOverviewCamera(
        activeBooking,
        routePoints: routePoints,
        operatorPoint: operatorPoint,
        destinationPoint: destinationPoint,
      );
      _shouldFitRouteBeforeFollow = false;
      if (_navigationMode == OperatorMapNavigationMode.tracking &&
          operatorPoint != null) {
        await followOperatorWithPolicy(operatorPoint, forceFollow: true);
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
        _emitState();
        return _navigationMode;
      case OperatorMapNavigationMode.tracking:
        if (operatorPoint != null) {
          await followOperatorWithPolicy(
            operatorPoint,
            forceFollow: forceFollow,
          );
        }
        _emitState();
        return _navigationMode;
    }
  }

  void handleCameraMoveStarted({
    required bool shouldYieldToUser,
  }) {
    if (shouldYieldToUser &&
        _navigationMode == OperatorMapNavigationMode.tracking) {
      _navigationMode = OperatorMapNavigationMode.userControlled;
      _log('camera_yield_to_user');
      _emitState();
    }
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
        OperatorHomeRouteMapper.boundsFromPoints(fitPoints),
        padding,
      ),
      allowIfBusy: true,
    );
  }

  Future<void> followOperatorWithPolicy(
    LatLng operatorPoint, {
    required bool forceFollow,
  }) async {
    final lastPoint = _lastFollowOperatorPoint;
    final lastAt = _lastFollowAt;
    final now = DateTime.now();
    final elapsed = lastAt == null ? null : now.difference(lastAt);
    final movementDistance = lastPoint == null
        ? double.infinity
        : _distanceMeters(lastPoint, operatorPoint);
    final bearing = lastPoint == null
        ? 0.0
        : _bearingDegrees(lastPoint, operatorPoint);
    final bearingDelta = _lastBearing == null
        ? double.infinity
        : _bearingDeltaDegrees(_lastBearing!, bearing);
    final shouldFollow =
        forceFollow ||
        lastPoint == null ||
        (elapsed != null &&
            elapsed >= const Duration(milliseconds: 2000) &&
            (movementDistance >= 28 || bearingDelta >= 6));

    if (!shouldFollow) {
      return;
    }

    try {
      final speedMps = lastPoint == null || elapsed == null
          ? 0.0
          : _distanceMeters(lastPoint, operatorPoint) /
                math.max(elapsed.inMilliseconds / 1000, 0.001);
      final aheadMeters = (18 + (speedMps * 5)).clamp(18.0, 55.0);
      final targetZoom = (17.8 - (speedMps * 0.14)).clamp(16.1, 17.8);
      final targetTilt = (46.0 + (speedMps * 1.8)).clamp(40.0, 60.0);
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
      final cameraTarget = _lastCameraTarget == null
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

  Future<void> animateCameraSafely(
    CameraUpdate update, {
    bool allowIfBusy = false,
  }) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    _cameraAnimationTail = _cameraAnimationTail.then((_) async {
      if (_isCameraAnimating && !allowIfBusy) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
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
    });

    await _cameraAnimationTail;
  }

  double _resolveBoundsPadding(List<LatLng> points) {
    if (points.length < 2) {
      return _cameraBoundsPadding;
    }

    final bounds = OperatorHomeRouteMapper.boundsFromPoints(points);
    final latSpan = (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final lngSpan = (bounds.northeast.longitude - bounds.southwest.longitude).abs();
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

  double _distanceMeters(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
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
    return (0.18 + (speedMps * 0.003)).clamp(0.18, 0.3);
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
    );
  }
}
