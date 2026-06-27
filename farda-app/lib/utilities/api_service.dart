import 'dart:convert';
import 'dart:io';
import 'package:farda/env.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/utilities/storage_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class ApiService {
  // Get headers with optional Bearer token
  static Future<Map<String, String>> _buildHeaders({Map<String, String>? customHeaders, bool auth = false}) async {
    final headers = <String, String>{
      "Content-Type": "application/json",
      ...?customHeaders,
    };

    if (auth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access');
      if (token != null && token.isNotEmpty) {
        headers["Authorization"] = "Bearer $token";
      }
    }

    return headers;
  }

  // POST request
  static Future<Map<String, dynamic>?> post({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = false,
  }) async {
    final uri = Uri.parse("$appBaseUrl/$endpoint");
    try {
      final finalHeaders = await _buildHeaders(customHeaders: headers, auth: auth);
      
      Log.i("➡️ POST Request: $uri\nHeaders: $finalHeaders\nBody: ${jsonEncode(body)}");

      final response = await http.post(
        uri,
        headers: finalHeaders,
        body: jsonEncode(body),
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

  // POST with get response
  static Future<http.Response?> postResponse({
    required String endpoint,
    required dynamic body,
    Map<String, String>? headers,
    bool auth = false,
  }) async {
    final uri = Uri.parse("$appBaseUrl/$endpoint");
    try {
      final finalHeaders = await _buildHeaders(customHeaders: headers, auth: auth);
      
      Log.i("➡️ POST Request: $uri\nHeaders: $finalHeaders\nBody: ${jsonEncode(body)}");

      final response = await http.post(
        uri,
        headers: finalHeaders,
        body: jsonEncode(body),
      );

      _logResponse("POST", uri.toString(), response);

      return response;
    } catch (e, stackTrace) {
      Log.e("❌ POST Request Error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // GET request
  static Future<Map<String, dynamic>?> get({
    required String endpoint,
    Map<String, String>? headers,
    Map<String, String>? queryParams,
    bool auth = false,
  }) async {
    final uri = Uri.parse("$appBaseUrl/$endpoint").replace(queryParameters: queryParams);
    try {
      final finalHeaders = await _buildHeaders(customHeaders: headers, auth: auth);
      
      Log.i("➡️ GET Request: $uri\nHeaders: $finalHeaders");

      final response = await http.get(
        uri,
        headers: finalHeaders,
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
  }) async {
    final uri = Uri.parse("$appBaseUrl/$endpoint").replace(queryParameters: queryParams);
    try {
      Log.i("➡️ GET Request: $uri\nHeaders: ${headers ?? {"Content-Type": "application/json"}}");

      final response = await http.get(
        uri,
        headers: headers ?? {"Content-Type": "application/json"},
      );

      _logResponse("GET", uri.toString(), response);
      return response;
    } catch (e, stackTrace) {
      Log.e("❌ GET Request Error: $uri", error: e, stackTrace: stackTrace);
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
          files[i].path
        ));
      }

      if (fields != null) {
        request.fields.addAll(fields);
      }

      Log.i("➡️ Multipart POST Request: $uri\nHeaders: ${request.headers}\nFields: $fields\nFiles count: ${files.length}");

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _logResponse("Multipart POST", uri.toString(), response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      } else {
        return null;
      }
    } catch (e, stackTrace) {
      Log.e("❌ Multipart POST request error: $uri", error: e, stackTrace: stackTrace);
      return null;
    }
  }

  static void _logResponse(String method, String url, http.Response response) {
    if (response.statusCode == 401) {
      Log.w("⚠️ 401 Unauthorized - Redirecting to login [$url]");
      StorageService.clearPrefs();
      StorageService.deleteSecureStorage();
      AppRouter.router.go(CustomRoutePaths.login);
    } else if (response.statusCode >= 200 && response.statusCode < 300) {
      Log.d("✅ $method Response [$url] | Status: ${response.statusCode}\nBody: ${response.body}");
    } else {
      Log.w("⚠️ $method Response Error [$url] | Status: ${response.statusCode}\nBody: ${response.body}");
    }
  }
}
