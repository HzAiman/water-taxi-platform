import 'dart:math';

import 'package:water_taxi_shared/water_taxi_shared.dart';

enum PaymentGatewayStatus {
  success,
  failed,
  cancelled,
}

class PaymentGatewayConfig {
  const PaymentGatewayConfig({
    required this.portalPublicKey,
  });

  factory PaymentGatewayConfig.fromDartDefine() {
    return const PaymentGatewayConfig(
      portalPublicKey: String.fromEnvironment('PAYMENT_PORTAL_PUBLIC_KEY'),
    );
  }

  final String portalPublicKey;

  bool get hasPortalPublicKey => portalPublicKey.trim().isNotEmpty;
}

class PaymentGatewayRequest {
  const PaymentGatewayRequest({
    required this.userId,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
    required this.idempotencyKey,
    required this.description,
  });

  final String userId;
  final double amount;
  final String currency;
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

/// Temporary external-gateway adapter scaffold.
///
/// This implementation always returns success for supported methods and is
/// designed to be replaced with a real provider SDK/API integration.
class SimulatedExternalPaymentGatewayService implements PaymentGatewayService {
  SimulatedExternalPaymentGatewayService({
    Duration? simulatedLatency,
    PaymentGatewayConfig? config,
    bool requirePortalKey = false,
  })  : _requirePortalKey = requirePortalKey,
        _config = config ?? PaymentGatewayConfig.fromDartDefine(),
        _simulatedLatency =
            simulatedLatency ?? const Duration(milliseconds: 800);

  final Duration _simulatedLatency;
  final bool _requirePortalKey;
  final PaymentGatewayConfig _config;

  @override
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request) async {
    await Future<void>.delayed(_simulatedLatency);

    if (_requirePortalKey && !_config.hasPortalPublicKey) {
      return const PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage:
            'Payment gateway is not configured. Run with --dart-define=PAYMENT_PORTAL_PUBLIC_KEY=...',
      );
    }

    if (!PaymentMethods.all.contains(request.paymentMethod)) {
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
