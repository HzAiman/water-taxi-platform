import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:passenger_app/core/theme/passenger_brand.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/features/auth/presentation/pages/registration_page.dart';
import 'package:passenger_app/routes/main_screen.dart';
import 'dart:async';

// Common country codes
const Map<String, String> countryCodes = {
  'Malaysia': '+60',
  'Singapore': '+65',
  'Indonesia': '+62',
  'Thailand': '+66',
  'Philippines': '+63',
  'Vietnam': '+84',
  'Cambodia': '+855',
  'Laos': '+856',
  'Myanmar': '+95',
  'Brunei': '+673',
};

@visibleForTesting
class OtpRequestThrottle {
  static const Duration normalCooldown = Duration(seconds: 60);
  static const Duration lockoutCooldown = Duration(minutes: 5);

  static final Map<String, DateTime> _nextAllowedAt = <String, DateTime>{};
  static final Map<String, DateTime> _serverLockoutUntil = <String, DateTime>{};

  static Duration remainingFor(String phoneNumber) {
    final now = DateTime.now();
    final nextAllowed = _nextAllowedAt[phoneNumber];
    final serverLockout = _serverLockoutUntil[phoneNumber];
    final effectiveNextAllowed =
        _laterOf(nextAllowed, serverLockout) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final remaining = effectiveNextAllowed.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static bool isServerLockedOut(String phoneNumber) {
    final lockoutUntil = _serverLockoutUntil[phoneNumber];
    return lockoutUntil != null && lockoutUntil.isAfter(DateTime.now());
  }

  static void recordSuccessfulRequest(String phoneNumber) {
    _nextAllowedAt[phoneNumber] = DateTime.now().add(normalCooldown);
  }

  static void recordServerLockout(String phoneNumber) {
    _serverLockoutUntil[phoneNumber] = DateTime.now().add(lockoutCooldown);
  }

  static void allowImmediateRetry(String phoneNumber) {
    _nextAllowedAt.remove(phoneNumber);
  }

  @visibleForTesting
  static void resetForTesting() {
    _nextAllowedAt.clear();
    _serverLockoutUntil.clear();
  }

  static DateTime? _laterOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

String _formatCooldown(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds <= 0) return 'a moment';
  if (totalSeconds < 60) {
    return '$totalSeconds second${totalSeconds == 1 ? '' : 's'}';
  }

  final minutes = (totalSeconds / 60).ceil();
  return '$minutes minute${minutes == 1 ? '' : 's'}';
}

String _friendlyPhoneAuthError(FirebaseAuthException error) {
  final message = error.message ?? '';
  final text = '${error.code} $message'.toLowerCase();

  if (_isOtpRateLimitError(error)) {
    return 'Too many OTP attempts. Please wait a few minutes before requesting another code.';
  }

  if (error.code == 'invalid-phone-number') {
    return 'Please enter a valid phone number, then try again.';
  }

  if (error.code == 'app-not-authorized' ||
      error.code == 'missing-client-identifier' ||
      text.contains('missing a valid app identifier')) {
    return 'Phone verification could not confirm this app. Please try again later or contact support.';
  }

  if (message.trim().isNotEmpty) {
    return message;
  }

  return 'Phone verification failed. Please try again.';
}

String _friendlyOtpVerifyError(FirebaseAuthException error) {
  if (error.code == 'invalid-verification-code') {
    return 'The code is incorrect. Please check the latest SMS and try again.';
  }

  if (error.code == 'session-expired') {
    return 'This code session expired. Please request a new OTP.';
  }

  if (error.code == 'invalid-verification-id') {
    return 'This OTP session is no longer valid. Please request a new OTP and use the latest SMS.';
  }

  return _friendlyPhoneAuthError(error);
}

bool _isOtpRateLimitError(FirebaseAuthException error) {
  final message = error.message ?? '';
  final text = '${error.code} $message'.toLowerCase();
  return error.code == 'too-many-requests' ||
      text.contains('blocked all requests') ||
      text.contains('unusual activity') ||
      text.contains('quota');
}

bool _isOtpSessionExpiredError(FirebaseAuthException error) {
  return error.code == 'session-expired' ||
      error.code == 'invalid-verification-id';
}

String _maskedPhoneNumber(String phoneNumber) {
  if (phoneNumber.length <= 4) {
    return '****';
  }
  return '${'*' * (phoneNumber.length - 4)}${phoneNumber.substring(phoneNumber.length - 4)}';
}

Future<void> _routeAfterPhoneAuthentication({
  required BuildContext context,
  required String phoneNumber,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) {
    if (context.mounted) {
      showTopError(context, message: 'Authentication error');
    }
    return;
  }

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUser.uid)
      .get();

  if (!context.mounted) {
    return;
  }

  if (userDoc.exists) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  } else {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => RegistrationPage(phoneNumber: phoneNumber),
      ),
      (route) => false,
    );
  }
}

@visibleForTesting
String otpVerifyErrorMessageForTesting(FirebaseAuthException error) {
  return _friendlyOtpVerifyError(error);
}

@visibleForTesting
bool isOtpSessionExpiredErrorForTesting(FirebaseAuthException error) {
  return _isOtpSessionExpiredError(error);
}

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  String _selectedCountry = 'Malaysia';
  bool _isLoading = false;
  bool _autoSignInCompleted = false;

  void _logAuthTiming(
    String stage,
    Stopwatch stopwatch, {
    String status = 'ok',
    String? detail,
  }) {
    if (!kDebugMode) {
      return;
    }
    final extra = detail == null ? '' : ' detail=$detail';
    debugPrint(
      '[AuthTiming][Passenger] stage=$stage status=$status durationMs=${stopwatch.elapsedMilliseconds}$extra',
    );
  }

  void _logAttemptSummary(
    String flow,
    Stopwatch totalStopwatch,
    Map<String, int> stageDurations, {
    String status = 'ok',
  }) {
    if (!kDebugMode) {
      return;
    }
    if (stageDurations.isEmpty) {
      debugPrint(
        '[AuthTiming][Passenger] flow=$flow status=$status totalMs=${totalStopwatch.elapsedMilliseconds} stageCount=0',
      );
      return;
    }

    final slowest = stageDurations.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    debugPrint(
      '[AuthTiming][Passenger] flow=$flow status=$status totalMs=${totalStopwatch.elapsedMilliseconds} slowestStage=${slowest.key} slowestMs=${slowest.value} stageCount=${stageDurations.length}',
    );
  }

  String get _countryCode => countryCodes[_selectedCountry] ?? '+60';

  Future<void> _sendOTP() async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) {
      if (!mounted) return;
      showTopError(context, message: 'Please enter a phone number');
      return;
    }

    final stopwatch = Stopwatch()..start();
    final stageDurations = <String, int>{};

    // Combine country code with phone number
    String fullPhoneNumber = "$_countryCode$phoneNumber";
    final cooldownRemaining = OtpRequestThrottle.remainingFor(fullPhoneNumber);
    if (cooldownRemaining > Duration.zero) {
      if (!mounted) return;
      showTopError(
        context,
        title: 'Please wait',
        message:
            'You can request another OTP in ${_formatCooldown(cooldownRemaining)}.',
      );
      return;
    }

    _autoSignInCompleted = false;
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android Auto-retrieval: Logs in automatically if SMS is detected
          _logAuthTiming('sendOtp.verificationCompleted', stopwatch);
          stageDurations['sendOtp.verificationCompleted'] =
              stopwatch.elapsedMilliseconds;
          final signInStopwatch = Stopwatch()..start();
          await FirebaseAuth.instance.signInWithCredential(credential);
          _logAuthTiming('sendOtp.autoSignIn', signInStopwatch);
          stageDurations['sendOtp.autoSignIn'] =
              signInStopwatch.elapsedMilliseconds;
          _logAttemptSummary('sendOtp', stopwatch, stageDurations);
          _autoSignInCompleted = true;
          if (!mounted) return;
          setState(() => _isLoading = false);
          await _routeAfterPhoneAuthentication(
            context: context,
            phoneNumber: fullPhoneNumber,
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          _logAuthTiming(
            'sendOtp.verificationFailed',
            stopwatch,
            status: 'error',
            detail: e.code,
          );
          stageDurations['sendOtp.verificationFailed'] =
              stopwatch.elapsedMilliseconds;
          _logAttemptSummary(
            'sendOtp',
            stopwatch,
            stageDurations,
            status: 'error',
          );
          if (_isOtpRateLimitError(e)) {
            OtpRequestThrottle.recordServerLockout(fullPhoneNumber);
          }
          if (!mounted) return;
          setState(() => _isLoading = false);
          showTopError(
            context,
            title: 'OTP request failed',
            message: _friendlyPhoneAuthError(e),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          _logAuthTiming('sendOtp.codeSent', stopwatch);
          stageDurations['sendOtp.codeSent'] = stopwatch.elapsedMilliseconds;
          _logAttemptSummary('sendOtp', stopwatch, stageDurations);
          OtpRequestThrottle.recordSuccessfulRequest(fullPhoneNumber);
          if (_autoSignInCompleted ||
              FirebaseAuth.instance.currentUser != null) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            return;
          }
          if (!mounted) return;
          setState(() => _isLoading = false);
          // Navigate to the OTP verification screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OTPScreen(
                verificationId: verificationId,
                phoneNumber: fullPhoneNumber,
                resendToken: resendToken,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _logAuthTiming(
            'sendOtp.autoRetrievalTimeout',
            stopwatch,
            status: 'timeout',
          );
          stageDurations['sendOtp.autoRetrievalTimeout'] =
              stopwatch.elapsedMilliseconds;
          _logAttemptSummary(
            'sendOtp',
            stopwatch,
            stageDurations,
            status: 'timeout',
          );
        },
        timeout: const Duration(seconds: 60),
      );
    } on FirebaseAuthException catch (e) {
      if (_isOtpRateLimitError(e)) {
        OtpRequestThrottle.recordServerLockout(fullPhoneNumber);
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      showTopError(
        context,
        title: 'OTP request failed',
        message: _friendlyPhoneAuthError(e),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showTopError(
        context,
        title: 'OTP request failed',
        message: 'Unable to request an OTP right now. Please try again later.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        extendBody: true,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [PassengerBrand.mint, PassengerBrand.blue],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = constraints.maxWidth > 430
                    ? 430.0
                    : constraints.maxWidth;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 56,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Image.asset(
                                'assets/app_icon/icon_trans.png',
                                width: 108,
                                height: 108,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Melaka Water Taxi',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 28,
                                    letterSpacing: -0.3,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Welcome to Melaka',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                            ),
                            const SizedBox(height: 32),
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.20),
                                    blurRadius: 30,
                                    offset: const Offset(0, 18),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Telephone Country Code',
                                      prefixIcon: Icon(Icons.public_outlined),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 2,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        value: _selectedCountry,
                                        items: countryCodes.keys.map((country) {
                                          return DropdownMenuItem(
                                            value: country,
                                            child: Text(
                                              '$country (${countryCodes[country]})',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: _isLoading
                                            ? null
                                            : (value) {
                                                if (value != null) {
                                                  setState(
                                                    () => _selectedCountry =
                                                        value,
                                                  );
                                                }
                                              },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    enabled: !_isLoading,
                                    decoration: InputDecoration(
                                      labelText: 'Phone number',
                                      hintText: 'Enter your phone number',
                                      prefixIcon: const Icon(
                                        Icons.phone_outlined,
                                      ),
                                      prefixText: '$_countryCode  ',
                                      prefixStyle: const TextStyle(
                                        color: PassengerBrand.blue,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                      hintStyle: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  _PassengerLoginButton(
                                    isLoading: _isLoading,
                                    onPressed: _isLoading ? null : _sendOTP,
                                  ),
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: PassengerBrand.mint.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: PassengerBrand.mint.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      "We'll send you a verification code via SMS.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }
}

class _PassengerLoginButton extends StatelessWidget {
  const _PassengerLoginButton({
    required this.isLoading,
    required this.onPressed,
    this.label = 'Send OTP Code',
  });

  final bool isLoading;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null
            ? null
            : const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [PassengerBrand.mint, PassengerBrand.blue],
              ),
        color: onPressed == null ? Colors.grey.shade300 : null,
        borderRadius: BorderRadius.circular(18),
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: PassengerBrand.blue.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

// --- OTP Verification Screen ---

class OTPScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final int? resendToken;

  const OTPScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.resendToken,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  static const Duration _otpSessionValidity = Duration(minutes: 5);

  late final List<TextEditingController> _otpControllers;
  late final List<FocusNode> _otpFocusNodes;
  bool _isVerifying = false;
  Timer? _timer;
  StreamSubscription<User?>? _authSubscription;
  late String _currentVerificationId;
  String _verificationIdSource = 'initialCodeSent';
  late DateTime _otpSentAt;
  late DateTime _otpExpiresAt;
  int? _currentResendToken;
  int _secondsRemaining = 60;
  bool _canResend = false;
  bool _isSessionExpired = false;
  bool _hasRoutedAfterAuth = false;

  void _logAuthTiming(
    String stage,
    Stopwatch stopwatch, {
    String status = 'ok',
    String? detail,
  }) {
    if (!kDebugMode) {
      return;
    }
    final extra = detail == null ? '' : ' detail=$detail';
    debugPrint(
      '[AuthTiming][Passenger] stage=$stage status=$status durationMs=${stopwatch.elapsedMilliseconds}$extra',
    );
  }

  void _logAttemptSummary(
    String flow,
    Stopwatch totalStopwatch,
    Map<String, int> stageDurations, {
    String status = 'ok',
  }) {
    if (!kDebugMode) {
      return;
    }
    if (stageDurations.isEmpty) {
      debugPrint(
        '[AuthTiming][Passenger] flow=$flow status=$status totalMs=${totalStopwatch.elapsedMilliseconds} stageCount=0',
      );
      return;
    }

    final slowest = stageDurations.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    debugPrint(
      '[AuthTiming][Passenger] flow=$flow status=$status totalMs=${totalStopwatch.elapsedMilliseconds} slowestStage=${slowest.key} slowestMs=${slowest.value} stageCount=${stageDurations.length}',
    );
  }

  void _logOtpSessionEvent(
    String event, {
    FirebaseAuthException? error,
    String? detail,
  }) {
    if (!kDebugMode) {
      return;
    }

    final now = DateTime.now();
    final ageSeconds = now.difference(_otpSentAt).inSeconds;
    final expiresInSeconds = _otpExpiresAt.difference(now).inSeconds;
    final errorDetail = error == null
        ? ''
        : ' errorCode=${error.code} errorMessage=${error.message ?? ''}';
    final extra = detail == null ? '' : ' detail=$detail';
    debugPrint(
      '[OTP][Passenger] event=$event phone=${_maskedPhoneNumber(widget.phoneNumber)} '
      'sessionAgeSec=$ageSeconds expiresInSec=$expiresInSeconds '
      'verificationIdSource=$_verificationIdSource isSessionExpired=$_isSessionExpired'
      '$errorDetail$extra',
    );
  }

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(6, (_) => TextEditingController());
    _otpFocusNodes = List.generate(6, (_) => FocusNode());
    _currentVerificationId = widget.verificationId;
    _currentResendToken = widget.resendToken;
    _resetOtpSession();
    _logOtpSessionEvent('screenStarted');
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null || _hasRoutedAfterAuth || !mounted) {
        return;
      }
      _routeAfterExistingAuthentication('authStateChanged');
    });
    if (FirebaseAuth.instance.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _hasRoutedAfterAuth) {
          return;
        }
        _routeAfterExistingAuthentication('screenStartedAlreadySignedIn');
      });
    }
    _startTimer();
  }

  Future<void> _routeAfterExistingAuthentication(String event) async {
    if (_hasRoutedAfterAuth) {
      return;
    }
    _hasRoutedAfterAuth = true;
    _timer?.cancel();
    _logOtpSessionEvent(event);
    if (mounted) {
      setState(() => _isVerifying = false);
    }
    await _routeAfterPhoneAuthentication(
      context: context,
      phoneNumber: widget.phoneNumber,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    final remaining = OtpRequestThrottle.remainingFor(widget.phoneNumber);
    _syncSessionExpiry();
    _secondsRemaining = remaining.inSeconds;
    _canResend = _secondsRemaining <= 0 || _isSessionExpired;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _syncSessionExpiry();
      if (_isSessionExpired) {
        setState(() {
          _secondsRemaining = 0;
          _canResend = true;
        });
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        setState(() => _canResend = true);
        timer.cancel();
      }
    });
  }

  void _resetOtpSession() {
    _otpSentAt = DateTime.now();
    _otpExpiresAt = _otpSentAt.add(_otpSessionValidity);
    _isSessionExpired = false;
  }

  void _markOtpSessionExpired() {
    _logOtpSessionEvent('markSessionExpired');
    OtpRequestThrottle.allowImmediateRetry(widget.phoneNumber);
    _timer?.cancel();
    setState(() {
      _isSessionExpired = true;
      _isVerifying = false;
      _secondsRemaining = 0;
      _canResend = true;
      _currentResendToken = null;
      _clearOtpFields();
    });
  }

  void _syncSessionExpiry() {
    if (_isSessionExpired || DateTime.now().isBefore(_otpExpiresAt)) {
      return;
    }
    OtpRequestThrottle.allowImmediateRetry(widget.phoneNumber);
    _isSessionExpired = true;
  }

  Future<void> _verifyOTP() async {
    _syncSessionExpiry();
    if (_isSessionExpired) {
      _logOtpSessionEvent('verifyBlockedExpired');
      showTopError(
        context,
        title: 'Verification failed',
        message: 'This code session expired. Please request a new OTP.',
      );
      return;
    }

    final otpCode = _otpCode;
    if (otpCode.isEmpty || otpCode.length != 6) {
      if (!mounted) return;
      showTopError(context, message: 'Please enter a valid 6-digit code');
      return;
    }

    setState(() => _isVerifying = true);
    _logOtpSessionEvent('verifyStarted');
    final verifyStopwatch = Stopwatch()..start();
    final stageDurations = <String, int>{};
    try {
      AuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _currentVerificationId,
        smsCode: otpCode,
      );

      final signInStopwatch = Stopwatch()..start();
      await FirebaseAuth.instance.signInWithCredential(credential);
      _logAuthTiming('verifyOtp.signInWithCredential', signInStopwatch);
      stageDurations['verifyOtp.signInWithCredential'] =
          signInStopwatch.elapsedMilliseconds;

      if (!mounted) return;
      _logAuthTiming('verifyOtp.routeAfterAuth', verifyStopwatch);
      stageDurations['verifyOtp.routeAfterAuth'] =
          verifyStopwatch.elapsedMilliseconds;
      _logAttemptSummary('verifyOtp', verifyStopwatch, stageDurations);
      await _routeAfterPhoneAuthentication(
        context: context,
        phoneNumber: widget.phoneNumber,
      );
    } on FirebaseAuthException catch (e) {
      _logAuthTiming(
        'verifyOtp.failed',
        verifyStopwatch,
        status: 'error',
        detail: e.code,
      );
      stageDurations['verifyOtp.failed'] = verifyStopwatch.elapsedMilliseconds;
      _logAttemptSummary(
        'verifyOtp',
        verifyStopwatch,
        stageDurations,
        status: 'error',
      );
      if (!mounted) return;

      if (FirebaseAuth.instance.currentUser != null) {
        _logOtpSessionEvent('verifyFailedButAlreadySignedIn', error: e);
        await _routeAfterExistingAuthentication('verifyFailedAlreadySignedIn');
        return;
      }

      if (_isOtpSessionExpiredError(e)) {
        _logOtpSessionEvent('verifySessionInvalid', error: e);
        _markOtpSessionExpired();
      } else {
        _logOtpSessionEvent('verifyFailed', error: e);
        setState(() {
          _isVerifying = false;
          if (e.code == 'invalid-verification-code') {
            _clearOtpFields();
          }
        });
      }
      showTopError(
        context,
        title: 'Verification failed',
        message: _friendlyOtpVerifyError(e),
      );
    } catch (e) {
      _logAuthTiming(
        'verifyOtp.failed',
        verifyStopwatch,
        status: 'error',
        detail: e.runtimeType.toString(),
      );
      stageDurations['verifyOtp.failed'] = verifyStopwatch.elapsedMilliseconds;
      _logAttemptSummary(
        'verifyOtp',
        verifyStopwatch,
        stageDurations,
        status: 'error',
      );
      if (!mounted) return;

      setState(() => _isVerifying = false);
      showTopError(
        context,
        title: 'Verification failed',
        message: 'Unable to verify the code right now. Please try again.',
      );
    }
  }

  Future<void> _resendOTP() async {
    _syncSessionExpiry();
    final cooldownRemaining = OtpRequestThrottle.remainingFor(
      widget.phoneNumber,
    );
    final isServerLockedOut = OtpRequestThrottle.isServerLockedOut(
      widget.phoneNumber,
    );
    if ((isServerLockedOut || !_isSessionExpired) &&
        cooldownRemaining > Duration.zero) {
      showTopError(
        context,
        title: 'Please wait',
        message:
            'You can request another OTP in ${_formatCooldown(cooldownRemaining)}.',
      );
      _startTimer();
      return;
    }

    setState(() => _isVerifying = true);
    final resendStopwatch = Stopwatch()..start();
    final stageDurations = <String, int>{};
    final forceResendingToken = _isSessionExpired ? null : _currentResendToken;

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          _logAuthTiming('resendOtp.verificationCompleted', resendStopwatch);
          stageDurations['resendOtp.verificationCompleted'] =
              resendStopwatch.elapsedMilliseconds;
          final signInStopwatch = Stopwatch()..start();
          await FirebaseAuth.instance.signInWithCredential(credential);
          _logAuthTiming('resendOtp.autoSignIn', signInStopwatch);
          stageDurations['resendOtp.autoSignIn'] =
              signInStopwatch.elapsedMilliseconds;
          _logAttemptSummary('resendOtp', resendStopwatch, stageDurations);
          if (!mounted) return;
          setState(() => _isVerifying = false);
          await _routeAfterPhoneAuthentication(
            context: context,
            phoneNumber: widget.phoneNumber,
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          _logAuthTiming(
            'resendOtp.verificationFailed',
            resendStopwatch,
            status: 'error',
            detail: e.code,
          );
          stageDurations['resendOtp.verificationFailed'] =
              resendStopwatch.elapsedMilliseconds;
          _logAttemptSummary(
            'resendOtp',
            resendStopwatch,
            stageDurations,
            status: 'error',
          );
          if (_isOtpRateLimitError(e)) {
            OtpRequestThrottle.recordServerLockout(widget.phoneNumber);
          }
          if (!mounted) return;
          setState(() => _isVerifying = false);
          _startTimer();
          showTopError(
            context,
            title: 'OTP request failed',
            message: _friendlyPhoneAuthError(e),
          );
        },
        codeSent: (String newVerificationId, int? newResendToken) {
          _logAuthTiming('resendOtp.codeSent', resendStopwatch);
          stageDurations['resendOtp.codeSent'] =
              resendStopwatch.elapsedMilliseconds;
          _logAttemptSummary('resendOtp', resendStopwatch, stageDurations);
          OtpRequestThrottle.recordSuccessfulRequest(widget.phoneNumber);
          if (!mounted) return;
          setState(() {
            _isVerifying = false;
            _currentVerificationId = newVerificationId;
            _verificationIdSource = 'resendCodeSent';
            _currentResendToken = newResendToken;
            _resetOtpSession();
            _clearOtpFields();
          });
          _logOtpSessionEvent('resendCodeSent');
          _startTimer();
          showTopSuccess(context, message: 'OTP code sent again');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted && verificationId.isNotEmpty) {
            setState(() {
              _currentVerificationId = verificationId;
              _verificationIdSource = 'resendAutoRetrievalTimeout';
            });
            _logOtpSessionEvent('resendAutoRetrievalTimeout');
          }
          _logAuthTiming(
            'resendOtp.autoRetrievalTimeout',
            resendStopwatch,
            status: 'timeout',
          );
          stageDurations['resendOtp.autoRetrievalTimeout'] =
              resendStopwatch.elapsedMilliseconds;
          _logAttemptSummary(
            'resendOtp',
            resendStopwatch,
            stageDurations,
            status: 'timeout',
          );
        },
        timeout: const Duration(seconds: 60),
      );
    } on FirebaseAuthException catch (e) {
      if (_isOtpRateLimitError(e)) {
        OtpRequestThrottle.recordServerLockout(widget.phoneNumber);
      }
      if (!mounted) return;
      setState(() => _isVerifying = false);
      _startTimer();
      showTopError(
        context,
        title: 'OTP request failed',
        message: _friendlyPhoneAuthError(e),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isVerifying = false);
      _startTimer();
      showTopError(
        context,
        title: 'OTP request failed',
        message: 'Unable to request another OTP right now. Please try later.',
      );
    }
  }

  String get _otpCode => _otpControllers.map((c) => c.text.trim()).join();

  void _clearOtpFields() {
    for (final controller in _otpControllers) {
      controller.clear();
    }
    _otpFocusNodes.first.requestFocus();
  }

  void _handleOtpChanged(String value, int index) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length > 1) {
      _fillOtpDigits(digits, startIndex: index);
      return;
    }

    if (digits.isEmpty) {
      _otpControllers[index].clear();
      if (index > 0) {
        _otpFocusNodes[index - 1].requestFocus();
      }
      return;
    }

    if (_otpControllers[index].text != digits) {
      _otpControllers[index].text = digits;
      _otpControllers[index].selection = TextSelection.collapsed(
        offset: digits.length,
      );
    }

    if (index < _otpFocusNodes.length - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    } else {
      _otpFocusNodes[index].unfocus();
    }
  }

  void _fillOtpDigits(String digits, {required int startIndex}) {
    var cursor = startIndex;
    for (final digit in digits.split('')) {
      if (cursor >= _otpControllers.length) {
        break;
      }
      _otpControllers[cursor].text = digit;
      cursor++;
    }

    final nextIndex = cursor.clamp(0, _otpFocusNodes.length - 1);
    if (cursor >= _otpFocusNodes.length) {
      _otpFocusNodes.last.unfocus();
    } else {
      _otpFocusNodes[nextIndex].requestFocus();
    }
  }

  String get _resendCountdownLabel {
    if (OtpRequestThrottle.isServerLockedOut(widget.phoneNumber)) {
      return 'Try again in $_secondsRemaining seconds';
    }
    return 'Resend code in $_secondsRemaining seconds';
  }

  String get _resendButtonLabel {
    if (_isSessionExpired) {
      return 'Request a new OTP';
    }
    return 'Resend OTP Code';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [PassengerBrand.mint, PassengerBrand.blue],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 4,
                  left: 16,
                  child: IconButton(
                    onPressed: _isVerifying
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth > 430
                        ? 430.0
                        : constraints.maxWidth;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: contentWidth,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - 36,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Container(
                                    width: 92,
                                    height: 92,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.22,
                                        ),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.sms_outlined,
                                      size: 48,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  'Verify Code',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 30,
                                        letterSpacing: -0.3,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Enter the 6-digit code sent to',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.88,
                                        ),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.phoneNumber,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 34),
                                Container(
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.20,
                                        ),
                                        blurRadius: 30,
                                        offset: const Offset(0, 18),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildOtpBoxes(),
                                      const SizedBox(height: 24),
                                      if (!_canResend)
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: PassengerBrand.mint
                                                .withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Text(
                                            _resendCountdownLabel,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: PassengerBrand.blue,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 22),
                                      _PassengerLoginButton(
                                        label: 'Verify & Log In',
                                        isLoading: _isVerifying,
                                        onPressed: _isVerifying
                                            ? null
                                            : _verifyOTP,
                                      ),
                                      if (_canResend)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 14,
                                          ),
                                          child: TextButton(
                                            onPressed: _isVerifying
                                                ? null
                                                : _resendOTP,
                                            child: Text(
                                              _resendButtonLabel,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: PassengerBrand.blue,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildOtpBoxes() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 5.0;
        final boxWidth = ((constraints.maxWidth - (gap * 5)) / 6).clamp(
          34.0,
          42.0,
        );

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            return Padding(
              padding: EdgeInsets.only(right: index == 5 ? 0 : gap),
              child: SizedBox(
                width: boxWidth,
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpFocusNodes[index],
                  enabled: !_isVerifying,
                  keyboardType: TextInputType.number,
                  textInputAction: index == 5
                      ? TextInputAction.done
                      : TextInputAction.next,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: PassengerBrand.blue,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    filled: true,
                    fillColor: PassengerBrand.surface,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: PassengerBrand.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: PassengerBrand.mint,
                        width: 2,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: PassengerBrand.border,
                      ),
                    ),
                  ),
                  onChanged: (value) => _handleOtpChanged(value, index),
                  onSubmitted: (_) {
                    if (index == 5) {
                      _verifyOTP();
                    }
                  },
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
