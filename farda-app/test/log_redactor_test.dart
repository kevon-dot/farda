// Pure-Dart unit tests for the log redaction helper and the auth-storage key
// contract. These import only the helper/storage files (no widgets, plugins, or
// platform channels are exercised) so they run fast and reliably under
// `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/utilities/logger_service.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';

void main() {
  group('LogRedactor.redact', () {
    test('masks a bearer token in a free-form string', () {
      const token = 'eyJhbGciOiJIUzI1NiJ9.payload.signature';
      final out = LogRedactor.redact('Authorization: Bearer $token');

      expect(out.contains(token), isFalse);
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('masks the value of an Authorization map/JSON entry', () {
      const token = 'abc123.def456.ghi789';
      final out = LogRedactor.redact('{"Authorization": "Bearer $token"}');

      expect(out.contains(token), isFalse);
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('is case-insensitive for the bearer scheme', () {
      final out = LogRedactor.redact('authorization: bearer secrettokenvalue');

      expect(out.contains('secrettokenvalue'), isFalse);
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('leaves non-sensitive content untouched', () {
      const safe = 'GET /doses | Status: 200 | Bytes: 1234';
      expect(LogRedactor.redact(safe), safe);
    });
  });

  group('LogRedactor.redactHeaders', () {
    test('masks Authorization but preserves other headers', () {
      final redacted = LogRedactor.redactHeaders({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer super.secret.token',
      });

      expect(redacted['Content-Type'], 'application/json');
      expect(redacted['Authorization'], '[REDACTED]');
    });

    test('matches the Authorization header case-insensitively', () {
      final redacted = LogRedactor.redactHeaders({
        'authorization': 'Bearer another.secret.token',
      });

      expect(redacted['authorization'], '[REDACTED]');
    });
  });

  group('AuthStorage key contract', () {
    test('token lives under a dedicated secure-storage key, not "access"', () {
      // The token must never share the plaintext SharedPreferences "access"
      // key; it is stored under its own secure-storage key.
      expect(AuthStorage.tokenKey, 'token');
      expect(AuthStorage.tokenKey, isNot(AuthStorage.legacyAccessKey));
      expect(AuthStorage.legacyAccessKey, 'access');
    });

    test('non-sensitive metadata keys are distinct', () {
      final keys = <String>{
        AuthStorage.refreshKey,
        AuthStorage.idKey,
        AuthStorage.nameKey,
      };
      expect(keys.length, 3);
      expect(keys.contains(AuthStorage.tokenKey), isFalse);
    });
  });
}
