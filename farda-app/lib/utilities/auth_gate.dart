/// Pure helper that decides whether authenticated data fetches are allowed.
///
/// The Calendar / Prescription providers hit authenticated endpoints
/// (`dosetime/`, `mood/`, `my-prescriptions/`). Before login the stored bearer
/// token is empty, so firing those calls at startup means hitting protected
/// endpoints with an empty `Authorization` header. This helper centralises the
/// "do we have a usable token yet?" check so the eager fetches can be gated
/// behind authentication.
///
/// Kept free of Flutter / plugin imports so it can be unit-tested as plain Dart.
class AuthGate {
  const AuthGate._();

  /// Returns `true` only when [token] looks like a real, non-empty bearer
  /// token. A `null`, empty, or whitespace-only token means the user is not
  /// authenticated yet and authenticated fetches should be skipped.
  static bool hasValidToken(String? token) {
    if (token == null) return false;
    return token.trim().isNotEmpty;
  }

  /// Whether authenticated data fetches (dose times, mood, prescriptions)
  /// should run for the given [token]. Alias of [hasValidToken] expressed at
  /// the call site's intent.
  static bool shouldFetchAuthedData(String? token) => hasValidToken(token);
}
