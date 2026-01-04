import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'operator_profile_setup_page.dart';

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

    try {
      // Sign in with email and password
      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Verify that this user is an operator in Firestore
      final operatorDocRef = FirebaseFirestore.instance
          .collection('operators')
          .doc(userCredential.user!.uid);
      final operatorDoc = await operatorDocRef.get();

      // First-time login: no operator profile yet. Send to setup page.
      if (!operatorDoc.exists) {
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

      // Login successful - AuthWrapper will handle navigation
      
    } on FirebaseAuthException catch (e) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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
        title: const Text("Melaka Water Taxi"),
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
                
                // Welcome Icon with gradient background
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
                
                // Welcome Text
                Text(
                  "Operator Login",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Access your operator dashboard",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 40),
                
                // Email Field
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
                
                // Password Field
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
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
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
                
                // Login Button
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
                            "Login",
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
                    "Only registered operators can access this portal",
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
