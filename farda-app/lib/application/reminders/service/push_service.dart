import 'dart:io' show Platform;

import 'package:farda/application/reminders/repo/reminder_repo.dart';
import 'package:farda/application/reminders/service/push_capability.dart';
import 'package:flutter/foundation.dart';

/// SCAFFOLD: FCM/APNs push registration (GTM-537).
///
/// Deliberately does NOT import `firebase_messaging` so the app builds + runs
/// without a Firebase project or platform config (see [PushCapability]). When
/// push is enabled, [retrieveToken] is the single place to wire up
/// `FirebaseMessaging.instance.getToken()` and the maintainer can flip the flag.
///
/// What IS implemented here today: the backend registration call. Given a token
/// (from a future Firebase integration), [registerIfEnabled] POSTs it to
/// `/api/reminders/push-tokens` keyed to the session user — that endpoint is
/// live. SENDING push from the backend is the separately-flagged part.
class PushService {
  PushService({ReminderRepo? repo}) : _repo = repo ?? ReminderRepo();

  final ReminderRepo _repo;

  /// The push platform for this device: "fcm" on Android, "apns" on iOS/macOS.
  static String get platform {
    if (Platform.isIOS || Platform.isMacOS) return 'apns';
    return 'fcm';
  }

  /// Retrieves the device push token, or null when push is disabled / no
  /// Firebase integration is present.
  ///
  /// SCAFFOLD: returns null until `firebase_messaging` is wired up. Replace the
  /// body with `FirebaseMessaging.instance.getToken()` (FCM) once the Firebase
  /// project + platform config exist and the dependency is added.
  Future<String?> retrieveToken() async {
    if (!PushCapability.enabled) return null;
    // TODO(GTM-537 / maintainer): integrate firebase_messaging:
    //   final token = await FirebaseMessaging.instance.getToken();
    //   return token;
    debugPrint(
      'PushService: ENABLE_PUSH is set but firebase_messaging is not wired up '
      'yet (no token retrieved). See push_capability.dart for setup steps.',
    );
    return null;
  }

  /// Registers this device's push token with the backend when push is enabled
  /// and a token is available. NO-OP (returns false) otherwise, so it is safe to
  /// call unconditionally after auth (#43).
  Future<bool> registerIfEnabled({String? deviceId}) async {
    if (!PushCapability.enabled) return false;
    final token = await retrieveToken();
    if (token == null || token.isEmpty) return false;
    return _repo.registerPushToken(
      token: token,
      platform: platform,
      deviceId: deviceId,
    );
  }
}
