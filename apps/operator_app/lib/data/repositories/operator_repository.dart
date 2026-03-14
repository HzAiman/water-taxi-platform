import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `operators` Firestore collection.
class OperatorRepository {
  OperatorRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns the operator document, or `null` if it doesn't exist.
  Future<OperatorModel?> getOperator(String uid) async {
    final snap = await _db
        .collection(FirestoreCollections.operators)
        .doc(uid)
        .get();
    if (!snap.exists || snap.data() == null) return null;
    return _fromDoc(uid, snap.data()!);
  }

  /// Streams the operator document in real-time.
  Stream<OperatorModel?> streamOperator(String uid) {
    return _db
        .collection(FirestoreCollections.operators)
        .doc(uid)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return _fromDoc(uid, snap.data()!);
    });
  }

  /// Creates or merges an operator document.
  Future<void> createOperator(OperatorModel op) async {
    await _db
        .collection(FirestoreCollections.operators)
        .doc(op.uid)
        .set({
      ...op.toMap(),
      OperatorFields.createdAt: FieldValue.serverTimestamp(),
      OperatorFields.updatedAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Updates operator profile fields.
  Future<void> updateOperator(
    String uid, {
    String? name,
    String? email,
  }) async {
    final updates = <String, dynamic>{
      OperatorFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (name != null) updates[OperatorFields.name] = name;
    if (email != null) updates[OperatorFields.email] = email;

    await _db
        .collection(FirestoreCollections.operators)
        .doc(uid)
        .update(updates);
  }

  /// Sets the operator's online status.
  Future<void> setOnlineStatus(String uid, {required bool isOnline}) async {
    await _db
        .collection(FirestoreCollections.operators)
        .doc(uid)
        .update({
      OperatorFields.isOnline: isOnline,
      OperatorFields.updatedAt: FieldValue.serverTimestamp(),
    });
  }

  static OperatorModel _fromDoc(String uid, Map<String, dynamic> data) {
    final createdAt = (data[OperatorFields.createdAt] as Timestamp?)?.toDate();
    final updatedAt = (data[OperatorFields.updatedAt] as Timestamp?)?.toDate();
    return OperatorModel.fromMap(
      uid,
      data,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
