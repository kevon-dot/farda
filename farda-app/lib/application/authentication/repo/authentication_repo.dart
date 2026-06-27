import 'package:farda/utilities/api_service.dart';
import 'package:flutter/widgets.dart';

class AuthenticationRepo {
  Future<Map<String, dynamic>?> sendOtp(String phoneNumber) async {
    try {
      final response = await ApiService.post(
        endpoint: "auth/send-otp",
        body: {"phoneNumber": phoneNumber},
      );
      return response;
    } catch (e) {
      debugPrint("sendOtp error: $e");
      return null;
    }
  }


  Future<Map<String, dynamic>?> verifyOtp(String phoneNumber, String otp) async {
    try {
      final response = await ApiService.post(
        endpoint: "auth/verify-otp",
        body: {
          "phoneNumber": phoneNumber,
          "code" : otp
        },
      );
      return response;
    } catch (e) {
      debugPrint("verifyOtp error: $e");
      return null;
    }
  }
}
