import 'reminder_intent.dart';
import 'reminder_occurrence.dart';
import 'reminder_transition.dart';

/// Provides time without coupling the domain to platform clocks.
abstract interface class ReminderClock {
  DateTime nowUtc();
}

/// Resolves an instant into the wall-clock time for an IANA timezone ID.
///
/// Implementations belong in infrastructure (for example, using a timezone
/// package). The domain only consumes the resulting [WallClockTime].
abstract interface class ReminderLocalTimeResolver {
  WallClockTime wallClockTime({
    required DateTime instantUtc,
    required String timeZoneId,
  });
}

/// Persistence/outbox boundary. Implementations should use optimistic locking
/// on the expected revision and atomically store state plus emitted intents.
abstract interface class ReminderOccurrenceStore {
  Future<ReminderOccurrence?> load(String occurrenceId);

  Future<void> commit(
    ReminderTransition transition, {
    required int expectedRevision,
  });
}

/// Infrastructure boundary for consuming a durable outbox intent.
///
/// Implementations must deduplicate [ReminderIntent.idempotencyKey]. This layer
/// intentionally supplies no OS-notification or telephony implementation.
abstract interface class ReminderIntentHandler {
  Future<void> handle(ReminderIntent intent);
}
