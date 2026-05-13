const String operatorMalaysiaCountryCode = '+60';

String operatorPhoneLocalPart(String phoneNumber) {
  var value = phoneNumber.trim().replaceAll(RegExp(r'\s+|-'), '');
  if (value.startsWith(operatorMalaysiaCountryCode)) {
    value = value.substring(operatorMalaysiaCountryCode.length);
  } else if (value.startsWith('60')) {
    value = value.substring(2);
  }
  if (value.startsWith('0')) {
    value = value.substring(1);
  }
  return value;
}

String formatOperatorMalaysiaPhoneNumber(String phoneNumber) {
  final localPart = operatorPhoneLocalPart(phoneNumber);
  if (localPart.isEmpty) {
    return '';
  }
  return '$operatorMalaysiaCountryCode$localPart';
}
