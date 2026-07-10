// Main test file - runs all tests
// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';

// Import all test files
import 'models/user_model_test.dart' as user_model_tests;
import 'models/balance_model_test.dart' as balance_model_tests;
import 'models/order_model_test.dart' as order_model_tests;

void main() {
  group('CizreApp Tests', () {
    group('Models', () {
      user_model_tests.main();
      balance_model_tests.main();
      order_model_tests.main();
    });
  });
}
