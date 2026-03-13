import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'app.dart';

void main() async {
  // CRITICAL: This line prevents the "Isolate" crash
  WidgetsFlutterBinding.ensureInitialized(); 

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // Enable offline persistence
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (e) {
    // Firebase already initialized (can happen on hot reload)
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  runApp(const PassengerApp());
}