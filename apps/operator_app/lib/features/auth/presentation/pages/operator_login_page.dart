import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/auth/presentation/pages/operator_profile_setup_page.dart';

class OperatorLoginPage extends StatefulWidget {
  const OperatorLoginPage({super.key});

  @override
  State<OperatorLoginPage> createState() => _OperatorLoginPageState();
}

class _OperatorLoginPageState extends State<OperatorLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _logAuthTiming(
    String stage,
    Stopwatch stopwatch, {
    String status = 'ok',
    String? detail,
  }) {
    final extra = detail == null ? '' : ' detail=$detail';
    debugPrint(
      '[AuthTiming][Operator] stage=$stage status=$status durationMs=${stopwatch.elapsedMilliseconds}$extra',
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
        '[AuthTiming][Operator] flow=$flow status=$status totalMs=${totalStopwatch.elapsedMilliseconds} stageCount=0',
      );
      return;
    }

    final slowest = stageDurations.entries
        .reduce((a, b) => a.value >= b.value ? a : b);
    debugPrint(
      '[AuthTiming][Operator] flow=$flow status=$status totalMs=${totalStopwatch.elapsedMilliseconds} slowestStage=${slowest.key} slowestMs=${slowest.value} stageCount=${stageDurations.length}',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });
    final loginStopwatch = Stopwatch()..start();
    final stageDurations = <String, int>{};

    try {
      final signInStopwatch = Stopwatch()..start();
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      _logAuthTiming('login.signInWithEmailPassword', signInStopwatch);
      stageDurations['login.signInWithEmailPassword'] = signInStopwatch.elapsedMilliseconds;

      final operatorDocRef = FirebaseFirestore.instance
          .collection('operators')
          .doc(userCredential.user!.uid);
      final fetchDocStopwatch = Stopwatch()..start();
      final operatorDoc = await operatorDocRef.get();
      _logAuthTiming(
        'login.fetchOperatorDoc',
        fetchDocStopwatch,
        detail: operatorDoc.exists ? 'existingOperator' : 'newOperator',
      );
      stageDurations['login.fetchOperatorDoc'] = fetchDocStopwatch.elapsedMilliseconds;

      if (!operatorDoc.exists) {
        _logAuthTiming('login.navigateProfileSetup', loginStopwatch);
        stageDurations['login.navigateProfileSetup'] = loginStopwatch.elapsedMilliseconds;
        _logAttemptSummary('login', loginStopwatch, stageDurations);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OperatorProfileSetupPage(
                uid: userCredential.user!.uid,
                email: userCredential.user!.email ?? '',
              ),
            ),
          );
        }
        return;
      }
      _logAuthTiming('login.completed', loginStopwatch);
      stageDurations['login.completed'] = loginStopwatch.elapsedMilliseconds;
      _logAttemptSummary('login', loginStopwatch, stageDurations);
    } on FirebaseAuthException catch (e) {
      _logAuthTiming(
        'login.failed',
        loginStopwatch,
        status: 'error',
        detail: e.code,
      );
      stageDurations['login.failed'] = loginStopwatch.elapsedMilliseconds;
      _logAttemptSummary(
        'login',
        loginStopwatch,
        stageDurations,
        status: 'error',
      );
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No operator found with this email';
          break;
        case 'wrong-password':
          message = 'Incorrect password';
          break;
        case 'invalid-email':
          message = 'Invalid email address';
          break;
        case 'user-disabled':
          message = 'This account has been disabled';
          break;
        case 'too-many-requests':
          message = 'Too many failed attempts. Please try again later';
          break;
        default:
          message = 'Login failed: ${e.message}';
      }

      if (mounted) {
        showTopError(context, message: message, title: 'Login failed');
      }
    } catch (e) {
      _logAuthTiming(
        'login.failed',
        loginStopwatch,
        status: 'error',
        detail: e.runtimeType.toString(),
      );
      stageDurations['login.failed'] = loginStopwatch.elapsedMilliseconds;
      _logAttemptSummary(
        'login',
        loginStopwatch,
        stageDurations,
        status: 'error',
      );
      if (mounted) {
        showTopError(context, message: 'An error occurred: ${e.toString()}', title: 'Login failed');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Melaka Water Taxi'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
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
                      Icons.person_outline,
                      size: 70,
                      color: Color(0xFF0066CC),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Operator Login',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A1A),
                        fontSize: 28,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Access your operator dashboard',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'operator@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
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
                          onPressed: _login,
                          child: const Text(
                            'Login',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066CC).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Only registered operators can access this portal',
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
      ),
    );
  }
}