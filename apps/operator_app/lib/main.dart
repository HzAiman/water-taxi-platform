import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:operator_app/app.dart';
import 'package:operator_app/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  final bookingRepo = BookingRepository();
  final operatorRepo = OperatorRepository();

  runApp(
    MultiProvider(
      providers: [
        // Repositories
        Provider<BookingRepository>.value(value: bookingRepo),
        Provider<OperatorRepository>.value(value: operatorRepo),

        // App-scoped ViewModel
        ChangeNotifierProvider<OperatorHomeViewModel>(
          create: (_) => OperatorHomeViewModel(
            bookingRepo: bookingRepo,
            operatorRepo: operatorRepo,
          ),
        ),
      ],
      child: const OperatorApp(),
    ),
  );
}
