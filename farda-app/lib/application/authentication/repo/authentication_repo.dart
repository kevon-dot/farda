import 'package:farda/utilities/api_service.dart';

class AuthenticationRepo {
  Future<Map<String, dynamic>?> sendOtp(String phoneNumber) async {
    try {
      final response = await ApiService.post(
        endpoint: "auth/send-otp",
        body: {"phoneNumber": phoneNumber},
      );
      return response;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> verifyOtp(
    String phoneNumber,
    String otp,
  ) async {
    try {
      final response = await ApiService.post(
        endpoint: "auth/verify-otp",
        body: {"phoneNumber": phoneNumber, "code": otp},
      );
      return response;
    } catch (e) {
      return null;
    }
  }

  /// Revokes the still-current authenticated session before a different
  /// account replaces it in protected storage.
  Future<bool> signOutCurrentSession() async {
    try {
      final response = await ApiService.postResponse(
        endpoint: 'auth/sign-out',
        body: const <String, dynamic>{},
        auth: true,
      );
      return response?.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
