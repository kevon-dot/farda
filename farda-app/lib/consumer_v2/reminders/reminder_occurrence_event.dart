import 'reminder_occurrence.dart';

/// Input to the occurrence reducer. Event IDs are idempotency keys supplied by
/// the caller and must remain stable across retries.
sealed class ReminderOccurrenceEvent {
  ReminderOccurrenceEvent({
    required this.eventId,
    required this.occurrenceId,
    required DateTime occurredAtUtc,
  }) : occurredAtUtc = occurredAtUtc.toUtc() {
    if (eventId.trim().isEmpty) {
      throw ArgumentError.value(eventId, 'eventId', 'must not be empty');
    }
    if (occurrenceId.trim().isEmpty) {
      throw ArgumentError.value(
        occurrenceId,
        'occurrenceId',
        'must not be empty',
      );
    }
  }

  final String eventId;
  final String occurrenceId;
  final DateTime occurredAtUtc;
}

/// Requests one delivery milestone. It does not perform the delivery itself.
final class ReminderDeliveryRequested extends ReminderOccurrenceEvent {
  ReminderDeliveryRequested({
    required super.eventId,
    required super.occurrenceId,
    required super.occurredAtUtc,
    required this.kind,
    required this.localWallClockTime,
  });

  final ReminderDeliveryKind kind;

  /// Wall-clock time in the occurrence's [ReminderOccurrence.timeZoneId].
  /// Infrastructure obtains this through a reminder local-time resolver.
  final WallClockTime localWallClockTime;
}

/// A user explicitly asks to move reminder delivery. This changes reminders,
/// not the routine directions or routine record.
final class ReminderSnoozed extends ReminderOccurrenceEvent {
  ReminderSnoozed({
    required super.eventId,
    required super.occurrenceId,
    required super.occurredAtUtc,
    this.snoozeFor = const Duration(minutes: 15),
  });

  final Duration snoozeFor;
}

/// Cancels remaining reminder delivery for this occurrence. It does not create
/// a taken or skipped record.
final class OccurrenceRemindersCancelled extends ReminderOccurrenceEvent {
  OccurrenceRemindersCancelled({
    required super.eventId,
    required super.occurrenceId,
    required super.occurredAtUtc,
  });
}

/// Transport signal only. Answering a reminder call never confirms a dose.
final class ReminderCallAnswered extends ReminderOccurrenceEvent {
  ReminderCallAnswered({
    required super.eventId,
    required super.occurrenceId,
    required super.occurredAtUtc,
    required this.callAttemptId,
  }) {
    if (callAttemptId.trim().isEmpty) {
      throw ArgumentError.value(
        callAttemptId,
        'callAttemptId',
        'must not be empty',
      );
    }
  }

  final String callAttemptId;
}

/// Device telemetry only. Movement may prompt a check-in but never confirms
/// that medication was taken.
final class VialMovementDetected extends ReminderOccurrenceEvent {
  VialMovementDetected({
    required super.eventId,
    required super.occurrenceId,
    required super.occurredAtUtc,
    required this.deviceId,
  }) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
    }
  }

  final String deviceId;
}

/// The sole event that can transition the routine record to `taken`.
///
/// Application code should emit this only after a user reviews and explicitly
/// confirms the proposed entry. Phone check-ins must complete their separate
/// authentication and confirmation flow before emitting it.
final class DoseTakenExplicitlyConfirmed extends ReminderOccurrenceEvent {
  DoseTakenExplicitlyConfirmed({
    required super.eventId,
    required super.occurrenceId,
    required super.occurredAtUtc,
    required this.channel,
    required this.confirmationId,
  }) {
    if (confirmationId.trim().isEmpty) {
      throw ArgumentError.value(
        confirmationId,
        'confirmationId',
        'must not be empty',
      );
    }
  }

  final ExplicitConfirmationChannel channel;
  final String confirmationId;
}
