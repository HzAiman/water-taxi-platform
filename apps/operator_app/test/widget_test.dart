import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/core/constants/app_constants.dart';

void main() {
  test('app name constant is defined', () {
    expect(AppConstants.appName, 'Melaka Water Taxi - Operator');
  });
}
