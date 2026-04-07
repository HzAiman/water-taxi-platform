import 'package:water_taxi_shared/src/constants/booking_status.dart';

/// Immutable data class representing a `bookings/{id}` Firestore document.
///
/// Firestore-specific types are mapped to plain Dart types by the repository
/// layer in each app before constructing this model:
/// - `GeoPoint`  → separate `lat` / `lng` doubles
/// - `Timestamp` → `DateTime?`
class BookingModel {
  const BookingModel({
    required this.bookingId,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.origin,
    required this.destination,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    this.routePolyline = const <BookingRoutePoint>[],
    required this.adultCount,
    required this.childCount,
    required this.passengerCount,
    required this.adultFare,
    required this.childFare,
    required this.adultSubtotal,
    required this.childSubtotal,
    required this.fare,
    required this.totalFare,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    String? operatorUid,
    @Deprecated('Use operatorUid instead.') String? operatorId,
    this.operatorLat,
    this.operatorLng,
    required this.rejectedBy,
    this.orderNumber,
    this.transactionId,
    this.createdAt,
    this.updatedAt,
    this.cancelledAt,
  }) : operatorUid = operatorUid ?? operatorId;

  final String bookingId;
  final String userId;
  final String userName;
  final String userPhone;
  final String origin;
  final String destination;
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final List<BookingRoutePoint> routePolyline;
  final int adultCount;
  final int childCount;
  final int passengerCount;
  final double adultFare;
  final double childFare;
  final double adultSubtotal;
  final double childSubtotal;
  final double fare;
  final double totalFare;
  final String paymentMethod;
  final String paymentStatus;
  final BookingStatus status;
  final String? operatorUid;
  String? get operatorId => operatorUid;
  final double? operatorLat;
  final double? operatorLng;
  final List<String> rejectedBy;
  final String? orderNumber;
  final String? transactionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? cancelledAt;

  /// Creates a [BookingModel] from a raw Firestore document map.
  ///
  /// The caller (repository) is responsible for converting [GeoPoint] and
  /// [Timestamp] values to plain Dart types before calling this factory.
  factory BookingModel.fromMap(
    Map<String, dynamic> data, {
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? cancelledAt,
  }) {
    return BookingModel(
      bookingId: _str(data['bookingId']),
      userId: _str(data['userId']),
      userName: _str(data['userName']),
      userPhone: _str(data['userPhone']),
      origin: _str(data['origin']),
      destination: _str(data['destination']),
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      routePolyline: _routePolyline(data),
      adultCount: _int(data['adultCount']),
      childCount: _int(data['childCount']),
      passengerCount: _int(data['passengerCount']),
      adultFare: _double(data['adultFare']),
      childFare: _double(data['childFare']),
      adultSubtotal: _double(data['adultSubtotal']),
      childSubtotal: _double(data['childSubtotal']),
      fare: _double(data['fare']),
      totalFare: _double(data['totalFare']),
      paymentMethod: _str(data['paymentMethod']),
      paymentStatus: _str(data['paymentStatus']),
      status: BookingStatus.fromString(_str(data['status'])),
      operatorUid: (data['operatorUid'] ?? data['operatorId'])?.toString(),
      operatorLat: _nullableDouble(data['operatorLat']),
      operatorLng: _nullableDouble(data['operatorLng']),
      rejectedBy: _strList(data['rejectedBy']),
      orderNumber: data['orderNumber']?.toString(),
      transactionId: data['transactionId']?.toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      cancelledAt: cancelledAt,
    );
  }

  BookingModel copyWith({
    String? bookingId,
    String? userId,
    String? userName,
    String? userPhone,
    String? origin,
    String? destination,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
    List<BookingRoutePoint>? routePolyline,
    int? adultCount,
    int? childCount,
    int? passengerCount,
    double? adultFare,
    double? childFare,
    double? adultSubtotal,
    double? childSubtotal,
    double? fare,
    double? totalFare,
    String? paymentMethod,
    String? paymentStatus,
    BookingStatus? status,
    String? operatorUid,
    @Deprecated('Use operatorUid instead.') String? operatorId,
    double? operatorLat,
    double? operatorLng,
    List<String>? rejectedBy,
    String? orderNumber,
    String? transactionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? cancelledAt,
  }) {
    return BookingModel(
      bookingId: bookingId ?? this.bookingId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      originLat: originLat ?? this.originLat,
      originLng: originLng ?? this.originLng,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      routePolyline: routePolyline ?? this.routePolyline,
      adultCount: adultCount ?? this.adultCount,
      childCount: childCount ?? this.childCount,
      passengerCount: passengerCount ?? this.passengerCount,
      adultFare: adultFare ?? this.adultFare,
      childFare: childFare ?? this.childFare,
      adultSubtotal: adultSubtotal ?? this.adultSubtotal,
      childSubtotal: childSubtotal ?? this.childSubtotal,
      fare: fare ?? this.fare,
      totalFare: totalFare ?? this.totalFare,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      operatorUid: operatorUid ?? operatorId ?? this.operatorUid,
      operatorLat: operatorLat ?? this.operatorLat,
      operatorLng: operatorLng ?? this.operatorLng,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      orderNumber: orderNumber ?? this.orderNumber,
      transactionId: transactionId ?? this.transactionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
    );
  }

  // ---------- private helpers ----------

  static String _str(dynamic v) => (v ?? '').toString();

  static double _double(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static double? _nullableDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.truncate();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<String> _strList(dynamic v) {
    if (v is Iterable) return v.map((e) => e.toString()).toList();
    return const [];
  }

  static List<BookingRoutePoint> _routePolyline(Map<String, dynamic> data) {
    final raw =
        data['routePolyline'] ??
        data['routeCoordinates'] ??
        data['polylineCoordinates'] ??
        data['routePoints'];

    if (raw is! Iterable) {
      return const <BookingRoutePoint>[];
    }

    final points = <BookingRoutePoint>[];
    for (final p in raw) {
      final point = BookingRoutePoint.tryParse(p);
      if (point != null) {
        points.add(point);
      }
    }
    return points;
  }
}

class BookingRoutePoint {
  const BookingRoutePoint({required this.lat, required this.lng});

  final double lat;
  final double lng;

  static BookingRoutePoint? tryParse(dynamic raw) {
    if (raw is Map) {
      final lat = _asDouble(raw['lat'] ?? raw['latitude']);
      final lng = _asDouble(raw['lng'] ?? raw['longitude'] ?? raw['lon']);
      if (lat != null && lng != null) {
        return BookingRoutePoint(lat: lat, lng: lng);
      }
      return null;
    }

    if (raw is List && raw.length >= 2) {
      final lat = _asDouble(raw[0]);
      final lng = _asDouble(raw[1]);
      if (lat != null && lng != null) {
        return BookingRoutePoint(lat: lat, lng: lng);
      }
      return null;
    }

    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }
}
