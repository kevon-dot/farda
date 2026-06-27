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

  // Shared Preferences (for non-sensitive cached data)
  static Future<void> saveTokensToPrefs({required String access, required String refresh, required String id}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access', access);
    await prefs.setString('refresh', refresh);
    await prefs.setString('id', id);
  }

  static Future<void> clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
