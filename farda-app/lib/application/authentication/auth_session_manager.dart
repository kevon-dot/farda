import 'package:farda/application/authentication/auth_token_helpers.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/env.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/utilities/logger_service.dart';
import 'package:farda/utilities/storage_service.dart';
import 'package:http/http.dart' as http;

/// Centralises bearer-token rotation and clean logout for the better-auth
/// session (issue #19).
///
/// In better-auth bearer mode a session is "refreshed" by calling
/// `GET /api/auth/get-session` with the current `Authorization: Bearer <token>`
/// header. On success better-auth returns a rotated token in the
/// `set-auth-token` response header, which we persist. On failure (or when
/// there is no token to refresh) we log out cleanly: clear all stored tokens
/// and route back to login.
///
/// This is the ONE place the refresh/rotation + logout policy lives; the HTTP
/// client ([ApiService]) delegates to it so call sites never reimplement it.
class AuthSessionManager {
  AuthSessionManager._();

  /// Guards against several concurrent 401s all firing a refresh at once: the
  /// first refresh wins and the rest await its result.
  static Future<bool>? _inFlight;

  /// Attempts to refresh + rotate the stored bearer token.
  ///
  /// Returns `true` when a new token was obtained and persisted, `false`
  /// otherwise. A `false` result means the caller should treat the session as
  /// dead (see [logout]).
  ///
  /// Concurrent callers share a single in-flight refresh.
  static Future<bool> refreshSession() {
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  static Future<bool> _doRefresh() async {
    final current = await AuthStorage.getToken();
    if (!AuthTokenHelpers.canRefresh(current)) {
      return false;
    }

    try {
      final uri =
          Uri.parse("$appBaseUrl/${AuthTokenHelpers.getSessionEndpoint}");
      final response = await http.get(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $current",
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        Log.w("⚠️ Session refresh failed | Status: ${response.statusCode}");
        return false;
      }

      // better-auth rotates the token in the `set-auth-token` header. If the
      // header is absent the existing token is still considered valid (the
      // session call succeeded), so keep it.
      final rotated = AuthTokenHelpers.extractToken(response.headers);
      if (rotated != null && rotated != current) {
        await AuthStorage.saveToken(rotated);
        Log.d("🔄 Bearer token rotated after session refresh");
      }
      return true;
    } catch (e, st) {
      Log.e("❌ Session refresh error", error: e, stackTrace: st);
      return false;
    }
  }

  /// Clears all stored auth state and routes back to login. Safe to call more
  /// than once.
  static Future<void> logout() async {
    await AuthStorage.clearSession();
    await StorageService.clearPrefs();
    await StorageService.deleteSecureStorage();
    // Clear the cached auth flag so the router guard now treats the user as
    // unauthenticated (and /login is no longer redirected back to /dashboard).
    AppRouter.authState.setAuthed(false);
    Log.w("⚠️ Session ended - routing to login");
    AppRouter.router.go(CustomRoutePaths.login);
  }
}
