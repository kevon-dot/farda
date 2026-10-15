/// Storage boundary for sessions and the device outbox. Production values use
/// the platform's protected secure storage, never shared preferences.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}
