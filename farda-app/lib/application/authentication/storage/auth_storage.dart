import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:farda/utilities/platform_secure_store.dart';
import 'session_store.dart';
export 'session_store.dart';

class AuthStorage {
  static final ValueNotifier<int> sessionRevision = ValueNotifier<int>(0);
  static final SessionStore _sessions = SessionStore(
    const PlatformSecureStore(),
    purgeLegacyPreferences: _purgeLegacyPreferences,
    onSessionChanged: () => sessionRevision.value++,
  );
  static Future<void> _purgeLegacyPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['access', 'refresh', 'id', 'token']) {
      await prefs.remove(key);
    }
  }

  static SessionStore get sessionStore => _sessions;
  static Future<StoredSession?> readSession() => _sessions.read();
  static Future<void> saveSession({
    required String access,
    String refresh = '',
    required String id,
  }) => _sessions.save(StoredSession(token: access, userId: id));
  static Future<Map<String, String?>> getSession() async {
    final session = await readSession();
    return {'access': session?.token, 'refresh': null, 'id': session?.userId};
  }

  static Future<String?> getToken() async => (await readSession())?.token;
  static Future<void> saveToken(String token) async {
    final session = await readSession();
    if (session == null) throw StateError('Use saveSession with the user ID');
    await saveSession(access: token, id: session.userId);
  }

  static Future<bool> invalidateToken(String token) =>
      _sessions.invalidateToken(token);
  static Future<void> clear() => _sessions.clear();
  static Future<void> clearSession() => clear();
  static Future<void> clearToken() => clear();
}
