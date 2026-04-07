import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorPresenceDebugUtils {
  const OperatorPresenceDebugUtils._();

  static const Duration staleThreshold = Duration(minutes: 10);

  static Future<void> syncPresence({
    required FirebaseFirestore db,
    required String operatorId,
    required bool profileOnline,
  }) {
    return db
        .collection(FirestoreCollections.operatorPresence)
        .doc(operatorId)
        .set({
          OperatorPresenceFields.isOnline: profileOnline,
          OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static int compareTimestamps(dynamic left, dynamic right) {
    final leftDate = asDateTime(left);
    final rightDate = asDateTime(right);
    if (leftDate == null && rightDate == null) return 0;
    if (leftDate == null) return -1;
    if (rightDate == null) return 1;
    return leftDate.compareTo(rightDate);
  }

  static DateTime? asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static bool isStale(DateTime? value) {
    if (value == null) return true;
    return DateTime.now().difference(value) > staleThreshold;
  }

  static String formatTimestamp(DateTime? value) {
    if (value == null) return 'N/A';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute:$second';
  }
}
