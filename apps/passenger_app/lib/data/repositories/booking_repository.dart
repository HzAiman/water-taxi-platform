import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Parameters required to create a new booking document.
class BookingCreationParams {
  const BookingCreationParams({
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.origin,
    required this.destination,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.adultCount,
    required this.childCount,
    required this.adultFare,
    required this.childFare,
    required this.paymentMethod,
    this.orderNumber,
    this.transactionId,
  });

  final String userId;
  final String userName;
  final String userPhone;
  final String origin;
  final String destination;
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final int adultCount;
  final int childCount;
  final double adultFare;
  final double childFare;
  final String paymentMethod;
  final String? orderNumber;
  final String? transactionId;
}

/// Data-access layer for the `bookings` Firestore collection (passenger side).
class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ── Write ────────────────────────────────────────────────────────────────

  /// Creates a new booking document and returns the generated booking ID.
  Future<String> createBooking(BookingCreationParams p) async {
    final ref = _db.collection(FirestoreCollections.bookings).doc();
    final id = ref.id;
    final passengerCount = p.adultCount + p.childCount;
    final adultSubtotal = p.adultFare * p.adultCount;
    final childSubtotal = p.childFare * p.childCount;
    final total = adultSubtotal + childSubtotal;

    await ref.set({
      BookingFields.bookingId: id,
      BookingFields.userId: p.userId,
      BookingFields.userName: p.userName,
      BookingFields.userPhone: p.userPhone,
      BookingFields.origin: p.origin,
      BookingFields.destination: p.destination,
      BookingFields.routeKey: _routeKey(p.origin, p.destination),
      BookingFields.originCoords: GeoPoint(p.originLat, p.originLng),
      BookingFields.destinationCoords: GeoPoint(p.destinationLat, p.destinationLng),
      BookingFields.adultCount: p.adultCount,
      BookingFields.childCount: p.childCount,
      BookingFields.passengerCount: passengerCount,
      BookingFields.adultFare: p.adultFare,
      BookingFields.childFare: p.childFare,
      BookingFields.adultSubtotal: adultSubtotal,
      BookingFields.childSubtotal: childSubtotal,
      BookingFields.fare: total,
      BookingFields.totalFare: total,
      BookingFields.paymentMethod: p.paymentMethod,
      // Payment is authorized/held first and captured after trip completion.
      BookingFields.paymentStatus: 'authorized',
      if (p.orderNumber != null) BookingFields.orderNumber: p.orderNumber,
      if (p.transactionId != null) BookingFields.transactionId: p.transactionId,
      BookingFields.status: BookingStatus.pending.firestoreValue,
      BookingFields.driverId: null,
      BookingFields.createdAt: FieldValue.serverTimestamp(),
      BookingFields.updatedAt: FieldValue.serverTimestamp(),
    });

    return id;
  }

  /// Cancels a booking owned by the current passenger.
  Future<void> cancelBooking(String bookingId) async {
    await _db
        .collection(FirestoreCollections.bookings)
        .doc(bookingId)
        .update({
      BookingFields.status: BookingStatus.cancelled.firestoreValue,
      BookingFields.updatedAt: FieldValue.serverTimestamp(),
      BookingFields.cancelledAt: FieldValue.serverTimestamp(),
    });
  }

  // ── Read / Stream ────────────────────────────────────────────────────────

  /// Streams a single booking document in real-time. Emits `null` if the
  /// document does not exist.
  Stream<BookingModel?> streamBooking(String bookingId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .doc(bookingId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return _fromDoc(snap.id, snap.data()!);
    });
  }

  /// Streams the user's currently active booking (pending / accepted /
  /// on_the_way), or `null` if there is none.
  Stream<BookingModel?> streamUserActiveBooking(String userId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.userId, isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final activeDocs = snap.docs.where((d) {
        final status = BookingStatus.fromString(
          (d.data()[BookingFields.status] ?? '').toString(),
        );
        return status.isActive;
      }).toList();

      if (activeDocs.isEmpty) return null;
      return _fromDoc(activeDocs.first.id, activeDocs.first.data());
    });
  }

  /// Streams the complete booking history for a user, sorted newest first.
  Stream<List<BookingModel>> streamUserBookingHistory(String userId) {
    return _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.userId, isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final bookings = snap.docs
          .map((d) => _fromDoc(d.id, d.data()))
          .toList()
        ..sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      return bookings;
    });
  }

  /// Returns `true` if the user has at least one active booking.
  Future<bool> hasActiveBooking(String userId) async {
    final snap = await _db
        .collection(FirestoreCollections.bookings)
        .where(BookingFields.userId, isEqualTo: userId)
        .get();

    return snap.docs.any((d) {
      final status = BookingStatus.fromString(
        (d.data()[BookingFields.status] ?? '').toString(),
      );
      return status.isActive;
    });
  }

  /// Returns `true` when at least one operator is currently online.
  Future<bool> hasOnlineOperators() async {
    final snap = await _db
        .collection(FirestoreCollections.operatorPresence)
        .where(OperatorPresenceFields.isOnline, isEqualTo: true)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _routeKey(String origin, String destination) {
    return '${origin.trim().toLowerCase()}__${destination.trim().toLowerCase()}';
  }

  static BookingModel _fromDoc(String id, Map<String, dynamic> data) {
    final origin = data[BookingFields.originCoords] as GeoPoint?;
    final dest = data[BookingFields.destinationCoords] as GeoPoint?;
    final createdAt = (data[BookingFields.createdAt] as Timestamp?)?.toDate();
    final updatedAt = (data[BookingFields.updatedAt] as Timestamp?)?.toDate();
    final cancelledAt =
        (data[BookingFields.cancelledAt] as Timestamp?)?.toDate();

    // Ensure bookingId is present (fallback to document ID)
    if (data[BookingFields.bookingId] == null) {
      data = {...data, BookingFields.bookingId: id};
    }

    return BookingModel.fromMap(
      data,
      originLat: origin?.latitude ?? 0.0,
      originLng: origin?.longitude ?? 0.0,
      destinationLat: dest?.latitude ?? 0.0,
      destinationLng: dest?.longitude ?? 0.0,
      createdAt: createdAt,
      updatedAt: updatedAt,
      cancelledAt: cancelledAt,
    );
  }
}
