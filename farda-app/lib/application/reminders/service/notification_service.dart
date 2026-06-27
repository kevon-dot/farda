import 'dart:async';

import 'package:farda/application/reminders/model/reminder_model.dart';
import 'package:farda/application/reminders/repo/reminder_repo.dart';
import 'package:farda/application/reminders/service/reminder_scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules + delivers local notifications for the reminder engine (GTM-537).
///
/// This is the ONLY file that touches `flutter_local_notifications` /
/// `timezone`. All decisions (which reminders to schedule, quiet-hours
/// suppression, snooze time, event payloads) are delegated to the pure
/// [ReminderScheduler] so they stay unit-testable. The plugin glue here is thin.
///
/// Lifecycle:
///   * [init] once at app start (sets up timezone db + the plugin + tap handler).
///   * [syncSchedule] after auth (#43) and on every schedule change: cancels the
///     previously-scheduled reminders and (re)schedules the next N upcoming ones
///     from the backend, skipping quiet hours.
///   * notification actions (snooze / dismiss) log a response event and, for
///     snooze, reschedule the reminder.
class NotificationService {
  NotificationService({ReminderRepo? repo})
      : _repo = repo ?? ReminderRepo();

  /// App-wide singleton. The notification engine is inherently a single
  /// per-process scheduler (one OS notification namespace), so a singleton keeps
  /// `_deliveredAt` + init state consistent across screens without threading the
  /// instance through every widget.
  static final NotificationService instance = NotificationService();

  final ReminderRepo _repo;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'farda_dose_reminders';
  static const String _channelName = 'Dose reminders';
  static const String _channelDescription =
      'Reminders to take your medication on schedule.';

  static const String snoozeActionId = 'SNOOZE';
  static const String dismissActionId = 'DISMISS';

  /// Tracks the delivery time per dose so we can compute time-to-action when the
  /// user responds. In-memory only (best-effort metric); a missing entry just
  /// omits the latency.
  final Map<String, DateTime> _deliveredAt = {};

  bool _initialized = false;

  /// Initialise the timezone database + the plugin. Idempotent.
  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
    );
    _initialized = true;
  }

  /// Pulls the latest schedule from the backend and (re)schedules the next N
  /// upcoming reminders, suppressing quiet hours. Cancels everything first so
  /// the on-device set always matches the server (survives reinstall + schedule
  /// changes). Returns the number of reminders scheduled.
  Future<int> syncSchedule({DateTime? now}) async {
    await init();
    final token = await _repo.currentToken();
    if (token == null || token.isEmpty) return 0;

    final result = await _repo.fetchSchedule();
    if (result == null) return 0;

    final when = now ?? DateTime.now();
    final due = ReminderScheduler.nextReminders(
      result.reminders,
      now: when,
      preferences: result.prefs,
    );

    // Clear the previous set so we never accumulate stale/duplicate reminders.
    await _plugin.cancelAll();
    _deliveredAt.clear();

    for (final reminder in due) {
      await _scheduleOne(reminder);
    }
    return due.length;
  }

  /// Schedules a single local notification for [reminder] at its local time.
  Future<void> _scheduleOne(ReminderModel reminder) async {
    final body = reminder.medicineName != null
        ? 'Time to take ${reminder.medicineName}.'
        : 'Time to take your medication.';

    await _plugin.zonedSchedule(
      reminder.notificationId,
      'Medication reminder',
      body,
      tz.TZDateTime.from(reminder.scheduledFor, tz.local),
      _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: reminder.doseId,
    );
    _deliveredAt[reminder.doseId] = reminder.scheduledFor;

    // Log the (planned) delivery so the pipeline sees the reminder lifecycle.
    // Fire-and-forget: a logging hiccup must not block scheduling.
    unawaited(_repo.logEvent(
      eventType: ReminderEventType.delivered,
      doseId: reminder.doseId,
      scheduledFor: reminder.scheduledFor,
    ));
  }

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(snoozeActionId, 'Snooze'),
        AndroidNotificationAction(dismissActionId, 'Dismiss'),
      ],
    );
    const darwin = DarwinNotificationDetails(
      categoryIdentifier: _channelId,
    );
    return const NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
  }

  /// Handles a notification tap or action button. Logs the appropriate response
  /// event (with time-to-action), and for snooze reschedules the reminder.
  void _onResponse(NotificationResponse response) {
    final doseId = response.payload;
    final deliveredAt = doseId != null ? _deliveredAt[doseId] : null;
    final tta = deliveredAt != null
        ? DateTime.now().difference(deliveredAt)
        : null;

    switch (response.actionId) {
      case snoozeActionId:
        unawaited(_handleSnooze(doseId, deliveredAt, tta));
        break;
      case dismissActionId:
        unawaited(_repo.logEvent(
          eventType: ReminderEventType.dismissed,
          doseId: doseId,
          scheduledFor: deliveredAt,
          timeToAction: tta,
        ));
        break;
      default:
        // Body tap -> the user opened the reminder.
        unawaited(_repo.logEvent(
          eventType: ReminderEventType.opened,
          doseId: doseId,
          scheduledFor: deliveredAt,
          timeToAction: tta,
        ));
    }
  }

  Future<void> _handleSnooze(
    String? doseId,
    DateTime? scheduledFor,
    Duration? tta,
  ) async {
    const snoozeMinutes = ReminderScheduler.defaultSnoozeMinutes;
    await _repo.logEvent(
      eventType: ReminderEventType.snoozed,
      doseId: doseId,
      scheduledFor: scheduledFor,
      snoozeMinutes: snoozeMinutes,
      timeToAction: tta,
    );
    if (doseId == null) return;

    final fireAt = ReminderScheduler.snoozeUntil(DateTime.now());
    // Reuse the same notification id so the snoozed copy replaces the original.
    await _plugin.zonedSchedule(
      _idForDose(doseId),
      'Medication reminder',
      'Snoozed reminder — time to take your medication.',
      tz.TZDateTime.from(fireAt, tz.local),
      _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: doseId,
    );
    _deliveredAt[doseId] = fireAt;
  }

  int _idForDose(String doseId) =>
      ReminderModel(doseId: doseId, scheduledFor: DateTime.now())
          .notificationId;

  /// Cancels the local notification for a dose (e.g. after it is taken). Logs an
  /// ACTIONED event so the pipeline records the take.
  Future<void> markTaken(String doseId) async {
    await _plugin.cancel(_idForDose(doseId));
    final deliveredAt = _deliveredAt.remove(doseId);
    await _repo.logEvent(
      eventType: ReminderEventType.actioned,
      doseId: doseId,
      scheduledFor: deliveredAt,
      timeToAction:
          deliveredAt != null ? DateTime.now().difference(deliveredAt) : null,
    );
  }
}
