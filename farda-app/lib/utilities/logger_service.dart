import 'package:logger/logger.dart';

/// PHI/credential-safe redaction helpers for log output.
///
/// This app handles protected health information (PHI) and bearer tokens.
/// Logs must never contain either. Use [LogRedactor.redact] to scrub any
/// string before it is passed to [Log]. Kept as pure functions with no plugin
/// dependencies so they are unit-testable under `flutter test`.
class LogRedactor {
  LogRedactor._();

  static const String mask = '[REDACTED]';

  // Matches an Authorization bearer header value, e.g. `Bearer abc.def.ghi`.
  static final RegExp _bearer = RegExp(
    r'Bearer\s+[A-Za-z0-9\-_\.=]+',
    caseSensitive: false,
  );

  // Matches an "Authorization": "..." map/JSON entry and the token after it.
  static final RegExp _authHeader = RegExp(
    r'("?[Aa]uthorization"?\s*[:=]\s*)("?)([^",}\n]+)',
  );

  /// Returns [input] with bearer tokens and Authorization header values masked.
  static String redact(String input) {
    return input
        .replaceAll(_bearer, 'Bearer $mask')
        .replaceAllMapped(_authHeader, (m) => '${m[1]}${m[2]}$mask');
  }

  /// Replaces a headers map's Authorization entry with a mask, preserving the
  /// other (non-sensitive) keys. Safe to log.
  static Map<String, String> redactHeaders(Map<String, String> headers) {
    return headers.map((key, value) {
      if (key.toLowerCase() == 'authorization') {
        return MapEntry(key, mask);
      }
      return MapEntry(key, value);
    });
  }
}

class Log {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0, // Number of method calls to be displayed
      errorMethodCount: 5, // Number of method calls if stacktrace is provided
      lineLength: 80, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      dateTimeFormat: DateTimeFormat.none, // Should each log print contain a timestamp
    ),
  );

  // Defense-in-depth: scrub bearer tokens / Authorization values from any
  // string message before it reaches the underlying logger. Callers should
  // still avoid passing PHI, but this guarantees credentials never leak.
  static dynamic _safe(dynamic message) =>
      message is String ? LogRedactor.redact(message) : message;

  static void v(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.t(_safe(message), error: error, stackTrace: stackTrace);
  }

  static void d(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(_safe(message), error: error, stackTrace: stackTrace);
  }

  static void i(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(_safe(message), error: error, stackTrace: stackTrace);
  }

  static void w(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(_safe(message), error: error, stackTrace: stackTrace);
  }

  static void e(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(_safe(message), error: error, stackTrace: stackTrace);
  }
}
