import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/utilities/auth_gate.dart';
import 'package:flutter/foundation.dart';

/// Pure router-redirect target computation.
///
/// Kept free of Flutter / plugin imports so it can be unit-tested as plain
/// Dart. GoRouter's `redirect` must be synchronous-friendly, so it gates on a
/// cached [isAuthed] flag (see [AuthState]) rather than reading secure storage
/// on every navigation.
///
/// Rules:
/// - Unauthenticated users hitting a protected route are sent to `/login`.
/// - Authenticated users hitting `/login` (or the OTP step) are sent to
///   `/dashboard`.
/// - Otherwise no redirect (returns `null`).
String? redirectTarget({
  required bool isAuthed,
  required String location,
}) {
  final isUnauthedEntry = _unauthedRoutes.contains(location);

  if (!isAuthed) {
    // Allow the unauthenticated entry/auth screens through; everything else is
    // protected and bounces to login.
    return isUnauthedEntry ? null : _loginPath;
  }

  // Authenticated: keep users out of the login / OTP flow.
  if (location == _loginPath || location == _otpPath) {
    return _dashboardPath;
  }
  return null;
}

const String _loginPath = '/login';
const String _otpPath = '/otp-verify';
const String _dashboardPath = '/dashboard';

/// Routes reachable without a session. The onboarding splash decides where to
/// send first-launch vs. returning users itself, so it must stay reachable.
const Set<String> _unauthedRoutes = {
  '/',
  '/onboard',
  _loginPath,
  _otpPath,
};

/// Holds the cached "is the user authenticated?" flag that the router redirect
/// reads synchronously. Hydrated once at startup from secure storage and kept
/// in sync as the user logs in / out.
class AuthState extends ChangeNotifier {
  AuthState({bool isAuthed = false}) : _isAuthed = isAuthed;

  bool _isAuthed;
  bool get isAuthed => _isAuthed;

  /// Reads the stored bearer token and caches whether it is valid. Call once at
  /// startup (and the router will re-run redirects via [notifyListeners]).
  Future<void> hydrate() async {
    final token = await AuthStorage.getToken();
    setAuthed(AuthGate.hasValidToken(token));
  }

  /// Updates the cached flag and notifies the router to re-evaluate redirects.
  void setAuthed(bool value) {
    if (_isAuthed == value) return;
    _isAuthed = value;
    notifyListeners();
  }
}
