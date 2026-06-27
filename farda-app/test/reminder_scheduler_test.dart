// Pure-Dart unit tests for the reminder + notification engine scheduling logic
// (GTM-537). These import only the pure model/service/repo files (no widgets,
// plugins, or platform channels) so they run fast and reliably under
// `flutter test` in CI, matching `test/models_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:farda/application/reminders/model/reminder_model.dart';
import 'package:farda/application/reminders/repo/reminder_repo.dart';
import 'package:farda/application/reminders/service/reminder_scheduler.dart';

ReminderModel _r(String id, DateTime at, {String? med}) =>
    ReminderModel(doseId: id, scheduledFor: at, medicineName: med);

void main() {
  group('ReminderScheduler.nextReminders', () {
    final now = DateTime(2026, 7, 1, 12, 0);

    test('drops past reminders and keeps only future ones, sorted ascending',
        () {
      final reminders = [
        _r('past', now.subtract(const Duration(hours: 1))),
        _r('soon', now.add(const Duration(hours: 2))),
        _r('later', now.add(const Duration(hours: 5))),
        _r('now', now), // exactly now is NOT in the future -> dropped
      ];

      final next = ReminderScheduler.nextReminders(reminders, now: now);

      expect(next.map((r) => r.doseId), ['soon', 'later']);
    });

    test('limits to the next N reminders', () {
      final reminders = List.generate(
        10,
        (i) => _r('d$i', now.add(Duration(hours: i + 1))),
      );

      final next =
          ReminderScheduler.nextReminders(reminders, now: now, limit: 3);

      expect(next.length, 3);
      expect(next.map((r) => r.doseId), ['d0', 'd1', 'd2']);
    });

    test('suppresses reminders that fall inside quiet hours', () {
      // Quiet hours 22:00 (1320) -> 07:00 (420), wrapping past midnight.
      const prefs = ReminderPreferences(
        quietHoursStart: 1320,
        quietHoursEnd: 420,
      );
      final base = DateTime(2026, 7, 2);
      final reminders = [
        _r('night', base.add(const Duration(hours: 2))), // 02:00 -> suppressed
        _r('morning', base.add(const Duration(hours: 9))), // 09:00 -> kept
        _r('lateNight', base.add(const Duration(hours: 23))), // 23:00 -> suppressed
      ];

      final next = ReminderScheduler.nextReminders(
        reminders,
        now: base,
        preferences: prefs,
      );

      expect(next.map((r) => r.doseId), ['morning']);
    });
  });

  group('ReminderScheduler.isInQuietHours', () {
    test('returns false when no window is configured', () {
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 3), null),
        isFalse,
      );
      expect(
        ReminderScheduler.isInQuietHours(
          DateTime(2026, 7, 1, 3),
          const ReminderPreferences(quietHoursStart: 1320), // end null
        ),
        isFalse,
      );
    });

    test('same-day window [01:00, 06:00) is inclusive start, exclusive end', () {
      const prefs =
          ReminderPreferences(quietHoursStart: 60, quietHoursEnd: 360);
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 1, 0), prefs),
        isTrue,
      );
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 5, 59), prefs),
        isTrue,
      );
      // Exactly the end bound fires (exclusive end).
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 6, 0), prefs),
        isFalse,
      );
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 0, 59), prefs),
        isFalse,
      );
    });

    test('wrapping window [22:00, 07:00) covers both sides of midnight', () {
      const prefs =
          ReminderPreferences(quietHoursStart: 1320, quietHoursEnd: 420);
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 23, 0), prefs),
        isTrue,
      );
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 2, 0), prefs),
        isTrue,
      );
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 7, 0), prefs),
        isFalse, // exclusive end
      );
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 12, 0), prefs),
        isFalse,
      );
    });

    test('a zero-width window (start == end) suppresses nothing', () {
      const prefs =
          ReminderPreferences(quietHoursStart: 480, quietHoursEnd: 480);
      expect(
        ReminderScheduler.isInQuietHours(DateTime(2026, 7, 1, 8, 0), prefs),
        isFalse,
      );
    });
  });

  group('ReminderScheduler.snoozeUntil', () {
    final from = DateTime(2026, 7, 1, 9, 0);

    test('adds the default 10 minutes', () {
      expect(
        ReminderScheduler.snoozeUntil(from),
        DateTime(2026, 7, 1, 9, 10),
      );
    });

    test('adds a custom snooze duration', () {
      expect(
        ReminderScheduler.snoozeUntil(from, snoozeMinutes: 30),
        DateTime(2026, 7, 1, 9, 30),
      );
    });

    test('clamps non-positive snooze to 1 minute (always moves forward)', () {
      expect(
        ReminderScheduler.snoozeUntil(from, snoozeMinutes: 0),
        DateTime(2026, 7, 1, 9, 1),
      );
      expect(
        ReminderScheduler.snoozeUntil(from, snoozeMinutes: -5),
        DateTime(2026, 7, 1, 9, 1),
      );
    });
  });

  group('ReminderScheduler.buildEventPayload', () {
    test('builds a SNOOZED payload with timings and snooze minutes', () {
      final scheduled = DateTime.utc(2026, 7, 1, 8, 0);
      final payload = ReminderScheduler.buildEventPayload(
        eventType: ReminderEventType.snoozed,
        doseId: 'dose-1',
        scheduledFor: scheduled,
        occurredAt: DateTime.utc(2026, 7, 1, 8, 0, 5),
        snoozeMinutes: 10,
        timeToAction: const Duration(seconds: 5),
        metadata: {'platform': 'ios'},
      );

      expect(payload['eventType'], 'SNOOZED');
      expect(payload['doseId'], 'dose-1');
      expect(payload['channel'], 'LOCAL');
      expect(payload['snoozeMinutes'], 10);
      expect(payload['timeToActionMs'], 5000);
      expect(payload['scheduledFor'], '2026-07-01T08:00:00.000Z');
      expect(payload['metadata'], {'platform': 'ios'});
    });

    test('omits null/empty optional fields', () {
      final payload = ReminderScheduler.buildEventPayload(
        eventType: ReminderEventType.delivered,
      );

      expect(payload['eventType'], 'DELIVERED');
      expect(payload.containsKey('doseId'), isFalse);
      expect(payload.containsKey('snoozeMinutes'), isFalse);
      expect(payload.containsKey('timeToActionMs'), isFalse);
      expect(payload.containsKey('metadata'), isFalse);
      // occurredAt is always present.
      expect(payload.containsKey('occurredAt'), isTrue);
    });

    test('event type wire values are uppercase and match the backend', () {
      expect(ReminderEventType.delivered.wire, 'DELIVERED');
      expect(ReminderEventType.opened.wire, 'OPENED');
      expect(ReminderEventType.snoozed.wire, 'SNOOZED');
      expect(ReminderEventType.dismissed.wire, 'DISMISSED');
      expect(ReminderEventType.actioned.wire, 'ACTIONED');
    });

    test('payload carries NO PHI free-text (only ids/types/timings)', () {
      final payload = ReminderScheduler.buildEventPayload(
        eventType: ReminderEventType.actioned,
        doseId: 'dose-9',
        scheduledFor: DateTime.utc(2026, 7, 1, 8, 0),
      );
      final serialized = payload.toString().toLowerCase();
      expect(serialized.contains('mood'), isFalse);
      expect(serialized.contains('note'), isFalse);
      expect(serialized.contains('medicine'), isFalse);
    });
  });

  group('ReminderModel', () {
    test('fromJson parses fields and converts scheduledFor to local', () {
      final model = ReminderModel.fromJson({
        'doseId': 'dose-1',
        'prescriptionId': 'rx-1',
        'scheduledFor': '2026-07-01T08:00:00.000Z',
        'medicineName': 'Lisinopril',
      });

      expect(model.doseId, 'dose-1');
      expect(model.prescriptionId, 'rx-1');
      expect(model.medicineName, 'Lisinopril');
      expect(model.scheduledFor.isUtc, isFalse); // localised
    });

    test('notificationId is stable, positive, and 31-bit for the same dose', () {
      final a = _r('dose-abc', DateTime(2026, 7, 1)).notificationId;
      final b = _r('dose-abc', DateTime(2026, 8, 1)).notificationId;
      final c = _r('dose-xyz', DateTime(2026, 7, 1)).notificationId;

      expect(a, b); // depends only on doseId, not time
      expect(a, isNot(c)); // different dose -> different id (very likely)
      expect(a, greaterThan(0));
      expect(a, lessThanOrEqualTo(0x7fffffff));
    });
  });

  group('ReminderPreferences', () {
    test('fromJson coerces numeric quiet-hours and round-trips', () {
      final prefs = ReminderPreferences.fromJson({
        'timezone': 'America/New_York',
        'quietHoursStart': 1320,
        'quietHoursEnd': 420,
      });

      expect(prefs.timezone, 'America/New_York');
      expect(prefs.quietHoursStart, 1320);
      expect(prefs.quietHoursEnd, 420);

      final copy = ReminderPreferences.fromJson(prefs.toJson());
      expect(copy.quietHoursStart, 1320);
      expect(copy.quietHoursEnd, 420);
    });

    test('fromJson tolerates null quiet hours', () {
      final prefs = ReminderPreferences.fromJson({'timezone': null});
      expect(prefs.timezone, isNull);
      expect(prefs.quietHoursStart, isNull);
      expect(prefs.quietHoursEnd, isNull);
    });
  });

  group('ReminderRepo.parseSchedule', () {
    test('parses reminders + preferences from the schedule response', () {
      final result = ReminderRepo.parseSchedule({
        'preferences': {
          'timezone': 'Europe/London',
          'quietHoursStart': 1320,
          'quietHoursEnd': 420,
        },
        'reminders': [
          {
            'doseId': 'dose-1',
            'prescriptionId': 'rx-1',
            'scheduledFor': '2026-07-01T08:00:00.000Z',
            'medicineName': 'Metformin',
          },
          {
            'doseId': 'dose-2',
            'scheduledFor': '2026-07-01T20:00:00.000Z',
          },
        ],
      });

      expect(result.reminders.length, 2);
      expect(result.reminders.first.medicineName, 'Metformin');
      expect(result.prefs.timezone, 'Europe/London');
      expect(result.prefs.quietHoursStart, 1320);
    });

    test('handles a missing reminders/preferences gracefully', () {
      final result = ReminderRepo.parseSchedule({});
      expect(result.reminders, isEmpty);
      expect(result.prefs.timezone, isNull);
    });
  });
}
