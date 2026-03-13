import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:operator_app/app.dart';
import 'package:operator_app/firebase_options.dart';

void main() async {
  // CRITICAL: This line prevents the "Isolate" crash
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // Firebase already initialized (can happen on hot reload)
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  runApp(const OperatorApp());
}
