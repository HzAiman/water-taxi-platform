import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

enum PaymentGatewayStatus {
  success,
  failed,
  cancelled,
}

class PaymentGatewayConfig {
  const PaymentGatewayConfig({
    required this.stripePublishableKey,
    this.merchantDisplayName = 'Water Taxi',
    this.returnUrlScheme,
  });

  factory PaymentGatewayConfig.fromDartDefine() {
    return const PaymentGatewayConfig(
      stripePublishableKey: String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'),
      merchantDisplayName:
          String.fromEnvironment('STRIPE_MERCHANT_DISPLAY_NAME', defaultValue: 'Water Taxi'),
      returnUrlScheme: String.fromEnvironment(
        'STRIPE_RETURN_URL',
        defaultValue: 'watertaxistripe://stripe-redirect',
      ),
    );
  }

  final String stripePublishableKey;
  final String merchantDisplayName;
  final String? returnUrlScheme;

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
}

/// Production-oriented gateway service that delegates sensitive payment logic
/// to a secured Cloud Function.
class CloudFunctionPaymentGatewayService implements PaymentGatewayService {
  CloudFunctionPaymentGatewayService({
    FirebaseFunctions? functions,
    PaymentGatewayConfig? config,
  })  : _config = config ?? PaymentGatewayConfig.fromDartDefine(),
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;
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
      final callable = _functions.httpsCallable('createStripePaymentIntent');
      final response = await callable.call(<String, dynamic>{
        'amount': request.amount,
        'currency': request.currency,
        'userId': request.userId,
        'orderNumber': request.orderNumber,
        'payerName': request.payerName,
        'payerEmail': request.payerEmail,
        'payerTelephoneNumber': request.payerTelephoneNumber,
        'idempotencyKey': request.idempotencyKey,
        'description': request.description,
      });

      final data = Map<String, dynamic>.from(
        (response.data as Map?) ?? const <String, dynamic>{},
      );
      final status = (data['status'] ?? '').toString();
      final clientSecret = (data['clientSecret'] ?? '').toString();
      final paymentIntentId = (data['paymentIntentId'] ?? '').toString();

      if (status == 'ready' && clientSecret.isNotEmpty) {
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: _config.merchantDisplayName,
            returnURL: _config.returnUrlScheme,
          ),
        );

        await Stripe.instance.presentPaymentSheet();

        return PaymentGatewayResult(
          status: PaymentGatewayStatus.success,
          transactionId: paymentIntentId,
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
    } on FirebaseFunctionsException catch (e) {
      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage:
            'Payment service error (${e.code}): ${e.message ?? 'Unknown error'}',
      );
    } catch (_) {
      return const PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: 'Unable to reach payment service. Please try again.',
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
      status: PaymentGatewayStatus.success,
      transactionId: 'sim-$stamp-$suffix',
    );
  }
}
