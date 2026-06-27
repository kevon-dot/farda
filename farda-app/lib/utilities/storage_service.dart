import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _secureStorage = FlutterSecureStorage();

  // Secure Storage (for sensitive info like tokens)
  static Future<void> saveToken(String token) async {
    await _secureStorage.write(key: 'token', value: token);
  }

  static Future<String?> getToken() async {
    return await _secureStorage.read(key: 'token');
  }

  static Future<void> deleteSecureStorage() async {
    await _secureStorage.deleteAll();
  }

  // Shared Preferences (for non-sensitive cached data).
  //
  // NOTE: the access token is intentionally NOT stored here. It lives only in
  // secure storage (see [AuthStorage]). A previous `saveTokensToPrefs` helper
  // that wrote the token to plaintext SharedPreferences has been removed.
  static Future<void> clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
