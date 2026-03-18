import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `operators` Firestore collection.
class OperatorRepository {
  OperatorRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static String normalizeOperatorIdKey(String operatorId) {
    return operatorId.trim().toLowerCase();
  }

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
    await saveProfile(
      uid: op.uid,
      name: op.name,
      email: op.email,
      operatorId: op.operatorId,
      isOnline: op.isOnline,
    );
  }

  /// Saves operator profile and atomically claims [operatorId] uniqueness.
  Future<void> saveProfile({
    required String uid,
    required String name,
    required String email,
    required String operatorId,
    bool? isOnline,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();
    final trimmedOperatorId = operatorId.trim();
    final operatorIdKey = normalizeOperatorIdKey(trimmedOperatorId);
    final canonicalOperatorId = operatorIdKey;

    if (trimmedName.isEmpty ||
        trimmedOperatorId.isEmpty ||
        trimmedEmail.isEmpty) {
      throw StateError('Name, email, and operator ID are required.');
    }

    final operatorRef = _db.collection(FirestoreCollections.operators).doc(uid);
    final presenceRef = _db
        .collection(FirestoreCollections.operatorPresence)
        .doc(uid);
    final newClaimRef = _db
        .collection(FirestoreCollections.operatorIdClaims)
        .doc(operatorIdKey);

    await _db.runTransaction((tx) async {
      final operatorSnap = await tx.get(operatorRef);
      final claimSnap = await tx.get(newClaimRef);

      final claimOwner = claimSnap.data()?['uid']?.toString();
      if (claimSnap.exists && claimOwner != uid) {
        throw StateError('Operator ID is already used by another operator.');
      }

      final operatorData = operatorSnap.data() ?? const <String, dynamic>{};
      final previousKey = (operatorData[OperatorFields.operatorIdKey] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (previousKey.isNotEmpty && previousKey != operatorIdKey) {
        final previousClaimRef = _db
            .collection(FirestoreCollections.operatorIdClaims)
            .doc(previousKey);
        final previousClaimSnap = await tx.get(previousClaimRef);
        if (previousClaimSnap.exists &&
            previousClaimSnap.data()?['uid']?.toString() == uid) {
          tx.delete(previousClaimRef);
        }
      }

      final resolvedOnline =
          isOnline ?? (operatorData[OperatorFields.isOnline] == true);

      tx.set(newClaimRef, {
        'uid': uid,
        OperatorFields.operatorId: canonicalOperatorId,
        OperatorFields.operatorIdKey: operatorIdKey,
        OperatorFields.updatedAt: FieldValue.serverTimestamp(),
        if (!claimSnap.exists)
          OperatorFields.createdAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(operatorRef, {
        OperatorFields.name: trimmedName,
        OperatorFields.email: trimmedEmail,
        OperatorFields.operatorId: canonicalOperatorId,
        OperatorFields.operatorIdKey: operatorIdKey,
        OperatorFields.isOnline: resolvedOnline,
        OperatorFields.updatedAt: FieldValue.serverTimestamp(),
        if (!operatorSnap.exists)
          OperatorFields.createdAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(presenceRef, {
        OperatorPresenceFields.isOnline: resolvedOnline,
        OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Repairs legacy operator records by ensuring claim ownership is present.
  ///
  /// Returns `true` when a migration write was applied.
  Future<bool> ensureProfileClaim({
    required String uid,
    String? fallbackEmail,
  }) async {
    final op = await getOperator(uid);
    if (op == null) return false;

    final normalized = normalizeOperatorIdKey(op.operatorId);
    final currentKey = normalized;
    final claimRef = _db
        .collection(FirestoreCollections.operatorIdClaims)
        .doc(currentKey);
    final claimSnap = await claimRef.get();
    final claimOwner = claimSnap.data()?['uid']?.toString();

    final needsRepair = !claimSnap.exists || claimOwner != uid;
    if (!needsRepair) return false;

    await saveProfile(
      uid: uid,
      name: op.name,
      email: op.email.isNotEmpty ? op.email : (fallbackEmail ?? ''),
      operatorId: op.operatorId,
      isOnline: op.isOnline,
    );

    return true;
  }

  /// Updates operator profile fields.
  Future<void> updateOperator(String uid, {String? name, String? email}) async {
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
    final batch = _db.batch();
    final operatorRef = _db.collection(FirestoreCollections.operators).doc(uid);
    final presenceRef = _db
        .collection(FirestoreCollections.operatorPresence)
        .doc(uid);

    batch.update(operatorRef, {
      OperatorFields.isOnline: isOnline,
      OperatorFields.updatedAt: FieldValue.serverTimestamp(),
    });
    batch.set(presenceRef, {
      OperatorPresenceFields.isOnline: isOnline,
      OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Mirrors the current online flag into the presence collection.
  Future<void> syncPresence(String uid, {required bool isOnline}) async {
    await _db.collection(FirestoreCollections.operatorPresence).doc(uid).set({
      OperatorPresenceFields.isOnline: isOnline,
      OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
