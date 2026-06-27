// Pure-Dart unit tests for the better-auth phoneNumber + bearer-token helpers
// and the login provider's response parsing. These import only pure helper
// files (no widgets, plugins, or platform channels) so they run fast and
// reliably under `flutter test` in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/authentication/auth_token_helpers.dart';
import 'package:farda/screens/login/login_provider.dart';

void main() {
  group('AuthTokenHelpers endpoints', () {
    test('uses better-auth phoneNumber plugin paths', () {
      expect(AuthTokenHelpers.sendOtpEndpoint, 'auth/phone-number/send-otp');
      expect(AuthTokenHelpers.verifyEndpoint, 'auth/phone-number/verify');
      expect(AuthTokenHelpers.getSessionEndpoint, 'auth/get-session');
    });
  });

  group('AuthTokenHelpers.sendOtpBody', () {
    test('wraps the e164 phone number under phoneNumber', () {
      expect(
        AuthTokenHelpers.sendOtpBody('+8801712345678'),
        {'phoneNumber': '+8801712345678'},
      );
    });
  });

  group('AuthTokenHelpers.verifyBody', () {
    test('sends phoneNumber and the OTP under the code key', () {
      expect(
        AuthTokenHelpers.verifyBody('+8801712345678', '123456'),
        {'phoneNumber': '+8801712345678', 'code': '123456'},
      );
    });
  });

  group('AuthTokenHelpers.extractToken', () {
    test('reads the token from the set-auth-token header', () {
      final headers = {'set-auth-token': 'sess.abc.123'};
      expect(AuthTokenHelpers.extractToken(headers), 'sess.abc.123');
    });

    test('is case-insensitive on the header name', () {
      final headers = {'Set-Auth-Token': 'sess.xyz'};
      expect(AuthTokenHelpers.extractToken(headers), 'sess.xyz');
    });

    test('trims surrounding whitespace', () {
      final headers = {'set-auth-token': '  tok  '};
      expect(AuthTokenHelpers.extractToken(headers), 'tok');
    });

    test('returns null when the header is absent', () {
      expect(AuthTokenHelpers.extractToken({'content-type': 'json'}), isNull);
    });

    test('returns null for a blank header value', () {
      expect(AuthTokenHelpers.extractToken({'set-auth-token': '   '}), isNull);
    });

    test('returns null for null headers', () {
      expect(AuthTokenHelpers.extractToken(null), isNull);
    });
  });

  group('AuthTokenHelpers.shouldRefreshOnStatus', () {
    test('refreshes only on 401', () {
      expect(AuthTokenHelpers.shouldRefreshOnStatus(401), isTrue);
    });

    test('does not refresh on success or other errors', () {
      expect(AuthTokenHelpers.shouldRefreshOnStatus(200), isFalse);
      expect(AuthTokenHelpers.shouldRefreshOnStatus(403), isFalse);
      expect(AuthTokenHelpers.shouldRefreshOnStatus(500), isFalse);
    });
  });

  group('AuthTokenHelpers.canRefresh', () {
    test('true only when a real token is present', () {
      expect(AuthTokenHelpers.canRefresh('a.token'), isTrue);
    });

    test('false for null/empty/whitespace tokens', () {
      expect(AuthTokenHelpers.canRefresh(null), isFalse);
      expect(AuthTokenHelpers.canRefresh(''), isFalse);
      expect(AuthTokenHelpers.canRefresh('   '), isFalse);
    });
  });

  group('LoginProvider.userIdFromResponse', () {
    test('reads the nested better-auth user id', () {
      final id = LoginProvider.userIdFromResponse({
        'user': {'id': 'u-42', 'name': 'Jane'},
      });
      expect(id, 'u-42');
    });

    test('stringifies a numeric id', () {
      expect(
        LoginProvider.userIdFromResponse({
          'user': {'id': 7},
        }),
        '7',
      );
    });

    test('returns empty string when user/id is missing or response is null', () {
      expect(LoginProvider.userIdFromResponse({'user': {}}), '');
      expect(LoginProvider.userIdFromResponse({'session': {}}), '');
      expect(LoginProvider.userIdFromResponse(null), '');
    });
  });
}
