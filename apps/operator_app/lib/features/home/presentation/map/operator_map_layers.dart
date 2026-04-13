import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

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

    final routePoints = (routePointsOverride ??
            activeBooking.routePolyline
                .map((p) => LatLng(p.lat, p.lng))
                .toList(growable: false))
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

    return const <Polyline>{};
  }

  static bool _isValidLatLng(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }
}
