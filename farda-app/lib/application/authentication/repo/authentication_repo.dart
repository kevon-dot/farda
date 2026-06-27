import 'dart:convert';

import 'package:farda/application/authentication/auth_token_helpers.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// Result of a successful better-auth verify call: the parsed JSON body plus
/// the bearer token extracted from the `set-auth-token` response header.
class VerifyResult {
  const VerifyResult({required this.body, required this.token});

  final Map<String, dynamic>? body;
  final String? token;
}

class AuthenticationRepo {
  /// Send OTP via better-auth's phoneNumber plugin.
  /// POST /api/auth/phone-number/send-otp  { phoneNumber }
  Future<Map<String, dynamic>?> sendOtp(String phoneNumber) async {
    try {
      final response = await ApiService.post(
        endpoint: AuthTokenHelpers.sendOtpEndpoint,
        body: AuthTokenHelpers.sendOtpBody(phoneNumber),
      );
      return response;
    } catch (e) {
      debugPrint("sendOtp error: $e");
      return null;
    }
  }

  /// Verify OTP via better-auth's phoneNumber plugin.
  /// POST /api/auth/phone-number/verify  { phoneNumber, code }
  ///
  /// On success better-auth (bearer mode) returns the session/user in the body
  /// and the bearer token in the `set-auth-token` response header. We capture
  /// the raw [http.Response] so the header is available, then hand back both.
  Future<VerifyResult?> verifyOtp(String phoneNumber, String otp) async {
    try {
      final http.Response? response = await ApiService.postResponse(
        endpoint: AuthTokenHelpers.verifyEndpoint,
        body: AuthTokenHelpers.verifyBody(phoneNumber, otp),
      );

      if (response == null) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final token = AuthTokenHelpers.extractToken(response.headers);
      Map<String, dynamic>? body;
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      }
      return VerifyResult(body: body, token: token);
    } catch (e) {
      debugPrint("verifyOtp error: $e");
      return null;
    }
  }
}
