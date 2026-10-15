import 'reminder_occurrence.dart';
import 'reminder_occurrence_event.dart';
import 'reminder_transition.dart';

final class ReminderDeliveryEligibility {
  const ReminderDeliveryEligibility._({
    required this.isEligible,
    required this.scheduledForUtc,
    required this.blockReason,
  });

  factory ReminderDeliveryEligibility.eligible(DateTime scheduledForUtc) =>
      ReminderDeliveryEligibility._(
        isEligible: true,
        scheduledForUtc: scheduledForUtc.toUtc(),
        blockReason: null,
      );

  const factory ReminderDeliveryEligibility.blocked(
    ReminderRejectionReason reason,
  ) = _BlockedReminderDeliveryEligibility;

  final bool isEligible;
  final DateTime? scheduledForUtc;
  final ReminderRejectionReason? blockReason;
}

final class _BlockedReminderDeliveryEligibility
    extends ReminderDeliveryEligibility {
  const _BlockedReminderDeliveryEligibility(ReminderRejectionReason reason)
    : super._(
        isEligible: false,
        scheduledForUtc: null,
        blockReason: reason,
      );
}

/// Pure policy for deciding whether a milestone may create a delivery intent.
final class ReminderEligibilityPolicy {
  const ReminderEligibilityPolicy();

  ReminderDeliveryEligibility evaluate(
    ReminderOccurrence occurrence,
    ReminderDeliveryRequested request,
  ) {
    if (occurrence.remindersCancelled) {
      return const ReminderDeliveryEligibility.blocked(
        ReminderRejectionReason.occurrenceCancelled,
      );
    }
    if (occurrence.record.isFinal) {
      return const ReminderDeliveryEligibility.blocked(
        ReminderRejectionReason.recordAlreadyFinalized,
      );
    }

    final kind = request.kind;
    final isOriginalTimeline = kind != ReminderDeliveryKind.snoozeFollowUp;
    if (occurrence.isSnoozed && isOriginalTimeline) {
      return const ReminderDeliveryEligibility.blocked(
        ReminderRejectionReason.originalTimelineSnoozed,
      );
    }
    if (!occurrence.isSnoozed &&
        kind == ReminderDeliveryKind.snoozeFollowUp) {
      return const ReminderDeliveryEligibility.blocked(
        ReminderRejectionReason.noSnoozeScheduled,
      );
    }

    final deliveryKey = occurrence.deliveryKeyFor(kind);
    if (occurrence.dispatchedDeliveryKeys.contains(deliveryKey)) {
      return const ReminderDeliveryEligibility.blocked(
        ReminderRejectionReason.alreadyDispatched,
      );
    }

    final scheduledForUtc = occurrence.scheduledAtFor(kind);
    if (scheduledForUtc == null) {
      return const ReminderDeliveryEligibility.blocked(
        ReminderRejectionReason.noSnoozeScheduled,
      );
    }
    if (request.occurredAtUtc.isBefore(scheduledForUtc)) {
      return const ReminderDeliveryEligibility.blocked(
        ReminderRejectionReason.beforeScheduledTime,
      );
    }

    if (kind == ReminderDeliveryKind.reminderCall) {
      final call = occurrence.callConfiguration;
      if (!call.enabled) {
        return const ReminderDeliveryEligibility.blocked(
          ReminderRejectionReason.callDisabled,
        );
      }
      if (!call.phoneVerified) {
        return const ReminderDeliveryEligibility.blocked(
          ReminderRejectionReason.phoneNotVerified,
        );
      }
      if (!call.userConsented) {
        return const ReminderDeliveryEligibility.blocked(
          ReminderRejectionReason.callConsentMissing,
        );
      }
      if (occurrence.callAttempts >= 1) {
        return const ReminderDeliveryEligibility.blocked(
          ReminderRejectionReason.callAlreadyAttempted,
        );
      }
      if (call.quietHours?.contains(request.localWallClockTime) ?? false) {
        return const ReminderDeliveryEligibility.blocked(
          ReminderRejectionReason.quietHours,
        );
      }
    }

    return ReminderDeliveryEligibility.eligible(scheduledForUtc);
  }
}
