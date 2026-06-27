import 'package:farda/application/authentication/repo/authentication_repo.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:flutter/material.dart';

class LoginProvider extends ChangeNotifier {
  final AuthenticationRepo _authRepo = AuthenticationRepo();

  String access = "";
  String refresh = "";
  String id = "";

  String countryCode = "+880";
  String phoneNumber = "";
  bool isLoading = false;

  void updateCountryCode(String newCode) {
    countryCode = newCode;
    notifyListeners();
  }

  void updatePhoneNumber(String newNumber) {
    phoneNumber = newNumber;
    notifyListeners();
  }

  bool _isValidPhoneNumber() {
    // Regex matches 7 to 15 digits (standard international phone number lengths)
    final RegExp phoneRegex = RegExp(r'^[0-9]{7,15}$');
    return phoneRegex.hasMatch(phoneNumber);
  }

  // Send OTP
  Future<bool> sendOtpApi() async {
    if (!_isValidPhoneNumber()) {
       return false;
    }

    _setLoading(true);

    final fullPhoneNumber = "$countryCode$phoneNumber";

    try {
      final response = await _authRepo.sendOtp(fullPhoneNumber);

      // We just check if response is not null and preferably has a message
      if (response != null && response["message"] != null) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Verify OTP and store tokens
  Future<bool> verifyOtpApi(String otp) async {
    _setLoading(true);

    final fullPhoneNumber = "$countryCode$phoneNumber";

    try {
      final response = await _authRepo.verifyOtp(fullPhoneNumber, otp);

      if (response != null && response["status"] == true) {
        if (response["token"] != null) {
          access = response["token"].toString();
          await AuthStorage.saveToken(access);
        }
        
        if (response["user"] != null && response["user"]["id"] != null) {
          id = response["user"]["id"].toString();
        }

        await AuthStorage.saveSession(
          access: access,
          refresh: '', // No refresh token in this response
          id: id,
        );

        return true;
      }
      return false;
    } catch (e) {
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Load data from Storage (e.g., on app startup)
  Future<void> loadFromPrefs() async {
    final session = await AuthStorage.getSession();
    access = session['access'] ?? '';
    refresh = session['refresh'] ?? '';
    id = session['id'] ?? '';
    notifyListeners();
  }

  // Optional: Clear data
  Future<void> clearPrefs() async {
    await AuthStorage.clearSession();
    await AuthStorage.clearToken();
    access = "";
    refresh = "";
    id = "";
    notifyListeners();
  }

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }
}
