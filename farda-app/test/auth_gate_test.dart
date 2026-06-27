// Pure-Dart unit tests for AuthGate, the helper that gates authenticated data
// fetches (dose times, mood, prescriptions) behind a valid bearer token.
// It imports only the helper (no widgets, plugins, or platform channels) so it
// runs fast and reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/utilities/auth_gate.dart';

void main() {
  group('AuthGate.hasValidToken', () {
    test('returns false for a null token (pre-login)', () {
      expect(AuthGate.hasValidToken(null), isFalse);
    });

    test('returns false for an empty token', () {
      expect(AuthGate.hasValidToken(''), isFalse);
    });

    test('returns false for a whitespace-only token', () {
      expect(AuthGate.hasValidToken('   '), isFalse);
    });

    test('returns true for a real token', () {
      expect(AuthGate.hasValidToken('eyJhbGciOi.aaa.bbb'), isTrue);
    });
  });

  group('AuthGate.shouldFetchAuthedData', () {
    test('does not fetch when there is no token yet', () {
      // Mirrors app startup before login: no token => no authenticated calls.
      expect(AuthGate.shouldFetchAuthedData(null), isFalse);
      expect(AuthGate.shouldFetchAuthedData(''), isFalse);
    });

    test('fetches only once authenticated', () {
      expect(AuthGate.shouldFetchAuthedData('a-valid-token'), isTrue);
    });
  });
}
