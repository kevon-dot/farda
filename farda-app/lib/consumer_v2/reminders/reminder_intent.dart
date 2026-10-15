import 'reminder_occurrence.dart';

/// Durable outbox item emitted by the pure reducer.
///
/// Infrastructure must persist an intent atomically with the next aggregate
/// revision and deduplicate on [idempotencyKey] before invoking an OS or phone
/// provider API.
sealed class ReminderIntent {
  ReminderIntent({
    required this.idempotencyKey,
    required this.occurrenceId,
    required DateTime requestedAtUtc,
  }) : requestedAtUtc = requestedAtUtc.toUtc();

  final String idempotencyKey;
  final String occurrenceId;
  final DateTime requestedAtUtc;
}

final class DeliverReminderIntent extends ReminderIntent {
  DeliverReminderIntent({
    required super.idempotencyKey,
    required super.occurrenceId,
    required super.requestedAtUtc,
    required this.kind,
    required DateTime scheduledForUtc,
    required this.timeZoneId,
  }) : scheduledForUtc = scheduledForUtc.toUtc();

  final ReminderDeliveryKind kind;
  final DateTime scheduledForUtc;
  final String timeZoneId;
}

/// Requests that infrastructure arrange a future domain trigger. It is not a
/// notification payload and does not imply that delivery has happened.
final class ScheduleReminderIntent extends ReminderIntent {
  ScheduleReminderIntent({
    required super.idempotencyKey,
    required super.occurrenceId,
    required super.requestedAtUtc,
    required this.kind,
    required this.deliveryKey,
    required DateTime triggerAtUtc,
  }) : triggerAtUtc = triggerAtUtc.toUtc();

  final ReminderDeliveryKind kind;
  final String deliveryKey;
  final DateTime triggerAtUtc;
}

enum ReminderCancellationReason {
  snoozed,
  occurrenceCancelled,
  recordFinalized,
}

final class CancelReminderIntents extends ReminderIntent {
  CancelReminderIntents({
    required super.idempotencyKey,
    required super.occurrenceId,
    required super.requestedAtUtc,
    required this.reason,
    required Set<String> deliveryKeys,
  }) : deliveryKeys = Set<String>.unmodifiable(deliveryKeys);

  final ReminderCancellationReason reason;
  final Set<String> deliveryKeys;
}
