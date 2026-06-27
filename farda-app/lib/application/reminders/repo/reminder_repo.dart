import 'package:farda/app_const/app_urls.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/application/reminders/model/reminder_model.dart';
import 'package:farda/application/reminders/service/reminder_scheduler.dart';
import 'package:farda/utilities/api_service.dart';
import 'package:flutter/foundation.dart';

/// Backend client for the reminder + notification engine (GTM-537).
///
/// Talks to the Main API (`appBaseUrl`) reminder routes through the shared
/// [ApiService] so the bearer token + refresh-on-401 behaviour is reused. The
/// pure parsing/payload logic is factored into static helpers so it can be
/// unit-tested without a network call (see `test/reminder_*`).
class ReminderRepo {
  /// Fetches the user's upcoming reminder schedule + delivery preferences.
  /// Returns null on failure so callers can keep the previously-scheduled set.
  Future<({List<ReminderModel> reminders, ReminderPreferences prefs})?>
      fetchSchedule({int limit = ReminderScheduler.maxScheduled}) async {
    try {
      final response = await ApiService.get(
        endpoint: AppUrls.reminderSchedule,
        queryParams: {'limit': '$limit'},
        auth: true,
      );
      if (response == null) return null;
      return parseSchedule(response);
    } catch (e) {
      debugPrint('fetchSchedule error: $e');
      return null;
    }
  }

  /// Parses the `/reminders/schedule` response body. Pure + static so it is
  /// testable without HTTP.
  static ({List<ReminderModel> reminders, ReminderPreferences prefs})
      parseSchedule(Map<String, dynamic> json) {
    final rawList = (json['reminders'] as List?) ?? const [];
    final reminders = rawList
        .whereType<Map<String, dynamic>>()
        .map(ReminderModel.fromJson)
        .toList();
    final prefs = json['preferences'] is Map<String, dynamic>
        ? ReminderPreferences.fromJson(
            json['preferences'] as Map<String, dynamic>)
        : const ReminderPreferences();
    return (reminders: reminders, prefs: prefs);
  }

  /// Logs a single reminder-response event. Fire-and-forget friendly: returns
  /// true on success, false otherwise, and never throws.
  Future<bool> logEvent({
    required ReminderEventType eventType,
    String? doseId,
    DateTime? scheduledFor,
    DateTime? occurredAt,
    int? snoozeMinutes,
    Duration? timeToAction,
    String channel = 'LOCAL',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final body = ReminderScheduler.buildEventPayload(
        eventType: eventType,
        doseId: doseId,
        scheduledFor: scheduledFor,
        occurredAt: occurredAt,
        snoozeMinutes: snoozeMinutes,
        timeToAction: timeToAction,
        channel: channel,
        metadata: metadata,
      );
      final response = await ApiService.post(
        endpoint: AppUrls.reminderEvents,
        body: body,
        auth: true,
      );
      return response != null;
    } catch (e) {
      debugPrint('logEvent error: $e');
      return false;
    }
  }

  /// Persists the user's delivery preferences (timezone + quiet hours). The
  /// backend route is a PUT (see ReminderRoutes.updatePreferences).
  Future<bool> updatePreferences(ReminderPreferences prefs) async {
    try {
      final response = await ApiService.put(
        endpoint: AppUrls.reminderPreferences,
        body: prefs.toJson(),
        auth: true,
      );
      return response != null;
    } catch (e) {
      debugPrint('updatePreferences error: $e');
      return false;
    }
  }

  /// SCAFFOLD: registers an FCM/APNs push token for this device. Only reached
  /// when push is enabled via the capability flag (see PushCapability). Sending
  /// push is NOT implemented (needs a Firebase project + APNs cert).
  Future<bool> registerPushToken({
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    try {
      final body = <String, dynamic>{
        'token': token,
        'platform': platform,
        if (deviceId != null) 'deviceId': deviceId,
      };
      final response = await ApiService.post(
        endpoint: AppUrls.reminderPushTokens,
        body: body,
        auth: true,
      );
      return response != null;
    } catch (e) {
      debugPrint('registerPushToken error: $e');
      return false;
    }
  }

  /// The bearer token, exposed so callers can short-circuit when signed out.
  Future<String?> currentToken() => AuthStorage.getToken();
}
