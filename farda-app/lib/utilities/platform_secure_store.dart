import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'secure_store.dart';

class PlatformSecureStore implements SecureStore {
  const PlatformSecureStore();
  // Never erase the only queued observation to recover from a key error.
  // Device-only keychain items do not migrate into another phone's session.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}
