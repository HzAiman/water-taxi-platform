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
    this.originJettyId,
    this.destinationJettyId,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    this.routePolylineId,
    this.routePolyline = const <BookingRoutePoint>[],
    this.routeToOriginPolyline = const <BookingRoutePoint>[],
    this.routeToDestinationPolyline = const <BookingRoutePoint>[],
    required this.adultCount,
    required this.childCount,
    required this.passengerCount,
    required this.totalFare,
    this.fareSnapshotId,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    String? operatorUid,
    @Deprecated('Use operatorUid instead.') String? operatorId,
    this.assignedOperatorName = '',
    this.assignedOperatorDisplayId = '',
    this.assignedOperatorPhone = '',
    this.pooled = false,
    this.poolGroupId,
    this.routeDirection,
    this.poolSequence,
    this.poolCriteriaVersion,
    this.poolMax,
    this.poolEligibilityScore,
    this.poolEtaSnapshot,
    this.poolStopPlan = const <PoolStopPlanItem>[],
    this.currentStopIndex,
    this.currentStopId,
    this.currentPoolStopId,
    this.poolStatus,
    this.poolPickupStopId,
    this.poolDropoffStopId,
    this.poolPhase,
    this.onboard = false,
    this.operatorLat,
    this.operatorLng,
    required this.rejectedBy,
    this.orderNumber,
    this.transactionId,
    this.createdAt,
    this.updatedAt,
    this.cancelledAt,
    this.passengerPickedUpAt,
    this.pickedUpAt,
    this.droppedOffAt,
    this.completedAt,
  }) : operatorUid = operatorUid ?? operatorId;

  final String bookingId;
  final String userId;
  final String userName;
  final String userPhone;
  final String origin;
  final String destination;
  final String? originJettyId;
  final String? destinationJettyId;
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final String? routePolylineId;
  final List<BookingRoutePoint> routePolyline;
  final List<BookingRoutePoint> routeToOriginPolyline;
  final List<BookingRoutePoint> routeToDestinationPolyline;
  final int adultCount;
  final int childCount;
  final int passengerCount;
  final double totalFare;
  final String? fareSnapshotId;
  final String paymentMethod;
  final String paymentStatus;
  final BookingStatus status;
  final String? operatorUid;
  String? get operatorId => operatorUid;
  final String assignedOperatorName;
  final String assignedOperatorDisplayId;
  final String assignedOperatorPhone;
  final bool pooled;
  final String? poolGroupId;
  final String? routeDirection;
  final int? poolSequence;
  final String? poolCriteriaVersion;
  final int? poolMax;
  final double? poolEligibilityScore;
  final Map<String, dynamic>? poolEtaSnapshot;
  final List<PoolStopPlanItem> poolStopPlan;
  final int? currentStopIndex;
  final String? currentStopId;
  final String? currentPoolStopId;
  final String? poolStatus;
  final String? poolPickupStopId;
  final String? poolDropoffStopId;
  final String? poolPhase;
  final bool onboard;
  final double? operatorLat;
  final double? operatorLng;
  final List<String> rejectedBy;
  final String? orderNumber;
  final String? transactionId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? cancelledAt;
  final DateTime? passengerPickedUpAt;
  final DateTime? pickedUpAt;
  final DateTime? droppedOffAt;
  final DateTime? completedAt;

  PoolStopPlanItem? get currentPoolStop {
    if (poolStopPlan.isEmpty) return null;
    if (currentStopId != null) {
      for (final stop in poolStopPlan) {
        if (stop.stopId == currentStopId) return stop;
      }
    }
    for (final stop in poolStopPlan) {
      if (stop.status == 'active') return stop;
    }
    final index = currentStopIndex ?? 0;
    if (index >= 0 && index < poolStopPlan.length) {
      return poolStopPlan[index];
    }
    return poolStopPlan.first;
  }

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
      originJettyId: _nullableString(data['originJettyId']),
      destinationJettyId: _nullableString(data['destinationJettyId']),
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      routePolylineId: data['routePolylineId']?.toString(),
      routePolyline: _routePolyline(data),
      routeToOriginPolyline: _routePolylineForKeys(data, const [
        'routeToOriginPolyline',
        'operatorToOriginPolyline',
        'toOriginPolyline',
        'routeToOrigin',
        'pickupPolyline',
        'routeToPickupPolyline',
        'operatorToPickupPolyline',
        'pickupRoutePolyline',
        'pickupRoute',
        'pickupPath',
        'toOriginPath',
        'operatorToPickupPath',
        'operatorToOriginCoordinates',
        'pickupPathCoordinates',
      ]),
      routeToDestinationPolyline: _routePolylineForKeys(data, const [
        'routeToDestinationPolyline',
        'originToDestinationPolyline',
        'toDestinationPolyline',
        'routeToDestination',
        'dropoffPolyline',
        'dropoffRoutePolyline',
        'dropoffRoute',
        'destinationRoutePolyline',
        'toDestinationPath',
        'pickupToDestinationPath',
        'originToDestinationCoordinates',
        'dropoffPathCoordinates',
      ]),
      adultCount: _int(data['adultCount']),
      childCount: _int(data['childCount']),
      passengerCount: _int(data['passengerCount']),
      totalFare: _double(data['totalFare']),
      fareSnapshotId: data['fareSnapshotId']?.toString(),
      paymentMethod: _str(data['paymentMethod']),
      paymentStatus: _str(data['paymentStatus']),
      status: BookingStatus.fromString(_str(data['status'])),
      operatorUid: (data['operatorUid'] ?? data['operatorId'])?.toString(),
      assignedOperatorName: _str(data['assignedOperatorName']),
      assignedOperatorDisplayId: _str(data['assignedOperatorDisplayId']),
      assignedOperatorPhone: _str(data['assignedOperatorPhone']),
      pooled: _bool(data['pooled']),
      poolGroupId: _nullableString(data['poolGroupId']),
      routeDirection: _nullableString(data['routeDirection']),
      poolSequence: _nullableInt(data['poolSequence']),
      poolCriteriaVersion: _nullableString(data['poolCriteriaVersion']),
      poolMax: _nullableInt(data['poolMax']),
      poolEligibilityScore: _nullableDouble(data['poolEligibilityScore']),
      poolEtaSnapshot: _nullableMap(data['poolEtaSnapshot']),
      poolStopPlan: _poolStopPlan(data['poolStopPlan']),
      currentStopIndex: _nullableInt(data['currentStopIndex']),
      currentStopId: _nullableString(data['currentStopId']),
      currentPoolStopId: _nullableString(data['currentPoolStopId']),
      poolStatus: _nullableString(data['poolStatus']),
      poolPickupStopId: _nullableString(data['poolPickupStopId']),
      poolDropoffStopId: _nullableString(data['poolDropoffStopId']),
      poolPhase: _nullableString(data['poolPhase']),
      onboard: _bool(data['onboard']),
      operatorLat: _nullableDouble(data['operatorLat']),
      operatorLng: _nullableDouble(data['operatorLng']),
      rejectedBy: _strList(data['rejectedBy']),
      orderNumber: data['orderNumber']?.toString(),
      transactionId: data['transactionId']?.toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      cancelledAt: cancelledAt,
      passengerPickedUpAt: _nullableDateTime(data['passengerPickedUpAt']),
      pickedUpAt: _nullableDateTime(data['pickedUpAt']),
      droppedOffAt: _nullableDateTime(data['droppedOffAt']),
      completedAt: _nullableDateTime(data['completedAt']),
    );
  }

  BookingModel copyWith({
    String? bookingId,
    String? userId,
    String? userName,
    String? userPhone,
    String? origin,
    String? destination,
    String? originJettyId,
    String? destinationJettyId,
    double? originLat,
    double? originLng,
    double? destinationLat,
    double? destinationLng,
    String? routePolylineId,
    List<BookingRoutePoint>? routePolyline,
    List<BookingRoutePoint>? routeToOriginPolyline,
    List<BookingRoutePoint>? routeToDestinationPolyline,
    int? adultCount,
    int? childCount,
    int? passengerCount,
    double? totalFare,
    String? fareSnapshotId,
    String? paymentMethod,
    String? paymentStatus,
    BookingStatus? status,
    String? operatorUid,
    @Deprecated('Use operatorUid instead.') String? operatorId,
    String? assignedOperatorName,
    String? assignedOperatorDisplayId,
    String? assignedOperatorPhone,
    bool? pooled,
    String? poolGroupId,
    String? routeDirection,
    int? poolSequence,
    String? poolCriteriaVersion,
    int? poolMax,
    double? poolEligibilityScore,
    Map<String, dynamic>? poolEtaSnapshot,
    List<PoolStopPlanItem>? poolStopPlan,
    int? currentStopIndex,
    String? currentStopId,
    String? currentPoolStopId,
    String? poolStatus,
    String? poolPickupStopId,
    String? poolDropoffStopId,
    String? poolPhase,
    bool? onboard,
    double? operatorLat,
    double? operatorLng,
    List<String>? rejectedBy,
    String? orderNumber,
    String? transactionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? cancelledAt,
    DateTime? passengerPickedUpAt,
    DateTime? pickedUpAt,
    DateTime? droppedOffAt,
    DateTime? completedAt,
  }) {
    return BookingModel(
      bookingId: bookingId ?? this.bookingId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      originJettyId: originJettyId ?? this.originJettyId,
      destinationJettyId: destinationJettyId ?? this.destinationJettyId,
      originLat: originLat ?? this.originLat,
      originLng: originLng ?? this.originLng,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      routePolylineId: routePolylineId ?? this.routePolylineId,
      routePolyline: routePolyline ?? this.routePolyline,
      routeToOriginPolyline:
          routeToOriginPolyline ?? this.routeToOriginPolyline,
      routeToDestinationPolyline:
          routeToDestinationPolyline ?? this.routeToDestinationPolyline,
      adultCount: adultCount ?? this.adultCount,
      childCount: childCount ?? this.childCount,
      passengerCount: passengerCount ?? this.passengerCount,
      totalFare: totalFare ?? this.totalFare,
      fareSnapshotId: fareSnapshotId ?? this.fareSnapshotId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      operatorUid: operatorUid ?? operatorId ?? this.operatorUid,
      assignedOperatorName: assignedOperatorName ?? this.assignedOperatorName,
      assignedOperatorDisplayId:
          assignedOperatorDisplayId ?? this.assignedOperatorDisplayId,
      assignedOperatorPhone:
          assignedOperatorPhone ?? this.assignedOperatorPhone,
      pooled: pooled ?? this.pooled,
      poolGroupId: poolGroupId ?? this.poolGroupId,
      routeDirection: routeDirection ?? this.routeDirection,
      poolSequence: poolSequence ?? this.poolSequence,
      poolCriteriaVersion: poolCriteriaVersion ?? this.poolCriteriaVersion,
      poolMax: poolMax ?? this.poolMax,
      poolEligibilityScore: poolEligibilityScore ?? this.poolEligibilityScore,
      poolEtaSnapshot: poolEtaSnapshot ?? this.poolEtaSnapshot,
      poolStopPlan: poolStopPlan ?? this.poolStopPlan,
      currentStopIndex: currentStopIndex ?? this.currentStopIndex,
      currentStopId: currentStopId ?? this.currentStopId,
      currentPoolStopId: currentPoolStopId ?? this.currentPoolStopId,
      poolStatus: poolStatus ?? this.poolStatus,
      poolPickupStopId: poolPickupStopId ?? this.poolPickupStopId,
      poolDropoffStopId: poolDropoffStopId ?? this.poolDropoffStopId,
      poolPhase: poolPhase ?? this.poolPhase,
      onboard: onboard ?? this.onboard,
      operatorLat: operatorLat ?? this.operatorLat,
      operatorLng: operatorLng ?? this.operatorLng,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      orderNumber: orderNumber ?? this.orderNumber,
      transactionId: transactionId ?? this.transactionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      passengerPickedUpAt: passengerPickedUpAt ?? this.passengerPickedUpAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      droppedOffAt: droppedOffAt ?? this.droppedOffAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  // ---------- private helpers ----------

  static String _str(dynamic v) => (v ?? '').toString();

  static double _double(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static bool _bool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final text = v?.toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static double? _nullableDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _nullableInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.truncate();
    return int.tryParse(v.toString());
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.truncate();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String? _nullableString(dynamic v) {
    final normalized = v?.toString().trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  static Map<String, dynamic>? _nullableMap(dynamic v) {
    if (v is Map) {
      return Map<String, dynamic>.from(v);
    }
    return null;
  }

  static List<PoolStopPlanItem> _poolStopPlan(dynamic value) {
    if (value is! Iterable) return const <PoolStopPlanItem>[];
    return value
        .whereType<Map>()
        .map((item) => PoolStopPlanItem.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
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

  static List<BookingRoutePoint> _routePolylineForKeys(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final raw = data[key];
      if (raw is! Iterable) {
        continue;
      }
      final points = <BookingRoutePoint>[];
      for (final p in raw) {
        final point = BookingRoutePoint.tryParse(p);
        if (point != null) {
          points.add(point);
        }
      }
      if (points.isNotEmpty) {
        return points;
      }
    }
    return const <BookingRoutePoint>[];
  }

  static DateTime? _nullableDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v == null) return null;
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    }
    return DateTime.tryParse(v.toString());
  }
}

class BookingRoutePoint {
  const BookingRoutePoint({required this.lat, required this.lng});

  final double lat;
  final double lng;

  static BookingRoutePoint? tryParse(dynamic raw) {
    if (raw is Map) {
      final lat = _asDouble(raw['lat'] ?? raw['latitude'] ?? raw['_latitude']);
      final lng = _asDouble(
        raw['lng'] ?? raw['longitude'] ?? raw['lon'] ?? raw['_longitude'],
      );
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

class PoolStopPlanItem {
  const PoolStopPlanItem({
    required this.stopId,
    required this.index,
    required this.stopType,
    this.stopJettyId,
    required this.stopName,
    required this.lat,
    required this.lng,
    this.routePositionMeters,
    this.distanceFromRouteMeters,
    required this.bookingIds,
    this.status = 'pending',
    this.etaToStopMinutes,
    this.reachedAt,
    this.completedAt,
  });

  final String stopId;
  final int index;
  final String stopType;
  final String? stopJettyId;
  final String stopName;
  final double lat;
  final double lng;
  final double? routePositionMeters;
  final double? distanceFromRouteMeters;
  final List<String> bookingIds;
  final String status;
  final double? etaToStopMinutes;
  final DateTime? reachedAt;
  final DateTime? completedAt;

  bool get isPickup => stopType == 'pickup';
  bool get isDropoff => stopType == 'dropoff';

  factory PoolStopPlanItem.fromMap(Map<String, dynamic> data) {
    return PoolStopPlanItem(
      stopId: _str(data['stopId']),
      index: _int(data['stopIndex'] ?? data['index']),
      stopType: _str(data['stopType']),
      stopJettyId: _nullableString(data['jettyId'] ?? data['stopJettyId']),
      stopName: _str(data['jettyName'] ?? data['stopName']),
      lat: _double(data['lat']),
      lng: _double(data['lng']),
      routePositionMeters: _nullableDouble(data['routePositionMeters']),
      distanceFromRouteMeters: _nullableDouble(data['distanceFromRouteMeters']),
      bookingIds: _strList(data['bookingIds']),
      status: _str(data['status']).isEmpty ? 'pending' : _str(data['status']),
      etaToStopMinutes: _nullableDouble(data['etaToStop']),
      reachedAt: _nullableDateTime(data['reachedAt']),
      completedAt: _nullableDateTime(data['completedAt']),
    );
  }

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

  static String? _nullableString(dynamic v) {
    final text = v?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _strList(dynamic v) {
    if (v is Iterable) return v.map((e) => e.toString()).toList();
    return const [];
  }

  static DateTime? _nullableDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) return DateTime.tryParse(v);
    try {
      final dynamic maybeTimestamp = v;
      return maybeTimestamp.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
