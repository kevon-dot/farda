import 'dart:convert';
import 'dart:io';
import 'package:farda/application/authentication/auth_session_manager.dart';
import 'package:farda/application/authentication/auth_token_helpers.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/env.dart';
import 'package:http/http.dart' as http;
import 'logger_service.dart';

/// Single HTTP client for the Farda backends.
///
/// This is the ONE place that:
///   * attaches `Authorization: Bearer <token>` (issue: bearer-token sessions),
///   * captures a rotated token from the `set-auth-token` response header,
///   * on a `401` refreshes the better-auth session once and retries the
///     request, and logs out cleanly when the refresh fails (issue #19).
///
/// Both the Main API ([appBaseUrl]) and the Vial API ([vialBaseUrl]) validate
/// the SAME better-auth session, so every method takes an optional [baseUrl].
/// Pass [vialBaseUrl] for device/event/caregiver calls (issue #14/#30,
/// app-calls-both); leave it unset to target the Main API as before. Either way
/// the bearer + refresh-on-401 behaviour above is reused for free.
///
/// Call sites must not reimplement any of the above.
class ApiService {
  /// Joins a base URL and an endpoint with exactly one `/`, tolerating a
  /// trailing slash on [baseUrl] and/or a leading slash on [endpoint]. Extracted
  /// so URL composition is testable without performing a network call.
  static Uri buildUri(String baseUrl, String endpoint) {
    final trimmedBase =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final trimmedEndpoint =
        endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return Uri.parse("$trimmedBase/$trimmedEndpoint");
  }
  // Get headers with optional Bearer token (read from secure storage).
  static Future<Map<String, String>> _buildHeaders({
    Map<String, String>? customHeaders,
    bool auth = false,
  }) async {
    final headers = <String, String>{
      "Content-Type": "application/json",
      ...?customHeaders,
    };

    // Attach the bearer token unless a caller already supplied an explicit
    // Authorization header. We attach for authenticated calls; the
    // refresh-on-401 path always re-reads the (possibly rotated) token.
    final hasAuthHeader = headers.keys.any(
      (k) => k.toLowerCase() == 'authorization',
    );
    if (auth && !hasAuthHeader) {
      final token = await AuthStorage.getToken();
      if (token != null && token.isNotEmpty) {
        headers["Authorization"] = "Bearer $token";
      }
    }

    return headers;
  }

  /// Re-applies a freshly rotated bearer token onto a header map that
  /// previously carried an `Authorization` entry, so the retried request uses
  /// the new token.
  static Future<Map<String, String>> _reapplyToken(
    Map<String, String> headers,
  ) async {
    final updated = Map<String, String>.from(headers);
    final token = await AuthStorage.getToken();
    final authKey = updated.keys.firstWhere(
      (k) => k.toLowerCase() == 'authorization',
      orElse: () => 'Authorization',
    );
    if (token != null && token.isNotEmpty) {
      updated[authKey] = "Bearer $token";
    }
    return updated;
  }

  /// Whether the headers carry an Authorization bearer (i.e. an authenticated
  /// request worth refreshing on 401).
  static bool _isAuthed(Map<String, String> headers) {
    return headers.keys.any((k) => k.toLowerCase() == 'authorization');
  }

  /// Runs [send] (an HTTP call) and, on a `401` for an authenticated request,
  /// refreshes the better-auth session once and retries with the rotated
  /// token. Logs out cleanly when the refresh fails. Also persists any rotated
  /// token handed back in the `set-auth-token` response header.
  static Future<http.Response> _withRefresh(
    Map<String, String> headers,
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    http.Response response = await send(headers);
    _captureRotatedToken(response);

    if (AuthTokenHelpers.shouldRefreshOnStatus(response.statusCode) &&
        _isAuthed(headers)) {
      final refreshed = await AuthSessionManager.refreshSession();
      if (refreshed) {
        final retryHeaders = await _reapplyToken(headers);
        response = await send(retryHeaders);
        _captureRotatedToken(response);
        if (response.statusCode == 401) {
          // Still unauthorized after a successful refresh -> session is dead.
          await AuthSessionManager.logout();
        }
      } else {
        await AuthSessionManager.logout();
      }
    }

    return response;
  }

  /// Persists a rotated bearer token if better-auth sent one back.
  static void _captureRotatedToken(http.Response response) {
    final rotated = AuthTokenHelpers.extractToken(response.headers);
    if (rotated != null) {
      // Fire-and-forget: persisting the rotated token must not block the
      // response. Secure-storage writes are quick and idempotent.
      AuthStorage.saveToken(rotated);
    }
  }

  // POST request
  static Future<Map<String, dynamic>?> post({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = false,
    String? baseUrl,
  }) async {
    final uri = buildUri(baseUrl ?? appBaseUrl, endpoint);
    try {
      final finalHeaders =
          await _buildHeaders(customHeaders: headers, auth: auth);

      Log.i("➡️ POST Request: $uri");

      final response = await _withRefresh(
        finalHeaders,
        (h) => http.post(uri, headers: h, body: jsonEncode(body)),
      );

      _logResponse("POST", uri.toString(), response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e, stackTrace) {
      Log.e("❌ POST Request Error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // POST with raw response
  static Future<http.Response?> postResponse({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = false,
    String? baseUrl,
  }) async {
    final uri = buildUri(baseUrl ?? appBaseUrl, endpoint);
    try {
      final finalHeaders =
          await _buildHeaders(customHeaders: headers, auth: auth);

      Log.i("➡️ POST Request: $uri");

      final response = await _withRefresh(
        finalHeaders,
        (h) => http.post(uri, headers: h, body: jsonEncode(body)),
      );

      _logResponse("POST", uri.toString(), response);

      return response;
    } catch (e, stackTrace) {
      Log.e("❌ POST Request Error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // PUT request returning the decoded body (or null on non-2xx / error).
  // Reuses the shared bearer + refresh-on-401 path. Added for the reminder
  // preferences endpoint (GTM-537), which is a PUT on the Main API.
  static Future<Map<String, dynamic>?> put({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = false,
    String? baseUrl,
  }) async {
    final uri = buildUri(baseUrl ?? appBaseUrl, endpoint);
    try {
      final finalHeaders =
          await _buildHeaders(customHeaders: headers, auth: auth);

      Log.i("➡️ PUT Request: $uri");

      final response = await _withRefresh(
        finalHeaders,
        (h) => http.put(uri, headers: h, body: jsonEncode(body)),
      );

      _logResponse("PUT", uri.toString(), response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e, stackTrace) {
      Log.e("❌ PUT Request Error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // GET request
  static Future<Map<String, dynamic>?> get({
    required String endpoint,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    bool auth = false,
    String? baseUrl,
  }) async {
    final uri = buildUri(baseUrl ?? appBaseUrl, endpoint)
        .replace(queryParameters: queryParams);
    try {
      final finalHeaders =
          await _buildHeaders(customHeaders: headers, auth: auth);

      Log.i("➡️ GET Request: $uri");

      final response = await _withRefresh(
        finalHeaders,
        (h) => http.get(uri, headers: h),
      );

      _logResponse("GET", uri.toString(), response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e, stackTrace) {
      Log.e("❌ GET Request Error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  static Future<http.Response?> getList({
    required String endpoint,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    bool auth = false,
    String? baseUrl,
  }) async {
    final uri = buildUri(baseUrl ?? appBaseUrl, endpoint)
        .replace(queryParameters: queryParams);
    try {
      // When [auth] is set we attach the shared bearer via [_buildHeaders] so
      // Vial-direct callers don't have to read the token themselves. Existing
      // callers that pass an explicit Authorization header are unaffected.
      final finalHeaders = auth
          ? await _buildHeaders(customHeaders: headers, auth: true)
          : (headers ?? {"Content-Type": "application/json"});

      Log.i("➡️ GET Request: $uri");

      final response = await _withRefresh(
        finalHeaders,
        (h) => http.get(uri, headers: h),
      );

      _logResponse("GET", uri.toString(), response);
      return response;
    } catch (e, stackTrace) {
      Log.e("❌ GET Request Error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// DELETE request returning the raw response. Used by the Vial-direct
  /// device/caregiver endpoints (unclaim, delete events, revoke caregiver
  /// access) which are real HTTP DELETEs on the Vial backend. Reuses the same
  /// bearer + refresh-on-401 path as the other verbs.
  static Future<http.Response?> deleteResponse({
    required String endpoint,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    bool auth = false,
    String? baseUrl,
  }) async {
    final uri = buildUri(baseUrl ?? appBaseUrl, endpoint)
        .replace(queryParameters: queryParams);
    try {
      final finalHeaders =
          await _buildHeaders(customHeaders: headers, auth: auth);

      Log.i("➡️ DELETE Request: $uri");

      final response = await _withRefresh(
        finalHeaders,
        (h) => http.delete(uri, headers: h),
      );

      _logResponse("DELETE", uri.toString(), response);
      return response;
    } catch (e, stackTrace) {
      Log.e("❌ DELETE Request Error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  static Future<Map<String, dynamic>?> postMultipart({
    required String endpoint,
    required String fileFieldName,
    required List<File> files,
    Map<String, String>? headers,
    Map<String, String>? fields,
  }) async {
    final uri = Uri.parse("$appBaseUrl/$endpoint");
    try {
      var request = http.MultipartRequest("POST", uri);

      request.headers.addAll(headers ?? {"Content-Type": "multipart/form-data"});

      for (int i = 0; i < files.length; i++) {
        request.files.add(await http.MultipartFile.fromPath(
          fileFieldName,
          files[i].path,
        ));
      }

      if (fields != null) {
        request.fields.addAll(fields);
      }

      Log.i(
          "➡️ Multipart POST Request: $uri | Files count: ${files.length}");

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _captureRotatedToken(response);
      _logResponse("Multipart POST", uri.toString(), response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e, stackTrace) {
      Log.e("❌ Multipart POST request error: $uri",
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  static void _logResponse(
      String method, String url, http.Response response) {
    if (response.statusCode == 401) {
      // The refresh + logout policy lives in [_withRefresh] /
      // [AuthSessionManager]; here we only log. (A 401 reaching this point has
      // already been through a refresh attempt.)
      Log.w("⚠️ 401 Unauthorized [$url]");
    } else if (response.statusCode >= 200 && response.statusCode < 300) {
      Log.d(
          "✅ $method Response [$url] | Status: ${response.statusCode} | Bytes: ${response.bodyBytes.length}");
    } else {
      Log.w(
          "⚠️ $method Response Error [$url] | Status: ${response.statusCode} | Bytes: ${response.bodyBytes.length}");
    }
  }
}
