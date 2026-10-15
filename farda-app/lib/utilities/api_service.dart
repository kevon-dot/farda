import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/env.dart';
import 'package:http/http.dart' as http;

import 'logger_service.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.kind, {this.statusCode});
  final String kind;
  final int? statusCode;
  @override
  String toString() => 'ApiFailure($kind)';
}

/// Secure compatibility client. UI callers decide navigation/recovery; this
/// boundary awaits invalidation and never logs tokens, URLs or health payloads.
class ApiService {
  static const timeout = Duration(seconds: 20);
  static Future<void> Function()? onSessionExpired;

  static Future<Map<String, String>> _buildHeaders({
    Map<String, String>? customHeaders,
    bool auth = false,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    // An explicit old Authorization header requests authentication, but cannot
    // inject a stale plaintext token or override the secure active session.
    final explicitAuth =
        customHeaders?.keys.any(
          (key) => key.toLowerCase() == 'authorization',
        ) ??
        false;
    customHeaders?.forEach((key, value) {
      if (key.toLowerCase() != 'authorization') headers[key] = value;
    });
    if (auth || explicitAuth) {
      final token = await AuthStorage.getToken();
      if (token == null || token.isEmpty) {
        throw const ApiFailure('session_required');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<http.Response?> _request({
    required String method,
    required String endpoint,
    dynamic body,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    bool auth = false,
  }) async {
    try {
      final uri = apiUri(appBaseUrl, endpoint, query: queryParams);
      final request = http.Request(method, uri);
      request.headers.addAll(
        await _buildHeaders(customHeaders: headers, auth: auth),
      );
      if (body != null) request.body = jsonEncode(body);
      // Avoid forwarding bearer credentials through redirects to another host.
      request.followRedirects = false;
      final client = http.Client();
      try {
        final response = await client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(timeout);
        await _recordResponse(
          method,
          response,
          request.headers['Authorization'],
        );
        return response;
      } finally {
        client.close();
      }
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      Log.w('network_timeout');
      return null;
    } on SocketException {
      Log.w('network_unavailable');
      return null;
    } on http.ClientException {
      Log.w('network_request_failed');
      return null;
    }
  }

  static Map<String, dynamic>? _object(http.Response? response) {
    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      return null;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      Log.w('invalid_api_json');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> post({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = false,
  }) async => _object(
    await postResponse(
      endpoint: endpoint,
      body: body,
      headers: headers,
      auth: auth,
    ),
  );

  static Future<http.Response?> postResponse({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = false,
  }) => _request(
    method: 'POST',
    endpoint: endpoint,
    body: body,
    headers: headers,
    auth: auth,
  );

  static Future<http.Response?> patchResponse({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = true,
  }) => _request(
    method: 'PATCH',
    endpoint: endpoint,
    body: body,
    headers: headers,
    auth: auth,
  );

  static Future<Map<String, dynamic>?> get({
    required String endpoint,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    bool auth = false,
  }) async => _object(
    await _request(
      method: 'GET',
      endpoint: endpoint,
      headers: headers,
      queryParams: queryParams,
      auth: auth,
    ),
  );

  static Future<http.Response?> getList({
    required String endpoint,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    bool auth = true,
  }) => _request(
    method: 'GET',
    endpoint: endpoint,
    headers: headers,
    queryParams: queryParams,
    auth: auth,
  );

  static Future<Map<String, dynamic>?> postMultipart({
    required String endpoint,
    required String fileFieldName,
    required List<File> files,
    Map<String, String>? headers,
    Map<String, String>? fields,
    bool auth = true,
  }) async {
    try {
      if (files.length != 1 || await files.single.length() > 8 * 1024 * 1024) {
        throw const ApiFailure('upload_size_invalid');
      }
      final request = http.MultipartRequest(
        'POST',
        apiUri(appBaseUrl, endpoint),
      );
      request.followRedirects = false;
      request.headers.addAll(
        await _buildHeaders(customHeaders: headers, auth: auth),
      );
      request.headers.removeWhere(
        (key, _) => key.toLowerCase() == 'content-type',
      );
      request.files.add(
        await http.MultipartFile.fromPath(fileFieldName, files.single.path),
      );
      if (fields != null) request.fields.addAll(fields);
      final client = http.Client();
      try {
        final response = await client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(timeout);
        await _recordResponse(
          'POST',
          response,
          request.headers['Authorization'],
        );
        return _object(response);
      } finally {
        client.close();
      }
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      Log.w('upload_timeout');
      return null;
    } on SocketException {
      Log.w('upload_unavailable');
      return null;
    } on http.ClientException {
      Log.w('upload_failed');
      return null;
    }
  }

  static Future<void> _recordResponse(
    String method,
    http.Response response,
    String? authorization,
  ) async {
    Log.network(method, response.statusCode);
    if (response.statusCode == 401) {
      if (authorization != null && authorization.startsWith('Bearer ')) {
        final invalidated = await AuthStorage.invalidateToken(
          authorization.substring(7),
        );
        if (invalidated) await onSessionExpired?.call();
      }
      throw const ApiFailure('session_expired', statusCode: 401);
    }
  }
}
