import 'package:farda/application/reminders/model/reminder_model.dart';

/// PURE Dart scheduling logic for the reminder + notification engine (GTM-537).
///
/// Deliberately free of Flutter / plugin imports so every decision (which
/// reminders to schedule next, whether a time falls in quiet hours, the snooze
/// time, and the response-event payload) is unit-testable without platform
/// channels. The plugin-touching glue lives in `notification_service.dart` and
/// delegates the decisions here.
class ReminderScheduler {
  /// How many local notifications we keep scheduled at once. iOS caps pending
  /// local notifications at 64; staying well under that leaves headroom for
  /// snoozes and other app notifications.
  static const int maxScheduled = 32;

  /// Returns the next [limit] reminders that are STRICTLY in the future relative
  /// to [now], sorted ascending by time. Past/elapsed doses are dropped (we do
  /// not fire stale reminders on app launch), and reminders inside quiet hours
  /// are suppressed when [preferences] defines a quiet-hours window.
  ///
  /// This is the single source of truth for "what should currently be
  /// scheduled", called on login (#43) and whenever the schedule changes.
  static List<ReminderModel> nextReminders(
    List<ReminderModel> reminders, {
    required DateTime now,
    ReminderPreferences? preferences,
    int limit = maxScheduled,
  }) {
    final upcoming = reminders
        .where((r) => r.scheduledFor.isAfter(now))
        .where((r) => !isInQuietHours(r.scheduledFor, preferences))
        .toList()
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

    if (upcoming.length <= limit) return upcoming;
    return upcoming.sublist(0, limit);
  }

  /// Whether [when]'s local time-of-day falls inside the user's quiet-hours
  /// window. Returns false when no window is configured (either bound null).
  ///
  /// Bounds are minutes-from-local-midnight in [0, 1440). A window may wrap past
  /// midnight: when start > end (e.g. 22:00 -> 07:00) the window is the UNION of
  /// [start, 1440) and [0, end). The start bound is inclusive and the end bound
  /// is exclusive so a reminder exactly at the wake time still fires.
  static bool isInQuietHours(
    DateTime when,
    ReminderPreferences? preferences,
  ) {
    final start = preferences?.quietHoursStart;
    final end = preferences?.quietHoursEnd;
    if (start == null || end == null) return false;
    if (start == end) return false; // zero-width window suppresses nothing

    final minutes = when.hour * 60 + when.minute;

    if (start < end) {
      // Same-day window, e.g. 01:00 -> 06:00.
      return minutes >= start && minutes < end;
    }
    // Wrapping window, e.g. 22:00 -> 07:00.
    return minutes >= start || minutes < end;
  }

  /// The time a snoozed reminder should re-fire: [from] plus [snoozeMinutes].
  /// Defaults to a 10-minute snooze. Clamps non-positive values to 1 minute so a
  /// snooze always moves the reminder into the future.
  static DateTime snoozeUntil(
    DateTime from, {
    int snoozeMinutes = defaultSnoozeMinutes,
  }) {
    final mins = snoozeMinutes > 0 ? snoozeMinutes : 1;
    return from.add(Duration(minutes: mins));
  }

  static const int defaultSnoozeMinutes = 10;

  /// Builds the JSON body for a reminder-response event POSTed to
  /// `/api/reminders/events`. PHI-free by construction (ids + types + timings
  /// only). [timeToAction] is the delivery->action latency for the analytics
  /// "time-to-action" metric. Omits null fields so the payload stays compact.
  static Map<String, dynamic> buildEventPayload({
    required ReminderEventType eventType,
    String? doseId,
    DateTime? scheduledFor,
    DateTime? occurredAt,
    int? snoozeMinutes,
    Duration? timeToAction,
    String channel = 'LOCAL',
    Map<String, dynamic>? metadata,
  }) {
    final body = <String, dynamic>{
      'eventType': eventType.wire,
      'channel': channel,
      'occurredAt': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    if (doseId != null) body['doseId'] = doseId;
    if (scheduledFor != null) {
      body['scheduledFor'] = scheduledFor.toUtc().toIso8601String();
    }
    if (snoozeMinutes != null) body['snoozeMinutes'] = snoozeMinutes;
    if (timeToAction != null) {
      body['timeToActionMs'] = timeToAction.inMilliseconds;
    }
    if (metadata != null && metadata.isNotEmpty) body['metadata'] = metadata;
    return body;
  }
}
