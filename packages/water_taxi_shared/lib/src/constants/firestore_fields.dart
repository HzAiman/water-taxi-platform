/// Field name constants for the `bookings` Firestore collection.
abstract final class BookingFields {
  static const String bookingId = 'bookingId';
  static const String userId = 'userId';
  static const String userName = 'userName';
  static const String userPhone = 'userPhone';
  static const String origin = 'origin';
  static const String destination = 'destination';
  @Deprecated('No longer used for booking writes.')
  static const String routeKey = 'routeKey';
  static const String originCoords = 'originCoords';
  static const String destinationCoords = 'destinationCoords';
  static const String adultCount = 'adultCount';
  static const String childCount = 'childCount';
  static const String passengerCount = 'passengerCount';
  static const String adultFare = 'adultFare';
  static const String childFare = 'childFare';
  static const String adultSubtotal = 'adultSubtotal';
  static const String childSubtotal = 'childSubtotal';
  static const String fare = 'fare';
  static const String totalFare = 'totalFare';
  static const String paymentMethod = 'paymentMethod';
  static const String paymentStatus = 'paymentStatus';
  static const String orderNumber = 'orderNumber';
  static const String transactionId = 'transactionId';
  static const String status = 'status';
  static const String operatorId = 'operatorId';
  static const String rejectedBy = 'rejectedBy';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String cancelledAt = 'cancelledAt';
}

/// Field name constants for the `users` Firestore collection.
abstract final class UserFields {
  static const String uid = 'uid';
  static const String name = 'name';
  static const String email = 'email';
  static const String phoneNumber = 'phoneNumber';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
}

/// Field name constants for the `operators` Firestore collection.
abstract final class OperatorFields {
  static const String operatorId = 'operatorId';
  static const String operatorIdKey = 'operatorIdKey';
  static const String name = 'name';
  static const String email = 'email';
  static const String isOnline = 'isOnline';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
}

/// Field name constants for the `operator_presence` Firestore collection.
abstract final class OperatorPresenceFields {
  static const String isOnline = 'isOnline';
  static const String updatedAt = 'updatedAt';
}

/// Field name constants for device token collections.
abstract final class DeviceTokenFields {
  static const String token = 'token';
  static const String platform = 'platform';
  static const String appRole = 'appRole';
  static const String updatedAt = 'updatedAt';
}

/// Field name constants for the `jetties` Firestore collection.
abstract final class JettyFields {
  static const String jettyId = 'jettyId';
  static const String name = 'name';
  static const String lat = 'lat';
  static const String lng = 'lng';
}

/// Field name constants for the `fares` Firestore collection.
abstract final class FareFields {
  static const String origin = 'origin';
  static const String destination = 'destination';
  static const String adultFare = 'adultFare';
  static const String childFare = 'childFare';
}
