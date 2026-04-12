/// Field name constants for the `bookings` Firestore collection.
abstract final class BookingFields {
  static const String bookingId = 'bookingId';
  static const String userId = 'userId';
  static const String userName = 'userName';
  static const String userPhone = 'userPhone';
  static const String origin = 'origin';
  static const String destination = 'destination';
  static const String originJettyId = 'originJettyId';
  static const String destinationJettyId = 'destinationJettyId';
  @Deprecated('No longer used for booking writes.')
  static const String routeKey = 'routeKey';
  static const String originCoords = 'originCoords';
  static const String destinationCoords = 'destinationCoords';
  static const String routePolylineId = 'routePolylineId';
  static const String routePolyline = 'routePolyline';
  static const String adultCount = 'adultCount';
  static const String childCount = 'childCount';
  static const String passengerCount = 'passengerCount';
  static const String adultFare = 'adultFare';
  static const String childFare = 'childFare';
  static const String adultSubtotal = 'adultSubtotal';
  static const String childSubtotal = 'childSubtotal';
  static const String fare = 'fare';
  static const String totalFare = 'totalFare';
  static const String fareSnapshotId = 'fareSnapshotId';
  static const String paymentMethod = 'paymentMethod';
  static const String paymentStatus = 'paymentStatus';
  static const String orderNumber = 'orderNumber';
  static const String transactionId = 'transactionId';
  static const String status = 'status';
  static const String operatorUid = 'operatorUid';
  static const String operatorId = 'operatorId';
  static const String operatorLat = 'operatorLat';
  static const String operatorLng = 'operatorLng';
  static const String rejectedBy = 'rejectedBy';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String cancelledAt = 'cancelledAt';
}

/// Field name constants for booking subcollections.
abstract final class BookingSubcollections {
  static const String statusHistory = 'statusHistory';
}

/// Field name constants for `bookings/{id}/statusHistory` documents.
abstract final class BookingStatusHistoryFields {
  static const String from = 'from';
  static const String to = 'to';
  static const String changedBy = 'changedBy';
  static const String source = 'source';
  static const String timestamp = 'timestamp';
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
  static const String originJettyId = 'originJettyId';
  static const String destinationJettyId = 'destinationJettyId';
  static const String adultFare = 'adultFare';
  static const String childFare = 'childFare';
}

/// Field name constants for the `tracking` Firestore collection.
abstract final class TrackingFields {
  static const String bookingId = 'bookingId';
  static const String operatorUid = 'operatorUid';
  static const String operatorLat = 'operatorLat';
  static const String operatorLng = 'operatorLng';
  static const String updatedAt = 'updatedAt';
}
