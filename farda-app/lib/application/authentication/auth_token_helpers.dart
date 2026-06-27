/// Pure-Dart helpers for the better-auth phoneNumber + bearer-token flow.
///
/// These functions contain no Flutter / plugin / platform-channel imports so
/// they can be unit-tested as plain Dart under `flutter test` in CI.
///
/// Background (better-auth, Main API PR #81):
///   * Send OTP:  POST /api/auth/phone-number/send-otp  { phoneNumber }
///   * Verify:    POST /api/auth/phone-number/verify     { phoneNumber, code }
///   * On a successful verify (and on session refresh) better-auth running in
///     bearer mode returns the freshly minted session token in the
///     `set-auth-token` response header. The session/user live in the JSON body.
///   * Authenticated requests then send `Authorization: Bearer <token>`.
class AuthTokenHelpers {
  AuthTokenHelpers._();

  /// better-auth phoneNumber plugin endpoints (relative to the API base URL,
  /// which already ends in `/api`).
  static const String sendOtpEndpoint = 'auth/phone-number/send-otp';
  static const String verifyEndpoint = 'auth/phone-number/verify';

  /// better-auth session endpoint. In bearer mode, calling this with a valid
  /// `Authorization: Bearer <token>` returns the current session and emits a
  /// rotated token in the `set-auth-token` response header, which we persist.
  static const String getSessionEndpoint = 'auth/get-session';

  /// Header better-auth uses to hand back the bearer token (response side).
  static const String setAuthTokenHeader = 'set-auth-token';

  /// Body for `POST /api/auth/phone-number/send-otp`.
  static Map<String, dynamic> sendOtpBody(String phoneNumber) {
    return {'phoneNumber': phoneNumber};
  }

  /// Body for `POST /api/auth/phone-number/verify`.
  ///
  /// better-auth's phoneNumber plugin expects the OTP under the `code` key.
  static Map<String, dynamic> verifyBody(String phoneNumber, String code) {
    return {'phoneNumber': phoneNumber, 'code': code};
  }

  /// Extracts the bearer token from a response `headers` map.
  ///
  /// better-auth emits the token under the `set-auth-token` header (lower-cased
  /// by `package:http`). Returns `null` when the header is absent or blank so
  /// callers can decide whether to keep an existing token.
  static String? extractToken(Map<String, String>? headers) {
    if (headers == null) return null;
    // `package:http` lower-cases response header names, but be defensive and
    // match case-insensitively so this helper is robust to other clients.
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == setAuthTokenHeader) {
        final value = entry.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  /// Whether a failed request warrants attempting a session refresh + retry.
  ///
  /// A `401 Unauthorized` means the bearer token was rejected (expired or
  /// rotated). Any other status is not an auth failure and must not trigger a
  /// refresh.
  static bool shouldRefreshOnStatus(int statusCode) => statusCode == 401;

  /// Whether we even have a token worth refreshing. A blank/absent token means
  /// the user is logged out; there is nothing to rotate, so refresh must be
  /// skipped (and the caller should route to login instead).
  static bool canRefresh(String? token) {
    return token != null && token.trim().isNotEmpty;
  }
}
