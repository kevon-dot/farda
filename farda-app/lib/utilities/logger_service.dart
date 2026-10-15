import 'diagnostics_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Diagnostics contain fixed event names and numeric status only. Dynamic
/// messages, exception strings, paths and payloads are deliberately suppressed.
class Log {
  static final Logger _logger = Logger(printer: SimplePrinter());
  static String safeEvent(Object? message) =>
      DiagnosticsPolicy.safeEvent(message);
  static void network(String method, int statusCode) {
    if (kReleaseMode) return;
    final allowed = {'GET', 'POST', 'PATCH', 'PUT', 'DELETE'};
    if (!allowed.contains(method)) return;
    _logger.d('http_${method.toLowerCase()} status=$statusCode');
  }

  static void v(dynamic message, {Object? error, StackTrace? stackTrace}) {
    if (!kReleaseMode) _logger.t(safeEvent(message));
  }

  static void d(dynamic message, {Object? error, StackTrace? stackTrace}) {
    if (!kReleaseMode) _logger.d(safeEvent(message));
  }

  static void i(dynamic message, {Object? error, StackTrace? stackTrace}) {
    if (!kReleaseMode) _logger.i(safeEvent(message));
  }

  static void w(dynamic message, {Object? error, StackTrace? stackTrace}) {
    if (!kReleaseMode) _logger.w(safeEvent(message));
  }

  static void e(dynamic message, {Object? error, StackTrace? stackTrace}) {
    if (!kReleaseMode) _logger.e(safeEvent(message));
  }
}
