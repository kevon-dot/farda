import 'package:farda/application/authentication/storage/auth_storage.dart';

/// Compatibility callers share the secure session boundary.
class StorageService {
  static Future<void> saveToken(String token) => AuthStorage.saveToken(token);
  static Future<String?> getToken() => AuthStorage.getToken();
  static Future<void> deleteSecureStorage() => AuthStorage.clear();
  @Deprecated('Use AuthStorage.saveSession; credentials are never preferences')
  static Future<void> saveTokensToPrefs({
    required String access,
    required String refresh,
    required String id,
  }) => AuthStorage.saveSession(access: access, refresh: refresh, id: id);
  static Future<void> clearPrefs() => AuthStorage.clear();
}
