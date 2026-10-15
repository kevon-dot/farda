import 'reminder_eligibility.dart';
import 'reminder_intent.dart';
import 'reminder_occurrence.dart';
import 'reminder_occurrence_event.dart';
import 'reminder_transition.dart';

/// Deterministic state machine for a single reminder occurrence.
///
/// The reducer has no side effects. Persist [ReminderTransition.state] and its
/// intents together (for example, in one database transaction/outbox write).
final class ReminderOccurrenceReducer {
  const ReminderOccurrenceReducer({
    this.eligibilityPolicy = const ReminderEligibilityPolicy(),
    this.maximumSnooze = const Duration(hours: 24),
  });

  final ReminderEligibilityPolicy eligibilityPolicy;
  final Duration maximumSnooze;

  ReminderTransition reduce(
    ReminderOccurrence current,
    ReminderOccurrenceEvent event,
  ) {
    if (event.occurrenceId != current.id) {
      return ReminderTransition.rejected(
        current,
        ReminderRejectionReason.wrongOccurrence,
      );
    }
    if (current.processedEventIds.contains(event.eventId)) {
      return ReminderTransition.duplicate(current);
    }

    return switch (event) {
      ReminderDeliveryRequested request => _requestDelivery(current, request),
      ReminderSnoozed snoozed => _snooze(current, snoozed),
      OccurrenceRemindersCancelled cancelled => _cancel(current, cancelled),
      ReminderCallAnswered answered => _recordCallAnswer(current, answered),
      VialMovementDetected movement => _recordMovement(current, movement),
      DoseTakenExplicitlyConfirmed confirmation => _confirmTaken(
        current,
        confirmation,
      ),
    };
  }

  ReminderTransition _requestDelivery(
    ReminderOccurrence current,
    ReminderDeliveryRequested event,
  ) {
    final eligibility = eligibilityPolicy.evaluate(current, event);
    if (!eligibility.isEligible) {
      return ReminderTransition.rejected(current, eligibility.blockReason!);
    }

    final deliveryKey = current.deliveryKeyFor(event.kind);
    final next = _commit(
      current,
      event,
      auditType: ReminderAuditType.deliveryRequested,
      detail: event.kind.name,
      callAttempts:
          event.kind == ReminderDeliveryKind.reminderCall
              ? current.callAttempts + 1
              : current.callAttempts,
      dispatchedDeliveryKeys: <String>{
        ...current.dispatchedDeliveryKeys,
        deliveryKey,
      },
    );

    return ReminderTransition.applied(
      state: next,
      intents: <ReminderIntent>[
        DeliverReminderIntent(
          idempotencyKey: deliveryKey,
          occurrenceId: current.id,
          requestedAtUtc: event.occurredAtUtc,
          kind: event.kind,
          scheduledForUtc: eligibility.scheduledForUtc!,
          timeZoneId: current.timeZoneId,
        ),
      ],
    );
  }

  ReminderTransition _snooze(
    ReminderOccurrence current,
    ReminderSnoozed event,
  ) {
    if (current.remindersCancelled) {
      return ReminderTransition.rejected(
        current,
        ReminderRejectionReason.occurrenceCancelled,
      );
    }
    if (current.record.isFinal) {
      return ReminderTransition.rejected(
        current,
        ReminderRejectionReason.recordAlreadyFinalized,
      );
    }
    if (event.snoozeFor <= Duration.zero ||
        event.snoozeFor > maximumSnooze) {
      return ReminderTransition.rejected(
        current,
        ReminderRejectionReason.invalidSnoozeDuration,
      );
    }

    final nextSnoozeCount = current.snoozeCount + 1;
    final nextReminderAtUtc = event.occurredAtUtc.add(event.snoozeFor);
    final nextDeliveryKey =
        '${current.id}:delivery:${ReminderDeliveryKind.snoozeFollowUp.name}:'
        '$nextSnoozeCount';
    final next = _commit(
      current,
      event,
      auditType: ReminderAuditType.snoozed,
      detail: '${event.snoozeFor.inMinutes} minutes; record unchanged',
      snoozedUntilUtc: nextReminderAtUtc,
      snoozeCount: nextSnoozeCount,
    );

    return ReminderTransition.applied(
      state: next,
      intents: <ReminderIntent>[
        CancelReminderIntents(
          idempotencyKey: '${current.id}:cancel:snooze:$nextSnoozeCount',
          occurrenceId: current.id,
          requestedAtUtc: event.occurredAtUtc,
          reason: ReminderCancellationReason.snoozed,
          deliveryKeys: _knownDeliveryKeys(current),
        ),
        ScheduleReminderIntent(
          idempotencyKey:
              '${current.id}:schedule:snooze-follow-up:$nextSnoozeCount',
          occurrenceId: current.id,
          requestedAtUtc: event.occurredAtUtc,
          kind: ReminderDeliveryKind.snoozeFollowUp,
          deliveryKey: nextDeliveryKey,
          triggerAtUtc: nextReminderAtUtc,
        ),
      ],
    );
  }

  ReminderTransition _cancel(
    ReminderOccurrence current,
    OccurrenceRemindersCancelled event,
  ) {
    if (current.remindersCancelled) {
      return ReminderTransition.rejected(
        current,
        ReminderRejectionReason.alreadyCancelled,
      );
    }

    final next = _commit(
      current,
      event,
      auditType: ReminderAuditType.remindersCancelled,
      detail: 'remaining delivery cancelled; record unchanged',
      remindersCancelled: true,
      clearSnooze: true,
    );
    return ReminderTransition.applied(
      state: next,
      intents: <ReminderIntent>[
        CancelReminderIntents(
          idempotencyKey: '${current.id}:cancel:occurrence',
          occurrenceId: current.id,
          requestedAtUtc: event.occurredAtUtc,
          reason: ReminderCancellationReason.occurrenceCancelled,
          deliveryKeys: _knownDeliveryKeys(current),
        ),
      ],
    );
  }

  ReminderTransition _recordCallAnswer(
    ReminderOccurrence current,
    ReminderCallAnswered event,
  ) {
    final next = _commit(
      current,
      event,
      auditType: ReminderAuditType.callAnswered,
      detail: 'call ${event.callAttemptId} answered; no dose confirmation',
      lastCallAnsweredAtUtc: event.occurredAtUtc,
    );
    return ReminderTransition.applied(state: next);
  }

  ReminderTransition _recordMovement(
    ReminderOccurrence current,
    VialMovementDetected event,
  ) {
    final next = _commit(
      current,
      event,
      auditType: ReminderAuditType.vialMovementObserved,
      detail: 'movement from ${event.deviceId}; no dose confirmation',
      lastVialMovementAtUtc: event.occurredAtUtc,
    );
    return ReminderTransition.applied(state: next);
  }

  ReminderTransition _confirmTaken(
    ReminderOccurrence current,
    DoseTakenExplicitlyConfirmed event,
  ) {
    if (current.record.isFinal) {
      return ReminderTransition.rejected(
        current,
        ReminderRejectionReason.recordAlreadyFinalized,
      );
    }

    final next = _commit(
      current,
      event,
      auditType: ReminderAuditType.doseExplicitlyConfirmed,
      detail: event.channel.name,
      record: RoutineRecord.taken(
        confirmedAtUtc: event.occurredAtUtc,
        channel: event.channel,
        confirmationId: event.confirmationId,
      ),
      clearSnooze: true,
    );
    return ReminderTransition.applied(
      state: next,
      intents: <ReminderIntent>[
        CancelReminderIntents(
          idempotencyKey: '${current.id}:cancel:record-finalized',
          occurrenceId: current.id,
          requestedAtUtc: event.occurredAtUtc,
          reason: ReminderCancellationReason.recordFinalized,
          deliveryKeys: _knownDeliveryKeys(current),
        ),
      ],
    );
  }

  ReminderOccurrence _commit(
    ReminderOccurrence current,
    ReminderOccurrenceEvent event, {
    required ReminderAuditType auditType,
    required String detail,
    RoutineRecord? record,
    bool? remindersCancelled,
    DateTime? snoozedUntilUtc,
    bool clearSnooze = false,
    int? snoozeCount,
    int? callAttempts,
    DateTime? lastCallAnsweredAtUtc,
    DateTime? lastVialMovementAtUtc,
    Set<String>? dispatchedDeliveryKeys,
  }) {
    return current.copyWith(
      revision: current.revision + 1,
      record: record,
      remindersCancelled: remindersCancelled,
      snoozedUntilUtc: snoozedUntilUtc,
      clearSnooze: clearSnooze,
      snoozeCount: snoozeCount,
      callAttempts: callAttempts,
      lastCallAnsweredAtUtc: lastCallAnsweredAtUtc,
      lastVialMovementAtUtc: lastVialMovementAtUtc,
      processedEventIds: <String>{
        ...current.processedEventIds,
        event.eventId,
      },
      dispatchedDeliveryKeys: dispatchedDeliveryKeys,
      auditTrail: <ReminderAuditEntry>[
        ...current.auditTrail,
        ReminderAuditEntry(
          eventId: event.eventId,
          type: auditType,
          occurredAtUtc: event.occurredAtUtc,
          detail: detail,
        ),
      ],
    );
  }

  Set<String> _knownDeliveryKeys(ReminderOccurrence occurrence) {
    return <String>{
      occurrence.deliveryKeyFor(ReminderDeliveryKind.headsUp),
      occurrence.deliveryKeyFor(ReminderDeliveryKind.due),
      occurrence.deliveryKeyFor(ReminderDeliveryKind.reminderCall),
      for (var index = 1; index <= occurrence.snoozeCount; index++)
        '${occurrence.id}:delivery:'
            '${ReminderDeliveryKind.snoozeFollowUp.name}:$index',
    };
  }
}
