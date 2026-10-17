import 'dart:async';

import 'package:farda/services/consumer_live_activity_coordinator.dart';
import 'package:farda/services/live_activity_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('farda/live_activity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final due = DateTime.utc(2026, 10, 15, 9);
  final calls = <MethodCall>[];

  LiveRoutineActivity activity({
    DateTime? dueAt,
    int revision = 1,
    DateTime? snoozedUntil,
  }) => LiveRoutineActivity(
    occurrenceId: 'dose-123',
    dueAt: dueAt ?? due,
    windowEndsAt: (dueAt ?? due).add(const Duration(hours: 1)),
    updatedAt: due.subtract(const Duration(minutes: 30)),
    revision: revision,
    phase: LiveRoutinePhase.headsUp,
    callAt: due.add(const Duration(minutes: 10)),
    snoozedUntil: snoozedUntil,
  );

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'availability':
          return {
            'supported': true,
            'enabled': true,
            'backgroundDeliveryConfigured': false,
          };
        case 'activeActivities':
          return [];
        default:
          return {'status': 'updated'};
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'before and due share an opaque occurrence and private numeric payload',
    () async {
      final service = LiveActivityService(isIOS: true);
      await service.upsert(
        activity().at(due.subtract(const Duration(minutes: 10))),
      );
      await service.upsert(activity().at(due));
      final before = calls[0].arguments as Map;
      final active = calls[1].arguments as Map;
      expect(before['occurrenceId'], active['occurrenceId']);
      expect(before['phase'], 'headsUp');
      expect(active['phase'], 'due');
      expect(active['dueAt'], due.millisecondsSinceEpoch);
      expect(active.keys.toSet(), {
        'occurrenceId',
        'dueAt',
        'windowEndsAt',
        'updatedAt',
        'revision',
        'phase',
        'callAt',
        'requestPushToken',
      });
      expect(active['requestPushToken'], false);
    },
  );

  test('reminder window starts ten minutes before and excludes its end', () {
    final entry = activity();
    expect(
      entry.isVisibleAt(
        due.subtract(const Duration(minutes: 10, milliseconds: 1)),
      ),
      false,
    );
    expect(entry.isVisibleAt(due.subtract(const Duration(minutes: 10))), true);
    expect(entry.isVisibleAt(due), true);
    expect(entry.isVisibleAt(due.add(const Duration(hours: 1))), false);
  });

  test('snooze suppresses call display and returns to due when it expires', () {
    final entry = activity(snoozedUntil: due.add(const Duration(minutes: 15)));
    expect(entry.at(due).toMap()['phase'], 'snoozed');
    expect(entry.at(due).toMap().containsKey('callAt'), false);
    expect(
      entry.at(due.add(const Duration(minutes: 15))).phase,
      LiveRoutinePhase.due,
    );
    expect(entry.at(due.add(const Duration(minutes: 15))).callAt, isNull);
  });

  test(
    'rejects malformed identifiers, long windows and out-of-window call times',
    () {
      LiveRoutineActivity invalid({
        String id = 'dose-123',
        Duration duration = const Duration(hours: 1),
        DateTime? callAt,
      }) => LiveRoutineActivity(
        occurrenceId: id,
        dueAt: due,
        windowEndsAt: due.add(duration),
        updatedAt: due,
        revision: 0,
        phase: LiveRoutinePhase.due,
        callAt: callAt,
      );
      expect(() => invalid(id: 'x/../../record').toMap(), throwsArgumentError);
      expect(
        () => invalid(duration: const Duration(hours: 8)).toMap(),
        throwsArgumentError,
      );
      expect(
        () => invalid(callAt: due.subtract(const Duration(seconds: 1))).toMap(),
        throwsArgumentError,
      );
    },
  );

  test(
    'unsupported platforms return unavailable without channel invocation',
    () async {
      final service = LiveActivityService(isIOS: false);
      expect((await service.availability()).supported, false);
      expect(await service.upsert(activity()), {'status': 'unsupported'});
      expect(await service.activeActivities(), isEmpty);
      await service.endAll();
      expect(calls, isEmpty);
    },
  );

  test(
    'native permission denial is observable, not represented as successful display',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {'supported': true, 'enabled': false},
      );
      final value = await LiveActivityService(isIOS: true).availability();
      expect(value.supported, true);
      expect(value.enabled, false);
      expect(value.backgroundDeliveryConfigured, false);
    },
  );

  test(
    'explicit terminal update only calls display end, never a record API',
    () async {
      await LiveActivityService(
        isIOS: true,
      ).end('dose-123', outcome: LiveRoutineOutcome.confirmed, revision: 2);
      expect(calls.single.method, 'end');
      expect(calls.single.arguments, {
        'occurrenceId': 'dose-123',
        'outcome': 'confirmed',
        'revision': 2,
      });
    },
  );

  test('tokens do not appear in event diagnostics', () {
    final event = LiveActivityEvent({
      'type': 'pushToken',
      'token': 'secret-token',
    });
    expect(event.token, 'secret-token');
    expect(event.toString(), isNot(contains('secret-token')));
  });

  testWidgets('enabling requests token re-emission without returning a token', (
    tester,
  ) async {
    final coordinator = ConsumerLiveActivityCoordinator(
      service: LiveActivityService(isIOS: true),
      onOpenRoutine: (_, __) {},
      clock: () => due,
    );
    await coordinator.reconcile(occurrences: [activity()], enabled: true);
    expect(calls.first.method, 'refreshTokens');
    expect(calls.first.arguments, isNull);
    await coordinator.dispose();
  });

  testWidgets(
    'foreground boundary produces heads-up then due for the same record',
    (tester) async {
      var now = due.subtract(const Duration(minutes: 10, seconds: 1));
      final coordinator = ConsumerLiveActivityCoordinator(
        service: LiveActivityService(isIOS: true),
        onOpenRoutine: (_, __) {},
        clock: () => now,
      );
      await coordinator.reconcile(occurrences: [activity()], enabled: true);
      expect(calls.where((call) => call.method == 'upsert'), isEmpty);
      now = due.subtract(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));
      expect((calls.last.arguments as Map)['phase'], 'headsUp');
      now = due;
      await tester.pump(const Duration(minutes: 10));
      expect((calls.last.arguments as Map)['phase'], 'due');
      expect((calls.last.arguments as Map)['occurrenceId'], 'dose-123');
      await coordinator.dispose();
    },
  );

  testWidgets('a successful empty snapshot ends an orphaned activity', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'availability') {
        return {'supported': true, 'enabled': true};
      }
      if (call.method == 'activeActivities') {
        return [
          {
            'activityId': 'native-1',
            'occurrenceId': 'old-dose',
            'revision': 4,
            'state': 'active',
          },
        ];
      }
      return {'status': 'ended'};
    });
    final coordinator = ConsumerLiveActivityCoordinator(
      service: LiveActivityService(isIOS: true),
      onOpenRoutine: (_, __) {},
    );
    await coordinator.reconcile(occurrences: [], enabled: true);
    expect(calls.last.method, 'end');
    expect((calls.last.arguments as Map)['outcome'], 'cancelled');
    await coordinator.dispose();
  });

  testWidgets('disabling ends all activities and schedules no future starts', (
    tester,
  ) async {
    final coordinator = ConsumerLiveActivityCoordinator(
      service: LiveActivityService(isIOS: true),
      onOpenRoutine: (_, __) {},
      clock: () => due,
    );
    await coordinator.reconcile(occurrences: [activity()], enabled: false);
    expect(calls.last.method, 'endAll');
    await tester.pump(const Duration(minutes: 20));
    expect(calls.where((call) => call.method == 'upsert'), isEmpty);
    await coordinator.dispose();
  });

  testWidgets('confirmation waits for an in-flight update then ends once', (
    tester,
  ) async {
    final started = Completer<void>();
    final release = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'availability') {
        return {'supported': true, 'enabled': true};
      }
      if (call.method == 'activeActivities') return [];
      if (call.method == 'upsert') {
        started.complete();
        await release.future;
      }
      return {'status': 'updated'};
    });
    final coordinator = ConsumerLiveActivityCoordinator(
      service: LiveActivityService(isIOS: true),
      onOpenRoutine: (_, __) {},
      clock: () => due,
    );
    final sync = coordinator.reconcile(
      occurrences: [activity()],
      enabled: true,
    );
    await started.future;
    final resolution = coordinator.resolve(
      'dose-123',
      outcome: LiveRoutineOutcome.confirmed,
      revision: 2,
    );
    release.complete();
    await sync;
    await resolution;
    expect(
      calls
          .where((call) => ['upsert', 'end'].contains(call.method))
          .map((call) => call.method),
      ['upsert', 'end'],
    );
    await coordinator.dispose();
  });
}
