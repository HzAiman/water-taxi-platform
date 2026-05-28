import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passenger_app/features/auth/presentation/pages/phone_login_page.dart';

void main() {
  const phoneNumber = '+601156950311';

  setUp(OtpRequestThrottle.resetForTesting);
  tearDown(OtpRequestThrottle.resetForTesting);

  group('OtpRequestThrottle', () {
    test('normal successful requests only start the short resend cooldown', () {
      for (var i = 0; i < 5; i++) {
        OtpRequestThrottle.recordSuccessfulRequest(phoneNumber);
      }

      final remaining = OtpRequestThrottle.remainingFor(phoneNumber);

      expect(remaining, greaterThan(Duration.zero));
      expect(remaining, lessThan(const Duration(minutes: 2)));
      expect(OtpRequestThrottle.isServerLockedOut(phoneNumber), isFalse);
    });

    test('server lockout keeps long cooldown', () {
      OtpRequestThrottle.recordServerLockout(phoneNumber);

      final remaining = OtpRequestThrottle.remainingFor(phoneNumber);

      expect(remaining, greaterThan(const Duration(minutes: 4)));
      expect(OtpRequestThrottle.isServerLockedOut(phoneNumber), isTrue);
    });

    test(
      'expired session can clear normal cooldown without clearing lockout',
      () {
        OtpRequestThrottle.recordSuccessfulRequest(phoneNumber);
        OtpRequestThrottle.allowImmediateRetry(phoneNumber);

        expect(OtpRequestThrottle.remainingFor(phoneNumber), Duration.zero);

        OtpRequestThrottle.recordServerLockout(phoneNumber);
        OtpRequestThrottle.allowImmediateRetry(phoneNumber);

        expect(
          OtpRequestThrottle.remainingFor(phoneNumber),
          greaterThan(Duration.zero),
        );
        expect(OtpRequestThrottle.isServerLockedOut(phoneNumber), isTrue);
      },
    );
  });

  group('OTP verification errors', () {
    test('session-expired is treated as a recoverable expired session', () {
      final error = FirebaseAuthException(code: 'session-expired');

      expect(isOtpSessionExpiredErrorForTesting(error), isTrue);
      expect(
        otpVerifyErrorMessageForTesting(error),
        'This code session expired. Please request a new OTP.',
      );
    });

    test('invalid-verification-id is treated as expired session', () {
      final error = FirebaseAuthException(code: 'invalid-verification-id');

      expect(isOtpSessionExpiredErrorForTesting(error), isTrue);
    });

    test('invalid-verification-code keeps the session retryable', () {
      final error = FirebaseAuthException(code: 'invalid-verification-code');

      expect(isOtpSessionExpiredErrorForTesting(error), isFalse);
      expect(
        otpVerifyErrorMessageForTesting(error),
        'The code is incorrect. Please check the latest SMS and try again.',
      );
    });
  });
}
