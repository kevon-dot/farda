import 'package:farda/consumer_v2/reminders/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dueAtUtc = DateTime.utc(2026, 10, 15, 16); // 9:00 AM Los Angeles.
  const enabledCalls = ReminderCallConfiguration(
    enabled: true,
    phoneVerified: true,
    userConsented: true,
    quietHours: QuietHours(
      start: WallClockTime(21, 0),
      end: WallClockTime(8, 0),
    ),
  );
  const reducer = ReminderOccurrenceReducer();

  ReminderOccurrence occurrence({
    ReminderCallConfiguration calls = enabledCalls,
  }) => ReminderOccurrence.create(
    id: 'routine-2026-10-15-morning',
    timeZoneId: 'America/Los_Angeles',
    dueAtUtc: dueAtUtc,
    callConfiguration: calls,
  );

  ReminderDeliveryRequested delivery({
    required String eventId,
    required ReminderDeliveryKind kind,
    required DateTime atUtc,
    WallClockTime localTime = const WallClockTime(9, 0),
  }) => ReminderDeliveryRequested(
    eventId: eventId,
    occurrenceId: 'routine-2026-10-15-morning',
    occurredAtUtc: atUtc,
    kind: kind,
    localWallClockTime: localTime,
  );

  group('cadence', () {
    test('models 8:50 heads-up, 9:00 due, and 9:10 optional call', () {
      final state = occurrence();

      expect(state.cadence.headsUpAtUtc, DateTime.utc(2026, 10, 15, 15, 50));
      expect(state.cadence.dueAtUtc, DateTime.utc(2026, 10, 15, 16));
      expect(state.cadence.callAtUtc, DateTime.utc(2026, 10, 15, 16, 10));
      expect(state.record.status, RoutineRecordStatus.unconfirmed);
    });

    test('does not let a future routine edit mutate this timing snapshot', () {
      final state = occurrence();
      final originalCadence = state.cadence;

      final movedFutureRoutine = ReminderOccurrence.create(
        id: 'routine-2026-10-16-morning',
        timeZoneId: state.timeZoneId,
        dueAtUtc: dueAtUtc.add(const Duration(days: 1, hours: 1)),
      );

      expect(state.cadence, same(originalCadence));
      expect(state.cadence.dueAtUtc, dueAtUtc);
      expect(movedFutureRoutine.cadence.dueAtUtc, isNot(dueAtUtc));
    });
  });

  group('delivery eligibility', () {
    test('emits each standard milestone once and increments one call attempt', () {
      var state = occurrence();

      final headsUp = reducer.reduce(
        state,
        delivery(
          eventId: 'heads-up-trigger',
          kind: ReminderDeliveryKind.headsUp,
          atUtc: state.cadence.headsUpAtUtc,
          localTime: const WallClockTime(8, 50),
        ),
      );
      expect(headsUp.wasApplied, isTrue);
      expect(headsUp.intents.single, isA<DeliverReminderIntent>());
      state = headsUp.state;

      final due = reducer.reduce(
        state,
        delivery(
          eventId: 'due-trigger',
          kind: ReminderDeliveryKind.due,
          atUtc: state.cadence.dueAtUtc,
        ),
      );
      expect(due.wasApplied, isTrue);
      state = due.state;

      final call = reducer.reduce(
        state,
        delivery(
          eventId: 'call-trigger',
          kind: ReminderDeliveryKind.reminderCall,
          atUtc: state.cadence.callAtUtc,
          localTime: const WallClockTime(9, 10),
        ),
      );
      expect(call.wasApplied, isTrue);
      expect(call.state.callAttempts, 1);
      expect(
        (call.intents.single as DeliverReminderIntent).kind,
        ReminderDeliveryKind.reminderCall,
      );
    });

    test('rejects an early milestone without consuming its event ID', () {
      final state = occurrence();
      final earlyEvent = delivery(
        eventId: 'due-trigger',
        kind: ReminderDeliveryKind.due,
        atUtc: dueAtUtc.subtract(const Duration(seconds: 1)),
      );

      final early = reducer.reduce(state, earlyEvent);
      expect(early.status, ReminderTransitionStatus.rejected);
      expect(early.rejectionReason, ReminderRejectionReason.beforeScheduledTime);
      expect(early.state.processedEventIds, isNot(contains(earlyEvent.eventId)));

      final onTime = reducer.reduce(
        early.state,
        delivery(
          eventId: earlyEvent.eventId,
          kind: ReminderDeliveryKind.due,
          atUtc: dueAtUtc,
        ),
      );
      expect(onTime.wasApplied, isTrue);
    });

    test('requires enabled, verified, separately consented calls', () {
      const configurations = <ReminderCallConfiguration>[
        ReminderCallConfiguration(
          enabled: false,
          phoneVerified: true,
          userConsented: true,
        ),
        ReminderCallConfiguration(
          enabled: true,
          phoneVerified: false,
          userConsented: true,
        ),
        ReminderCallConfiguration(
          enabled: true,
          phoneVerified: true,
          userConsented: false,
        ),
      ];
      const reasons = <ReminderRejectionReason>[
        ReminderRejectionReason.callDisabled,
        ReminderRejectionReason.phoneNotVerified,
        ReminderRejectionReason.callConsentMissing,
      ];

      for (var index = 0; index < configurations.length; index++) {
        final state = occurrence(calls: configurations[index]);
        final result = reducer.reduce(
          state,
          delivery(
            eventId: 'call-$index',
            kind: ReminderDeliveryKind.reminderCall,
            atUtc: state.cadence.callAtUtc,
            localTime: const WallClockTime(9, 10),
          ),
        );
        expect(result.rejectionReason, reasons[index]);
        expect(result.intents, isEmpty);
      }
    });

    test('blocks calls inside quiet hours and allows the exact end boundary', () {
      final state = occurrence();
      final quiet = reducer.reduce(
        state,
        delivery(
          eventId: 'quiet-call',
          kind: ReminderDeliveryKind.reminderCall,
          atUtc: state.cadence.callAtUtc,
          localTime: const WallClockTime(21, 0),
        ),
      );
      expect(quiet.rejectionReason, ReminderRejectionReason.quietHours);
      expect(quiet.state.callAttempts, 0);

      final allowed = reducer.reduce(
        quiet.state,
        delivery(
          eventId: 'allowed-call',
          kind: ReminderDeliveryKind.reminderCall,
          atUtc: state.cadence.callAtUtc,
          localTime: const WallClockTime(8, 0),
        ),
      );
      expect(allowed.wasApplied, isTrue);
      expect(allowed.state.callAttempts, 1);
    });

    test('quiet-hours windows wrap across midnight', () {
      const quiet = QuietHours(
        start: WallClockTime(21, 0),
        end: WallClockTime(8, 0),
      );

      expect(quiet.contains(const WallClockTime(23, 59)), isTrue);
      expect(quiet.contains(const WallClockTime(0, 0)), isTrue);
      expect(quiet.contains(const WallClockTime(7, 59)), isTrue);
      expect(quiet.contains(const WallClockTime(8, 0)), isFalse);
      expect(quiet.contains(const WallClockTime(20, 59)), isFalse);
    });
  });

  group('confirmation safety', () {
    test('answering a call never marks the occurrence taken', () {
      var state = occurrence();
      final call = reducer.reduce(
        state,
        delivery(
          eventId: 'call-trigger',
          kind: ReminderDeliveryKind.reminderCall,
          atUtc: state.cadence.callAtUtc,
          localTime: const WallClockTime(9, 10),
        ),
      );
      state = call.state;

      final answer = reducer.reduce(
        state,
        ReminderCallAnswered(
          eventId: 'provider-answer-webhook',
          occurrenceId: state.id,
          occurredAtUtc: state.cadence.callAtUtc.add(
            const Duration(seconds: 5),
          ),
          callAttemptId: 'call-attempt-1',
        ),
      );

      expect(answer.wasApplied, isTrue);
      expect(answer.state.record.status, RoutineRecordStatus.unconfirmed);
      expect(answer.state.record.confirmedAtUtc, isNull);
      expect(answer.intents, isEmpty);
      expect(answer.state.lastCallAnsweredAtUtc, isNotNull);
    });

    test('vial movement never marks the occurrence taken', () {
      final state = occurrence();
      final movement = reducer.reduce(
        state,
        VialMovementDetected(
          eventId: 'device-signal-1',
          occurrenceId: state.id,
          occurredAtUtc: dueAtUtc.add(const Duration(minutes: 2)),
          deviceId: 'vial-42',
        ),
      );

      expect(movement.wasApplied, isTrue);
      expect(movement.state.record.status, RoutineRecordStatus.unconfirmed);
      expect(movement.state.record.confirmationChannel, isNull);
      expect(movement.intents, isEmpty);
      expect(movement.state.lastVialMovementAtUtc, isNotNull);
    });

    test('only explicit confirmation creates a taken record', () {
      var state = occurrence();
      state = reducer
          .reduce(
            state,
            ReminderCallAnswered(
              eventId: 'answered',
              occurrenceId: state.id,
              occurredAtUtc: dueAtUtc.add(const Duration(minutes: 10)),
              callAttemptId: 'attempt-1',
            ),
          )
          .state;
      state = reducer
          .reduce(
            state,
            VialMovementDetected(
              eventId: 'moved',
              occurrenceId: state.id,
              occurredAtUtc: dueAtUtc.add(const Duration(minutes: 11)),
              deviceId: 'vial-42',
            ),
          )
          .state;
      expect(state.record.status, RoutineRecordStatus.unconfirmed);

      final confirmation = reducer.reduce(
        state,
        DoseTakenExplicitlyConfirmed(
          eventId: 'explicit-confirmation-command',
          occurrenceId: state.id,
          occurredAtUtc: dueAtUtc.add(const Duration(minutes: 12)),
          channel: ExplicitConfirmationChannel.app,
          confirmationId: 'confirmation-screen-submit-1',
        ),
      );

      expect(confirmation.wasApplied, isTrue);
      expect(confirmation.state.record.status, RoutineRecordStatus.taken);
      expect(
        confirmation.state.record.confirmationChannel,
        ExplicitConfirmationChannel.app,
      );
      expect(confirmation.intents.single, isA<CancelReminderIntents>());
    });
  });

  group('snooze and cancel', () {
    test('snooze changes reminder timing but leaves the record unconfirmed', () {
      final state = occurrence();
      final snooze = reducer.reduce(
        state,
        ReminderSnoozed(
          eventId: 'snooze-1',
          occurrenceId: state.id,
          occurredAtUtc: dueAtUtc,
        ),
      );

      expect(snooze.wasApplied, isTrue);
      expect(snooze.state.record.status, RoutineRecordStatus.unconfirmed);
      expect(snooze.state.cadence.dueAtUtc, dueAtUtc);
      expect(
        snooze.state.snoozedUntilUtc,
        dueAtUtc.add(const Duration(minutes: 15)),
      );
      expect(snooze.intents.whereType<CancelReminderIntents>(), hasLength(1));
      expect(snooze.intents.whereType<ScheduleReminderIntent>(), hasLength(1));
      final cancellation =
          snooze.intents.whereType<CancelReminderIntents>().single;
      final scheduled =
          snooze.intents.whereType<ScheduleReminderIntent>().single;
      expect(cancellation.deliveryKeys, isNot(contains(scheduled.deliveryKey)));
    });

    test('snooze suppresses original call and allows one follow-up on time', () {
      final state = occurrence();
      final snoozed = reducer
          .reduce(
            state,
            ReminderSnoozed(
              eventId: 'snooze-1',
              occurrenceId: state.id,
              occurredAtUtc: dueAtUtc,
            ),
          )
          .state;

      final originalCall = reducer.reduce(
        snoozed,
        delivery(
          eventId: 'original-call',
          kind: ReminderDeliveryKind.reminderCall,
          atUtc: snoozed.cadence.callAtUtc,
          localTime: const WallClockTime(9, 10),
        ),
      );
      expect(
        originalCall.rejectionReason,
        ReminderRejectionReason.originalTimelineSnoozed,
      );

      final earlyFollowUp = reducer.reduce(
        snoozed,
        delivery(
          eventId: 'snooze-follow-up',
          kind: ReminderDeliveryKind.snoozeFollowUp,
          atUtc: snoozed.snoozedUntilUtc!.subtract(
            const Duration(seconds: 1),
          ),
          localTime: const WallClockTime(9, 14),
        ),
      );
      expect(
        earlyFollowUp.rejectionReason,
        ReminderRejectionReason.beforeScheduledTime,
      );

      final followUp = reducer.reduce(
        snoozed,
        delivery(
          eventId: 'snooze-follow-up',
          kind: ReminderDeliveryKind.snoozeFollowUp,
          atUtc: snoozed.snoozedUntilUtc!,
          localTime: const WallClockTime(9, 15),
        ),
      );
      expect(followUp.wasApplied, isTrue);
      expect(followUp.state.record.status, RoutineRecordStatus.unconfirmed);
      expect(
        (followUp.intents.single as DeliverReminderIntent).kind,
        ReminderDeliveryKind.snoozeFollowUp,
      );
    });

    test('explicit confirmation clears a pending snooze', () {
      final state = occurrence();
      final snoozed = reducer
          .reduce(
            state,
            ReminderSnoozed(
              eventId: 'snooze-before-confirmation',
              occurrenceId: state.id,
              occurredAtUtc: dueAtUtc,
            ),
          )
          .state;

      final confirmed = reducer.reduce(
        snoozed,
        DoseTakenExplicitlyConfirmed(
          eventId: 'confirm-after-snooze',
          occurrenceId: snoozed.id,
          occurredAtUtc: dueAtUtc.add(const Duration(minutes: 2)),
          channel: ExplicitConfirmationChannel.app,
          confirmationId: 'confirmation-screen-submit-2',
        ),
      );

      expect(confirmed.wasApplied, isTrue);
      expect(confirmed.state.record.status, RoutineRecordStatus.taken);
      expect(confirmed.state.snoozedUntilUtc, isNull);
      expect(confirmed.state.isSnoozed, isFalse);
    });

    test('rejects zero, negative, and excessive snooze durations', () {
      final state = occurrence();
      for (final duration in <Duration>[
        Duration.zero,
        const Duration(minutes: -1),
        const Duration(hours: 25),
      ]) {
        final result = reducer.reduce(
          state,
          ReminderSnoozed(
            eventId: 'invalid-${duration.inMinutes}',
            occurrenceId: state.id,
            occurredAtUtc: dueAtUtc,
            snoozeFor: duration,
          ),
        );
        expect(
          result.rejectionReason,
          ReminderRejectionReason.invalidSnoozeDuration,
        );
        expect(result.state.revision, 0);
      }
    });

    test('cancel stops reminders without claiming the dose was taken', () {
      final state = occurrence();
      final event = OccurrenceRemindersCancelled(
        eventId: 'cancel-reminders',
        occurrenceId: state.id,
        occurredAtUtc: dueAtUtc.subtract(const Duration(minutes: 30)),
      );
      final cancelled = reducer.reduce(state, event);

      expect(cancelled.wasApplied, isTrue);
      expect(cancelled.state.remindersCancelled, isTrue);
      expect(cancelled.state.record.status, RoutineRecordStatus.unconfirmed);
      expect(cancelled.intents.single, isA<CancelReminderIntents>());

      final attemptedDelivery = reducer.reduce(
        cancelled.state,
        delivery(
          eventId: 'due-after-cancel',
          kind: ReminderDeliveryKind.due,
          atUtc: dueAtUtc,
        ),
      );
      expect(
        attemptedDelivery.rejectionReason,
        ReminderRejectionReason.occurrenceCancelled,
      );
    });
  });

  group('idempotency', () {
    test('replaying an applied event produces no new revision or intent', () {
      final state = occurrence();
      final event = delivery(
        eventId: 'due-trigger',
        kind: ReminderDeliveryKind.due,
        atUtc: dueAtUtc,
      );
      final first = reducer.reduce(state, event);
      final replay = reducer.reduce(first.state, event);

      expect(first.wasApplied, isTrue);
      expect(replay.wasDuplicate, isTrue);
      expect(replay.state.revision, first.state.revision);
      expect(replay.intents, isEmpty);
      expect(replay.state.auditTrail, hasLength(1));
    });

    test('a new event ID still cannot dispatch the same milestone twice', () {
      final state = occurrence();
      final first = reducer.reduce(
        state,
        delivery(
          eventId: 'due-trigger-1',
          kind: ReminderDeliveryKind.due,
          atUtc: dueAtUtc,
        ),
      );
      final second = reducer.reduce(
        first.state,
        delivery(
          eventId: 'due-trigger-2',
          kind: ReminderDeliveryKind.due,
          atUtc: dueAtUtc.add(const Duration(seconds: 1)),
        ),
      );

      expect(second.status, ReminderTransitionStatus.rejected);
      expect(second.rejectionReason, ReminderRejectionReason.alreadyDispatched);
      expect(second.intents, isEmpty);
      expect(second.state.revision, first.state.revision);
    });

    test('replaying explicit confirmation cannot create duplicate cancellation', () {
      final state = occurrence();
      final event = DoseTakenExplicitlyConfirmed(
        eventId: 'confirm-1',
        occurrenceId: state.id,
        occurredAtUtc: dueAtUtc,
        channel: ExplicitConfirmationChannel.authenticatedPhoneCheckIn,
        confirmationId: 'phone-confirmation-1',
      );
      final first = reducer.reduce(state, event);
      final replay = reducer.reduce(first.state, event);

      expect(first.intents, hasLength(1));
      expect(replay.wasDuplicate, isTrue);
      expect(replay.intents, isEmpty);
      expect(replay.state.record.confirmationId, 'phone-confirmation-1');
    });
  });
}
