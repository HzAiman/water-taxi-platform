import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:passenger_app/main_screen.dart';

class RegistrationPage extends StatefulWidget {
  final String phoneNumber;

  const RegistrationPage({super.key, required this.phoneNumber});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  bool _validateInputs(String name, String email) {
    if (name.isEmpty) {
      _showErrorSnackBar("Please enter your name");
      return false;
    }

    if (name.length < 2) {
      _showErrorSnackBar("Name must be at least 2 characters");
      return false;
    }

    if (email.isEmpty) {
      _showErrorSnackBar("Please enter your email address");
      return false;
    }

    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      _showErrorSnackBar("Please enter a valid email address");
      return false;
    }

    return true;
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _completeRegistration() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    // Validate inputs
    if (!_validateInputs(name, email)) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get current user
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception("User not authenticated. Please login again.");
      }

      // Verify phone number is not empty
      if (widget.phoneNumber.isEmpty) {
        throw Exception("Phone number is missing");
      }

      // Save user data to Firestore
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set(
        {
          'uid': currentUser.uid,
          'phoneNumber': widget.phoneNumber,
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      _showSuccessSnackBar("Registration completed successfully!");

      // Small delay before navigation for better UX
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Navigate to main screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MainScreen()),
        (route) => false,
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnackBar("Firebase error: ${e.message ?? e.toString()}");
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnackBar(e.toString().replaceFirst('Exception: ', ''));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showErrorSnackBar("An unexpected error occurred: ${e.toString()}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Complete Registration"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              
              // Welcome Icon
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
                  Icons.person_add,
                  size: 70,
                  color: Color(0xFF0066CC),
                ),
              ),
              const SizedBox(height: 40),
              
              // Title
              Text(
                "Welcome to Melaka Water Taxi!",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 12),
              
              // Subtitle
              Text(
                "Please complete your profile",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 40),
              
              // Phone Number Display
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066CC).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF0066CC).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone, color: Color(0xFF0066CC)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.phoneNumber,
                        style: const TextStyle(
                          color: Color(0xFF0066CC),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Name Field
              TextField(
                controller: _nameController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: "Full Name",
                  hintText: "Enter your full name",
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                  prefixIcon: const Icon(Icons.person, color: Color(0xFF0066CC)),
                ),
              ),
              const SizedBox(height: 16),
              
              // Email Field
              TextField(
                controller: _emailController,
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email Address",
                  hintText: "Enter your email",
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                  prefixIcon: const Icon(Icons.email, color: Color(0xFF0066CC)),
                ),
              ),
              const SizedBox(height: 32),
              
              // Complete Registration Button
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
                      onPressed: _completeRegistration,
                      child: const Text(
                        "Complete Registration",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
