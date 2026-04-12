import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `users` Firestore collection.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns the user document, or `null` if it doesn't exist.
  Future<UserModel?> getUser(String uid) async {
    final snap = await _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .get();

    if (!snap.exists || snap.data() == null) return null;
    return _fromDoc(uid, snap.data()!);
  }

  /// Creates a user document (merges if already exists).
  Future<void> createUser(UserModel user) async {
    final payload = Map<String, dynamic>.from(user.toMap())
      ..remove(UserFields.uid);
    await _db
        .collection(FirestoreCollections.users)
        .doc(user.uid)
        .set({
      ...payload,
      UserFields.createdAt: FieldValue.serverTimestamp(),
      UserFields.updatedAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Updates mutable user profile fields.
  Future<void> updateUser(
    String uid, {
    String? name,
    String? email,
  }) async {
    final updates = <String, dynamic>{
      UserFields.updatedAt: FieldValue.serverTimestamp(),
    };
    if (name != null) updates[UserFields.name] = name;
    if (email != null) updates[UserFields.email] = email;

    await _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .set(updates, SetOptions(merge: true));
  }

  /// Deletes the user Firestore document.
  Future<void> deleteUser(String uid) async {
    await _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .delete();
  }

  static UserModel _fromDoc(String uid, Map<String, dynamic> data) {
    final createdAt = (data[UserFields.createdAt] as Timestamp?)?.toDate();
    final updatedAt = (data[UserFields.updatedAt] as Timestamp?)?.toDate();
    final parsed = UserModel.fromMap(
      data,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    if (parsed.uid.isNotEmpty) {
      return parsed;
    }
    return parsed.copyWith(uid: uid);
  }
}
