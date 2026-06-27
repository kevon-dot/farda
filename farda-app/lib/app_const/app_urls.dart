class AppUrls {
  // --- Main API (BASE_API_URL) ----------------------------------------------
  static String getDoseTime = "dosetime/";
  static String getExtractPrescriptionOcr = "prescriptions/ocr/extract";
  static String getPrescription = "my-prescriptions/";
  static String submitPrescription = "prescriptions/ocr/save";
  static String getMode = "mood/";
  static String setMood = "mood/";
  static String setNotes = "dose-notes/";

  // --- Reminder + notification engine (GTM-537) -----------------------------
  /// GET the user's upcoming reminder schedule + delivery preferences.
  static const String reminderSchedule = "reminders/schedule";

  /// POST a single reminder-response event (delivered/opened/snoozed/...).
  static const String reminderEvents = "reminders/events";

  /// PUT the user's delivery preferences (timezone + quiet hours).
  static const String reminderPreferences = "reminders/preferences";

  /// POST register an FCM/APNs push token for this device (SCAFFOLD).
  static const String reminderPushTokens = "reminders/push-tokens";

  // --- Refill prediction + pharmacy-readiness (GTM-541) ---------------------
  /// GET per-prescription remaining / days-left / refill-due predictions.
  static const String refills = "refills";

  /// POST a single refill lifecycle event (requested/completed/delayed).
  static const String refillEvents = "refills/events";

  /// GET refill-adherence metrics for the session user.
  static const String refillMetrics = "refills/metrics";
}

/// Vial API (VIAL_API_URL) endpoint paths — issue #14/#30 (app-calls-both).
///
/// The app now calls the Vial backend (smart-vial-backend) DIRECTLY for
/// device/event/caregiver data, because the Main API's proxy for these paths was
/// removed in PR #83. These paths are passed to [ApiService] with
/// `baseUrl: vialBaseUrl` and `auth: true` so the shared better-auth bearer is
/// attached and refresh-on-401 still applies.
///
/// Paths mirror the Vial Express routers exactly:
///   * `/api/user/*`      -> routes/userAPI.js      (Server.js: app.use('/api/user', ...))
///   * `/api/caregiver/*` -> routes/caregiverAPI.js (app.use('/api/caregiver', ...))
///   * `/api/ingest/*`    -> routes/ingestionAPI.js (app.use('/api/ingest', ...))
class VialUrls {
  // --- User / device (routes/userAPI.js) ------------------------------------

  /// POST — upsert the authenticated user in the Vial DB (`/save`).
  static const String saveUser = "api/user/save";

  /// POST `{ device_id }` — claim a provisioned device for the current user.
  static const String claimDevice = "api/user/claim";

  /// GET — all devices owned by the current user.
  static const String userDevices = "api/user/devices";

  /// GET — events across all of the user's devices.
  static const String allDevicesEvents = "api/user/events/all";

  /// GET — most recent events for a single device.
  static String deviceEvents(String deviceId) =>
      "api/user/devices/${Uri.encodeComponent(deviceId)}/events";

  /// GET `?start_time=&end_time=` — device events within a time range.
  static String deviceEventsSearch(String deviceId) =>
      "api/user/devices/${Uri.encodeComponent(deviceId)}/events/search";

  /// DELETE — unclaim (fully detach) a device owned by the current user.
  static String unclaimDevice(String deviceId) =>
      "api/user/devices/${Uri.encodeComponent(deviceId)}/unclaim";

  /// DELETE — all events for a device.
  static String deleteDeviceEvents(String deviceId) =>
      "api/user/devices/${Uri.encodeComponent(deviceId)}/events";

  /// DELETE — remove caregiver access to a device (owner only).
  static String deleteCaregiverAccess(String deviceId) =>
      "api/user/devices/${Uri.encodeComponent(deviceId)}/caregiver";

  // --- Caregiver (routes/caregiverAPI.js) -----------------------------------

  /// POST `{ device_id, caregiver_id }` — owner assigns a caregiver to a device.
  static const String caregiverClaimDevice = "api/caregiver/claim-device";

  /// GET `?status=&role=` — the session user's caregiver grants (GTM-517),
  /// server-authoritative + PHI-free. Returns `as_caregiver` (my invites inbox /
  /// patients I look after) and `as_owner` (relationships I created).
  static const String caregiverGrants = "api/caregiver/grants";

  /// POST — the invited caregiver ACCEPTS a pending grant (`pending → accepted`).
  static String caregiverAcceptGrant(String grantId) =>
      "api/caregiver/grants/${Uri.encodeComponent(grantId)}/accept";

  /// POST — owner OR caregiver REVOKES a grant (`* → revoked`). The caregiver
  /// uses this to DECLINE a pending invite; the owner uses it to cut access.
  static String caregiverRevokeGrant(String grantId) =>
      "api/caregiver/grants/${Uri.encodeComponent(grantId)}/revoke";

  /// GET — all devices assigned to the current caregiver.
  static const String caregiverDevices = "api/caregiver/devices";

  /// GET — summary of a single device the caregiver has access to.
  static String caregiverDeviceSummary(String deviceId) =>
      "api/caregiver/devices/${Uri.encodeComponent(deviceId)}/summary";

  /// GET `?device_id=` — look up a device by id (caregiver scope).
  static const String caregiverSearchDevice = "api/caregiver/search/device";

  /// GET `?device_id=&start_time=&end_time=` — caregiver event filter by date.
  static const String caregiverEventsByDate = "api/caregiver/events/filter/date";

  // --- Ingestion (GTM-514: app-relayed vial dose-log sync) -------------------

  /// POST `{ device_id, event, event_id, timestamp, payload }` — relay ONE dose
  /// event the app read off a vial over BLE.
  ///
  /// NOTE (scope/hardware flag): the existing `/api/ingest/event` route
  /// (routes/ingestionAPI.js) is signed with per-DEVICE HMAC (A3,
  /// middleware/authDevice.js) and is meant to be called by the firmware itself
  /// — the APP does not hold the device's HMAC secret, so it cannot post there.
  /// This user-bearer relay path lets the app forward buffered events the device
  /// couldn't send while offline; the backend authenticates it with the shared
  /// better-auth session (verifyUserToken) + the device-claim check, and dedupes
  /// on `event_id` exactly like the device path. Adding the matching
  /// `POST /api/user/devices/:device_id/events/ingest` route + controller is a
  /// SEPARATE backend task (out of farda-app/ scope); until it lands, uploads
  /// fail transiently and stay safely buffered in [DoseSyncQueue].
  static String ingestDeviceEvent(String deviceId) =>
      "api/user/devices/${Uri.encodeComponent(deviceId)}/events/ingest";
}
