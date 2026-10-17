import 'package:farda/application/authentication/repo/authentication_repo.dart';
import 'package:farda/application/authentication/storage/session_store.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:farda/utilities/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecureStore implements SecureStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _AuthenticationRepo extends AuthenticationRepo {
  _AuthenticationRepo({required this.revoked});

  final bool revoked;
  var signOutCalls = 0;

  @override
  Future<Map<String, dynamic>?> verifyOtp(
    String phoneNumber,
    String otp,
  ) async => {
    'token': 'new-session',
    'user': {'id': 'new-user'},
  };

  @override
  Future<bool> signOutCurrentSession() async {
    signOutCalls++;
    return revoked;
  }
}

void main() {
  test('revokes the previous account before replacing its session', () async {
    final sessions = SessionStore(
      _MemorySecureStore(),
      purgeLegacyPreferences: () async {},
    );
    await sessions.save(
      const StoredSession(token: 'old-session', userId: 'old-user'),
    );
    final auth = _AuthenticationRepo(revoked: true);
    final provider =
        LoginProvider(authRepo: auth, sessions: sessions)
          ..countryCode = '+1'
          ..phoneNumber = '5555555555';

    expect(await provider.verifyOtpApi('123456'), isTrue);
    expect(auth.signOutCalls, 1);
    expect(await sessions.read(), isNotNull);
    expect((await sessions.read())?.userId, 'new-user');
  });

  test(
    'retains the prior account when server revocation cannot be confirmed',
    () async {
      final sessions = SessionStore(
        _MemorySecureStore(),
        purgeLegacyPreferences: () async {},
      );
      await sessions.save(
        const StoredSession(token: 'old-session', userId: 'old-user'),
      );
      final auth = _AuthenticationRepo(revoked: false);
      final provider =
          LoginProvider(authRepo: auth, sessions: sessions)
            ..countryCode = '+1'
            ..phoneNumber = '5555555555';

      expect(await provider.verifyOtpApi('123456'), isFalse);
      expect(auth.signOutCalls, 1);
      expect((await sessions.read())?.userId, 'old-user');
    },
  );
}
