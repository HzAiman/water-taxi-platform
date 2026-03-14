/// Payment method identifiers written to Firestore.
abstract final class PaymentMethods {
  static const String creditCard = 'credit_card';
  static const String eWallet = 'e_wallet';
  static const String onlineBanking = 'online_banking';

  /// All supported payment method identifiers.
  static const List<String> all = [creditCard, eWallet, onlineBanking];

  /// Returns a human-readable label for the given payment method identifier.
  static String label(String value) {
    switch (value) {
      case creditCard:
        return 'Credit / Debit Card';
      case eWallet:
        return 'E-Wallet';
      case onlineBanking:
        return 'Online Banking';
      default:
        return value;
    }
  }
}
