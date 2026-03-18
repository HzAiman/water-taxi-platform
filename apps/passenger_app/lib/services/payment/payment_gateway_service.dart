import 'dart:math';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';

enum PaymentGatewayStatus {
  authorized,    // ← NEW: Payment held, not captured
  success,       // (keep for backward compatibility, but now means captured)
  failed,
  cancelled,
}

class PaymentGatewayConfig {
  const PaymentGatewayConfig({
    required this.stripePublishableKey,
    this.merchantDisplayName = 'Water Taxi',
    this.returnUrlScheme,
    required this.paymentIntentEndpoint,
  });

  factory PaymentGatewayConfig.fromDartDefine() {
    return const PaymentGatewayConfig(
      stripePublishableKey: String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: 'pk_test_51T97A8DffuNgYO2I26KHN9DHMPqilZ5ZxO5KYwUxUA1X153WZNcMk1eO9jXCBQqo3Fcb9012xTIRovouQekYCuNS00SCObGaWN'),
      merchantDisplayName:
          String.fromEnvironment('STRIPE_MERCHANT_DISPLAY_NAME', defaultValue: 'Water Taxi'),
      returnUrlScheme: String.fromEnvironment(
        'STRIPE_RETURN_URL',
        defaultValue: 'watertaxistripe://stripe-redirect',
      ),
      paymentIntentEndpoint: String.fromEnvironment(
        'STRIPE_PAYMENT_INTENT_ENDPOINT',
        defaultValue:
            'https://asia-southeast1-melaka-water-taxi.cloudfunctions.net/createStripePaymentIntentHttp',
      ),
    );
  }

  final String stripePublishableKey;
  final String merchantDisplayName;
  final String? returnUrlScheme;
  final String paymentIntentEndpoint;

  bool get hasStripePublishableKey => stripePublishableKey.trim().isNotEmpty;
}

class PaymentGatewayRequest {
  const PaymentGatewayRequest({
    required this.userId,
    required this.amount,
    required this.currency,
    required this.orderNumber,
    required this.payerName,
    required this.payerEmail,
    required this.paymentMethod,
    required this.idempotencyKey,
    required this.description,
    this.payerTelephoneNumber,
  });

  final String userId;
  final double amount;
  final String currency;
  final String orderNumber;
  final String payerName;
  final String payerEmail;
  final String? payerTelephoneNumber;
  final String paymentMethod;
  final String idempotencyKey;
  final String description;
}

class PaymentGatewayResult {
  const PaymentGatewayResult({
    required this.status,
    this.transactionId,
    this.errorMessage,
  });

  final PaymentGatewayStatus status;
  final String? transactionId;
  final String? errorMessage;

  bool get isSuccess => status == PaymentGatewayStatus.success;
}

abstract class PaymentGatewayService {
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request);
  
  /// Captures a held payment intent. Returns success/failure.
  Future<PaymentGatewayResult> capturePayment({
    required String paymentIntentId,
    required String orderNumber,
  });
  
  /// Cancels a held payment intent. Returns success/failure.
  Future<PaymentGatewayResult> cancelPayment({
    required String paymentIntentId,
    required String orderNumber,
    String reason = 'requested_by_customer',
  });
}

/// Production-oriented gateway service that delegates sensitive payment logic
/// to a secured Cloud Function.
class CloudFunctionPaymentGatewayService implements PaymentGatewayService {
  CloudFunctionPaymentGatewayService({
    PaymentGatewayConfig? config,
  }) : _config = config ?? PaymentGatewayConfig.fromDartDefine();

  final PaymentGatewayConfig _config;

  @override
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request) async {
    if (!_config.hasStripePublishableKey) {
      return const PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage:
            'Stripe is not configured. Pass --dart-define=STRIPE_PUBLISHABLE_KEY=pk_... when running the app.',
      );
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return const PaymentGatewayResult(
          status: PaymentGatewayStatus.failed,
          errorMessage: 'You must be signed in to make payment.',
        );
      }

      final idToken = await currentUser.getIdToken();
      final uri = Uri.parse(_config.paymentIntentEndpoint);
      final response = await http
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(<String, dynamic>{
              'amount': request.amount,
              'currency': request.currency,
              'userId': request.userId,
              'orderNumber': request.orderNumber,
              'payerName': request.payerName,
              'payerEmail': request.payerEmail,
              'payerTelephoneNumber': request.payerTelephoneNumber,
              'idempotencyKey': request.idempotencyKey,
              'description': request.description,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final bodyMap = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PaymentGatewayResult(
          status: PaymentGatewayStatus.failed,
          errorMessage: (bodyMap['message'] ?? 'Payment service error').toString(),
        );
      }

      final data = bodyMap;
      final status = (data['status'] ?? '').toString();
      final clientSecret = (data['clientSecret'] ?? '').toString();
      final paymentIntentId = (data['paymentIntentId'] ?? '').toString();

      if (status == 'ready' && clientSecret.isNotEmpty && paymentIntentId.isNotEmpty) {
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: _config.merchantDisplayName,
            returnURL: _config.returnUrlScheme,
          ),
        );

        await Stripe.instance.presentPaymentSheet();

        return PaymentGatewayResult(
          status: PaymentGatewayStatus.authorized,  // ← CHANGE: Now returns "authorized" not "success"
          transactionId: paymentIntentId.isNotEmpty ? paymentIntentId : null,
        );
      }

      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: (data['message'] ?? 'Payment failed').toString(),
      );
    } on StripeException catch (e) {
      final code = e.error.code;
      if (code == FailureCode.Canceled) {
        return PaymentGatewayResult(
          status: PaymentGatewayStatus.cancelled,
          errorMessage:
              e.error.localizedMessage ?? 'Payment sheet was cancelled.',
        );
      }

      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage:
            e.error.localizedMessage ?? 'Stripe payment failed. Please try again.',
      );
    } catch (e) {
      final details = e.toString();
      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: 'Unable to reach payment service. $details',
      );
    }
  }

  /// Captures a held payment intent.
  /// Call this when the ride is completed.
  @override
  Future<PaymentGatewayResult> capturePayment({
    required String paymentIntentId,
    required String orderNumber,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return const PaymentGatewayResult(
          status: PaymentGatewayStatus.failed,
          errorMessage: 'You must be signed in to capture payment.',
        );
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('capturePaymentIntent')
          .call({
            'paymentIntentId': paymentIntentId,
            'orderNumber': orderNumber,
          });

      final data = result.data as Map<String, dynamic>?;
      if (data?['status'] == 'captured') {
        return PaymentGatewayResult(
          status: PaymentGatewayStatus.success,
          transactionId: paymentIntentId,
        );
      }

      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: data?['message'] ?? 'Failed to capture payment.',
      );
    } on FirebaseFunctionsException catch (e) {
      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: e.message ?? 'Payment capture failed.',
      );
    } catch (e) {
      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: 'Unable to capture payment: ${e.toString()}',
      );
    }
  }

  /// Cancels a held payment intent (refunds the held amount).
  /// Call this if the ride is cancelled before completion.
  @override
  Future<PaymentGatewayResult> cancelPayment({
    required String paymentIntentId,
    required String orderNumber,
    String reason = 'requested_by_customer',
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return const PaymentGatewayResult(
          status: PaymentGatewayStatus.failed,
          errorMessage: 'You must be signed in to cancel payment.',
        );
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('cancelPaymentIntent')
          .call({
            'paymentIntentId': paymentIntentId,
            'orderNumber': orderNumber,
            'reason': reason,
          });

      final data = result.data as Map<String, dynamic>?;
      final status = (data?['status'] ?? '').toString();
      if (status == 'cancelled' || status == 'refunded') {
        return PaymentGatewayResult(
          status: PaymentGatewayStatus.cancelled,
          transactionId: paymentIntentId,
        );
      }

      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: data?['message'] ?? 'Failed to cancel payment.',
      );
    } on FirebaseFunctionsException catch (e) {
      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: e.message ?? 'Payment cancellation failed.',
      );
    } catch (e) {
      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: 'Unable to cancel payment: ${e.toString()}',
      );
    }
  }
}

/// Temporary external-gateway adapter scaffold.
///
/// This implementation always returns success for supported methods and is
/// designed to be replaced with a real provider SDK/API integration.
class SimulatedExternalPaymentGatewayService implements PaymentGatewayService {
  SimulatedExternalPaymentGatewayService({
    Duration? simulatedLatency,
    PaymentGatewayConfig? config,
    bool requireStripeKey = false,
  })  : _requireStripeKey = requireStripeKey,
        _config = config ?? PaymentGatewayConfig.fromDartDefine(),
        _simulatedLatency =
            simulatedLatency ?? const Duration(milliseconds: 800);

  final Duration _simulatedLatency;
  final bool _requireStripeKey;
  final PaymentGatewayConfig _config;

  @override
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request) async {
    await Future<void>.delayed(_simulatedLatency);

    if (_requireStripeKey && !_config.hasStripePublishableKey) {
      return const PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage:
            'Stripe is not configured. Pass --dart-define=STRIPE_PUBLISHABLE_KEY=pk_... when running the app.',
      );
    }

    if (request.paymentMethod.trim().isEmpty) {
      return const PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: 'Unsupported payment method.',
      );
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = Random().nextInt(999999).toString().padLeft(6, '0');

    return PaymentGatewayResult(
      status: PaymentGatewayStatus.authorized,
      transactionId: 'sim-$stamp-$suffix',
    );
  }

  @override
  Future<PaymentGatewayResult> capturePayment({
    required String paymentIntentId,
    required String orderNumber,
  }) async {
    await Future<void>.delayed(_simulatedLatency);
    return PaymentGatewayResult(
      status: PaymentGatewayStatus.success,
      transactionId: paymentIntentId,
    );
  }

  @override
  Future<PaymentGatewayResult> cancelPayment({
    required String paymentIntentId,
    required String orderNumber,
    String reason = 'requested_by_customer',
  }) async {
    await Future<void>.delayed(_simulatedLatency);
    return PaymentGatewayResult(
      status: PaymentGatewayStatus.cancelled,
      transactionId: paymentIntentId,
    );
  }
}
