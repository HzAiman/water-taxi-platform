import 'package:firebase_auth/firebase_auth.dart';

class FirebaseSessionService {
  const FirebaseSessionService._();

  static Future<void> refreshIdToken({FirebaseAuth? auth}) async {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) {
      throw StateError('Session expired. Please sign in again.');
    }
    await user.getIdToken(true);
  }

  static Future<T> runWithFreshToken<T>(
    Future<T> Function() action, {
    FirebaseAuth? auth,
  }) async {
    await refreshIdToken(auth: auth);

    try {
      return await action();
    } catch (error) {
      if (!isSessionPermissionError(error)) {
        rethrow;
      }

      await refreshIdToken(auth: auth);
      return action();
    }
  }

  static bool isSessionPermissionError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('permission-denied') ||
        text.contains('permission denied') ||
        text.contains('unauthenticated') ||
        text.contains('user-token-expired') ||
        text.contains('token-expired') ||
        text.contains('requires recent authentication');
  }

  static bool shouldReturnToLogin(Object error) {
    if (error is StateError) {
      return true;
    }

    if (error is FirebaseAuthException) {
      return const {
        'invalid-user-token',
        'user-token-expired',
        'user-disabled',
        'user-not-found',
      }.contains(error.code);
    }

    final text = error.toString().toLowerCase();
    return text.contains('invalid-user-token') ||
        text.contains('user-token-expired') ||
        text.contains('user-disabled') ||
        text.contains('user-not-found') ||
        text.contains('unauthenticated');
  }
}
