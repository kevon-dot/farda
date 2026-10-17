import 'package:farda/application/authentication/repo/authentication_repo.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:flutter/material.dart';

class LoginProvider extends ChangeNotifier {
  LoginProvider({AuthenticationRepo? authRepo, SessionStore? sessions})
    : _authRepo = authRepo ?? AuthenticationRepo(),
      _sessions = sessions ?? AuthStorage.sessionStore;

  final AuthenticationRepo _authRepo;
  final SessionStore _sessions;

  String access = "";
  String refresh = "";
  String id = "";

  String countryCode = "+1";
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
      if (response != null &&
          (response["success"] == true ||
              response["status"] == true ||
              response["message"] != null)) {
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

      final token = response?['token'];
      final user = response?['user'];
      if (token is String &&
          token.isNotEmpty &&
          user is Map &&
          user['id'] is String &&
          (user['id'] as String).isNotEmpty) {
        final nextUserId = user['id'] as String;
        final previous = await _sessions.read();
        if (previous != null && previous.userId != nextUserId) {
          final revoked = await _authRepo.signOutCurrentSession();
          // A 401 clears the expired local session. Other failures retain it,
          // preventing an account switch that strands its server registration.
          if (!revoked && await _sessions.read() != null) return false;
        }
        await _sessions.save(StoredSession(token: token, userId: nextUserId));
        access = token;
        id = nextUserId;
        refresh = '';
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
    final session = await _sessions.read();
    access = session?.token ?? '';
    refresh = '';
    id = session?.userId ?? '';
    notifyListeners();
  }

  // Optional: Clear data
  Future<void> clearPrefs() async {
    await _sessions.clear();
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
