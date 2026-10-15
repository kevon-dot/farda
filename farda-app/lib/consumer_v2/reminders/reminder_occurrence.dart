/// Pure domain types for one scheduled routine occurrence.
///
/// These types deliberately contain no notification, telephony, persistence,
/// or device SDK dependencies. Infrastructure code can translate the intents
/// produced by the occurrence reducer at the application boundary.

enum ReminderDeliveryKind {
  headsUp,
  due,
  reminderCall,
  snoozeFollowUp,
}

enum RoutineRecordStatus {
  unconfirmed,
  taken,
}

enum ExplicitConfirmationChannel {
  app,
  authenticatedPhoneCheckIn,
}

/// A timezone-independent wall-clock value used by quiet-hours rules.
final class WallClockTime implements Comparable<WallClockTime> {
  const WallClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  final int hour;
  final int minute;

  int get minutesSinceMidnight => (hour * 60) + minute;

  @override
  int compareTo(WallClockTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  bool operator ==(Object other) =>
      other is WallClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Half-open quiet-hours window: start is included and end is excluded.
///
/// A window such as 21:00-08:00 wraps across midnight. Equal endpoints are
/// treated as an all-day quiet window; callers that want no quiet hours should
/// set [ReminderCallConfiguration.quietHours] to null.
final class QuietHours {
  const QuietHours({required this.start, required this.end});

  final WallClockTime start;
  final WallClockTime end;

  bool contains(WallClockTime time) {
    final startMinute = start.minutesSinceMidnight;
    final endMinute = end.minutesSinceMidnight;
    final currentMinute = time.minutesSinceMidnight;

    if (startMinute == endMinute) return true;
    if (startMinute < endMinute) {
      return currentMinute >= startMinute && currentMinute < endMinute;
    }
    return currentMinute >= startMinute || currentMinute < endMinute;
  }
}

/// Consent and safety gates for the optional reminder call.
final class ReminderCallConfiguration {
  const ReminderCallConfiguration({
    required this.enabled,
    required this.phoneVerified,
    required this.userConsented,
    this.quietHours,
  });

  const ReminderCallConfiguration.disabled()
    : enabled = false,
      phoneVerified = false,
      userConsented = false,
      quietHours = null;

  final bool enabled;
  final bool phoneVerified;
  final bool userConsented;
  final QuietHours? quietHours;
}

/// The immutable timing snapshot for one occurrence.
///
/// Editing a future routine must create/update future occurrences rather than
/// changing this cadence after it has been created.
final class ReminderCadence {
  ReminderCadence({
    required DateTime dueAtUtc,
    this.headsUpLead = const Duration(minutes: 10),
    this.callDelay = const Duration(minutes: 10),
  }) : dueAtUtc = dueAtUtc.toUtc() {
    if (headsUpLead <= Duration.zero) {
      throw ArgumentError.value(
        headsUpLead,
        'headsUpLead',
        'must be greater than zero',
      );
    }
    if (callDelay <= Duration.zero) {
      throw ArgumentError.value(
        callDelay,
        'callDelay',
        'must be greater than zero',
      );
    }
  }

  final DateTime dueAtUtc;
  final Duration headsUpLead;
  final Duration callDelay;

  DateTime get headsUpAtUtc => dueAtUtc.subtract(headsUpLead);
  DateTime get callAtUtc => dueAtUtc.add(callDelay);
}

/// A routine record can only become taken through an explicit confirmation
/// event handled by the reducer. Reminder calls and vial signals are evidence
/// that an interaction occurred, not evidence of ingestion.
final class RoutineRecord {
  const RoutineRecord.unconfirmed()
    : status = RoutineRecordStatus.unconfirmed,
      confirmedAtUtc = null,
      confirmationChannel = null,
      confirmationId = null;

  const RoutineRecord._({
    required this.status,
    required this.confirmedAtUtc,
    required this.confirmationChannel,
    required this.confirmationId,
  });

  factory RoutineRecord.taken({
    required DateTime confirmedAtUtc,
    required ExplicitConfirmationChannel channel,
    required String confirmationId,
  }) {
    if (confirmationId.trim().isEmpty) {
      throw ArgumentError.value(
        confirmationId,
        'confirmationId',
        'must not be empty',
      );
    }
    return RoutineRecord._(
      status: RoutineRecordStatus.taken,
      confirmedAtUtc: confirmedAtUtc.toUtc(),
      confirmationChannel: channel,
      confirmationId: confirmationId,
    );
  }

  final RoutineRecordStatus status;
  final DateTime? confirmedAtUtc;
  final ExplicitConfirmationChannel? confirmationChannel;
  final String? confirmationId;

  bool get isFinal => status != RoutineRecordStatus.unconfirmed;
}

enum ReminderAuditType {
  deliveryRequested,
  snoozed,
  remindersCancelled,
  callAnswered,
  vialMovementObserved,
  doseExplicitlyConfirmed,
}

final class ReminderAuditEntry {
  ReminderAuditEntry({
    required this.eventId,
    required this.type,
    required DateTime occurredAtUtc,
    required this.detail,
  }) : occurredAtUtc = occurredAtUtc.toUtc();

  final String eventId;
  final ReminderAuditType type;
  final DateTime occurredAtUtc;
  final String detail;
}

/// Immutable aggregate for exactly one routine occurrence.
final class ReminderOccurrence {
  ReminderOccurrence._({
    required this.id,
    required this.revision,
    required this.timeZoneId,
    required this.cadence,
    required this.callConfiguration,
    required this.record,
    required this.remindersCancelled,
    required this.snoozedUntilUtc,
    required this.snoozeCount,
    required this.callAttempts,
    required this.lastCallAnsweredAtUtc,
    required this.lastVialMovementAtUtc,
    required Set<String> processedEventIds,
    required Set<String> dispatchedDeliveryKeys,
    required List<ReminderAuditEntry> auditTrail,
  }) : processedEventIds = Set<String>.unmodifiable(processedEventIds),
       dispatchedDeliveryKeys = Set<String>.unmodifiable(
         dispatchedDeliveryKeys,
       ),
       auditTrail = List<ReminderAuditEntry>.unmodifiable(auditTrail);

  factory ReminderOccurrence.create({
    required String id,
    required String timeZoneId,
    required DateTime dueAtUtc,
    ReminderCallConfiguration callConfiguration =
        const ReminderCallConfiguration.disabled(),
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (timeZoneId.trim().isEmpty) {
      throw ArgumentError.value(
        timeZoneId,
        'timeZoneId',
        'must not be empty',
      );
    }

    return ReminderOccurrence._(
      id: id,
      revision: 0,
      timeZoneId: timeZoneId,
      cadence: ReminderCadence(dueAtUtc: dueAtUtc),
      callConfiguration: callConfiguration,
      record: const RoutineRecord.unconfirmed(),
      remindersCancelled: false,
      snoozedUntilUtc: null,
      snoozeCount: 0,
      callAttempts: 0,
      lastCallAnsweredAtUtc: null,
      lastVialMovementAtUtc: null,
      processedEventIds: const <String>{},
      dispatchedDeliveryKeys: const <String>{},
      auditTrail: const <ReminderAuditEntry>[],
    );
  }

  final String id;
  final int revision;
  final String timeZoneId;
  final ReminderCadence cadence;
  final ReminderCallConfiguration callConfiguration;
  final RoutineRecord record;
  final bool remindersCancelled;
  final DateTime? snoozedUntilUtc;
  final int snoozeCount;
  final int callAttempts;
  final DateTime? lastCallAnsweredAtUtc;
  final DateTime? lastVialMovementAtUtc;
  final Set<String> processedEventIds;
  final Set<String> dispatchedDeliveryKeys;
  final List<ReminderAuditEntry> auditTrail;

  bool get isSnoozed => snoozedUntilUtc != null;
  bool get isUnconfirmed => record.status == RoutineRecordStatus.unconfirmed;

  String deliveryKeyFor(ReminderDeliveryKind kind) {
    if (kind == ReminderDeliveryKind.snoozeFollowUp) {
      return '$id:delivery:${kind.name}:$snoozeCount';
    }
    return '$id:delivery:${kind.name}';
  }

  DateTime? scheduledAtFor(ReminderDeliveryKind kind) {
    return switch (kind) {
      ReminderDeliveryKind.headsUp => cadence.headsUpAtUtc,
      ReminderDeliveryKind.due => cadence.dueAtUtc,
      ReminderDeliveryKind.reminderCall => cadence.callAtUtc,
      ReminderDeliveryKind.snoozeFollowUp => snoozedUntilUtc,
    };
  }

  ReminderOccurrence copyWith({
    int? revision,
    RoutineRecord? record,
    bool? remindersCancelled,
    DateTime? snoozedUntilUtc,
    bool clearSnooze = false,
    int? snoozeCount,
    int? callAttempts,
    DateTime? lastCallAnsweredAtUtc,
    DateTime? lastVialMovementAtUtc,
    Set<String>? processedEventIds,
    Set<String>? dispatchedDeliveryKeys,
    List<ReminderAuditEntry>? auditTrail,
  }) {
    return ReminderOccurrence._(
      id: id,
      revision: revision ?? this.revision,
      timeZoneId: timeZoneId,
      cadence: cadence,
      callConfiguration: callConfiguration,
      record: record ?? this.record,
      remindersCancelled: remindersCancelled ?? this.remindersCancelled,
      snoozedUntilUtc:
          clearSnooze ? null : snoozedUntilUtc ?? this.snoozedUntilUtc,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      callAttempts: callAttempts ?? this.callAttempts,
      lastCallAnsweredAtUtc:
          lastCallAnsweredAtUtc ?? this.lastCallAnsweredAtUtc,
      lastVialMovementAtUtc:
          lastVialMovementAtUtc ?? this.lastVialMovementAtUtc,
      processedEventIds: processedEventIds ?? this.processedEventIds,
      dispatchedDeliveryKeys:
          dispatchedDeliveryKeys ?? this.dispatchedDeliveryKeys,
      auditTrail: auditTrail ?? this.auditTrail,
    );
  }
}
