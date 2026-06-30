import 'package:flutter_test/flutter_test.dart';

/// LoginScreen widget tests require Firebase initialization which is not
/// available in the unit test environment. See integration tests for
/// full LoginScreen coverage.
void main() {
  testWidgets('LoginScreen placeholder', (tester) async {
    // Firebase + GoogleSignInService require native bindings not available
    // in unit tests. Integration tests cover the full login flow.
    expect(true, isTrue);
  });
}
