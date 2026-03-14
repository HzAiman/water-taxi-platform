import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

typedef PushForegroundCallback = void Function(String title, String body);

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  bool _started = false;

  Future<void> startForOperator(
    String operatorUid, {
    required PushForegroundCallback onForegroundMessage,
  }) async {
    if (_started) {
      return;
    }
    _started = true;

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await _messaging.getToken();
    if (token != null) {
      await _upsertToken(operatorUid, token);
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _upsertToken(operatorUid, newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) {
        return;
      }

      onForegroundMessage(
        notification.title ?? 'Operator update',
        notification.body ?? 'You have a new notification.',
      );
    });
  }

  Future<void> _upsertToken(String operatorUid, String token) {
    final platform = _platformLabel();
    return _firestore
        .collection(FirestoreCollections.operatorDevices)
        .doc(operatorUid)
        .set({
      DeviceTokenFields.token: token,
      DeviceTokenFields.platform: platform,
      DeviceTokenFields.appRole: 'operator',
      DeviceTokenFields.updatedAt: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _platformLabel() {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    return 'unknown';
  }
}
