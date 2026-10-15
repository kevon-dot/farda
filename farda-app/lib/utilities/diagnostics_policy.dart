class DiagnosticsPolicy {
  static String safeEvent(Object? message) {
    final value = message is String ? message : '';
    const allowed = {
      'network_timeout',
      'network_unavailable',
      'network_request_failed',
      'invalid_api_json',
      'upload_timeout',
      'upload_unavailable',
      'upload_failed',
    };
    return allowed.contains(value) ? value : 'diagnostic_redacted';
  }
}
