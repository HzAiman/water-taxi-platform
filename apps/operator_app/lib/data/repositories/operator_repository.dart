import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:operator_app/core/services/firebase_session_service.dart';
import 'package:operator_app/core/utils/operator_id_input_formatter.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

/// Data-access layer for the `operators` Firestore collection.
class OperatorRepository {
  OperatorRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: _functionsRegion),
       _useCallableProfileSave = firestore == null || functions != null;

  static const _functionsRegion = 'asia-southeast1';

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final bool _useCallableProfileSave;

  /// Returns the operator document, or `null` if it doesn't exist.
  Future<OperatorModel?> getOperator(String uid) async {
    final operatorSnap = await _db
        .collection(FirestoreCollections.operators)
        .doc(uid)
        .get();
    if (!operatorSnap.exists || operatorSnap.data() == null) return null;

    final presenceSnap = await _db
        .collection(FirestoreCollections.operatorPresence)
        .doc(uid)
        .get();

    return _fromDocs(uid, operatorSnap.data()!, presenceSnap.data());
  }

  /// Streams the operator document in real-time.
  Stream<OperatorModel?> streamOperator(String uid) {
    final operatorRef = _db.collection(FirestoreCollections.operators).doc(uid);
    final presenceRef = _db
        .collection(FirestoreCollections.operatorPresence)
        .doc(uid);

    late final StreamController<OperatorModel?> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? operatorSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? presenceSub;

    Map<String, dynamic>? operatorData;
    Map<String, dynamic>? presenceData;
    var hasOperatorSnapshot = false;

    void emitCurrent() {
      if (!hasOperatorSnapshot) return;
      if (operatorData == null) {
        controller.add(null);
        return;
      }
      controller.add(_fromDocs(uid, operatorData!, presenceData));
    }

    controller = StreamController<OperatorModel?>.broadcast(
      onListen: () {
        operatorSub = operatorRef.snapshots().listen((snap) {
          hasOperatorSnapshot = true;
          operatorData = snap.data();
          emitCurrent();
        }, onError: controller.addError);

        presenceSub = presenceRef.snapshots().listen((snap) {
          presenceData = snap.data();
          if (hasOperatorSnapshot && operatorData != null) {
            emitCurrent();
          }
        }, onError: controller.addError);
      },
      onCancel: () async {
        await operatorSub?.cancel();
        await presenceSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Creates or merges an operator document.
  Future<void> createOperator(OperatorModel op) async {
    await saveProfile(
      uid: op.uid,
      name: op.name,
      email: op.email,
      operatorId: op.operatorId,
      phoneNumber: op.phoneNumber,
      isOnline: op.isOnline,
    );
  }

  /// Saves operator profile and atomically claims [operatorId] uniqueness.
  Future<void> saveProfile({
    required String uid,
    required String name,
    required String email,
    required String operatorId,
    required String phoneNumber,
    bool? isOnline,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();
    final trimmedOperatorId = normalizeOperatorId(operatorId);
    final trimmedPhone = phoneNumber.trim();

    if (trimmedName.isEmpty ||
        trimmedOperatorId.isEmpty ||
        trimmedEmail.isEmpty ||
        trimmedPhone.isEmpty) {
      throw StateError('Name, email, operator ID, and phone are required.');
    }

    if (_useCallableProfileSave) {
      await _saveProfileWithBackend(
        name: trimmedName,
        email: trimmedEmail,
        operatorId: trimmedOperatorId,
        phoneNumber: trimmedPhone,
      );
      return;
    }

    await _saveProfileDirect(
      uid: uid,
      name: trimmedName,
      email: trimmedEmail,
      operatorId: trimmedOperatorId,
      phoneNumber: trimmedPhone,
      isOnline: isOnline,
    );
  }

  Future<void> _saveProfileWithBackend({
    required String name,
    required String email,
    required String operatorId,
    required String phoneNumber,
  }) async {
    try {
      await FirebaseSessionService.runWithFreshToken(() async {
        final callable = _functions.httpsCallable('saveOperatorProfile');
        await callable.call(<String, dynamic>{
          'name': name,
          'email': email,
          'operatorId': operatorId,
          'phoneNumber': phoneNumber,
        });
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        throw StateError(
          e.message ?? 'Operator ID $operatorId is already used.',
        );
      }
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        throw StateError(
          'Profile backend is not deployed yet. Deploy saveOperatorProfile '
          'to $_functionsRegion, then try again.',
        );
      }
      if (e.code == 'permission-denied') {
        throw StateError(
          e.message ??
              'You do not have permission to update this operator profile.',
        );
      }
      throw StateError(
        e.message ?? 'Unable to save profile. Please try again.',
      );
    } catch (e) {
      final message = e.toString();
      if (message.contains('NOT_FOUND') ||
          message.toLowerCase().contains('not-found')) {
        throw StateError(
          'Profile backend is not deployed in $_functionsRegion yet. Deploy '
          'saveOperatorProfile, then try again.',
        );
      }
      if (message.contains('ExecutionException')) {
        throw StateError(
          'Profile backend request failed. Please redeploy '
          'saveOperatorProfile and try again.',
        );
      }
      throw StateError('Unable to save profile. Please try again.');
    }
  }

  Future<void> _saveProfileDirect({
    required String uid,
    required String name,
    required String email,
    required String operatorId,
    required String phoneNumber,
    bool? isOnline,
  }) async {
    await FirebaseSessionService.runWithFreshToken(() async {
      final operatorRef = _db
          .collection(FirestoreCollections.operators)
          .doc(uid);
      final operatorIdIndexRef = _db
          .collection('operator_id_index')
          .doc(operatorId);
      final presenceRef = _db
          .collection(FirestoreCollections.operatorPresence)
          .doc(uid);

      await _db.runTransaction((tx) async {
        final operatorSnap = await tx.get(operatorRef);
        final operatorIdIndexSnap = await tx.get(operatorIdIndexRef);
        final presenceSnap = await tx.get(presenceRef);

        final currentOperatorId = normalizeOperatorId(
          operatorSnap.data()?[OperatorFields.operatorId]?.toString() ?? '',
        );
        if (operatorIdIndexSnap.exists) {
          final claimedBy = operatorIdIndexSnap.data()?['uid']?.toString();
          if (claimedBy != null && claimedBy.isNotEmpty && claimedBy != uid) {
            throw StateError('Operator ID $operatorId is already used.');
          }
        }

        final presenceData = presenceSnap.data() ?? const <String, dynamic>{};
        final resolvedOnline =
            isOnline ?? (presenceData[OperatorPresenceFields.isOnline] == true);

        tx.set(operatorRef, {
          OperatorFields.name: name,
          OperatorFields.email: email,
          OperatorFields.operatorId: operatorId,
          OperatorFields.phoneNumber: phoneNumber,
          OperatorFields.updatedAt: FieldValue.serverTimestamp(),
          if (!operatorSnap.exists)
            OperatorFields.createdAt: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(operatorIdIndexRef, {
          'uid': uid,
          OperatorFields.operatorId: operatorId,
          OperatorFields.updatedAt: FieldValue.serverTimestamp(),
          if (!operatorIdIndexSnap.exists)
            OperatorFields.createdAt: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (currentOperatorId.isNotEmpty && currentOperatorId != operatorId) {
          final oldOperatorIdIndexRef = _db
              .collection('operator_id_index')
              .doc(currentOperatorId);
          tx.delete(oldOperatorIdIndexRef);
        }

        tx.set(presenceRef, {
          OperatorPresenceFields.isOnline: resolvedOnline,
          OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    });
  }

  /// Updates operator profile fields.
  Future<void> updateOperator(
    String uid, {
    String? name,
    String? email,
    String? phoneNumber,
  }) async {
    await FirebaseSessionService.runWithFreshToken(() async {
      final updates = <String, dynamic>{
        OperatorFields.updatedAt: FieldValue.serverTimestamp(),
      };
      if (name != null) updates[OperatorFields.name] = name;
      if (email != null) updates[OperatorFields.email] = email;
      if (phoneNumber != null) {
        updates[OperatorFields.phoneNumber] = phoneNumber;
      }

      await _db
          .collection(FirestoreCollections.operators)
          .doc(uid)
          .update(updates);
    });
  }

  /// Sets the operator's online status.
  Future<void> setOnlineStatus(String uid, {required bool isOnline}) async {
    await FirebaseSessionService.runWithFreshToken(() async {
      final presenceRef = _db
          .collection(FirestoreCollections.operatorPresence)
          .doc(uid);

      await presenceRef.set({
        OperatorPresenceFields.isOnline: isOnline,
        OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Mirrors the current online flag into the presence collection.
  Future<void> syncPresence(String uid, {required bool isOnline}) async {
    await FirebaseSessionService.runWithFreshToken(() async {
      await _db.collection(FirestoreCollections.operatorPresence).doc(uid).set({
        OperatorPresenceFields.isOnline: isOnline,
        OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static OperatorModel _fromDocs(
    String uid,
    Map<String, dynamic> operatorData,
    Map<String, dynamic>? presenceData,
  ) {
    final data = <String, dynamic>{
      ...operatorData,
      OperatorFields.isOnline:
          presenceData?[OperatorPresenceFields.isOnline] == true,
    };

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
