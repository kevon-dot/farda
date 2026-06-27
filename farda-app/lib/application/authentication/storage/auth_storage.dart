import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _secureStorage = FlutterSecureStorage();

  // Secure Storage
  static Future<void> saveToken(String token) async {
    await _secureStorage.write(key: 'token', value: token);
  }

  static Future<String?> getToken() async {
    return await _secureStorage.read(key: 'token');
  }

  static Future<void> clearToken() async {
    await _secureStorage.delete(key: 'token');
  }

  // Shared Preferences (for non-sensitive data, user info, access etc)
  static Future<void> saveSession({required String access, required String refresh, required String id}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access', access);
    await prefs.setString('refresh', refresh);
    await prefs.setString('id', id);
  }

  static Future<Map<String, String?>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'access': prefs.getString('access'),
      'refresh': prefs.getString('refresh'),
      'id': prefs.getString('id'),
    };
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
