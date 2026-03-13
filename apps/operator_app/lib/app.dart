import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:operator_app/core/constants/app_constants.dart';
import 'package:operator_app/core/theme/app_theme.dart';
import 'package:operator_app/features/auth/presentation/pages/operator_login_page.dart';
import 'package:operator_app/features/auth/presentation/pages/operator_profile_setup_page.dart';
import 'package:operator_app/routes/main_screen.dart';

class OperatorApp extends StatelessWidget {
  const OperatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appName,
      theme: AppTheme.light,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!authSnap.hasData || authSnap.data == null) {
          return const OperatorLoginPage();
        }

        final user = authSnap.data!;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('operators').doc(user.uid).snapshots(),
          builder: (context, docSnap) {
            if (docSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!docSnap.hasData || !docSnap.data!.exists) {
              return OperatorProfileSetupPage(
                uid: user.uid,
                email: user.email ?? '',
              );
            }

            return const MainScreen();
          },
        );
      },
    );
  }
}