import 'package:geolocator/geolocator.dart';

enum OperatorLocationAccess { granted, denied, deniedForever, serviceDisabled }

class OperatorLocationCoordinator {
  const OperatorLocationCoordinator();

  Future<OperatorLocationAccess> ensureLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return OperatorLocationAccess.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return OperatorLocationAccess.deniedForever;
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return OperatorLocationAccess.granted;
    }

    return OperatorLocationAccess.denied;
  }

  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition();
  }
}
