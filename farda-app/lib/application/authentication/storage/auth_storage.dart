import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage for auth state.
///
/// The access token is sensitive and is ALWAYS stored in [FlutterSecureStorage]
/// (Keychain on iOS / Keystore on Android), never in plaintext
/// SharedPreferences. Non-sensitive identifiers (user id, refresh placeholder,
/// display name) live in SharedPreferences.
///
/// Older builds also mirrored the token into the plaintext `access`
/// SharedPreferences key and read it back from there. That key is no longer
/// written and is proactively removed on save/migrate so the token only ever
/// lives in secure storage.
class AuthStorage {
  static const _secureStorage = FlutterSecureStorage();

  // Secure storage key.
  static const tokenKey = 'token';

  // SharedPreferences keys (non-sensitive).
  static const legacyAccessKey = 'access';
  static const refreshKey = 'refresh';
  static const idKey = 'id';
  static const nameKey = 'name';

  // ---------------------------------------------------------------------------
  // Token (secure storage only)
  // ---------------------------------------------------------------------------

  static Future<void> saveToken(String token) async {
    await _secureStorage.write(key: tokenKey, value: token);
  }

  /// Reads the access token from secure storage.
  ///
  /// Returns `null` on first launch / when the user is not authenticated.
  /// Transparently migrates a token left in the legacy plaintext `access`
  /// SharedPreferences key into secure storage, then deletes the plaintext copy.
  static Future<String?> getToken() async {
    final secure = await _secureStorage.read(key: tokenKey);
    if (secure != null && secure.isNotEmpty) {
      return secure;
    }

    // Migrate any token persisted by an older plaintext build.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyAccessKey);
    if (legacy != null && legacy.isNotEmpty) {
      await saveToken(legacy);
      await prefs.remove(legacyAccessKey);
      return legacy;
    }

    return null;
  }

  static Future<void> clearToken() async {
    await _secureStorage.delete(key: tokenKey);
  }

  // ---------------------------------------------------------------------------
  // Session (token in secure storage; metadata in SharedPreferences)
  // ---------------------------------------------------------------------------

  static Future<void> saveSession({
    required String access,
    required String refresh,
    required String id,
    String name = '',
  }) async {
    // Token -> secure storage.
    await saveToken(access);

    final prefs = await SharedPreferences.getInstance();
    // Ensure no plaintext token lingers from older builds.
    await prefs.remove(legacyAccessKey);
    await prefs.setString(refreshKey, refresh);
    await prefs.setString(idKey, id);
    await prefs.setString(nameKey, name);
  }

  /// Returns the session map. The `access` value is sourced from secure
  /// storage; the remaining fields come from SharedPreferences.
  static Future<Map<String, String?>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'access': await getToken(),
      'refresh': prefs.getString(refreshKey),
      'id': prefs.getString(idKey),
      'name': prefs.getString(nameKey),
    };
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await clearToken();
  }
}
