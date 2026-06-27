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

/// Base URL for the Vial API (smart-vial-backend).
///
/// Issue #14/#30 (app-calls-both): the app now talks to the Vial API DIRECTLY
/// for device/event/caregiver data — the Main API's proxy for these was removed
/// (PR #83). The value comes from the loaded .env.<environment> file
/// (VIAL_API_URL). Like [appBaseUrl] this MUST be https:// in staging/prod
/// (issue #20); the hard-coded fallback is an intentionally https:// safety net.
///
/// Unlike the Main API base, the Vial base has NO trailing `/api` segment: the
/// Vial route prefixes (`/api/user`, `/api/caregiver`, `/api/ingest`) are part
/// of the endpoint paths themselves (see [AppUrls]).
String get vialBaseUrl =>
    dotenv.env['VIAL_API_URL'] ?? "https://localhost:5000";
