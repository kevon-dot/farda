import 'dart:convert';

import 'package:farda/utilities/secure_store.dart';

class StoredSession {
  const StoredSession({required this.token, required this.userId});
  final String token;
  final String userId;
}

/// One secure record prevents pairing a token with another user's ID.
/// Authentication validity still comes from the server, not local presence.
class SessionStore {
  SessionStore(this.store, {required this.purgeLegacyPreferences, this.onSessionChanged});
  static const sessionKey = 'farda.session.v1';
  static const revokedKey = 'farda.session.revoked';
  static const privatePrefix = 'farda.private.';
  final SecureStore store;
  final Future<void> Function() purgeLegacyPreferences;
  final void Function()? onSessionChanged;
  Future<void> _tail = Future.value();
  bool _blocked = false;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<StoredSession?> read() => _serial(() async {
    if (_blocked || await store.read(revokedKey) != null) return null;
    // Exposed legacy plaintext credentials require reauthentication.
    await purgeLegacyPreferences();
    final raw = await store.read(sessionKey);
    if (_blocked || raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['version'] != 1 ||
          data['token'] is! String ||
          data['userId'] is! String ||
          (data['token'] as String).isEmpty ||
          (data['userId'] as String).isEmpty) {
        throw const FormatException('Invalid session');
      }
      return StoredSession(token: data['token'], userId: data['userId']);
    } on FormatException {
      await _clear();
      return null;
    }
  });

  Future<void> save(StoredSession session) => _serial(() async {
    if (session.token.trim().isEmpty || session.userId.trim().isEmpty) {
      throw ArgumentError('A complete session is required');
    }
    _blocked = true;
    onSessionChanged?.call();
    final existing = await _readStored();
    // Preserve this account's pending uploads on token renewal. A different
    // account must never inherit its private data.
    if (existing?.userId != session.userId) {
      await _clear();
    } else {
      await store.delete(sessionKey);
      await purgeLegacyPreferences();
    }
    await store.write(
      sessionKey,
      jsonEncode({
        'version': 1,
        'token': session.token,
        'userId': session.userId,
      }),
    );
    await store.delete(revokedKey);
    _blocked = false;
    onSessionChanged?.call();
  });

  Future<StoredSession?> _readStored() async {
    if (await store.read(revokedKey) != null) return null;
    final raw = await store.read(sessionKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is Map &&
          data['version'] == 1 &&
          data['token'] is String &&
          data['userId'] is String &&
          (data['token'] as String).isNotEmpty &&
          (data['userId'] as String).isNotEmpty) {
        return StoredSession(token: data['token'], userId: data['userId']);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Serialize private storage changes with logout/account switching. Never
  /// call another SessionStore method from within this callback.
  Future<T> forUser<T>(
    String userId,
    Future<T> Function(SecureStore store) action,
  ) => _serial(() async {
    final session = _blocked ? null : await _readStored();
    if (_blocked || session?.userId != userId) {
      throw StateError('Active account changed');
    }
    return action(store);
  });

  Future<bool> invalidateToken(String token) => _serial(() async {
    final session = await _readStored();
    if (session?.token != token) return false;
    _blocked = true;
    await _clear();
    return true;
  });

  Future<void> clear() {
    // Prevent new authorization synchronously, even if storage is slow.
    _blocked = true;
    onSessionChanged?.call();
    return _serial(_clear);
  }

  Future<void> _clear() async {
    _blocked = true;
    onSessionChanged?.call();
    // A persistent tombstone prevents reusing a token after partial cleanup.
    // Storage failure is surfaced; callers must not claim logout succeeded.
    await store.write(revokedKey, '1');
    await store.delete(sessionKey);
    await store.delete('token');
    final all = await store.readAll();
    for (final key in all.keys.where((key) => key.startsWith(privatePrefix))) {
      await store.delete(key);
    }
    await purgeLegacyPreferences();
  }
}
