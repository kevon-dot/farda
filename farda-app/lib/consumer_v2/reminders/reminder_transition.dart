import 'reminder_intent.dart';
import 'reminder_occurrence.dart';

enum ReminderTransitionStatus {
  applied,
  duplicate,
  rejected,
}

enum ReminderRejectionReason {
  wrongOccurrence,
  beforeScheduledTime,
  alreadyDispatched,
  occurrenceCancelled,
  recordAlreadyFinalized,
  originalTimelineSnoozed,
  noSnoozeScheduled,
  callDisabled,
  phoneNotVerified,
  callConsentMissing,
  callAlreadyAttempted,
  quietHours,
  invalidSnoozeDuration,
  alreadyCancelled,
}

final class ReminderTransition {
  ReminderTransition._({
    required this.state,
    required this.status,
    required List<ReminderIntent> intents,
    required this.rejectionReason,
  }) : intents = List<ReminderIntent>.unmodifiable(intents);

  factory ReminderTransition.applied({
    required ReminderOccurrence state,
    List<ReminderIntent> intents = const <ReminderIntent>[],
  }) => ReminderTransition._(
    state: state,
    status: ReminderTransitionStatus.applied,
    intents: intents,
    rejectionReason: null,
  );

  factory ReminderTransition.duplicate(ReminderOccurrence state) =>
      ReminderTransition._(
        state: state,
        status: ReminderTransitionStatus.duplicate,
        intents: const <ReminderIntent>[],
        rejectionReason: null,
      );

  factory ReminderTransition.rejected(
    ReminderOccurrence state,
    ReminderRejectionReason reason,
  ) => ReminderTransition._(
    state: state,
    status: ReminderTransitionStatus.rejected,
    intents: const <ReminderIntent>[],
    rejectionReason: reason,
  );

  final ReminderOccurrence state;
  final ReminderTransitionStatus status;
  final List<ReminderIntent> intents;
  final ReminderRejectionReason? rejectionReason;

  bool get wasApplied => status == ReminderTransitionStatus.applied;
  bool get wasDuplicate => status == ReminderTransitionStatus.duplicate;
}
