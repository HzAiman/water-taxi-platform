import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';

import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/fare_repository.dart';
import 'package:passenger_app/data/repositories/jetty_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/home_view_model.dart';
import 'package:passenger_app/features/profile/presentation/viewmodels/profile_view_model.dart';
import 'package:passenger_app/services/payment/payment_gateway_service.dart';
import 'firebase_options.dart';
import 'app.dart';

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

  final stripePublishableKey = const String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue:
        'pk_test_51T97A8DffuNgYO2I26KHN9DHMPqilZ5ZxO5KYwUxUA1X153WZNcMk1eO9jXCBQqo3Fcb9012xTIRovouQekYCuNS00SCObGaWN',
  );
  final stripeMerchantIdentifier =
      const String.fromEnvironment('STRIPE_MERCHANT_IDENTIFIER');
  final stripeUrlScheme = const String.fromEnvironment(
    'STRIPE_URL_SCHEME',
    defaultValue: 'watertaxistripe',
  );

  if (stripePublishableKey.trim().isNotEmpty) {
    Stripe.publishableKey = stripePublishableKey;
    if (stripeMerchantIdentifier.trim().isNotEmpty) {
      Stripe.merchantIdentifier = stripeMerchantIdentifier;
    }
    Stripe.urlScheme = stripeUrlScheme;
    // Do not block first frame on Stripe SDK setup.
    Stripe.instance.applySettings().catchError((_) {});
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // App Check helps reduce callable token fetch failures.
      // For development, we skip App Check to avoid provider compatibility issues.
      // In production, configure:
      // await FirebaseAppCheck.instance.activate(
      //   providerAndroid: AndroidAppCheckProvider.safetyNet(),
      //   providerApple: AppleAppCheckProvider.appAttest(),
      // );

      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    if (!e.toString().contains('duplicate-app')) {
      rethrow;
    }
  }

  // Repositories are singletons; ViewModels are created per-screen via
  // context.read<Repository>() inside each screen's initState.
  final bookingRepo = BookingRepository();
  final userRepo = UserRepository();
  final jettyRepo = JettyRepository();
  final fareRepo = FareRepository();
  final paymentGateway = CloudFunctionPaymentGatewayService();

  runApp(
    MultiProvider(
      providers: [
        // Repositories
        Provider<BookingRepository>.value(value: bookingRepo),
        Provider<UserRepository>.value(value: userRepo),
        Provider<JettyRepository>.value(value: jettyRepo),
        Provider<FareRepository>.value(value: fareRepo),
        Provider<PaymentGatewayService>.value(value: paymentGateway),

        // App-scoped ViewModels
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) => HomeViewModel(
            userRepo: userRepo,
            jettyRepo: jettyRepo,
            fareRepo: fareRepo,
            bookingRepo: bookingRepo,
          ),
        ),
        ChangeNotifierProvider<ProfileViewModel>(
          create: (_) => ProfileViewModel(
            userRepo: userRepo,
            bookingRepo: bookingRepo,
          ),
        ),
      ],
      child: const PassengerApp(),
    ),
  );
}
