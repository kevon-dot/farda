import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Base URL for the Main API.
///
/// Issue #20: this MUST be served over HTTPS. The value normally comes from the
/// loaded .env.<environment> file (BASE_API_URL). The hard-coded fallback below
/// is only a safety net for a misconfigured build and is intentionally https://
/// so we never silently fall back to cleartext. Set BASE_API_URL in the env
/// file for the target environment (see .env.example).
String get appBaseUrl =>
    dotenv.env['BASE_API_URL'] ?? "https://localhost:8000/api";
