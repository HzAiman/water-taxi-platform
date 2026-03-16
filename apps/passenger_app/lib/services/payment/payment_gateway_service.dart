import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

enum PaymentGatewayStatus {
  success,
  failed,
  cancelled,
}

class PaymentBankOption {
  const PaymentBankOption({
    required this.code,
    required this.name,
  });

  final String code;
  final String name;
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
    required this.orderNumber,
    required this.payerName,
    required this.payerEmail,
    required this.paymentMethod,
    required this.idempotencyKey,
    required this.description,
    this.payerTelephoneNumber,
    this.payerBankCode,
    this.payerBankName,
  });

  final String userId;
  final double amount;
  final String currency;
  final String orderNumber;
  final String payerName;
  final String payerEmail;
  final String? payerTelephoneNumber;
  final String? payerBankCode;
  final String? payerBankName;
  final String paymentMethod;
  final String idempotencyKey;
  final String description;
}

class PaymentGatewayResult {
  const PaymentGatewayResult({
    required this.status,
    this.transactionId,
    this.redirectUrl,
    this.errorMessage,
  });

  final PaymentGatewayStatus status;
  final String? transactionId;
  final String? redirectUrl;
  final String? errorMessage;

  bool get isSuccess => status == PaymentGatewayStatus.success;
}

abstract class PaymentGatewayService {
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request);
  Future<List<PaymentBankOption>> fetchDobwBanks();
}

/// Production-oriented gateway service that delegates sensitive payment logic
/// to a secured Cloud Function.
class CloudFunctionPaymentGatewayService implements PaymentGatewayService {
  CloudFunctionPaymentGatewayService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  @override
  Future<PaymentGatewayResult> charge(PaymentGatewayRequest request) async {
    try {
      final callable = _functions.httpsCallable('createPaymentCharge');
      final response = await callable.call(<String, dynamic>{
        'amount': request.amount,
        'currency': request.currency,
        'orderNumber': request.orderNumber,
        'payerName': request.payerName,
        'payerEmail': request.payerEmail,
        'payerTelephoneNumber': request.payerTelephoneNumber,
        'payerBankCode': request.payerBankCode,
        'payerBankName': request.payerBankName,
        'paymentMethod': request.paymentMethod,
        'idempotencyKey': request.idempotencyKey,
        'description': request.description,
      });

      final data = Map<String, dynamic>.from(
        (response.data as Map?) ?? const <String, dynamic>{},
      );
      final status = (data['status'] ?? '').toString();

      if (status == 'success') {
        return PaymentGatewayResult(
          status: PaymentGatewayStatus.success,
          transactionId: (data['transactionId'] ?? '').toString(),
          redirectUrl: (data['redirectUrl'] ?? '').toString(),
        );
      }

      if (status == 'cancelled') {
        return PaymentGatewayResult(
          status: PaymentGatewayStatus.cancelled,
          errorMessage: (data['message'] ?? 'Payment cancelled').toString(),
        );
      }

      return PaymentGatewayResult(
        status: PaymentGatewayStatus.failed,
        errorMessage: (data['message'] ?? 'Payment failed').toString(),
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

  @override
  Future<List<PaymentBankOption>> fetchDobwBanks() async {
    try {
      final callable = _functions.httpsCallable('getDobwBanks');
      final response = await callable.call();
      final data = Map<String, dynamic>.from(
        (response.data as Map?) ?? const <String, dynamic>{},
      );
      final banks = (data['banks'] as List?) ?? const [];

      return banks
          .map((e) => Map<String, dynamic>.from((e as Map?) ?? const {}))
          .map(
            (e) => PaymentBankOption(
              code: (e['code'] ?? '').toString(),
              name: (e['name'] ?? '').toString(),
            ),
          )
          .where((b) => b.code.isNotEmpty && b.name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
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
            'Payment gateway is not configured. Pass --dart-define=PAYMENT_PORTAL_PUBLIC_KEY=...',
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
      redirectUrl: null,
    );
  }

  @override
  Future<List<PaymentBankOption>> fetchDobwBanks() async {
    return const [];
  }
}
