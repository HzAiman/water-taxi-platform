import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:passenger_app/main_screen.dart';
import 'package:passenger_app/registration_page.dart';
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

  String get _countryCode => countryCodes[_selectedCountry] ?? '+60';

  Future<void> _sendOTP() async {
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a phone number")),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    // Combine country code with phone number
    String fullPhoneNumber = "$_countryCode$phoneNumber";

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: fullPhoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android Auto-retrieval: Logs in automatically if SMS is detected
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.message}")),
        );
      },
      codeSent: (String verificationId, int? resendToken) {
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
      codeAutoRetrievalTimeout: (String verificationId) {},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Melaka Water Taxi"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              // Welcome Icon with gradient background
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0066CC).withValues(alpha: 0.1),
                      const Color(0xFF0066CC).withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.directions_boat,
                  size: 70,
                  color: Color(0xFF0066CC),
                ),
              ),
              const SizedBox(height: 40),
              // Welcome Text
              Text(
                "Welcome Aboard!",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Book your water taxi in just a few taps",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 40),
              
              // Country Dropdown
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDE5F0), width: 1.5),
                  color: Colors.white,
                ),
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCountry,
                  underline: const SizedBox(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  items: countryCodes.keys.map((country) {
                    return DropdownMenuItem(
                      value: country,
                      child: Text(
                        "$country (${countryCodes[country]})",
                        style: const TextStyle(fontSize: 15),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedCountry = value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              
              // Phone Input Field
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  prefixText: "$_countryCode  ",
                  prefixStyle: const TextStyle(
                    color: Color(0xFF0066CC),
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                  hintText: "Enter your phone number",
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                ),
              ),
              const SizedBox(height: 32),
              
              // Send OTP Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: _isLoading
                  ? ElevatedButton(
                      onPressed: null,
                      child: const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _sendOTP,
                      child: const Text(
                        "Send OTP Code",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              ),
              const SizedBox(height: 24),
              
              // Info Text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066CC).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "We'll send you a verification code via SMS",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
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
    _phoneController.dispose();
    super.dispose();
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
  int _secondsRemaining = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid 6-digit code")),
      );
      return;
    }

    setState(() => _isVerifying = true);
    try {
      AuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otpCode,
      );
      
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;

      // Check if user exists in Firestore
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Authentication error")),
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!mounted) return;

      if (userDoc.exists) {
        // User exists, go to main screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (route) => false,
        );
      } else {
        // New user, go to registration page
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => RegistrationPage(
              phoneNumber: widget.phoneNumber,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Invalid Code. Please try again. Error: ${e.toString()}")),
      );
    }
  }

  Future<void> _resendOTP() async {
    setState(() => _isVerifying = true);
    
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.message}")),
        );
      },
      codeSent: (String newVerificationId, int? newResendToken) {
        if (!mounted) return;
        setState(() {
          _isVerifying = false;
          _otpController.clear();
        });
        _startTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("OTP code sent again")),
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
      timeout: const Duration(seconds: 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify Code"),
        centerTitle: true,
      ),
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
                      const Color(0xFF0066CC).withValues(alpha: 0.1),
                      const Color(0xFF0066CC).withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.sms_outlined,
                  size: 70,
                  color: Color(0xFF0066CC),
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
                  color: const Color(0xFF0066CC),
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
                  color: Color(0xFF0066CC),
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
                  if (value.isNotEmpty && !RegExp(r'^[0-9]*$').hasMatch(value)) {
                    _otpController.text = value.replaceAll(RegExp(r'[^0-9]'), '');
                  }
                },
              ),
              const SizedBox(height: 32),
              
              // Timer or Resend Button
              if (!_canResend)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066CC).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Resend code in $_secondsRemaining seconds",
                    style: const TextStyle(
                      color: Color(0xFF0066CC),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              
              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: _isVerifying
                  ? ElevatedButton(
                      onPressed: null,
                      child: const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _verifyOTP,
                      child: const Text(
                        "Verify & Log In",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
                            color: Color(0xFF0066CC),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: const Text(
                        "Resend OTP Code",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0066CC),
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