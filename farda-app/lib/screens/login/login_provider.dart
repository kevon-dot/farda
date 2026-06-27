import 'package:farda/application/authentication/repo/authentication_repo.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:flutter/material.dart';

class LoginProvider extends ChangeNotifier {
  final AuthenticationRepo _authRepo = AuthenticationRepo();

  String access = "";
  String refresh = "";
  String id = "";
  String name = "";

  /// Extracts the authenticated user's display name from a better-auth verify
  /// response body. Returns an empty string when no usable name is present.
  /// Kept as a pure function so it can be unit-tested without plugins.
  static String displayNameFromResponse(Map<String, dynamic>? response) {
    final user = response?["user"];
    if (user is Map) {
      final name = user["name"];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    }
    return "";
  }

  /// Extracts the authenticated user's id from a better-auth verify response
  /// body. better-auth nests the user under `user`. Returns an empty string
  /// when absent. Pure so it can be unit-tested without plugins.
  static String userIdFromResponse(Map<String, dynamic>? response) {
    final user = response?["user"];
    if (user is Map && user["id"] != null) {
      return user["id"].toString();
    }
    return "";
  }

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

  // Verify OTP and store tokens.
  //
  // better-auth (bearer mode) returns the session/user in the response body and
  // the bearer token in the `set-auth-token` response header, captured by the
  // repo into [VerifyResult.token]. We persist that token as the access token
  // AND as the rotatable session token (`refresh`): in better-auth bearer mode
  // the same session token is what `get-session` rotates (issue #19), so there
  // is no separate refresh credential to store.
  Future<bool> verifyOtpApi(String otp) async {
    _setLoading(true);

    final fullPhoneNumber = "$countryCode$phoneNumber";

    try {
      final result = await _authRepo.verifyOtp(fullPhoneNumber, otp);

      final token = result?.token;
      if (token != null && token.isNotEmpty) {
        access = token;
        refresh = token;
        id = userIdFromResponse(result?.body);
        name = displayNameFromResponse(result?.body);

        await AuthStorage.saveSession(
          access: access,
          refresh: refresh,
          id: id,
          name: name,
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
    name = session['name'] ?? '';
    notifyListeners();
  }

  // Optional: Clear data
  Future<void> clearPrefs() async {
    await AuthStorage.clearSession();
    await AuthStorage.clearToken();
    access = "";
    refresh = "";
    id = "";
    name = "";
    notifyListeners();
  }

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }
}
