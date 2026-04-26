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

    if (activeBooking.status == BookingStatus.onTheWay) {
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

    // Final fallback: build a minimal straight line only for the current phase.
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
        color: isPreview ? const Color(0xFF94A3B8) : const Color(0xFF0066CC),
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
}
