import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:passenger_app/core/theme/passenger_brand.dart';
import 'package:passenger_app/core/widgets/app_action_button.dart';
import 'package:passenger_app/core/widgets/gradient_app_bar.dart';
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

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  String _selectedCountry = 'Malaysia';
  bool _isLoading = false;

  void _logAuthTiming(
    String stage,
    Stopwatch stopwatch, {
    String status = 'ok',
    String? detail,
  }) {
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

    setState(() => _isLoading = true);
    final stopwatch = Stopwatch()..start();
    final stageDurations = <String, int>{};

    // Combine country code with phone number
    String fullPhoneNumber = "$_countryCode$phoneNumber";

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
        if (!mounted) return;
        setState(() => _isLoading = false);
        showTopError(context, message: 'Error: ${e.message}');
      },
      codeSent: (String verificationId, int? resendToken) {
        _logAuthTiming('sendOtp.codeSent', stopwatch);
        stageDurations['sendOtp.codeSent'] = stopwatch.elapsedMilliseconds;
        _logAttemptSummary('sendOtp', stopwatch, stageDurations);
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
  });

  final bool isLoading;
  final VoidCallback? onPressed;

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
            : const Text(
                'Send OTP Code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
  final TextEditingController _otpController = TextEditingController();
  bool _isVerifying = false;
  late Timer _timer;
  late String _currentVerificationId;
  int? _currentResendToken;
  int _secondsRemaining = 60;
  bool _canResend = false;

  void _logAuthTiming(
    String stage,
    Stopwatch stopwatch, {
    String status = 'ok',
    String? detail,
  }) {
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

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _currentResendToken = widget.resendToken;
    _startTimer();
  }

  void _startTimer() {
    _secondsRemaining = 60;
    _canResend = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        setState(() => _canResend = true);
        _timer.cancel();
      }
    });
  }

  Future<void> _verifyOTP() async {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty || otpCode.length != 6) {
      if (!mounted) return;
      showTopError(context, message: 'Please enter a valid 6-digit code');
      return;
    }

    setState(() => _isVerifying = true);
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

      // Check if user exists in Firestore
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() => _isVerifying = false);
        showTopError(context, message: 'Authentication error');
        return;
      }

      final userDocStopwatch = Stopwatch()..start();
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      _logAuthTiming(
        'verifyOtp.fetchUserDoc',
        userDocStopwatch,
        detail: userDoc.exists ? 'existingUser' : 'newUser',
      );
      stageDurations['verifyOtp.fetchUserDoc'] =
          userDocStopwatch.elapsedMilliseconds;

      if (!mounted) return;

      if (userDoc.exists) {
        _logAuthTiming('verifyOtp.navigateMain', verifyStopwatch);
        stageDurations['verifyOtp.navigateMain'] =
            verifyStopwatch.elapsedMilliseconds;
        _logAttemptSummary('verifyOtp', verifyStopwatch, stageDurations);
        // User exists, go to main screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (route) => false,
        );
      } else {
        _logAuthTiming('verifyOtp.navigateRegistration', verifyStopwatch);
        stageDurations['verifyOtp.navigateRegistration'] =
            verifyStopwatch.elapsedMilliseconds;
        _logAttemptSummary('verifyOtp', verifyStopwatch, stageDurations);
        // New user, go to registration page
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) =>
                RegistrationPage(phoneNumber: widget.phoneNumber),
          ),
          (route) => false,
        );
      }
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
        message: 'Invalid code. Please try again. Error: ${e.toString()}',
      );
    }
  }

  Future<void> _resendOTP() async {
    setState(() => _isVerifying = true);
    final resendStopwatch = Stopwatch()..start();
    final stageDurations = <String, int>{};

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      forceResendingToken: _currentResendToken,
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
        if (!mounted) return;
        setState(() => _isVerifying = false);
        showTopError(context, message: 'Error: ${e.message}');
      },
      codeSent: (String newVerificationId, int? newResendToken) {
        _logAuthTiming('resendOtp.codeSent', resendStopwatch);
        stageDurations['resendOtp.codeSent'] =
            resendStopwatch.elapsedMilliseconds;
        _logAttemptSummary('resendOtp', resendStopwatch, stageDurations);
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
          _currentVerificationId = newVerificationId;
          _currentResendToken = newResendToken;
          _otpController.clear();
        });
        _startTimer();
        showTopSuccess(context, message: 'OTP code sent again');
      },
      codeAutoRetrievalTimeout: (String verificationId) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Verify Code'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // SMS Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      PassengerBrand.mint.withValues(alpha: 0.12),
                      PassengerBrand.blue.withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.sms_outlined,
                  size: 70,
                  color: PassengerBrand.blue,
                ),
              ),
              const SizedBox(height: 40),

              // Title
              Text(
                "Verify Your Number",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 12),

              // Instructions
              Text(
                "Enter the 6-digit code sent to",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),

              // Phone Number
              Text(
                widget.phoneNumber,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: PassengerBrand.blue,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 40),

              // OTP Input Field
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                enabled: !_isVerifying,
                style: const TextStyle(
                  fontSize: 36,
                  letterSpacing: 12,
                  fontWeight: FontWeight.bold,
                  color: PassengerBrand.blue,
                ),
                decoration: InputDecoration(
                  counterText: "",
                  hintText: "- - - - - -",
                  hintStyle: const TextStyle(
                    fontSize: 36,
                    letterSpacing: 8,
                    color: Color(0xFFDDE5F0),
                  ),
                ),
                onChanged: (value) {
                  // Validate that only numbers are entered
                  if (value.isNotEmpty &&
                      !RegExp(r'^[0-9]*$').hasMatch(value)) {
                    _otpController.text = value.replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );
                  }
                },
              ),
              const SizedBox(height: 32),

              // Timer or Resend Button
              if (!_canResend)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PassengerBrand.mint.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Resend code in $_secondsRemaining seconds",
                    style: const TextStyle(
                      color: PassengerBrand.blue,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Verify Button
              AppActionButton(
                label: 'Verify & Log In',
                onPressed: _isVerifying ? null : _verifyOTP,
                isLoading: _isVerifying,
              ),

              // Resend Button (appears after 60 seconds)
              if (_canResend)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TextButton(
                      onPressed: _resendOTP,
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                            color: PassengerBrand.blue,
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: const Text(
                        "Resend OTP Code",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PassengerBrand.blue,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    _timer.cancel();
    super.dispose();
  }
}
